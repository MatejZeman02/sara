## Bake, Attach and Layer are one sliding choice with a label
## over each stop, above a filter dialog's buttons.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Read as three more buttons, the choice looked unlabelled and sat in the
## button row. It should look like a toggle, closer to a slider, and not like
## three buttons where only one can be clicked. This holds that WayToggle is a `SaStopSlider`, in
## a row of its own over the Apply row rather than in it, and that the door's
## step still picks a way by name. What a pick does to the painting is
## `test_the_filter_dialog_offers_bake_attach_or_layer.gd`.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

var _easel: SaEasel = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
var _host: Node = null
var _registry: SaFilterRegistry = null
var _key: StringName = &""
var _was_embedding: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _was_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "N103TestHost"
    EventBus.add_child(_host)

    _easel = Bench.easel(Vector2i(256, 256))
    _canvas = SaCanvas.new()
    _canvas.easel = _easel

    _registry = SaFilterRegistry.new()
    _key = SaFilterRegistry.key_for(&"sara-base-modules", SaBrightnessContrastFilter.new())
    _registry.register(SaBrightnessContrastFilter.new(), &"sara-base-modules")
    _easel.compositor.filter_chain.registry = _registry

    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.layer_types = Fixtures.make_registries().layer_types
    _window.watch(_registry)
    _host.add_child(_window)


func after_each() -> void:
    # A pick is remembered for the next filter, and no suite leaves it for another.
    SaSettings.filter_way = "bake"
    Teardown.free_nodes([_window, _canvas, _easel])
    _window = null
    _canvas = null
    _easel = null
    _registry = null
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _was_embedding


func test_the_way_toggle_is_a_stop_slider_over_the_buttons_and_not_among_them() -> void:
    _window.open_filter(_key)
    var toggle := _window.find_child("WayToggle", true, false)
    assert_true(toggle is SaStopSlider, "WayToggle is one sliding control, not a row of buttons")
    assert_eq(toggle, _window.way_toggle, "and the one the window reads")
    assert_eq(SaMake.kind_of(toggle), SaMake.Kind.STOPS, "made through SaMake, so the walker knows its kind")

    var slider := toggle as SaStopSlider
    var labels: Array = slider.options.map(func(option: Dictionary) -> String: return option["label"])
    assert_eq(labels, ["Apply", "Attach", "Layer"], "with a label over each of its three stops")
    var tips: Array = slider.options.map(func(option: Dictionary) -> String: return option["tooltip"])
    for tip: String in tips:
        assert_false(tip.is_empty(), "and each stop keeps the tooltip its button had")
    assert_eq(slider.value, &"bake", "It opens on Bake")

    var row := SaFilterDialogFrame.apply_row(_window.dialog)
    var buttons := row.control as HBoxContainer
    assert_false(buttons.is_ancestor_of(slider), "It is not in the row that holds Cancel and Apply")
    assert_eq(buttons.get_child_count(), 2, "which holds the two buttons alone")
    var frame := _window.find_child("FilterFrame", true, false) as SaFilterDialogFrame
    # Beside the Affect all check, in the row the two share.
    var way_row := slider.get_parent()
    assert_eq(way_row.get_parent(), frame.footer, "It is pinned in the strip under the page")
    var line := row.line if row.line != null else row.control
    assert_true(way_row.get_index() < line.get_index(), "in a row of its own over the buttons")


func test_the_doors_way_step_still_picks_layer() -> void:
    _window.open_filter(_key)
    var tree := Engine.get_main_loop() as SceneTree
    var said := SaFilterDialogWindow.capture(tree, {"way": "layer"})
    assert_true(said.contains("way layer picked"), "The step picks Layer: %s" % said)
    assert_eq(_window.way(), &"layer", "and Apply would take the Layer way")
    assert_eq(_window.way_toggle.value, &"layer", "with the thumb on Layer")
    assert_eq(_window.describe()["way"], &"layer", "and the dump says so")

    said = SaFilterDialogWindow.capture(tree, {"way": "sideways"})
    assert_true(said.contains("the ways are bake, attach, layer"), "A way nobody offers is named with the three: %s" % said)
    assert_eq(_window.way(), &"layer", "and moves nothing")


func test_a_reopened_dialog_is_on_the_way_last_picked() -> void:
    _window.open_filter(_key)
    _window.way_toggle.pick(&"attach")
    _window.cancel_filter()
    _window.open_filter(_key)
    assert_eq(_window.way(), &"attach", "The dialog opens on the way a hand last picked")
    assert_eq(_window.find_children("WayToggle", "", true, false).size(), 1, "with one toggle, not one a dialog")
