## What a stored profile does not name is appended in the order a fresh
## bar holds it, so the second row reads in one order whichever side of the
## door an element came in by.
##
## The profile is `scenarios/top-bar-second-row.json`'s: it names the stamp brush's
## controls the way a version 4 profile did, so every one of them is in the
## tail. They must not arrive after Keep Blend Mode, the rotation pair and the
## symmetry buttons, which would put the blend dropdown at the far end of the
## second row.
##
## Built detached and `_ready()`ed by hand, the way `test_top_bar_rows.gd`
## does, because a PopupMenu is a Window and nothing here needs a tree.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar's controls come from the tools' descriptors, and building one needs
## a machine with the built-in tools, which needs a device.
const REQUIRES_GPU := true

## The scenario's `top_bar_order`, verbatim: the English names a profile
## written before version 5 carried, and the sentinel between Erase Toggle and
## Size Slider.
const F9_ROWS_ORDER := [
    "File",
    "Edit",
    "View",
    "Window",
    "Image",
    "Layer",
    "Select",
    "Filter",
    "Modules",
    "Help",
    "Brush Presets",
    "Blend Mode",
    "Erase Toggle",
    "Second Row",
    "Size Slider",
    "Opacity Slider",
    "Hardness Slider",
    "Flow Slider",
    "Size Pressure",
    "Opacity Pressure",
]

## What the brush shows on the second row, in the order it draws them. Every
## one is past the sentinel above, and every one is a key the profile does not
## name, so the whole row is the appended tail. Edit Brush ends it: it is on no order, and a control no order
## names comes after every
## one it does.
const SECOND_ROW := [
    "blend_mode",
    "Keep Blend Mode",
    "eraser_toggled",
    # Opacity before Radius, and no Flat or Environment button and no Mirror V
    # on a fresh bar.
    "opacity",
    "radius",
    # The document's Double Resolution toggle.
    "Double Resolution",
    "Rotation",
    "Reset Rotation",
    "Mirror H",
    "Radial",
    "Stabilizer Toggle",
    # Undo and Redo after the stabiliser's toggle.
    "Undo",
    "Redo",
    # Focus Mode after Redo, anchored there by its registration.
    "Focus Mode",
    "Edit Brush",
]

var _saved_path: String = ""
var _saved_row: bool = false
var _row_saved: bool = false
var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    if not _row_saved:
        _saved_row = SaSettings.second_row
        _row_saved = true
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(SaDataRoot.path("test_d22_second_row.cfg"))
    _remove_profile()
    SaSettings.load_settings()


## The run hands every suite one profile, and a suite before this one can leave
## a stored order in it. This suite is one of the few that writes one, so it is
## the suite that would carry that order into a later one that reads a bar
## where nothing was moved: `test_menus` asserts the default order and caught
## exactly that. The layout is cleared through this suite's own profile, gone
## by now, and the run's order is put back as a first launch draws it.
func after_each() -> void:
    _remove_profile()
    SaSettings.load_settings()
    _remove_profile()
    var fresh := SaSettings.get_layout_order("TopMenuBar")
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    SaSettings.set_layout_order("TopMenuBar", fresh)
    SaSettings.second_row = _saved_row
    if _machine != null:
        Fixtures.teardown(_surface, _machine)
        _surface = null
        _machine = null


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(SaDataRoot.path("test_d22_second_row.cfg")) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## A bar with its tool options, the way main builds them, detached, over a
## machine holding the built-in tools so the brush's controls exist.
func _bar() -> TopMenuBar:
    if _machine == null:
        _surface = Fixtures.make_surface()
        _machine = Fixtures.make_bound_machine(_surface)
    var bar := TopMenuBar.new()
    var options := ToolOptionsBar.new()
    options.target_tool_machine = _machine
    options._ready()
    bar.add_tool_options(options)
    bar._ready()
    # `TopMenuBar._init` takes `PRESET_TOP_WIDE`, and a detached Control has no
    # parent to lay it out, so the anchors are pinned together to keep the
    # "size overridden after _ready()" warning out of the gate.
    bar.set_anchor(SIDE_RIGHT, 0.0)
    return bar


## The controls of *row* that are on screen, in the order they are drawn. The
## breaks drawn between the groups are not controls and are left out.
func _visible(row: Container) -> Array:
    var out: Array = []
    for child in row.get_children():
        var control := child as Control
        if control != null and control.visible and not String(control.name).begins_with(SaTopBarRows.BREAK_NAME):
            out.append(control)
    return out


## What the scenario's profile puts on the second row, in order.
func test_the_scenarios_profile_opens_with_the_brush_controls_on_the_second_row() -> void:
    SaSettings.second_row = true
    SaSettings.set_layout_order("TopMenuBar", F9_ROWS_ORDER)
    var bar := _bar()

    var elements := bar.rows.elements()
    var expected: Array = []
    for key: String in SECOND_ROW:
        assert_true(elements.has(key), "The brush declares %s" % key)
        expected.append(elements[key])
    assert_eq(
        _visible(bar.rows.second_options_row),
        expected,
        "Blend mode, Keep blend, Erase, Size and Opacity first, the rotation pair, the symmetry three, Undo, Redo, Edit Brush"
    )
    bar.free()


## The rule behind it, stated without the bar: what a stored order lacks is the
## fresh order filtered to those elements, and not the defaults first and every
## registered element after them.
func test_what_a_stored_order_lacks_is_appended_in_the_fresh_orders_sequence() -> void:
    SaSettings.set_layout_order("TopMenuBar", F9_ROWS_ORDER)
    var stored := SaSettings.get_layout_order("TopMenuBar")
    _remove_profile()
    SaSettings.load_settings()
    var fresh := SaSettings.get_layout_order("TopMenuBar")

    var tail: Array = []
    for element: String in stored:
        if not F9_ROWS_ORDER.has(element):
            tail.append(element)
    var expected: Array = []
    for element: String in fresh:
        if not F9_ROWS_ORDER.has(element):
            expected.append(element)

    assert_eq(tail, expected, "The tail is the fresh order's own sequence, filtered to what the profile lacked")
    assert_eq(
        tail.slice(0, 4),
        ["Tools", "blend_mode", "Keep Blend Mode", "eraser_toggled"],
        "and the stamp brush's blend mode is the first control in it, not the last"
    )
