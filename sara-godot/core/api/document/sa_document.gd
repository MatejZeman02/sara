## High-level container for canvas data and layer management.
##
## Manages the overall canvas dimensions, the stack of SaLayer objects,
## and coordinates the temporary stroke buffer for active drawing operations.
@tool
extends Node

class_name SaDocument

const SaStrokeTransactionScript = preload("res://core/api/document/sa_stroke_transaction.gd")

var canvas_size: Vector2i:
    set(value):
        var old_middle := Vector2(canvas_size) * 0.5
        canvas_size = value
        brush_side = minf(value.x, value.y)
        if _symmetry != null:
            _symmetry.follow_canvas(old_middle, Vector2(value))

## The side a brush's radius and the feather are fractions of, which `SaCrop` keeps.
var brush_side: float = 0.0

## Which part of the document that was is the document that is now, in the old
## coordinates, while a resize is being announced and never at any other moment.
##
## `document_resized` carries the new size and nothing else, and a size alone
## cannot tell a view where the picture went: a crop makes the rectangle the
## painter dragged into the whole document, so every texel moves by that
## rectangle's origin. `SaCrop` writes this immediately before the signal and
## puts it back to an empty rectangle immediately after, which a synchronous
## signal makes airtight, and a view reads it to keep its zoom and re-derive its
## pan. An empty rectangle is "nobody said", and a view fits the whole document
## to itself the way it always did.
var resize_source: Rect2i = Rect2i()

## Pixels per inch, so the document can say how big it is on paper.
##
## 72 for a file that does not record it, which is also what File > New offers
## first. A plain field rather than a property: nothing on screen
## mirrors it yet, and the `.sad` header is the only reader.
const DEFAULT_DPI: float = 72.0
var dpi: float = DEFAULT_DPI

## The layer a stroke lands on.
##
## A property rather than a plain field because three places assigned it directly
## and nothing downstream heard: the default document adds its layers first and
## points here afterwards, the reset clears it, and loading a .sad picks the first
## layer. The layers docker rebuilds itself from child_entered_tree, which fires
## while this is still null, so its last word on the subject was "no active layer"
## and no row was highlighted after File > New or File > Open.
##
## set_active_layer() is still what a tool or the UI calls. It owes the caches a fold
## and announces a document change as well, and neither of those is right during
## construction, which is why the assignment alone has to be the thing that speaks.
var active_layer: SaLayer = null:
    set(value):
        active_layer = value
        active_layer_changed.emit(value)

## The mask the brush paints just now, or null for the ordinary paint target. A
## mask is painted the way the quick mask paints the selection: straight in, as
## coverage, with the same engine. A `SaMask` rather than a layer, because a mask
## lives in two stores and this is the one door to both: the layers docker writes
## a layer's or a group's here, and an attached filter's record writes its own.
##
## It announces from its setter, for the reason `active_layer` does.
var mask_target: SaMask = null:
    set(value):
        mask_target = value
        mask_target_changed.emit(value)

## What this document's numbers mean: gamut, white point, transfer and depth.
##
## Never null. A document created here declares sRGB, written down rather than
## assumed. One loaded from a file that records no colour space gets `SaColorSpace.unspecified()`, which
## renders identically but reports `is_specified == false`, so a converter can
## tell "painted as sRGB" from "nobody ever said".
var color_space: SaColorSpace = SaColorSpace.srgb():
    set(value):
        color_space = value
        # Every route that changes it goes through this assignment: File > New,
        # Assign, Convert and load. Announcing here rather than at each of those
        # is what stops the fourth one being forgotten. The declaration's own
        # initial value does not run a setter, so a fresh document is silent
        # until something really changes it.
        modified = true
        EventBus.document_color_space_changed.emit(self)

## What the pixels are a picture of: flat, or a panorama of a registered kind.
## Never null, and flat until assigned. Changed by being handed a new
## descriptor, `SaProjection.assign` as one history step, and announced from
## here for the reason the colour space is.
var projection: SaProjection = SaProjection.new():
    set(value):
        projection = value if value != null else SaProjection.new()
        modified = true
        projection_changed.emit(projection)

## The value a display-referred blend mode should treat as 1.0.
##
## `screen(a, b) = a + b - ab` is meaningless at a = 40, so those modes evaluate
## `out = W * f(src / W, dst / W)` instead. W is document data rather than viewer
## state, so a file reopens looking exactly as it was saved.
##
## 1.0 is the identity in both directions, and a file that does not record
## the value is read at it. Raising it widens the window a display-referred
## mode reasons in without capping anything: storage still keeps whatever
## magnitude the arithmetic produced, negatives included.
##
## This is not the tonemapper. What a blend *computes* and what the screen
## *shows* are separate questions, and mixing them would bake a look into the
## pixels (see `render/sa_canvas.gd`).
var blend_reference_white: float = 1.0

