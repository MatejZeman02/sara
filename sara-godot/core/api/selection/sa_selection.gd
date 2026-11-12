## The document-wide selection: one sparse set of single-channel chunks that
## every tool and every layer reads.
##
## A mask is coverage, 0 to 1 per document pixel, stored as `r32f` on the same
## chunk grid as the paint. Sparse in the same way: a chunk exists only where
## the selection reaches, and a chunk that does not exist is fully unselected.
## No selection at all means everything is selected, and that case is not a
## flag but a texture: a 1 by 1 mask holding 1.0, which a kernel reads through
## `min(pixel, imageSize(mask) - 1)` and so sees as 1.0 everywhere. The kernel
## needs no branch and the push constant no field, and every dispatch binds a
## mask of the one format the binding declares.
##
## Shapes are written by the kernels in `shaders/compute/selection.gmacs`, a
## rectangle, an ellipse and a polygon, each in one of four modes: replace,
## add, subtract and intersect. A region another engine made, the wand's flood,
## a colour range or a layer's alpha, joins through [method merge_region] in
## the same four. Invert, feather and border are the Select menu's and live
## in `SaSelectionFilters`, because they read across chunk seams and this
## file is what stores. The quick mask is `editing`: while
## it is on the brush paints coverage into these chunks instead of colour
## into the layer.
##
## Not persisted. A selection is a working state, not part of the picture,
## but every change a painter makes to it is one undo step, through
## [method change], as Krita and Photoshop both list one. The methods that
## write a shape record nothing themselves, so a caller that only wants a mask
## for a moment, the bucket fill's flood, leaves no step behind.
class_name SaSelection
extends RefCounted

## Announced after every change, so the overlay redraws its ants and the
## bar follows the quick mask.
signal changed

## What a shape does to what is selected already. Intersect keeps only what
## both hold, and is last so no number a tool's options stored moves.
enum Mode { REPLACE, ADD, SUBTRACT, INTERSECT }

## The one field a mask chunk holds.
const FIELD: StringName = &"mask"

## Single-channel float, whatever depth the document paints at: a mask is not
## colour, and its precision is its own business.
const FORMAT: int = RenderingDevice.DATA_FORMAT_R32_SFLOAT

## The binding every kernel that honours the selection declares for it, as
## `layout( r32f, set = 0, binding = 1 ) uniform readonly image2D mask;`.
const BINDING: int = 1

## The bindings of `selection.gmacs` beyond the mask: the neighbours a filter
## reads and the polygon's points. Every dispatch binds all of them, because
## a uniform set covers the whole layout whichever kernel runs.
const BINDING_BEFORE: int = 1
const BINDING_SELF: int = 2
const BINDING_AFTER: int = 3
const BINDING_POINTS: int = 4

## Where the `bounds` kernel reduces the tight box, four ints in document
## pixels. Bound to a stand-in by every other kernel, for the reason above.
const BINDING_BOX: int = 5

## What the box is seeded with, so the first covered texel wins both atomics and
## an empty selection comes back as the empty box rather than as a box round
## nothing. Not `INT32_MAX`, because a document is never that wide and a number
## a reader can recognise is worth more than the last bit of headroom.
const BOX_WIDE: int = 1 << 24


## The selection either side of a commit, exchanged by the same history step
## that exchanges the pixels.
##
## **The mask is kept, not recomputed.** The carry is a resample, so its inverse
## is a second resample and a second interpolation: a feathered edge would come
## back softer than it went out and a pixel-art mask would not come back at all.
## Holding the chunks is exact, and it costs one R32 field per chunk against the
## step's own grid of colour chunks, which is four fields of four channels each.
## The chunks the selection is dropping are already built, so nothing is copied
## here either: the dictionary the carry replaced is simply not let go of.
##
## Self-inverting like `SaDocument.swap_pixels`, so undo and redo are the
## same call and neither direction needs a second closure.
##
## It lives here rather than on `SaTransformSelection`, its only builder. What
## it holds is a selection's chunks and bounds and nothing of a transform, and
## a skeleton signature names it: `SaDocument.swap_pixels` and
## `SaDocument.record_pixel_step` both take one.
class Swap:
    extends RefCounted

    var _selection: SaSelection
    var _chunks: Dictionary
    var _bounds: Rect2i

    func _init(selection: SaSelection, chunks: Dictionary, bounds: Rect2i) -> void:
        _selection = selection
        _chunks = chunks
        _bounds = bounds

    ## Puts the held selection on the document and holds the one it replaced.
    func exchange() -> void:
        if _selection == null:
            return
        var chunks_now: Dictionary = _selection.chunks
        var bounds_now: Rect2i = _selection.bounds
        _selection.chunks = _chunks
        # After the chunks, because writing bounds rebuilds the per-chunk boxes
        # from whatever `chunks` holds at that moment.
        _selection.bounds = _bounds
        _chunks = chunks_now
        _bounds = bounds_now
        _selection.changed.emit()


## The history step a drop records, Krita's name for it.
const DROP_TITLE: String = "Deselect"

