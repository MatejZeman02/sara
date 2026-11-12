## The `path` step: a closed polygon or a circle in document pixels, filled
## with the foreground colour on the active layer as one undo step.
##
## Without it a client has no fill for a shape, and builds a circle out of stacked rows of short strokes and a
## head out of widening rows, dozens of steps for one shape. This is one.
##
## **Nothing here is a new kernel.** The shape is drawn by the selection's own
## `select_polygon` and `select_ellipse`, softened by its own feather, and
## painted by `shaders/compute/fill.gmacs`, the masked fill every selection
## already fills through. The steps are the bucket fill's, in
## `modules/sara-base-modules/base/tools/state_bucket_fill.gd`, with a shape
## where that tool has a flood:
##
## 1. The painter's selection is put aside and the shape is selected in its
##    place, so the selection kernels draw it into mask chunks.
## 2. With antialiasing on, which is the default, the mask is feathered by one
##    texel, and only the chunks the shape itself entered are kept, for the
##    reason the bucket fill gives: the feather rounds its reach out to whole
##    chunks and would otherwise paint a column of colour at a seam.
## 3. The painter's selection goes back exactly as it was, the same dictionary,
##    the same bounds and the same flags.
## 4. With `inside_selection` the shape's mask is met with the painter's, the
##    minimum of the two, the way a stroke takes the selection as a clip. The
##    meeting is done by a scratch selection of its own, so the painter's mask
##    is read and never written, and no step lands in the selection's history.
## 5. Each chunk the shape reached is allocated on the layer and dispatched
##    through `fill` with that chunk's mask, which is hard rules 2 and 3 at once:
##    a small shape allocates and writes the chunks it covers and no others.
## 6. One undo step, `Path`.
##
## The shape is filled whole unless `inside_selection` asks for the clip. The
## step names the region itself, which is what a `select` followed by the Edit
## menu's fill would do, since that `select` replaces the selection, and the
## scripts that rely on that keep working. A whole fill over an active selection
## that does not name the key counts the pixels it laid outside the selection,
## and the answer says how many. That count is the one kernel of this step's
## own, `path_outside.gmacs` beside this file, since no kernel of the selection
## counts.
##
## Static, like the capture steps the table prints, and it
## holds nothing between steps. The `fill` pipeline is built per step, whose
## shader the compiler has already cached, and a scenario fills a handful of
## shapes rather than one a frame.
class_name SaScenarioPath
extends RefCounted

const CanvasDriver := preload("res://harness/drivers/sa_canvas_driver.gd")

## The name the undo history shows for a path fill.
const ACTION: String = "Path"

## The kernel that counts what the fill laid outside the painter's selection,
## and the file beside this one it is in, by the name `SaCompute` finds it by.
const OUTSIDE_SHADER: String = "path_outside"
const OUTSIDE_KERNEL: String = "path_outside"
## Where `path_outside.gmacs` reads the painter's mask and adds its counts.
## Binding 0 is the shape's own mask chunk, which the walk binds.
const BINDING_SELECTED: int = 1
const BINDING_TALLY: int = 2

## The two things a fill answers, the chunks it wrote and the pixels it laid
## outside the selection.
const LAID_CHUNKS: String = "chunks"
const LAID_OUTSIDE: String = "outside"


## Fills a polygon or a circle: a closed polygon by even-odd winding with
## `{"path": {"polygon": [[x, y], ...]}}`, and a circle with `{"path": {"circle":
## [cx, cy, r]}}`, both in document pixels, with the foreground colour on the main
## document's active layer as one undo step, whole, with the pixels it laid
## outside an active selection counted in its answer, or clipped to the painter's
## selection when `"inside_selection": true` is given, and hard edged when
## `"antialias": false` is, which is the edge a retouch wants, since
## `{"path": {"polygon": [[700, 694], [701, 694], [701, 695], [700, 695]],
## "antialias": false}}` lays the one pixel at (700, 694) in the whole colour and
## leaves every pixel beside it as it was. The edge is soft by default, graded
## over about a pixel, which suits a shape and not a pixel: the square above at
## the soft edge lays a ninth of its colour on that pixel and as much again on
## each of its eight neighbours. A polygon tests each pixel's centre, so a square whose corners sit
## on pixel lines covers exactly the pixels inside it. The clip keeps only the
## part of the shape inside the selection, as a stroke is clipped by it, and
## fills the whole shape when nothing is selected. The selection is left as it
## was found. Answers the line the step prints, which a whole fill over an active
## selection ends with `, and laid paint at N pixel(s) outside the selection`
## when it did, N being the pixels the clip would have laid less on. A spec that
## names `inside_selection`, true or false, is not told.
##
## **Arguments.**
## - `polygon` array, `[[x, y], ...]` in document pixels.
## - `circle` array, `[cx, cy, r]` in document pixels.
## - `antialias` boolean, false for a hard edge.
## - `inside_selection` boolean, true to fill only inside the painter's selection.
static func path(spec: Dictionary) -> String:
    var canvas := CanvasDriver.main_canvas()
    if canvas == null or canvas.document == null:
        push_warning("SaCapture: path failed, no document to fill on")
        return "SaCapture: path filled nothing"
    var line := answer(canvas.document, spec)
    canvas.request_composite()
    return line


