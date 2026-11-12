## A linked layer's override: the strokes painted into its contents, kept over
## the file's picture through a reload and an open, as a library override
## does in Blender.
##
## **The picture, kept apart.** This object holds the picture the file gave,
## [member picture], chunks of their own that no stroke reaches, while the
## link's chunks are what is painted. The override is every texel where the
## two differ, so it is Blender's override texel by texel: a texel painted
## keeps its painted value whatever the file does, and every other texel
## follows the file. Nothing is tracked while painting, since a stroke buffer's
## commit does not say which chunks it wrote, and so the two are compared on
## the card when it matters, at a reload, an open, a save and Clear Override.
##
## **The comparison.** `linked_override_differs` flags each chunk holding a
## texel that differs by more than a rounding, and the flags are read back as
## one small buffer, never the canvas (hard rule 1). `linked_override_keep`
## then writes a chunk of the reloaded paint, the stroke where it differs and
## the new picture elsewhere. A stroke at part opacity is kept as it was laid,
## the old picture under it included, because what was under a texel is not in
## the texel.
##
## **The file.** A save stores what the link's chunks cannot give back, the
## picture under the strokes, for the chunks that hold one, in the link's entry
## beside its path. An open puts that over the stored paint to have the old
## picture again, compares, and keeps the strokes over what the file holds now.
## Named only by `SaLinkedFile`.
class_name SaLinkedOverride
extends RefCounted

## The entry's key for the stored picture's textures, and for the chunks of it
## that were empty.
const PICTURE := "picture"
const BARE := "bare"

## The picture the file gave, never painted. Set in the constructor.
var picture: Dictionary[Vector2i, SaChunk] = {}

static var _differs: SaCompute = null
static var _keep: SaCompute = null


func _init(read: Dictionary[Vector2i, SaChunk]) -> void:
    picture = read


## A copy of every chunk of *chunks* on the card, so that painting one of the
## two reaches nothing of the other.
static func apart(chunks: Dictionary[Vector2i, SaChunk]) -> Dictionary[Vector2i, SaChunk]:
    var copy: Dictionary[Vector2i, SaChunk] = {}
    for grid_pos: Vector2i in chunks:
        copy[grid_pos] = chunks[grid_pos].duplicate_chunk()
    return copy


## The grid positions where *painted* holds a texel that is not the picture's,
## which are the chunks the override is in. Empty with no device.
func strokes(painted: Dictionary[Vector2i, SaChunk], schema: Array[SaFieldSpec]) -> Array[Vector2i]:
    var found: Array[Vector2i] = []
    var positions := _union([painted, picture])
    if positions.is_empty() or GlobalShaderCompiler.get_rd() == null:
        return found
    if _differs == null:
        _differs = SaCompute.new("linked_override_differs")
    var zeros := PackedInt32Array()
    zeros.resize(positions.size())
    var tally := SaCompute.Buffer.new(zeros.to_byte_array())
    var blanks := Blanks.new(schema)
    for slot in positions.size():
        var grid_pos := positions[slot]
        var mine: SaChunk = painted.get(grid_pos, null)
        var was: SaChunk = picture.get(grid_pos, null)
        for field_id: StringName in _fields([mine, was]):
            var a := blanks.field(mine, field_id, was)
            var b := blanks.field(was, field_id, mine)
            if a.size != b.size:
                zeros[slot] = 1
                continue
            var size := {"width": a.size.x, "height": a.size.y, "slot": slot}
            _differs.run("linked_override_differs", {"painted": a, "was": b, "tally": tally}, size, Rect2i(Vector2i.ZERO, a.size))
    var flags := tally.read()
    for slot in positions.size():
        if zeros[slot] != 0 or flags.decode_u32(slot * 4) != 0:
            found.append(positions[slot])
    return found


