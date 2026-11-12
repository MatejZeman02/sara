## File > Import takes an OpenRaster file's layers.
##
## The Krita-like fixture of the open test imported into a document of two layers, a
## Background and a Layer 1, with the Background active. Its stack goes in
## above the active layer and below Layer 1, bottom first as Sara keeps it,
## and one undo takes the whole of it back.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const KRITA := "res://tests/data/openraster/krita_like.ora"
const NOT_A_ZIP := "res://tests/data/import_gradient.png"
const BYTE := 1.0 / 255.0

## The document's two layers with the file's stack between them. The file's
## Background is renamed, since the document has one, and Missing is left out
## as an open leaves it out.
const IMPORTED: Array[String] = ["Background", "Background 2", "Xor", "Hidden", "Group", "Sixteen", "Layer 1"]

var _problems: Array[String] = []
var _easel: SaEasel

## The skeleton's formats with this module's after them, built again before
## each test because registries a test builds install over them.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()
    SaProblems.announce = false
    SaProblems.attach_sink(func(line: String, _kind: SaProblems.Kind) -> void: _problems.append(line))
    _problems.clear()
    _easel = SaEasel.create_default(Vector2i(128, 128))
    _easel.document.set_active_layer(_layer("Background"))


func after_each() -> void:
    SaProblems.detach_sink()
    SaProblems.announce = true
    _easel.free()
    _easel = null


func _import(path: String) -> Array[SaLayer]:
    return SaOraReader.new(ProjectSettings.globalize_path(path)).import_into(_easel.document)


func _names() -> Array[String]:
    var out: Array[String] = []
    for child in _easel.document.get_children():
        if child is SaLayer:
            out.append(str(child.name))
    return out


func _layer(layer_name: String) -> SaLayer:
    return _easel.document.get_node_or_null(layer_name) as SaLayer


func _texel(layer: SaLayer, x: int, y: int) -> Color:
    var side := SaChunk.SIZE
    @warning_ignore("integer_division")
    var texture := layer.get_field(Vector2i(x / side, y / side))
    if texture == null:
        return Color(0, 0, 0, 0)
    @warning_ignore("static_called_on_instance")
    return SaExport.get_texture_image_float(texture).get_pixel(x % side, y % side)


func test_the_stack_goes_in_above_the_active_layer_in_order() -> void:
    var block := _import(KRITA)
    assert_eq(block.size(), 5, "Five nodes come in, the missing layer left out")
    assert_eq(_names(), IMPORTED, "above the active layer and below Layer 1, bottom first")
    var group := _layer("Group")
    assert_true(group.is_group and group.isolated, "The nested stack is an isolated group")
    assert_eq(_layer("Xor").group, group, "holding Xor")
    assert_eq(_layer("Hidden").group, group, "and Hidden")
    assert_eq(_layer("Sixteen").group, null, "and nothing above it")
    assert_eq(_layer("Hidden").blend_mode, &"multiply", "Blend modes come in")
    assert_almost_eq(_layer("Xor").opacity, 0.75, 1e-4, "and opacities")
    assert_false(_layer("Hidden").visible, "and visibility")
    assert_eq(_easel.document.active_layer, _layer("Sixteen"), "The layer the file selects is active")
    assert_eq(_easel.document.canvas_size, Vector2i(128, 128), "The document keeps its size")
    assert_eq(_problems.size(), 2, "The fallen-back and the left-out layers are each said once")


func test_the_layers_keep_their_offsets() -> void:
    _import(KRITA)
    var green := Color(0.0, 200.0 / 255.0, 0.0, 1.0)
    var got := _texel(_layer("Xor"), 2, 2)
    assert_almost_eq(got.g, green.g, BYTE, "Xor starts at the group's offset")
    assert_eq(_texel(_layer("Xor"), 1, 1).a, 0.0, "and nothing before it")
    assert_almost_eq(_texel(_layer("Hidden"), 12, 12).r, 200.0 / 255.0, BYTE, "Hidden at its offset plus the group's")
    assert_eq(_texel(_layer("Sixteen"), 39, 4).a, 0.0, "Sixteen not before its offset")
    assert_almost_eq(_texel(_layer("Sixteen"), 40, 4).a, 1.0, BYTE, "and there at it")


func test_one_undo_takes_the_whole_import_back() -> void:
    var doc := _easel.document
    var before := _names()
    _import(KRITA)
    assert_true(doc.undo_redo.has_undo(), "An import is a step")
    doc.undo_redo.undo()
    assert_eq(_names(), before, "One undo takes every imported layer and group back")
    assert_eq(doc.active_layer, _layer("Background"), "and the layer that was active is again")
    doc.undo_redo.redo()
    assert_eq(_names(), IMPORTED, "and redo brings the stack back in its order")
    assert_eq(_layer("Xor").group, _layer("Group"), "with its membership")


func test_an_import_inside_a_group_stays_in_it() -> void:
    var doc := _easel.document
    var outer := SaLayerOps.new(doc).group_layers([_layer("Background")])
    assert_true(outer != null, "The Background wrapped in a group")
    doc.set_active_layer(_layer("Background"))
    _import(KRITA)
    assert_eq(_layer("Group").group, outer, "The file's group goes into the active layer's group")
    assert_eq(_layer("Sixteen").group, outer, "and so does its top layer")
    assert_eq(_layer("Xor").group, _layer("Group"), "while a nested member keeps its own")


func test_a_file_that_is_not_ora_imports_nothing() -> void:
    var before := _names()
    assert_true(_import(NOT_A_ZIP).is_empty(), "A PNG called anything is not OpenRaster")
    assert_eq(_names(), before, "and the document is untouched")
    assert_false(_easel.document.undo_redo.has_undo(), "with no step")
    assert_eq(_problems.size(), 1, "and one line saying why")
