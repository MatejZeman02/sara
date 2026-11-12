## The bar's own controls placed in a docker work as they do on the bar.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The top bar hands the door a
## view of each of its own controls, through `SaSettings.register_layout_element`
## as a module would, so each view is built here through the door a composed
## docker builds it through, over a top bar and a tool options bar of the
## suite's own, and parented under a node in the tree as a placed view is. The
## rotation pair is handed the surface's view, since a suite has no scene with a
## main canvas for it to find one in.
##
## `scenarios/the-bar-s-own-controls-placed-in-a-docker-work-as-they-do-on-the-bar.json`
## places Brush Presets, Rotation and Stabilizer Toggle in a composed docker of
## the running app and clicks the placed toggle.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const CATEGORY: String = "TopMenuBar"

## The nine of the note: the preset group, Keep, the rotation and its reset,
## the three symmetry switches, the stabiliser's toggle and Edit Brush.
const NINE: Array[String] = [
    "Brush Presets",
    "Keep Blend Mode",
    "Rotation",
    "Reset Rotation",
    "Mirror H",
    "Mirror V",
    "Radial",
    "Stabilizer Toggle",
    "Edit Brush",
]

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _bar: ToolOptionsBar = null
var _top: TopMenuBar = null
var _host: Node = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _registries = Fixtures.make_registries(_surface)
    _machine.set_active_tool(&"brush")
    _bar = ToolOptionsBar.new()
    _bar.target_tool_machine = _machine
    _bar._ready()
    _bar.bind_registries(_registries.blend_modes)
    _top = TopMenuBar.new()
    _top.rotation_row = SaTopBarRotation.new(_surface.view)
    _top.add_tool_options(_bar)
    _host = Node.new()
    _host.name = "T2BarHost"
    EventBus.add_child(_host)
    _host.add_child(_top)


func after_each() -> void:
    _host.free()
    _host = null
    _top = null
    _bar = null
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    _registries = null


## A view of *element* built through the door and placed under the suite's host,
## which is in the tree, the way a composed docker places it.
func _view(element: String) -> Control:
    var built := SaSettings.build_element_view(CATEGORY, element)
    if built != null:
        _host.add_child(built)
    return built


func test_each_of_the_nine_is_placeable_under_the_title_it_had() -> void:
    for element: String in NINE:
        assert_true(SaSettings.is_placeable(CATEGORY, element), "%s is placeable, the top bar registered it" % element)
        var view := _view(element)
        assert_not_null(view, "and the door builds a view of %s" % element)
        var home: Variant = _bar.layout_elements().get(element, _top.rotation_row.elements().get(element))
        if view != null and home != null:
            assert_true(view.name != (home as Node).name, "%s's view is not named as the bar's control is" % element)
    assert_eq(SaSettings.element_title(CATEGORY, "Mirror H"), "Mirror H", "Mirror H keeps the one name it has on screen")


func test_a_press_on_the_mirror_h_view_turns_the_symmetry_on_and_presses_the_bar() -> void:
    var mirrors := _surface.get_document().symmetry
    var view := _view("Mirror H") as Button
    assert_not_null(view, "There is a Mirror H view")
    assert_false(mirrors.mirror_horizontal, "The canvas starts with no horizontal symmetry")
    assert_false(view.button_pressed, "and the view is not lit")

    view.button_pressed = true
    assert_true(mirrors.mirror_horizontal, "The press turned the canvas's horizontal symmetry on")
    assert_true(_bar.mirror_h_btn.button_pressed, "and the bar's Mirror H button is pressed")
    assert_true(view.button_pressed, "and the view stays lit")

    _bar.mirror_h_btn.button_pressed = false
    assert_false(mirrors.mirror_horizontal, "The bar's own button turns it off again")
    assert_false(view.button_pressed, "and the view goes out with it")


func test_the_mirror_v_and_radial_views_drive_the_canvas_as_the_bars_buttons_do() -> void:
    var mirrors := _surface.get_document().symmetry
    var vertical := _view("Mirror V") as Button
    var radial := _view("Radial") as Button
    assert_not_null(vertical, "There is a Mirror V view")
    assert_not_null(radial, "and a Radial view")

    vertical.button_pressed = true
    assert_true(mirrors.mirror_vertical, "The Mirror V press turned the vertical symmetry on")
    assert_true(_bar.mirror_v_btn.button_pressed, "and the bar's Mirror V button is pressed")

    radial.button_pressed = true
    assert_eq(mirrors.radial, mirrors.radial_count, "The Radial press repeats strokes around the centre")
    assert_true(_bar.radial_btn.button_pressed, "and the bar's Radial button is pressed")

    _bar.radial_btn.button_pressed = false
    assert_eq(mirrors.radial, 0, "The bar's Radial puts it off")
    assert_false(radial.button_pressed, "and the Radial view goes out")
    assert_true(vertical.button_pressed, "while the Mirror V view stays lit")


