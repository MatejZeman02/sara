## A document written as OpenRaster, the open format Krita, GIMP and MyPaint
## read, so a painter who carries on elsewhere keeps the layers.
##
## The file is a zip: `mimetype` first, `stack.xml` stacking the layers top
## first, one PNG a layer under `data/`, `Thumbnails/thumbnail.png` no larger
## than 256 pixels, and `mergedimage.png`, which is byte for byte the PNG
## [method SaPictureFile.png_bytes] writes, so a viewer that reads only that
## shows what Sara shows.
##
## **What carries over.** A paint layer is one PNG cut to the chunks it holds,
## placed by `x` and `y`. A group is a nested `stack`. Opacity and visibility go
## on every element. A blend mode OpenRaster names is its `svg:` operator, and
## any other is written as normal, which [method fallen_back] lists and
## [method losses] says for the dialog before the painter confirms.
##
## **A pass-through group** is written the way MyPaint writes one, a stack at
## full opacity and `svg:src-over` with `isolation="auto"`, with the group's
## opacity moved onto each member. Krita and Sara's own reader draw that as Sara
## does. GIMP 3.2 reads no `isolation` and isolates every stack, so a mode inside
## such a group blends with the group alone, and [method passed_through] names
## those groups for the dialog.
##
## **What is baked.** OpenRaster has no masks, filters, clipping or generated
## layers, so a layer is written as the pixels it shows, in the compositor's
## order. A group's own mask and filters have no pixels to go into and are left
## out, which [method dropped] names for the dialog. The relief is not baked,
## because a light baked into each layer is one no reader could turn off, and
## `mergedimage.png` is unlit as well. The `.sad` is what keeps the height.
##
## **The pixels** go through [SaPictureFile] at the PNG export's depths. Chunks
## are read back one at a time and assembled on the CPU, so no texture the size
## of a layer is ever made (hard rules 1 and 2).
##
## **The zip** is written by [SaZipStored] with every entry stored (method 0), so
## `image/openraster` stands at byte 38 where a format sniffer looks.
## `ZIPPacker` writes method 8 whatever level it is asked for, and the PNGs are
## compressed already.
class_name SaExportOra
extends RefCounted

const MIMETYPE: String = "image/openraster"
const STACK_VERSION: String = "0.0.5"
## The longest edge the thumbnail may have, from the OpenRaster spec.
const THUMBNAIL_EDGE: int = 256
## Sara's blend modes that OpenRaster names, as the operator it names each by.
## A mode missing here is written as `svg:src-over`.
const COMPOSITE_OPS: Dictionary[StringName, String] = {
    &"normal": "svg:src-over",
    &"multiply": "svg:multiply",
    &"screen": "svg:screen",
    &"overlay": "svg:overlay",
    &"darken": "svg:darken",
    &"lighten": "svg:lighten",
    &"color_dodge": "svg:color-dodge",
    &"hard_light": "svg:hard-light",
    &"soft_light": "svg:soft-light",
    &"difference": "svg:difference",
    &"color": "svg:color",
    &"lightness": "svg:luminosity",
    &"hue": "svg:hue",
    &"saturation": "svg:saturation",
    &"add": "svg:plus",
    # Krita writes its own modes as `krita:` and the op's id, and Signed Add is
    # its Grain Merge, so Krita opens the layer in the same mode.
    &"signed_add": "krita:grain_merge",
    # OpenRaster names no Divide, and Krita writes its own as `krita:divide`.
    &"divide": "krita:divide",
    # OpenRaster names no Hard Mix either. Krita's own `hard_mix` is another
    # formula, and its `hard_mix_photoshop` is the one Sara draws: full on
    # where the two channels together reach white.
    &"hard_mix": "krita:hard_mix_photoshop",
    &"erase": "svg:dst-out",
}
const NORMAL_OP: String = "svg:src-over"

