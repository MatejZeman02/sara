## Owns one painting: the document, the compositor that flattens it, and the
## texture they composite into.
##
## Named "easel" rather than "workspace" because in Krita and Photoshop a
## workspace is a saved UI arrangement, which is what docker_layout_store.gd
## and the secondary monitor hosts already mean by the word here. An easel holds
## the painting, never the panels around it.
##
## An easel names no UI, so a suite or an export holds a document with no view.
##
## A view (SaCanvas) is given an easel and binds its Texture2DRD to `output`.
extends Node

class_name SaEasel

var canvas_size: Vector2i
var document: SaDocument
var compositor: SaCompositor

## The flattened result. A view binds a Texture2DRD to this RID. Nothing copies.
var output: SaTexture

var needs_composite: bool = false

## The output a resize or a document swap displaced, kept alive for exactly one
## frame so anything that polls for the swap rather than subscribing to it does
## not draw from a freed RID first. Cleared at the top of `_process`.
var _displaced_output: SaTexture = null
var needs_full_composite: bool = false

## What a composite costs on the CPU, in microseconds: the time spent walking
## the stack and issuing its dispatches. The GPU finishes later and cannot be
## timed from here without a stall, so this is the half of stroke latency that
## GDScript can see, and the number stroke latency is measured against.
## Cumulative, so two state dumps either side of a stroke give the stroke's
## own cost.
var composite_usec_total: int = 0
var composite_usec_last: int = 0
var composite_count: int = 0

## How many of the latest composites the recent mean spans. The session mean
## above never resets, so an hour into a sitting it says what the program did
## then rather than what it does now, and the Info docker reads this one.
const RECENT_COMPOSITES: int = 60

## The CPU cost of the last `RECENT_COMPOSITES` composites in microseconds, a
## ring written at `_recent_next`, and their sum, kept rather than added up on
## every read. Fewer than the full count while the ring fills.
var composite_usec_recent: PackedInt64Array = PackedInt64Array()
var composite_usec_recent_total: int = 0
var _recent_next: int = 0

## What the window shows, in document pixels. Handed in by the `SaCanvas` that
## shows this easel, as `core` never names `render`. Unset, or empty, the whole
## output is composited, as for a suite's easel or a thumbnail's.
var shown_rect: Callable = Callable()

## How many device pixels a document pixel covers in that view, handed in the
## same way. Past one, the detail view draws a layer at 2.0 at its own density.
var pixels_per_texel: Callable = Callable()

## The display chunks of a layer at 2.0 while the view is zoomed in.
var detail := SaDetailView.new()

## What changed where the window did not reach.
var backlog := SaCompositeBacklog.new()

## How much of a dirty set the easel's own frame composites, the rest held in
## [member backlog] for the next frame.
var budget := SaCompositeBudget.new()

## The visible heights resolved for the view to light, beside every composite.
var relief := SaRelief.new()

## The window the backlog was last asked against. A frame with nothing dirty
## asks again only when the window moved.
var _window_asked: Rect2 = Rect2()


## A easel with the default document (grey background plus one paint layer).
## What the app's own document is in, and what File > New opens on. Both ask
## here, so the two agree by saying so rather than by the dialog's first row
## happening to match a document that names no space.
##
## Asked for rather than applied here: `create_default` still means sRGB at F32
## when nobody names a space, because it is what every suite in the tree builds
## a document with and a fixture that changes underfoot is a hundred failing
## assertions about colours nobody changed.
##
## A function rather than a `const`, because a descriptor is a `RefCounted` and
## a constant one would be a single object every document then shared.
##
## **The gamut is the display profile's**. A picked `1, 0, 0` is the red of the
## gamut the document declares, so a document wider than the screen holds
## colours its painter picked and cannot see, and one narrower cannot hold the
## red the screen shows. The curve, the coordinates and the depth stay the
## shipped preset's, so a Display P3 profile still opens on the shipped preset
## and an sRGB one opens on the same choices over sRGB's
## primaries, which no preset names.
static func default_space() -> SaColorSpace:
    var space := SaColorSpace.oklab_p3().with_depth(SaColorSpace.Depth.F16)
    var display := SaSettings.display_profile_space()
    if display == null or space.shares_gamut(display):
        return space
    return space.with_gamut(display.gamut())


static func create_default(size: Vector2i, shared_compositor: SaCompositor = null, space: SaColorSpace = null) -> SaEasel:
    var easel := SaEasel.new()
    easel.name = "SaEasel"
    easel.setup(size, shared_compositor, space)
    return easel


