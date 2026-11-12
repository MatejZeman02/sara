## Moving what the transform tool's box covers, as one undo step.
##
## Beside `state_transform.gd` in the base module, because every caller of this
## file is that tool, and `module.gd` registers it under the `transform` role
## the way it registers the wand's flood.
##
## No kernel is new here. The lift is the pair `core/api/selection/sa_clipboard.gd` already uses, `copy_masked` into fresh
## chunks and `cut_masked` through the hole it leaves, so a feathered selection lifts a feathered piece and
## leaves a feathered hole, and the height half of the pair, `height_masked`, thins a ridge the same way.
## The offset is `shift` out of `shaders/compute/crop.gmacs`, whose push constant is a destination origin, a
## source origin and an extent, and the overlap arithmetic is `SaCrop._retile`'s, for a crop whose origin is
## not a multiple of the chunk edge.
##
## **The preview is the document's own stroke layer.** The lift cuts a real hole in the active layer and the
## moved pixels go into `stroke_layer`, which the compositor already draws over the active layer. So the hole
## is genuinely empty rather than painted over, the preview is the same maths the commit will be rather than
## a second path to keep in step with it, and the drag costs no readback: every frame is shift kernels into
## chunks that stay in VRAM.
##
## **Nothing is recorded until Enter.** A gesture is one history step: the lift keeps the snapshot of what it
## cut and the commit grows it over the landing through `SaChunkDelta.grown_to`, reading only the newly exposed
## bands off the live chunk rather than the whole thing, which would put the hole in the undo.
##
## The resampling kernel and the one matrix of all four gestures are below. What is here is the translate, the
## only one that moves texels without touching their values.
##
## **A live session lifts nothing.** On a smart layer, one that carries a live transform, with no selection,
## the tool opens one through `hold`, and `live/sa_transform_live.gd` draws each frame's map through the
## layer's own transform, so the layer's chunks never change. An ordinary layer takes the lift above, which
## resamples at Enter and leaves no transform pending, so there is no Apply Transform for the painter to
## press. A selection's lift and the freehand mesh keep the resample on a smart layer too, because a live
## transform moves the whole layer and a mesh is not a 3 by 3 map.
class_name SaTransform
extends RefCounted

## What the undo menu calls a committed transform.
const ACTION_NAME := "Transform"

## The smallest scale a handle can pull to. A scale of zero has no inverse and
## the map is handed to the kernel already inverted, so the drag stops here
## rather than dividing by nothing.
const MIN_SCALE: float = 0.01

var _document: SaDocument
var _layer: SaLayer = null

## Grid position -> SaChunk, the masked copy the lift took, in the coordinates
## it was taken from. The offset is applied on the way out rather than stored.
var _lifted: Dictionary = {}

## The rectangle the lift covered, in document pixels, where it stood before anything moved it.
var bounds: Rect2i = Rect2i()

## Grid position -> SaChunkDelta, or null where the active layer had no chunk
## at all, which `SaDocument.swap_pixels` round-trips as "remove it again".
var _before: Dictionary = {}

## Every stroke-layer position this gesture has allocated, so the whole set can be given back at the commit
## or the cancel.
##
## **Nothing is freed mid-drag**, which is the invariant `core/api/gpu/sa_texture.gd` states in its own header:
## freeing a texture bumps the epoch every cache keyed on a RID watches, and "textures are never freed
## mid-stroke, so the hot path sees this stand still". A chunk given back the moment the picture leaves it is
## recycled by Vulkan underneath a uniform set that still names it, and the drag then draws fragments of the
## stroke in chunks the picture has already left. Holding them costs one tile per position the drag passes
## over and they are all released together.
var _preview_chunks: Dictionary = {}

## Grid position -> the chunk-local rectangle the last frame wrote there, which is exactly what this frame
## has to erase.
##
## **Erased with `clear.gmacs` rather than with `texture_clear`.** A clear is a transfer and everything else
## here is compute, and the two are not ordered against each other on this driver, so a tile cleared that way
## can keep the texels the frame before shifted into it and a freshly allocated one the texels of whatever
## last owned that memory, which draws as fragments of the painting in several places at once. `clear_chunk`
## is a compute write of `vec4(0.0)` over a named rectangle, it is on the same queue as the shift, and it is
## over the rectangle that was written and nothing wider.
var _preview_written: Dictionary = {}

var _offset: Vector2i = Vector2i.ZERO

