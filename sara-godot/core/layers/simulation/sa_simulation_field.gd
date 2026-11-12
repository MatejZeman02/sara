## The field a rule declares of its own, on the one layer a record holds it
## for: what [SaSimulation.State] names, put into the layer's schema, seeded
## from the paint, and coloured into `albedo` through the layer's resolve hook.
## The record owns it and hands it the layer at every call, so like the record
## it holds no reference to the layer.
##
## **The schema** carries the field for as long as the record is on the layer,
## beside an `albedo` worked out from it, the same depth and colour space as
## before but derived, so a brush's walk and a fill with a selection leave it to
## the hook (`SaChunkWalk._fields_of`). Every chunk the layer holds gains a
## texture of the field, and one a ring or a stroke allocates later gains one
## from the schema. Taking it off resolves what is stale first, so `albedo`
## holds the colour last resolved, then takes the field out of every chunk and
## the schema, and puts the `albedo` back as it was declared, painted, with the
## hook the layer had before.
##
## **The seed** is the rule's seed kernel over the record's copies of the paint
## as last painted, chunk by chunk, after the painted colour is summed over
## every copy by `simulation_tint`. A texture the field gains here is written
## whole by that kernel rather than cleared, since a clear is a transfer and the
## kernel is compute, which are not ordered inside a frame. It stays in VRAM, the sum and the
## colour included (hard rule 1).
##
## **The colour** is the rule's colour kernel, run by `SaLayer.resolve_pending`
## for a chunk whose field a step, a seed or a reset moved, and only for that
## chunk (hard rule 2), from the field and the painted colour into `albedo`.
class_name SaSimulationField
extends RefCounted

## The field, as the rule declares it.
var spec: SaFieldSpec = null

## What the rule's kernels are, and where.
var _state: SaSimulation.State = null
## The `albedo` the layer declared before the field, put back when it goes.
var _painted: SaFieldSpec = null
## The resolve hook the layer had before, put back when the field goes.
var _hook: Callable = Callable()
## The running sum of the seed's cover-weighted colour, and the colour itself,
## one texel each.
var _sum: SaTexture = null
var _tint: SaTexture = null
var _summer: SaCompute = null
var _kernels: SaCompute = null


