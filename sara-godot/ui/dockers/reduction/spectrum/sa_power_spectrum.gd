## The Fourier spectrogram's numbers: the composite's Oklab lightness,
## transformed on the GPU into its power spectrum, and that spectrum's radial
## average, once the painter has stopped.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **What it keeps.** [member power] holds the power of every coefficient of
## the half spectrum NumPy's `rfft2` answers, [member side] rows of
## `side / 2 + 1`, and [member radial] its mean over each ring of one frequency,
## from the zero outwards. The power is `|X / N²|²`, so a flat picture of
## lightness L reads L² at the zero frequency and nothing anywhere else,
## whatever N is. [method power_at] reads the whole spectrum through its
## mirror, and [method period_of] says which scale in document pixels a ring
## stands for.
##
## **Over what.** A square N texels a side, N the largest power of two that is
## neither above the canvas's longer side nor above [member largest], laid
## centred over the canvas. Each texel is the mean lightness of the composite
## texels whose centres it covers, a box filter over the whole picture, and the
## square keeps one scale on both axes so that a ring is one scale. Past the
## canvas on its shorter side the picture is reflected, which keeps a flat
## picture flat where a pad of black would put two edges into it. The kernels
## are `power_spectrum.gmacs` beside this file, which says how the transform
## runs.
##
## **When.** On the idle clock and only on it, "nothing computes
## while the painter paints". A run while the clock has not said the painter
## stopped, or with a stroke open, does nothing, and so does a run over the
## picture the last transform already read. So this sits on the service beside
## the graph docker's pass, which sets the per-frame pace and has every
## reduction run on each frame something moved, and still transforms once a
## stop. Under that pace the service runs nothing when the clock fires, so this
## asks for a run itself, and under the idle pace the service's own run is the
## one. [member runs] counts the service's calls and [member transforms] the
## transforms.
##
## **What comes back.** One buffer of floats, the power spectrum and then the
## radial average, handed back on a later frame by `buffer_get_data_async` the
## way [SaReductionService.OverDocument]'s tally is, or at once with
## [member read_at_once]. The canvas and every texture of the transform stay in
## VRAM. The main device answers only as a frame is drawn, and the
## app draws none while nothing on screen moves, which is when this runs, so
## [method draw_while_owed] draws the frames the answer waits for.
class_name SaPowerSpectrum
extends SaReductionService.Reduction

## A transform's answer came back and [member power] and [member radial] hold it.
signal arrived

## The side the square is held to unless the constructor says otherwise. A
## quarter of a megabyte of half spectrum, and about the
## size a docker draws the spectrum at.
const LARGEST := 256

## Below this the square is too small to say anything, and a canvas whose
## longer side is shorter than it is not transformed.
const SMALLEST := 4

## The kernels, `power_spectrum.gmacs` beside this file.
const SHADER := "power_spectrum"

## The largest side the square may take, a power of two.
var largest: int = LARGEST

## N of the spectrum held, 0 before the first answer.
var side: int = 0

## How many document pixels a texel of that square spans, so ring r is a
## period of `side * document_pixels_per_texel / r` document pixels.
var document_pixels_per_texel: float = 0.0

## The power of the half spectrum, `side` rows of `side / 2 + 1`, the zero
## frequency first in each.
var power: PackedFloat32Array = PackedFloat32Array()

## The mean power of each ring, `side / 2 + 1` of them from the zero frequency.
var radial: PackedFloat32Array = PackedFloat32Array()

## How many transforms this has dispatched, and when the last went, by
## `Time.get_ticks_msec`, -1 before the first.
var transforms: int = 0
var transformed_msec: int = -1

## When the last answer came back, -1 before the first.
var arrived_msec: int = -1

## Asks the device has not answered yet.
var waiting: int = 0
## The frames the engine had drawn when [method draw_while_owed] last looked.
var _drawn_seen: int = -1

## Reads the answer back at once rather than on a later frame. Off in the app,
## and on in a suite that wants the spectrum before its next line.
var read_at_once: bool = false

## The clock the constructor was handed, or null for the app's own, `SaIdle`.
var _given_clock: SaIdleClock = null
## The clock whose [signal SaIdleClock.stopped] this hears, and the document
## whose edits it counts.
var _heard_clock: SaIdleClock = null
var _document: SaDocument = null
## Edits the document announced since this started following it.
var _edits: int = 0
## What the last transform read: the document, the composite's texture, the
## history's position and the edits, which together say whether the picture can
## have changed since.
var _transformed: Array = []
var _asks: int = 0
## Each result the device still owes an answer for, by its ask, kept here
## rather than in the callable the device holds.
var _owed: Dictionary[int, SaCompute.Buffer] = {}

