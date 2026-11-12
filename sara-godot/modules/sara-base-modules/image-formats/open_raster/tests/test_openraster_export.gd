## A picture exports as OpenRaster with its layers.
##
## A document of a generated ground, an empty layer, two paint layers, a group
## holding a multiply layer, a hidden layer, a masked layer and a layer in a mode
## OpenRaster has no name for is written out, and the file is read back the way
## another program reads it: `ZIPReader` for the entries, `XMLParser` for the
## stack, Godot's own PNG decoder for the pixels, and the zip's own bytes for
## the order and the method of its first entry. The document is sRGB, so a
## stored number leaves as the byte nearest it and the suite can say which byte
## that is without asking Sara's gamut path.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

static var scratch: String = SaDataRoot.path("test_e2_openraster.ora")
static var scratch_png: String = SaDataRoot.path("test_e2_openraster.png")

const GROUND := Color(0.2, 0.4, 0.6, 1.0)
const FIRST := Color(0.8, 0.2, 0.4, 1.0)
const SECOND := Color(0.4, 0.8, 0.2, 0.6)
const MULTIPLIED := Color(0.6, 0.4, 0.8, 1.0)
const HIDDEN := Color(0.2, 0.2, 0.8, 1.0)
const MASKED := Color(0.8, 0.6, 0.2, 1.0)
const EXCLUDED := Color(0.4, 0.4, 0.4, 1.0)

## The layer the right half of the first chunk is hidden on, and a point either
## side of the line.
const SHOWN_AT := Vector2i(40, 10)
const HIDDEN_AT := Vector2i(200, 10)

var _easel: SaEasel
var _doc: SaDocument
var _ops: SaLayerOps
var _metadata := SaExportMetadata.new("E2", 1790190245, 0)

## The skeleton's formats with this module's after them, built again before
## each test because registries a test builds install over them.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()
    _easel = Bench.easel(Vector2i(512, 256))
    _doc = _easel.document
    _ops = SaLayerOps.new(_doc)
    _build()
    Bench.composite(_easel)


func after_each() -> void:
    for path: String in [scratch, scratch_png]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    _ops = null
    _doc = null
    _easel.free()
    _easel = null


# --- The document -------------------------------------------------------------


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    return registries


## A layer called *layer_name* above the active one, holding *color* in the
## chunk at *grid_pos* alone.
func _painted(layer_name: String, color: Color, grid_pos: Vector2i) -> SaLayer:
    var layer := _ops.add()
    layer.name = layer_name
    layer.get_or_create_chunk(grid_pos).clear(color)
    return layer


## One over the left half of the first chunk and zero over the right half.
func _write_half(coverage: SaTexture) -> void:
    var values := PackedFloat32Array()
    values.resize(coverage.size.x * coverage.size.y)
    for y in coverage.size.y:
        for x in coverage.size.x:
            values[y * coverage.size.x + x] = 1.0 if x < 128 else 0.0
    GlobalShaderCompiler.get_rd().texture_update(coverage.rid, 0, values.to_byte_array())


func _build() -> void:
    _ops.remove(_doc.get_node("Background") as SaLayer)
    var ground := _ops.add(&"background", _registries().layer_types)
    ground.name = "Ground"
    _doc.fill_layer(GROUND, ground)
    _ops.move(ground, -1)
    _doc.set_active_layer(_doc.get_node("Layer 1") as SaLayer)
    _painted("Paint A", FIRST, Vector2i(1, 0))
    _painted("Paint B", SECOND, Vector2i(0, 0))
    var multiply := _painted("Multiply", MULTIPLIED, Vector2i(0, 0))
    _ops.set_blend_mode(multiply, &"multiply")
    var hidden := _painted("Hidden", HIDDEN, Vector2i(1, 0))
    _ops.set_visible(hidden, false)
    var masked := _painted("Masked", MASKED, Vector2i(0, 0))
    assert_true(SaMaskOps.new(_doc).add(masked), "The masked layer takes a mask")
    _write_half(masked.mask.get_or_create(Vector2i(0, 0)))
    var excluded := _painted("Exclusion", EXCLUDED, Vector2i(1, 0))
    excluded.blend_mode = &"exclusion"
    var group := _ops.group_layers([multiply])
    group.name = "Group"
    _ops.set_opacity(group, 0.5)
    SaLayerStack.invalidate_layer_chunks(_doc, masked)
    _doc.update_caches()