## `shared_compositor` lets several easels share one blend-mode registry.
## Passing null builds a private one.
func setup(size: Vector2i, shared_compositor: SaCompositor = null, space: SaColorSpace = null) -> void:
    assert(size.x > 0 and size.y > 0, "Canvas size must be positive")
    canvas_size = size
    compositor = shared_compositor if shared_compositor != null else SaCompositor.new()

    # The document comes first, so the output can be allocated at the depth it
    # declares. Compositing writes chunks into this texture through one kernel,
    # and one kernel cannot serve two storage formats.
    document = SaDocument.new()
    document.name = "Document"
    add_child(document)
    document.setup_default_document(size, compositor, space)

    output = SaTexture.new(size, document.color_space.texel_format())
    # SaTexture does not clear on allocation, and any part of the output not
    # covered by an allocated chunk is never written by the compositor.
    output.clear(Color.TRANSPARENT)

    # The document was made above, so nothing is connected to it yet, and it
    # is this easel's child, so its connections go with it.
    document.chunks_invalidated.connect(_on_chunks_invalidated)
    # A halo reads across the seam of a projection that wraps, so a new one redraws.
    document.projection_changed.connect(_on_projection_changed)
    # The document's own request and not one on the bus, so a change in one
    # open document composites that document's easel alone.
    document.composite_requested.connect(request_composite)

    request_full_composite()


## Re-sizes the painting surface, replacing the output texture.
##
## Returns the texture that was displaced, and the caller must hold that
## reference until it has rebound its view. `output` is the only strong reference
## to it, so dropping it here would free the RID while the view's Texture2DRD
## still pointed at it. The document is not touched: resetting or loading it is
## the caller's job and has to happen first, so the composite this schedules sees
## the new content.
func resize_output(size: Vector2i) -> SaTexture:
    assert(size.x > 0 and size.y > 0, "Canvas size must be positive")
    var displaced := output
    # Held here as well as returned, for one frame, because the view is not the
    # only thing bound to this texture and it is the only one that rebinds
    # inside this call. The Minimap docker polls `easel.output.rid` against the
    # one it holds, so it rebinds on its *next* `_process`, and without the
    # hold the frame between the two draws a `Texture2DRD` over a freed RID:
    # "Texture (binding: 0, index 0) is not a valid texture" out of Godot's own
    # canvas batcher, once per swap, with any docker open. One frame
    # of one output texture is the price, and `_process` below drops it before
    # it composites.
    _displaced_output = displaced
    canvas_size = size
    # Depth as well as size: this runs after the document has been reset or
    # loaded, so it is also the moment a document of a different depth gets an
    # output that matches it.
    var depth_format := document.color_space.texel_format() if document != null else displaced.format
    output = SaTexture.new(size, depth_format)
    output.clear(Color.TRANSPARENT)
    backlog.clear()  # The new output is composited whole.
    detail.release()
    request_full_composite()
    return displaced


## Composite whatever chunks the document has marked dirty on the next frame.
func request_composite() -> void:
    needs_composite = true


## Re-composite every allocated chunk. For document load, layer reordering and
## anything else that invalidates more than the dirty set knows about.
func request_full_composite() -> void:
    needs_composite = true
    needs_full_composite = true


## Composites what changed where the window reaches, holding the rest, and
## what was held once the window moves over it, which is a pan. *budgeted*,
## which the easel's own frame alone passes, holds too what [member budget]
## says this frame cannot pay for, and asks for the next frame to go on. A
## caller that reads the output after this call passes nothing and gets all.
func process_pending_composite(budgeted: bool = false) -> void:
    var window := composed_area()
    if not needs_composite and (window == _window_asked or not backlog.reaches(window)):
        _window_asked = window
        _follow_detail({}, false)
        return
    _compose(window, budgeted)


## The positions of *dirty* a full composite does not walk, where no layer the
## walk draws holds paint. A layer that stores nothing draws everywhere, so
## then there are none.
func _left_out(dirty: Dictionary[Vector2i, Rect2i]) -> Array[Vector2i]:
    var left: Array[Vector2i] = []
    if SaGeneratedLayer.any_in(document):
        return left
    var walked: Dictionary[Vector2i, bool] = {}
    for layer in SaLayerStack.layers(document):
        for grid_pos: Vector2i in layer.chunks:
            walked[grid_pos] = true
    for grid_pos: Vector2i in dirty:
        if not walked.has(grid_pos):
            left.append(grid_pos)
    return left


