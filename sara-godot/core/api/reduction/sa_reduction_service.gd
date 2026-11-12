## The one reduction service: runs the graph docker's pass and the stats
## docker's numbers on one schedule, and nothing while neither docker is open.
##
## **A service and not a docker's own poll.** One reduction service under both
## dockers, at the graph docker's per-frame pace while that docker is open and
## on the idle clock otherwise, so neither docker depends on the other: the
## stats docker registers its numbers here rather than asking the graph docker.
##
## **What registers.** A [SaReductionService.Reduction], added with [method add]
## and taken off with [method leave]. A docker adds its reductions while it is
## open and takes them off when it closes, so a closed docker costs nothing:
## with nothing registered the service stops processing and dispatches nothing.
##
## **The two paces.** While a reduction that sets the pace is registered, the
## graph docker's pass, the service decides every frame. It runs when the easel
## composited, its output was replaced,
## the view moved, a reduction's own shape changed or a reduction asked, and
## while only the paint moved it waits `PAINT_INTERVAL_MSEC` between runs.
## Every registered reduction runs on that decision. While none sets the pace,
## the service runs them once each time the idle clock says the painter has
## stopped, and it never looks at a frame.
##
## **A reduction over the document** is a [SaReductionService.OverDocument],
## which dispatches over the painted chunks that changed since its last run,
## folds their tallies into its total and has the tally handed back on a later
## frame rather than waiting for the device, so no frame stalls on a read back
## and nothing the stroke did not touch is dispatched.
##
## **It follows the main canvas and nobody wires it.** The service is an
## autoload, `SaReductions`, which each frame it processes reads the canvas the
## main scene shows by name, as `SaIdleClock` reads its document, and which
## listens to `SaIdle`, the one idle clock. A suite builds one of its own, hands
## it an easel and a clock, and drives both with [method tick] and the clock's.
class_name SaReductionService
extends Node

## The least time between two runs while the only thing that moved is the
## paint, in milliseconds. The graph's pass takes a sample per shown pixel,
## too dear to pay every frame of a stroke, so it runs less often rather than
## reading less: a stroke is reduced fifteen times a second and the run after
## the last composite always comes. A moved view or a resized panel is never
## held back.
const PAINT_INTERVAL_MSEC := 66


## One pass the service runs, a docker's, registered while that docker is open.
##
## The graph docker's pass is one of these made of two callables, and a number
## over the document is an [SaReductionService.OverDocument], which overrides
## [method _reduce]. Either way the service calls [method run] and nothing else.
class Reduction:
    extends RefCounted

    ## Whether this reduction sets the per-frame pace while it is registered.
    ## The graph docker's pass does, and a number of the stats docker does not.
    var sets_pace: bool = false
    ## How many times the service has run it, and when last, by
    ## `Time.get_ticks_msec`, -1 before the first.
    var runs: int = 0
    var ran_msec: int = -1
    ## Whether it asked for a run of its own, as a graph switched to another
    ## mode does. Set by [method stale] and cleared by [method run].
    var asked: bool = false

    var _pass: Callable
    var _shape: Callable

    ## *paced* says whether it sets the pace. *each_run* is called with the
    ## easel at each run, and *shape_of* answers what of the reduction's own the
    ## per-frame decision watches beside the paint and the view, the graph's
    ## panel size.
    func _init(paced: bool = false, each_run: Callable = Callable(), shape_of: Callable = Callable()) -> void:
        sets_pace = paced
        _pass = each_run
        _shape = shape_of

    ## Asks for a run on the next frame the service decides, whatever moved.
    func stale() -> void:
        asked = true

    ## What the decision compares between frames, null when nothing.
    func shape() -> Variant:
        return _shape.call() if _shape.is_valid() else null

    ## One run, at *now_msec*, over *easel*. Called by the service alone.
    func run(easel: SaEasel, now_msec: int) -> void:
        asked = false
        runs += 1
        ran_msec = now_msec
        _reduce(easel)

    ## Taken off the service: whatever it was following, it stops following.
    func let_go() -> void:
        pass

    ## What a run does. The base calls its callable and a subclass overrides it.
    func _reduce(easel: SaEasel) -> void:
        if _pass.is_valid():
            _pass.call(easel)