## Where the lifted picture is now, as one affine map from the box's own frame,
## which is document coordinates at the moment of the lift.
##
## **One matrix rather than an offset, a scale and an angle.** Those are three
## cases with a branch each, they have no room for the shear, and the kernel
## wants the inverse anyway: composing them per drag and inverting once is both
## shorter and the thing the GPU is handed. `preview_affine` is a builder over
## this, because a caller that only wants a scale should not have to write a
## `Transform2D` to ask for one. The option rows read the matrix, and it is the
## one place any gesture writes.
var matrix: Transform2D = Transform2D.IDENTITY
## The perspective map, nine numbers in row order, empty while the gesture is
## affine. It wins over `matrix` wherever both could answer, and every
## `preview_matrix` clears it.
var _homography: PackedFloat32Array = PackedFloat32Array()
## The warp's control points in document positions, Freehand's nine or the
## cage's dense grid, or empty while the map is a matrix or a homography. The
## three are exclusive: the last one asked for is the one that holds.
var _mesh: PackedVector2Array = PackedVector2Array()
## The mesh's points in the warp kernel's storage buffer, written at the first
## dispatch after the mesh moved and bound by every chunk's after it.
var _mesh_buffer: SaCompute.Buffer = null

var _preview_pending: bool = false

## The lifted layer's height field when a lifted chunk held some, and null
## otherwise. While it is set every preview chunk carries a height beside its
## colour, so the shift and the resample move the relief by the same map and
## filter as the paint, and the commit lays it down.
var _height_spec: SaFieldSpec = null

## Field id -> the whole lifted picture as one texture, built once per lift and
## only when a resample needs it.
##
## **One texture rather than the chunks it came from**, because a bilinear read
## at a chunk border needs the four texels around a position and two of them
## live in the neighbour, which is not bound. Sampling per chunk means a seam
## every 256 pixels, and every way of hiding one is worse than the tile this
## costs for the life of the gesture.
var _stitched: Dictionary = {}

## Which filter the resample reads with, as [SaResampleKernel.Filter]. A field
## rather than an argument because it is a setting of the gesture and not of one
## frame of it.
var filter: int = SaResampleKernel.Filter.BILINEAR

## The seven kernels a transform runs and the dispatches that drive them, cut
## out to `SaTransformKernels`, which owns them.
var _kernels: SaTransformKernels = SaTransformKernels.new()

## The three kernels the selection's carry runs at the commit, kept for the
## pass's life and made at the first lift that holds a selection. Apart from
## `_kernels` because the mask is `r32f` and those run at the document's depth.
var _mask_kernels: SaTransformSelection.Kernels = SaTransformSelection.Kernels.new()

## The live session open on `_layer`, set by `hold` and cleared with it, or
## null while there is none.
var _live: SaTransformLive = null
## The layer's mask lifted with the paint, null when the layer has none of its
## own chunks or nothing is lifted.
var _mask: SaTransformMask = null
## The move a text layer's recipe takes at Enter in place of the moved pixels,
## null for every other lift.
var _drawn: SaTransformDrawn = null


func _init(document: SaDocument) -> void:
    _document = document


## Whether a lift is live, so the tool knows Enter and Escape mean something.
func is_lifted() -> bool:
    return not _lifted.is_empty()


## Whether a live session is open, the other thing Enter and Escape end.
func is_held() -> bool:
    return _live != null


## Opens a live session on *layer* over *box*, its paint in its own pixels, at
## the map the layer is drawn through. True when the layer can take a live
## transform, and a sentence in the corner when it cannot.
func hold(layer: SaLayer, box: Rect2i) -> bool:
    cancel()
    _live = SaTransformLive.open(_document, layer, box)
    if _live == null:
        return false
    _layer = layer
    bounds = box
    var at := _live.at_rest(box)
    matrix = at[0]
    _homography = at[1]
    return true


## Whether the map has moved since the session opened: off the map the layer
## was drawn through for a live one, and off where the pixels were lifted for
## a lift. A perspective or a mesh counts as moved, since its affine part alone
## can read as the identity.
func has_moved() -> bool:
    if _live != null:
        return _live.has_moved(SaTransformLive.map_at(matrix, _homography))
    return is_lifted() and (is_perspective() or is_warped() or not matrix.is_equal_approx(Transform2D.IDENTITY))


## Where the lifted picture currently sits, relative to where it was taken.
func offset() -> Vector2i:
    return Vector2i(matrix.origin.round()) if _is_plain() else Vector2i((matrix * _centre() - _centre()).round())


## Puts the picture under *to*, which maps the box's own frame to the canvas.
##
## Clears any homography, because an affine map and a perspective one are two
## answers to the same question and the last one asked is the one that holds.
##
## *to* is held to a map with an inverse first, by `_held_matrix`, because a
## typed scale of nought and a side handle pulled onto the opposite side both
## arrive here flat, and the kernel's `affine_inverse` of a flat map prints an
## engine error and hands the forward map back.
func preview_matrix(to: Transform2D) -> void:
    if _drawn != null and not SaTransformDrawn.is_move(to):
        _drawn.refuse()
        return
    matrix = _held_matrix(to, _centre())
    _homography = PackedFloat32Array()
    _mesh = PackedVector2Array()
    _preview_pending = true