## What the Undo History docker calls each change, one name a tool or a
## command, kept here so a tool, a menu and the harness name one change alike.
## A tool's step is the tool's own name in the toolbox, so the history and the
## toolbox never disagree about what made a selection.
const RECT_TITLE: String = "Marquee"
const ELLIPSE_TITLE: String = "Ellipse Select"
const FREEHAND_TITLE: String = "Lasso"
const WAND_TITLE: String = "Magic Wand"
const COLOR_RANGE_TITLE: String = "Colour Range"
const ALL_TITLE: String = "Select All"
const RESELECT_TITLE: String = "Reselect"
const INVERT_TITLE: String = "Invert Selection"
const FEATHER_TITLE: String = "Feather Selection"
const BORDER_TITLE: String = "Border Selection"
const GROW_TITLE: String = "Grow Selection"
const SHRINK_TITLE: String = "Shrink Selection"

## Whether a selection exists. Off, everything is selected and the chunks are
## empty. On, only what the chunks say, and never no chunks at all: a change
## that leaves none drops the selection. An active selection
## of nothing clipped every dab to nothing and drew no ants, so the pen did
## nothing with no sign of why.
var active: bool = false

## The quick mask: the brush paints coverage into the selection rather than
## colour into the layer while this is on.
var editing: bool = false:
    set(value):
        if editing == value:
            return
        editing = value
        if editing:
            shape = null
        if editing and not active:
            active = true
        # The mask turned off with nothing painted into it is no selection.
        # Nothing stood before it either, so there is no step to record.
        if not editing and chunks.is_empty():
            active = false
        changed.emit()

## Grid position -> SaChunk holding one FIELD texture.
var chunks: Dictionary = {}

## The feather over the hard mask the shapes write, a live amount that
## [method change] lays over the hard mask whenever either moves.
var feather := SaSelectionFeather.new()

## The rectangle, ellipse or polygon a plain Replace wrote, for a point test
## with nothing read back. Null when another change made the selection, and
## standing only while [method SaSelectionShape.stands_in] says so.
var shape: SaSelectionShape = null

## The rectangle everything selected lies inside, in document pixels, so a copy
## or a cut dispatches over that rather than over every chunk whole. Empty when
## nothing is selected.
##
## The union of [member _boxes] rather than a number of its own, because a number of its own
## only ever grows: a subtract merges nothing into it, and the quick mask's path writes none of
## it. Writing it is still allowed and is how
## `SaSelectionFilters` and the base module's flood hand over the reach of what they wrote,
## which they compute better than this file could. Such a write is authoritative and rebuilds
## the per-chunk boxes from itself.
##
## Every box here is an over-estimate. Where one cannot be shrunk without
## reading the mask back off the GPU, it is not shrunk, which is the wand's
## subtract and a cut through the middle of a box.
var bounds: Rect2i:
    get:
        return _bounds
    set(value):
        _bounds = value
        _boxes.clear()
        for grid_pos: Vector2i in chunks:
            var local := value.intersection(chunk_rect(grid_pos))
            if local.size.x > 0 and local.size.y > 0:
                _boxes[grid_pos] = local

## Grid position -> the tightest rectangle in document pixels that certainly
## holds every selected pixel of that chunk. Kept per chunk rather than as one
## number because that is what lets a subtract shrink the answer: a rectangle
## taken off the top of one chunk's coverage says nothing about the chunk beside
## it, and the union of the two is the only honest total.
##
## Every box is an over-estimate and never an under-estimate. An ellipse or a
## polygon claims its bounding box, a dab painted through the quick mask claims
## the whole chunk, and a subtract shrinks only where it can prove the shrink.
var _boxes: Dictionary[Vector2i, Rect2i] = {}
var _bounds: Rect2i = Rect2i()

## What the last `deselect` dropped, its chunks, boxes and bounds, held whole
## so `reselect` brings it back exactly. Empty when nothing
## was dropped or the last reselect took it. It costs what the selection did,
## one R32 field per chunk, until the next deselect replaces it.
var _kept_chunks: Dictionary = {}
var _kept_boxes: Dictionary[Vector2i, Rect2i] = {}
var _kept_bounds: Rect2i = Rect2i()

var _everything: SaTexture = null
var _nothing: SaTexture = null
var _compute: SaCompute = null
var _no_points: SaCompute.Buffer = null
## The stand-in every kernel but `bounds` binds at BINDING_BOX, and the buffer
## `measure_bounds` seeds and reads. One buffer rather than one per call, so a
## uniform set built against it stays valid (SaCompute.Buffer.update).
var _box: SaCompute.Buffer = null

## `func() -> SaHistory`, the document's history asked at the moment a change
## empties the selection, so the drop is one undo step. A question rather than
## the history, because a document makes its selection before its history and
## replaces the history on File > New. Empty for a scratch selection such as
## the patch tool's, which records nothing.
var _history_of: Callable

## How many [method change] calls are running, so only the outermost records
## a step and a marquee with a Feather option is one step.
var _depth: int = 0

## Every chunk the running change made or copied, as keys, so one it owns is
## written in place and one the way back still holds is copied first. Empty
## outside a change.
var _owned: Dictionary = {}

## Whether the selection is the one Select All made, unchanged since. Any
## change emits [signal changed], which lets it go, so an inverted, added to or
## feathered Select All is a shape the painter drew.
var _whole: bool = false


func _init(history_of: Callable = Callable()) -> void:
    _history_of = history_of
    # A method rather than a lambda, which would hold this selection and leak it.
    changed.connect(_forget_whole)


