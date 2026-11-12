## One 256x256 tile of a layer, holding every field in that layer's schema.
##
## A chunk owns a dictionary of fields, keyed by `SaFieldSpec.id`, plus the
## resolution it is stored at, rather than being a bare SaTexture, which would
## say a chunk has exactly one field forever.
##
## `resolution_scale` is the layer's, 1.0 unless the layer was made at another
## density: New Layer at Double Resolution makes its chunks at 2.0, and the
## `.sad` reader makes a chunk at the scale the file stored it at, never below
## 1.0, on a layer it opens at 1.0 to 2.0. Every consumer reads the scale rather
## than assuming one, so nothing may assume
## a chunk is SIZE pixels across: ask `pixel_size()`.
##
## Deliberately not an atlas plus an indirection map: the sparse dictionary is
## the right substrate, and an atlas makes per-chunk variable resolution harder
## rather than easier.
@tool
class_name SaChunk
extends RefCounted

## Edge length in document pixels at `resolution_scale` 1.0.
const SIZE: int = 256

## StringName -> SaTexture, one entry per field in the owning layer's schema.
##
## The gate an evicted chunk comes back through. Past the budget, `SaResidency`
## reads a chunk of a layer nobody is painting back to RAM and gives its
## textures up, and the chunk stays in its layer's dictionary holding the
## compressed copy, [member stored]. Every reader of a chunk's pixels, the
## compositor, the export, the save, the wand and the tools, reaches them
## through this dictionary or a method of this class that reads it, so the
## getter uploads the copy again before the reader meets an empty dictionary.
var fields: Dictionary[StringName, SaTexture]:
    get:
        if stored != null:
            _bring_back()
        return _fields

var _fields: Dictionary[StringName, SaTexture] = {}

## The chunk's fields read back and compressed in RAM while it is evicted, and
## null while its textures are on the card.
var stored: Stored = null

## How many chunks are in RAM now, every document's, and the bytes their
## compressed copies hold.
static var stored_count: int = 0
static var stored_bytes: int = 0


## A chunk's fields in RAM: each field's texels compressed by the save's Zstd,
## with what it takes to make the texture again.
class Stored:
    extends RefCounted

    var size: Vector2i
    var compression: int
    ## Field id -> the compressed texels, their raw length and their format.
    var packed: Dictionary[StringName, PackedByteArray] = {}
    var raw_sizes: Dictionary[StringName, int] = {}
    var formats: Dictionary[StringName, int] = {}

    func _init(edge: Vector2i, mode: int) -> void:
        size = edge
        compression = mode

    ## Keeps one field's texels *raw*, read back from a texture of *format*.
    func keep(field_id: StringName, raw: PackedByteArray, format: int) -> void:
        packed[field_id] = raw.compress(compression)
        raw_sizes[field_id] = raw.size()
        formats[field_id] = format

    ## Uploads every field into a fresh texture and answers them by field id.
    ## What brings a chunk, or a history snapshot's delta, back to the card.
    func upload() -> Dictionary[StringName, SaTexture]:
        var made: Dictionary[StringName, SaTexture] = {}
        var rd := GlobalShaderCompiler.get_rd()
        for field_id: StringName in packed:
            var texture := SaTexture.new(size, formats[field_id])
            if rd != null and texture.rid.is_valid():
                var raw := packed[field_id].decompress(raw_sizes[field_id], compression)
                rd.texture_update(texture.rid, 0, raw)
            made[field_id] = texture
        return made

    ## What the compressed copies hold in RAM.
    func bytes() -> int:
        var total := 0
        for field_id: StringName in packed:
            total += packed[field_id].size()
        return total


## Texels per document pixel along each axis, the density this chunk is
## stored at: 1.0 at the document's resolution and 2.0 on a layer at double
## resolution.
var resolution_scale: float = 1.0

## StringName -> Color, the fields a clear leaves at their own blank rather
## than the colour it names, from `SaFieldSpec.blank`: a layer's mask, whose
## blank is one, and a lazy field such as height, whose blank is zero and which
## a ground colour must not write a thickness into. Kept on the chunk because
## `clear` is called by files that hold a chunk and no schema.
var blanks: Dictionary[StringName, Color] = {}

## The kernel a lazy field's first texture is blanked by, one for every chunk.
static var _blanker: SaCompute = null


## Allocates one texture per field but the lazy ones, which wait for their
## first write. The contents are undefined until something clears or paints
## them, which is what `SaLayer.get_or_create_chunk` does.
static func create(schema: Array[SaFieldSpec], scale: float = 1.0) -> SaChunk:
    var chunk := SaChunk.new()
    chunk.resolution_scale = scale
    var edge := chunk.pixel_size()
    for spec in schema:
        if spec == null or spec.id.is_empty() or spec.lazy:
            continue
        chunk.fields[spec.id] = SaTexture.new(Vector2i(edge, edge), spec.format)
        if keeps_blank(spec):
            chunk.blanks[spec.id] = spec.blank
    return chunk


## Whether a clear leaves *spec*'s field at its blank whatever colour it names.
static func keeps_blank(spec: SaFieldSpec) -> bool:
    return spec.blank != SaFieldSpec.NO_PAINT or spec.lazy


## Gives a chunk that already exists one more field, holding *value* everywhere.
## What `SaLayer.add_mask` calls for the chunks the layer held before the mask,
## and `SaLayer.get_or_create_field` for a lazy field's first write here.
func add_field(spec: SaFieldSpec, value: Color) -> void:
    var edge := pixel_size()
    var texture := SaTexture.new(Vector2i(edge, edge), spec.format)
    texture.clear(value)
    fields[spec.id] = texture
    if keeps_blank(spec):
        blanks[spec.id] = spec.blank