## Brings the output up to the picture the stack draws for a reader of the
## whole of it, a file or a copy: a fold the debt holds the picture back for
## paid, `SaFoldDebt.before_reading`, and what changed since the last frame
## composited now rather than at the next. A reader calls [method flush] after
## it for what the window held back.
func catch_up() -> void:
    SaFoldDebt.before_reading(document)
    process_pending_composite()


## Composites the held chunks *area* reaches, the whole canvas when empty, with
## *area* as the window. Every reader of the output as the picture calls it
## first. A GPU composite over held and dirty chunks, nothing read back, so hard
## rules 1 and 2 hold, and nothing at all when nothing is held there. The dirty
## set goes in too, because the filter chain grows one composite's regions by
## what was attached since the last, and a flush that took that growth alone
## would leave the next frame without it.
func flush(area: Rect2i = Rect2i()) -> void:
    var window := Rect2(area) if area.has_area() else Rect2(0.0, 0.0, canvas_size.x, canvas_size.y)
    if backlog.reaches(window):
        _compose(window)


## What the view shows grown by a chunk, so a pan shows no empty edge for a
## frame, or the whole canvas when nothing shows this easel.
func composed_area() -> Rect2:
    var whole := Rect2(0.0, 0.0, canvas_size.x, canvas_size.y)
    if not shown_rect.is_valid():
        return whole
    var shown: Rect2 = shown_rect.call()
    if not shown.has_area():
        return whole
    return shown.grow(SaLayer.CHUNK_SIZE)


func _compose(window: Rect2, budgeted: bool = false) -> void:
    needs_composite = false
    _window_asked = window
    if compositor == null or output == null or document == null:
        return

    var traced := SaFrameTrace.now()
    var folding := Time.get_ticks_usec()
    var dirty := document.consume_dirty_chunks()
    budget.spent_usec = Time.get_ticks_usec() - folding
    var fold := document.fold if budgeted else null
    var debt := fold.debt if fold != null else null
    var paid := debt.take_paid() if debt != null else 0
    budget.spent_usec += paid
    budget.waits = paid * 4 >= SaCompositeBudget.FRAME_USEC
    SaFrameTrace.spent("caches", traced)
    # The consume brings the active layer's cache up to date, and where it
    # changed asks for a composite that this one already holds.
    needs_composite = false
    var full := needs_full_composite
    needs_full_composite = false
    # What was held where the window now reaches, drawn beside what is new.
    var late: Dictionary[Vector2i, Rect2i] = {}
    backlog.take(window, late)

    # The main window's easel alone, because the scratchpad and the thumbnails
    # composite too and an event's latency is the painter's canvas's.
    if (full or not dirty.is_empty()) and is_inside_tree() and get_window() == get_tree().root:
        SaStrokeLedger.composite_issued()
    var started := Time.get_ticks_usec()
    var walked: Dictionary[Vector2i, Rect2i] = {}
    if full:
        SaGpuTiming.category_begin("composite")
        traced = SaFrameTrace.now()
        walked = compositor.composite_all_layers(output, document, window, backlog, budget if budgeted else null)
        SaFrameTrace.spent("walk of the whole canvas", traced)
        # A held chunk no layer stores is in no walk, and its clear is owed, as
        # is a dirty one only a layer the walk leaves out holds, an isolated
        # view's hidden paint.
        for grid_pos: Vector2i in _left_out(dirty):
            SaCompositeBacklog.merge(late, grid_pos, dirty[grid_pos])
        if not late.is_empty():
            compositor.composite_chunks(output, document, late, window, false, backlog)
    elif not dirty.is_empty() or not late.is_empty():
        # An empty dirty set is nothing to redraw, where a stray request once
        # fell through to re-flattening every allocated chunk of all four tiers.
        SaGpuTiming.category_begin("composite")
        for grid_pos: Vector2i in late:
            SaCompositeBacklog.merge(dirty, grid_pos, late[grid_pos])
        traced = SaFrameTrace.now()
        walked = compositor.composite_chunks(output, document, dirty, window, false, backlog, budget if budgeted else null)
        if traced > 0:
            SaFrameTrace.spent("walk of %d chunks" % walked.size(), traced)
    else:
        _follow_detail({}, false)
        return
    traced = SaFrameTrace.now()
    relief.resolve(document, dirty, late if full else walked, full, window)
    SaFrameTrace.spent("relief", traced)
    traced = SaFrameTrace.now()
    _follow_detail(walked, full)
    SaFrameTrace.spent("detail", traced)
    composite_usec_last = Time.get_ticks_usec() - started
    composite_usec_total += composite_usec_last
    budget.learn(composite_usec_last, walked.size(), document)
    if debt != null and composite_usec_last * 4 >= SaCompositeBudget.FRAME_USEC:
        debt.walked()
    # What the budget held where the window reaches is the next frame's.
    if budgeted and backlog.reaches(window):
        needs_composite = true
    composite_count += 1
    _remember_recent(composite_usec_last)
    # Opened inside each composing branch and closed here, so the early return
    # above leaves no capture open.
    if SaGpuTiming.enabled:
        var texels := 0
        for grid_pos: Vector2i in dirty:
            texels += (dirty[grid_pos] as Rect2i).get_area()
        SaGpuTiming.category_end("composite", {"dirty_chunks": dirty.size(), "dirty_texels": texels, "full": int(full)})


