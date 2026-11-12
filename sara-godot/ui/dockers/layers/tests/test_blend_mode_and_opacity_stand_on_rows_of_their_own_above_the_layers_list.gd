## The layer's blend mode and opacity stand on rows of their own
## above the Layers docker's list.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The blending mode and the opacity slider are on separate rows, not next to
## each other, and they are above the layers list. So the docker's column reads the blend row, then the opacity
## row, then the list, a fresh profile's order and a stored one's say so, and
## the slider still moves the active layer.
##
## A docker is a `Window` and adding one to the tree in a headless test hangs,
## so nothing here enters the tree, as in the second-blend-row suite beside this one, and the
## widths the rows are laid out at are the shot's to show.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _registries: SaRegistries
var _easel: SaEasel
var _canvas: SaCanvas
var _doc: SaDocument
var _docker: LayersDocker
var _top: SaLayer


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(Vector2i(256, 256))
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document
    var ops := SaLayerOps.new(_doc)
    _top = ops.add()
    ops.set_opacity(_top, 0.25)
    _doc.set_active_layer(_top)
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.target_canvas = _canvas
    _docker.bind_registries(_registries.blend_modes, _registries.layer_types)
    _docker.hide()


func after_each() -> void:
    if _docker != null:
        _docker.free()
    _canvas.free()
    _easel.free()
    _docker = null
    _doc = null


## The column's children in order, by node name.
func _names_in(parent: Node) -> Array[String]:
    var names: Array[String] = []
    for child: Node in parent.get_children():
        names.append(String(child.name))
    return names


func test_the_blend_row_stands_above_the_opacity_row_and_both_above_the_list() -> void:
    var row := _docker.blend_row
    assert_true(row is VBoxContainer, "the two parts stack, one row each, rather than sharing one")
    assert_eq(_names_in(row), ["BlendBox", "OpacityBox"] as Array[String], "the blend row first, the opacity row under it")
    assert_true(row.get_index() < _docker.item_list.get_index(), "and both above the list, as the docker is built")


func test_the_layout_order_seats_them_above_the_list() -> void:
    var shipped: Array = SaSettings.get_layout_order(SaDockerIds.LAYERS)
    var before := "the order a profile reads has Blend Mode before the list"
    assert_true(shipped.find("Blend Mode") < shipped.find("Layer List"), before)
    assert_true(shipped.find("Opacity") < shipped.find("Layer List"), "and Opacity")
    _docker.apply_layout_settings()
    var above := "so the docker's layout pass keeps the rows above the list"
    assert_true(_docker.blend_row.get_index() < _docker.item_list.get_index(), above)
    assert_true(_docker.item_list.get_index() < _docker.actions.get_index(), "with the actions still under it")


## A column gives every child its full width unless the child asks to shrink,
## so a row that fills is one that neither shrinks nor shares a line.
func test_each_row_fills_the_columns_width() -> void:
    for part: Control in [_docker.blend_row.blend_box, _docker.blend_row.opacity_box]:
        assert_true(part.get_parent() is VBoxContainer, "%s is a line of the column of its own" % part.name)
        assert_true(part.size_flags_horizontal & Control.SIZE_FILL, "%s fills the column's width" % part.name)
    assert_true(_docker.blend_row.size_flags_horizontal & Control.SIZE_FILL, "and the pair fills the docker's")


func test_the_slider_moves_the_active_layers_opacity() -> void:
    assert_almost_eq(_docker.opacity_slider.value, 0.25, 0.0001, "the slider opens on the active layer's quarter")
    _docker.opacity_slider.step_by_units(35.0)
    assert_almost_eq(_top.opacity, 0.6, 0.0001, "35 per cent up is the active layer's opacity")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Layer Opacity", "as a step on the document")


func test_a_stored_order_from_before_takes_the_rows_above_the_list() -> void:
    var config := ConfigFile.new()
    var stored := ["Drag Handle", "Resizer", "Layer List", "Actions", "Blend Mode", "Opacity"]
    config.set_value("profile_order", "LayersDocker", stored)
    SaSettingsMigrations.apply(config, 24)
    var order: Array = config.get_value("profile_order", "LayersDocker")
    var moved := ["Drag Handle", "Resizer", "Blend Mode", "Opacity", "Layer List", "Actions"]
    assert_eq(order, moved, "the two seated just before the list, the rest in place")
    assert_eq(config.get_value("meta", "version"), SaSettingsMigrations.SETTINGS_VERSION, "and stamped with this build")


func test_a_profile_with_no_layers_order_is_left_without_one() -> void:
    var config := ConfigFile.new()
    SaSettingsMigrations.apply(config, 24)
    assert_false(config.has_section_key("profile_order", "LayersDocker"), "a fresh profile reads the shipped order")
