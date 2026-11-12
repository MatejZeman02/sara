## The settings of a Paper or a Canvas open in a dialog window
## of their own and not in a panel of the layers docker.
##
## A normal dialog window opens, not something inside the layers docker. The
## Ground button opens `SaGroundDialog`, an `SaDialogWindow` holding the same `SaGroundRows`. The suite
## changes a colour and a thread row
## in the window and reads one history step each that undo takes back, and
## reads that no `Frame` panel is built over the docker. A double click on a
## ground's picture in the list opens the dialog, and one on its name renames
## it as on every row. The running app's half
## is `scenarios/the-settings-of-a-paper-or-a-canvas-open-in-a-dialog-window.json`.
extends "res://tests/test_framework.gd"

## The rows carry a thumbnail each, which is a compute dispatch.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _host: Node = null
var _registries: SaRegistries = null


func before_each() -> void:
    _registries = Fixtures.make_registries()


func after_each() -> void:
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    _registries = null


## A docker over a document with a Canvas ground and a paint layer above it,
## the paint layer active, in the tree so its dialog can open.
func _docker() -> LayersDocker:
    var canvas := SaCanvas.new()
    _host = canvas
    EventBus.add_child(canvas)
    canvas.canvas_size = Vector2i(128, 128)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    var doc := canvas.easel.document
    var paint := doc.active_layer
    var ground := SaLayerOps.new(doc).add(&"canvas", _registries.layer_types)
    ground.name = "Canvas"
    doc.set_active_layer(paint)
    var docker := LayersDocker.new()
    docker.target_canvas = canvas
    canvas.add_child(docker)
    docker.bind_registries(_registries.blend_modes, _registries.layer_types)
    docker.sync_layer_list()
    return docker


func _ground_of(docker: LayersDocker) -> SaLayer:
    for layer: SaLayer in SaLayerOps.new(docker.target_canvas.document).layers():
        if layer.layer_type == &"canvas":
            return layer
    return null


func test_the_ground_button_opens_a_dialog_window_with_the_rows() -> void:
    var docker := _docker()
    var dialog := docker.ground_dialog
    assert_true(dialog is SaDialogWindow, "the rows' window is a Sara dialog")
    assert_false(dialog.visible, "closed until asked")
    assert_true(docker.toggle_ground_dialog(), "the Ground button answers")
    assert_true(dialog.visible, "and the dialog shows")
    assert_true(dialog.is_ancestor_of(docker.ground_rows), "holding the ground's rows")
    assert_true(docker.ground_rows._layer == _ground_of(docker), "for the Canvas")
    for name: String in ["GroundBox", "ColourBox", "ScaleBox", "ThicknessBox", "IrregularityBox", "AngleBox"]:
        assert_true((docker.ground_rows.get_node(name) as Control).visible, "%s shows in it" % name)
    assert_false(dialog.exclusive, "it leaves the canvas its presses, so it stays open while painting")
    docker.target_canvas.document.set_active_layer(_ground_of(docker))
    assert_true(dialog.visible, "a row picked in the list leaves it open")
    docker.toggle_ground_dialog()
    assert_false(dialog.visible, "and a second press of Ground closes it")


func test_a_colour_changed_in_the_dialog_is_one_step_and_undo_restores_it() -> void:
    var docker := _docker()
    var doc := docker.target_canvas.document
    var ground := _ground_of(docker)
    docker.toggle_ground_dialog()
    var rows := docker.ground_dialog.rows
    var before: Color = ground.generator_params["color"]
    var steps := doc.history.step_count()
    var red := Color(0.8, 0.1, 0.1, 1.0)
    rows.swatches["color"].color_changed.emit(red)
    assert_true(ground.generator_params["color"].is_equal_approx(doc.color_space.from_display(red)), "the colour is written")
    assert_eq(doc.history.step_count(), steps + 1, "as one history step")
    doc.undo()
    assert_true(ground.generator_params["color"].is_equal_approx(before), "and undo gives the old colour back")


func test_a_thread_row_changed_in_the_dialog_is_one_step_and_undo_restores_it() -> void:
    var docker := _docker()
    var doc := docker.target_canvas.document
    var ground := _ground_of(docker)
    docker.toggle_ground_dialog()
    var thickness: FactorSlider = docker.ground_dialog.rows.weave_sliders["thickness"]
    var before := float(ground.generator_params["thickness"])
    var steps := doc.history.step_count()
    thickness.value_changed.emit(0.9)
    assert_almost_eq(float(ground.generator_params["thickness"]), 0.9, 0.0001, "the thread's thickness is written")
    assert_eq(doc.history.step_count(), steps + 1, "as one history step")
    doc.undo()
    assert_almost_eq(float(ground.generator_params["thickness"]), before, 0.0001, "and undo gives the old one back")


func test_no_frame_panel_is_built_over_the_docker() -> void:
    var docker := _docker()
    docker.toggle_ground_dialog()
    assert_null(docker.find_child("GroundPanel", true, false), "no node named GroundPanel")
    for node: Node in docker.find_children("*", "PopupPanel", true, false):
        assert_false(node.is_ancestor_of(docker.ground_rows), "no popup panel holds the ground's rows: %s" % node.name)
    var constants: Dictionary = docker.ground_rows.get_script().get_script_constant_map()
    assert_false(constants.has("Frame"), "and the rows carry no Frame class")


func _row_of(docker: LayersDocker, layer: SaLayer) -> int:
    var list: SaLayerList = docker.item_list
    for i in list.row_count():
        if list.layer_at(i) == layer:
            return i
    return -1


## A press pair on row *row* of the list, at the middle of its picture or at
## its name.
func _double_click(docker: LayersDocker, row: int, on_picture: bool) -> void:
    var list: SaLayerList = docker.item_list
    var frame: SaRowFrame = list.rows[row]
    var at := frame.hbox.position + frame.thumb.get_rect().get_center()
    if not on_picture:
        at.x = frame.hbox.position.x + frame.thumb.get_rect().end.x + 40.0
    for double: bool in [false, true]:
        var press := InputEventMouseButton.new()
        press.button_index = MOUSE_BUTTON_LEFT
        press.pressed = true
        press.double_click = double
        press.position = at
        list._on_row_gui_input(press, row)


func test_a_double_click_on_a_grounds_picture_opens_the_dialog() -> void:
    var docker := _docker()
    await (Engine.get_main_loop() as SceneTree).process_frame
    var row := _row_of(docker, _ground_of(docker))
    assert_true(row >= 0, "the Canvas has a row")
    _double_click(docker, row, true)
    assert_true(docker.ground_dialog.visible, "a double click on its picture opens the Ground dialog")
    assert_eq(docker.item_list.renaming_row(), -1, "and opens no name field")
    _double_click(docker, row, true)
    assert_true(docker.ground_dialog.visible, "a second one leaves it open")
    docker.ground_dialog.hide()
    _double_click(docker, row, false)
    assert_false(docker.ground_dialog.visible, "a double click on its name opens no dialog")
    assert_eq(docker.item_list.renaming_row(), row, "it renames the Canvas, as on every row")