func _forget_whole() -> void:
    _whole = false


func schema() -> Array[SaFieldSpec]:
    var fields: Array[SaFieldSpec] = [SaFieldSpec.create(FIELD, FORMAT, false)]
    return fields


## The mask a kernel binds for *grid_pos*: the chunk's own when the selection
## covers it, the everything stand-in when no selection is active, and null when
## a selection is active and leaves the chunk out, which a dispatcher reads as
## "nothing to do here" and skips.
func texture_for(grid_pos: Vector2i) -> SaTexture:
    if not active:
        return everything()
    var chunk: SaChunk = chunks.get(grid_pos, null)
    return chunk.field(FIELD) if chunk != null else null


## Whether painting at *grid_pos* can change anything.
func covers(grid_pos: Vector2i) -> bool:
    return not active or chunks.has(grid_pos)


## The 1 by 1 mask that reads as 1.0 everywhere. Owned here, so it goes with
## the document rather than living as a static that would be freed at shutdown
## against a device already gone.
func everything() -> SaTexture:
    if _everything == null:
        _everything = SaTexture.new(Vector2i(1, 1), FORMAT)
        _everything.clear(Color(1.0, 1.0, 1.0, 1.0))
    return _everything


## The 1 by 1 mask that reads as 0.0 everywhere: what a filter sees past the
## last chunk, so a feather ends where the selection does.
func nothing() -> SaTexture:
    if _nothing == null:
        _nothing = SaTexture.new(Vector2i(1, 1), FORMAT)
        _nothing.clear(Color(0.0, 0.0, 0.0, 0.0))
    return _nothing


## The mode a press asks for, the chord Photoshop and Krita share: Shift and
## Alt together intersect, Shift alone adds, Alt alone subtracts, and a press
## with neither takes *base*, what the tool's options say.
static func mode_for_press(base: int, shift: bool, alt: bool) -> int:
    if shift and alt:
        return Mode.INTERSECT
    if shift:
        return Mode.ADD
    if alt:
        return Mode.SUBTRACT
    return base


## What the selection holds now, for [method drop_if_empty] after a change.
func hold() -> SaSelectionHeld:
    return SaSelectionHeld.new(chunks, _boxes, _bounds, active, _kept_chunks, _kept_boxes, _kept_bounds, _whole, feather, shape)


## Runs *work*, which changes this selection, and records what it did as one
## undo step called *title* on the document's history. Answers what *work*
## answered, so Reselect's chord still falls through when nothing was kept.
##
## **The way back is the chunks as they were, never written into.** A replace
## starts from fresh chunks and leaves the old ones alone, so holding them is
## enough. An add, a subtract and an invert write into the chunks they find,
## so [method own_chunk] copies such a chunk on the GPU with `texture_copy`
## before the change's first write into it, and the selection goes on with
## the copy. The mask stays in VRAM (hard rule 1), and only a chunk the
## selection holds and the change writes into is copied (rule 3). The
## dictionaries start fresh for the same reason, since another step, Select
## Opaque's, may hold the ones the selection had.
##
## A change nested inside another records nothing, so the outer one is the one
## step, and a drop inside one is that step rather than a second. A change that
## leaves the selection as it was records nothing either: a deselect with
## nothing selected, a subtract from no selection, a reselect with nothing kept.
func change(title: String, work: Callable) -> Variant:
    if _depth > 0:
        return work.call()
    feather = feather.opened(self)
    var before := hold()
    _lay(feather.hard if feather.hard != null else before)
    _owned = {}
    _depth += 1
    var answer: Variant = work.call()
    _depth -= 1
    _owned = {}
    feather = feather.settled(self)
    var after := hold()
    if not after.differs_from(before):
        return answer
    var history: SaHistory = _history_of.call() if _history_of.is_valid() else null
    if history != null:
        history.commit_pair(title, _put_held.bind(after), _put_held.bind(before), before.bytes_not_in(after))
    return answer


## The chunk at *grid_pos* for a caller about to write into it in place, or
## null when the selection holds none there. Inside a [method change], a chunk
## the change has not written yet is copied first and the copy takes its
## place, because the step's way back holds the original.
func own_chunk(grid_pos: Vector2i) -> SaChunk:
    var existing: SaChunk = chunks.get(grid_pos, null)
    if existing == null or _depth == 0 or _owned.has(existing):
        return existing
    var copy := existing.duplicate_chunk()
    chunks[grid_pos] = copy
    _owned[copy] = true
    return copy


## The shape that made the selection while it still describes the mask, and
## null once a change has left it standing for chunks that are gone. A module
## holds the answer as a plain `RefCounted`, because the shape's class is
## inside this package and only the facade is named across its edge.
func standing_shape() -> SaSelectionShape:
    return shape if shape != null and shape.stands_in(self) else null


## Whether *point*, in document pixels, lies in the shape that made the
## selection, answered on the CPU with nothing read back. Where no shape
## stands, a selection added to, subtracted from, inverted or made by the
## wand, the answer is yes and the caller's own test of the bounds decides.
func shape_has_point(point: Vector2) -> bool:
    var made := standing_shape()
    return made == null or made.has_point(point)


