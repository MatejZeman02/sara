## GIMP opens Sara's pass-through group as Sara draws it, or
## the export says it will not.
##
## The document is a blue ground and Group 1, passing
## through at half opacity, holding a Multiply layer of `#9966cc`, which Sara
## draws as the blue darkened at half strength. GIMP opened the file Sara
## wrote as a group in Normal at 50 and read `#7466b5` there, the purple at
## half over the blue with no multiply. The writer now puts a pass-through
## group's opacity on its members and writes the stack at full opacity and
## normal with `auto`, which is how MyPaint writes one and the one shape a
## reader that honours `auto` only at full opacity passes through. GIMP reads
## no `isolation` at all, so the dialog's loss line names the group instead.
##
## Beside that group the document holds a glaze and a pass-through group inside
## Group 1, so an opacity is seen to multiply down two levels, a pass-through
## group of a normal layer, which an isolating reader draws the same and the
## line leaves out, and a group the painter isolated, which keeps its opacity.
## Every colour is a whole number of 255ths and the document is sRGB at full
## floats, so a layer's bytes are its stored numbers and come back exactly.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

static var scratch: String = SaDataRoot.path("test_d18_pass_through.ora")
static var scratch_back: String = SaDataRoot.path("test_d18_pass_through_back.ora")
## Four chunks of layers along the top row, and the blue alone under them.
const CANVAS := Vector2i(1024, 512)

## The two colours, `#29478a` and `#9966cc`.
const BLUE := Color8(0x29, 0x47, 0x8A)
const PURPLE := Color8(0x99, 0x66, 0xCC)
const GLAZE := Color(0.8, 0.6, 0.2, 1.0)
const SCREENED := Color(0.2, 0.6, 0.4, 1.0)
const PLAIN := Color(0.4, 0.8, 0.2, 1.0)
const KEPT := Color(0.6, 0.4, 0.8, 1.0)

var _easel: SaEasel
var _doc: SaDocument
var _ops: SaLayerOps
var _opened: SaEasel
var _metadata := SaExportMetadata.new("D18", 1790190245, 0)


func before_each() -> void:
    _easel = _new_easel()
    _doc = _easel.document
    _ops = SaLayerOps.new(_doc)
    _build()
    _composite(_easel)


func after_each() -> void:
    for path: String in [scratch, scratch_back]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    _ops = null
    _doc = null
    _easel.free()
    _easel = null
    if _opened != null:
        _opened.free()
        _opened = null


# --- The document -------------------------------------------------------------


## An sRGB easel at full floats whose compositor knows the blend modes.
func _new_easel() -> SaEasel:
    var made := SaEasel.create_default(CANVAS, null, SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F32))
    made.compositor.set_registry(Fixtures.make_picture_registries().blend_modes)
    return made


func _composite(easel: SaEasel) -> void:
    easel.document.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()


## A layer called *layer_name* above the active one, holding *color* in the
## chunk at *grid_pos* alone.
func _painted(layer_name: String, color: Color, grid_pos: Vector2i) -> SaLayer:
    var layer := _ops.add()
    layer.name = layer_name
    layer.get_or_create_chunk(grid_pos).clear(color)
    return layer


func _build() -> void:
    var ground := _doc.get_node("Background") as SaLayer
    _ops.remove(_doc.get_node("Layer 1") as SaLayer)
    _doc.set_active_layer(ground)
    _doc.fill_layer(BLUE, ground)
    var multiply := _painted("Multiply", PURPLE, Vector2i(0, 0))
    _ops.set_blend_mode(multiply, &"multiply")
    var glaze := _painted("Glaze", GLAZE, Vector2i(1, 0))
    _ops.set_opacity(glaze, 0.6)
    var screen := _painted("Screen", SCREENED, Vector2i(1, 0))
    _ops.set_blend_mode(screen, &"screen")
    var group := _ops.group_layers([multiply, glaze, screen])
    group.name = "Group 1"
    _ops.set_opacity(group, 0.5)
    var inner := _ops.group_layers([screen])
    inner.name = "Inner"
    _ops.set_opacity(inner, 0.5)
    _doc.set_active_layer(group)
    var plain := _painted("Plain", PLAIN, Vector2i(2, 0))
    var plain_group := _ops.group_layers([plain])
    plain_group.name = "Plain group"
    _ops.set_opacity(plain_group, 0.4)
    # A pass-through group's own mode is drawn by nobody, Sara included, so
    # one OpenRaster has no operator for is no loss.
    _ops.set_blend_mode(plain_group, &"exclusion")
    _doc.set_active_layer(plain_group)
    var kept_multiply := _painted("Kept multiply", KEPT, Vector2i(3, 0))
    _ops.set_blend_mode(kept_multiply, &"multiply")
    var kept := _ops.group_layers([kept_multiply])
    kept.name = "Kept"
    kept.isolated = true
    _ops.set_opacity(kept, 0.5)
    _doc.update_caches()