## The detail view over what the view shows, composited over *walked*, the
## regions the output's walk took this frame, or whole when *full*.
func _follow_detail(walked: Dictionary[Vector2i, Rect2i], full: bool) -> void:
    var zoomed := pixels_per_texel.is_valid() and SaDetailView.zoomed_in(SaTyped.real(pixels_per_texel.call()))
    detail.follow(document, compositor, composed_area(), zoomed, walked, full)


## One composite's CPU cost into the ring the recent mean reads, the oldest
## one leaving the sum as it is overwritten.
func _remember_recent(usec: int) -> void:
    if composite_usec_recent.size() < RECENT_COMPOSITES:
        composite_usec_recent.append(usec)
    else:
        composite_usec_recent_total -= composite_usec_recent[_recent_next]
        composite_usec_recent[_recent_next] = usec
    composite_usec_recent_total += usec
    _recent_next = (_recent_next + 1) % RECENT_COMPOSITES


## The sample merged door: a copy of the composite under *rect* as it stands,
## one GPU to GPU copy per chunk cell under it and nothing read back. A stroke
## takes one when it starts and grows it by each dab that leaves it, and the
## smudge stage on the brush plan reads its pickup from it. The eyedropper's
## sample merged is the first reader: its readback stays the texels it always
## was, taken off the snapshot rather than off `output`.
##
## The snapshot is [RefCounted] and the caller holds the only reference, so it
## is released with the stroke and the easel keeps no list of them. What the
## backlog holds under *rect* is flushed first, so the copy is the picture.
func snapshot_merged(rect: Rect2i) -> SaMergedSnapshot:
    flush(rect)
    return SaMergedSnapshot.new(output, canvas_size, rect)


func _process(_delta: float) -> void:
    # Before the composite rather than after it: every poller has had its own
    # `_process` by the time this frame draws, so the texture displaced by the
    # last swap has done its job and the RID can go.
    _displaced_output = null
    SaGpuTiming.collect()
    # What is asked stays asked while nothing shows this easel, a document
    # behind another tab, and is drawn once on the first frame it shows.
    if is_shown():
        var traced := SaFrameTrace.now()
        process_pending_composite(true)
        SaFrameTrace.spent("easel composite", traced)


## False while the nearest canvas item above this easel is hidden, and true
## for an easel no canvas item holds: a preset's thumbnail, an export, a suite.
func is_shown() -> bool:
    var above := get_parent()
    while above != null and not above is CanvasItem:
        above = above.get_parent()
    return above == null or (above as CanvasItem).is_visible_in_tree()


func _on_chunks_invalidated(_grid_positions: Array) -> void:
    request_composite()


func _on_projection_changed(_projection: SaProjection) -> void:
    request_full_composite()


## Order matters: the view must drop its Texture2DRD before `output` is released,
## so it is the view's job to null its texture first. Here the document goes
## before the compositor, because freeing layers frees chunk RIDs that the
## compositor's uniform sets may still reference.
func _cleanup_resources() -> void:
    # First, and before `output`, because an easel torn down between a swap and
    # the next frame is holding one texture nothing will ever come back for,
    # and the runner's exit code counts it as a leaked Texture RID.
    _displaced_output = null
    detail.release()
    document = null
    compositor = null
    output = null


func _exit_tree() -> void:
    _cleanup_resources()


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        _cleanup_resources()