## Mid grey in display coordinates, before the document's space is applied.
const BACKGROUND_GREY := Color(0.5, 0.5, 0.5, 1.0)
## The colour this document's background was laid in, in display terms, so a
## grow of the canvas extends a white background in white rather than grey.
var background_shown: Color = BACKGROUND_GREY

# --- STROKE BUFFER ---
var stroke_layer: SaLayer
var stroke_opacity: float = 1.0
## The stroke's commit and a wash eraser's lowering, which it owns.
var stroke_bake := SaStrokeBake.new()

## The document-wide selection, kept in core/api/selection/sa_selection.gd. Every document
## has one from birth, File > New replaces it, and it is dropped with the layers. It
## asks for `history` by name when a change empties it, which is made after it.
var selection: SaSelection = SaSelection.new(Callable(self, &"get").bind(&"history"))

## Symmetry for every tool that paints, core/api/document/sa_symmetry.gd. Made on first
## use, centred on the canvas, and kept for the window's life, because the tool
## options' three toggles listen to this one object. What follows the document
## are the axes, which `SaSymmetry.follow_canvas` puts back when the canvas changes.
var _symmetry: SaSymmetry = null
var symmetry: SaSymmetry:
    get:
        if _symmetry == null:
            _symmetry = SaSymmetry.new()
            _symmetry.reset_axes(Vector2(canvas_size))
        return _symmetry

## The light the impasto is drawn and baked under, the document's own and kept
## in its `.sad`. Mutated in place and never replaced, so the canvas that hears
## it hears every document this one becomes.
var relief_light := SaReliefLight.new()
## Whether new paint layers are made at double resolution, kept in the `.sad`.
var double_resolution := SaDoubleResolution.new()

var stroke_transaction: SaStrokeTransaction = SaStrokeTransactionScript.new()
var infinite_canvas := SaInfiniteCanvas.new()

# --- DIRTY SET ---
## All of a chunk, for every caller that changes all of one. `SaLayerStack`
## and the compositor read it by this name.
const WHOLE_CHUNK := Rect2i(0, 0, SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE)

## Grid position -> Rect2i in chunk-local pixels, the part of each chunk a
## frame still has to redraw.
var _dirty_chunks: Dictionary[Vector2i, Rect2i] = {}
## Where the dirty set the last consume answered was painted, keyed by grid
## position and read as a set, before a filter's halo or a whole-node pass
## widened it, and how many consumes there have been. A filter that keeps a
## node it gathered copies again what this names and nothing else, and one
## that missed a consume gathers anew.
var painted: Dictionary[Vector2i, bool] = {}
var consumed: int = 0
## The same dirty set without what the root's own whole-node filters added to
## it, keyed by grid position and read as a set: where the composite under the
## root may have changed, which is what a gather of the canvas copies again.
var beneath_root: Dictionary[Vector2i, bool] = {}
## The same dirty set by the layer each region moved at, layer instance id ->
## grid position -> Rect2i in chunk-local pixels, a region marked at no layer
## in none, which `SaAdjustmentCache` counts only above its layer.
var moved_at: Dictionary[int, Dictionary] = {}
## The same dirty set where only [method reveal_all_allocated_chunks] marked
## it, keyed by grid position and read as a set: chunks the walk draws again
## though no layer's paint, properties or place moved there, which an effect
## layer's cache that already holds its input need not draw again.
var still: Dictionary[Vector2i, bool] = {}
var _painting: Dictionary[Vector2i, bool] = {}
## Grid positions, read as sets, marked since the last consume by a reveal
## alone, and by any other mark.
var _still: Dictionary[Vector2i, bool] = {}
var _stirred: Dictionary[Vector2i, bool] = {}
## Whether the mark under way is a reveal's.
var _revealing := false
## What a change makes stale through the filters of the tree, which keeps
## where the composite under the root changed until a consume takes it.
var _spread := SaStaleSpread.new()

## What the caches wait to be built again for at the end of the frame: the
## layers a write moved, or the document itself for a whole rebuild.
var _cache_update_pending: Dictionary[Object, bool] = {}

# --- CACHES ---
## What the compositor walks and the caches the layers are folded into. The
## fold owns them, and `_drop_contents()` is where they are released.
var fold: SaLayerFold = null
var compositor: SaCompositor
## The Layers docker's picked rows, which the Layer menu's commands act on.
var picked := SaPickedLayers.new()

# --- HISTORY ---
var undo_redo: UndoRedo
## limits max history states
## Bounded by bytes, not by steps. `SaHistory` owns the accounting and sets
## `UndoRedo.max_steps` to whatever fits, so the step count is a result rather
## than a setting: thirty-two steps of a dab are a few megabytes and thirty-two
## steps of a full-canvas stroke about 2.5 GiB.
var history: SaHistory = null


