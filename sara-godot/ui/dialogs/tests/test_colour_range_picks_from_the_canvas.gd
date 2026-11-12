## Colour Range picks from a click on the canvas.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The dialog once opened with
## Pick from canvas ticked and the Brush still in the hand, so a click on the
## canvas painted a dab and the swatch stayed as it was, and a pick that did
## reach the swatch repainted the painter's foreground.
##
## The dialog now puts the Eyedropper in the hand while the box is ticked and
## gives the tool and the foreground back on every way out. The running app is
## `scenarios/colour-range-picks-from-a-click-on-the-canvas.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A machine holding the built-in tools needs a surface, which needs a device.
const REQUIRES_GPU := true

const PAINTERS := Color(0.8, 0.2, 0.2, 1.0)
## A colour the swatch can hold exactly, because the swatch takes a pick as the
## hex it shows.
const BLUE := Color(26.0 / 255.0, 77.0 / 255.0, 230.0 / 255.0, 1.0)

var _kept_embedding: bool = true
var _kept_foreground: Color = Color.BLACK
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _dialog: SaColorRangeDialog = null
var _host: Node = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _kept_foreground = SaColors.foreground
    SaColors.foreground = PAINTERS
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _host = Node.new()
    _host.name = "S5TestHost"
    EventBus.add_child(_host)
    _dialog = SaColorRangeDialog.new()
    _host.add_child(_dialog)


func after_each() -> void:
    _dialog.free()
    _dialog = null
    _host.free()
    _host = null
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    SaColors.foreground = _kept_foreground
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding


func _open() -> void:
    _dialog.open(SaColors.foreground, 40.0, true, int(SaSelection.Mode.REPLACE), true, _machine)


## What an eyedropper click announces: the colour goes out on the bus.
func _pick(color: Color) -> void:
    EventBus.color_picked.emit(color)


func test_opening_puts_the_eyedropper_in_the_hand() -> void:
    _open()
    assert_eq(_machine.default_tool_name, &"eyedropper", "The Eyedropper is the tool in the hand")
    assert_eq(_machine.active_tool_name, &"eyedropper", "and the machine is on it")
    assert_true(bool(_dialog.describe()["holding"]), "The dialog says it holds the tool")


## The hold asks the machine for the tool whose descriptor picks, so the
## skeleton names no module's tool id.
func test_the_machine_names_the_picker_by_its_descriptor() -> void:
    assert_eq(_machine.picker_tool_name(), &"eyedropper", "The base module's Eyedropper is the tool that picks")
    assert_true(_machine.get_descriptor(&"eyedropper").picks_colour, "because its descriptor says so")
    assert_false(_machine.get_descriptor(&"brush").picks_colour, "and the Brush's does not")


func test_a_pick_lands_in_the_swatch_and_leaves_the_foreground_after_close() -> void:
    _open()
    _pick(BLUE)
    assert_true(_dialog.picked_color().is_equal_approx(BLUE), "The swatch takes the blue")
    _dialog.hide()
    assert_true(SaColors.foreground.is_equal_approx(PAINTERS), "The foreground is what it was after the close")
    assert_eq(_machine.default_tool_name, &"brush", "and the Brush is back")


func test_every_way_of_closing_gives_the_tool_back() -> void:
    # Escape and the corner both emit `close_requested`, which the router's own
    # suite holds, so that is the one signal here for the two of them.
    for way: String in ["apply", "cancel", "escape or the corner", "hide"]:
        _open()
        _pick(BLUE)
        match way:
            "apply":
                _dialog.apply_range()
            "cancel":
                _dialog.page.cancelled.emit()
            "escape or the corner":
                _dialog.close_requested.emit()
            "hide":
                _dialog.hide()
        assert_false(_dialog.visible, "%s closes the dialog" % way)
        assert_eq(_machine.default_tool_name, &"brush", "%s gives the Brush back" % way)
        assert_true(SaColors.foreground.is_equal_approx(PAINTERS), "%s leaves the foreground alone" % way)


func test_unticking_the_box_gives_the_tool_and_the_foreground_back() -> void:
    _open()
    _pick(BLUE)
    _dialog._pick_row.drive(false)
    assert_eq(_machine.default_tool_name, &"brush", "The Brush is back with the box off")
    assert_true(SaColors.foreground.is_equal_approx(PAINTERS), "and so is the foreground")
    _pick(Color.GREEN)
    assert_true(_dialog.picked_color().is_equal_approx(BLUE), "A pick the box does not ask for stays out of the swatch")
    _dialog._pick_row.drive(true)
    assert_eq(_machine.default_tool_name, &"eyedropper", "Ticking it again takes the Eyedropper")


func test_a_tool_the_painter_chose_meanwhile_is_left_alone() -> void:
    _open()
    _machine.set_active_tool(&"eraser")
    _dialog.hide()
    assert_eq(_machine.default_tool_name, &"eraser", "The eraser the painter chose stays in the hand")


func test_the_previous_tool_is_what_it_was() -> void:
    _machine.set_active_tool(&"eraser")
    _machine.set_active_tool(&"brush")
    var before := _machine.previous_tool_name
    _open()
    _dialog.hide()
    assert_eq(_machine.previous_tool_name, before, "The tool Enter hands back to is what it was")


func test_the_box_says_what_is_put_back() -> void:
    _open()
    var row := _dialog._pick_row
    assert_true(row.explanation.contains("foreground"), "The sentence names the foreground: %s" % row.explanation)
    assert_true(row.explanation.contains("tool"), "and the tool")


func test_a_dialog_with_no_machine_holds_the_foreground_alone() -> void:
    _dialog.open(SaColors.foreground, 40.0, true, int(SaSelection.Mode.REPLACE), true)
    _pick(BLUE)
    assert_true(_dialog.picked_color().is_equal_approx(BLUE), "A pick still lands in the swatch")
    _dialog.hide()
    assert_true(SaColors.foreground.is_equal_approx(PAINTERS), "and the foreground comes back")
    assert_eq(_machine.default_tool_name, &"brush", "with no machine the tool is not touched")


func test_a_second_open_while_showing_keeps_the_first_tool() -> void:
    _open()
    _open()
    _dialog.hide()
    assert_eq(_machine.default_tool_name, &"brush", "Opening twice does not keep the Eyedropper as the tool before")
