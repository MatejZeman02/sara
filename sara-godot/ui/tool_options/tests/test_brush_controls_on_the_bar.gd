## The brush group stays on the bar for every tool, and stays live.
##
## The brush settings must not disappear when another tool is chosen, and must
## not be dimmed either, so there are two claims and no third state: the controls a painting tool declared
## have a place whatever is
## chosen, and moving one with the eyedropper chosen writes the brush.
##
## The rule is asked through `SaToolDescriptor.is_painting` rather than by naming
## the brush, so a module that ships a painting tool of its own gets it without a
## line in the skeleton, which is hard rule 6, built-ins through the public door, from the other side.
##
## `scenarios/brush-controls-stay-on-the-bar.json` drives the real app, where
## the same five controls are visible with the brush, the eyedropper and the pan,
## and a size written through the bar with the eyedropper chosen comes back on
## the brush.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A machine holding the built-in tools needs a surface, which needs a device.
const REQUIRES_GPU := true

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _bar: ToolOptionsBar = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _registries = Fixtures.make_registries(_surface)
    _bar = ToolOptionsBar.new()
    _bar.target_tool_machine = _machine
    _bar._ready()
    _bar.bind_registries(_registries.blend_modes)


func after_each() -> void:
    _bar.free()
    Fixtures.teardown(_surface, _machine)
    _registries = null


## Two today, the brush and the eraser, and neither is named here: the flag is.
func test_the_painting_tools_are_the_ones_whose_descriptors_say_so() -> void:
    var ids := _bar.painting_tool_ids()
    assert_false(ids.is_empty(), "At least one registered tool paints")
    for id: StringName in ids:
        var descriptor := _machine.get_descriptor(id)
        assert_true(descriptor.is_painting, "%s is on the list because its descriptor says it paints" % id)
    for id: StringName in [&"pan", &"zoom", &"eyedropper"]:
        assert_false(ids.has(id), "and %s is not on it" % id)


func test_the_brush_group_has_a_place_whatever_tool_is_chosen() -> void:
    var size := _bar.control_for(&"radius")
    var opacity := _bar.control_for(&"opacity")
    assert_not_null(size, "The bar built a Size control")

    for id: StringName in [&"brush", &"eyedropper", &"pan", &"zoom"]:
        _machine.set_active_tool(id)
        assert_true(_bar.shows_for_active_tool(size), "Size has a place with %s chosen" % id)
        assert_true(_bar.shows_for_active_tool(opacity), "and so does Opacity")
        assert_true(_bar.shows_for_active_tool(_bar.preset_box), "beside the skeleton's own group")


## The live half. Without this the control would be gone, and the shape that would have
## replaced it without this is worse: a control on the bar writing nowhere.
func test_a_size_written_with_the_eyedropper_chosen_lands_on_the_brush() -> void:
    var brush := _machine.get_tool(&"brush")
    _machine.set_active_tool(&"eyedropper")
    assert_eq(_bar.shown_tool_id(), &"eyedropper", "The eyedropper is what the bar shows")
    assert_eq(_bar.owner_of(&"radius"), &"brush", "and Size is still the brush's")

    assert_true(_bar.write_option(&"radius", 0.06), "so the bar can write it")
    assert_almost_eq(brush.settings.radius, 0.06, 0.0001, "and the brush is what it wrote")
    assert_almost_eq(float(_bar.read_option(&"radius")), 0.06, 0.0001, "and reads back through the same door")


## A slider moved by hand goes through `ToolOptionControls`, which writes to
## whoever the last `sync` recorded and so writes nothing for a brush row while
## the eyedropper is shown. The bar catches the announcement and lands it.
func test_a_control_moved_by_hand_lands_on_the_brush_too() -> void:
    var brush := _machine.get_tool(&"brush")
    _machine.set_active_tool(&"eyedropper")
    var size := _bar.control_for(&"radius") as FactorSlider
    assert_not_null(size, "There is a slider to move")

    size.value_changed.emit(0.07)
    assert_almost_eq(brush.settings.radius, 0.07, 0.0001, "The hand wrote the brush through the bar's seam")


## A tool that declares its own keeps them, which is the half the rule must not break.
func test_the_shown_tool_still_owns_the_keys_it_declared() -> void:
    _machine.set_active_tool(&"brush")
    assert_eq(_bar.owner_of(&"radius"), &"brush", "The brush owns its own Size")
    assert_eq(_bar.owner_of(&"blend_mode"), &"brush", "and its own blend mode")
    assert_eq(_bar.owner_of(&"nothing_declares_this"), &"brush", "and a key nobody declared answers the shown tool")