## Built on the first transform, so a reduction never run allocates nothing.
var _compute: SaCompute = null
## The two textures of the transform, whose roles swap at every pass.
var _textures: Array[SaTexture] = []
var _twiddles: SaCompute.Buffer = null


## *clock* is the idle clock it waits for, the app's own `SaIdle` when null, and
## *largest_side* the largest square it transforms, a power of two.
func _init(clock: SaIdleClock = null, largest_side: int = LARGEST) -> void:
    super(false)
    _given_clock = clock
    largest = largest_side


## Stops hearing the clock and the document and gives back every texture, so
## a closed docker costs nothing. The spectrum held stays, and the next run
## transforms afresh.
func let_go() -> void:
    _follow(null, null)
    _hear_the_loop(false)
    _transformed = []
    _compute = null
    _textures = []
    _twiddles = null


## Whether the painter has stopped painting *document* by *clock*: the clock
## watches that document, has said so since the last edit, and no stroke is
## open on it. The clock's own say, read rather than heard, because the
## service's handler of [signal SaIdleClock.stopped] runs before any other.
static func painter_stopped(clock: SaIdleClock, document: SaDocument) -> bool:
    if clock == null or not is_instance_valid(clock) or document == null or clock.document != document:
        return false
    return clock.said and not clock.is_stroke_open()


## The side of the square over a canvas of *canvas_size*: the largest power of
## two neither above its longer side nor above *most*.
static func side_for(canvas_size: Vector2i, most: int) -> int:
    var longer := maxi(canvas_size.x, canvas_size.y)
    var found := 1
    while found * 2 <= mini(longer, most):
        found *= 2
    return found


## How wide every texture of a transform at side *n* is, and how many
## coefficients a row of the half spectrum holds: `n / 2 + 1`.
static func columns_for(n: int) -> int:
    return (n >> 1) + 1


## The square the transform reads, in document pixels: as wide as the canvas's
## longer side and centred over the canvas, so it overhangs the shorter side by
## the same on both edges.
static func square_over(canvas_size: Vector2i) -> Rect2:
    var longer := float(maxi(canvas_size.x, canvas_size.y))
    var corner := (Vector2(canvas_size) - Vector2(longer, longer)) * 0.5
    return Rect2(corner, Vector2(longer, longer))


## The power at frequency (*u*, *v*) of the whole spectrum, each from
## `-side / 2` to `side / 2`, read from the half held through
## `X(u, v) = X*(-u, -v)`. Zero before the first answer.
func power_at(u: int, v: int) -> float:
    if side <= 0:
        return 0.0
    if u < 0:
        u = -u
        v = -v
    var columns := columns_for(side)
    if u >= columns:
        return 0.0
    return power[posmod(v, side) * columns + u]


## The period in document pixels of ring *ring*, how far apart the repeats of
## a pattern at that frequency are, and INF for the zero frequency.
func period_of(ring: int) -> float:
    if ring <= 0 or side <= 0:
        return INF
    return float(side) * document_pixels_per_texel / float(ring)


func _reduce(easel: SaEasel) -> void:
    if easel == null or easel.document == null or easel.output == null or not easel.output.rid.is_valid():
        return
    var clock := _given_clock if _given_clock != null else SaPowerSpectrum._app_clock()
    _follow(easel.document, clock)
    if not painter_stopped(clock, easel.document):
        return
    var history := easel.document.history
    var picture := [easel.document.get_instance_id(), easel.output.rid, history.position() if history != null else -1, _edits]
    if picture == _transformed:
        return
    var n := side_for(easel.document.canvas_size, largest)
    if n < SMALLEST:
        return
    # What changed outside the window the view shows is composited too, since
    # the spectrum is of the whole picture.
    easel.flush()
    if not _transform(easel, n):
        return
    _transformed = picture
    transforms += 1
    transformed_msec = Time.get_ticks_msec()


## The spectrum of *bytes*, the answer to ask *ask* over a square of *n* texels
## each spanning *span* document pixels, unless a later ask has gone out since.
## Called by the device's answer, or at once.
func heard(ask: int, n: int, span: float, bytes: PackedByteArray) -> void:
    if ask != _asks:
        return
    var floats := bytes.to_float32_array()
    var columns := columns_for(n)
    if floats.size() < columns * n + columns:
        return
    power = floats.slice(0, columns * n)
    radial = floats.slice(columns * n, columns * n + columns)
    side = n
    document_pixels_per_texel = span
    arrived_msec = Time.get_ticks_msec()
    arrived.emit()


