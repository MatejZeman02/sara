## A double click renames the layer
## whose row it landed on. The first press of the pair selects the layer, the
## docker rebuilds every row, and in the running app the second press then
## reached the row one below, the masked layer under it, because the new rows
## stood unsorted until the box laid them out. The list carries the layer from
## the first press to the second, so the index the second press arrives with no
## longer decides which layer is renamed.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the document and the mask.
const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")

## Along a row and past both pictures, so a press there lands on the name.
const NAME_X := 200.0


## A docker on a document of a background, a masked Layer 1 and a new Layer 2
## above it, readied so a selection rebuilds the rows the way it does in the app.
## *picked* is what the lower row carries when the double click comes: "mask"
## has its mask picked, "layer" its paint, and "neither" leaves Layer 2 active
## with the mask still the brush's, which is where the run that found this was.
func _docker(picked: String) -> LayersDocker:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(128, 128)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    var docker: LayersDocker = LayersDockerScript.new()
    docker.name = "LayersDocker"
    canvas.add_child(docker)
    docker.target_canvas = canvas
    docker._ready()

    var doc := canvas.document
    var ops := SaLayerOps.new(doc)
    var lower: SaLayer = ops.layers()[-1]
    lower.name = "Layer 1"
    doc.set_active_layer(lower)
    var mask := lower.add_mask()
    doc.mask_target = mask
    var upper := ops.add()
    upper.name = "Layer 2"
    match picked:
        "mask":
            doc.set_active_layer(lower)
            doc.mask_target = mask
        "layer":
            doc.set_active_layer(lower)
            doc.mask_target = null
    docker.sync_layer_list()
    return docker


func _row_of(docker: LayersDocker, name: String) -> int:
    var list: SaLayerList = docker.item_list
    for i in list.row_count():
        var layer: SaLayer = list.layer_at(i)
        if layer != null and str(layer.name) == name:
            return i
    return -1


func _press(double: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.double_click = double
    event.position = Vector2(NAME_X, 11.0)
    return event


## The pair, the first press on row *first* and the second arriving on row
## *second*, then *wanted* typed into whatever field opened and Enter.
func _double_click(docker: LayersDocker, first: int, second: int, wanted: String) -> void:
    var list: SaLayerList = docker.item_list
    list._on_row_gui_input(_press(false), first)
    list._on_row_gui_input(_press(true), second)
    var at: int = list.renaming_row()
    if at < 0:
        return
    var edit: LineEdit = list.rows[at].edit
    edit.text = wanted
    edit.text_submitted.emit(wanted)


func _names(docker: LayersDocker) -> Array:
    return SaLayerOps.new(docker.target_canvas.document).layers().map(func(layer: SaLayer) -> String: return str(layer.name))


func _free(docker: LayersDocker) -> void:
    docker.target_canvas.free()


## The case the run found: the second press reaches the row below the one the
## first landed on, and the upper layer is still the one renamed.
func _renames_the_upper(picked: String) -> void:
    var docker := _docker(picked)
    var upper := _row_of(docker, "Layer 2")
    assert_eq(upper, 0, "%s: Layer 2 is the top row" % picked)
    _double_click(docker, upper, upper + 1, "Sky")
    var names := _names(docker)
    assert_true(names.has("Sky"), "%s: a name was written" % picked)
    assert_false(names.has("Layer 2"), "%s: onto the upper layer, whose row the pair landed on" % picked)
    assert_true(names.has("Layer 1"), "%s: and the masked layer under it keeps its name" % picked)
    _free(docker)


func test_the_upper_row_is_renamed_with_the_mask_still_the_brushs() -> void:
    _renames_the_upper("neither")


func test_the_upper_row_is_renamed_with_the_lower_rows_mask_picked() -> void:
    _renames_the_upper("mask")


func test_the_upper_row_is_renamed_with_the_lower_rows_layer_picked() -> void:
    _renames_the_upper("layer")


## A press on a filter's row carries no layer, so a double click whose first
## press was that one renames the row its second press reached, and not the
## layer a plain press before the filter's had carried.
func test_a_press_on_a_filter_row_drops_the_carried_layer() -> void:
    var docker := _docker("neither")
    var document := docker.target_canvas.document
    var lower: SaLayer = docker.item_list.layer_at(_row_of(docker, "Layer 1"))
    SaFilterOps.new(document).attach(lower, &"base.brightness_contrast", {"brightness": 0.2})
    docker.sync_layer_list()
    var list: SaLayerList = docker.item_list
    list._on_row_gui_input(_press(false), _row_of(docker, "Layer 2"))
    var filter_row := -1
    for i in list.row_count():
        if list.filter_at(i) != null:
            filter_row = i
    assert_true(filter_row >= 0, "Layer 1 lists its filter as a row")
    list._on_filter_row_gui_input(_press(false), filter_row)
    list._on_row_gui_input(_press(true), _row_of(docker, "Layer 1"))
    var at: int = list.renaming_row()
    assert_eq(list.layer_at(at), lower, "The row the second press reached opens its name")
    _free(docker)


## A second double click on the same row renames the same layer again, where
## the run renamed Layer 1 twice.
func test_a_second_double_click_renames_the_same_layer_again() -> void:
    var docker := _docker("mask")
    _double_click(docker, 0, 1, "Sky")
    var sky := _row_of(docker, "Sky")
    assert_eq(sky, 0, "the renamed layer is still the top row")
    _double_click(docker, sky, sky + 1, "Dusk")
    var names := _names(docker)
    assert_true(names.has("Dusk") and not names.has("Sky"), "the second name replaced the first")
    assert_true(names.has("Layer 1"), "and the masked layer was never touched")
    _free(docker)


## A double click with no plain press before it, which a test or a harness can
## send, still renames the row it arrived on.
func test_a_double_click_with_no_first_press_renames_its_own_row() -> void:
    var docker := _docker("layer")
    var lower := _row_of(docker, "Layer 1")
    docker.item_list._on_row_gui_input(_press(true), lower)
    assert_eq(docker.item_list.renaming_row(), lower, "the field opened on the row the press reached")
    _free(docker)