func _export(bits: int = 8) -> Error:
    var ora := SaExportOra.new(_doc, bits, PackedFloat32Array(), SaGamutMapping.CLIP, _metadata)
    return ora.write(_easel.output, scratch)


# --- Reading the file back ----------------------------------------------------


func _u16_le(bytes: PackedByteArray, at: int) -> int:
    return bytes[at] | (bytes[at + 1] << 8)


## `stack.xml` as a tree of `{"tag", "attributes", "children"}`, the root
## element at the top.
func _tree(xml: PackedByteArray) -> Dictionary:
    var parser := XMLParser.new()
    assert_eq(parser.open_buffer(xml), OK, "stack.xml parses")
    var root: Dictionary = {"tag": "", "attributes": {}, "children": []}
    var path: Array = [root]
    while parser.read() == OK:
        match parser.get_node_type():
            XMLParser.NODE_ELEMENT:
                var node: Dictionary = {"tag": parser.get_node_name(), "attributes": {}, "children": []}
                for i in parser.get_attribute_count():
                    node["attributes"][parser.get_attribute_name(i)] = parser.get_attribute_value(i)
                (path[-1]["children"] as Array).append(node)
                if not parser.is_empty():
                    path.append(node)
            XMLParser.NODE_ELEMENT_END:
                path.pop_back()
    return (root["children"] as Array)[0]


func _names(stack: Dictionary) -> Array:
    return (stack["children"] as Array).map(func(node: Dictionary) -> String: return node["attributes"]["name"])


func _png(reader: ZIPReader, node: Dictionary) -> Image:
    var image := Image.new()
    assert_eq(image.load_png_from_buffer(reader.read_file(node["attributes"]["src"])), OK, "%s decodes" % node)
    return image


func _same_bytes(image: Image, at: Vector2i, color: Color, what: String) -> void:
    var got := image.get_pixelv(at)
    var want := [roundi(color.r * 255), roundi(color.g * 255), roundi(color.b * 255), roundi(color.a * 255)]
    assert_eq([got.r8, got.g8, got.b8, got.a8], want, what)


func _opened() -> ZIPReader:
    var reader := ZIPReader.new()
    assert_eq(reader.open(scratch), OK, "The file opens as a zip")
    return reader


# --- The tests ------------------------------------------------------------------


func test_the_document_holds_what_the_suite_built() -> void:
    var names := SaLayerStack.members(_doc, null).map(func(layer: SaLayer) -> String: return String(layer.name))
    assert_eq(names, ["Ground", "Layer 1", "Paint A", "Paint B", "Group", "Hidden", "Masked", "Exclusion"], "Bottom first")
    assert_true((_doc.get_node("Ground") as SaLayer).is_generated(), "The ground is a generated layer")


func test_the_mimetype_comes_first_and_is_not_compressed() -> void:
    assert_eq(_export(), OK, "The export succeeds")
    var reader := _opened()
    assert_eq(reader.get_files()[0], "mimetype", "mimetype is the first entry")
    assert_eq(reader.read_file("mimetype").get_string_from_ascii(), "image/openraster", "and names the format")
    var bytes := FileAccess.get_file_as_bytes(scratch)
    assert_eq(bytes.slice(0, 4), PackedByteArray([0x50, 0x4B, 0x03, 0x04]), "The zip starts with a local header")
    assert_eq(bytes.slice(30, 30 + _u16_le(bytes, 26)).get_string_from_ascii(), "mimetype", "for the mimetype")
    # `SaZipStored` writes it with method 0, as the spec asks.
    assert_eq(_u16_le(bytes, 8), 0, "and stores it")
    reader.close()


