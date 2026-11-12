## The sample merged snapshot: a stroke's read of the composite.
##
## The smudge stage the brush plan builds picks paint up from under the dab,
## and in overlay mode what is under the dab is the composite, every layer
## flattened. Reading the easel's output texture straight from a kernel would
## be a read of the picture while the same stroke is writing it, so a stroke
## asks the easel for a snapshot instead: a GPU to GPU copy of the composite
## under a rectangle, taken once when the stroke starts and grown by the
## dirty rectangle of each dab that leaves it. It is never taken per frame and
## it is never the whole canvas.
##
## The copy is one `texture_copy` per chunk cell under the rectangle, which is
## the dirty-rect discipline of hard rule 2 applied to a copy rather than a
## dispatch: a texel outside the rectangle is never read. The composite is one
## texture at the document's pitch rather than a layer's sparse chunks, so the
## cell is `SaChunk.SIZE` document pixels, the grid the compositor writes the
## output in. Nothing here reads back, and the hard-rules test holds that.
##
## RAII: the texture is a [SaTexture], the snapshot is a [RefCounted], and
## whoever asked for it holds the one reference. Dropping it at the end of the
## stroke frees the VRAM with it, and the easel keeps no list to forget.
class_name SaMergedSnapshot
extends RefCounted

## The copy, sized exactly to `rect`. Local texel (0, 0) is document texel
## `rect.position`.
var texture: SaTexture = null

## The document rectangle the copy covers, clipped to the canvas.
var rect: Rect2i = Rect2i()

## How many chunk cells have been copied from the composite so far. One per
## cell under the first rectangle, one more per cell a growth reaches, so a
## test can hold it to the chunk count rather than trust that no copy was of
## the whole canvas.
var chunk_copies: int = 0

## The composite copied from, and the canvas it covers. Handed in rather than
## asked of the easel, so the snapshot holds no easel. A snapshot lives for one
## stroke, and one that outlives a resize grows from the output it was taken
## from, which it keeps alive until the stroke lets go of it.
var _output: SaTexture = null
var _canvas_size: Vector2i = Vector2i.ZERO


## A snapshot of the composite *output* of a canvas *canvas_size* big, under
## *wanted* clipped to the canvas. The texture stays null when nothing of the
## rectangle is on the canvas.
func _init(output: SaTexture, canvas_size: Vector2i, wanted: Rect2i) -> void:
    _output = output
    _canvas_size = canvas_size
    var clipped := _clip(wanted)
    if clipped.size.x <= 0 or clipped.size.y <= 0:
        return
    var source := _source()
    if source == null:
        return
    rect = clipped
    texture = SaTexture.new(rect.size, source.format)
    _copy_cells(source, rect, Rect2i())


## Whether *wanted* lies wholly inside the snapshot, so a dab there reads
## without a growth.
func covers(wanted: Rect2i) -> bool:
    return texture != null and rect.encloses(wanted)


## Grows the snapshot to take *wanted* in, keeping what it already holds.
##
## The old copy moves into the new texture by one GPU to GPU copy and only
## the cells of the new area outside it are copied from the composite, so a
## stroke that wanders one chunk to the right pays for one chunk. The cells
## already held keep the picture they were taken with, which is the point of
## a snapshot: the stroke reads what stood before it, not what it painted.
## A rectangle already covered costs nothing.
func grow(wanted: Rect2i) -> void:
    var clipped := _clip(wanted)
    if clipped.size.x <= 0 or clipped.size.y <= 0:
        return
    if texture != null and rect.encloses(clipped):
        return
    var source := _source()
    if source == null:
        return
    if texture == null:
        rect = clipped
        texture = SaTexture.new(rect.size, source.format)
        _copy_cells(source, rect, Rect2i())
        return
    var old_rect := rect
    var old_texture := texture
    var grown := old_rect.merge(clipped)
    var carried := SaTexture.new(grown.size, source.format)
    var offset := old_rect.position - grown.position
    var rd := GlobalShaderCompiler.get_rd()
    rd.texture_copy(
        old_texture.rid,
        carried.rid,
        Vector3.ZERO,
        Vector3(offset.x, offset.y, 0),
        Vector3(old_rect.size.x, old_rect.size.y, 1),
        0,
        0,
        0,
        0
    )
    rect = grown
    texture = carried
    _copy_cells(source, grown, old_rect)


## Where document texel *pos* sits in the copy, for a reader that addresses
## the texture by hand.
func local_of(pos: Vector2i) -> Vector2i:
    return pos - rect.position


## One copy per chunk cell under *area*, leaving out what lies inside *held*,
## which is the part an earlier copy already brought across.
func _copy_cells(source: SaTexture, area: Rect2i, held: Rect2i) -> void:
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null or source == null or not source.rid.is_valid():
        return
    var pitch := SaChunk.SIZE
    @warning_ignore("integer_division")
    var first := Vector2i(area.position.x / pitch, area.position.y / pitch)
    @warning_ignore("integer_division")
    var last := Vector2i((area.end.x - 1) / pitch, (area.end.y - 1) / pitch)
    for gy in range(first.y, last.y + 1):
        for gx in range(first.x, last.x + 1):
            var cell := Rect2i(Vector2i(gx, gy) * pitch, Vector2i(pitch, pitch)).intersection(area)
            for part: Rect2i in _outside(cell, held):
                var target := part.position - rect.position
                rd.texture_copy(
                    source.rid,
                    texture.rid,
                    Vector3(part.position.x, part.position.y, 0),
                    Vector3(target.x, target.y, 0),
                    Vector3(part.size.x, part.size.y, 1),
                    0,
                    0,
                    0,
                    0
                )
                chunk_copies += 1


## The parts of *area* that lie outside *held*, at most four strips. The whole
## of *area* when the two do not meet, nothing when *held* covers it.
static func _outside(area: Rect2i, held: Rect2i) -> Array[Rect2i]:
    var parts: Array[Rect2i] = []
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


func _clip(wanted: Rect2i) -> Rect2i:
    return wanted.intersection(Rect2i(Vector2i.ZERO, _canvas_size))


## The composite copied from, or null when there is none to copy.
func _source() -> SaTexture:
    if _output == null or not _output.rid.is_valid():
        return null
    return _output