## Puts the picture under a homography, nine numbers in row order, which is the
## map a perspective drag needs and a `Transform2D` cannot hold.
##
## The affine matrix is kept in step with it, as the map through the box's own
## four corners, so ``matrix`` and the six Tool Options rows that read it still
## answer something true about where the picture is rather than going stale.
## False when the map is not kept, which a live session also says of one the
## layer's transform refuses, a horizon across the canvas.
func preview_homography(to: PackedFloat32Array) -> bool:
    if to.size() != 9 or is_zero_approx(to[8]):
        return false
    if _drawn != null:
        _drawn.refuse()
        return false
    if _live != null and _live.refuses(to):
        return false
    _homography = to.duplicate()
    _mesh = PackedVector2Array()
    matrix = SaHomography.affine_part(_homography, bounds, matrix)
    _preview_pending = true
    return true


## Puts the picture under a mesh of control points, Freehand's nine or the
## cage's grid, which neither a matrix nor a homography can hold.
##
## The affine matrix is kept in step with the four outer points the way it is
## with a homography, so the six Tool Options rows read something true, and
## the homography of those four is what the selection carries through at the
## commit: the mask follows the corners, and the tooth of the warp between
## them is the picture's alone. A live session takes none, since a layer's
## transform is a 3 by 3 map.
func preview_mesh(to: PackedVector2Array) -> void:
    if SaTransformMesh.side_of(to) == 0 or _live != null:
        return
    if _drawn != null:
        _drawn.refuse()
        return
    _mesh = to.duplicate()
    _mesh_buffer = null
    var corners := SaHomography.corners_to_quad(bounds, SaTransformMesh.corners_of(_mesh))
    _homography = PackedFloat32Array()
    if not corners.is_empty():
        matrix = SaHomography.affine_part(corners, bounds, matrix)
    _preview_pending = true


## Whether a mesh is in force, which is the one map the overlay draws as a
## grid rather than a quad.
func is_warped() -> bool:
    return SaTransformMesh.side_of(_mesh) > 0


## The mesh in force, for the overlay and a dump, empty when there is none.
func mesh() -> PackedVector2Array:
    return _mesh.duplicate()


## The frame's one dispatch, when a motion asked for one since the last.
func tick() -> void:
    if not _preview_pending:
        return
    _preview_pending = false
    _draw_preview()


## Whether a perspective map is in force, which is what makes ``matrix`` an
## approximation rather than the whole story.
func is_perspective() -> bool:
    return _homography.size() == 9


## Where the picture is now, as the axis-aligned box around it.
##
## A pure translate answers exactly, because a whole-pixel copy lands on whole
## pixels. Anything else answers one texel wider than the mapped corners, which
## is the skirt a bilinear read needs: the outermost texel of the lifted piece
## contributes to a texel just outside the mapped quad.
func landed_bounds() -> Rect2i:
    if bounds.size.x <= 0 or bounds.size.y <= 0:
        return Rect2i()
    if _is_plain():
        return Rect2i(bounds.position + Vector2i(matrix.origin.round()), bounds.size)
    if is_warped():
        # Every point and not the four corners: the centre dragged out past
        # them is picture too.
        return SaTransformMesh.bounds_of(_mesh)
    var corners := [
        _forward(Vector2(bounds.position)),
        _forward(Vector2(bounds.end.x, bounds.position.y)),
        _forward(Vector2(bounds.end)),
        _forward(Vector2(bounds.position.x, bounds.end.y)),
    ]
    var low: Vector2 = corners[0]
    var high: Vector2 = corners[0]
    for corner: Vector2 in corners:
        low = low.min(corner)
        high = high.max(corner)
    var origin := Vector2i(floori(low.x) - 1, floori(low.y) - 1)
    return Rect2i(origin, Vector2i(ceili(high.x) + 1, ceili(high.y) + 1) - origin)


## The four corners of the box as it currently stands, for the overlay to draw
## and for a test to check the arithmetic without a picture.
func landed_quad() -> PackedVector2Array:
    var quad := PackedVector2Array()
    if bounds.size.x <= 0 or bounds.size.y <= 0:
        return quad
    quad.append(_forward(Vector2(bounds.position)))
    quad.append(_forward(Vector2(bounds.end.x, bounds.position.y)))
    quad.append(_forward(Vector2(bounds.end)))
    quad.append(_forward(Vector2(bounds.position.x, bounds.end.y)))
    return quad


## A document position of the lifted picture, where it is now.
func _forward(at: Vector2) -> Vector2:
    if is_warped():
        return SaTransformMesh.through(_mesh, bounds, at)
    if is_perspective():
        return SaHomography.through(_homography, at)
    return matrix * at


## The box's centre in its own frame.
func _centre() -> Vector2:
    return Vector2(bounds.position) + Vector2(bounds.size) * 0.5


## Whether the map is a whole-pixel slide, which the shift kernel can do without
## reading between texels.
func _is_plain() -> bool:
    if is_perspective() or is_warped():
        return false
    if not matrix.x.is_equal_approx(Vector2.RIGHT) or not matrix.y.is_equal_approx(Vector2.DOWN):
        return false
    return matrix.origin.is_equal_approx(matrix.origin.round())


## A scale a handle pulled, held away from zero and keeping its sign, because a
## mirrored piece is a legal drag and an inverse of zero is not.
static func _held_scale(value: float) -> float:
    var direction := -1.0 if value < 0.0 else 1.0
    return direction * maxf(absf(value), MIN_SCALE)