func _export(document: SaDocument, output: SaTexture, path: String) -> void:
    var ora := SaExportOra.new(document, 8, PackedFloat32Array(), SaGamutMapping.CLIP, _metadata)
    assert_eq(ora.write(output, path), OK, "The export to %s succeeds" % path.get_file())


# --- Reading the file back ----------------------------------------------------


## `stack.xml` of the file at *path* as `{name: attributes}` for every layer
## and stack, and its stacks' member names under `members`.
func _elements(path: String) -> Dictionary:
    var reader := ZIPReader.new()
    assert_eq(reader.open(path), OK, "The file opens as a zip")
    var parser := XMLParser.new()
    assert_eq(parser.open_buffer(reader.read_file("stack.xml")), OK, "stack.xml parses")
    reader.close()
    var found: Dictionary = {}
    var open: Array[String] = []
    while parser.read() == OK:
        if parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
            open.pop_back()
            continue
        if parser.get_node_type() != XMLParser.NODE_ELEMENT:
            continue
        var tag := parser.get_node_name()
        if tag != "stack" and tag != "layer":
            continue
        var attributes: Dictionary = {"tag": tag, "members": []}
        for i in parser.get_attribute_count():
            attributes[parser.get_attribute_name(i)] = parser.get_attribute_value(i)
        var element_name: String = attributes.get("name", "")
        if not open.is_empty() and found.has(open[-1]):
            (found[open[-1]]["members"] as Array).append(element_name)
        found[element_name] = attributes
        if tag == "stack" and not parser.is_empty():
            open.append(element_name)
    return found


func _merged(path: String) -> Image:
    var reader := ZIPReader.new()
    assert_eq(reader.open(path), OK, "The file opens as a zip")
    var image := Image.new()
    assert_eq(image.load_png_from_buffer(reader.read_file("mergedimage.png")), OK, "mergedimage.png decodes")
    reader.close()
    return image


func _names(nodes: Array[SaLayer]) -> Array:
    return nodes.map(func(node: SaLayer) -> String: return String(node.name))


# --- The tests ------------------------------------------------------------------


func test_the_document_holds_e2s_group() -> void:
    var group := _doc.get_node("Group 1") as SaLayer
    assert_eq(_names(SaLayerStack.members(_doc, group)), ["Multiply", "Glaze", "Inner"], "Group 1 holds its three")
    assert_false(SaLayerStack.isolates(group), "and passes through, as the plain export's did")
    assert_false(SaLayerStack.isolates(_doc.get_node("Inner") as SaLayer), "Inner passes through as well")
    assert_true(SaLayerStack.isolates(_doc.get_node("Kept") as SaLayer), "Kept is isolated by its flag")


## Sara draws the Multiply over the blue, where GIMP read `#7466b5`, a red of
## 116 over the blue's 41.
func test_the_multiply_darkens_the_blue() -> void:
    _export(_doc, _easel.output, scratch)
    var merged := _merged(scratch)
    var square := merged.get_pixel(10, 10)
    var ground := merged.get_pixel(10, 300)
    assert_eq([ground.r8, ground.g8, ground.b8], [0x29, 0x47, 0x8A], "Where no group reaches the ground is the blue")
    for channel: int in 3:
        assert_true(square[channel] <= BLUE[channel] + 0.5 / 255.0, "The Multiply darkens it, channel %d" % channel)
    assert_true(square.r8 < 0x29, "and at half strength the red is below the blue's: %s" % square.to_html(false))