var _document: SaDocument
var _bits: int
var _tonemap: PackedFloat32Array
var _mapping: String
## Whether an eight-bit PNG in the file is rounded through the dither, the
## merged picture, every layer and the thumbnail alike.
var _dither: bool
var _metadata: SaExportMetadata
var _space: SaColorSpace
var _canvas_size: Vector2i
var _compositor: SaCompositor
## The PNGs the stack names, `data/<n>.png` to their bytes, in the order the
## stack was walked.
var _layers: Dictionary[String, PackedByteArray] = {}


## *bits* is 8 or 16, *tonemap* the rolloff's push constant or empty,
## *mapping* a key of `SaGamutMapping.MODES` and *dither* the eight-bit
## rounding's switch, each as a PNG export takes it. A
## null *metadata* is an export made now, read once so every PNG in the file
## names the same moment.
func _init(
    document: SaDocument,
    bits: int = 8,
    tonemap: PackedFloat32Array = PackedFloat32Array(),
    mapping: String = SaGamutMapping.CLIP,
    metadata: SaExportMetadata = null,
    dither: bool = false
) -> void:
    _document = document
    _bits = bits
    _tonemap = tonemap
    _mapping = mapping
    _dither = dither
    _metadata = metadata if metadata != null else SaExportMetadata.now()
    if document != null:
        _space = document.color_space
        _canvas_size = document.canvas_size
        _compositor = document.compositor


## Exports the document *easel* shows as an OpenRaster file to *path*, the
## Export dialog's writer, with *bits*, *tonemap*, *mapping* and *dither* as a
## PNG export takes them.
##
## Colour only, with no relief baked: the file keeps the layers, and a light
## baked into each would be a light no reader could turn off. The `.sad` is
## what keeps the height.
static func export(
    easel: SaEasel,
    path: String,
    bits: int = 8,
    tonemap: bool = false,
    mapping: String = SaGamutMapping.CLIP,
    dither: bool = false
) -> Error:
    if easel == null or easel.document == null:
        push_error("SaExportOra.export: no easel or no document")
        return ERR_INVALID_PARAMETER
    SaPictureFile.flush(easel)
    var ora := SaExportOra.new(easel.document, bits, SaPictureFile.tonemap_of(easel, tonemap), mapping, null, dither)
    return ora.write(easel.output, path)


## Writes the document and *output*, its composite, to *path*.
func write(output: SaTexture, path: String) -> Error:
    if _document == null or _compositor == null or output == null:
        push_error("SaExportOra.write: no document, compositor or output")
        return ERR_INVALID_PARAMETER
    if _bits != 8 and _bits != 16:
        push_error("SaExportOra.write: a layer holds 8 or 16 bits a channel, not %d" % _bits)
        return ERR_INVALID_PARAMETER
    var space := _space
    var merged := SaPictureFile.png_bytes(output, space, _bits, _tonemap, _mapping, _metadata, _dither)
    var thumbnail := _thumbnail(output)
    if merged.is_empty() or thumbnail.is_empty():
        return ERR_CANT_ACQUIRE_RESOURCE
    _layers.clear()
    var stack := stack_xml(output.format)
    var zip := SaZipStored.new(path, _metadata.unix_time + _metadata.zone_minutes * 60)
    var entries: Array = [["mimetype", MIMETYPE.to_ascii_buffer()], ["stack.xml", stack.to_utf8_buffer()]]
    for entry: String in _layers:
        entries.append([entry, _layers[entry]])
    entries.append(["Thumbnails/thumbnail.png", thumbnail])
    entries.append(["mergedimage.png", merged])
    for entry: Array in entries:
        var entry_path: String = entry[0]
        var entry_bytes: PackedByteArray = entry[1]
        var err := zip.add(entry_path, entry_bytes)
        if err != OK:
            push_error("SaExportOra.write: cannot write '%s' into '%s' (err %d)" % [entry[0], path, err])
            return err
    return zip.close()