## Keeps *was*, what [method standing_shape] answered before a carry of the
## outline by *by*, for the chunks the carry wrote, so a moved ellipse still
## knows its corners.
func carry_shape(was: RefCounted, by: Vector2i) -> void:
    var kept := was as SaSelectionShape
    shape = kept.moved(by, chunks) if kept != null else null


## Drops the selection when the change since *before* left it no chunks, the way
## [method deselect] does, and records the drop as one undo step that brings
## *before* back, which is what Krita does with a click of the marquee. Answers
## whether it dropped. A selection of nothing is never left standing, because
## every dab under it is clipped to nothing and no ants draw to say so.
func drop_if_empty(before: SaSelectionHeld) -> bool:
    if not active or not chunks.is_empty():
        return false
    _drop(before)
    return true


## Drops the selection as one undo step, for a click of a marquee that drew
## no shape. Nothing selected stays nothing and records nothing.
func drop() -> void:
    change(DROP_TITLE, deselect)


## Drops what an invert of a whole selection left, which is nothing. The invert
## wrote into the chunks it was given, so they hold zeros now and are neither
## the way back nor anything for Reselect to keep. What inverts to nothing over
## the canvas was everything over it, so the undo is a select all of
## *canvas_size*. Inside a [method change] the invert wrote into copies, so
## that change's step holds the selection as it was and is the way back.
func drop_inverted_whole(canvas_size: Vector2i) -> void:
    chunks = {}
    deselect()
    _record(select_all.bind(canvas_size), 0)


func _drop(before: SaSelectionHeld) -> void:
    deselect()
    if not before.holds_something():
        return
    # Kept for Reselect as a deselect keeps it, since the change that emptied
    # the selection is one the painter may not have meant.
    _kept_chunks = before.chunks.duplicate()
    _kept_boxes = before.boxes.duplicate()
    _kept_bounds = before.bounds
    var paid := 0
    for chunk: SaChunk in before.chunks.values():
        paid += chunk.byte_size()
    _record(_put_held.bind(before), paid)


## Records a drop as one step on the document's history, redone by a deselect
## and undone by *undo*. *paid* is what the step holds, in bytes. Nothing inside
## a [method change], whose own step is the one that undoes the drop.
func _record(undo: Callable, paid: int) -> void:
    if _depth > 0:
        return
    var history: SaHistory = _history_of.call() if _history_of.is_valid() else null
    if history != null:
        history.commit_pair(DROP_TITLE, deselect, undo, paid)


## Puts *state* back as the selection, either side of a step. An active
## selection of nothing is put back only while the quick mask is on to paint
## into it, because otherwise it clips every dab to nothing with no ants.
func _put_held(state: SaSelectionHeld) -> void:
    _lay(state)
    feather = state.feather
    shape = state.shape
    _kept_chunks = state.kept_chunks.duplicate()
    _kept_boxes = state.kept_boxes.duplicate()
    _kept_bounds = state.kept_bounds
    active = state.active and (editing or not chunks.is_empty())
    if not active:
        editing = false
    changed.emit()
    _whole = state.whole and active


## Lays the chunks, boxes and bounds *state* holds, in dictionaries of its own.
func _lay(state: SaSelectionHeld) -> void:
    chunks = state.chunks.duplicate()
    _boxes = state.boxes.duplicate()
    _bounds = state.bounds


## No selection: everything is selected again, and the chunks go.
##
## **What was selected is kept for `reselect`**, Krita's Ctrl+Shift+D, the way
## back past steps painted after the deselect, which an undo reaches only by
## undoing them. This records nothing itself. A deselect with nothing selected leaves the kept one
## alone, so a second stray click does not lose it. The dictionaries are let go
## of rather than cleared in place, because the kept ones are the same objects,
## and so is the one an undo step such as Select Opaque's holds as its before.
func deselect() -> void:
    if active and not chunks.is_empty():
        var kept := feather.hard_under(self, hold())
        _kept_chunks = kept.chunks
        _kept_boxes = kept.boxes
        _kept_bounds = kept.bounds
    active = false
    editing = false
    chunks = {}
    _boxes = {}
    _bounds = Rect2i()
    changed.emit()


## Deselects and lets the kept selection go as well, for a change that moves
## the picture under it. A crop and a resample leave the kept chunks on the old
## coordinates, and a reselect would bring them back over the wrong pixels.
func deselect_and_forget() -> void:
    deselect()
    _kept_chunks = {}
    _kept_boxes = {}
    _kept_bounds = Rect2i()


## Brings back what the last `deselect` dropped, in one step and exactly as it
## was. False when there is nothing to bring back.
func reselect() -> bool:
    if not can_reselect():
        return false
    chunks = _kept_chunks
    _boxes = _kept_boxes
    _bounds = _kept_bounds
    _kept_chunks = {}
    _kept_boxes = {}
    _kept_bounds = Rect2i()
    active = true
    changed.emit()
    return true


## Whether `reselect` has anything to bring back. Not while a selection
## stands, which a reselect would throw away: the next deselect keeps that one
## instead, as Krita's does.
func can_reselect() -> bool:
    return not active and not _kept_chunks.is_empty()