## The compositor is injected, never invented.
##
## A private SaCompositor made when none is set would let a document composite
## against a different blend-mode registry than the view showing it, so a
## module-registered blend mode would work in one and silently fall back to
## Normal in the other.
func injected_compositor() -> SaCompositor:
    assert(compositor != null, "SaDocument has no compositor; pass one to setup_default_document()")
    if compositor == null:
        push_error("SaDocument has no compositor: compositing is a no-op until one is set.")
    return compositor


signal active_layer_changed(layer: SaLayer)
signal mask_target_changed(mask: SaMask)
signal chunks_invalidated(grid_positions: Array)
## Asks the easel showing this document, and only that one, for a composite.
@warning_ignore("unused_signal")
signal composite_requested
signal document_changed
@warning_ignore("unused_signal")
signal layer_changed(layer: SaLayer)  # Its eye, opacity, mode, lock or name alone.
signal path_changed(path: String)
signal modified_changed(modified: bool)
signal projection_changed(projection: SaProjection)

## Where this document lives on disk. Empty until it has been saved or opened,
## which is what Save As and the quit prompt ask.
var file_path: String = "":
    set(value):
        if file_path == value:
            return
        file_path = value
        path_changed.emit(value)

## Whether anything has changed since the last save or load, kept by
## [member saved_mark] against the history. It announces through
## `modified_changed`, the way `active_layer` and `color_space` do, so the
## window title and the prompts mirror one bit rather than each keeping their own.
var modified: bool:
    get:
        return saved_mark.modified
    set(value):
        saved_mark.mark(value)

## How many times [member modified] was raised, read by a save in the background.
var raises: int:
    get:
        return saved_mark.raises

## Whether the document matches its file, kept against where the history stands.
var saved_mark := SaSavedMark.new(func() -> int: return history.position() if history != null else -1, modified_changed.emit)


## Records that the document on disk at *path* is this one, exactly. Called by
## whoever saved or opened it, never by the save itself: an autosave writing a
## recovery copy is a save that must not claim the document.
func mark_saved(path: String) -> void:
    file_path = path
    modified = false


## Marks whole chunks dirty, at *at* as [method invalidate_chunk_regions] does.
## What every caller but the paint context wants: a layer reorder, an undo or a
## cache rebuild changes all of a chunk. *paint* false is a redraw of what a
## preview shows over chunks nobody changed, left out of [member painted].
func invalidate_chunks(grid_positions: Array, at: SaLayer = null, paint: bool = true) -> void:
    var regions: Dictionary[Vector2i, Rect2i] = {}
    for grid_pos: Vector2i in grid_positions:
        regions[grid_pos] = WHOLE_CHUNK
    invalidate_chunk_regions(regions, at, paint)


## Marks part of each chunk dirty, in chunk-local pixels.
##
## A dab covers a few dozen pixels of a 256x256 chunk, and redrawing the whole
## chunk for it dispatches 65,536 threads to change a few hundred. Unioned rather
## than replaced, because several dabs can land in one chunk between two composites and every one of them has to be redrawn.
##
## A grid position outside the canvas is dropped rather than marked. The output
## texture is document-sized, so nothing there can be composited, and an import
## that places a picture whole leaves a layer holding chunks past the edge on
## purpose: they are paint a later crop should find, not paint to redraw.
##
## *regions* is grid position -> Rect2i in chunk-local pixels.
##
## Each region first takes in what it makes stale through the filters of the
## tree, a neighbourhood filter's halo and the chunks a whole-node filter
## rewrites, which `SaStaleSpread` answers, and is kept under *at*, the layer
## the change moved at, for [member moved_at]. Null names no layer, and counts
## as a change below every layer.
func invalidate_chunk_regions(changed_regions: Dictionary, at: SaLayer = null, paint: bool = true) -> void:
    # A module's table is its own untyped code, typed here where it enters.
    var regions := SaTyped.regions(changed_regions)
    # Taken here, so a mark a listener makes while this one is under way is
    # never read as a reveal.
    var revealing := _revealing
    _revealing = false
    if paint:
        _painting.merge(SaTyped.positions(regions))
    stroke_bake.lower_under(self, regions)
    regions = _spread.spread(self, root_filters, regions, canvas_size, at, projection.wrapping)
    var changed: Array[Vector2i] = []
    var grid_limit := Vector2i(ceili(canvas_size.x / float(SaLayer.CHUNK_SIZE)), ceili(canvas_size.y / float(SaLayer.CHUNK_SIZE)))
    for grid_pos: Vector2i in regions:
        var region: Rect2i = regions[grid_pos]
        if region.size.x <= 0 or region.size.y <= 0:
            continue
        if grid_pos.x < 0 or grid_pos.y < 0 or grid_pos.x >= grid_limit.x or grid_pos.y >= grid_limit.y:
            continue
        if revealing and not _stirred.has(grid_pos):
            _still[grid_pos] = true
        elif not revealing:
            _stirred[grid_pos] = true
            _still.erase(grid_pos)
        if _dirty_chunks.has(grid_pos):
            # merge(), not expand(): merging with an *empty* rect would anchor the
            # result at (0, 0) and grow a rectangle out of the chunk's corner, so
            # nothing empty is allowed into this dictionary in the first place.
            _dirty_chunks[grid_pos] = (_dirty_chunks[grid_pos] as Rect2i).merge(region)
            continue
        _dirty_chunks[grid_pos] = region
        changed.append(grid_pos)
    if not changed.is_empty():
        chunks_invalidated.emit(changed)


