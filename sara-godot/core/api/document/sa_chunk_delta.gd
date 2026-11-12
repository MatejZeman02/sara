## A snapshot of part of one chunk, for undo history.
##
## A dab covers a few dozen pixels of a 256x256 chunk, and keeping the whole
## chunk for it would be one megabyte to be able to put back a few thousand
## texels. The compositor already tracks the region a stroke touched to size its
## dispatches, and this spends it a second time.
##
## The rectangle is the union of everything the stroke touched in that chunk, so
## restoring it is complete: nothing outside it changed, which is the invariant the
## whole thing rests on.
class_name SaChunkDelta
extends RefCounted

## Chunk-local rectangle this covers, in texture pixels.
var rect: Rect2i

## StringName -> SaTexture, one per field of the chunk, each `rect.size` big.
##
## A field the chunk did not hold when this was captured is absent here, and
## that absence is part of the snapshot. A lazy field, height, arrives in a
## chunk on its first write, so a stroke that lays the chunk's first height
## finds none at capture and adds one after. Everything that field holds came
## from strokes inside `rect`, so putting the snapshot back takes the field off
## again, and a snapshot that holds a field the chunk lost puts it back on.
##
## The gate a snapshot in RAM comes back through, as `SaChunk.fields` is a
## chunk's. Past the budget `SaResidency` moves the history's snapshots to RAM
## before any layer's chunks, and an undo or a redo that reaches this one reads
## its textures here, so the getter uploads them again before the step meets them.
var fields: Dictionary[StringName, SaTexture]:
    get:
        if stored != null:
            _bring_back()
        return _fields

var _fields: Dictionary[StringName, SaTexture] = {}

## The fields read back and compressed in RAM while the snapshot is evicted,
## and null while its textures are on the card.
var stored: SaChunk.Stored = null

## How many snapshots are in RAM now, every history's, and the bytes their
## compressed copies hold.
static var stored_count: int = 0
static var stored_bytes: int = 0


## Copies *region* out of *chunk*. Null when there is nothing to copy.
static func capture(chunk: SaChunk, region: Rect2i) -> SaChunkDelta:
    if chunk == null:
        return null
    var clipped := region.intersection(Rect2i(Vector2i.ZERO, Vector2i(chunk.pixel_size(), chunk.pixel_size())))
    if clipped.size.x <= 0 or clipped.size.y <= 0:
        return null
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null:
        return null

    var delta := SaChunkDelta.new()
    delta.rect = clipped
    for field_id: StringName in chunk.fields:
        var source: SaTexture = chunk.fields[field_id]
        if source == null:
            continue
        var piece := SaTexture.new(clipped.size, source.format)
        _copy_region(rd, source, clipped.position, piece, Vector2i.ZERO, clipped.size)
        SaTexture.note_copy(piece.bytes)
        delta.fields[field_id] = piece
    return delta


## Writes this snapshot back into *chunk*, leaving everything outside `rect` alone.
func apply_to(chunk: SaChunk) -> void:
    if chunk == null:
        return
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null:
        return
    for field_id: StringName in chunk.field_ids():
        if not fields.has(field_id):
            chunk.drop_field(field_id)
    for field_id: StringName in fields:
        var piece: SaTexture = fields[field_id]
        if piece == null:
            continue
        if not chunk.has_field(field_id):
            # A transfer clear, where a dab's first height is blanked by a
            # kernel: the copy that follows is a transfer too, and the kernel
            # would not be ordered against it.
            chunk.add_field(SaFieldSpec.sparse(field_id, piece.format), SaFieldSpec.NO_PAINT)
        _copy_region(rd, piece, Vector2i.ZERO, chunk.field(field_id), rect.position, rect.size)


## The same snapshot over a larger rectangle.
##
## Called while a stroke is still being painted directly into the layer, so only
## the newly exposed bands are read from the chunk. Everything inside the old
## rectangle has already been painted on and must come from the old snapshot, or
## an undo would put back a half-painted tile.
func grown_to(chunk: SaChunk, region: Rect2i) -> SaChunkDelta:
    if chunk == null or rect.encloses(region):
        return self
    var bounds := rect.merge(region)
    var grown := SaChunkDelta.capture(chunk, bounds)
    if grown == null:
        return self
    # Overwrite the part that is no longer pristine with what was saved from it.
    apply_to_delta(grown)
    return grown


## Copies this snapshot into the matching part of a larger one.
func apply_to_delta(target: SaChunkDelta) -> void:
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null:
        return
    var offset := rect.position - target.rect.position
    # A field the larger one read off the chunk that this one never saw was
    # written since this was captured, so the snapshot holds its absence.
    for field_id: StringName in target.fields.keys():
        if not fields.has(field_id):
            target.fields.erase(field_id)
    for field_id: StringName in fields:
        var piece: SaTexture = fields[field_id]
        var destination: SaTexture = target.fields.get(field_id, null)
        if piece == null or destination == null:
            continue
        _copy_region(rd, piece, Vector2i.ZERO, destination, offset, rect.size)


## VRAM every field of this snapshot holds. Read past the gate, so a snapshot
## in RAM answers 0 rather than coming back to be counted.
func byte_size() -> int:
    var total := 0
    for field_id: StringName in _fields:
        var piece: SaTexture = _fields[field_id]
        if piece != null:
            total += piece.bytes
    return total


## Whether this snapshot's fields are in RAM rather than on the card.
func is_stored() -> bool:
    return stored != null


## Takes *kept*, every field of this snapshot read back and compressed, and
## gives the textures up. `SaResidency.evict_snapshot` is the one caller,
## outside any stroke.
func store(kept: SaChunk.Stored) -> void:
    if kept == null or stored != null:
        return
    stored = kept
    stored_count += 1
    stored_bytes += kept.bytes()
    _fields.clear()


func _bring_back() -> void:
    var kept := stored
    stored = null
    stored_count -= 1
    stored_bytes -= kept.bytes()
    _fields.assign(kept.upload())


func _notification(what: int) -> void:
    # A method of this object cannot be called while it is deleted.
    if what == NOTIFICATION_PREDELETE and stored != null:
        stored_count -= 1
        stored_bytes -= stored.bytes()


## One region copy, in texture pixels, read left to right: this much of *source*
## starting at *from_pos*, into *destination* starting at *to_pos*.
static func _copy_region(
    rd: RenderingDevice, source: SaTexture, from_pos: Vector2i, destination: SaTexture, to_pos: Vector2i, size: Vector2i
) -> void:
    rd.texture_copy(
        source.rid,
        destination.rid,
        Vector3(from_pos.x, from_pos.y, 0),
        Vector3(to_pos.x, to_pos.y, 0),
        Vector3(size.x, size.y, 1),
        0,
        0,
        0,
        0
    )
