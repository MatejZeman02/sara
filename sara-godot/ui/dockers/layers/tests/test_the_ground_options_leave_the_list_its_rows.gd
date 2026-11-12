## A ground's options leave the layer list its rows.
##
## With nine rows in the list and a Canvas added, its seven rows would take the
## docker's lower part, the list would keep two and a half rows and a scroll bar,
## and the buttons would jump up the moment a ground was active and back down
## when a paint layer was picked. The rows open in a dialog window from a Ground
## button on the strip, so the column is the same height whichever layer is
## active.
##
## The column is laid out the way the docker lays it out, at the default
## layout's 310 by 343, in a host in the tree, because a container off the tree
## sorts nothing and a docker window in it would hang the run. The running
## app's half is
## `scenarios/a-ground-layer-s-options-leave-the-layer-list-its-rows.json`.
extends "res://tests/test_framework.gd"

## The rows carry a thumbnail each, which is a compute dispatch.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## The file a fresh profile reads the Layers docker's rectangle from.
const LAYOUT_FILE := "res://docker_layout_default.cfg"

## Six added to the Layer 1 and the Background a new document holds, and the
## Canvas makes nine rows.
const PAINT_ADDED := 6

## Every control the strip held for a Canvas, by node name, which the dialog has
## to hold now.
const CANVAS_ROWS: Array[String] = [
    "GroundBox", "ToothBox", "ColourBox", "ScaleBox", "ThicknessBox", "IrregularityBox", "AngleBox"
]

var _host: Control = null
var _registries: SaRegistries = null


func before_each() -> void:
    _registries = Fixtures.make_registries()


func after_each() -> void:
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    _registries = null


## A docker over nine rows, the Canvas among them, with the paint layer on top
## active and the layer kinds bound, so the Ground button and the dialog know
## which layer is a ground. *in_tree* puts it in the tree, which readies it, so
## its dialog can open.
func _docker(in_tree := false) -> LayersDocker:
    var canvas := SaCanvas.new()
    if in_tree:
        _host = canvas
        EventBus.add_child(canvas)
    canvas.canvas_size = Vector2i(128, 128)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    var ops := SaLayerOps.new(canvas.easel.document)
    var ground := ops.add(&"canvas", _registries.layer_types)
    ground.name = "Canvas"
    for i in PAINT_ADDED:
        ops.add()
    var docker := LayersDocker.new()
    docker.target_canvas = canvas
    canvas.add_child(docker)
    if not in_tree:
        docker._ready()
    docker.bind_registries(_registries.blend_modes, _registries.layer_types)
    docker.sync_layer_list()
    return docker


func _ground_of(docker: LayersDocker) -> SaLayer:
    for layer: SaLayer in SaLayerOps.new(docker.target_canvas.document).layers():
        if layer.layer_type == &"canvas":
            return layer
    return null


func _paint_of(docker: LayersDocker) -> SaLayer:
    return SaLayerOps.new(docker.target_canvas.document).layers()[-1]


## The docker's column moved into a host in the tree and laid out at the
## default layout's size less the grip's corner, every container in it sorted
## top down the way a frame would. Answers the list's height and each button's
## top edge in the column.
func _measure(docker: LayersDocker) -> Dictionary:
    docker.reserve_grip_corner()
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(LAYOUT_FILE), OK, "the default layout loads")
    var rect_size: Vector2i = cfg.get_value("LayersDocker", "size", Vector2i.ZERO)
    var column := docker.content_column()
    if _host == null:
        _host = Control.new()
        _host.name = "S23Host"
        EventBus.add_child(_host)
        column.get_parent().remove_child(column)
        _host.add_child(column)
    # The column keeps its anchors to the whole window and its offset over the
    # grip, so the host stands in for the docker's window at its size.
    _host.size = Vector2(rect_size)
    _sort(column)
    var buttons := {}
    for child in docker.actions.get_children():
        var btn := child as Button
        if btn != null:
            buttons[String(btn.name)] = btn.get_global_rect().position.y
    return {"list_h": docker.item_list.size.y, "buttons": buttons, "column_wants": column.get_combined_minimum_size().y}


## Frees the host and the column it holds before the canvas and the docker,
## so nothing in the column outlives what it reads.
func _free(docker: LayersDocker) -> void:
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    docker.target_canvas.free()


func _sort(node: Node) -> void:
    if node is Container:
        node.notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child in node.get_children():
        _sort(child)


func test_the_list_and_the_buttons_stay_put_when_a_ground_is_active() -> void:
    var docker := _docker()
    var doc := docker.target_canvas.document
    assert_eq(docker.item_list.row_count(), 9, "nine rows")

    doc.set_active_layer(_paint_of(docker))
    var paint := _measure(docker)
    doc.set_active_layer(_ground_of(docker))
    var ground := _measure(docker)

    # The default layout's Layers docker is 343 tall since the Minimap above it
    # opens 250 tall, so the list shows about seven of the nine rows and scrolls
    # for the rest. The fault this guards left two and a half rows.
    assert_true(float(paint["list_h"]) > 6 * 25, "the list has room for its rows: %.0f" % paint["list_h"])
    assert_almost_eq(float(ground["list_h"]), float(paint["list_h"]), 0.5, "the list keeps its height on the Canvas")
    assert_almost_eq(float(ground["column_wants"]), float(paint["column_wants"]), 0.5, "and the column asks for no more")
    var names: Array = paint["buttons"].keys()
    assert_true(names.has("GroundBtn") and names.has("MoreBtn"), "the strip holds Ground and More: %s" % [names])
    for name: String in names:
        assert_almost_eq(
            float(ground["buttons"][name]),
            float(paint["buttons"][name]),
            0.5,
            "%s stays at %.0f, not %.0f" % [name, paint["buttons"][name], ground["buttons"][name]]
        )
    _free(docker)