## A reduction over the composite of the document, chunk by chunk.
##
## The kernel, a shader of `shaders/compute/` named in the constructor, reads
## the composite at binding 0 as a storage image and adds into the tally at
## binding 1, `cells` uints a slot and one slot a chunk, from a push constant
## the constructor's callable packs for each chunk,
## `func(rect: Rect2i, slot: int, document: SaDocument) -> PackedFloat32Array`,
## *rect* being the chunk's share of the canvas in document pixels. A slot
## holds one chunk, so a sum never overflows a uint, the bound `measure.gmacs`
## writes down, and that kernel keeps the same contract.
##
## **Only what changed.** The first run, and the first after the document or
## the composite's texture was replaced, dispatches over every painted chunk.
## Every run after it dispatches over the chunks the document announced since,
## and a chunk nothing paints any longer leaves the total with no dispatch.
## What is pending and what the backlog holds is composited first, so the
## reduction reads the picture and not what the window last showed.
##
## **Folded, not summed again.** Each chunk's tally is kept, and a chunk read
## again takes its old tally out of [member total] before its new one goes in,
## so the total of a hundred chunks costs the handful that changed. The sums
## are whole numbers in 64 bits, so a fold never drifts.
##
## **The tally comes back on a later frame.** `buffer_get_data_async` hands the
## bytes back once the frame the ask went into comes round, so no frame waits
## on the device, and [signal folded] says the total moved. Only the main
## device answers that way, so a run on another reads at once, as does a run
## with [member read_at_once]. An answer older than a later ask for the same
## chunk is not folded, so the total is never set back.
class OverDocument:
    extends Reduction

    ## The total moved: an answer was folded in or a chunk left it.
    signal folded

    ## The tally of every painted chunk, `cells` sums.
    var total: PackedInt64Array = PackedInt64Array()
    ## The chunks the last run dispatched over, in slot order.
    var dispatched: Array[Vector2i] = []
    ## When the total last moved, by `Time.get_ticks_msec`, -1 before.
    var folded_msec: int = -1
    ## Asks the device has not answered yet.
    var waiting: int = 0
    ## Reads the tally back at once rather than on a later frame. Off in the
    ## app, and on in a suite that wants the total before its next line.
    var read_at_once: bool = false

    var _shader: String
    var _kernel: String
    var _cells: int
    var _push: Callable
    ## Built on the first run, so a reduction never run allocates no pipeline.
    var _compute: SaCompute = null
    ## What the tallies are of: a document and the composite's texture.
    var _document: SaDocument = null
    var _output: RID = RID()
    ## The chunks announced since the last run, read at the next.
    var _changed: Dictionary[Vector2i, bool] = {}
    ## Each chunk's own tally, which a fold takes out of the total again.
    var _tallies: Dictionary[Vector2i, PackedInt64Array] = {}
    ## The ask that last read or dropped each chunk, the one answer folded in.
    var _latest: Dictionary[Vector2i, int] = {}
    var _asks: int = 0
    ## Each tally the device still owes an answer for, by its ask, kept here
    ## rather than in the callable the device holds.
    var _owed: Dictionary[int, SaCompute.Buffer] = {}

    func _init(shader: String, kernel: String, cells: int, push: Callable) -> void:
        super(false)
        _shader = shader
        _kernel = kernel
        _cells = cells
        _push = push
        total.resize(cells)
        total.fill(0)

    ## Stops hearing the document and forgets every tally, so the next run
    ## starts again from every painted chunk.
    func let_go() -> void:
        _follow(null)
        _document = null
        _output = RID()

    func _reduce(easel: SaEasel) -> void:
        dispatched = []
        if easel == null or easel.document == null or easel.output == null or not easel.output.rid.is_valid():
            return
        if easel.document != _document or easel.output.rid != _output:
            _start_over(easel)
        _asks += 1
        var ask := _asks
        var canvas := Rect2i(Vector2i.ZERO, _document.canvas_size)
        var layers := SaLayerStack.layers(_document)
        var everywhere := SaGeneratedLayer.any_in(_document)
        var reading: Array[Vector2i] = []
        var dropped := false
        for grid_pos: Vector2i in _changed:
            _latest[grid_pos] = ask
            if not canvas.intersects(_chunk_rect(grid_pos)) or not (everywhere or _held(layers, grid_pos)):
                dropped = _take_out(grid_pos) or dropped
                continue
            reading.append(grid_pos)
        _changed.clear()
        if dropped:
            _moved()
        if reading.is_empty():
            return
        easel.flush()
        var tally := SaCompute.Buffer.new(_zeroed(reading.size() * _cells))
        if not tally.rid.is_valid() or not _dispatch(easel.output, tally, reading, canvas):
            return
        dispatched = reading
        _ask(ask, reading, tally)

    ## The tally of the chunks *reading* names, slot by slot, out of *bytes*,
    ## folded into the total in place of each chunk's last. Called by the
    ## device's answer, or at once.
    func heard(ask: int, reading: Array[Vector2i], bytes: PackedByteArray) -> void:
        var cells := bytes.to_int32_array()
        var moved := false
        for slot in reading.size():
            var grid_pos := reading[slot]
            var latest: int = _latest.get(grid_pos, -1)
            if latest != ask:
                continue
            var tally := PackedInt64Array()
            tally.resize(_cells)
            for cell in _cells:
                var at := slot * _cells + cell
                var raw := cells[at] if at < cells.size() else 0
                # A uint whose top bit is set reads as a negative int32.
                tally[cell] = raw if raw >= 0 else raw + 4294967296
            _take_out(grid_pos)
            for cell in _cells:
                total[cell] += tally[cell]
            _tallies[grid_pos] = tally
            moved = true
        if moved:
            _moved()

    ## Every painted chunk of *easel*'s document waits for the next run, and
    ## nothing is kept of the last document's.
    func _start_over(easel: SaEasel) -> void:
        _follow(easel.document)
        _document = easel.document
        _output = easel.output.rid
        _tallies.clear()
        _latest.clear()
        total.fill(0)
        _changed.clear()
        for layer: SaLayer in SaLayerStack.layers(_document):
            for grid_pos: Vector2i in layer.chunks:
                _changed[grid_pos] = true
        for grid_pos: Vector2i in SaGeneratedLayer.covered_positions(_document):
            _changed[grid_pos] = true

    func _follow(document: SaDocument) -> void:
        if is_instance_valid(_document) and _document.chunks_invalidated.is_connected(_on_chunks_invalidated):
            _document.chunks_invalidated.disconnect(_on_chunks_invalidated)
        if document != null and not document.chunks_invalidated.is_connected(_on_chunks_invalidated):
            document.chunks_invalidated.connect(_on_chunks_invalidated)
        _changed.clear()
        _tallies.clear()
        _latest.clear()

    func _on_chunks_invalidated(grid_positions: Array) -> void:
        for grid_pos: Vector2i in grid_positions:
            _changed[grid_pos] = true

    ## One compute list, a dispatch a chunk over its share of the canvas, the
    ## counts adding atomically into each chunk's own slot.
    func _dispatch(output: SaTexture, tally: SaCompute.Buffer, reading: Array[Vector2i], canvas: Rect2i) -> bool:
        if _compute == null:
            _compute = SaCompute.new(_shader)
        var kernel := _compute.index_of_kernel(_kernel)
        if kernel < 0:
            push_error("SaReductionService: %s has no kernel %s" % [_shader, _kernel])
            return false
        _compute.use_storage_format(output.format)
        _compute.set_texture(0, output.rid)
        _compute.set_buffer(1, tally.rid)
        _compute.list_begin(kernel)
        for slot in reading.size():
            var rect := _chunk_rect(reading[slot]).intersection(canvas)
            var params: PackedFloat32Array = _push.call(rect, slot, _document)
            _compute.set_push_constant_float_array(params)
            _compute.list_dispatch(SaCompute.groups_for(rect.size.x), SaCompute.groups_for(rect.size.y), 1)
        _compute.list_end()
        return true

    ## Hands the tally back on a later frame, or at once off the main device.
    func _ask(ask: int, reading: Array[Vector2i], tally: SaCompute.Buffer) -> void:
        var rd := tally.rd
        if read_at_once or rd != RenderingServer.get_rendering_device():
            heard(ask, reading, tally.read())
            return
        waiting += 1
        _owed[ask] = tally
        if rd.buffer_get_data_async(tally.rid, _tally_back.bind(ask, reading)) != OK:
            _owed.erase(ask)
            waiting -= 1
            heard(ask, reading, tally.read())

    ## The device's answer to the ask numbered *ask*. A method with plain values
    ## bound and never a lambda or the tally, which `SaExport.ask_texture_bytes`
    ## says why: the method holds the reduction by its id alone, so one let go
    ## meanwhile is not kept for it. *tally* waits in `_owed` until the answer
    ## comes, and a reduction let go takes it along, which cuts no read short
    ## because the device frees a buffer only once the frames using it are done.
    func _tally_back(bytes: PackedByteArray, ask: int, reading: Array[Vector2i]) -> void:
        var tally: SaCompute.Buffer = _owed.get(ask)
        _owed.erase(ask)
        waiting -= 1
        if tally != null and bytes.size() == tally.size:
            heard(ask, reading, bytes)

    ## Takes *grid_pos*'s tally out of the total, and says whether there was one.
    func _take_out(grid_pos: Vector2i) -> bool:
        var old: PackedInt64Array = _tallies.get(grid_pos, PackedInt64Array())
        if old.is_empty():
            return false
        for cell in _cells:
            total[cell] -= old[cell]
        _tallies.erase(grid_pos)
        return true

    func _moved() -> void:
        folded_msec = Time.get_ticks_msec()
        folded.emit()

    ## The document pixels the chunk at *grid_pos* covers. The composite is at
    ## document density whatever a layer's chunks are stored at, so this is the
    ## grid the document invalidates on and not a chunk's own `pixel_size()`.
    static func _chunk_rect(grid_pos: Vector2i) -> Rect2i:
        return Rect2i(grid_pos * SaLayer.CHUNK_SIZE, Vector2i.ONE * SaLayer.CHUNK_SIZE)

    static func _held(layers: Array[SaLayer], grid_pos: Vector2i) -> bool:
        for layer: SaLayer in layers:
            if layer.chunks.has(grid_pos):
                return true
        return false

    static func _zeroed(cells: int) -> PackedByteArray:
        var zeros := PackedInt32Array()
        zeros.resize(cells)
        zeros.fill(0)
        return zeros.to_byte_array()