## The dirty set and the part of each chunk it covers, as grid position -> Rect2i
## in chunk-local pixels. Clears it, so a frame consumes it once. The active
## layer's live transform is brought up to date first, since the walk reads its
## cache itself, so where that cache changed is in the set and in `painted`.
func consume_dirty_chunks() -> Dictionary[Vector2i, Rect2i]:
    SaLiveTransform.paint_of(active_layer)
    SaFoldDebt.before_drawing(self, _dirty_chunks)
    var dirty := _dirty_chunks.duplicate()
    _dirty_chunks.clear()
    painted = _painting
    _painting = {}
    beneath_root = _spread.take_beneath()
    moved_at = _spread.take_moved()
    still = _still
    _still = {}
    _stirred = {}
    consumed += 1
    return dirty


## Marks every chunk the walk reads, at no layer, for a change that moved
## nothing the document holds: a view that reaches chunks it did not, or a
## stack whose drawing is rebuilt from layers that stand as they were. The
## chunks are drawn again as [method invalidate_all_allocated_chunks] has them,
## and a position no other mark reached before the consume is in [member still].
func reveal_all_allocated_chunks() -> void:
    _revealing = true
    invalidate_all_allocated_chunks()
    _revealing = false


## Marks whole chunks at *grid_positions* as a reveal, at no layer, as
## [method reveal_all_allocated_chunks] marks every chunk.
func reveal_chunks(grid_positions: Array) -> void:
    _revealing = true
    invalidate_chunks(grid_positions)
    _revealing = false


func invalidate_all_allocated_chunks() -> void:
    var all_chunks: Dictionary[Vector2i, bool] = {}
    for layer in SaFoldDebt.drawn_from(self):
        for grid_pos in layer.chunks:
            all_chunks[grid_pos] = true
    # A layer that stores nothing has drawn everywhere.
    for grid_pos in SaGeneratedLayer.covered_positions(self):
        all_chunks[grid_pos] = true
    invalidate_chunks(all_chunks.keys())


func set_active_layer(layer: SaLayer) -> void:
    active_layer = layer
    fold.debt.owe(self)
    document_changed.emit()


## Opens a stroke. *mode_id* is the brush's own blend mode, and *buffer_mode*
## is what the buffer composites as when the brush routes the stroke through it
## rather than painting straight in: ERASE for a wash eraser, ALPHA_LOCK for a
## wash stroke on an alpha-locked layer, empty for everything else.
##
## The buffer mode is the brush's decision rather than this method's, because
## the same erase can be either: build-up still paints straight into the layer,
## and only wash needs the coverage gathered first.
func begin_stroke(opacity: float, mode_id: StringName, buffer_mode: StringName = &"") -> void:
    fold.debt.settle(self)
    if active_layer != null:
        active_layer.stroke_pressed.emit()
    SaResidency.press(self)
    stroke_transaction.open(selection)
    stroke_transaction.erasing = SaLayer.BLEND_MODE.ERASE in [mode_id, buffer_mode]
    stroke_opacity = opacity
    stroke_bake.start(buffer_mode, active_layer)
    if stroke_layer == null:
        return
    # The buffer's chunks are made at the active layer's scale, so a stroke on
    # a double resolution layer is gathered at its density and the commit pairs
    # two textures of one size.
    stroke_layer.resolution_scale = active_layer.resolution_scale if active_layer != null else 1.0
    # A buffer mode is tagged with the rule the commit will apply, so the
    # preview shows what the commit leaves: an eraser's destination-out or an
    # alpha-locked stroke's kept alpha, once a stroke rather than once a dab.
    #
    # Without one, erasing paints straight onto the active layer in build-up,
    # so the buffer is never tagged ERASE there: composite.gmacs has a real
    # destination-out kernel, and an empty buffer tagged ERASE would carve the
    # canvas during the preview rather than composite as normal.
    var direct_mode: StringName = SaLayer.BLEND_MODE.NORMAL if mode_id == SaLayer.BLEND_MODE.ERASE else mode_id
    stroke_layer.blend_mode = direct_mode if buffer_mode.is_empty() else buffer_mode


