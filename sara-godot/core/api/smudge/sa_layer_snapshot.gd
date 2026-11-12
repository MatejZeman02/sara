## The layer snapshot: a stroke's read of the layer it paints on.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The other source for the smudge stage's pickup.** [SaMergedSnapshot] copies
## the composite, which is Krita's overlay mode and the stage's default. A
## brush with Sample Merged off reads the active layer alone,
## so a smudge on a layer above a painting drags only what that layer holds and
## not what shows through it. The two classes share a surface rather than a
## base, on purpose: the layer source is a second reader of the same idea and
## not a mode on the composite's copy. It sits in the door beside the
## reservoir, because both brush engines smudge.
##
## **One `texture_copy` per chunk cell under the rectangle**, the dirty-rect
## discipline of hard rule 2 applied to a copy like the composite's. A cell the
## layer has no chunk in is left transparent rather than copied, which is what a
## dab over unpainted canvas has to read as: nothing, not the layer below. The
## texture is cleared first because a fresh [SaTexture] is undefined rather than
## blank, and it is sized to the rectangle rather than to the canvas.
##
## **A cell the stroke has just painted is copied when the snapshot first
## reaches it**, so the pickup over fresh paint reads the stroke's own dabs
## rather than what stood there before the stroke. That is the difference
## between reading a layer and reading a snapshot of one, and it is the reason
## the composite is the default: a layer is live where the composite's copy is
## taken once and grown by the cell.
##
## RAII: the texture is a [SaTexture] and the snapshot is a [RefCounted], so
## whoever asked for it holds the one reference and dropping it at the end of
## the stroke frees the VRAM with it (hard rule 4).
class_name SaLayerSnapshot
extends RefCounted

## The copy, sized exactly to `rect` times `scale`. Local texel (0, 0) is
## document pixel `rect.position`.
var texture: SaTexture = null

## The document rectangle the copy covers, clipped to the canvas.
var rect: Rect2i = Rect2i()

## Texels along one document pixel of the copy: the layer's own scale, 2.0 for
## a double resolution layer, whose chunks are copied texel for texel into a
## copy at their density rather than averaged. A smudge on
## such a layer picks up the detail it drags.
var scale: float = 1.0

## How many chunk cells have been copied from the layer so far, one per cell
## that holds a chunk, so a test can hold it to the chunk count rather than
## trust that no copy was of the whole canvas.
var chunk_copies: int = 0

## The layer whose albedo is copied. Held as the layer rather than as a field,
## because a field is created with the chunk and the chunk a growth reaches may
## not exist yet.
var _layer: SaLayer = null


## A snapshot of *layer*'s albedo under *wanted*, clipped to the document's
## canvas. A layer in no document is not clipped, which is what a test building
## one by hand gets.
func _init(layer: SaLayer, wanted: Rect2i) -> void:
    _layer = layer
    if _layer == null:
        return
    scale = maxf(_layer.resolution_scale, 1.0)
    var clipped := _clip(wanted)
    if clipped.size.x <= 0 or clipped.size.y <= 0:
        return
    rect = clipped
    texture = SaTexture.new(_texels(rect.size), _format())
    texture.clear(Color(0.0, 0.0, 0.0, 0.0))
    _copy_cells(rect, Rect2i())


## Grows the snapshot to take *wanted* in, keeping what it already holds.
##
## The old copy moves into the new texture by one GPU to GPU copy and only the
## cells of the new area outside it are copied from the layer, so a stroke that
## wanders one chunk to the right pays for one chunk. The cells already held
## keep the picture they were taken with, which is the point of a snapshot: the
## stroke reads what stood before it, not what it has painted since. A rectangle
## already covered costs nothing.
func grow(wanted: Rect2i) -> void:
    if _layer == null:
        return
    var clipped := _clip(wanted)
    if clipped.size.x <= 0 or clipped.size.y <= 0:
        return
    if texture != null and rect.encloses(clipped):
        return
    if texture == null:
        rect = clipped
        texture = SaTexture.new(_texels(rect.size), _format())
        texture.clear(Color(0.0, 0.0, 0.0, 0.0))
        _copy_cells(rect, Rect2i())
        return
    var old_rect := rect
    var old_texture := texture
    var grown := old_rect.merge(clipped)
    var carried := SaTexture.new(_texels(grown.size), old_texture.format)
    # Cleared before the carry, because the cells of the new area that hold no
    # chunk are ones no copy will write and a fresh texture is undefined there.
    carried.clear(Color(0.0, 0.0, 0.0, 0.0))
    var offset := _texels(old_rect.position - grown.position)
    var rd := GlobalShaderCompiler.get_rd()
    rd.texture_copy(
        old_texture.rid,
        carried.rid,
        Vector3.ZERO,
        Vector3(offset.x, offset.y, 0),
        Vector3(old_texture.size.x, old_texture.size.y, 1),
        0,
        0,
        0,
        0
    )
    rect = grown
    texture = carried
    _copy_cells(grown, old_rect)


