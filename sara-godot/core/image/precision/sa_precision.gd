## Converts an open document's depth, 32-bit float to 16-bit float and back,
## as one history step.
##
## `SaColorConversion` keeps depth on purpose, because changing how many bits a
## channel gets is a reallocation of every chunk. This is that reallocation.
## Every colour field of every layer that holds paint, a group's and a smart
## layer's included, and of the stroke buffer, is written again at the new
## format by `precision_convert.gmacs` over the chunks the layer has allocated
## and nowhere else (hard rules 2 and 3), and the colour is never read back
## (hard rule 1). A simulation's seed goes the same way. A mask, a height and
## every field `SaFieldSpec.is_color` calls no colour keep their format and
## their texels.
##
## The caches are not converted, because what they hold is derived: the fold
## follows the document's depth on its next rebuild and refolds its caches at
## it, a smart layer's transform cache follows its layer's schema, and a derived
## colour field is marked unresolved and resolves at the new format, as
## `SaColorConversion` does.
##
## Built per use like `SaColorConversion`, `SaPrecision.new(document)`, and held
## by its history step for as long as the step can be undone.
@tool
class_name SaPrecision
extends RefCounted

## What the history and the corner call the step.
const STEP := "Convert Depth"

## The largest finite half float. A finite value past it is written as it,
## with its sign, and is what [method count_beyond_half] counts.
const HALF_MAX := 65504.0

## The float32 bit patterns the reference arithmetic below works in, the same
## constants `nearest_half.gmacs` names.
const _HALF_NORMAL_BITS := 0x38800000
const _FLOAT_NORMAL_BITS := 0x00800000
const _FLOAT_SPECIAL_BITS := 0x7f800000
const _HALF_DROPPED_BITS := 0x1fff
const _HALF_SUBNORMAL_STEPS := 16777216.0

## The document being converted, a `Node`, so holding it forms no cycle.
var _document: SaDocument
## The two kernels, made on first use and dropped with this object.
var _converter: SaCompute = null
var _counter: SaCompute = null


func _init(document: SaDocument) -> void:
    _document = document


## Why [method convert_to] would refuse *depth*, or "" when it would run. The
## document's own depth is no change, and a depth the card cannot store is
## refused as New Document refuses it.
func blocked_reason(depth: SaColorSpace.Depth) -> String:
    var space := _document.color_space if _document != null else null
    if space == null:
        return TranslationServer.translate("there is no document")
    if not SaColorSpace.storage_supports_depth(depth):
        return TranslationServer.translate("%s cannot be allocated on this card") % SaColorSpace.depth_name(depth)
    if space.depth == depth:
        return TranslationServer.translate("the document is already at %s") % SaColorSpace.depth_name(depth)
    return ""


## How many texels of the document's colour hold a finite channel past
## [constant HALF_MAX], which a half float cannot hold. Counted on the card over
## every allocated chunk of every layer and the stroke buffer, and read back as
## one number, a few bytes and not the canvas, outside any stroke. A seed is a
## copy of what is painted and is not counted twice. Zero for a document at
## half already, whose texels are all within it.
func count_beyond_half() -> int:
    var space := _document.color_space
    if space == null or space.depth == SaColorSpace.Depth.F16 or GlobalShaderCompiler.get_rd() == null:
        return 0
    var tally := SaCompute.Buffer.new(PackedInt32Array([0]).to_byte_array())
    if _counter == null:
        _counter = SaCompute.new("precision_count")
    var colour_format := space.texel_format()
    for held: Dictionary in _distinct_chunks():
        var layer: SaLayer = held["layer"]
        var chunks: Dictionary = held["chunks"]
        for grid_pos: Vector2i in chunks:
            var chunk: SaChunk = chunks[grid_pos]
            for field_id: StringName in chunk.fields:
                var texture: SaTexture = chunk.fields[field_id]
                if texture == null or texture.format != colour_format or not layer.is_color_field(field_id):
                    continue
                _counter.use_storage_format(texture.format)
                _counter.set_texture(0, texture.rid)
                _counter.set_buffer(1, tally.rid)
                var groups := Vector2i(SaCompute.groups_for(texture.size.x), SaCompute.groups_for(texture.size.y))
                _counter.dispatch_kernel("precision_count", groups.x, groups.y, 1)
    return tally.read().decode_u32(0)


## What the step would hold, the old chunks and seeds and a copy of the new
## ones, in bytes. About one and a half times the document going to half and
## three times its size going back to float.
func step_bytes(depth: SaColorSpace.Depth) -> int:
    var target := _document.color_space.with_depth(depth).texel_format()
    var old := 0
    var fresh := 0
    for texture: SaTexture in _held_textures():
        old += texture.bytes
        var converts := texture.format == _document.color_space.texel_format()
        var texel := SaTyped.int_at(SaFieldSpec.BYTES_PER_TEXEL, target, 16)
        fresh += texture.size.x * texture.size.y * texel if converts else texture.bytes
    return old + fresh


