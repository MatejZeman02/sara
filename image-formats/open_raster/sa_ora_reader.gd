## An OpenRaster file opened as a document with its layers, the partner of
## [SaExportOra], so a picture made in Krita, GIMP or MyPaint
## comes in as the stack it was painted in rather than as its flattened
## picture.
##
## **What is read.** The zip's `stack.xml` through `XMLParser`, and each layer's
## PNG out of the zip. The document is the image's `w` and `h` at its `xres`,
## and every `layer` element is a paint layer with its pixels uploaded at its
## `x` and `y`, its name, opacity, visibility and the blend mode the reversed
## [const SaExportOra.COMPOSITE_OPS] names. Every nested `stack` is a group,
## isolated when it says `isolation="isolate"`, and the `x` and `y` a stack
## carries move everything inside it. OpenRaster stacks top first and Sara
## keeps its layers bottom first, with a group's own node on top of its
## members, so the walk runs each stack backwards. `mergedimage.png` and the
## thumbnail are pictures of the layers and are not read.
##
## **The pixels.** Each PNG goes through [method SaImageImport.read_png_bytes],
## so a sixteen-bit layer keeps its sixteen bits, and is uploaded into sparse
## chunks by [method SaImageImport.upload], which allocates only where the
## layer reaches (hard rule 3). A PNG holds sRGB-encoded values, so each layer
## is converted from the gamut its own `cICP` chunk names, sRGB when it names
## none, into the document's space. The document takes the gamut the first
## layer names, which is how a file Sara wrote from a P3 document opens as P3.
## A sixteen-bit layer makes the document F32, for the reason
## [method SaImageImport.depth_for] gives: sixteen bits of integer fit in a
## full float and not in a half.
##
## **What is left out, and said.** A composite op Sara has no mode for opens
## as normal, and a layer whose `src` is not in the zip or is not a PNG is left
## out. Each is said once, in one line naming every layer it touched, rather
## than lost in silence.
##
## **Not an undoable step.** An open replaces the document, as a `.sad` load
## does, so the layers are built straight into the fresh document and the
## history is empty after. The document is left modified and nameless, as an
## image opened as a document is, because the file on disk is not a `.sad` and
## Save has to ask where. An import, [method import_into], is the other way
## in: it adds the file's layers to the document open now, as one step.
class_name SaOraReader
extends RefCounted

const STACK_ENTRY: String = "stack.xml"
## What an element without a `composite-op` means, by the spec.
const DEFAULT_OP: String = "svg:src-over"
## What a stack's `isolation` says when it isolates.
const ISOLATE: String = "isolate"

## The file being read, as the painter names it in a line.
var _path: String
## The storage depth the caller asks for when no layer decides it, -1 for F32.
var _depth: int
## The layers whose op opened as normal, and those left out, by name, after
## [method open_into]. Read by the suite, and said to the painter already.
var fallen_back: PackedStringArray = []
var left_out: PackedStringArray = []


## *depth* is a [enum SaColorSpace.Depth] for a file whose layers are all
## eight bits, and -1 leaves it at F32.
func _init(path: String, depth: int = -1) -> void:
    _path = path
    _depth = depth


## Sara's blend mode for OpenRaster's *op*, and an empty name for an op Sara
## has none for. The writer's table read backwards.
static func mode_for(op: String) -> StringName:
    if op == DEFAULT_OP:
        return SaLayer.BLEND_MODE.NORMAL
    var ops := SaExportOra.COMPOSITE_OPS
    for mode: StringName in ops:
        if ops[mode] == op:
            return mode
    return &""