## Selects the whole canvas, chunk by chunk, so that an invert or a subtract
## later has something to work from.
func select_all(canvas_size: Vector2i) -> void:
    # Fresh dictionaries rather than cleared ones, because a step may hold these.
    chunks = {}
    _boxes = {}
    feather = feather.replaced(_depth)
    active = true
    for grid_pos: Vector2i in SaLayer.grid_positions(canvas_size):
        _chunk_at(grid_pos).clear(Color(1.0, 1.0, 1.0, 1.0))
    # Through the property, so the per-chunk boxes are the canvas clipped to each
    # chunk rather than each chunk whole. The last column and the last row of a
    # canvas that is not a multiple of 256 are shorter than the chunks holding
    # them, and a subtract off the bottom has to shrink from the canvas edge.
    bounds = Rect2i(Vector2i.ZERO, canvas_size)
    changed.emit()
    _whole = true


## Whether everything on every layer is selected by Select All, past the canvas
## edge too, so a copy, a cut and Layer via Copy take the whole layer as they
## do with no selection, while the chunks still cover the canvas for a subtract.
func selects_everything() -> bool:
    return active and _whole


## Selects a rectangle in document pixels. The rectangle's edges are exact:
## the kernel tests each pixel, so nothing spills to the workgroup boundary.
## *mode* is a Mode, and a bare `true` from an older caller reads as ADD.
func select_rect(rect: Rect2i, mode: int = Mode.REPLACE) -> void:
    _select_shape("select_rect", rect, mode)


## Selects the ellipse inscribed in *rect*, tested at each pixel's centre, or
## graded by coverage as [method select_polygon] is when *anti_alias* asks.
func select_ellipse(rect: Rect2i, mode: int = Mode.REPLACE, anti_alias: bool = false) -> void:
    _select_shape("select_ellipse", rect, mode, PackedVector2Array(), 1.0 if anti_alias else 0.0)


## Selects a polygon in document pixels by even-odd winding, so a self-crossing
## lasso leaves a hole where it crosses itself, the way Photoshop's does, and
## so do rings joined by [method SaSelectionRings.flatten]. The
## dirty region is the polygon's bounding box, never the canvas.
##
## *anti_alias* grades the edge by how much of each pixel the polygon covers,
## which is what the lasso asks for by default. Off, every pixel is wholly in
## or out, as the rectangle's are, and that is the default here and on the
## ellipse so a caller that does not ask keeps the mask it always had.
func select_polygon(points: PackedVector2Array, mode: int = Mode.REPLACE, anti_alias: bool = false) -> void:
    if points.size() < 3:
        return
    _select_shape("select_polygon", SaSelectionRings.box_of(points), mode, points, 1.0 if anti_alias else 0.0)


## Selects *rings*, closed outlines in document pixels, as one polygon in which
## a ring inside another is a hole, through [SaSelectionRings].
func select_rings(rings: Array, mode: int = Mode.REPLACE, anti_alias: bool = false) -> void:
    select_polygon(SaSelectionRings.flatten(rings), mode, anti_alias)


## What every shape does: settles the mode, then writes the shape's value into
## every chunk its box touches, over the box alone. *edge* is a polygon's or an
## ellipse's edge width in pixels, 1 to anti-alias and 0 for a hard edge.
func _select_shape(
    kernel: String, box: Rect2i, mode: int, points: PackedVector2Array = PackedVector2Array(), edge: float = 0.0
) -> void:
    if mode == Mode.SUBTRACT and not active:
        # Everything is selected and nothing holds it, so there is nothing to
        # take the shape out of.
        return
    if mode == Mode.INTERSECT and active:
        # A kernel writes one value inside the shape, which cannot keep only what
        # is selected already, so the shape goes into chunks of its own first.
        var region := {}
        var into_region := func(grid_pos: Vector2i) -> SaChunk:
            region[grid_pos] = make_chunk()
            return region[grid_pos]
        _write_shape(kernel, box, 1.0, into_region, points, edge)
        merge_region(region, mode)
        return
    var before := hold()
    var fresh := mode != Mode.SUBTRACT and (mode == Mode.REPLACE or not active)
    shape = null
    # Fresh dictionaries rather than cleared ones, because `before` and the kept
    # selection may be holding these.
    if mode == Mode.REPLACE or not active or (mode == Mode.SUBTRACT and kernel == "select_rect" and _takes_all(box)):
        chunks = {}
        _boxes = {}
        _bounds = Rect2i()
        feather = feather.replaced(_depth)
    active = true
    if box.size.x <= 0 or box.size.y <= 0 or (mode == Mode.SUBTRACT and chunks.is_empty()):
        if not drop_if_empty(before):
            changed.emit()
        return
    # Only a rectangle clears every pixel of the box it is given. An ellipse and
    # a polygon are tested per pixel inside theirs, so what came out is smaller
    # than the box and shrinking a chunk's own box by it would claim less
    # coverage than the mask holds.
    var exact_cut := kernel == "select_rect"
    # A subtract can only take the shape out of a chunk that holds something,
    # and every other mode writes into one, making it where it is missing.
    var chunk_at := func(grid_pos: Vector2i) -> SaChunk:
        if mode == Mode.SUBTRACT and not chunks.has(grid_pos):
            return null
        return _chunk_at(grid_pos)
    var value := 0.0 if mode == Mode.SUBTRACT else 1.0
    for grid_pos: Vector2i in _write_shape(kernel, box, value, chunk_at, points, edge):
        _note_shape(grid_pos, box, mode, exact_cut)
    _drop_empty_chunks()
    _refresh_bounds()
    if fresh:
        shape = SaSelectionShape.new(kernel, box, points, chunks)
    changed.emit()


