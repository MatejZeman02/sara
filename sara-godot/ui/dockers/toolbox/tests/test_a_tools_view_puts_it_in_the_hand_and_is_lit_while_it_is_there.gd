## A tool's view puts the tool in the hand and is lit while it is there.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Toolbox is the first docker whose elements have a second view, one per
## tool, registered through `SaSettings.register_layout_element` as a module
## registers its own. A placed element is a second
## view of the same state, so the views are built through the door, not off
## the docker, and the state they share is the machine's tool in hand: a press
## on one view moves it, and a pick made anywhere else, here the brush's own
## chord through the shortcut router, lights the other.
##
## The views drive the main canvas's machine in the app. A suite has no main
## canvas, so it registers the same views over its own bound machine and puts
## the shipped ones back after.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const CATEGORY: String = SaToolBoxViews.CATEGORY

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _views: Array[Control] = []


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    SaToolBoxViews.register(func() -> ToolMachine: return _machine)


func after_each() -> void:
    for view: Control in _views:
        view.free()
    _views.clear()
    SaToolBoxViews.register()
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func _view(element: String) -> Button:
    var built := SaSettings.build_element_view(CATEGORY, element)
    if built != null:
        _views.append(built)
    return built as Button


## B, the way a keyboard sends it.
func _key(keycode: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.pressed = true
    return event


func test_every_tool_of_the_toolbox_is_placeable_and_its_places_are_not() -> void:
    SaToolBoxGrid.register_options()
    for element: String in SaToolBoxViews.tool_elements():
        assert_true(SaSettings.is_placeable(CATEGORY, element), "%s has a view the toolbox registered" % element)
    # Seventeen, from the Brush to the Assistants, liquify being an engine of the
    # Brush with no button of its own, and the Polygonal and Magnetic Lassos
    # tools beside the Lasso. The shipped order holds them and the two places.
    assert_eq(SaToolBoxViews.tool_elements().size(), 17, "one per tool the toolbox lists")
    assert_false(SaSettings.is_placeable(CATEGORY, "Drag Handle"), "and the toolbox's drag bar is not placeable")
    assert_false(SaSettings.is_placeable(CATEGORY, "Resizer"), "nor its grip")


func test_pressing_the_erasers_view_puts_the_eraser_in_the_hand() -> void:
    var brush := _view("Brush Tool")
    var eraser := _view("Eraser Tool")
    assert_not_null(brush, "The Brush Tool's view builds")
    assert_not_null(eraser, "and the Eraser Tool's")
    assert_true(brush.button_pressed, "With the brush in the hand its view is lit")
    assert_false(eraser.button_pressed, "and the eraser's is not")

    eraser.pressed.emit()
    assert_eq(_machine.active_tool_name, &"eraser", "A press on the eraser's view puts the eraser in the hand")
    assert_true(eraser.button_pressed, "and lights that view")
    assert_false(brush.button_pressed, "and puts the brush's out")


func test_the_brushs_command_lights_its_view_and_puts_the_erasers_out() -> void:
    var brush := _view("Brush Tool")
    var eraser := _view("Eraser Tool")
    eraser.pressed.emit()
    assert_eq(_machine.active_tool_name, &"eraser", "The eraser is in the hand first")

    var router := ShortcutRouter.new()
    router.canvas_provider = func() -> SaCanvas: return null
    router.tool_machine_provider = func() -> ToolMachine: return _machine
    assert_true(router.handle(_key(KEY_B)), "B is the brush's command")
    router.free()
    assert_eq(_machine.active_tool_name, &"brush", "and it puts the brush in the hand")
    assert_true(brush.button_pressed, "which lights the brush's view")
    assert_false(eraser.button_pressed, "and puts the eraser's out")