## *to* with each axis held off nought as `_held_scale` holds a scale, and with
## the two axes held off one line, so the map always has an inverse. *pivot*
## lands where *to* put it, so a held map sits where the flat one would have.
##
## An axis pulled to nought has no direction left, so it takes the one square
## to the other axis that the identity has, and a map flat on both takes the
## identity's axes. Two axes on one line keep the first and lean the second off
## it, to the side it leant before or the identity's side, until the sine
## between them is `MIN_SCALE`. A map that already has an inverse comes back
## untouched, a mirror and a shear included.
static func _held_matrix(to: Transform2D, pivot: Vector2) -> Transform2D:
    var x := to.x
    var y := to.y
    if x.length() < MIN_SCALE and y.length() < MIN_SCALE:
        x = Vector2.RIGHT * MIN_SCALE
        y = Vector2.DOWN * MIN_SCALE
    elif x.length() < MIN_SCALE:
        x = y.orthogonal().normalized() * MIN_SCALE
    elif y.length() < MIN_SCALE:
        y = -x.orthogonal().normalized() * MIN_SCALE
    var sine := x.cross(y) / (x.length() * y.length())
    if absf(sine) < MIN_SCALE:
        var side := -1.0 if sine < 0.0 else 1.0
        var across := -x.orthogonal().normalized() * y.length()
        var along := x.normalized() * y.length()
        var cosine := 1.0 if along.dot(y) >= 0.0 else -1.0
        y = along * cosine * sqrt(1.0 - MIN_SCALE * MIN_SCALE) + across * side * MIN_SCALE
    if x == to.x and y == to.y:
        return to
    var landed := to * pivot
    return Transform2D(x, y, landed - Transform2D(x, y, Vector2.ZERO).basis_xform(pivot))


## Takes what *box* covers off *layer* and leaves the hole, honouring the
## selection. True when something was taken.
##
## The snapshot of every chunk it cuts is kept rather than committed, because
## the whole gesture is one step and the step is not final until Enter.
func lift(layer: SaLayer, box: Rect2i) -> bool:
    cancel()
    if _document == null or layer == null or box.size.x <= 0 or box.size.y <= 0:
        return false
    # A text layer is lifted as paint for the drag and moved in its recipe at
    # Enter, so the drawn kind's refusal of paint is not its answer.
    var drawn := SaTransformDrawn.of(layer)
    if drawn != null and _document.selection != null and _document.selection.active:
        drawn.refuse()
        return false
    if drawn == null and SaContext.refuse_paint(layer, TranslationServer.translate("transform")):
        return false
    if _kernels.copy() == null or _kernels.cut() == null:
        return false

    _layer = layer
    _drawn = drawn
    bounds = box
    var regions: Dictionary = {}
    for grid_pos: Vector2i in layer.chunks.keys():
        var local := _local_rect(grid_pos)
        if local.size.x <= 0 or local.size.y <= 0:
            continue
        var mask := _document.selection.texture_for(grid_pos)
        if mask == null:
            continue
        var live: SaChunk = layer.chunks[grid_pos]
        var taken := SaChunk.create(layer.schema, live.resolution_scale)
        taken.clear(Color(0.0, 0.0, 0.0, 0.0))
        for field_id: StringName in live.fields:
            var from: SaTexture = live.fields[field_id]
            var to: SaTexture = taken.field(field_id)
            if from != null and to == null and field_id == SaFieldSpec.HEIGHT:
                # A lazy field, which `create` leaves out.
                _height_spec = SaFieldSpec.find(layer.schema, field_id)
                to = taken.add_sparse_field(_height_spec)
            if from == null or to == null:
                continue
            if layer.is_color_field(field_id):
                _kernels.masked(_kernels.copy(), "copy_masked", from, mask, local, to)
            elif field_id == SaFieldSpec.HEIGHT:
                # Masked on the thickness itself, the way the clipboard takes it.
                _kernels.masked(_kernels.height(), "height_copy_masked", from, mask, local, to)
            else:
                # Whole, the way the clipboard takes one: a concentration has
                # no alpha to mask, and what a partial lift of such a field
                # means belongs to the layer type that introduces it. No layer
                # type introduces one today.
                var extent := Vector3(from.size.x, from.size.y, 1)
                GlobalShaderCompiler.get_rd().texture_copy(from.rid, to.rid, Vector3.ZERO, Vector3.ZERO, extent, 0, 0, 0, 0)
        _lifted[grid_pos] = taken

        _before[grid_pos] = SaChunkDelta.capture(live, local)
        for field_id: StringName in live.fields:
            if layer.is_color_field(field_id):
                _kernels.masked(_kernels.cut(), "cut_masked", live.fields[field_id], mask, local, null)
            elif field_id == SaFieldSpec.HEIGHT:
                _kernels.masked(_kernels.height(), "height_cut_masked", live.fields[field_id], mask, local, null)
        if _mask == null:
            _mask = SaTransformMask.of(_document, layer, box)
        if _mask != null:
            _mask.take(grid_pos, local, mask)
        layer.mark_unresolved(grid_pos)
        regions[grid_pos] = local

    if _lifted.is_empty():
        _layer = null
        _drawn = null
        _mask = null
        bounds = Rect2i()
        _before.clear()
        return false

    matrix = Transform2D.IDENTITY
    _homography = PackedFloat32Array()
    # The carry's kernels now rather than at Enter, so the frame the painter
    # commits in does not also wait on their pipelines. Once per pass: every
    # lift after the first finds them made.
    if _document.selection != null and _document.selection.active:
        _mask_kernels.prepare()
    _document.invalidate_chunk_regions(regions)
    _document.modified = true
    _document.document_changed.emit()
    return true