## Where document pixel *pos* sits in the copy, for a reader that addresses
## the texture by hand: its first texel, of `scale` by `scale`.
func local_of(pos: Vector2i) -> Vector2i:
    return _texels(pos - rect.position)


## *size* in document pixels, in the copy's texels.
func _texels(size: Vector2i) -> Vector2i:
    return Vector2i(Vector2(size) * scale)


## One copy per chunk cell of *area* that holds a chunk and lies outside *held*,
## which is the part an earlier copy already brought across. A cell with no
## chunk is left as the clear left it, since the layer holds nothing there.
func _copy_cells(area: Rect2i, held: Rect2i) -> void:
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null or _layer == null or texture == null:
        return
    for grid_pos: Vector2i in _layer.chunks.keys():
        var chunk: SaChunk = _layer.chunks[grid_pos]
        if chunk == null:
            continue
        var source := chunk.field(SaFieldSpec.ALBEDO)
        if source == null:
            continue
        var edge := chunk.pixel_size()
        if edge != _texels(Vector2i(SaChunk.SIZE, SaChunk.SIZE)).x:
            # `texture_copy` moves texels one for one, so a chunk stored at a
            # scale other than its layer's needs a resample and not a copy.
            # Whoever brings per-chunk resolution inside one layer brings that
            # pass with it, and until then saying part was left out beats a
            # silently transparent hole.
            SaProblems.report(
                "SaLayerSnapshot", TranslationServer.translate("Part of the layer has a different resolution and was not copied.")
            )
            continue
        var cell := Rect2i(grid_pos * SaChunk.SIZE, Vector2i(SaChunk.SIZE, SaChunk.SIZE))
        var part := cell.intersection(area)
        for piece: Rect2i in _outside(part, held):
            var from := _texels(piece.position - cell.position)
            var to := _texels(piece.position - rect.position)
            var across := _texels(piece.size)
            rd.texture_copy(
                source.rid,
                texture.rid,
                Vector3(from.x, from.y, 0),
                Vector3(to.x, to.y, 0),
                Vector3(across.x, across.y, 1),
                0,
                0,
                0,
                0
            )
            chunk_copies += 1


## The parts of *area* that lie outside *held*, at most four strips. The whole
## of *area* when the two do not meet, nothing when *held* covers it, and
## nothing at all for an empty *area*.
##
## The same four strips [SaMergedSnapshot] computes, written here rather than
## reached for: that file is core's and this one is the module's, and a module
## calling a sibling's private static is a wire the skeleton would have to keep.
static func _outside(area: Rect2i, held: Rect2i) -> Array[Rect2i]:
    var parts: Array[Rect2i] = []
    if area.size.x <= 0 or area.size.y <= 0:
        return parts
    var inner := area.intersection(held)
    if inner.size.x <= 0 or inner.size.y <= 0:
        parts.append(area)
        return parts
    if inner.position.y > area.position.y:
        parts.append(Rect2i(area.position, Vector2i(area.size.x, inner.position.y - area.position.y)))
    if inner.end.y < area.end.y:
        parts.append(Rect2i(Vector2i(area.position.x, inner.end.y), Vector2i(area.size.x, area.end.y - inner.end.y)))
    if inner.position.x > area.position.x:
        var left := Vector2i(area.position.x, inner.position.y)
        parts.append(Rect2i(left, Vector2i(inner.position.x - area.position.x, inner.size.y)))
    if inner.end.x < area.end.x:
        var right := Vector2i(inner.end.x, inner.position.y)
        parts.append(Rect2i(right, Vector2i(area.end.x - inner.end.x, inner.size.y)))
    return parts


## The depth the copy is taken at: the layer's own albedo, which the document
## declared. Asked of the schema rather than of a chunk, because a rectangle the
## layer has no chunk under still gets a texture a dab can read as nothing.
func _format() -> int:
    var spec := SaFieldSpec.find(_layer.schema, SaFieldSpec.ALBEDO)
    return spec.format if spec != null else RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT


func _clip(wanted: Rect2i) -> Rect2i:
    var document := _layer.get_parent() as SaDocument
    if document == null:
        return wanted
    return wanted.intersection(Rect2i(Vector2i.ZERO, document.canvas_size))
