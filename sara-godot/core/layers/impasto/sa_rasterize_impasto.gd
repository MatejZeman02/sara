## Layer > Rasterize Impasto: a layer's relief lit into its pixels with the
## light as it stands, and its height cleared, as one undoable step.
##
## A generated ground is rasterised too. The light is the one set at that
## moment, since a painter rarely changes the light, and the kernel is the
## export's lit bake.
##
## **The light the view shines.** The view's relief is resolved over the whole
## picture, what the window left held included, the way a flat export resolves
## it, and each chunk is lit through `SaExportRelief.light_cell`, which is the
## export's `bake_relief` kernel, with Preferences' Light direction and Relief
## strength. So what the layer's pixels take is the shading the view put over
## them a moment before: the visible surface, every layer that shows summed
## with the grounds' tooth under it. A texel with no slope under it is not
## touched, and at a strength of nought nothing is lit and the height still
## goes, which is what the view showed of it.
##
## **A paint layer** keeps its place and everything but its height. Each chunk
## is copied by compute into a new one with every field but the height, its
## colour is lit there, and the layer takes the new chunks and a schema without
## the height. The old chunks are never written, so the step holds them and
## undo swaps them back with the schema, as `SaLayerBake` swaps its chunks with
## the scale. Copied by a dispatch rather than a texture copy, because a copy is
## a transfer and the light that follows it is compute, and the two are not
## ordered inside a frame.
##
## **A ground** stores nothing, so it becomes a paint layer of its pixels:
## a new layer with the ground's place, name, blending, note and filters, its
## generator's `generate` kernel evaluated into a chunk at every grid position
## of the canvas and lit there. A ground takes no mask, so there is none to
## carry. The ground leaves with its tooth, and undo puts it back, the way a
## flatten over a ground does.
##
## **One chunk at a time.** Every dispatch is the size of one chunk, so hard
## rule 2 holds for a ground that covers the whole canvas, and nothing is read
## back.
class_name SaRasterizeImpasto
extends RefCounted

## What the undo menu and the Layer menu call this.
const ACTION_NAME := "Rasterize Impasto"

var _easel: SaEasel
var _document: SaDocument
var _copier: SaCompute = null
## Generator name -> SaCompute of that generator's `.gmacs`, for a ground's
## `generate` kernel.
var _generators: Dictionary[String, SaCompute] = {}


## *easel* holds the document and the relief the view lights it by.
func _init(easel: SaEasel) -> void:
    _easel = easel
    _document = easel.document if easel != null else null


## Whether *layer* of *document* has a relief to rasterise: a paint layer that
## carries a height, or a ground with a tooth, either of them shown and not
## locked. A layer the view does not show has no visible surface to light, and
## a locked one refuses its pixels being written. Quiet, because the Layer menu
## asks it on every open.
static func can_rasterize(document: SaDocument, layer: SaLayer) -> bool:
    if document == null or layer == null or layer.get_parent() != document or layer.is_group or layer.is_locked:
        return false
    if not SaLayerStack.contributes(document, layer):
        return false
    if layer.is_generated():
        return SaGeneratedLayer.tooth_of(layer) > 0.0
    return layer.carries_height()


## Lights *layer*'s relief into its pixels and clears its height. True when it
## happened.
func rasterize(layer: SaLayer) -> bool:
    if _easel == null or not can_rasterize(_document, layer) or GlobalShaderCompiler.get_rd() == null:
        return false
    var light := lit_by()
    if layer.is_generated():
        _rasterize_ground(layer, light)
    else:
        _rasterize_paint(layer, light)
    return true


## The export's pass over the relief the view shows now, resolved over the
## whole picture first, or null when nothing in it has relief or the strength
## is nought. Under the document's own light, the one the view draws.
## `SaRasterizeLayer` lights the chunks it draws by it too.
func lit_by() -> SaExportRelief:
    var light := _document.relief_light
    if light.strength <= 0.0:
        return null
    _easel.flush()
    var whole := Rect2(Vector2.ZERO, Vector2(_document.canvas_size))
    _easel.relief.resolve(_document, {}, {}, false, whole)
    if _easel.relief.texture == null:
        return null
    return SaExportRelief.new(_easel.relief.texture, _document.color_space, light.toward(), light.strength)


## A paint layer: every chunk lit into a copy without its height, and the
## swap of the chunks and the schema recorded as one step.
func _rasterize_paint(layer: SaLayer, light: SaExportRelief) -> void:
    layer.resolve_pending()
    var before: Dictionary[Vector2i, SaChunk] = layer.chunks.duplicate()
    var after: Dictionary[Vector2i, SaChunk] = {}
    for grid_pos: Vector2i in before:
        var chunk: SaChunk = before[grid_pos]
        if chunk != null:
            after[grid_pos] = _lit_copy(chunk, grid_pos, light)
    var flat: Array[SaFieldSpec] = []
    for spec in layer.schema:
        if spec != null and spec.id != SaFieldSpec.HEIGHT:
            flat.append(spec)
    var state: Dictionary[StringName, Variant] = {&"schema": layer.schema, &"chunks": before}
    _apply(layer, flat, after)
    if _document.history != null:
        _document.history.commit(ACTION_NAME, _swap.bind(layer, state), {}, _bytes_held(before), [state])


## A copy of *chunk* at *grid_pos* holding every field but the height, its
## colour lit by *light* when there is one.
func _lit_copy(chunk: SaChunk, grid_pos: Vector2i, light: SaExportRelief) -> SaChunk:
    var copy := SaChunk.new()
    copy.resolution_scale = chunk.resolution_scale
    for field_id: StringName in chunk.fields:
        var source: SaTexture = chunk.fields[field_id]
        if field_id == SaFieldSpec.HEIGHT or source == null or not source.rid.is_valid():
            continue
        copy.fields[field_id] = _copied(source)
        if chunk.blanks.has(field_id):
            copy.blanks[field_id] = chunk.blanks[field_id]
    light_chunk(copy, grid_pos, light)
    return copy