## Puts the lifted picture into the stroke layer, moved by *to*, with no scale
## and no rotation. Kept as its own entry point because a whole-pixel translate
## copies texels and never reads between them.
func preview(to: Vector2i) -> void:
    preview_affine(to, Vector2.ONE, 0.0)


## The same, built from a scale and a rotation about the box's centre.
##
## A builder over `preview_matrix`, because a caller that wants a scale
## should not have to write a `Transform2D` to ask for one.
func preview_affine(to: Vector2i, scale: Vector2, angle: float) -> void:
    if not is_lifted():
        return
    var held := Vector2(_held_scale(scale.x), _held_scale(scale.y))
    var basis := Transform2D(angle, Vector2.ZERO).scaled_local(held)
    var centre := _centre()
    preview_matrix(Transform2D(basis.x, basis.y, centre + Vector2(to) - basis.basis_xform(centre)))


## Draws the picture where `matrix` puts it.
##
## One dispatch per destination chunk either way, each over the rectangle that
## chunk actually receives and nothing wider, which is hard rule 2. A
## whole-pixel slide goes through `shift`, which copies a rectangle from one
## place to another, and everything else through `resample`, which reads between
## texels.
## **Not an [SaChunkWalk], because a stop here is not one dispatch.** A plain
## drag shifts each lifted chunk into up to four landed ones, so the work is a
## list of source-to-destination overlaps built first and run after, and one
## destination position appears in it several times. The perspective branch is
## a work list for the same reason the resampler's is: its dispatch belongs to
## `SaResampleKernel`. What the walk supplies is the grid arithmetic both
## branches would otherwise write out, `SaChunkWalk.positions_in` and
## `local_rect`.
func _draw_preview() -> void:
    if _live != null:
        _live.draw(SaTransformLive.map_at(matrix, _homography))
        return
    if not is_lifted() or _document == null or _document.stroke_layer == null:
        return
    var stroke := _document.stroke_layer
    var edge := SaLayer.CHUNK_SIZE
    var plain := _is_plain()
    if plain and _kernels.shift() == null:
        return
    if not plain and (_kernels.resample() == null or not _stitch()):
        return
    var to := Vector2i(matrix.origin.round())

    var wanted: Dictionary = {}
    var work: Array = []
    if plain:
        for source_pos: Vector2i in _lifted:
            var source_origin := source_pos * edge
            var taken := Rect2i(source_origin, Vector2i(edge, edge)).intersection(bounds)
            if taken.size.x <= 0 or taken.size.y <= 0:
                continue
            var landed := Rect2i(taken.position + to, taken.size)
            for grid_pos: Vector2i in SaChunkWalk.positions_in(landed):
                var overlap := landed.intersection(Rect2i(grid_pos * edge, Vector2i(edge, edge)))
                if overlap.size.x <= 0 or overlap.size.y <= 0:
                    continue
                var local := _texels(Rect2i(overlap.position - grid_pos * edge, overlap.size))
                var from := _texels(Rect2i(overlap.position - to - source_origin, Vector2i.ONE)).position
                wanted[grid_pos] = local.merge(wanted[grid_pos]) if wanted.has(grid_pos) else local
                work.append([source_pos, grid_pos, from, local.position, local.size])
    else:
        var reach := landed_bounds()
        for grid_pos: Vector2i in SaChunkWalk.positions_in(reach):
            var overlap := reach.intersection(Rect2i(grid_pos * edge, Vector2i(edge, edge)))
            if overlap.size.x <= 0 or overlap.size.y <= 0:
                continue
            var local := _texels(Rect2i(overlap.position - grid_pos * edge, overlap.size))
            wanted[grid_pos] = local
            work.append([grid_pos, local])

    var touched: Array = []
    for grid_pos: Vector2i in _preview_written:
        touched.append(grid_pos)
        var held: SaChunk = stroke.chunks.get(grid_pos, null)
        if held == null:
            continue
        _blank_part(held, _preview_written[grid_pos])
        stroke.mark_unresolved(grid_pos)
    for grid_pos: Vector2i in wanted:
        var fresh := _fresh_preview_chunk(stroke, grid_pos)
        var chunk := stroke.get_or_create_chunk(grid_pos, _scale())
        if _height_spec != null and not chunk.has_field(SaFieldSpec.HEIGHT):
            chunk.add_sparse_field(_height_spec)
        if fresh:
            # A whole tile, once, because a tile the drag has just entered is
            # freshly allocated memory and the clear `get_or_create_chunk` gives
            # it is the transfer this kernel exists to replace. Once per tile per
            # gesture rather than once per frame, which is what makes a tile-wide
            # dispatch affordable here.
            _blank_part(chunk, Rect2i(0, 0, chunk.pixel_size(), chunk.pixel_size()))
        _preview_chunks[grid_pos] = true
        if not _preview_written.has(grid_pos):
            touched.append(grid_pos)

    for entry: Array in work:
        var into: SaChunk = stroke.chunks.get(entry[0] if not plain else entry[1], null)
        if into == null:
            continue
        if plain:
            _kernels.shift_part(_lifted[entry[0]], into, entry[2], entry[3], entry[4])
        else:
            _resample_part(into, entry[0], entry[1])

    _preview_written = wanted
    for grid_pos: Vector2i in wanted:
        stroke.mark_unresolved(grid_pos)
    if _mask != null:
        for grid_pos: Vector2i in _mask.draw(wanted, _resample_with):
            if not touched.has(grid_pos):
                touched.append(grid_pos)
    _document.invalidate_chunks(touched)


