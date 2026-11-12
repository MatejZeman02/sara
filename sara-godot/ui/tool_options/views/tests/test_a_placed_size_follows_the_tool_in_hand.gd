## A placed Size is the Size of the tool in the hand, in step with the bar's.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The bar registers a view of each
## option key it builds through `SaSettings.register_layout_element`, the call a
## module makes, so the view is built here through the door a composed docker
## builds it through, over a bar of the suite's own. One view of `radius`, three
## claims: a move on it lands on the brush and on the bar, a move on the bar or
## on the Tool Options docker lands on it, and a tool with no size in the hand
## leaves it hidden.
##
## `scenarios/the-bar-s-tool-options-placed-in-a-docker-follow-the-tool-in-hand.json`
## places Size and Opacity in a composed docker of the running app.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const CATEGORY: String = "TopMenuBar"

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _bar: ToolOptionsBar = null
var _views: Array[Control] = []


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _registries = Fixtures.make_registries(_surface)
    _machine.set_active_tool(&"brush")
    _bar = ToolOptionsBar.new()
    _bar.target_tool_machine = _machine
    _bar._ready()
    _bar.bind_registries(_registries.blend_modes)


func after_each() -> void:
    for view: Control in _views:
        view.free()
    _views.clear()
    _bar.free()
    Fixtures.teardown(_surface, _machine)
    _registries = null


func _view(element: String) -> Control:
    var built := SaSettings.build_element_view(CATEGORY, element)
    if built != null:
        _views.append(built)
    return built


func _slider_of(view: Control) -> FactorSlider:
    return view.call(&"control") as FactorSlider


func test_the_bar_registers_a_view_of_its_size() -> void:
    assert_true(SaSettings.is_placeable(CATEGORY, "radius"), "Size is placeable, because the bar registered it")
    var view := _view("radius")
    assert_not_null(view, "and the door builds a view of it")
    assert_true(view.visible, "shown with the brush in the hand")
    assert_not_null(_slider_of(view), "as a slider")


func test_a_move_on_the_view_lands_on_the_brush_and_the_bar() -> void:
    var brush := _machine.get_tool(&"brush")
    var view := _view("radius")
    var slider := _slider_of(view)
    assert_not_null(slider, "There is a slider to move")

    slider.value_changed.emit(0.07)
    assert_almost_eq(brush.settings.radius, 0.07, 0.0001, "The view wrote the brush's size")
    var bar_size := _bar.control_for(&"radius") as FactorSlider
    assert_almost_eq(bar_size.value, 0.07, 0.0001, "and the bar's Size slider shows it")


func test_a_move_on_the_bar_lands_on_the_view() -> void:
    var view := _view("radius")
    var bar_size := _bar.control_for(&"radius") as FactorSlider
    bar_size.value_changed.emit(0.05)
    assert_almost_eq(_slider_of(view).value, 0.05, 0.0001, "The bar's move shows on the view")

    assert_true(_bar.write_option(&"radius", 0.04), "A write through the bar's door")
    assert_almost_eq(_slider_of(view).value, 0.04, 0.0001, "shows on the view as well")


## The Tool Options docker writes the brush and then puts the value on the
## bar's control with `show_value`, which writes nothing, so the view hears it
## there.
func test_a_write_from_the_docker_lands_on_the_view() -> void:
    var brush := _machine.get_tool(&"brush")
    var view := _view("radius")
    brush.settings.radius = 0.03
    _bar.options.show_value(&"radius", 0.03)
    assert_almost_eq(_slider_of(view).value, 0.03, 0.0001, "The docker's move shows on the view")


func test_a_tool_with_no_size_in_the_hand_hides_the_view() -> void:
    var view := _view("radius")
    _machine.set_active_tool(&"eyedropper")
    assert_false(view.visible, "The eyedropper declares no size, so the view is hidden")

    _machine.set_active_tool(&"brush")
    assert_true(view.visible, "and the brush back in the hand shows it again")


func test_a_view_built_with_no_size_in_the_hand_starts_hidden() -> void:
    _machine.set_active_tool(&"pan")
    var view := _view("radius")
    assert_not_null(view, "The door builds it all the same")
    assert_false(view.visible, "hidden from the start")


func test_a_preset_load_lands_on_the_view() -> void:
    var brush := _machine.get_tool(&"brush")
    var view := _view("radius")
    brush.settings.radius = 0.02
    EventBus.preset_loaded.emit("Suite")
    assert_almost_eq(_slider_of(view).value, 0.02, 0.0001, "A preset load reads the brush again")