## Writes *value* inside the shape into the chunk *chunk_at* answers for each
## grid position *box* touches, over the box alone, and answers the positions
## written.
func _write_shape(
    kernel: String, box: Rect2i, value: float, chunk_at: Callable, points: PackedVector2Array, edge: float
) -> Array:
    var buffer: SaCompute.Buffer = null
    if not points.is_empty():
        buffer = SaCompute.Buffer.new(points.to_byte_array())
    var size := SaChunk.SIZE
    # The shape arrives in the chunk's own texels, and the kernel is told where
    # the dispatch starts because it reads `global_id` as an offset from there.
    # A polygon's shape is its points, so the box's width word carries its edge
    # instead, and the count word carries the edge of a shape with no points. A
    # thirteenth float would pad the push constant to sixteen, and every other
    # caller of this shader sends twelve.
    var per_chunk := func(grid_pos: Vector2i, local: Rect2i, start: Vector2i) -> PackedFloat32Array:
        var local_box := Rect2i(box.position - grid_pos * size, box.size)
        return PackedFloat32Array(
            [
                local_box.position.x,
                local_box.position.y,
                float(local_box.size.x) if points.is_empty() else edge,
                local_box.size.y,
                value,
                float(start.x),
                float(start.y),
                float(points.size()) if not points.is_empty() else edge,
                float(grid_pos.x * size),
                float(grid_pos.y * size),
                float(local.end.x),
                float(local.end.y),
            ]
        )
    return walk().run(kernel, box, chunk_at, per_chunk, {BINDING_POINTS: buffer})


## Joins *region*, a fresh mask chunk per grid position and none where it holds
## nothing, to the selection in *mode*, the one merge the wand, a colour range
## and Select Opaque share. Records nothing, so a caller runs it inside
## [method change]. Every chunk kept is the region's or new, so a step's way
## back is never written into. The box is measured on the GPU, because a region
## is a shape inside its chunks, and a chunk the box misses goes.
func merge_region(region: Dictionary, mode: int) -> void:
    if mode == Mode.SUBTRACT and not active:
        # Everything is selected and nothing holds it, so there is nothing to
        # take the region out of. An intersect with everything is the region.
        return
    var before := hold()
    shape = null
    if mode == Mode.REPLACE or not active:
        chunks = region.duplicate()
        feather = feather.replaced(_depth)
    else:
        _meet(region, mode)
    active = true
    var box := measure_bounds()
    for grid_pos: Vector2i in chunks.keys():
        if not chunk_rect(grid_pos).intersects(box):
            chunks.erase(grid_pos)
    bounds = box
    if not drop_if_empty(before):
        changed.emit()


## Writes each chunk *region* and the selection share as the two met by *mode*'s
## kernel, into a fresh chunk. Where one side holds no chunk the other is
## unselected: an add takes the region's chunk, a subtract keeps the
## selection's, and an intersect has nothing there.
func _meet(region: Dictionary, mode: int) -> void:
    var kernel: String = {Mode.ADD: "unite", Mode.SUBTRACT: "combine", Mode.INTERSECT: "intersect"}[mode]
    if mode == Mode.INTERSECT:
        for grid_pos: Vector2i in chunks.keys():
            if not region.has(grid_pos):
                chunks.erase(grid_pos)
    var whole := Rect2i(0, 0, SaChunk.SIZE, SaChunk.SIZE)
    var params := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, whole.end.x, whole.end.y])
    for grid_pos: Vector2i in region:
        var existing: SaChunk = chunks.get(grid_pos, null)
        if existing == null:
            if mode == Mode.ADD:
                chunks[grid_pos] = region[grid_pos]
            continue
        var met: SaChunk = region[grid_pos]
        var out := make_chunk()
        var bindings: Dictionary[int, SaTexture] = {BINDING_BEFORE: existing.field(FIELD), BINDING_AFTER: met.field(FIELD)}
        dispatch(kernel, out.field(FIELD), whole, params, bindings)
        chunks[grid_pos] = out


## Whether a rectangle subtracted over *box* takes every chunk's coverage, known
## from the boxes before any kernel runs. Asked first because the subtract
## writes into the chunks in place, and a drop's undo needs them as they were.
## Every box is an over-estimate, so a rectangle that swallows them all leaves
## nothing for certain.
func _takes_all(box: Rect2i) -> bool:
    for grid_pos: Vector2i in chunks:
        var kept: Rect2i = _boxes.get(grid_pos, Rect2i())
        var left := without(kept, box.intersection(chunk_rect(grid_pos)))
        if left.size.x > 0 and left.size.y > 0:
            return false
    return true


