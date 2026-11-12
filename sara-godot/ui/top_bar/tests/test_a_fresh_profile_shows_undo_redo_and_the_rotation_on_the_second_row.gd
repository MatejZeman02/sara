## A fresh profile's bar shows Undo, Redo, the rotation and
## its reset on the second row, at the width of the app's own window.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The three went invisible in `scripts/test_undo_and_redo_stand_on_the_bar`
## because that Sara read the painter's own settings, whose
## `[profile_visibility]` hid them, and not because a fresh bar lost them. This
## suite reads the fresh bar itself, so a change to the shipped defaults that
## hides any of them fails here, beside the bar, rather than only in a real
## Sara. The fixture is that of `test_the_bars_second_row_is_on_and_holds_every_tool_option.gd`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar's controls come from the tools' descriptors, and building one needs
## a machine with the built-in tools, which needs a device.
const REQUIRES_GPU := true

## The width of the window the real Sara of the Python suite opens, logical.
const APP_WIDTH := 1920.0

## The second row's elements the Python suite found hidden, by stored name and
## by node name.
const ELEMENTS := {
    "Undo": "UndoBtn",
    "Redo": "RedoBtn",
    "Rotation": "RotationSlider",
    "Reset Rotation": "ResetRotationBtn",
}

## The scratch profile, absent before each test, so the bar is a fresh one.
static var scratch_profile: String = SaDataRoot.path("test_fresh_bar_profile.cfg")

var _saved_path: String
var _surface: SaSurface
var _machine: ToolMachine
var _host: Node


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()
    SaSettings.load_settings()
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    # Parented to an autoload rather than to the root, because the runner calls
    # a suite from its own `_ready`.
    _host = Node.new()
    _host.name = "U463Host"
    EventBus.add_child(_host)


## The run's own profile is put back as it was, since a later suite reads the
## bar it leaves.
func after_each() -> void:
    _host.free()
    Fixtures.teardown(_surface, _machine)
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## A bar with its tool options, the way main builds them, in the tree and
## *width* wide.
func _bar(width: float) -> TopMenuBar:
    var options := ToolOptionsBar.new()
    options.target_tool_machine = _machine
    options._ready()
    var bar := TopMenuBar.new()
    bar.add_tool_options(options)
    _host.add_child(bar)
    bar.set_anchor(SIDE_RIGHT, 0.0)
    bar.size.x = width
    bar.apply_layout_settings()
    return bar


## The profile asks for each of them, and the bar shows each on its second row,
## in the tree and not in the overflow's list.
func test_undo_redo_and_the_rotation_stand_visible_on_a_fresh_bar() -> void:
    var bar := _bar(APP_WIDTH)
    assert_true(bar.rows.second_row.is_visible_in_tree(), "A fresh bar shows its second row")
    var elements := bar.rows.elements()
    for element: String in ELEMENTS:
        assert_true(SaSettings.get_element_visible("TopMenuBar", element), "A fresh profile shows %s" % element)
        var node: Control = elements.get(element)
        assert_not_null(node, "The bar has %s" % element)
        if node == null:
            continue
        assert_eq(String(node.name), ELEMENTS[element], "under the name the door reads, %s" % ELEMENTS[element])
        assert_eq(node.get_parent(), bar.rows.second_options_row, "%s is on the second row" % element)
        assert_true(node.is_visible_in_tree(), "and shows there, at %d wide" % int(APP_WIDTH))
    var held: Array = bar.rows.overflow.report()["held"]
    for element: String in ELEMENTS:
        assert_false(held.has(ELEMENTS[element]), "%s is not in the overflow's list: %s" % [element, held])
