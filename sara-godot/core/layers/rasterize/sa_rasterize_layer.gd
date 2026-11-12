## Layer > Rasterize Layer: whatever a layer is more than its pixels, written
## into a plain paint layer that looks as it did, in one undoable step. It is
## Photoshop's Rasterize Layer and Krita's Convert to Paint Layer.
##
## **What it folds in.** A live transform, the mask, every enabled filter and
## the relief, all at once, where Convert to Ordinary Layer, Apply Mask and
## Rasterize Impasto each fold one of them. A generated layer, a ground among
## them, a scene layer, an effect layer, a drawn one and a simulated one become
## paint of what they show, a drawn layer's chunks copied as they stand and its
## recipe left behind. A group is left to Merge, and an adjustment layer to Merge
## Down, since neither has a picture of its own to keep.
##
## **Drawn the way the compositor draws it.** Each chunk is the layer's paint,
## its live transform's cache when it carries one, or its generator's kernel,
## run through `SaCompositor.shown`: the filters, then the mask, which is the
## walk `SaTreeRender` takes for a merge. The blend is left out, so the new
## layer keeps the name, opacity, blend mode, clip and place of the old one and
## is composited exactly as it was. A layer at double resolution is drawn
## through a fine `SaLayerShown`, the one `SaLayerGroups.BakeShown` uses, and
## keeps its density. A relief is lit into each chunk by the light Rasterize
## Impasto lights by, resolved before the layer leaves, so what the view lit is
## in the pixels and the new layer carries no height.
##
## **Over its own footprint.** One dispatch a chunk, at the positions the layer
## holds and the ring its filters' halo reaches, or for a generated layer at the
## grid positions it covers, so hard rule 2 holds and nothing is read back.
##
## **One step, the layer swapped.** The new layer takes the old one's place
## through `SaLayerOps`' keeper, and undo puts the old one back whole, with its
## mask, transform, relief and filters, the way Rasterize Impasto swaps a
## ground for paint.
class_name SaRasterizeLayer
extends RefCounted

## What the undo menu and the Layer menu call this.
const ACTION_NAME := "Rasterize Layer"

## Why the row is dimmed, the line its hover reads and the corner says.
const PLAIN := "'%s' is plain paint already, with no transform, mask, relief, filter or generator to turn into pixels."
const GROUP := "A group has no picture of its own. Merge it to turn its layers into one layer of paint."
const ADJUSTMENT := "An adjustment layer changes the layers below it. Merge Down writes it into the layer under it."
const LOCKED := "'%s' is locked. Unlock it in the Layers docker first."
const NO_LAYER := "There is no active layer to rasterize."

var _easel: SaEasel
var _document: SaDocument
var _copier: SaCompute = null
## The fine path `SaLayerShown` draws a layer at double resolution through,
## made when the first one comes.
var _fine: SaLayerShown = null


## *easel* holds the document, its compositor and the relief the view lights.
func _init(easel: SaEasel) -> void:
    _easel = easel
    _document = easel.document if easel != null else null


## Why Rasterize Layer would not act on *layer* of *document*, in the words the
## dimmed row and the corner say, or empty when it would. Quiet, because the
## Layer menu asks it on every open.
static func refusal(document: SaDocument, layer: SaLayer) -> String:
    if document == null or layer == null or layer.get_parent() != document:
        return TranslationServer.translate(NO_LAYER)
    if layer.is_group:
        return TranslationServer.translate(GROUP)
    if layer.is_adjustment():
        return TranslationServer.translate(ADJUSTMENT)
    if layer.is_locked:
        return TranslationServer.translate(LOCKED) % layer.name
    if plain(layer):
        return TranslationServer.translate(PLAIN) % layer.name
    return ""


## Whether *layer* is plain paint: pixels of its own with nothing drawn over
## or through them. A filter switched off and a mask switched off change
## nothing on screen, so neither makes it more than paint.
static func plain(layer: SaLayer) -> bool:
    if layer.is_generated() or layer.is_effect() or layer.is_scene() or layer.is_drawn():
        return false
    if layer.simulation != null or layer.live_transform != null or layer.carries_height() or layer.has_derived:
        return false
    if layer.mask != null and layer.mask.enabled:
        return false
    for record in layer.filters:
        if record != null and record.enabled:
            return false
    return true


## Whether the row is lit on *layer*.
static func can_rasterize(document: SaDocument, layer: SaLayer) -> bool:
    return refusal(document, layer).is_empty()


## Turns *layer* into a plain paint layer showing what it showed, or says in
## the corner why not. True when it happened.
func rasterize(layer: SaLayer) -> bool:
    if _easel == null or GlobalShaderCompiler.get_rd() == null or _document.compositor == null:
        return false
    if not can_rasterize(_document, layer):
        SaProblems.refuse(ACTION_NAME, SaRasterizeLayer.refusal(_document, layer))
        return false
    SaLocalView.end_contents(_document)
    layer.resolve_pending()
    var light: SaExportRelief = null
    if layer.carries_height() or (layer.is_generated() and SaGeneratedLayer.tooth_of(layer) > 0.0):
        light = SaRasterizeImpasto.new(_easel).lit_by()
    var paint := _paint_of(layer)
    for grid_pos: Vector2i in _footprint(layer):
        var chunk := _drawn(layer, paint, grid_pos)
        if chunk != null:
            SaRasterizeImpasto.light_chunk(chunk, grid_pos, light)
            paint.chunks[grid_pos] = chunk
    _swap_in(layer, paint)
    return true