## What *box* in *mode* does to the chunk at *grid_pos*'s own coverage box.
## *exact_cut* says the kernel clears every pixel of the box rather than a shape
## inside it, which is the only case a subtract may shrink anything on.
func _note_shape(grid_pos: Vector2i, box: Rect2i, mode: int, exact_cut: bool) -> void:
    var here := box.intersection(chunk_rect(grid_pos))
    if here.size.x <= 0 or here.size.y <= 0:
        return
    if mode != Mode.SUBTRACT:
        var had: Rect2i = _boxes.get(grid_pos, Rect2i())
        _boxes[grid_pos] = here if had.size == Vector2i.ZERO else had.merge(here)
        return
    if not exact_cut:
        return
    var kept: Rect2i = _boxes.get(grid_pos, Rect2i())
    var left := without(kept, here)
    if left.size.x <= 0 or left.size.y <= 0:
        _boxes.erase(grid_pos)
    else:
        _boxes[grid_pos] = left


## A chunk whose coverage box is gone holds nothing but zeros, so it stops being
## a chunk. `texture_for` then answers null there and a dispatcher skips it,
## which is what an unselected region is supposed to look like.
func _drop_empty_chunks() -> void:
    for grid_pos: Vector2i in chunks.keys():
        if not _boxes.has(grid_pos):
            chunks.erase(grid_pos)


## The union of every chunk's coverage box, which is what `bounds` reads.
func _refresh_bounds() -> void:
    var out := Rect2i()
    for box: Rect2i in _boxes.values():
        out = box if out.size == Vector2i.ZERO else out.merge(box)
    _bounds = out


## The tightest rectangle that certainly holds everything of *have* that *cut*
## did not take, in document pixels. Static so a test can ask without a document.
##
## A rectangle minus a rectangle is not a rectangle in general, so this answers
## only the three cases where it is: the cut misses, the cut swallows, and the
## cut spans one whole axis and reaches an end of the other, which is a strip off
## an edge. A cut through the middle of a box leaves two pieces and the answer is
## the box unchanged, which is honest rather than tight.
static func without(have: Rect2i, cut: Rect2i) -> Rect2i:
    var hit := have.intersection(cut)
    if hit.size.x <= 0 or hit.size.y <= 0:
        return have
    if hit.position.x <= have.position.x and hit.end.x >= have.end.x:
        var top := hit.position.y <= have.position.y
        var bottom := hit.end.y >= have.end.y
        if top and bottom:
            return Rect2i()
        if top:
            return Rect2i(have.position.x, hit.end.y, have.size.x, have.end.y - hit.end.y)
        if bottom:
            return Rect2i(have.position.x, have.position.y, have.size.x, hit.position.y - have.position.y)
        return have
    if hit.position.y <= have.position.y and hit.end.y >= have.end.y:
        var near := hit.position.x <= have.position.x
        var far := hit.end.x >= have.end.x
        if near:
            return Rect2i(hit.end.x, have.position.y, have.end.x - hit.end.x, have.size.y)
        if far:
            return Rect2i(have.position.x, have.position.y, hit.position.x - have.position.x, have.size.y)
    return have


## The rectangle the chunk at *grid_pos* covers, in document pixels.
static func chunk_rect(grid_pos: Vector2i) -> Rect2i:
    return Rect2i(grid_pos * SaChunk.SIZE, Vector2i(SaChunk.SIZE, SaChunk.SIZE))


## Every chunk position the selection holds, for whoever draws or saves it.
func grid_positions() -> Array:
    return chunks.keys()


## The chunk at *grid_pos*, made unselected everywhere when it is new. Public
## because the paint context paints into it while the quick mask is on.
##
## Handing the chunk out claims the whole of it, because whoever asked is about
## to write coverage this file cannot see: a dab lands where the brush says and
## nothing tells the selection where that was. A chunk-aligned over-estimate is
## the right answer and a box that misses painted coverage is not, which is what
## `bounds` did when nothing on this path wrote it at all. Shapes go through
## [method _chunk_at] instead and keep their exact box.
func get_or_create_chunk(grid_pos: Vector2i) -> SaChunk:
    feather = feather.painted()
    var chunk := _chunk_at(grid_pos)
    var whole := chunk_rect(grid_pos)
    if _boxes.get(grid_pos, Rect2i()) != whole:
        _boxes[grid_pos] = whole
        _refresh_bounds()
    return chunk


## The chunk at *grid_pos*, allocated and cleared when it is new, claiming
## nothing. For a caller that knows exactly what it is about to write, so an
## existing one comes through [method own_chunk].
func _chunk_at(grid_pos: Vector2i) -> SaChunk:
    var existing := own_chunk(grid_pos)
    if existing != null:
        return existing
    var chunk := SaChunk.create(schema())
    chunk.clear(Color(0.0, 0.0, 0.0, 0.0))
    chunks[grid_pos] = chunk
    if _depth > 0:
        _owned[chunk] = true
    return chunk


## A fresh mask chunk that belongs to nobody yet, for a filter's output.
func make_chunk(value: float = 0.0) -> SaChunk:
    var chunk := SaChunk.create(schema())
    chunk.clear(Color(value, value, value, value))
    return chunk