func test_a_pass_through_group_is_written_at_full_opacity_and_normal() -> void:
    _export(_doc, _easel.output, scratch)
    var elements := _elements(scratch)
    for group_name: String in ["Group 1", "Inner", "Plain group"]:
        var stack: Dictionary = elements[group_name]
        assert_eq(stack["tag"], "stack", "%s is a stack" % group_name)
        assert_eq(float(stack["opacity"]), 1.0, "%s is written at full opacity" % group_name)
        assert_eq(stack["composite-op"], "svg:src-over", "%s is written normal" % group_name)
        assert_eq(stack["isolation"], "auto", "%s passes through" % group_name)
    assert_eq(elements["Group 1"]["members"], ["Inner", "Glaze", "Multiply"], "Group 1 holds its members, top first")
    assert_eq(elements["Inner"]["members"], ["Screen"], "and Inner its one")
    var kept: Dictionary = elements["Kept"]
    assert_eq(float(kept["opacity"]), 0.5, "An isolated group keeps its own opacity")
    assert_eq(kept["isolation"], "isolate", "and is written isolated")


func test_each_member_carries_the_groups_opacity() -> void:
    _export(_doc, _easel.output, scratch)
    var elements := _elements(scratch)
    var wanted := {"Multiply": 0.5, "Glaze": 0.3, "Screen": 0.25, "Plain": 0.4, "Kept multiply": 1.0}
    for layer_name: String in wanted:
        var written := float(elements[layer_name]["opacity"])
        assert_almost_eq(written, float(wanted[layer_name]), 1e-4, "%s carries the opacity Sara draws it at" % layer_name)
    assert_eq(elements["Multiply"]["composite-op"], "svg:multiply", "and its own mode")
    assert_eq(elements["Screen"]["composite-op"], "svg:screen", "through two groups")


func test_the_loss_line_names_the_groups_whose_modes_reach_below() -> void:
    var passing := _names(SaExportOra.passed_through(_doc))
    assert_eq(passing, ["Inner", "Group 1"], "The two groups holding a mode, bottom first")
    var said := SaExportOra.losses(_doc)
    assert_eq(said.size(), 1, "The export dialog's loss line has one sentence to say: %s" % [said])
    var line := " ".join(said)
    assert_true(line.contains("Inner, Group 1"), "and it names both: %s" % line)
    assert_true(line.contains("GIMP"), "and the reader that isolates every group: %s" % line)
    assert_false(line.contains("Plain group"), "A group of a normal layer draws the same isolated: %s" % line)
    assert_false(line.contains("Kept"), "and an isolated group is isolated everywhere: %s" % line)
    assert_eq(SaExportOra.fallen_back(_doc), [] as Array[SaLayer], "and Plain group's own mode, which nobody draws, is no loss")


func test_sara_reads_the_file_back_to_the_same_merged_image() -> void:
    _export(_doc, _easel.output, scratch)
    _opened = _new_easel()
    var reader := SaOraReader.new(ProjectSettings.globalize_path(scratch), SaColorSpace.Depth.F32)
    assert_eq(reader.open_into(_opened.document), OK, "The file opens")
    _composite(_opened)
    var group := _opened.document.get_node("Group 1") as SaLayer
    assert_false(SaLayerStack.isolates(group), "Group 1 opens passing through")
    assert_eq(group.opacity, 1.0, "at full opacity")
    assert_almost_eq((_opened.document.get_node("Multiply") as SaLayer).opacity, 0.5, 1e-4, "its Multiply at half")
    _export(_opened.document, _opened.output, scratch_back)
    var first := _merged(scratch)
    var back := _merged(scratch_back)
    assert_eq(back.get_size(), first.get_size(), "The merged image comes back the same size")
    assert_eq(back.get_data(), first.get_data(), "and the same picture, byte for byte")