## Hears *clock* and counts *document*'s edits, in place of any before.
func _follow(document: SaDocument, clock: SaIdleClock) -> void:
    if document != _document:
        if is_instance_valid(_document) and _document.document_changed.is_connected(_on_edit):
            _document.document_changed.disconnect(_on_edit)
        _document = document
        if document != null:
            document.document_changed.connect(_on_edit)
    if clock != _heard_clock:
        if is_instance_valid(_heard_clock) and _heard_clock.stopped.is_connected(stale):
            _heard_clock.stopped.disconnect(stale)
        _heard_clock = clock
        if clock != null:
            clock.stopped.connect(stale)


func _on_edit() -> void:
    _edits += 1


## Records every pass of the transform over *easel*'s composite at side *n*,
## sends them as one compute list with a barrier between each two, and asks for
## the answer. False when nothing was sent.
func _transform(easel: SaEasel, n: int) -> bool:
    var columns := columns_for(n)
    var output := easel.output
    _hold(n)
    if _compute == null:
        _compute = SaCompute.new(SHADER)
    # Before anything is bound, because a change of format reloads the
    # kernels and forgets what was bound.
    _compute.use_storage_format(output.format)
    var result := SaCompute.Buffer.new(_zeroed(columns * n + columns))
    if not result.rid.is_valid() or _twiddles == null or not _twiddles.rid.is_valid():
        return false
    _compute.set_storage("twiddles", _twiddles.rid)
    _compute.set_storage("result", result.rid)
    _compute.set_image("composite", output)

    var square := square_over(easel.document.canvas_size)
    var shared := _params(easel.document.color_space, square)
    var recorded: Array[SaCompute.Recorded] = []
    var writes := 0
    for step: Pass in Pass.all_for(n):
        # A set binds every binding, so the gather, which reads the composite
        # alone, still has a source bound, and the last two passes a target.
        _compute.set_image("source", _textures[1 - writes])
        _compute.set_image("target", _textures[writes])
        var params := shared.duplicate()
        params.append_array(PackedFloat32Array([float(n), float(step.span), float(step.points), float(step.along)]))
        _compute.set_push_constant_float_array(params)
        var one := _compute.record(step.kernel, output.format, step.groups.x, step.groups.y, 1, true)
        if one == null:
            return false
        recorded.append(one)
        writes = 1 - writes
    SaCompute.submit(recorded, SHADER)
    _asks += 1
    _ask(_asks, n, square.size.x / float(n), result)
    return true


## The first 68 bytes `power_spectrum.gmacs` reads, in its order, which are
## the same for every pass of a transform.
static func _params(space: SaColorSpace, square: Rect2) -> PackedFloat32Array:
    var params := PackedFloat32Array([square.position.x, square.position.y, square.size.x, float(space.coordinates)])
    params.append_array(space.transfer.to_params())
    for column: Vector3 in SaColorSpaceGlsl.basis_columns(space.to_linear_srgb_matrix()):
        params.append_array(PackedFloat32Array([column.x, column.y, column.z]))
    return params


## The two textures and the twiddles for side *n*, kept from the last
## transform when it was the same side.
func _hold(n: int) -> void:
    var extent := Vector2i(columns_for(n), n)
    if _textures.size() == 2 and _textures[0].size == extent and _twiddles != null:
        return
    _textures = [
        SaTexture.new(extent, RenderingDevice.DATA_FORMAT_R32G32_SFLOAT),
        SaTexture.new(extent, RenderingDevice.DATA_FORMAT_R32G32_SFLOAT),
    ]
    _twiddles = SaCompute.Buffer.new(SaPowerSpectrum.twiddles_for(n).to_byte_array())


## `exp(-2 pi i k / n)` for k from 0 to n / 2, as cos and sin pairs, worked in
## doubles and rounded once to floats.
static func twiddles_for(n: int) -> PackedFloat32Array:
    var pairs := PackedFloat32Array()
    for k in columns_for(n):
        var angle := -TAU * float(k) / float(n)
        pairs.append(cos(angle))
        pairs.append(sin(angle))
    return pairs