## Writes the moved picture into the layer and records the whole gesture as one
## step. True when something was committed.
func commit() -> bool:
    if _live != null:
        tick()
        var live := _live
        _forget()
        return live.put()
    if not is_lifted() or _document == null or _layer == null:
        return false
    var stroke := _document.stroke_layer
    if stroke == null:
        cancel()
        return false
    if not is_perspective() and not is_warped() and matrix.is_equal_approx(Transform2D.IDENTITY):
        # Lifted and put down where it was. Restoring is the same picture and
        # costs no history step, and a step that changes nothing is worse than
        # no step: it is an undo the painter presses and nothing happens.
        # Perspective is exempt: its affine part is a reading of three corners,
        # so a drag of the fourth alone leaves it at the identity and Enter
        # would throw a visibly skewed picture away.
        cancel()
        return false
    if _drawn != null:
        return _land_drawn()

    # A tick may not have run since the motion that set this map.
    tick()

    var edge := SaLayer.CHUNK_SIZE
    var compositor := _document.injected_compositor()
    var touched: Array = []
    # The mask as the lift left it before anything is captured, so the step's
    # undo reads no frame's landing.
    if _mask != null:
        touched.append_array(_mask.restore())
    # The positions the last preview wrote to, not every position the drag
    # passed over: an empty tile the gesture merely visited would otherwise be
    # composited into the layer and left there, which is a chunk holding
    # nothing and hard rule 3 says there is no such chunk.
    for grid_pos: Vector2i in _preview_written.keys():
        var landing := landed_bounds().intersection(Rect2i(grid_pos * edge, Vector2i(edge, edge)))
        if landing.size.x <= 0 or landing.size.y <= 0:
            continue
        var local := _texels(Rect2i(landing.position - grid_pos * edge, landing.size))
        var live: SaChunk = _layer.chunks.get(grid_pos, null)
        if live == null:
            # No chunk here before, so the undo is "remove it again" rather
            # than a rectangle of transparency, and the grid stays sparse.
            _before[grid_pos] = null
            live = _layer.get_or_create_chunk(grid_pos)
            live.clear(Color(0.0, 0.0, 0.0, 0.0))
        elif _before.has(grid_pos) and _before[grid_pos] is SaChunkDelta:
            var held: SaChunkDelta = _before[grid_pos]
            _before[grid_pos] = held.grown_to(live, held.rect.merge(local))
        elif not _before.has(grid_pos):
            _before[grid_pos] = SaChunkDelta.capture(live, local)

        var stroke_chunk: SaChunk = stroke.chunks.get(grid_pos, null)
        if stroke_chunk == null:
            continue
        # Texel over texel: the preview's chunk is at the layer's own scale, so
        # a density of one rather than the two a 512 chunk reads as.
        var space := _document.color_space
        compositor.composite_chunk(
            live.albedo(), stroke_chunk.albedo(), SaLayer.BLEND_MODE.NORMAL, 1.0, Vector2.ZERO, space, 1.0, Rect2i(), 1.0
        )
        _land_height(live, stroke_chunk)
        if _mask != null:
            _mask.land(live, grid_pos, local, _resample_with)
        _layer.mark_unresolved(grid_pos)
        touched.append(grid_pos)

    var state := _before.duplicate()
    var into := _layer
    # The selection goes with the pixels it was holding, before `_forget` clears
    # the map and the bounds this reads, and under a perspective map too.
    # `SaTransformSelection` is a sibling rather than more of this file, so
    # reading the old mask happens there as well: what comes back is what the history step needs to
    # put the selection back with the pixels, or null if nothing moved. A warp's
    # mask follows its four corners: the homography through them is the nearest
    # thing to the mesh a mask kernel has a row for.
    var mask_map := _homography
    if is_warped():
        mask_map = SaHomography.corners_to_quad(bounds, SaTransformMesh.corners_of(_mesh))
    var selection_swap := SaTransformSelection.carry_and_hold(
        _document.selection, mask_map, matrix, bounds, landed_bounds(), filter, _mask_kernels
    )
    _release_preview()
    _forget()
    if _document.history != null:
        _document.record_pixel_step(ACTION_NAME, into, state, selection_swap)
    _document.invalidate_chunks(touched)
    _document.modified = true
    _document.document_changed.emit()
    return true