## The paint a link takes when its file gives *now*: in every chunk the
## override is in, the stroke where *painted* differs from the picture and
## *now* elsewhere, and a copy of *now* in every other chunk, all of them
## textures of their own.
func kept_over(
    painted: Dictionary[Vector2i, SaChunk], now: Dictionary[Vector2i, SaChunk], schema: Array[SaFieldSpec]
) -> Dictionary[Vector2i, SaChunk]:
    var marked := strokes(painted, schema)
    var made: Dictionary[Vector2i, SaChunk] = {}
    for grid_pos: Vector2i in now:
        if not marked.has(grid_pos):
            made[grid_pos] = now[grid_pos].duplicate_chunk()
    if marked.is_empty():
        return made
    if _keep == null:
        _keep = SaCompute.new("linked_override_keep")
    var blanks := Blanks.new(schema)
    for grid_pos in marked:
        var mine: SaChunk = painted.get(grid_pos, null)
        var was: SaChunk = picture.get(grid_pos, null)
        var fresh: SaChunk = now.get(grid_pos, null)
        var into := SaChunk.new()
        into.resolution_scale = (mine if mine != null else (was if was != null else fresh)).resolution_scale
        for field_id: StringName in _fields([mine, was, fresh]):
            var a := blanks.field(mine, field_id, was if was != null else fresh)
            var b := blanks.field(was, field_id, a)
            var c := blanks.field(fresh, field_id, a)
            var out := SaTexture.new(a.size, a.format)
            into.fields[field_id] = out
            if blanks.blank.has(field_id):
                into.blanks[field_id] = blanks.blank[field_id]
            if b.size != a.size or c.size != a.size:
                a.rd.texture_copy(a.rid, out.rid, Vector3.ZERO, Vector3.ZERO, Vector3(a.size.x, a.size.y, 1), 0, 0, 0, 0)
                continue
            var bound := {"painted": a, "was": b, "now": c, "into": out}
            var size := {"width": a.size.x, "height": a.size.y}
            _keep.run("linked_override_keep", bound, size, Rect2i(Vector2i.ZERO, a.size))
        made[grid_pos] = into
    return made


## What a save stores of the override in the link's entry *entry*: the picture
## under the strokes of *painted*, a slot of *blobs* for each field of each
## chunk the override is in, rounded as the save rounds the paint over it, and
## the chunks where the picture held nothing. Nothing for a link with no
## override, so a file with none is the file a build without overrides
## writes.
func write(painted: Dictionary[Vector2i, SaChunk], schema: Array[SaFieldSpec], entry: Dictionary, blobs: PackedByteArray) -> void:
    var marked := strokes(painted, schema)
    if marked.is_empty():
        return
    var rd := GlobalShaderCompiler.get_rd()
    var slots: Array = []
    var bare: Array = []
    for grid_pos in marked:
        var chunk: SaChunk = picture.get(grid_pos, null)
        if chunk == null:
            bare.append([grid_pos.x, grid_pos.y])
            continue
        var over: SaChunk = painted.get(grid_pos, null)
        for field_id: StringName in chunk.fields:
            var texture := _as_saved(chunk.fields[field_id], over.field(field_id) if over != null else null)
            var slot := SaSadFile.write_texture(texture, blobs, rd)
            if slot.is_empty():
                continue
            slot.merge({"x": grid_pos.x, "y": grid_pos.y, "field": String(field_id), "scale": chunk.resolution_scale})
            slots.append(slot)
    entry[PICTURE] = slots
    entry[BARE] = bare