## Whether the service follows the canvas the main scene shows. A suite turns
## it off and hands its own easel to [method watch].
var follow_main: bool = true

## The canvas the service decides by, whose view the graph samples, or null.
var canvas: SaCanvas = null

## What is registered, in the order it was added.
var reductions: Array[Reduction] = []

## How many times the service ran its reductions, at either pace.
var passes: int = 0

## The easel a suite handed in, read when there is no canvas.
var _easel: SaEasel = null
var _clock: SaIdleClock = null

## The easel's composite count and output, the view, the reductions' shapes
## and the time at the last run, which together say whether there is anything
## new to reduce.
var _seen_composites: int = -1
var _seen_output: RID = RID()
var _seen_mapping: PackedFloat32Array = PackedFloat32Array()
var _seen_shapes: Array = []
var _passed_at_msec: int = -PAINT_INTERVAL_MSEC


func _init() -> void:
    SaBootMarks.mark(&"reductions_init")
    name = "SaReductionService"
    set_process(false)


func _ready() -> void:
    var clock := get_node_or_null(^"/root/SaIdle") as SaIdleClock
    if clock != null:
        listen(clock)
    # The engine turns processing on at ready for a script with `_process`, so
    # it is put back to what is registered.
    set_process(not reductions.is_empty())


func _process(_delta: float) -> void:
    if follow_main:
        _follow_main_canvas()
    tick(Time.get_ticks_msec())