## Replaces *document* with the file. OK, or the error with the reason said in
## a line the painter reads.
func open_into(document: SaDocument) -> Error:
    if document == null:
        return ERR_INVALID_PARAMETER
    var read := _read()
    if read.has("error"):
        return read["error"]
    var image: Dictionary[String, Variant] = read["image"]
    var pixels: Dictionary[int, Dictionary] = read["pixels"]
    var gamut := _gamut_of(pixels)
    var depth := _depth if _depth >= 0 else SaColorSpace.Depth.F32
    for entry: Dictionary[String, Variant] in pixels.values():
        var picture: Image = entry["image"]
        if picture.get_format() == Image.FORMAT_RGBAF:
            depth = SaColorSpace.Depth.F32
    var size := Vector2i(SaTyped.whole(image["w"]), SaTyped.whole(image["h"]))
    document.reset_to_default(size, gamut.with_depth(depth as SaColorSpace.Depth), SaTyped.real(image["xres"]))
    # The two layers a fresh document comes with go before the file's arrive,
    # so a layer the file calls Background keeps its name.
    document.active_layer = null
    document.mask_target = null
    for child in document.get_children():
        if child is SaLayer:
            child.free()
    var built := Builder.new(document, pixels, document.get_child_count())
    var root: Dictionary[String, Variant] = image["stack"]
    built.stack(root, null, Vector2i.ZERO)
    if built.first == null:
        # Nothing the file holds could be read, so the document opens with one
        # empty layer rather than with none to paint on.
        built.empty()
    fallen_back = built.fallen_back
    _finish(document, built.selected if built.selected != null else built.first)
    _say_what_was_dropped()
    return OK


## Puts the file's layers and groups into *document* above its active layer,
## in the group that layer is in, as one step Undo takes back whole. The document
## keeps its size, space and depth: each layer lands at its own offset and is
## converted from its gamut into the document's, as a PNG brought in by File >
## Import is. The layer the file marks selected is active after, the top of what
## came in when none is. The layers that came in bottom first, empty when nothing
## could be read, and said so.
func import_into(document: SaDocument) -> Array[SaLayer]:
    var none: Array[SaLayer] = []
    if document == null:
        return none
    var read := _read()
    if read.has("error"):
        return none
    var active := document.active_layer
    var at := active.get_index() + 1 if active != null else document.get_child_count()
    var pixels: Dictionary[int, Dictionary] = read["pixels"]
    var image: Dictionary[String, Variant] = read["image"]
    var root: Dictionary[String, Variant] = image["stack"]
    var built := Builder.new(document, pixels, at)
    built.stack(root, SaLayerStack.parent_of(active), Vector2i.ZERO)
    fallen_back = built.fallen_back
    _say_what_was_dropped()
    if built.block.is_empty():
        SaProblems.refuse(
            "SaOraReader",
            TranslationServer.translate("'%s' holds no layer Sara can read, nothing was imported.") % _path.get_file()
        )
        return none
    document.set_active_layer(built.selected if built.selected != null else built.block[-1])
    SaLayerOps.new(document).commit_added("Import OpenRaster", built.block)
    return built.block


## The file's `image` element as [StackXml] parses it and its readable layers'
## pixels, or an `error` with the reason said. What an open and an import share.
func _read() -> Dictionary[String, Variant]:
    fallen_back.clear()
    left_out.clear()
    var zip := ZIPReader.new()
    var err := zip.open(_path)
    if err != OK:
        SaProblems.refuse(
            "SaOraReader",
            TranslationServer.translate("Could not open '%s' as OpenRaster, it is not a zip (%s).") % [_path, error_string(err)]
        )
        return {"error": err}
    var image := StackXml.parse(zip.read_file(STACK_ENTRY) if zip.file_exists(STACK_ENTRY) else PackedByteArray())
    if image.is_empty():
        zip.close()
        SaProblems.refuse(
            "SaOraReader",
            TranslationServer.translate("Could not open '%s' as OpenRaster, its stack.xml is missing or unreadable.") % _path
        )
        return {"error": ERR_FILE_CORRUPT}
    var root: Dictionary[String, Variant] = image["stack"]
    var pixels := _decode(zip, root)
    zip.close()
    if SaTyped.whole(image["w"]) <= 0 or SaTyped.whole(image["h"]) <= 0:
        SaProblems.refuse(
            "SaOraReader", TranslationServer.translate("Could not open '%s' as OpenRaster, its image has no size.") % _path
        )
        return {"error": ERR_FILE_CORRUPT}
    return {"image": image, "pixels": pixels}