## The whole of `stack.xml`, rendering every layer's PNG into [member _layers]
## on the way. *format* is the output's, which a generated layer is evaluated
## at.
func stack_xml(format: int) -> String:
    var dpi := str(roundi(_document.dpi))
    var size := _canvas_size
    var lines := PackedStringArray(['<?xml version="1.0" encoding="UTF-8"?>'])
    lines.append('<image version="%s" w="%d" h="%d" xres="%s" yres="%s">' % [STACK_VERSION, size.x, size.y, dpi, dpi])
    lines.append("  <stack>")
    _append_members(lines, null, "    ", format)
    lines.append("  </stack>")
    lines.append("</image>")
    return "\n".join(lines) + "\n"


## *group*'s members into *lines*, the top one first as OpenRaster stacks
## them, where Sara keeps them bottom first. *factor* is the opacity of the
## pass-through groups around them up to the nearest isolated one, which each
## member carries in its own while those groups are written at full opacity.
func _append_members(lines: PackedStringArray, group: SaLayer, indent: String, format: int, factor: float = 1.0) -> void:
    var members := SaLayerStack.members(_document, group)
    members.reverse()
    for node in members:
        var opacity := node.opacity * factor
        if _passes_through(node):
            lines.append('%s<stack %s isolation="auto">' % [indent, _attributes(node, 1.0, NORMAL_OP)])
            _append_members(lines, node, indent + "  ", format, opacity)
            lines.append("%s</stack>" % indent)
            continue
        var shared := _attributes(node, opacity, composite_op(node.get_blend_mode_name()))
        if node.is_group:
            lines.append('%s<stack %s isolation="isolate">' % [indent, shared])
            _append_members(lines, node, indent + "  ", format)
            lines.append("%s</stack>" % indent)
            continue
        var entry := "data/layer%d.png" % _layers.size()
        var placed := _layer_png(node, format)
        _layers[entry] = placed["bytes"]
        var at: Vector2i = placed["at"]
        var selected := ' selected="true"' if node == _document.active_layer else ""
        lines.append('%s<layer %s src="%s" x="%d" y="%d"%s/>' % [indent, shared, entry, at.x, at.y, selected])


## What a layer and a stack both carry: name, visibility, and the *opacity*
## and operator *op* it is written at.
static func _attributes(node: SaLayer, opacity: float, op: String) -> String:
    return (
        'name="%s" opacity="%s" visibility="%s" composite-op="%s"'
        % [String(node.name).xml_escape(true), String.num(opacity, 4), "visible" if node.visible else "hidden", op]
    )


## The operator OpenRaster writes *mode* as, normal's for a mode it has none for.
static func composite_op(mode: StringName) -> String:
    return SaTyped.text_at(COMPOSITE_OPS, mode, NORMAL_OP)