## The picture a saved link had before its file is read again: *painted*, the
## paint the `.sad` stored, with the picture *entry* keeps under its strokes
## put back out of *blobs*, and the chunks it says were empty taken out. The
## chunks it shares with *painted* are the same objects, so the caller copies
## them before anything paints either.
static func stored(
    entry: Dictionary[String, Variant], painted: Dictionary[Vector2i, SaChunk], schema: Array[SaFieldSpec], blobs: PackedByteArray
) -> Dictionary[Vector2i, SaChunk]:
    var was: Dictionary[Vector2i, SaChunk] = painted.duplicate()
    for raw: Variant in entry.get(PICTURE, []):
        var slot := SaTyped.strings(raw)
        var grid_pos := Vector2i(SaTyped.int_at(slot, "x", 0), SaTyped.int_at(slot, "y", 0))
        var field_id := StringName(SaTyped.text_at(slot, "field", String(SaFieldSpec.ALBEDO)))
        var spec := SaFieldSpec.find(schema, field_id)
        if spec == null:
            continue
        var chunk: SaChunk = was.get(grid_pos, null)
        if chunk == null or is_same(chunk, painted.get(grid_pos, null)):
            chunk = SaChunk.new()
            chunk.resolution_scale = SaTyped.float_at(slot, "scale", 1.0)
            was[grid_pos] = chunk
        var edge := chunk.pixel_size()
        var texture := SaTexture.new(Vector2i(edge, edge), spec.format)
        if not SaSadFile.read_texture(slot, blobs, texture):
            push_warning("SaLinkedFile: a chunk of the picture under a linked layer's strokes did not read")
            continue
        chunk.fields[field_id] = texture
        if SaChunk.keeps_blank(spec):
            chunk.blanks[field_id] = spec.blank
    for raw: Variant in entry.get(BARE, []):
        if raw is Array:
            var pair: Array = raw
            if pair.size() == 2:
                var x: float = pair[0]
                var y: float = pair[1]
                was.erase(Vector2i(roundi(x), roundi(y)))
    return was


## *texture* as a save writes it: a rounded copy when the save rounds *over*,
## the painted texture above it, so the two compare equal where nothing was
## painted, and *texture* itself otherwise.
static func _as_saved(texture: SaTexture, over: SaTexture) -> SaTexture:
    if over == null or not SaSadSnapshot.is_rounded(over) or texture.format != over.format:
        return texture
    var copy := SaTexture.new(texture.size, texture.format)
    var extent := Vector3(texture.size.x, texture.size.y, 1)
    texture.rd.texture_copy(texture.rid, copy.rid, Vector3.ZERO, Vector3.ZERO, extent, 0, 0, 0, 0)
    SaSadSnapshot.round_in_place(copy)
    return copy


static func _union(sets: Array) -> Array[Vector2i]:
    var seen: Dictionary[Vector2i, bool] = {}
    for held: Dictionary in sets:
        for grid_pos: Vector2i in held:
            seen[grid_pos] = true
    var positions: Array[Vector2i] = seen.keys()
    return positions


static func _fields(chunks: Array) -> Array[StringName]:
    var ids: Array[StringName] = []
    for chunk: SaChunk in chunks:
        if chunk == null:
            continue
        for field_id: StringName in chunk.fields:
            if chunk.fields[field_id] != null and not ids.has(field_id):
                ids.append(field_id)
    return ids


## The textures a comparison binds where a chunk or a field is missing: the
## field's blank, the value a layer holds where it holds nothing, one texture
## a field and a size, made on first use.
class Blanks:
    extends RefCounted

    ## The blank of each field of the schema that keeps one of its own.
    var blank: Dictionary[StringName, Color] = {}
    var _made: Dictionary[String, SaTexture] = {}

    func _init(schema: Array[SaFieldSpec]) -> void:
        for spec in schema:
            if spec != null and SaChunk.keeps_blank(spec):
                blank[spec.id] = spec.blank

    ## *chunk*'s field *field_id*, or a blank of the size and format *like* has
    ## for it, *like* being a chunk or a texture.
    func field(chunk: SaChunk, field_id: StringName, like: Variant) -> SaTexture:
        var held := chunk.field(field_id) if chunk != null else null
        if held != null:
            return held
        var shape: SaTexture = null
        if like is SaTexture:
            shape = like
        elif like is SaChunk:
            var other: SaChunk = like
            shape = other.field(field_id)
        var side := chunk.pixel_size() if chunk != null else SaChunk.SIZE
        var size := shape.size if shape != null else Vector2i(side, side)
        var format := shape.format if shape != null else RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
        var key := "%s %d %d %d" % [field_id, size.x, size.y, format]
        if not _made.has(key):
            var texture := SaTexture.new(size, format)
            var colour: Color = blank.get(field_id, Color(0.0, 0.0, 0.0, 0.0))
            texture.clear(colour)
            _made[key] = texture
        return _made[key]