## A paint layer standing for *layer*, out of the document and empty: how it
## blends, shows and sits in a group, its note and its filters switched off,
## at its density, and the document's schema, which carries no height and no
## mask.
func _paint_of(layer: SaLayer) -> SaLayer:
    var paint := SaLayer.new()
    paint.schema = SaFieldSpec.schema_for_space(_document.color_space)
    paint.resolution_scale = 1.0 if layer.is_generated() else SaFilterDensity.scale_of(layer)
    for key: StringName in [&"opacity", &"blend_mode", &"visible", &"clip_to_below", &"alpha_locked", &"comment", &"group"]:
        paint.set(key, layer.get(key))
    paint.module_data = layer.module_data.duplicate(true)
    for record in layer.filters:
        if record != null and not record.enabled:
            paint.filters.append(record.duplicate_record())
    return paint


## The grid positions *layer* shows anything at: every one a generated layer
## covers, or the chunks of its paint and the ring its filters carry paint
## into, cut to the canvas.
func _footprint(layer: SaLayer) -> Array[Vector2i]:
    if layer.is_generated():
        return SaGeneratedLayer.covered_positions(_document)
    var found: Array[Vector2i] = []
    var held: Dictionary[Vector2i, bool] = {}
    for grid_pos: Vector2i in SaLiveTransform.paint_of(layer).chunks:
        held[grid_pos] = true
    for grid_pos: Vector2i in SaTreeRender.new(_document).reach(layer, held):
        found.append(grid_pos)
    return found


## A chunk for *paint* holding what *layer* shows at *grid_pos* before its
## blend, or null where it shows nothing.
func _drawn(layer: SaLayer, paint: SaLayer, grid_pos: Vector2i) -> SaChunk:
    var compositor := _document.compositor
    var chunk := SaChunk.create(paint.schema, paint.resolution_scale)
    var albedo := chunk.albedo()
    var region := Rect2i(0, 0, SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE)
    var shown: SaTexture = null
    if layer.is_generated():
        var made := compositor.generate_chunk(layer, Vector2(grid_pos * SaLayer.CHUNK_SIZE), region, albedo.format)
        shown = compositor.shown(layer, layer, made, grid_pos, region)
    else:
        # The live transform's cache holds the mask already, so the mask is
        # read off the paint drawn, as `SaTreeRender` draws it.
        var drawn := SaLiveTransform.paint_of(layer)
        var source := drawn.get_field(grid_pos)
        if paint.resolution_scale > 1.0:
            shown = _fine_shown().shown(layer, drawn, source, grid_pos, region, drawn)
        else:
            shown = compositor.shown(layer, drawn, source, grid_pos, region, drawn)
    if shown == null:
        return null
    for field_id: StringName in chunk.field_ids():
        if field_id != SaFieldSpec.ALBEDO:
            var blank: Color = chunk.blanks.get(field_id, SaFieldSpec.NO_PAINT)
            chunk.field(field_id).clear(blank)
    _copy(shown, albedo)
    return chunk


func _fine_shown() -> SaLayerShown:
    if _fine == null:
        var compositor := _document.compositor
        _fine = SaLayerShown.new(true, compositor.filter_chain, compositor.get_compute)
    return _fine


## *source* written into *into* over the whole of *into* by the `copy_region`
## kernel, a dispatch rather than a transfer, because the light that follows
## is compute and the two are not ordered inside a frame.
func _copy(source: SaTexture, into: SaTexture) -> void:
    if _copier == null:
        _copier = SaCompute.new("copy_region")
    _copier.use_storage_format(into.format)
    _copier.use_binding_format(1, source.format)
    _copier.set_texture(0, into.rid)
    _copier.set_texture(1, source.rid)
    _copier.set_push_constant_float_array(PackedFloat32Array([0.0, 0.0, 0.0, 0.0, into.size.x, into.size.y, 0.0, 0.0]))
    _copier.dispatch_kernel("copy_region", SaCompute.groups_for(into.size.x), SaCompute.groups_for(into.size.y), 1)


## *paint* put in *layer*'s place under its name, and the exchange recorded
## as one step.
func _swap_in(layer: SaLayer, paint: SaLayer) -> void:
    var at := layer.get_index()
    var ops := SaLayerOps.new(_document)
    var gone := SaLayerOps.LayerKeeper.new(layer, at)
    ops.take_out(gone)
    # Once the layer is out, so the name it leaves is free.
    paint.name = layer.name
    var made := SaLayerOps.LayerKeeper.new(paint, at)
    ops.put_back(made)
    _document.modified = true
    ops.refresh()
    ops.commit_presence(ACTION_NAME, [gone, made], made.bytes())