func test_the_stack_holds_every_layer_and_attribute() -> void:
    assert_eq(_export(), OK, "The export succeeds")
    var reader := _opened()
    var image := _tree(reader.read_file("stack.xml"))
    assert_eq(image["tag"], "image", "The root is an image")
    assert_eq(image["attributes"]["w"], "512", "as wide as the canvas")
    assert_eq(image["attributes"]["h"], "256", "and as tall")
    assert_eq(image["attributes"]["xres"], str(roundi(_doc.dpi)), "at the document's resolution")
    var stack: Dictionary = (image["children"] as Array)[0]
    assert_eq(stack["tag"], "stack", "holding one root stack")
    var top_first := ["Exclusion", "Masked", "Hidden", "Group", "Paint B", "Paint A", "Layer 1", "Ground"]
    assert_eq(_names(stack), top_first, "Top first")
    var by_name: Dictionary = {}
    for node: Dictionary in stack["children"]:
        by_name[node["attributes"]["name"]] = node

    var group: Dictionary = by_name["Group"]
    assert_eq(group["tag"], "stack", "A group is a nested stack")
    assert_eq(_names(group), ["Multiply"], "holding its member")
    assert_eq(float(group["attributes"]["opacity"]), 1.0, "at full opacity, its own moved onto its member")
    assert_eq(group["attributes"]["isolation"], "auto", "passing through, as Sara composites it")
    var multiply: Dictionary = (group["children"] as Array)[0]
    assert_eq(multiply["attributes"]["composite-op"], "svg:multiply", "Multiply is OpenRaster's multiply")
    assert_eq(float(multiply["attributes"]["opacity"]), 0.5, "at the group's opacity times its own")

    assert_eq(by_name["Hidden"]["attributes"]["visibility"], "hidden", "A hidden layer is written, hidden")
    assert_eq(by_name["Paint A"]["attributes"]["visibility"], "visible", "and a shown one visible")
    assert_eq(by_name["Exclusion"]["attributes"]["composite-op"], "svg:src-over", "Exclusion falls back to normal")
    assert_eq(by_name["Paint B"]["attributes"]["composite-op"], "svg:src-over", "Normal is src-over")
    for layer_name: String in top_first:
        var node: Dictionary = by_name[layer_name]
        for attribute: String in ["name", "opacity", "visibility", "composite-op"]:
            assert_true((node["attributes"] as Dictionary).has(attribute), "%s carries %s" % [layer_name, attribute])
    assert_eq(by_name["Paint A"]["attributes"]["x"], "256", "A layer sits where its chunks are")
    assert_eq(by_name["Paint A"]["attributes"]["y"], "0", "on both axes")
    assert_eq(by_name["Paint B"]["attributes"]["x"], "0", "and one at the origin at the origin")
    reader.close()


