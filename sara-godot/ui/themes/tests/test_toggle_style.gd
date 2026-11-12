## A toggle button says whether it is on.
##
## A painter must be able to see whether a toggle is on. On a Tool Options row the pressed state
## was Godot's own default box, which hid it. The claims here are the two halves of the fix: the pressed box
## is visibly apart from the normal one in every shipped palette, and the door
## that puts it on a button is walked through by the toggles a painter meets.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The tool options bar's own toggles are built from a bound machine, which
## needs a surface, which needs a device.
const REQUIRES_GPU := true

var _saved_theme: String = ""


func before_each() -> void:
    _saved_theme = SaTheme.palette_id


func after_each() -> void:
    SaTheme.use_named(_saved_theme)


## How far apart two colours are, as the sum of the three channel differences.
## A sum rather than a distance, because the claim is "a painter can see it" and
## nothing here needs a perceptual number to say that a blue box is not a black
## one.
func _apart(first: Color, second: Color) -> float:
    return absf(first.r - second.r) + absf(first.g - second.g) + absf(first.b - second.b)


## The pressed box differs from the normal one in every palette Sara ships, and
## not by a shade. The engine's own default pressed box is what this replaces
## and the whole complaint about it is that the difference was invisible.
func test_the_pressed_box_is_apart_from_the_normal_one_in_every_palette() -> void:
    for id: String in SaTheme.PALETTES:
        SaTheme.use_named(id)
        var normal := SaTheme.make_toggle_style("normal")
        var pressed := SaTheme.make_toggle_style("pressed")
        var apart := _apart(normal.bg_color, pressed.bg_color)
        assert_true(apart > 0.3, "%s: the pressed box is apart from the normal one, %.2f" % [id, apart])
        assert_eq(pressed.bg_color, SaTheme.palette.toggle_on, "%s: and it is the accent moved as far as white text needs" % id)
        var hover := SaTheme.make_toggle_style("hover")
        assert_true(_apart(hover.bg_color, pressed.bg_color) > 0.3, "%s: hover is not the pressed box either" % id)


## The boxes follow a theme switch, because they are bound to the palette the
## way every other box in this file is rather than fixed at build time.
func test_the_boxes_follow_a_theme_switch() -> void:
    SaTheme.use_named("default")
    var button := Button.new()
    button.toggle_mode = true
    SaTheme.make_toggle(button)
    var was: Color = (button.get_theme_stylebox("pressed") as StyleBoxFlat).bg_color

    SaTheme.use_named("krita")
    var now: Color = (button.get_theme_stylebox("pressed") as StyleBoxFlat).bg_color
    assert_true(_apart(was, now) > 0.05, "The pressed box moved with the palette")
    assert_eq(now, SaTheme.palette.toggle_on, "onto the new palette's accent")
    button.free()


## The door sets all five states and writes `flat` off, because a flat button
## draws no stylebox at all and every box would be set and never seen. That is
## the layer row's three locks, which were built flat.
func test_the_door_sets_every_state_and_unflattens() -> void:
    var button := Button.new()
    button.toggle_mode = true
    button.flat = true
    SaTheme.make_toggle(button)

    assert_false(button.flat, "A flat button draws no box, so the door unflattens it")
    for state: String in SaTheme.TOGGLE_STATES:
        assert_true(button.has_theme_stylebox_override(state), "the '%s' box is the palette's" % state)
    button.free()


## The tool options bar's own toggles walk through it, which is the surface the
## note was written about.
func test_the_tool_options_toggles_carry_the_box() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var registries := Fixtures.make_registries(surface)
    var bar := ToolOptionsBar.new()
    bar.target_tool_machine = machine
    bar._ready()
    bar.bind_registries(registries.blend_modes)
    machine.set_active_tool(&"brush")

    var erase := bar.control_for(&"eraser_toggled") as Button
    assert_not_null(erase, "The brush declares Erase")
    assert_true(erase.toggle_mode, "as a toggle")
    assert_true(erase.has_theme_stylebox_override("pressed"), "carrying a pressed box of its own")
    assert_false(erase.flat, "and not flat, or it would draw none")
    bar.free()
    Fixtures.teardown(surface, machine)


## The report the dump reads: a toggle is listed with whether it is down and
## whether it is styled, and a row of a list is left out by name rather than by
## guess.
func test_the_report_lists_a_toggle_and_leaves_a_list_row_out() -> void:
    var window := Window.new()
    var button := Button.new()
    button.name = "PlainToggle"
    button.toggle_mode = true
    button.button_pressed = true
    SaTheme.make_toggle(button)
    window.add_child(button)

    var bare := Button.new()
    bare.name = "BareToggle"
    bare.toggle_mode = true
    window.add_child(bare)

    var list := SaChoicePopup.new()
    list.one_of = true
    list.add_row(&"first", "First")
    window.add_child(list)

    var report := SaToggleReport.of(window)
    var names: Array = []
    for row: Dictionary in report:
        names.append(String(row["name"]))
    assert_true(names.has("PlainToggle"), "The toggle is in the report")
    assert_true(names.has("BareToggle"), "and so is one nobody styled")
    assert_false(names.has("Label"), "A row of a list is not a toggle button")

    for row: Dictionary in report:
        if String(row["name"]) == "PlainToggle":
            assert_true(bool(row["styled"]), "The styled one says so")
            assert_true(bool(row["pressed"]), "and that it is down")
        if String(row["name"]) == "BareToggle":
            assert_false(bool(row["styled"]), "and the bare one says it is not styled")
    window.free()