func capture_direct_stroke_chunk(layer: SaLayer, grid_pos: Vector2i) -> void:
    if layer == null:
        return
    stroke_transaction.capture_before(layer, grid_pos)
    stroke_transaction.mark_direct_paint()


## The colour a new document's background layer starts on, mid grey unless the
## New Document dialog chose another, in the document's own coordinates.
##
## Converted rather than written straight into the chunk, which is right only
## for a document that stores gamma sRGB. A linear document would read the
## literal as light-linear and come up at 0.735 rather than mid grey, and an
## Oklab one would read 0.5, 0.5, 0.5 as a lightness with a and b both at 0.5,
## which is a saturated orange.
##
## `from_display` is the same seam the brush and the eyedropper use, and
## it is an exact passthrough for an sRGB document, so nothing anyone has already
## painted moves by a last bit.
func background_fill() -> Color:
    return color_space.from_display(background_shown) if color_space != null else background_shown


## Creates a default new file: the background *background* asks for, which is
## `SaDocumentBackground`'s dictionary and a solid grey one when empty, and an
## empty transparent paint layer. *types* is where a ground is looked up.
func setup_default_document(
    size: Vector2i,
    document_compositor: SaCompositor = null,
    space: SaColorSpace = null,
    resolution: float = DEFAULT_DPI,
    background: Dictionary = {},
    types: SaLayerTypeRegistry = null,
) -> void:
    assert(size.x > 0 and size.y > 0, "Canvas size must be strictly positive")
    if document_compositor != null:
        compositor = document_compositor
    if space != null:
        color_space = space
    canvas_size = size
    dpi = resolution if resolution > 0.0 else DEFAULT_DPI
    undo_redo = UndoRedo.new()
    history = SaHistory.new(undo_redo)

    # Every layer this document owns allocates at the descriptor's depth, the
    # caches and the stroke buffer included. One of them left at F32 in an F16
    # document would be the single mismatched binding in an otherwise correct
    # dispatch, and a kernel cannot serve two formats at once.
    var layer_schema := SaFieldSpec.schema_for_space(color_space)

    background_shown = SaDocumentBackground.shown_of(background, BACKGROUND_GREY)
    SaDocumentBackground.lay(self, background, types, BACKGROUND_GREY)

    # Paint Layer. Empty, and allocated only where the brush lands: a fresh
    # chunk is cleared to transparent when it is made, so there is nothing to
    # fill here.
    var paint_layer := SaLayer.new()
    paint_layer.name = "Layer 1"
    paint_layer.schema = layer_schema
    add_child(paint_layer)

    # Stroke Buffer (Temporary scratchpad, explicitly NOT added as a child)
    var buffer := SaLayer.new()
    buffer.name = "StrokeBuffer"
    buffer.schema = layer_schema
    stroke_layer = buffer
    # Note: intentionally DO NOT call setup() on the stroke layer.
    # We want it to be completely empty and only allocate chunks exactly where the brush touches

    # The fold makes its caches at the document's schema when it first needs one.
    fold = SaLayerFold.new()

    # Set the target for the brush
    active_layer = paint_layer

    # Force initial cache build for the starting screen resolution
    var visible_rect := Rect2(0, 0, size.x, size.y)
    update_caches(visible_rect)

    # A fresh document belongs to no file and has nothing to lose yet. Last,
    # because the colour space assignment above raised the flag.
    file_path = ""
    SaDocumentSource.forget(self)
    modified = false


## Throws this document away and builds a fresh default one in its place.
func reset_to_default(
    size: Vector2i,
    space: SaColorSpace = null,
    resolution: float = DEFAULT_DPI,
    background: Dictionary = {},
    types: SaLayerTypeRegistry = null,
) -> void:
    assert(size.x > 0 and size.y > 0, "Canvas size must be strictly positive")

    _drop_contents()
    # Before the layers go, since the layers docker reads the active layer when
    # a layer leaves. The stack goes in one notice and not one per layer: over
    # the 305 layers of the seasons file each notice listed the stack again, and
    # a New took 24.8 s and 3.9 GB.
    active_layer = null
    mask_target = null
    set_block_signals(true)
    for child in get_children():
        if child is SaLayer:
            child.free()
    set_block_signals(false)
    child_order_changed.emit()
    selection = SaSelection.new(Callable(self, &"get").bind(&"history"))
    # The rest of what belongs to the document rather than to its layers, which
    # a new document, a picture opened and an OpenRaster file must not inherit.
    # The `.sad` reader replaces all three on its own.
    root_filters.clear()
    module_data = {}
    reference_boards = []
    # W too, for the reason the colour space is never inherited.
    blend_reference_white = 1.0
    # And the relief's light goes back to where Preferences starts one.
    relief_light.start_from_preferences()
    # So does the projection: a picture opened after a panorama is flat until
    # someone says otherwise.
    projection = SaProjection.new()
    infinite_canvas = SaInfiniteCanvas.new()
    setup_default_document(size, compositor, space, resolution, background, types)


