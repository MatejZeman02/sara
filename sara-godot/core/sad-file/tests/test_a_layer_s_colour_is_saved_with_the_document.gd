## A layer's colour, the one a right click on its row gives it,
## is saved in the `.sad` and read back, and a file from before the colour
## existed opens with every layer at No Colour.
##
## The docker's half, the right click and the row's tint, is
## `ui/dockers/layers/tests/test_a_right_click_on_a_layer_s_row_gives_it_a_colour.gd`.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save reads chunks back and a load writes them.
const REQUIRES_GPU := true

## Saved by a build of 2026, long before row colours.
const UNCOLOURED := "res://tests/data/painted_two_layers.sad"
static var scratch: String = SaDataRoot.path("test_colours.sad")


func after_each() -> void:
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))


func _layers(doc: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in doc.get_children():
        if child is SaLayer and child != doc.stroke_layer:
            found.append(child)
    return found


func _blank() -> SaDocument:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(16, 16), SaCompositor.new())
    return doc


func test_a_green_layer_and_a_violet_group_open_green_and_violet() -> void:
    var source := SaDocument.new()
    source.setup_default_document(Vector2i(64, 64), SaCompositor.new())
    var ops := SaLayerOps.new(source)
    var painted := source.active_layer
    var group := ops.group_layers([ops.add()])
    SaLayerColorTag.new(source).write([painted], &"green")
    SaLayerColorTag.new(source).write([group], &"violet")
    assert_eq(SaExport.save_sad(source, scratch), OK, "Saving succeeds")

    var reopened := _blank()
    assert_eq(SaExport.load_sad(reopened, scratch), OK, "Loading succeeds")
    var colours := {}
    for layer in _layers(reopened):
        colours[str(layer.name)] = layer.color_tag
    assert_eq(colours.get(str(painted.name)), &"green", "The painted layer is green again")
    assert_eq(colours.get(str(group.name)), &"violet", "and the group violet")
    assert_eq(colours.get("Background"), &"", "and the background, never coloured, has No Colour")
    source.free()
    reopened.free()


func test_a_file_with_no_row_colours_opens_with_no_colour() -> void:
    var doc := _blank()
    # A layer coloured before the open, so the read has to write No Colour
    # rather than leave what was there.
    doc.active_layer.color_tag = &"red"
    assert_eq(SaExport.load_sad(doc, UNCOLOURED), OK, "The uncoloured file opens")
    var layers := _layers(doc)
    assert_true(layers.size() > 0, "with its layers")
    for layer in layers:
        assert_eq(layer.color_tag, &"", "%s has No Colour" % layer.name)
    doc.free()


func test_a_colour_this_build_does_not_know_opens_as_no_colour() -> void:
    assert_eq(SaLayerColorTag.known(&"teal"), &"", "A colour from a later build reads as none")
    assert_eq(SaLayerColorTag.known(&"blue"), &"blue", "and a known one as itself")