## Fills the shape *spec* names on *document*'s active layer and answers the
## line the step prints: the chunks it wrote and, when it painted outside an
## active selection with no `inside_selection` in *spec*, how many pixels.
##
## The count is there because the shape fills whole by default, and without it
## nothing says the fill has gone past the selection. The default stays, so a
## recorded scenario lays what it was written to lay, and the answer says what
## it laid outside. A pixel counts
## where the shape lays more than the selection lets through, which is where the
## clip would have laid less, so a pixel on a selection's soft rim counts when
## the shape covers it more than the selection does. A spec that names the key,
## true or false, has said what it wants and is not told.
static func answer(document: SaDocument, spec: Dictionary) -> String:
    var laid := _lay(document, spec)
    var line := "SaCapture: path %s filled %d chunk(s)" % [JSON.stringify(spec), laid[LAID_CHUNKS]]
    var outside := int(laid[LAID_OUTSIDE])
    if outside > 0:
        line += ', and laid paint at %d pixel(s) outside the selection, which "inside_selection": true keeps out' % outside
    return line


## Fills the shape *spec* names on *document*'s active layer and answers the
## number of chunks it wrote. Zero when the spec names no shape, the layer is
## locked or generated, the shape lies off the canvas, or `inside_selection`
## leaves nothing of it inside the selection. The door the suites call, with
## [method answer] the one the step goes through.
static func fill(document: SaDocument, spec: Dictionary) -> int:
    return int(_lay(document, spec)[LAID_CHUNKS])


## The fill itself, answering what [method answer] prints: the chunks written
## at `LAID_CHUNKS` and the pixels laid outside the selection at `LAID_OUTSIDE`.
static func _lay(document: SaDocument, spec: Dictionary) -> Dictionary:
    var laid := {LAID_CHUNKS: 0, LAID_OUTSIDE: 0}
    var layer := document.active_layer
    if layer == null or (("is_locked" in layer) and layer.is_locked):
        push_warning("SaCapture: path failed, no unlocked active layer")
        return laid
    if layer.is_generated():
        # A background is a kernel's output and stores no chunks to fill.
        push_warning("SaCapture: path failed, the active layer is generated and holds no paint")
        return laid
    var region := _region(document, spec)
    if region.is_empty():
        return laid
    if document.selection.active and not spec.has("inside_selection"):
        laid[LAID_OUTSIDE] = _outside(document.selection, region)
    laid[LAID_CHUNKS] = _paint(document, layer, region)
    return laid


## The pixels of *region*, the shape's mask chunks, that lay more paint than
## *selection* lets through, counted by `path_outside.gmacs` beside this file.
## One slot a chunk, read back as one uint each, and each weighed by its chunk's
## own texels a pixel (hard rule 3), so the answer is in document pixels.
static func _outside(selection: SaSelection, region: Dictionary) -> int:
    var slots: Dictionary = {}
    for grid_pos: Vector2i in region:
        slots[grid_pos] = slots.size()
    var zeros := PackedInt32Array()
    zeros.resize(slots.size())
    zeros.fill(0)
    var tally := SaCompute.Buffer.new(zeros.to_byte_array())
    var stand_in := selection.nothing()
    var defaults: Dictionary[int, Variant] = {BINDING_SELECTED: stand_in, BINDING_TALLY: tally}
    var walk := SaChunkWalk.new(SaCompute.new(OUTSIDE_SHADER), null, null, SaSelection.FIELD, defaults)
    var chunk_at := func(grid_pos: Vector2i) -> SaChunk: return region.get(grid_pos, null)
    var push := func(grid_pos: Vector2i, local: Rect2i, start: Vector2i) -> PackedFloat32Array:
        return PackedFloat32Array(
            [
                float(start.x),
                float(start.y),
                float(local.end.x),
                float(local.end.y),
                float(slots[grid_pos]),
                0.0,
                0.0,
                0.0,
            ]
        )
    # The painter's chunk where it holds one, and the stand-in, which reads as
    # nothing, where it does not, since an active selection with no chunk at a
    # position has nothing selected there.
    var held_at := func(grid_pos: Vector2i) -> Dictionary: return {BINDING_SELECTED: selection.texture_for(grid_pos)}
    walk.run(OUTSIDE_KERNEL, SaChunkWalk.reach_of(region.keys()), chunk_at, push, held_at)
    var counts := tally.read().to_int32_array()
    var outside := 0.0
    for grid_pos: Vector2i in slots:
        var side := (region[grid_pos] as SaChunk).pixel_size()
        outside += float(counts[slots[grid_pos]]) * float(SaChunk.SIZE * SaChunk.SIZE) / float(side * side)
    return roundi(outside)