## *state* on *layer*: the field in every chunk and the schema, the hook set.
## A chunk's texture of the field at its side and format is kept. Nothing is
## seeded until [method seed].
func _init(layer: SaLayer, state: SaSimulation.State) -> void:
    _state = state
    spec = state.field
    _painted = SaFieldSpec.find(layer.schema, SaFieldSpec.ALBEDO)
    _hook = layer.resolve_hook
    _sum = SaTexture.new(Vector2i.ONE, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
    _tint = SaTexture.new(Vector2i.ONE, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
    _summer = SaCompute.new("simulation_tint")
    _kernels = SaCompute.new(state.shader)
    for grid_pos: Vector2i in layer.chunks:
        _texture_in(layer.chunks[grid_pos])
    var sources: Array[StringName] = [spec.id]
    var worked_out := SaFieldSpec.create(SaFieldSpec.ALBEDO, _painted.format, _painted.is_color, sources)
    var with_field: Array[SaFieldSpec] = []
    # A field of the same name is the one a file kept, whose textures stay.
    for kept in layer.schema:
        if kept != null and kept.id != spec.id:
            with_field.append(worked_out if kept.id == SaFieldSpec.ALBEDO else kept)
    with_field.append(spec)
    layer.schema = with_field
    layer.resolve_hook = colour


## The painted colour summed over every copy *seeds* holds, then the field at
## each of *grid_positions* the layer holds seeded from its copy there. A
## position the seed holds no copy at is left as it is. Every position seeded
## is marked for the hook.
func seed(layer: SaLayer, seeds: Dictionary[Vector2i, SaTexture], grid_positions: Array) -> void:
    _sum_tint(seeds)
    for grid_pos: Vector2i in grid_positions:
        var chunk: SaChunk = layer.chunks.get(grid_pos, null)
        var kept: SaTexture = seeds.get(grid_pos, null)
        if chunk == null or kept == null:
            continue
        var into := _texture_in(chunk)
        _dispatch(_state.seed_kernel, kept, into, grid_pos)
        layer.mark_unresolved(grid_pos)


## The hook: *chunk* of *layer* at *grid_pos* coloured from its field into its
## `albedo`. A chunk with no texture of the field is left as it is.
func colour(_layer: SaLayer, grid_pos: Vector2i, chunk: SaChunk) -> void:
    var held := chunk.field(spec.id)
    var albedo := chunk.albedo()
    if held == null or albedo == null:
        return
    _dispatch(_state.colour_kernel, albedo, held, grid_pos)


## The field off *layer*: the stale chunks coloured first, the field out of
## every chunk and the schema, `albedo` painted again, and the old hook back.
func release(layer: SaLayer) -> void:
    layer.resolve_pending()
    for grid_pos: Vector2i in layer.chunks:
        layer.chunks[grid_pos].drop_field(spec.id)
    var without: Array[SaFieldSpec] = []
    for kept in layer.schema:
        if kept != null and kept.id != spec.id:
            without.append(_painted if kept.id == SaFieldSpec.ALBEDO else kept)
    layer.resolve_hook = _hook
    layer.schema = without


## The texture of the field in *chunk*, made at the chunk's side when it has
## none or one of another size, and left unwritten for the seed kernel.
func _texture_in(chunk: SaChunk) -> SaTexture:
    var edge := chunk.pixel_size()
    var held := chunk.field(spec.id)
    if held == null or held.size != Vector2i(edge, edge) or held.format != spec.format:
        held = SaTexture.new(Vector2i(edge, edge), spec.format)
        chunk.fields[spec.id] = held
    return held


## *kernel* of the rule's pair with *paint* at `paint`, *held* at `field` and
## the painted colour at `tint`, over one chunk at *grid_pos*.
func _dispatch(kernel: String, paint: SaTexture, held: SaTexture, grid_pos: Vector2i) -> void:
    _kernels.use_storage_format(paint.format)
    _kernels.set_image("paint", paint)
    _kernels.set_image("field", held)
    _kernels.set_image("tint", _tint)
    var given: Dictionary[String, Variant] = {"chunk": Vector2(grid_pos * held.size.x), "step": 0}
    if not GlobalShaderCompiler.push_constant_layout(_state.shader).is_empty():
        _kernels.set_params(_declared(given))
    _kernels.dispatch_kernel(kernel, SaCompute.groups_for(held.size.x), SaCompute.groups_for(held.size.y), 1)


## The painted colour, summed over *seeds* in the order it lists them.
func _sum_tint(seeds: Dictionary[Vector2i, SaTexture]) -> void:
    var first := 1.0
    if seeds.is_empty():
        _tint.clear(SaFieldSpec.NO_PAINT)
        return
    for grid_pos: Vector2i in seeds:
        var kept: SaTexture = seeds[grid_pos]
        _summer.use_storage_format(kept.format)
        _summer.set_image("paint", kept)
        _summer.set_image("sum", _sum)
        _summer.set_image("tint", _tint)
        _summer.set_params({"first": first})
        _summer.dispatch_kernel("simulation_tint", 1, 1, 1)
        first = 0.0


## *given* kept to the names the rule's colouring block declares, `chunk` and
## `step` or neither, since a push constant refuses a name its block does not
## have.
func _declared(given: Dictionary[String, Variant]) -> Dictionary[String, Variant]:
    var out: Dictionary[String, Variant] = {}
    for raw: Variant in GlobalShaderCompiler.push_constant_layout(_state.shader):
        var named := SaTyped.text_at(SaTyped.strings(raw), "name", "")
        if given.has(named):
            out[named] = given[named]
    return out
