## A fresh profile's bar shows its second row, the first row
## holds the menus and the window buttons only, and every option of the brush
## is on the second, with the overflow button, in a bar lower than a two-row bar with every control on the first.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The secondary top bar is enabled by default and holds everything but the
## menus and the window buttons, and it is thin, as in Krita. The running
## app's proof is
## `scenarios/the-bars-second-row-is-on-and-holds-every-tool-option.json`.
##
## The bar stands in the tree under an autoload, the way
## `test_the_default_layout_opens_its_columns_under_the_bar.gd` puts it, so its
## controls read the shared theme and ask for the heights the app draws.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar's controls come from the tools' descriptors, and building one needs
## a machine with the built-in tools, which needs a device.
const REQUIRES_GPU := true

## A bar this wide holds every control it has, so nothing goes into the
## overflow and every control is on its row.
const ROOMY := 4000.0

## The bar's height with every control on one row, logical, at scale 1 with the
## second row on: a first row of 33, the separation of 2, a
## second row of 39 and the bar's two margins.
const BAR_HEIGHT_BEFORE := 76.0

## The scratch profile, absent before each test, so the bar is a fresh one.
static var scratch_profile: String = SaDataRoot.path("test_d6_second_row_profile.cfg")

var _saved_path: String
var _saved_row: bool
var _surface: SaSurface
var _machine: ToolMachine
var _host: Node


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    _saved_row = SaSettings.second_row
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()
    SaSettings.load_settings()
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    # Parented to an autoload rather than to the root, because the runner calls
    # a suite from its own `_ready`.
    _host = Node.new()
    _host.name = "D6Host"
    EventBus.add_child(_host)


## The run's own profile is put back as it was, the switch with it, since a
## later suite reads the bar it leaves.
func after_each() -> void:
    _host.free()
    Fixtures.teardown(_surface, _machine)
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    SaSettings.second_row = _saved_row


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## A bar with its tool options, the way main builds them, in the tree and
## *width* wide.
func _bar(width: float = ROOMY) -> TopMenuBar:
    var options := ToolOptionsBar.new()
    options.target_tool_machine = _machine
    options._ready()
    var bar := TopMenuBar.new()
    bar.add_tool_options(options)
    _host.add_child(bar)
    # A bar outside a container keeps the width written to it only with its
    # anchors pinned together.
    bar.set_anchor(SIDE_RIGHT, 0.0)
    bar.size.x = width
    bar.apply_layout_settings()
    return bar


## The names of *row*'s children that are on screen, in order.
func _shown(row: Container) -> Array[String]:
    var out: Array[String] = []
    for child in row.get_children():
        var control := child as Control
        if control != null and control.visible:
            out.append(String(control.name))
    return out


## The row elements the brush shows, by stored name.
func _brush_elements(bar: TopMenuBar) -> Dictionary:
    var out := {}
    var elements := bar.rows.elements()
    for element: String in elements:
        var node: Control = elements[element]
        if node != null and node.visible:
            out[element] = node
    return out


## A first launch writes the defaults back from whatever the run held before,
## so whether the file carries the key depends on the suite before this one.
## What it reads, and stores when it stores anything, is on.
func test_a_fresh_profile_shows_the_second_row() -> void:
    assert_true(SaSettings.second_row, "A fresh profile reads the row on")
    assert_eq(SaSettings.config.get_value("ui", "second_row", true), true, "and stores nothing else")
    var bar := _bar()
    assert_true(bar.rows.second_row.visible, "so the bar shows it")


## The note's "moving all other than menus/x-[] to it": the first row is the
## menus and the window buttons, with the separator between the menus and the
## empty slot, and nothing of the tool options is on it.
func test_the_first_row_holds_the_menus_and_the_window_buttons_only() -> void:
    var bar := _bar()
    assert_eq(
        _shown(bar.rows.main_row),
        ["HBoxMenuBar", "MenuSeparator", "BrushOptionsScrollContainer", "HBoxWindowControls"] as Array[String],
        "The first row is the menus, the separator, the slot and the window buttons"
    )
    assert_eq(_shown(bar.rows.row_container(1)), [] as Array[String], "and the slot holds no control of the brush")
    assert_almost_eq(bar.rows.row_spent(1), 0.0, 0.01, "so it spends nothing of its row")
    var order := SaSettings.get_layout_order("TopMenuBar")
    assert_eq(
        order.slice(0, TopMenuBar.MENU_NAMES.size() + 1),
        TopMenuBar.MENU_NAMES + [SaSettings.ROW_SENTINEL],
        "The sentinel follows the last menu"
    )