## The service the app runs, the autoload `SaReductions`, found from the root
## so a docker outside the tree can still ask, or null in a run without it.
static func shared() -> SaReductionService:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null or tree.root == null:
        return null
    return tree.root.get_node_or_null(^"SaReductions") as SaReductionService


## Registers *reduction*, which runs at the next decision.
func add(reduction: Reduction) -> void:
    if reduction == null or reductions.has(reduction):
        return
    reductions.append(reduction)
    # A docker opened again shows what was painted while it was closed.
    reduction.stale()
    set_process(true)


## Takes *reduction* off. With nothing left the service stops processing.
func leave(reduction: Reduction) -> void:
    if not reductions.has(reduction):
        return
    reductions.erase(reduction)
    reduction.let_go()
    set_process(not reductions.is_empty())


## Whether *reduction* is registered.
func holds(reduction: Reduction) -> bool:
    return reductions.has(reduction)


## Whether a registered reduction sets the per-frame pace.
func paced() -> bool:
    for reduction: Reduction in reductions:
        if reduction.sets_pace:
            return true
    return false


## Hears *clock*'s [signal SaIdleClock.stopped] in place of any clock before.
func listen(clock: SaIdleClock) -> void:
    if is_instance_valid(_clock) and _clock.stopped.is_connected(_on_stopped):
        _clock.stopped.disconnect(_on_stopped)
    _clock = clock
    if clock != null and not clock.stopped.is_connected(_on_stopped):
        clock.stopped.connect(_on_stopped)


## Decides by *easel* rather than a canvas, for a suite with no view.
func watch(easel: SaEasel) -> void:
    follow_main = false
    canvas = null
    _easel = easel