## Rebuilds the Bottom and Top caches for the specific canvas area.
## This should only be called when layers change (visibility, opacity, ordering, etc.).
## *revealing* marks the chunks as [method reveal_all_allocated_chunks] does,
## for a caller whose change moved nothing the document holds.
func update_caches(visible_rect: Rect2 = Rect2(), revealing: bool = false) -> void:
    # An explicit rebuild absorbs whatever was queued: it is about to do the work
    # that request was asking for.
    _cache_update_pending = {}
    if visible_rect == Rect2():
        visible_rect = Rect2(0, 0, canvas_size.x, canvas_size.y)
    assert(fold != null, "the fold must be built")
    assert(active_layer != null, "active_layer must be set")

    if fold == null or active_layer == null:
        return

    # The caches read each child's albedo, so anything derived must be resolved
    # first or a cache bakes in a stale field.
    for child in get_children():
        if child is SaLayer:
            (child as SaLayer).resolve_pending()

    fold.rebuild(self, injected_compositor(), visible_rect)

    # Everything the walk reads is redrawn, over a dense grid plus one row and one column past the canvas.
    if revealing:
        reveal_all_allocated_chunks()
    else:
        invalidate_all_allocated_chunks()
    document_changed.emit()


## Redraws what a change to *mask* at *grid_positions* moves, at the layer that
## holds it. A mask the fold baked into a cache is read again only when the
## cache folds, so each cache that baked its holder folds again over those
## chunks. Any other mask is read where it stands on every composite, and the
## chunks are enough. A stroke on a mask comes here, and so does the undo of one.
func mask_moved(mask: SaMask, grid_positions: Array) -> void:
    _paint_moved(mask.holder_in(self), grid_positions)
    document_changed.emit()


## Redraws what *write* moves and nothing else: a write to a filter's
## parameters on *node*, which a played time makes every frame (hard rule 2),
## or to its blend mode, opacity or visibility. No cache is rebuilt whole.
## The node's chunks are marked at it with the halo its old passes read and
## again with the halo its new ones read, and `SaLayerFold.refold` folds a
## cache again over those alone where only *node* moved in it. The root's
## filters, null for *node*, read the whole canvas.
func filter_moved(node: SaLayer, write: Callable) -> void:
    var drawn := SaLayerStack.drawn_by(self, node).keys()
    var stale := _stale_around(drawn)
    invalidate_chunks(drawn, node)
    write.call()
    modified = true
    if node == null:
        invalidate_all_allocated_chunks()
    elif compositor != null:
        # A write drops the record's passes, and a halo is read off them.
        compositor.filter_chain.reach_of(node)
        invalidate_chunks(drawn, node)
        stale.merge(_stale_around(drawn))
        if fold != null:
            invalidate_chunks(fold.refold(self, compositor, node, stale).keys(), node)
    document_changed.emit()


## Marks *grid_positions* of *layer*'s paint or mask dirty at the layer, and
## folds again over them each cache that baked it, so paint that came back under
## the active layer, an undo's, shows at once and no stale cache chunk with it.
func _paint_moved(layer: SaLayer, grid_positions: Array) -> void:
    invalidate_chunks(grid_positions, layer)
    if fold != null and compositor != null:
        invalidate_chunks(fold.refold(self, compositor, layer, _stale_around(grid_positions)).keys(), layer)


## The positions a change of the chunks at *drawn* makes stale, asked of a
## spread of its own so [member _spread]'s record beneath the root is kept.
func _stale_around(drawn: Array) -> Dictionary[Vector2i, bool]:
    var regions: Dictionary[Vector2i, Rect2i] = {}
    for grid_pos: Vector2i in drawn:
        regions[grid_pos] = WHOLE_CHUNK
    return SaTyped.positions(SaStaleSpread.new().spread(self, root_filters, regions, canvas_size, null, projection.wrapping))


## Bakes the temporary stroke chunks into the active layer and records History,
## then lets the document settle against the card's budget, `SaResidency`.
func commit_stroke(override_opacity: float = -1.0) -> void:
    SaInfiniteCanvas.settle(self, stroke_bake.commit.bind(self, injected_compositor, override_opacity))
    SaResidency.release(self)