## Gives this chunk its first texture of a lazy field, at the field's blank,
## and answers it. What a lazy field's first write here goes through.
##
## Blanked by the `blank` kernel rather than a transfer clear, because the
## write that follows is a dab over part of the texture and a transfer is not
## ordered against compute: the rest
## could come out holding whatever the allocation left there.
func add_sparse_field(spec: SaFieldSpec) -> SaTexture:
    var edge := pixel_size()
    var texture := SaTexture.new(Vector2i(edge, edge), spec.format)
    fields[spec.id] = texture
    blanks[spec.id] = spec.blank
    if _blanker == null and GlobalShaderCompiler.get_rd() != null:
        _blanker = SaCompute.new("blank")
    if _blanker == null:
        texture.clear(spec.blank)
        return texture
    var value := spec.blank
    _blanker.use_storage_format(spec.format)
    _blanker.set_texture(0, texture.rid)
    _blanker.set_push_constant_float_array(PackedFloat32Array([value.r, value.g, value.b, value.a, 0.0, 0.0, edge, edge]))
    _blanker.dispatch_kernel("blank_region", SaCompute.groups_for(edge), SaCompute.groups_for(edge), 1)
    return texture


## Takes one field out, and its texture goes with the last reference.
func drop_field(field_id: StringName) -> void:
    fields.erase(field_id)
    blanks.erase(field_id)


## Texture edge length in pixels, which is SIZE only at full resolution.
##
## `SaChunkWalk`, which `SaLayer.fill`, the filters and the selection dispatch
## through, cuts a chunk's region by this rather than by a hardcoded 32 groups,
## so a chunk at 2.0 dispatches the right number of threads for its 512 texels
## across.
func pixel_size() -> int:
    return maxi(1, roundi(float(SIZE) * resolution_scale))


## Workgroup count along one axis for an 8x8 compute kernel over the whole chunk.
func workgroups(workgroup_size: int = 8) -> int:
    return maxi(1, ceili(float(pixel_size()) / float(workgroup_size)))


func has_field(field_id: StringName) -> bool:
    return fields.has(field_id) and fields[field_id] != null


## The texture backing one field, or null.
##
## Returning null rather than asserting is deliberate: a layer whose schema
## gained a field after this chunk was allocated is a real state, not a
## programming error.
func field(field_id: StringName) -> SaTexture:
    return fields.get(field_id, null)


## The one field the compositor reads. Whether it was painted or derived is the
## layer's business, not the compositor's.
## VRAM every field of this chunk holds together.
##
## What one entry in the undo history costs, which is the number the byte budget
## is spent in. Summed rather than assumed: a chunk is
## one texture per field of its layer's schema, at whatever depth each declared.
##
## Read past the gate, so an evicted chunk answers 0 rather than coming back to
## be counted.
func byte_size() -> int:
    var total := 0
    for field_id: StringName in _fields:
        var texture: SaTexture = _fields[field_id]
        if texture != null:
            total += texture.bytes
    return total


## Whether this chunk's fields are in RAM rather than on the card.
func is_stored() -> bool:
    return stored != null


## Takes *kept*, every field of this chunk read back and compressed, and gives
## the textures up. `SaResidency.evict` is the one caller, outside any stroke.
func store(kept: Stored) -> void:
    if kept == null or stored != null:
        return
    stored = kept
    stored_count += 1
    stored_bytes += kept.bytes()
    _fields.clear()


## Uploads the copy in RAM into fresh textures, which is what the getter of
## [member fields] runs before any reader meets the chunk.
func _bring_back() -> void:
    var kept := stored
    _forget_stored()
    _fields.assign(kept.upload())


func _forget_stored() -> void:
    if stored == null:
        return
    stored_count -= 1
    stored_bytes -= stored.bytes()
    stored = null


func _notification(what: int) -> void:
    # A method of this object cannot be called while it is deleted.
    if what == NOTIFICATION_PREDELETE and stored != null:
        stored_count -= 1
        stored_bytes -= stored.bytes()


func albedo() -> SaTexture:
    return field(SaFieldSpec.ALBEDO)


## Every field id this chunk actually holds.
func field_ids() -> Array:
    return fields.keys()


## Fills every field with one value, but for a field with a blank of its own,
## which takes that blank.
##
## Every caller clears a chunk it has just allocated, to transparent or to a
## ground colour, and none of them means "hide this layer here": a crop that
## grounds a fresh chunk in white would otherwise write one into the mask by
## luck and a paste would write zero into it by the same luck.
func clear(color: Color) -> void:
    for field_id: StringName in fields:
        var texture: SaTexture = fields[field_id]
        if texture != null:
            var blank: Color = blanks.get(field_id, color)
            texture.clear(blank)


## A GPU copy of every field, for undo history.
##
## Copied field by field because they may have different formats and therefore
## different sizes: a single-channel height field is a quarter of an albedo one.
##
## *only* narrows the copy to one field, which is what an undo entry of a stroke
## on a mask is: the paint under it did not move and is not paid for twice.
func duplicate_chunk(only: StringName = &"") -> SaChunk:
    var copy := SaChunk.new()
    copy.resolution_scale = resolution_scale
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null:
        return copy
    for field_id: StringName in fields:
        var source: SaTexture = fields[field_id]
        if source == null or (not only.is_empty() and field_id != only):
            continue
        if blanks.has(field_id):
            copy.blanks[field_id] = blanks[field_id]
        var destination := SaTexture.new(source.size, source.format)
        var extent := Vector3(source.size.x, source.size.y, 1)
        rd.texture_copy(source.rid, destination.rid, Vector3.ZERO, Vector3.ZERO, extent, 0, 0, 0, 0)
        SaTexture.note_copy(destination.bytes)
        copy.fields[field_id] = destination
    return copy