## Every readable layer's pixels and gamut, keyed by the `id` the parse gave
## its element. A `src` that is not in the zip or is
## not a PNG is named in [member left_out] and has no entry.
func _decode(zip: ZIPReader, stack: Dictionary[String, Variant]) -> Dictionary[int, Dictionary]:
    var out: Dictionary[int, Dictionary] = {}
    for node: Dictionary[String, Variant] in stack["children"]:
        if node["kind"] == "stack":
            out.merge(_decode(zip, node))
            continue
        var attrs: Dictionary[String, String] = node["attrs"]
        var src := SaTyped.text_at(attrs, "src", "")
        var bytes := zip.read_file(src) if not src.is_empty() and zip.file_exists(src) else PackedByteArray()
        if not SaPictureFile.is_png(bytes):
            left_out.append(SaTyped.text_at(attrs, "name", src))
            continue
        var picture := SaPictureFile.read_png_bytes(bytes, "%s/%s" % [_path.get_file(), src])
        if picture == null:
            left_out.append(SaTyped.text_at(attrs, "name", src))
            continue
        var primaries := SaPictureFile.png_primaries(bytes)
        var entry: Dictionary[String, Variant] = {"image": picture, "primaries": primaries}
        out[SaTyped.whole(node["id"])] = entry
    return out


## The space the first readable layer's `cICP` names, sRGB when none does.
static func _gamut_of(pixels: Dictionary[int, Dictionary]) -> SaColorSpace:
    for entry: Dictionary[String, Variant] in pixels.values():
        var named := SaPictureFile.space_for_primaries(SaTyped.whole(entry["primaries"]))
        if named != null:
            return named
        break
    return SaColorSpace.srgb()


## The document as a load leaves it: the chosen layer active, the caches
## rebuilt, and no step to take back.
static func _finish(document: SaDocument, active: SaLayer) -> void:
    # The fold still names the layers the open freed until it is rebuilt, and
    # this rebuilds it and then redraws every allocated chunk.
    document.set_active_layer(active)
    if document.undo_redo != null:
        document.undo_redo.clear_history()
    if document.history != null:
        document.history.reset()
    document.modified = true
    document.composite_requested.emit()


func _say_what_was_dropped() -> void:
    if not fallen_back.is_empty():
        SaProblems.refuse(
            "SaOraReader",
            (
                TranslationServer.translate(
                    "'%s': these layers use an operator Sara has no blend mode for and open as normal: %s."
                )
                % [_path.get_file(), ", ".join(fallen_back)]
            )
        )
    if not left_out.is_empty():
        SaProblems.refuse(
            "SaOraReader",
            (
                TranslationServer.translate(
                    "'%s': these layers are left out, because the file holds no PNG Sara can read for them: %s."
                )
                % [_path.get_file(), ", ".join(left_out)]
            )
        )


## `stack.xml` as a tree: the `image` element's size and resolution, and its
## root `stack` as nested dictionaries of `kind`, `attrs`, `children` and an
## `id` counting elements in the file's order, the children top first as the
## file lists them. The `id` is what tells two elements with the same
## attributes apart, which a dictionary key by value would not.
class StackXml:
    extends RefCounted

    ## The tree, or an empty dictionary when *bytes* hold no `image` with a
    ## root `stack`.
    static func parse(bytes: PackedByteArray) -> Dictionary[String, Variant]:
        if bytes.is_empty():
            return {}
        var parser := XMLParser.new()
        if parser.open_buffer(bytes) != OK:
            return {}
        var image: Dictionary[String, Variant] = {}
        var open: Array[Dictionary] = []
        var count := 0
        while parser.read() == OK:
            var type := parser.get_node_type()
            if type == XMLParser.NODE_ELEMENT_END:
                if parser.get_node_name() == "stack" and not open.is_empty():
                    open.pop_back()
                continue
            if type != XMLParser.NODE_ELEMENT:
                continue
            var tag := parser.get_node_name()
            var attrs := _attributes(parser)
            if tag == "image" and image.is_empty():
                var resolution := SaTyped.float_at(attrs, "xres", SaDocument.DEFAULT_DPI)
                image = {"w": SaTyped.int_at(attrs, "w", 0), "h": SaTyped.int_at(attrs, "h", 0), "xres": resolution}
                continue
            if image.is_empty() or (tag != "stack" and tag != "layer"):
                continue
            var node: Dictionary[String, Variant] = {"kind": tag, "attrs": attrs, "children": [], "id": count}
            count += 1
            if open.is_empty():
                if tag != "stack" or image.has("stack"):
                    continue
                image["stack"] = node
            else:
                var children: Array = open[-1]["children"]
                children.append(node)
            if tag == "stack" and not parser.is_empty():
                open.append(node)
        return image if image.has("stack") else {}

    static func _attributes(parser: XMLParser) -> Dictionary[String, String]:
        var out: Dictionary[String, String] = {}
        for i in parser.get_attribute_count():
            out[parser.get_attribute_name(i)] = parser.get_attribute_value(i)
        return out