## The tight rectangle the coverage actually occupies, measured on the GPU.
##
## `bounds` is bookkeeping everywhere else: a shape writer knows the rectangle it
## drew and merges it in. A merged region, a subtract and an intersect cannot,
## because what survives is a shape inside the chunk rectangles, and shrinking
## by them would claim less coverage than the mask holds. So the pixels are
## reduced on the GPU, four atomics per covered texel, and four ints cross the
## bus, the read the base module's flood makes once per sweep. Hard rule 1 is
## about the canvas during a stroke, and this is a click that has finished. The
## empty rectangle when nothing is covered, as an empty selection's bounds is.
func measure_bounds() -> Rect2i:
    if chunks.is_empty():
        return Rect2i()
    var wide := PackedInt32Array([BOX_WIDE, BOX_WIDE, -BOX_WIDE, -BOX_WIDE])
    _box_buffer().update(wide.to_byte_array())
    var chunk_at := func(grid_pos: Vector2i) -> SaChunk: return chunks.get(grid_pos, null)
    var push := func(grid_pos: Vector2i, local: Rect2i, start: Vector2i) -> PackedFloat32Array:
        return PackedFloat32Array(
            [
                0.0,
                0.0,
                0.0,
                0.0,
                0.0,
                float(start.x),
                float(start.y),
                0.0,
                float(grid_pos.x * SaChunk.SIZE),
                float(grid_pos.y * SaChunk.SIZE),
                float(local.end.x),
                float(local.end.y),
            ]
        )
    # Every chunk whole, because the box has to answer for the whole mask and
    # not only for the part of it some rectangle covers.
    walk().run("bounds", SaChunkWalk.reach_of(chunks.keys()), chunk_at, push)
    var read := _box_buffer().read().to_int32_array()
    if read.size() < 4 or read[2] < read[0] or read[3] < read[1]:
        return Rect2i()
    return Rect2i(read[0], read[1], read[2] - read[0] + 1, read[3] - read[1] + 1)


## The box buffer, built on first use so a selection that never measures one
## allocates nothing.
func _box_buffer() -> SaCompute.Buffer:
    if _box == null:
        _box = SaCompute.Buffer.new(PackedInt32Array([BOX_WIDE, BOX_WIDE, -BOX_WIDE, -BOX_WIDE]).to_byte_array())
    return _box


## Runs one kernel of `selection.gmacs` on *texture* over *local*, a region in
## chunk-local pixels, dispatching only the workgroups it touches. *params* is
## the whole push constant less the dispatch offset, which is written here.
## *bindings* names what the neighbour and point bindings hold, and anything
## unnamed is bound to the stand-ins, because the uniform set covers the whole
## layout whichever kernel runs.
func dispatch(
    kernel: String, texture: SaTexture, local: Rect2i, params: PackedFloat32Array, bindings: Dictionary[int, SaTexture] = {}
) -> void:
    if texture == null or local.size.x <= 0 or local.size.y <= 0:
        return
    _get_compute()
    var workgroup := SaCompute.WORKGROUP_SIZE
    var start := Vector2i(
        floori(float(local.position.x) / workgroup) * workgroup, floori(float(local.position.y) / workgroup) * workgroup
    )
    var covered := Vector2i(local.end.x - start.x, local.end.y - start.y)
    params[5] = float(start.x)
    params[6] = float(start.y)
    _compute.use_storage_format(texture.format)
    _compute.set_texture(0, texture.rid)
    for binding: int in [BINDING_BEFORE, BINDING_SELF, BINDING_AFTER]:
        var bound: SaTexture = bindings.get(binding, null)
        _compute.set_texture(binding, (bound if bound != null else nothing()).rid)
    var buffer: SaCompute.Buffer = bindings.get(BINDING_POINTS, null)
    if buffer == null:
        buffer = _points_stand_in()
    _compute.set_buffer(BINDING_POINTS, buffer.rid)
    _compute.set_buffer(BINDING_BOX, _box_buffer().rid)
    _compute.set_push_constant_float_array(params)
    _compute.dispatch_kernel(kernel, SaCompute.groups_for(covered.x), SaCompute.groups_for(covered.y), 1)


## An [SaChunkWalk] over mask chunks, on this file's compute and with every
## binding of `selection.gmacs`'s layout filled in with a stand-in.
##
## A uniform set covers the whole layout whichever kernel runs, which is the
## reason [method dispatch] binds all five for one chunk, and this is the same
## answer for a walk: a caller names the neighbours or the points it actually
## reads and the rest are the stand-ins. The two doors sit beside each other on
## purpose, `dispatch` for one chunk and this for the chunks a rectangle
## touches, and a caller that has a rectangle should want this one.
func walk() -> SaChunkWalk:
    var stand_in := nothing()
    return (
        SaChunkWalk
        . new(
            _get_compute(),
            null,
            null,
            FIELD,
            {
                BINDING_BEFORE: stand_in,
                BINDING_SELF: stand_in,
                BINDING_AFTER: stand_in,
                BINDING_POINTS: _points_stand_in(),
                BINDING_BOX: _box_buffer(),
            }
        )
    )


## The compute every selection kernel runs on, built on first use so a selection
## that never dispatches allocates nothing.
func _get_compute() -> SaCompute:
    if _compute == null:
        _compute = SaCompute.new("selection")
    return _compute


## What binds at BINDING_POINTS when there is no polygon: two floats, because a
## uniform set covers the whole layout whichever kernel runs.
func _points_stand_in() -> SaCompute.Buffer:
    if _no_points == null:
        _no_points = SaCompute.Buffer.new(PackedFloat32Array([0.0, 0.0]).to_byte_array())
    return _no_points