## A new texture holding what *source* holds, written by the `copy_region`
## kernel over the whole of it.
func _copied(source: SaTexture) -> SaTexture:
    if _copier == null:
        _copier = SaCompute.new("copy_region")
    var into := SaTexture.new(source.size, source.format)
    _copier.use_storage_format(source.format)
    _copier.use_binding_format(1, source.format)
    _copier.set_texture(0, into.rid)
    _copier.set_texture(1, source.rid)
    _copier.set_push_constant_float_array(PackedFloat32Array([0.0, 0.0, 0.0, 0.0, source.size.x, source.size.y, 0.0, 0.0]))
    _copier.dispatch_kernel("copy_region", SaCompute.groups_for(source.size.x), SaCompute.groups_for(source.size.y), 1)
    return into


## Lights the colour of *chunk*, the chunk at *grid_pos*, by *light*, at the
## density the chunk is stored at.
static func light_chunk(chunk: SaChunk, grid_pos: Vector2i, light: SaExportRelief) -> void:
    var albedo := chunk.albedo()
    if light == null or albedo == null:
        return
    var cell := Rect2i(grid_pos * SaLayer.CHUNK_SIZE, albedo.size)
    light.light_cell(albedo, cell, float(albedo.size.x) / float(SaChunk.SIZE))


## Puts *schema* and *chunks* on *layer* and tells everything that draws it,
## the relief among them, which then lets go of the height that left.
## Emptied and refilled by key, because `SaLayer.chunks` is a typed dictionary
## and refuses a plain one.
func _apply(layer: SaLayer, schema: Array[SaFieldSpec], chunks: Dictionary[Vector2i, SaChunk]) -> void:
    layer.chunks.clear()
    for grid_pos: Vector2i in chunks:
        layer.chunks[grid_pos] = chunks[grid_pos]
    layer.schema = schema
    _document.modified = true
    _document.invalidate_all_allocated_chunks()
    _document.document_changed.emit()


## The undo and the redo of a paint layer's step, which are one exchange run
## twice.
func _swap(layer: SaLayer, state: Dictionary[StringName, Variant]) -> void:
    if not is_instance_valid(layer):
        return
    var schema: Array[SaFieldSpec] = state[&"schema"]
    var chunks: Dictionary[Vector2i, SaChunk] = state[&"chunks"]
    state[&"schema"] = layer.schema
    state[&"chunks"] = layer.chunks.duplicate()
    _apply(layer, schema, chunks)


## A ground: a paint layer holding its pixels, lit, put in its place under
## its name, and the exchange of the two recorded as one step.
func _rasterize_ground(ground: SaLayer, light: SaExportRelief) -> void:
    var paint := _paint_of(ground)
    for grid_pos: Vector2i in SaLayer.grid_positions(_document.canvas_size):
        paint.chunks[grid_pos] = _generated(ground, paint.schema, grid_pos)
        light_chunk(paint.chunks[grid_pos], grid_pos, light)
    var at := ground.get_index()
    var ops := SaLayerOps.new(_document)
    var gone := SaLayerOps.LayerKeeper.new(ground, at)
    ops.take_out(gone)
    # Once the ground is out, so the name it leaves is free.
    paint.name = ground.name
    var made := SaLayerOps.LayerKeeper.new(paint, at)
    ops.put_back(made)
    _document.modified = true
    ops.refresh()
    ops.commit_presence(ACTION_NAME, [gone, made], made.bytes())


## A paint layer standing for *ground*, out of the document: what the file
## keeps of how it blends, shows and sits in a group, its note and copies of
## its filters, and the document's schema.
func _paint_of(ground: SaLayer) -> SaLayer:
    var paint := SaLayer.new()
    paint.schema = SaFieldSpec.schema_for_space(_document.color_space)
    for key: StringName in [&"opacity", &"blend_mode", &"visible", &"clip_to_below", &"alpha_locked", &"comment", &"group"]:
        paint.set(key, ground.get(key))
    paint.module_data = ground.module_data.duplicate(true)
    for record in ground.filters:
        if record != null:
            paint.filters.append(record.duplicate_record())
    return paint


## A chunk of *schema* holding *ground*'s kernel evaluated over the chunk at
## *grid_pos*, which is what the compositor draws of it there.
func _generated(ground: SaLayer, schema: Array[SaFieldSpec], grid_pos: Vector2i) -> SaChunk:
    var chunk := SaChunk.create(schema)
    var albedo := chunk.albedo()
    var compute: SaCompute = _generators.get(ground.generator)
    if compute == null:
        compute = SaCompute.new(ground.generator)
        _generators[ground.generator] = compute
    var region := Rect2i(Vector2i.ZERO, albedo.size)
    compute.use_storage_format(albedo.format)
    compute.set_texture(0, albedo.rid)
    SaGeneratedLayer.bind_params(compute, ground, Vector2(grid_pos * SaLayer.CHUNK_SIZE), region)
    compute.dispatch_kernel("generate", SaCompute.groups_for(region.size.x), SaCompute.groups_for(region.size.y), 1)
    return chunk


## What the step holds, in bytes of VRAM.
static func _bytes_held(chunks: Dictionary[Vector2i, SaChunk]) -> int:
    var total := 0
    for grid_pos: Vector2i in chunks:
        var chunk: SaChunk = chunks[grid_pos]
        if chunk != null:
            total += chunk.byte_size()
    return total