## Every control the brush shows is on the second row, Edit Brush with them,
## which no order names, and the overflow button stands at its end.
func test_the_second_row_holds_every_option_of_the_brush() -> void:
    var bar := _bar()
    var shown := _brush_elements(bar)
    assert_true(shown.size() >= 10, "The brush shows its controls: %s" % ", ".join(shown.keys()))
    for element: String in ["Brush Presets", "blend_mode", "radius", "opacity", "Edit Brush", "Stabilizer Toggle"]:
        assert_true(shown.has(element), "including %s" % element)
    for element: String in shown:
        var node: Control = shown[element]
        assert_eq(node.get_parent(), bar.rows.second_options_row, "%s is on the second row" % element)
    assert_eq(bar.rows.overflow.get_parent(), bar.rows.second_row, "The overflow button is on the second row")
    assert_eq(bar.rows.overflow.get_index(), bar.rows.second_slot.get_index() + 1, "right after its slot")
    assert_eq(bar.rows.row_report(2)["holds_overflow"], true, "and the report says so")


## A narrow bar sends the second row's tail into the list the button there
## opens, and the first row, which holds no option, sends nothing.
func test_a_narrow_bar_overflows_from_the_second_row() -> void:
    var bar := _bar(1100.0)
    var held: Array = bar.rows.overflow.report()["held"]
    assert_false(held.is_empty(), "A narrow bar overflows")
    assert_true(bar.rows.overflow.visible, "and shows the button")
    assert_eq(bar.rows.overflow.get_parent(), bar.rows.second_row, "on the second row")
    assert_true(bar.rows.row_spent(2) <= bar.rows.row_budget(2), "which then fits its budget, the button counted")
    assert_eq(_shown(bar.rows.row_container(1)), [] as Array[String], "while the first row holds no control still")


## "And make it less thick": each row is as tall as the tallest control it
## holds, and the bar is lower than the 76 it was with both rows on. The second
## row's floor is what its tallest controls, Edit Brush and the rotation's reset,
## ask for in the running app, 33, which the scenario records. The suite's theme
## draws them smaller, so here the floor is the row's height.
func test_both_rows_are_as_thin_as_their_controls_and_the_bar_is_lower() -> void:
    var bar := _bar()
    var tallest_option := 0.0
    for child in bar.rows.second_options_row.get_children():
        var control := child as Control
        if control != null and control.visible:
            tallest_option = maxf(tallest_option, control.get_combined_minimum_size().y)
    assert_true(
        tallest_option <= float(SaRowSlot.SECOND_ROW_HEIGHT),
        "No control of the brush asks for more than the floor, %d of %d" % [int(tallest_option), SaRowSlot.SECOND_ROW_HEIGHT]
    )
    var second := bar.rows.second_row.get_combined_minimum_size().y
    assert_almost_eq(second, float(SaRowSlot.SECOND_ROW_HEIGHT), 0.5, "and the second row asks for the floor and no more")

    var tallest_pinned := 0.0
    for child in bar.rows.main_row.get_children():
        var control := child as Control
        if control != null and control.visible:
            tallest_pinned = maxf(tallest_pinned, control.get_combined_minimum_size().y)
    var first := bar.rows.main_row.get_combined_minimum_size().y
    assert_almost_eq(first, tallest_pinned, 0.5, "The first row asks for what its tallest child does")
    assert_true(first < second, "which is lower than the second, %d under %d" % [int(first), int(second)])

    var height := bar.get_combined_minimum_size().y
    var said := "The bar is %d tall, lower than the %d it was" % [int(height), int(BAR_HEIGHT_BEFORE)]
    assert_true(height < BAR_HEIGHT_BEFORE, said)


## A profile that switched the row off keeps it off, and its bar puts every
## option back on the first row between the menus and the window buttons.
func test_a_profile_that_switched_the_row_off_keeps_it_off() -> void:
    SaSettings.second_row = false
    SaSettings.load_settings()
    assert_false(SaSettings.second_row, "The switch reads off after a reload")
    var bar := _bar()
    assert_false(bar.rows.second_row.visible, "and the bar shows one row")
    var radius: Control = bar.rows.elements()["radius"]
    assert_eq(radius.get_parent(), bar.rows.row_container(1), "with Size on it")
    assert_eq(bar.rows.overflow.get_parent(), bar.rows.main_row, "and the overflow button before the window buttons")


## A stored order keeps its sentinel where the painter dragged it: after Keep
## Blend Mode, the place a stored order gives it, the preset, the blend mode and
## Keep stay on the first row and the rest go to the second.
func test_a_stored_order_keeps_its_sentinel() -> void:
    var order := SaSettings.get_layout_order("TopMenuBar")
    order.erase(SaSettings.ROW_SENTINEL)
    order.insert(order.find("Keep Blend Mode") + 1, SaSettings.ROW_SENTINEL)
    SaSettings.set_layout_order("TopMenuBar", order)
    SaSettings.load_settings()
    assert_eq(SaSettings.get_layout_order("TopMenuBar"), order, "The stored order reads back as stored")
    var bar := _bar()
    var elements := bar.rows.elements()
    for element: String in ["Brush Presets", "blend_mode", "Keep Blend Mode"]:
        assert_eq((elements[element] as Control).get_parent(), bar.rows.row_container(1), "%s stays on the first row" % element)
    for element: String in ["radius", "opacity", "Rotation"]:
        assert_eq((elements[element] as Control).get_parent(), bar.rows.row_container(2), "%s is on the second" % element)