## Whether committing the step drops older steps from the history to make room.
## The step itself is always kept, `SaHistory` keeps a step larger than its
## whole budget, so the undo of the conversion is never lost, and what can go
## is what came before it. The budget as `SaHistory.effective_budget` will read
## it once this step is the largest it has seen.
func drops_older_steps(depth: SaColorSpace.Depth) -> bool:
    var history := _document.history
    if history == null or history.step_count() == 0:
        return false
    var incoming := step_bytes(depth)
    var budget := history.budget_bytes
    if not history.pin_budget:
        budget = maxi(budget, history.whole_canvas_depth() * maxi(history.largest_step_bytes, incoming))
    return history.total_bytes() + incoming > budget


## Writes every colour field of the document again at *depth*, as one history
## step whose undo puts back the old chunks bit for bit with the old descriptor,
## and marks the document modified. False, with nothing changed, when
## [method blocked_reason] has a reason.
func convert_to(depth: SaColorSpace.Depth) -> bool:
    var blocked := blocked_reason(depth)
    if not blocked.is_empty():
        push_warning("SaPrecision.convert_to refused: %s" % blocked)
        return false
    var source := _document.color_space
    var target := source.with_depth(depth)
    var from_format := source.texel_format()
    var to_format := target.texel_format()
    var narrowing := depth == SaColorSpace.Depth.F16

    var before: Array[Dictionary] = []
    var after: Array[Dictionary] = []
    var held := 0
    # One entry for each chunk dictionary, since a shared source's users hold
    # one between them and a chunk converted twice would split them apart.
    for entry: Dictionary in _distinct_chunks():
        var chunks: Dictionary[Vector2i, SaChunk] = entry["chunks"]
        var layer: SaLayer = entry["layer"]
        var old: Dictionary[Vector2i, SaChunk] = chunks.duplicate()
        var fresh: Dictionary[Vector2i, SaChunk] = {}
        for grid_pos: Vector2i in old:
            fresh[grid_pos] = _converted_chunk(old[grid_pos], layer, from_format, to_format, narrowing)
        before.append({"chunks": chunks, "held": old})
        after.append({"chunks": chunks, "held": _copies(fresh)})
        held += SaHistory.bytes_of(old) + SaHistory.bytes_of(fresh)
        for grid_pos: Vector2i in fresh:
            chunks[grid_pos] = fresh[grid_pos]

    var schemas_before: Array[Dictionary] = []
    var schemas_after: Array[Dictionary] = []
    for layer: SaLayer in _layers():
        schemas_before.append({"layer": layer, "schema": layer.schema})
        schemas_after.append({"layer": layer, "schema": schema_at(layer.schema, from_format, to_format)})

    var seeds_before: Array[Dictionary] = []
    var seeds_after: Array[Dictionary] = []
    for stepped: SaLayer in _stepped_layers():
        var record := SaSimulation.record_of(stepped)
        var old_seed: Dictionary[Vector2i, SaTexture] = record.seed_chunks.duplicate()
        var new_seed: Dictionary[Vector2i, SaTexture] = {}
        for grid_pos: Vector2i in old_seed:
            var texture: SaTexture = old_seed[grid_pos]
            new_seed[grid_pos] = _converted(texture, to_format, narrowing) if texture.format == from_format else texture
        seeds_before.append({"layer": stepped, "seed": old_seed})
        seeds_after.append({"layer": stepped, "seed": _texture_copies(new_seed)})
        for texture: SaTexture in old_seed.values() + new_seed.values():
            held += texture.bytes
        record.reseed(new_seed)

    var forward := {"space": target, "chunks": after, "schemas": schemas_after, "seeds": seeds_after}
    var back := {"space": source, "chunks": before, "schemas": schemas_before, "seeds": seeds_before}
    _put_schemas(schemas_after)
    _document.history.commit_pair(STEP, apply.bind(forward), apply.bind(back), held)
    _settle(target)
    return true