## Hands the answer back on a later frame, or at once off the main device.
func _ask(ask: int, n: int, span: float, result: SaCompute.Buffer) -> void:
    var rd := result.rd
    if read_at_once or rd != RenderingServer.get_rendering_device():
        heard(ask, n, span, result.read())
        return
    waiting += 1
    _owed[ask] = result
    if rd.buffer_get_data_async(result.rid, _result_back.bind(ask, n, span)) != OK:
        _owed.erase(ask)
        waiting -= 1
        heard(ask, n, span, result.read())
        return
    _drawn_seen = Engine.get_frames_drawn()
    _hear_the_loop(true)


## Connected to `SceneTree.process_frame` while an answer is owed. A turn of
## the loop that drew no frame since the last draws one without presenting it,
## as `SaTipCache` does, because the device hands the answer over only as
## frames are drawn and the app in low processor mode draws one only when
## something on screen changed, and the idle clock's stop changes nothing
## there. Never a present, which can wait for
## ever on a compositor that does not answer.
func draw_while_owed() -> void:
    if waiting <= 0:
        _hear_the_loop(false)
        return
    var drawn := Engine.get_frames_drawn()
    if drawn == _drawn_seen and RenderingServer.get_rendering_device() != null:
        RenderingServer.force_draw(false, 0.0)
    _drawn_seen = drawn


## Starts or stops hearing every turn of the main loop.
func _hear_the_loop(hear: bool) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return
    if hear and not tree.process_frame.is_connected(draw_while_owed):
        tree.process_frame.connect(draw_while_owed)
    elif not hear and tree.process_frame.is_connected(draw_while_owed):
        tree.process_frame.disconnect(draw_while_owed)


## The device's answer to the ask numbered *ask*, a method with plain values
## bound and never a lambda or the result, as `OverDocument._tally_back` is and
## for its reasons. *result* waits in `_owed` until the answer comes.
func _result_back(bytes: PackedByteArray, ask: int, n: int, span: float) -> void:
    var result: SaCompute.Buffer = _owed.get(ask)
    _owed.erase(ask)
    waiting -= 1
    if result != null and bytes.size() == result.size:
        heard(ask, n, span, bytes)


## The clock the app runs, the autoload `SaIdle`, or null in a run without it.
static func _app_clock() -> SaIdleClock:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null or tree.root == null:
        return null
    return tree.root.get_node_or_null(^"SaIdle") as SaIdleClock


static func _zeroed(floats: int) -> PackedByteArray:
    var zeros := PackedFloat32Array()
    zeros.resize(floats)
    zeros.fill(0.0)
    return zeros.to_byte_array()


## One pass of a transform: its kernel, the span, points and axis a butterfly
## pass reads, and its workgroups. Each pass writes the texture the last one
## did not, so the order of [method all_for] is the order of the reads.
class Pass:
    extends RefCounted

    var kernel: String
    var span: int
    var points: int
    var along: int
    var groups: Vector2i

    ## *extent* is what the kernel covers, a texel or a butterfly an
    ## invocation, across and down.
    func _init(kernel_name: String, extent: Vector2i, span_out: int = 0, axis_points: int = 0, axis: int = 0) -> void:
        kernel = kernel_name
        span = span_out
        points = axis_points
        along = axis
        groups = Vector2i(SaCompute.groups_for(extent.x), SaCompute.groups_for(extent.y))

    ## Every pass of a transform at side *n*: the gather, log2(n / 2) passes
    ## along the rows, the untangle, log2(n) down the columns, the power and
    ## the rings, the last a workgroup a ring.
    static func all_for(n: int) -> Array[Pass]:
        var columns := SaPowerSpectrum.columns_for(n)
        var passes: Array[Pass] = [Pass.new("spectrum_gather", Vector2i(n >> 1, n))]
        var span_out := 1
        while span_out < n >> 1:
            passes.append(Pass.new("spectrum_butterflies", Vector2i(n >> 2, n), span_out, n >> 1, 0))
            span_out *= 2
        passes.append(Pass.new("spectrum_untangle", Vector2i(columns, n)))
        span_out = 1
        while span_out < n:
            passes.append(Pass.new("spectrum_butterflies", Vector2i(n >> 1, columns), span_out, n, 1))
            span_out *= 2
        passes.append(Pass.new("spectrum_power", Vector2i(columns, n)))
        var rings := Pass.new("spectrum_radial", Vector2i.ONE)
        rings.groups = Vector2i(columns, 1)
        passes.append(rings)
        return passes