## Puts the lifted cache back and hands the move to the recipe, which draws
## the layer again where it lands. A map that is more than a move was refused
## as it was asked for, so one that reaches here anyway is refused again and
## lands nothing.
func _land_drawn() -> bool:
    var drawn := _drawn
    var by := matrix.origin
    var moved := not is_perspective() and not is_warped() and SaTransformDrawn.is_move(matrix)
    cancel()
    if not moved:
        drawn.refuse()
        return false
    return drawn.land(by)


## Lays the moved height into *live* by a mix, the layer's own paint moved,
## where Merge Down adds, `height_over` of `height.gmacs`: the height below goes
## towards the moved height by the moved paint's alpha, so moved flat paint
## covers a height below it too. A chunk gains its height only where either
## side holds some. After the capture, so undo has the chunk as it was.
func _land_height(live: SaChunk, moved: SaChunk) -> void:
    var spec := SaFieldSpec.find(_layer.schema, SaFieldSpec.HEIGHT)
    var above := moved.field(SaFieldSpec.HEIGHT)
    if spec == null or (above == null and not live.has_field(SaFieldSpec.HEIGHT)):
        return
    var below := live.field(SaFieldSpec.HEIGHT)
    if below == null:
        below = live.add_sparse_field(spec)
    _kernels.land_height(below, above, moved.albedo())


## Puts everything back where it was and forgets the lift, or draws a live
## session's layer at the map it opened on.
func cancel() -> void:
    if _live != null:
        var live := _live
        _forget()
        live.restore()
        return
    if not is_lifted():
        _release_preview()
        _forget()
        return
    var touched: Array = []
    if _mask != null:
        touched.append_array(_mask.restore())
    for grid_pos: Vector2i in _before:
        var held: Variant = _before[grid_pos]
        var live: SaChunk = _layer.chunks.get(grid_pos, null) if _layer != null else null
        if held is SaChunkDelta and live != null:
            (held as SaChunkDelta).apply_to(live)
            _layer.mark_unresolved(grid_pos)
        touched.append(grid_pos)
    _release_preview()
    _forget()
    if _document != null:
        _document.invalidate_chunks(touched)
        _document.document_changed.emit()


func _release_preview() -> void:
    if _document != null and _document.stroke_layer != null:
        for grid_pos: Vector2i in _preview_chunks:
            _document.stroke_layer.set_chunk(grid_pos, null)
        _document.invalidate_chunks(_preview_chunks.keys())
    _preview_chunks = {}
    _preview_written = {}


func _forget() -> void:
    _lifted.clear()
    _stitched.clear()
    matrix = Transform2D.IDENTITY
    _homography = PackedFloat32Array()
    _mesh = PackedVector2Array()
    _mesh_buffer = null
    _before.clear()
    _layer = null
    _height_spec = null
    bounds = Rect2i()
    _offset = Vector2i.ZERO
    _live = null
    _mask = null
    _drawn = null


## Builds the whole lifted picture as one texture per colour field and one of
## height when the lift took some, once per lift. True when there is something to resample from.
func _stitch() -> bool:
    if not _stitched.is_empty():
        return true
    if bounds.size.x <= 0 or bounds.size.y <= 0 or _kernels.shift() == null:
        return false
    var edge := SaLayer.CHUNK_SIZE
    for source_pos: Vector2i in _lifted:
        var source: SaChunk = _lifted[source_pos]
        var source_origin := source_pos * edge
        var taken := Rect2i(source_origin, Vector2i(edge, edge)).intersection(bounds)
        if taken.size.x <= 0 or taken.size.y <= 0:
            continue
        for field_id: StringName in source.fields:
            if _layer != null and not _layer.is_color_field(field_id) and field_id != SaFieldSpec.HEIGHT:
                continue
            var from: SaTexture = source.fields[field_id]
            if from == null or not from.rid.is_valid():
                continue
            var into: SaTexture = _stitched.get(field_id, null)
            if into == null:
                var whole := _texels(Rect2i(Vector2i.ZERO, bounds.size))
                into = SaTexture.new(whole.size, from.format)
                # Through the kernel, for the reason `_preview_written` gives:
                # this is fresh memory and its own clear is a transfer nothing
                # orders against the shifts below.
                _kernels.blank_texture(into, whole)
                _stitched[field_id] = into
            var part := _texels(Rect2i(taken.position - source_origin, taken.size))
            var at := _texels(Rect2i(taken.position - bounds.position, Vector2i.ONE)).position
            _kernels.shift_texture(from, into, part.position, at, part.size)
    return not _stitched.is_empty()