func test_the_rows_are_not_in_the_column() -> void:
    var docker := _docker()
    var column := docker.actions.get_parent()
    assert_false(column.is_ancestor_of(docker.ground_rows), "the ground's rows are not in the docker's column")
    assert_true(docker.ground_dialog.is_ancestor_of(docker.ground_rows), "they are the Ground dialog's")
    _free(docker)


func test_ground_stays_live_on_a_paint_layer_above_a_ground() -> void:
    var docker := _docker()
    var doc := docker.target_canvas.document
    var button := docker.actions.ground_btn

    doc.set_active_layer(_paint_of(docker))
    assert_false(button.disabled, "Ground is live on a paint layer while the document has a ground")
    assert_true(docker.toggle_ground_dialog(), "and opens the ground's rows")
    assert_true(docker.ground_rows._layer == _ground_of(docker), "the Canvas's, the document's ground")

    doc.set_active_layer(_ground_of(docker))
    assert_false(button.disabled, "Ground is live on the Canvas")
    assert_true(button.tooltip_text.begins_with("Ground"), "and says what it opens: %s" % button.tooltip_text)
    assert_eq(button.icon, SaUI.get_icon(SaLayerActions.GROUND_ICON), "with the mountains a row with height shows")
    _free(docker)


## Without any ground the button is dimmed and says where a ground comes from.
func test_ground_is_dimmed_with_the_reason_without_a_ground() -> void:
    var docker := _docker()
    var doc := docker.target_canvas.document
    var button := docker.actions.ground_btn
    SaLayerOps.new(doc).remove(_ground_of(docker))
    docker.sync_layer_list()
    doc.set_active_layer(_paint_of(docker))
    assert_true(button.disabled, "Ground is dimmed with no ground in the document")
    assert_eq(
        button.tooltip_text,
        "Add a Paper or Canvas layer from the arrow beside the plus to set a ground.",
        "and says where one comes from"
    )
    assert_false(docker.toggle_ground_dialog(), "and opens nothing")
    _free(docker)


## Every control the strip held for a Canvas is in the dialog and shown there,
## so nothing was lost on the way.
func test_the_dialog_holds_every_control_the_strip_held() -> void:
    var docker := _docker()
    docker.target_canvas.document.set_active_layer(_ground_of(docker))
    assert_true(docker.toggle_ground_dialog(), "Ground answers on the Canvas")
    var rows := docker.ground_rows
    assert_true(rows.visible, "the rows show for the Canvas")
    for name: String in CANVAS_ROWS:
        var row := rows.get_node_or_null(name) as Control
        assert_not_null(row, "the dialog holds %s" % name)
        if row != null:
            assert_true(row.visible, "and shows it")
    assert_false(rows.get_node("GrainScaleBox").visible, "a paper's Scale stays away from the woven Canvas")
    assert_true(docker.tooth_slider == rows.tooth_slider, "the tooth the dump reads is the dialog's")
    _free(docker)


## The rows open in a dialog window of the kind every other dialog is, which no
## press outside it closes, so it stays open while the painter paints.
func test_the_rows_open_in_a_dialog_window() -> void:
    var docker := _docker()
    var dialog := docker.ground_dialog
    assert_true(dialog is SaDialogWindow, "the window is a Sara dialog")
    assert_false(dialog.exclusive, "which leaves the canvas its presses")
    assert_false(dialog.popup_window, "and no press outside it closes")
    _free(docker)


## A layer made active by PageDown or an undo, which no press on a row came
## with, leaves the dialog open on the document's ground, so the settings are
## still in reach from a paint layer.
func test_the_dialog_stays_on_the_ground_when_a_paint_layer_is_made_active() -> void:
    var docker := _docker()
    var doc := docker.target_canvas.document
    doc.set_active_layer(_ground_of(docker))
    docker.ground_dialog.visible = true
    doc.set_active_layer(_paint_of(docker))
    assert_true(docker.ground_dialog.visible, "a paint layer made active leaves the dialog open")
    assert_true(docker.ground_rows.visible, "with the rows shown")
    assert_true(docker.ground_rows._layer == _ground_of(docker), "for the Canvas")
    _free(docker)


## A ground added from the Layer menu's row opens its dialog with it, since its
## tooth and colours are what a ground is added to set. Added means a document
## with no ground, since a pick where one stands swaps it instead.
func test_a_ground_added_from_the_layer_menu_opens_its_dialog() -> void:
    var docker := _docker(true)
    var doc := docker.target_canvas.document
    SaLayerOps.new(doc).remove(_ground_of(docker))
    assert_null(SaGroundChoice.new(doc, _registries.layer_types).standing(), "the document stands on no ground")
    assert_false(docker.ground_dialog.visible, "the dialog starts closed")
    SaLayerMenuRows.new(doc, null, _registries.layer_types).run(&"paper", null)
    await (Engine.get_main_loop() as SceneTree).process_frame
    assert_true(SaGroundRows.is_ground(doc.active_layer, _registries.layer_types), "the Paper is the active layer")
    assert_true(docker.ground_dialog.visible, "and its dialog opened")
    assert_true(docker.ground_rows._layer == doc.active_layer, "on the Paper")
    docker.ground_dialog.hide()