## Fills a layer (defaults to active_layer) with a solid colour, as one step called *step_name*
##
## *color* is the colour as it stands on screen, which is what the colour pair
## holds, and it is converted into the document's working space here. This is
## the one place the chord's fill and the background's fill both go through,
## so the conversion happens once rather than at each caller.
##
## **The conversion is not cosmetic.** Under an sRGB document `from_display` is
## an exact passthrough, so leaving it out shows nothing there, and under Oklab
## the three display numbers would be written straight in as L, a and b: a
## grey-purple #a7a2ae would land as an Oklab of (0.654, 0.634, 0.681), a
## saturated orange whose display value is red past one with green and blue
## below zero. The stroke converts through the same seam, in `state_brush.gd`.
func fill_layer(color: Color, target_layer: SaLayer = null, step_name: String = "Fill Layer") -> void:
    var layer := target_layer if target_layer != null else active_layer
    assert(layer != null, "Cannot fill: target layer is null")
    if layer == null or (("is_locked" in layer) and layer.is_locked):
        return
    # A layer that turns the brush away holds no pixels a fill could mean: a
    # scene would paint over the chunks, an adjustment or an effect has none,
    # and under a live transform the preview draws the layer elsewhere. A
    # generated layer refuses paint too, but its fill is its colour, so it
    # is asked first. The fill is a write of the layer's own pixels, which is
    # why `refuses_paint` is asked unmapped.
    if not layer.is_generated() and layer.refuses_paint():
        return
    var space := color_space
    var stored := space.from_display(color) if space != null else color
    if layer.is_generated():
        # A background stores nothing, so a fill is its colour. It takes the
        # converted value for the reason `SaGeneratedLayer.defaults_for` converts
        # a generator's own default: the params are read by a kernel that writes
        # the canvas, so they are working-space numbers.
        SaGeneratedLayer.fill(self, layer, stored)
        return

    var undo_data: Dictionary[Vector2i, Variant] = {}
    for grid_pos in layer.chunks:
        undo_data[grid_pos] = layer.duplicate_chunk(grid_pos)

    # Alpha is coverage rather than colour and `from_display` carries it through
    # untouched, so the clear branch reads the same either way.
    if stored.a <= 0.0 and not selection.active:
        # Transparent everywhere is no paint anywhere, so the chunks go rather
        # than being cleared: a layer holds chunks only where paint is. Under
        # a selection a clear is a masked fill like any other, and never a
        # clear of the whole layer regardless.
        layer.release_chunks()
    else:
        # A fill lands everywhere the selection lets it, so this is the one
        # operation after the background that allocates more than a brush
        # reaches: the whole grid with no selection, under one only the
        # positions it holds, and under an alpha lock none at all. The positions it adds are recorded as absent, so
        # an undo removes them again rather than leaving blanks. A clear under
        # a selection allocates nothing, because it lands only on paint the
        # layer already holds.
        if stored.a > 0.0:
            for grid_pos in SaLayer.fill_reach(self, layer):
                if not undo_data.has(grid_pos):
                    undo_data[grid_pos] = null
                layer.get_or_create_chunk(grid_pos)
        layer.fill(stored)

    record_pixel_step(step_name, layer, undo_data)

    _paint_moved(layer, undo_data.keys())
    modified = true
    document_changed.emit()


## Clears a layer (defaults to active_layer) to transparent, as one step called Clear Layer
func clear_layer(target_layer: SaLayer = null) -> void:
    fill_layer(Color(0, 0, 0, 0), target_layer, "Clear Layer")


## Arbitrary per-document state for each module, as { module_id -> Dictionary }.
##
## Which colour set a document was mixed with is a fact about the document,
## not about any one layer, and nothing in the skeleton can know what it means.
## Written and read through `SaContext.document_data()`, which hands a module its
## own slice and nobody else's.
##
## Data belonging to a module that is not installed is carried here untouched and
## written back out on the next save. Losing a collaborator's data because you
## had not installed their module would be worse than refusing to open the file.
var module_data: Dictionary[String, Variant] = {}

## The Reference docker's boards, as paths and rectangles. Written by the docker,
## stored under the `.sad` header's `reference_boards` key, never pixels.
var reference_boards: Array = []

## The filters attached to the document's root, which are the document's global
## filter: one more node a record hangs under and no second mechanism. Bottom
## first, evaluated over the whole composite, edited through `SaFilterOps`
## with a null node.
var root_filters: Array[SaAttachedFilter] = []


func undo() -> bool:
    if undo_redo == null or not undo_redo.has_undo():
        return false
    saved_mark.step(undo_redo.undo)
    return true


func redo() -> bool:
    if undo_redo == null or not undo_redo.has_redo():
        return false
    saved_mark.step(undo_redo.redo)
    return true