## Every layer and group whose mode is written as normal, because OpenRaster
## names no operator for it, in the document's order. A pass-through group is
## not one of them: it is written as normal whatever its mode, which Sara does
## not draw either.
static func fallen_back(document: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for node in _every_layer(document):
        if not COMPOSITE_OPS.has(node.get_blend_mode_name()) and not _passes_through(node):
            found.append(node)
    return found


## Every group whose mask or enabled filters are left out, because a group has
## no pixels of its own to bake them into.
static func dropped(document: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for node in _every_layer(document):
        if SaLayerStack.held_isolated(node):
            found.append(node)
    return found


## Every pass-through group a reader that isolates every stack, as GIMP does,
## draws otherwise than Sara, in the document's order: one holding a member
## written with an operator other than normal's, which reads the layers below
## the group in Sara and the group alone there. A pass-through group inside it
## is looked through, since it is isolated there as well. A group of normal
## members draws the same either way, its opacity being on its members.
static func passed_through(document: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for node in _every_layer(document):
        if _passes_through(node) and _blends_below(document, node):
            found.append(node)
    return found


## Whether a member of pass-through *group*, or of a pass-through group inside
## it, is written with an operator other than normal's.
static func _blends_below(document: SaDocument, group: SaLayer) -> bool:
    for node in SaLayerStack.members(document, group):
        if _passes_through(node):
            if _blends_below(document, node):
                return true
        elif composite_op(node.get_blend_mode_name()) != NORMAL_OP:
            return true
    return false


## What a file of *document* loses, a sentence each in the words the export
## dialog says before the painter confirms, and empty when it loses nothing:
## the modes written as normal, the groups whose mask or filters are left out,
## and the pass-through groups a reader that isolates every stack draws
## otherwise. A mode is named by its id as the file would have said it, since
## the registry's label is not in reach of the writer.
static func losses(document: SaDocument) -> PackedStringArray:
    var said := PackedStringArray()
    var fallen := PackedStringArray()
    for layer in fallen_back(document):
        fallen.append("%s (%s)" % [layer.name, String(layer.get_blend_mode_name()).capitalize()])
    if not fallen.is_empty():
        said.append(TranslationServer.translate("OpenRaster has no mode for %s, so written as Normal.") % ", ".join(fallen))
    var left_out := _names(dropped(document))
    if not left_out.is_empty():
        said.append(TranslationServer.translate("The mask and filters of %s are left out.") % left_out)
    var passing := _names(passed_through(document))
    if not passing.is_empty():
        var sentence := "A program such as GIMP draws %s isolated, and the modes inside then blend with the group alone."
        said.append(TranslationServer.translate(sentence) % passing)
    return said


## The names of *nodes* joined for a sentence, empty for none.
static func _names(nodes: Array[SaLayer]) -> String:
    var names := PackedStringArray()
    for node in nodes:
        names.append(String(node.name))
    return ", ".join(names)


## Whether *node* is a group Sara draws passing through, its members blended
## straight into the layers below it.
static func _passes_through(node: SaLayer) -> bool:
    return node.is_group and not SaLayerStack.isolates(node)


## The document's layers and groups bottom first, the way it holds them, which
## is what `SaLayerStack.members` walks. `SaLayerStack.layers` is the
## compositor's walk and holds its caches.
static func _every_layer(document: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    if document == null:
        return found
    for child in document.get_children():
        if child is SaLayer:
            found.append(child as SaLayer)
    return found


## *node*'s PNG and where it sits, `{"bytes", "at"}`: the chunks it shows,
## cut to their bounds on the canvas, or one transparent pixel at the origin
## when it shows none.
func _layer_png(node: SaLayer, format: int) -> Dictionary[String, Variant]:
    var side := SaChunk.SIZE
    var canvas := Rect2i(Vector2i.ZERO, _canvas_size)
    var positions := _positions(node)
    var bounds := Rect2i()
    for grid_pos: Vector2i in positions:
        var cell := Rect2i(grid_pos * side, Vector2i(side, side)).intersection(canvas)
        bounds = cell if bounds.size == Vector2i.ZERO else bounds.merge(cell)
    var image_format := Image.FORMAT_RGBAF if _bits == 16 else Image.FORMAT_RGBA8
    var image: Image = null
    if bounds.has_area():
        image = Image.create_empty(bounds.size.x, bounds.size.y, false, image_format)
        for grid_pos: Vector2i in positions:
            _blit_chunk(image, node, grid_pos, bounds, format)
    else:
        bounds = Rect2i(Vector2i.ZERO, Vector2i.ONE)
        image = Image.create_empty(1, 1, false, image_format)
    var encoded := SaPictureFile.png16(image) if _bits == 16 else image.save_png_to_buffer()
    return {"bytes": SaPictureFile.named_png(encoded, _space, _metadata), "at": bounds.position}


## The grid positions *node* can show something at: every one of the canvas
## for a generated layer, and for a paint layer its chunks with the ring its
## filters carry paint into, cut to the canvas grid.
func _positions(node: SaLayer) -> Dictionary[Vector2i, bool]:
    if node.is_generated():
        var every: Dictionary[Vector2i, bool] = {}
        for grid_pos in SaLayer.grid_positions(_canvas_size):
            every[grid_pos] = true
        return every
    var kept: Dictionary[Vector2i, bool] = {}
    var side := float(SaLayer.CHUNK_SIZE)
    var limit := Rect2i(0, 0, ceili(_canvas_size.x / side), ceili(_canvas_size.y / side))
    for grid_pos: Vector2i in _compositor.filter_chain.walked(node, SaTyped.positions(node.chunks)):
        if limit.has_point(grid_pos):
            kept[grid_pos] = true
    return kept


## What *node* shows at *grid_pos*, encoded the way a PNG export encodes it,
## into *image*, which covers *bounds* of the canvas.
func _blit_chunk(image: Image, node: SaLayer, grid_pos: Vector2i, bounds: Rect2i, format: int) -> void:
    var shown := _shown(node, grid_pos, format)
    if shown == null:
        return
    var origin := grid_pos * SaChunk.SIZE
    var cell: Image
    if _bits == 16:
        cell = SaPictureFile.encoded_image(shown, _space, _tonemap, _mapping)
    else:
        # The chunk's own corner in the picture, so its dither is the merged
        # picture's at the same texel and the chunks meet with no seam.
        cell = SaPictureFile.encoded_byte_image(shown, _space, _tonemap, _mapping, _dither, origin)
    if cell == null:
        return
    var inside := Rect2i(origin, cell.get_size()).intersection(bounds)
    if not inside.has_area():
        return
    if cell.get_format() != image.get_format():
        cell.convert(image.get_format())
    image.blit_rect(cell, Rect2i(inside.position - origin, inside.size), inside.position - bounds.position)


## *node*'s texels at *grid_pos* as the compositor draws them before the blend:
## a generated layer's kernel, the filters, the mask and then the clip, in
## the tree render's order. Null where it shows nothing. The texture is one of
## the compositor's scratches, read before anything else is asked of it.
func _shown(node: SaLayer, grid_pos: Vector2i, format: int) -> SaTexture:
    var compositor := _compositor
    var whole := Rect2i(Vector2i.ZERO, Vector2i(SaChunk.SIZE, SaChunk.SIZE))
    var source: SaTexture
    if node.is_generated():
        var generated := compositor.generate_chunk(node, Vector2(grid_pos * SaChunk.SIZE), whole, format)
        source = compositor.shown(node, node, generated, grid_pos, whole)
    else:
        source = compositor.shown(node, node, node.get_field(grid_pos), grid_pos, whole, node)
    if source == null:
        return null
    var base := SaLayerStack.clip_base(_document, node)
    if base == null:
        return source
    var alpha := compositor.clip_alpha(base, grid_pos, whole)
    return compositor.clip_chunk(source, alpha, whole) if alpha != null else null


## `Thumbnails/thumbnail.png`: the picture at eight bits, scaled to fit
## [const THUMBNAIL_EDGE] and never up.
func _thumbnail(output: SaTexture) -> PackedByteArray:
    var space := _space
    var picture := SaPictureFile.encoded_byte_image(output, space, _tonemap, _mapping, _dither)
    if picture == null:
        return PackedByteArray()
    var longest := maxi(picture.get_width(), picture.get_height())
    if longest > THUMBNAIL_EDGE:
        var scale := float(THUMBNAIL_EDGE) / float(longest)
        var fitted := Vector2i(maxi(1, roundi(picture.get_width() * scale)), maxi(1, roundi(picture.get_height() * scale)))
        picture.resize(fitted.x, fitted.y, Image.INTERPOLATE_LANCZOS)
    return SaPictureFile.named_png(picture.save_png_to_buffer(), space, _metadata)