## One frame of the per-frame pace at *now_msec*, and whether it ran. Nothing
## while no registered reduction sets the pace.
func tick(now_msec: int) -> bool:
    if not paced():
        return false
    var easel := _current_easel()
    if easel == null or easel.output == null or easel.document == null:
        return false
    var mapping := view_of(canvas, easel.document.canvas_size)
    var shapes: Array = []
    var asked := false
    for reduction: Reduction in reductions:
        shapes.append(reduction.shape())
        asked = asked or reduction.asked
    var same_frame := easel.output.rid == _seen_output and mapping == _seen_mapping and shapes == _seen_shapes
    if same_frame and easel.composite_count == _seen_composites and not asked:
        return false
    # Left as it was when held back, so a later frame still sees the change and
    # the last composite of a stroke is always reduced. A reduction that asked,
    # a graph switched to another mode, is a click and is never held back.
    if not pass_due(same_frame and not asked, now_msec, _passed_at_msec):
        return false
    _seen_output = easel.output.rid
    _seen_mapping = mapping
    _seen_shapes = shapes
    _passed_at_msec = now_msec
    _run_all(easel, now_msec)
    # After the run, which composited what was pending, so that composite is
    # not taken for new paint on the next frame.
    _seen_composites = easel.composite_count
    return true


## Whether a run comes now, at *now_msec* with the last at *last_msec*: at
## once for anything but paint, and for paint once `PAINT_INTERVAL_MSEC` has
## gone by.
static func pass_due(only_paint: bool, now_msec: int, last_msec: int) -> bool:
    return not only_paint or now_msec - last_msec >= PAINT_INTERVAL_MSEC


## The parallelogram of the document *view_canvas*'s screen shows, as origin,
## the vector along the screen's x axis and the vector along its y axis.
##
## Read off the view by three probes rather than out of its internals: the
## transform is affine, so a corner and two edges describe all of it, including
## a rotation. A canvas without a view falls back to the whole document, which
## is what a suite and a docker built before the canvas exists both have.
static func view_of(view_canvas: SaCanvas, canvas_size: Vector2i) -> PackedFloat32Array:
    var whole := PackedFloat32Array([0.0, 0.0, float(canvas_size.x), 0.0, 0.0, float(canvas_size.y)])
    if view_canvas == null or not is_instance_valid(view_canvas):
        return whole
    var view := SaCanvasView.for_canvas(view_canvas)
    if view == null:
        return whole
    var viewport := view.get_viewport_size()
    if viewport.x <= 0.0 or viewport.y <= 0.0:
        return whole
    var origin := view.screen_to_document(Vector2.ZERO)
    var along_x := view.screen_to_document(Vector2(viewport.x, 0.0)) - origin
    var along_y := view.screen_to_document(Vector2(0.0, viewport.y)) - origin
    return PackedFloat32Array([origin.x, origin.y, along_x.x, along_x.y, along_y.x, along_y.y])


## What the service holds and has done, for the graph docker's part of the
## state dump.
func report() -> Dictionary:
    return {"registered": reductions.size(), "paced": paced(), "passes": passes, "processing": is_processing()}


## The idle clock said the painter has stopped: every reduction runs once,
## unless the per-frame pace has been running them all along.
func _on_stopped() -> void:
    if reductions.is_empty() or paced():
        return
    var easel := _current_easel()
    if easel == null or easel.output == null or easel.document == null:
        return
    _run_all(easel, Time.get_ticks_msec())


## Every reduction once, over the picture as it stands: what was invalidated
## and not composited yet goes in first, as the easel would on its own frame,
## or a reduction over the changed chunks would read them as they were and
## never be told of them again.
func _run_all(easel: SaEasel, now_msec: int) -> void:
    passes += 1
    easel.process_pending_composite()
    for reduction: Reduction in reductions.duplicate():
        reduction.run(easel, now_msec)


func _current_easel() -> SaEasel:
    if canvas != null and is_instance_valid(canvas):
        return canvas.easel
    return _easel


## Follows the canvas the main scene shows, by name, since the main scene names
## no service and the service no main scene.
func _follow_main_canvas() -> void:
    var tree := get_tree()
    var main_node: Node = tree.current_scene if tree != null else null
    if main_node == null or not ("main_canvas" in main_node):
        return
    var surface: Object = main_node.get(&"main_canvas")
    if surface == null or not ("canvas" in surface):
        return
    var shown: SaCanvas = surface.get(&"canvas")
    if shown != null and shown != canvas:
        canvas = shown