## Asks for a cache rebuild at the end of the frame rather than now.
##
## Rebuilding both caches walks every visible chunk, and the controls that ask for
## it are sliders and dropdowns: a slider emits `value_changed` for every pixel it
## travels, so dragging layer opacity was a forty-chunk rebuild per tick for a
## value the user had not finished choosing. Coalescing costs one frame of latency
## on a number that is being dragged, which is not a number anyone reads mid-drag.
##
## Deferred rather than driven by the easel, so a document with no view behind it,
## which is every test and the info docker's scratchpad, still rebuilds.
##
## A *moved* layer, an opacity or a blend mode write, takes [method filter_moved]'s
## narrowed path at the flush instead of a rebuild, unless something in the
## same frame asked for the whole one.
func request_cache_update(moved: SaLayer = null) -> void:
    if _cache_update_pending.is_empty():
        _flush_cache_update.call_deferred()
    _cache_update_pending[self as Object if moved == null else moved as Object] = true


func _flush_cache_update() -> void:
    var pending := _cache_update_pending
    _cache_update_pending = {}
    if pending.has(self):
        update_caches()
        return
    for moved: Object in pending:
        if is_instance_valid(moved) and (moved as SaLayer).get_parent() == self:
            filter_moved(moved as SaLayer, func() -> void: pass)


## Records a pixel operation on *layer* as one reversible history step, charged against the
## history's byte budget. The stroke, the fill, a filter, the clipboard's cut and a module's tool
## all come here. *state* maps a grid position to the chunk or SaChunkDelta that was there before,
## or null for a chunk that was not.
##
## Undo and redo are the same operation from opposite sides, so one snapshot per step is enough:
## whatever comes off the layer is exactly what the other direction will need, and it becomes the
## history entry. So a step holds one copy of every touched chunk rather than one for each
## direction, and installing it is a handover rather than a third copy made so a backup survives
## being installed.
##
## *state* is mutated, and both directions are bound to the same Dictionary on purpose. A Dictionary
## is a reference in GDScript, which is what makes one object able to be both sides of the action.
func record_pixel_step(action_name: String, layer: SaLayer, state: Dictionary, selection_swap: SaSelection.Swap = null) -> void:
    layer.paint_recorded.emit(state.keys())
    if history == null:
        return
    history.commit(action_name, swap_pixels.bind(layer, state, selection_swap), state)


## Exchanges *layer*'s chunks with the ones *state* holds, and *state* keeps what
## came off. What a step recorded above runs in both directions, and what a
## layer operation calls when it needs the same trade inside a step of its own.
func swap_pixels(layer: SaLayer, state: Dictionary, selection_swap: SaSelection.Swap = null) -> void:
    assert(layer != null, "Target layer for Undo/Redo cannot be null")

    for grid_pos: Vector2i in state.keys():
        var stored: Variant = state[grid_pos]

        # Part of a tile, which is what a stroke leaves behind. Exchanging the
        # region is the same trade as exchanging the whole chunk, over fewer
        # pixels, and everything outside it is untouched by definition: the region
        # is the union of what the stroke painted there.
        if stored is SaChunkDelta:
            var live: SaChunk = layer.get_or_create_chunk(grid_pos)
            if live == null:
                continue
            var delta: SaChunkDelta = stored
            state[grid_pos] = SaChunkDelta.capture(live, delta.rect)
            delta.apply_to(live)
            layer.mark_unresolved(grid_pos)
            continue

        # A whole tile, or null where there was no tile at all, which round-trips
        # as the "remove it again" case rather than as missing data.
        var current: SaChunk = layer.duplicate_chunk(grid_pos)
        var whole: SaChunk = stored
        layer.set_chunk(grid_pos, whole)
        state[grid_pos] = current

    # The selection the transform carried goes back with the pixels, and comes
    # forward again on the redo, because the swap inverts itself the way the
    # loop above does.
    if selection_swap != null:
        selection_swap.exchange()

    _paint_moved(layer, state.keys())
    layer.paint_swapped.emit(state.keys())
    document_changed.emit()


## Lets go of everything a document holds that is nobody's child: the history,
## the stroke buffer and every cache. The reset and the teardown both come here.
##
## The history goes first. `UndoRedo` is an Object rather than a RefCounted, so
## letting go of it leaks it along with every chunk backup its steps still hold
## in VRAM, and its steps refer to layers that are about to be freed, so keeping
## it would let an undo reach into nothing.
##
## The stroke buffer and the caches are deliberately not children, because they
## are never serialised, and an orphan Node is nobody's job to free: leaving them
## behind leaked a full set of chunk textures on every File > New.
func _drop_contents() -> void:
    if stroke_transaction != null:
        stroke_transaction.reset()
    if undo_redo != null:
        undo_redo.clear_history()
        undo_redo.free()
        undo_redo = null
    history = null

    var buffer := stroke_layer
    if is_instance_valid(buffer):
        buffer.free()
    stroke_layer = null
    if fold != null:
        fold.release()
    fold = null


func _cleanup_resources() -> void:
    _drop_contents()
    stroke_transaction = null
    compositor = null
    _dirty_chunks.clear()
    selection = null


func _exit_tree() -> void:
    _cleanup_resources()


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        _cleanup_resources()