## Undo and redo, the descriptor, every layer's schema, its chunks and every
## seed together, copied out of the step so what it holds stays as it was.
## Public because `UndoRedo` binds it as a callable.
func apply(state: Dictionary) -> void:
    var schemas: Array[Dictionary] = state["schemas"]
    _put_schemas(schemas)
    for entry: Dictionary in state["chunks"]:
        var chunks: Dictionary[Vector2i, SaChunk] = entry["chunks"]
        var held := SaTyped.chunks(entry["held"])
        for grid_pos: Vector2i in held:
            chunks[grid_pos] = held[grid_pos].duplicate_chunk()
    for entry: Dictionary in state["seeds"]:
        var stepped: SaLayer = entry["layer"]
        var record := SaSimulation.record_of(stepped)
        var kept: Dictionary[Vector2i, SaTexture] = entry["seed"]
        if record != null:
            record.reseed(_texture_copies(kept))
    var space: SaColorSpace = state["space"]
    _settle(space)


## *schema* with every colour field at *from_format* moved to *to_format*, as
## fresh specs, since a spec is shared with the undo's copy of the schema.
static func schema_at(schema: Array[SaFieldSpec], from_format: int, to_format: int) -> Array[SaFieldSpec]:
    var moved: Array[SaFieldSpec] = []
    for spec in schema:
        if spec == null or not spec.is_color or spec.format != from_format:
            moved.append(spec)
            continue
        var copy := SaFieldSpec.create(spec.id, to_format, spec.is_color, spec.derived_from.duplicate())
        copy.blank = spec.blank
        copy.lazy = spec.lazy
        moved.append(copy)
    return moved


## The reference arithmetic: *x* as a half float holds it, rounded to the
## nearest with ties to even and a finite value past [constant HALF_MAX] held
## at it with its sign. What a suite compares the card with, rather than the
## kernel under test. An infinity and a NaN come back as they went in.
static func held_by_half(x: float) -> float:
    if is_nan(x) or is_inf(x):
        return x
    if absf(x) > HALF_MAX:
        return signf(x) * HALF_MAX
    var bits := _bits_of(x)
    var magnitude := bits & 0x7fffffff
    if magnitude < _FLOAT_NORMAL_BITS:
        return 0.0
    if magnitude < _HALF_NORMAL_BITS:
        return _round_even(_float_of(bits) * _HALF_SUBNORMAL_STEPS) / _HALF_SUBNORMAL_STEPS
    var kept := (magnitude >> 13) & 1
    var rounded := (magnitude + (_HALF_DROPPED_BITS >> 1) + kept) & ~_HALF_DROPPED_BITS
    return _float_of((bits & 0x80000000) | rounded)


## *x* as a half float holds it when the dropped bits are cut off, which is what
## a card that truncates on a store writes. Beside [method held_by_half] so a
## suite can say which of the two the card's numbers are.
static func truncated_to_half(x: float) -> float:
    if is_nan(x) or is_inf(x) or absf(x) > HALF_MAX:
        return held_by_half(x)
    var bits := _bits_of(x)
    var magnitude := bits & 0x7fffffff
    if magnitude < _HALF_NORMAL_BITS:
        var steps := _float_of(bits) * _HALF_SUBNORMAL_STEPS
        return (floorf(steps) if steps >= 0.0 else ceilf(steps)) / _HALF_SUBNORMAL_STEPS
    return _float_of(bits & ~_HALF_DROPPED_BITS)


static func _bits_of(x: float) -> int:
    return PackedFloat32Array([x]).to_byte_array().decode_u32(0)


static func _float_of(bits: int) -> float:
    var bytes := PackedByteArray()
    bytes.resize(4)
    bytes.encode_u32(0, bits)
    return bytes.decode_float(0)


static func _round_even(y: float) -> float:
    var below := floorf(y)
    var part := y - below
    if part > 0.5 or (part == 0.5 and fmod(below, 2.0) != 0.0):
        return below + 1.0
    return below


## Every layer of the document at any depth that is not a cache, the stroke
## buffer among them, since each has a schema to follow the depth.
func _layers() -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    _collect(_document, found)
    if _document.stroke_layer != null:
        found.append(_document.stroke_layer)
    return found


func _collect(from: Node, into: Array[SaLayer]) -> void:
    for child: Node in from.get_children():
        var layer := child as SaLayer
        if layer == null or layer == _document.stroke_layer:
            continue
        into.append(layer)
        _collect(layer, into)


## Each chunk dictionary of [method _layers] once, with the first layer that
## holds it, whose schema says which of its fields are colour.
func _distinct_chunks() -> Array[Dictionary]:
    var found: Array[Dictionary] = []
    for layer: SaLayer in _layers():
        if layer.chunks.is_empty():
            continue
        var seen := false
        for entry: Dictionary in found:
            if is_same(entry["chunks"], layer.chunks):
                seen = true
                break
        if not seen:
            found.append({"layer": layer, "chunks": layer.chunks})
    return found


## Every layer of the document a simulation steps, whose record holds a seed.
func _stepped_layers() -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for layer: SaLayer in _layers():
        if SaSimulation.record_of(layer) != null:
            found.append(layer)
    return found