func test_a_press_on_the_keep_blend_view_is_the_bars_keep_toggle() -> void:
    var was := SaSettings.keep_blend_mode
    var view := _view("Keep Blend Mode") as Button
    assert_not_null(view, "There is a Keep Blend Mode view")
    assert_eq(view.button_pressed, was, "The view starts as the setting stands")

    view.button_pressed = not was
    assert_eq(SaSettings.keep_blend_mode, not was, "The press wrote the setting")
    assert_eq(_bar.keep_blend_chk.button_pressed, not was, "and the bar's Keep toggle shows it")
    assert_eq(_bar.preset_store.keep_blend_mode, not was, "and the preset store keeps the blend as the bar's would")

    _bar.keep_blend_chk.button_pressed = was
    assert_eq(view.button_pressed, was, "The bar's own toggle puts it back, and the view follows")
    SaSettings.keep_blend_mode = was


func test_a_move_on_the_rotation_view_turns_the_canvas_and_the_bars_slider() -> void:
    var row := _view("Rotation")
    assert_not_null(row, "There is a Rotation view")
    var view := row.get(&"slider") as FactorSlider
    assert_not_null(view, "holding a slider")
    view.value = 30.0
    view.value_changed.emit(30.0)
    assert_almost_eq(rad_to_deg(_surface.view.get_rotation()), 30.0, 0.01, "The move turned the canvas to 30 degrees")
    assert_almost_eq(_top.rotation_row.slider.value, 30.0, 0.01, "and the bar's slider stands at that angle")

    _surface.view.rotate_at(deg_to_rad(-45.0), _surface.view.get_viewport_size() * 0.5)
    assert_almost_eq(view.value, -45.0, 0.01, "A turn from elsewhere puts its angle on the view")

    var reset := _view("Reset Rotation") as Button
    assert_not_null(reset, "There is a Reset Rotation view")
    reset.pressed.emit()
    assert_almost_eq(rad_to_deg(_surface.view.get_rotation()), 0.0, 0.01, "Its press turns the canvas back")
    assert_almost_eq(view.value, 0.0, 0.01, "and the placed slider follows")
    assert_almost_eq(_top.rotation_row.slider.value, 0.0, 0.01, "as the bar's does")


func test_a_press_on_the_stabilizer_view_writes_the_tool_in_hand_and_lights_the_bar() -> void:
    var view := _view("Stabilizer Toggle") as Button
    assert_not_null(view, "There is a Stabilizer Toggle view")
    var was_on := int(_bar.read_option(&"stabilizer_mode")) > 0
    assert_eq(view.button_pressed, was_on, "The view starts as the brush's stabiliser stands")

    view.button_pressed = not was_on
    assert_eq(int(_bar.read_option(&"stabilizer_mode")) > 0, not was_on, "The press switched the brush's stabiliser")
    assert_eq(_bar.stabilizer_btn.button_pressed, not was_on, "and the bar's toggle shows it")

    _bar.stabilizer_btn.button_pressed = was_on
    assert_eq(view.button_pressed, was_on, "The bar's own toggle puts it back, and the view follows")


func test_the_presets_view_reads_as_the_bars_preset_button() -> void:
    var view := _view("Brush Presets") as Button
    assert_not_null(view, "There is a Brush Presets view, one button for the group")
    assert_eq(view.text, _bar.preset_menu.text, "It names what the bar's preset button names")
    assert_true(view.toggle_mode, "and lights as that button does, while the docker is open")
    assert_false(view.button_pressed, "which with no docker in the tree it is not")


func test_a_press_on_the_edit_brush_view_is_a_press_of_the_bars_edit_brush() -> void:
    var presses: Array[int] = [0]
    var count := func() -> void: presses[0] += 1
    _bar.edit_brush_btn.pressed.connect(count)
    var view := _view("Edit Brush") as Button
    assert_not_null(view, "There is an Edit Brush view")
    assert_eq(view.text, _bar.edit_brush_btn.text, "named as the bar's button is")
    # Out of the tree for the press, so the bar's handler counts the press and
    # opens no editor window a suite would leave behind.
    EventBus.remove_child(_host)
    view.pressed.emit()
    assert_eq(presses[0], 1, "Its press is a press of the bar's Edit Brush, which opens the editor")
    _bar.edit_brush_btn.pressed.disconnect(count)