func test_each_layer_png_holds_its_layers_pixels() -> void:
    assert_eq(_export(), OK, "The export succeeds")
    var reader := _opened()
    var stack: Dictionary = (_tree(reader.read_file("stack.xml"))["children"] as Array)[0]
    var by_name: Dictionary = {}
    for node: Dictionary in stack["children"]:
        by_name[node["attributes"]["name"]] = node
    by_name["Multiply"] = (by_name["Group"]["children"] as Array)[0]

    var ground := _png(reader, by_name["Ground"])
    assert_eq(ground.get_size(), Vector2i(512, 256), "A generated layer is the pixels it produces, all of them")
    _same_bytes(ground, Vector2i(10, 10), GROUND, "The ground's colour")
    _same_bytes(ground, Vector2i(400, 200), GROUND, "everywhere")

    var empty := _png(reader, by_name["Layer 1"])
    assert_eq(empty.get_size(), Vector2i(1, 1), "An empty layer is one pixel")
    assert_eq(empty.get_pixel(0, 0).a8, 0, "and a transparent one")

    var cut := {"Paint A": FIRST, "Paint B": SECOND, "Multiply": MULTIPLIED, "Hidden": HIDDEN, "Exclusion": EXCLUDED}
    for layer_name: String in cut:
        var png := _png(reader, by_name[layer_name])
        assert_eq(png.get_size(), Vector2i(256, 256), "%s is cut to its one chunk" % layer_name)
        _same_bytes(png, Vector2i(10, 10), cut[layer_name], "%s holds its colour" % layer_name)
        _same_bytes(png, Vector2i(250, 250), cut[layer_name], "%s to the chunk's far corner" % layer_name)

    var masked := _png(reader, by_name["Masked"])
    _same_bytes(masked, SHOWN_AT, MASKED, "The mask shows the left half")
    assert_eq(masked.get_pixelv(HIDDEN_AT).a8, 0, "and its hiding is applied into the pixels")
    reader.close()


func test_the_merged_image_is_the_png_export() -> void:
    for bits: int in [8, 16]:
        assert_eq(_export(bits), OK, "The %d-bit export succeeds" % bits)
        var err := SaExport.export_png_texture(
            _easel.output, _doc.color_space, scratch_png, bits, PackedFloat32Array(), SaGamutMapping.CLIP, _metadata
        )
        assert_eq(err, OK, "The PNG export succeeds")
        var reader := _opened()
        var merged := reader.read_file("mergedimage.png")
        assert_eq(merged, FileAccess.get_file_as_bytes(scratch_png), "mergedimage.png is the %d-bit PNG export" % bits)
        reader.close()


func test_a_sixteen_bit_export_writes_sixteen_bit_layers() -> void:
    assert_eq(_export(16), OK, "The export succeeds")
    var reader := _opened()
    for entry: String in reader.get_files():
        # `ZIPReader` lists the folder as well as the files in it.
        if entry.begins_with("data/") and not entry.ends_with("/"):
            # The IHDR's depth byte: eight of signature, four of length, four
            # of type, then width and height.
            var png := reader.read_file(entry)
            assert_true(png.size() > 24, "%s holds a PNG, %d bytes" % [entry, png.size()])
            if png.size() > 24:
                assert_eq(png[24], 16, "%s is sixteen bits a channel" % entry)
    reader.close()


func test_the_thumbnail_fits_the_spec() -> void:
    assert_eq(_export(), OK, "The export succeeds")
    var reader := _opened()
    var thumbnail := Image.new()
    assert_eq(thumbnail.load_png_from_buffer(reader.read_file("Thumbnails/thumbnail.png")), OK, "The thumbnail decodes")
    assert_eq(thumbnail.get_size(), Vector2i(256, 128), "It fits 256 pixels and keeps the picture's shape")
    reader.close()


func test_the_dialog_is_told_what_falls_back() -> void:
    var fallen := SaExportOra.fallen_back(_doc).map(func(layer: SaLayer) -> String: return String(layer.name))
    assert_eq(fallen, ["Exclusion"], "Exclusion is the one mode written as normal")
    assert_eq(SaExportOra.dropped(_doc), [] as Array[SaLayer], "No group here has a mask to leave out")
    # Every mode the skeleton registers, read from the registry rather than
    # from a list kept beside it, so a new built-in is asked here the day its
    # row is written. The three Normals pinned to a space are Normal to
    # OpenRaster, which names no space.
    for mode: StringName in Fixtures.make_registries().blend_modes.list_ids():
        if mode in [&"exclusion", &"alpha_lock", &"normal_srgb", &"normal_linear", &"normal_oklab"]:
            assert_eq(SaExportOra.composite_op(mode), "svg:src-over", "%s has no operator" % mode)
        else:
            assert_true(SaExportOra.composite_op(mode) != "svg:src-over" or mode == &"normal", "%s has one" % mode)