## One resample dispatch: *local* of the chunk at *grid_pos*, read out of the
## stitched picture through the inverse of the map the handles are driving.
func _resample_part(into: SaChunk, grid_pos: Vector2i, local: Rect2i) -> void:
    if _kernels.resample() == null or local.size.x <= 0 or local.size.y <= 0:
        return
    for field_id: StringName in into.fields:
        var curve := SaResampleKernel.curve_for(_document.color_space, field_id)
        _resample_with(
            _kernels.resample(), _kernels.warp(), into.fields[field_id], _stitched.get(field_id, null), grid_pos, local, curve
        )


## Draws *source*, a texture over the whole lifted box, into *local* of
## *target*, the chunk at *grid_pos*, through the map, with *compute* for an
## affine or perspective map and *warp* for the mesh, in linear light by
## *curve*. The mask's carry draws through it too, with kernels at its own
## format and the identity curve.
func _resample_with(
    compute: SaCompute,
    warp: SaCompute,
    target: SaTexture,
    source: SaTexture,
    grid_pos: Vector2i,
    local: Rect2i,
    curve := SaResampleKernel.IDENTITY
) -> void:
    if compute == null or local.size.x <= 0 or local.size.y <= 0:
        return
    # The inverse of the one map, as the four pieces the kernel's push constant
    # wants, so it does no matrix work per texel and knows nothing about angles,
    # scales or the horizon. `SaHomography` owns that arithmetic for the affine
    # gesture and the perspective one alike, and `SaResampleKernel` is the one
    # place the push constant is written.
    # *local* is in the chunk's texels, so the map is taken into texels too:
    # every position times the layer's scale, which leaves the linear part of
    # an affine map as it was.
    var t := _scale()
    var world := Vector2(grid_pos * SaLayer.CHUNK_SIZE) * t
    var nearest := filter == SaResampleKernel.Filter.NEAREST
    if is_warped():
        if _mesh_buffer == null:
            _mesh_buffer = SaWarpKernel.points_buffer(_mesh, t)
        var side := SaTransformMesh.side_of(_mesh)
        SaWarpKernel.dispatch(warp, target, source, _mesh_buffer, side, world, local, nearest, curve)
        return
    var texel_matrix := Transform2D(matrix.x, matrix.y, matrix.origin * t)
    var rows := SaHomography.kernel_rows(_texel_homography(t), texel_matrix, Vector2(bounds.position) * t)
    SaResampleKernel.dispatch(compute, target, source, rows, world, local, nearest, curve)


## The part of `bounds` that lies in the chunk at *grid_pos*, in the lifted
## layer's texels.
func _local_rect(grid_pos: Vector2i) -> Rect2i:
    return SaChunkWalk.local_rect(grid_pos, bounds, roundi(SaChunk.SIZE * _scale()))


## The lifted layer's texels a document pixel: 2.0 on a double resolution
## layer, whose chunks are 512 texels over 256 document pixels, and 1.0 on any
## other or with nothing lifted. Everything the gesture reads, `bounds`, the
## map and the mesh, is in document pixels, and every dispatch is in texels.
func _scale() -> float:
    return _layer.resolution_scale if _layer != null else 1.0


## *rect*, in document pixels, in the lifted layer's texels.
func _texels(rect: Rect2i) -> Rect2i:
    var t := _scale()
    if is_equal_approx(t, 1.0):
        return rect
    var start := Vector2i((Vector2(rect.position) * t).floor())
    return Rect2i(start, Vector2i((Vector2(rect.end) * t).ceil()) - start)


## The perspective map in texels, `S H S^-1` with S scaling by *t*: the
## translation grows by *t* and the third row's first two entries shrink by it.
## Empty when the gesture has no perspective map.
func _texel_homography(t: float) -> PackedFloat32Array:
    if _homography.size() != 9 or is_equal_approx(t, 1.0):
        return _homography
    var h := _homography.duplicate()
    h[2] *= t
    h[5] *= t
    h[6] /= t
    h[7] /= t
    return h


## Whether the stroke layer's chunk at *grid_pos* has to be made for this
## preview: there is none, or one at another scale than the lifted layer's,
## which is let go so the preview's chunk matches the layer it lands in.
func _fresh_preview_chunk(stroke: SaLayer, grid_pos: Vector2i) -> bool:
    var held: SaChunk = stroke.chunks.get(grid_pos, null)
    if held == null:
        return true
    if is_equal_approx(held.resolution_scale, _scale()):
        return false
    stroke.set_chunk(grid_pos, null)
    return true


## Writes transparency over *local* of every field of *chunk*.
func _blank_part(chunk: SaChunk, local: Rect2i) -> void:
    for field_id: StringName in chunk.fields:
        _kernels.blank_texture(chunk.fields[field_id], local)