## Every texture the step weighs: each chunk's fields once and each seed.
func _held_textures() -> Array[SaTexture]:
    var found: Array[SaTexture] = []
    for entry: Dictionary in _distinct_chunks():
        var chunks: Dictionary = entry["chunks"]
        for chunk: SaChunk in chunks.values():
            for texture: SaTexture in chunk.fields.values():
                if texture != null:
                    found.append(texture)
    for stepped: SaLayer in _stepped_layers():
        for texture: SaTexture in SaSimulation.record_of(stepped).seed_chunks.values():
            found.append(texture)
    return found


## *chunk* with each colour field at *from_format* written again at
## *to_format*, and every other field copied as it is, so a later stroke on the
## mask of the converted chunk leaves the undo's old chunk alone.
func _converted_chunk(chunk: SaChunk, layer: SaLayer, from_format: int, to_format: int, narrowing: bool) -> SaChunk:
    var fresh := SaChunk.new()
    fresh.resolution_scale = chunk.resolution_scale
    fresh.blanks = chunk.blanks.duplicate()
    for field_id: StringName in chunk.fields:
        var texture: SaTexture = chunk.fields[field_id]
        if texture == null:
            continue
        if texture.format == from_format and layer.is_color_field(field_id):
            fresh.fields[field_id] = _converted(texture, to_format, narrowing)
        else:
            fresh.fields[field_id] = _texture_copy(texture)
    return fresh


## A new texture at *format* holding *texture*'s texels, through the kernel.
##
## Kernels are compiled once per storage format, and this one has two: the
## variant is picked by the source's format, `use_storage_format`, and the
## target binding is pointed at its own with `use_binding_format`, which every
## image declaring the storage-format token allows. So F32 to F16 and F16 to
## F32 are two variants of one kernel, each compiled on its first use.
func _converted(texture: SaTexture, format: int, narrowing: bool) -> SaTexture:
    var into := SaTexture.new(texture.size, format)
    if _converter == null:
        _converter = SaCompute.new("precision_convert")
    _converter.use_storage_format(texture.format)
    _converter.use_binding_format(1, format)
    _converter.set_texture(0, texture.rid)
    _converter.set_texture(1, into.rid)
    _converter.set_push_constant_float_array(PackedFloat32Array([1.0 if narrowing else 0.0, 0.0, 0.0, 0.0]))
    _converter.dispatch_kernel("precision_convert", SaCompute.groups_for(texture.size.x), SaCompute.groups_for(texture.size.y), 1)
    return into


static func _copies(chunks: Dictionary[Vector2i, SaChunk]) -> Dictionary[Vector2i, SaChunk]:
    var copied: Dictionary[Vector2i, SaChunk] = {}
    for grid_pos: Vector2i in chunks:
        copied[grid_pos] = chunks[grid_pos].duplicate_chunk()
    return copied


static func _texture_copies(textures: Dictionary[Vector2i, SaTexture]) -> Dictionary[Vector2i, SaTexture]:
    var copied: Dictionary[Vector2i, SaTexture] = {}
    for grid_pos: Vector2i in textures:
        copied[grid_pos] = _texture_copy(textures[grid_pos])
    return copied


## A GPU copy of *source*, counted as a snapshot the way `SaChunk.duplicate_chunk`
## counts one.
static func _texture_copy(source: SaTexture) -> SaTexture:
    var copy := SaTexture.new(source.size, source.format)
    var rd := GlobalShaderCompiler.get_rd()
    if rd != null:
        rd.texture_copy(source.rid, copy.rid, Vector3.ZERO, Vector3.ZERO, Vector3(source.size.x, source.size.y, 1), 0, 0, 0, 0)
        SaTexture.note_copy(copy.bytes)
    return copy


static func _put_schemas(schemas: Array) -> void:
    for entry: Dictionary in schemas:
        var layer: SaLayer = entry["layer"]
        if layer != null and is_instance_valid(layer):
            var schema: Array[SaFieldSpec] = entry["schema"]
            layer.schema = schema


## The descriptor at its new depth and everything drawn from it told. The
## view's output follows the depth through the resize every view hears, at the
## size it had, so nothing moves on the screen.
func _settle(space: SaColorSpace) -> void:
    _document.color_space = space
    for layer: SaLayer in _layers():
        layer.mark_all_unresolved()
    _document.update_caches()
    _document.invalidate_all_allocated_chunks()
    _document.resize_source = Rect2i(Vector2i.ZERO, _document.canvas_size)
    EventBus.document_resized.emit(_document, _document.canvas_size)
    _document.resize_source = Rect2i()
    _document.document_changed.emit()