## The layers of one open or import, built bottom first into the document in
## the order Sara keeps them, from one child index up.
class Builder:
    extends RefCounted

    ## The first layer built, and the one the file marks selected.
    var first: SaLayer = null
    var selected: SaLayer = null
    ## The names whose op had no mode, in the order they were built.
    var fallen_back: PackedStringArray = []
    ## Every node built, layers and groups, bottom first as they stand.
    var block: Array[SaLayer] = []

    var _document: SaDocument
    var _pixels: Dictionary[int, Dictionary]
    var _taken: Dictionary[String, bool] = {}
    var _next: int

    ## *at* is the child index the first node goes to. The names already in
    ## the document are taken, so an import beside them renames rather than
    ## letting the engine do it.
    func _init(document: SaDocument, pixels: Dictionary[int, Dictionary], at: int) -> void:
        _document = document
        _pixels = pixels
        _next = at
        for child in document.get_children():
            _taken[str(child.name)] = true

    ## One empty paint layer, for a file none of whose layers could be read.
    func empty() -> void:
        first = _layer({"name": "Layer 1"}, null)
        _put(first)

    ## *stack*'s members into the document under *group*, bottom first, at
    ## *offset* plus what each element says.
    func stack(node: Dictionary[String, Variant], group: SaLayer, offset: Vector2i) -> void:
        var children: Array = node["children"]
        var members := children.duplicate()
        members.reverse()
        for member: Dictionary[String, Variant] in members:
            var attrs: Dictionary[String, String] = member["attrs"]
            var at := offset + Vector2i(SaTyped.int_at(attrs, "x", 0), SaTyped.int_at(attrs, "y", 0))
            if member["kind"] == "stack":
                var inner := _layer(attrs, group)
                inner.is_group = true
                inner.isolated = SaTyped.text_at(attrs, "isolation", "") == SaOraReader.ISOLATE
                stack(member, inner, at)
                _put(inner)
                continue
            var id := SaTyped.whole(member["id"])
            if not _pixels.has(id):
                continue
            var layer := _layer(attrs, group)
            _put(layer)
            var decoded: Dictionary = _pixels[id]
            var picture: Image = decoded["image"]
            var named := SaPictureFile.space_for_primaries(SaTyped.int_at(decoded, "primaries", -1))
            var source := (named if named != null else SaColorSpace.srgb()).with_depth(_document.color_space.depth)
            SaPictureFile.fill_layer(_document, layer, picture, at, source)
            if first == null:
                first = layer
            if SaTyped.text_at(attrs, "selected", "") == "true":
                selected = layer

    ## *node* into the document at the next index up.
    func _put(node: SaLayer) -> void:
        _document.add_child(node)
        _document.move_child(node, _next)
        _next += 1
        block.append(node)

    ## A node with what a layer and a stack both carry.
    func _layer(attrs: Dictionary[String, String], group: SaLayer) -> SaLayer:
        var layer := SaLayer.new()
        layer.name = _free_name(SaTyped.text_at(attrs, "name", "Layer"))
        layer.schema = SaFieldSpec.schema_for_space(_document.color_space)
        layer.group = group
        layer.opacity = clampf(SaTyped.float_at(attrs, "opacity", 1.0), 0.0, 1.0)
        layer.visible = SaTyped.text_at(attrs, "visibility", "visible") != "hidden"
        var mode := SaOraReader.mode_for(SaTyped.text_at(attrs, "composite-op", SaOraReader.DEFAULT_OP))
        if mode == &"":
            fallen_back.append(str(layer.name))
            mode = SaLayer.BLEND_MODE.NORMAL
        layer.blend_mode = mode
        return layer

    ## *wanted*, or it with the first free number after it, since two
    ## siblings of one name would be renamed by the engine into nonsense.
    func _free_name(wanted: String) -> String:
        var base := wanted if not wanted.strip_edges().is_empty() else "Layer"
        var candidate := base
        var number := 2
        while _taken.has(candidate):
            candidate = "%s %d" % [base, number]
            number += 1
        _taken[candidate] = true
        return candidate