## The shape's coverage as `{grid_pos: SaChunk}` of mask chunks, drawn by the
## document's selection and handed back with the selection as it was.
static func _region(document: SaDocument, spec: Dictionary) -> Dictionary:
    var selection := document.selection
    var kept_chunks: Dictionary = selection.chunks
    var kept_bounds: Rect2i = selection.bounds
    var kept_active: bool = selection.active
    var kept_editing: bool = selection.editing

    # A dictionary of its own, because the replace inside the shape call clears
    # the one it finds, and that one is the painter's.
    selection.chunks = {}
    selection.active = false
    if not _select(selection, spec):
        push_warning('SaCapture: path needs {"polygon": [[x, y], ...]} with three points or more, or {"circle": [cx, cy, r]}')
    var entered: Array = selection.chunks.keys()
    if not entered.is_empty() and bool(spec.get("antialias", true)):
        SaSelectionFilters.feather(selection, 1, document.canvas_size)
    var region: Dictionary = {}
    for grid_pos: Vector2i in entered:
        if selection.chunks.has(grid_pos):
            region[grid_pos] = selection.chunks[grid_pos]

    selection.chunks = kept_chunks
    selection.active = kept_active
    # After the chunks, because writing the bounds rebuilds the per-chunk boxes
    # from whatever the chunks are at that moment.
    selection.bounds = kept_bounds
    selection.editing = kept_editing
    selection.changed.emit()
    if kept_active and bool(spec.get("inside_selection", false)):
        return _inside(region, kept_chunks)
    return region


## *region* met with *painters*, the painter's own mask chunks, as the minimum of
## the two at each texel, so the shape's soft edge and the selection's both
## survive. Done in a selection of its own that has no history to record on and
## nobody to announce to, since a merge into the painter's would write into its
## state. *painters* is only read. A position one side holds no chunk at has
## nothing selected there, so the answer has no chunk at it.
static func _inside(region: Dictionary, painters: Dictionary) -> Dictionary:
    var scratch := SaSelection.new()
    scratch.chunks = region.duplicate()
    scratch.active = true
    scratch.merge_region(painters, SaSelection.Mode.INTERSECT)
    return scratch.chunks


## Draws the shape *spec* names into *selection*, answering false when it names
## none that can be drawn.
static func _select(selection: SaSelection, spec: Dictionary) -> bool:
    if spec.has("circle"):
        var circle := spec["circle"] as Array
        if circle == null or circle.size() < 3 or float(circle[2]) <= 0.0:
            return false
        var centre := Vector2(float(circle[0]), float(circle[1]))
        var radius := float(circle[2])
        var low := Vector2i(roundi(centre.x - radius), roundi(centre.y - radius))
        var high := Vector2i(roundi(centre.x + radius), roundi(centre.y + radius))
        selection.select_ellipse(Rect2i(low, high - low))
        return true
    if spec.has("polygon"):
        var pairs := spec["polygon"] as Array
        if pairs == null or pairs.size() < 3:
            return false
        var points := PackedVector2Array()
        for pair: Variant in pairs:
            var xy := pair as Array
            if xy == null or xy.size() < 2:
                return false
            points.append(Vector2(float(xy[0]), float(xy[1])))
        selection.select_polygon(points)
        return true
    return false


## Paints *region* onto *layer* with the foreground colour through the masked
## fill, one chunk of mask per stop, and records it as one step.
static func _paint(document: SaDocument, layer: SaLayer, region: Dictionary) -> int:
    # Into the document's own encoding, the way the brush and the bucket fill
    # take it, so an Oklab document gets the colour the swatch shows.
    var space := document.color_space
    var colour: Color = space.from_display(SaColors.foreground) if space != null else SaColors.foreground
    var undo_data: Dictionary = {}
    for grid_pos: Vector2i in region:
        undo_data[grid_pos] = layer.duplicate_chunk(grid_pos) if layer.chunks.has(grid_pos) else null

    var alpha_lock := 1.0 if layer.alpha_locked else 0.0
    var params := PackedFloat32Array([colour.r, colour.g, colour.b, colour.a, alpha_lock, 0.0, 0.0, 0.0])
    layer.mark_all_unresolved()
    var chunk_at := func(grid_pos: Vector2i) -> SaChunk:
        return layer.get_or_create_chunk(grid_pos) if region.has(grid_pos) else null
    var same := func(_g: Vector2i, _l: Rect2i, _s: Vector2i) -> PackedFloat32Array: return params
    var mask_of := func(grid_pos: Vector2i) -> Dictionary:
        return {SaSelection.BINDING: (region[grid_pos] as SaChunk).field(SaSelection.FIELD)}
    # The kernel reads `global_id` as the chunk-local pixel, so the walk is given
    # whole chunks, which the reach of the region's positions is.
    var walk := SaChunkWalk.new(SaCompute.new("fill"), null, layer)
    var touched := walk.run("fill", SaChunkWalk.reach_of(region.keys()), chunk_at, same, mask_of).size()

    document.record_pixel_step(ACTION, layer, undo_data)
    document.invalidate_chunks(region.keys())
    document.modified = true
    document.document_changed.emit()
    return touched
