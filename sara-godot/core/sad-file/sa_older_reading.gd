## The layers of a file saved before a display-referred mode kept drawing above
## white whose picture changed with it, and the sentence that names them when
## the file is opened.
##
## The older reading is not kept behind the version: it would be a second
## kernel per mode that only an old file reaches, a sibling mode for every
## mode in the list. So the file opens as it draws
## now and the painter is told where that differs. A file older than the
## version `EXTENDED_ABOVE_WHITE` gives a mode drew that mode the older way.
## For a separable mode that was its formula alone, and each such mode's
## extension, "Above white" in libs/composite_blend_ops.gmacs as its kernel
## takes it, is that formula wherever both inputs are at or under white, so a
## layer's picture changed exactly where its mode met a value above white over
## a backdrop with coverage. For Hue, Saturation, Colour and Lightness it was
## the swap inside the window up to white, which changed there too, and under
## white as well on an RGB document whose white is not 1. That is what this
## asks of each such node, chunk by chunk: the backdrop it draws onto, rendered
## the way the walk renders it, then what it draws, and its mode's probe kernel
## at the end of composite.gmacs over the pair, read back as whether any texel
## met one.
##
## What it draws is the node's own picture through its records and its mask,
## and the clip is left out, which can only name a layer whose clip hid every
## texel that met white. A layer that is hidden is still named, because it
## draws differently the moment it is shown. A pass-through group's mode is
## never applied, so it is never named. An adjustment layer draws its backdrop
## filtered, so that is its picture, and its records read neighbours that are
## not there, the way the walk reads them away from a sweep.
##
## It runs at open only, for a file older than the stamp that holds a node in
## an extended mode: one backdrop, one source and one readback of a chunk per
## chunk position such a node covers, never during a stroke.
class_name SaOlderReading
extends RefCounted

## The probe in composite.gmacs.
const PROBE := "above_white_met"
## The probe for the modes that swap components in Oklab LCh, and those modes.
const PROBE_IN_LCH := "above_white_met_in_lch"
const IN_LCH: Array[StringName] = [&"hue", &"saturation", &"color", &"lightness"]

var _document: SaDocument
var _compositor: SaCompositor
var _tree: SaTreeRender
var _backdrop: SaTexture
var _solid: SaTexture


func _init(document: SaDocument) -> void:
    _document = document
    _compositor = document.compositor
    _tree = SaTreeRender.new(document)
    var format: int = SaFieldSpec.schema_for_space(document.color_space)[0].format
    _backdrop = SaTexture.new(SaDocument.WHOLE_CHUNK.size, format)


## The nodes of *document* whose picture changed since a file of *version* was
## saved, bottom first, and none for a file this build's stamp already covers.
static func changed(document: SaDocument, version: int) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    if document == null or document.compositor == null or version >= SaSadFile.SAD_VERSION:
        return found
    var reading: SaOlderReading = null
    for child in document.get_children():
        var node := child as SaLayer
        if node == null or version >= SaSadFile.EXTENDED_ABOVE_WHITE.get(node.blend_mode, 0):
            continue
        if node.is_group and not SaLayerStack.isolates(node):
            continue
        if reading == null:
            reading = SaOlderReading.new(document)
        if reading._met_above_white(node):
            found.append(node)
    return found


## The line that tells the painter *layers* draw differently now, or an empty
## one when there are none.
static func notice(layers: Array[SaLayer]) -> String:
    if layers.is_empty():
        return ""
    var names := PackedStringArray()
    for layer in layers:
        names.append("'%s'" % layer.name)
    var line := TranslationServer.translate_plural(
        "This file comes from an older Sara, which blended bright colours differently. This layer may look different: %s.",
        "This file comes from an older Sara, which blended bright colours differently. These layers may look different: %s.",
        layers.size()
    )
    return line % ", ".join(names)


## Whether *node* met a value above white anywhere it draws.
func _met_above_white(node: SaLayer) -> bool:
    for grid_pos in _positions(node):
        _compositor.clear_scratch_batch([[_backdrop, SaDocument.WHOLE_CHUNK]])
        _tree.render_below(_backdrop, grid_pos, node)
        var source := _drawn(node, grid_pos)
        if source != null and _probe(source, PROBE_IN_LCH if IN_LCH.has(node.blend_mode) else PROBE):
            return true
    return false


## Every chunk position *node* draws at.
func _positions(node: SaLayer) -> Array[Vector2i]:
    if node.is_generated():
        return SaLayer.grid_positions(_document.canvas_size)
    if node.is_group or node.is_adjustment():
        return SaNodeInput.new(_document, node).positions()
    var out: Array[Vector2i] = []
    out.assign(node.chunks.keys())
    return out


## What *node* draws over the backdrop at *grid_pos*, read after the backdrop
## is rendered, because the compositor's scratch it may sit in is the walk's.
func _drawn(node: SaLayer, grid_pos: Vector2i) -> SaTexture:
    var whole := SaDocument.WHOLE_CHUNK
    if node.is_adjustment():
        var filtered := _compositor.filter_chain.filtered(node, _backdrop, grid_pos, whole)
        if filtered == null:
            return null
        if _solid == null or _solid.size != filtered.size:
            _solid = SaTexture.new(filtered.size, _backdrop.format)
        _dispatch("opaque", _solid, filtered, Rect2i(Vector2i.ZERO, filtered.size), 1.0)
        return _compositor.masked(node, _solid, grid_pos, whole)
    if node.is_group:
        return _compositor.shown(node, node, SaNodeInput.new(_document, node).at(grid_pos), grid_pos, whole)
    if node.is_generated():
        var generated := _compositor.generate_chunk(node, Vector2(grid_pos * SaLayer.CHUNK_SIZE), whole, _backdrop.format)
        return _compositor.shown(node, node, generated, grid_pos, whole)
    return _compositor.shown(node, node, node.get_field(grid_pos), grid_pos, whole, node)


## Whether *source* met a value above white over the backdrop by *kernel*, which
## overwrites it with where it did.
func _probe(source: SaTexture, kernel: String) -> bool:
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null or source.format != _backdrop.format:
        return false
    var density := SaDocumentTexels.density_of(source)
    _dispatch(kernel, _backdrop, source, Rect2i(Vector2i.ZERO, Vector2i(Vector2(source.size) / density)), density)
    var bytes := rd.texture_get_data(_backdrop.rid, 0)
    var image_format := (
        Image.FORMAT_RGBAF if _backdrop.format == RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT else Image.FORMAT_RGBAH
    )
    var met := Image.create_from_data(_backdrop.size.x, _backdrop.size.y, false, image_format, bytes)
    return met.get_used_rect().has_area()


## One dispatch of *kernel* in composite.gmacs, *source* over *target* across
## *region* of the target, with *density* of the source's texels to a pixel.
func _dispatch(kernel: String, target: SaTexture, source: SaTexture, region: Rect2i, density: float) -> void:
    var compute := _compositor.get_compute("composite")
    compute.use_storage_format(target.format)
    compute.set_texture(0, target.rid)
    compute.set_texture(1, source.rid)
    compute.set_push_constant_float_array(
        SaCompute.pack_composite_params(
            Vector2.ZERO, 1.0, _document.color_space, density, _document.blend_reference_white, region
        )
    )
    compute.dispatch_kernel(kernel, SaCompute.groups_for(region.size.x), SaCompute.groups_for(region.size.y), 1)
