## The palette says what a push button and a toggle look like in each state.
##
## A painter can set the Push Button toggled, hovered and not-toggled colours
## because they exist as fields of the palette.
## the page hid nothing because the colours did not exist. What is held here is
## the shape of the answer: a state is a field of the palette, it derives from a
## ramp until the painter sets it, a set state stays set through a base moving
## and through its own file, and a palette nobody set draws exactly the boxes it
## drew before the fields existed.
extends "res://tests/test_framework.gd"

## What each toggle box read by name before the state fields existed, ground then rim, copied from
## `SaTheme.make_toggle_style`. The record of "before", so it is
## written out rather than read from the table it is checking.
const TOGGLE_BEFORE := {
    "normal": ["bg_input", "border_secondary"],
    "hover": ["bg_slider", "border_hover"],
    "pressed": ["accent_primary", "border_selected"],
    "focus": ["bg_input", "border_selected"],
    "disabled": ["bg_primary", "border_secondary"],
}

## What a push button's ground read by name before the state fields, from
## `SaThemeDefaults.BOX_COLORS`.
const BUTTON_BEFORE := {
    "normal": "bg_panel",
    "hover": "bg_slider",
    "pressed": "bg_secondary",
    "disabled": "bg_primary",
}

## The states a shipped palette holds, by id, and every other one holds none.
## Pink is a painter's own palette as the Colour Themes page saved it,
## so the three states set on it ship set.
const HELD := {"pink": ["toggle_off", "slider_handle", "slider_hover"]}


## The field a box reads by name before its family existed, unless the palette
## holds the state field it reads now or `SaPalette` moves it by a rule (a hover
## steps away from its rest, a pressed sits under its hover, an accent carries
## text), in which case that field is the answer. `test_state_rules_hold_in_every_palette`
## holds the rules themselves.
static func _read(palette: SaPalette, before: String, field: String) -> String:
    if palette.overridden_states.has(field) or _moved_by_rule(field):
        return field
    return before


static func _moved_by_rule(field: String) -> bool:
    return SaPalette.HOVER_FROM.has(field) or SaPalette.PRESSED_UNDER.has(field) or SaPalette.TEXT_GROUNDS.has(field)


## The five dropdown-like families, under the family key the strip heads the row
## with, and the table `SaPalette` holds for each. A function rather than a
## `const`, because a const whose initializer names a global `class_name` breaks
## the class cache.
static func _family_tables() -> Dictionary:
    return {
        "dropdown": SaPalette.DROPDOWN_BOXES,
        "slider": SaPalette.SLIDER_BOXES,
        "scrollbar": SaPalette.SCROLLBAR_BOXES,
        "tab": SaPalette.TAB_BOXES,
        "menu_row": SaPalette.MENU_ROW_BOXES,
        "text_field": SaPalette.FIELD_BOXES,
    }


## What a dropdown's box read by name before its family existed, ground then rim, copied from
## the `match` `SaTheme.make_dropdown_style` ran. The record of "before",
## so it is written out rather than read from the table it is checking.
const DROPDOWN_BEFORE := {
    "normal": ["bg_input", "border_primary"],
    "hover": ["bg_slider", "border_hover"],
    "pressed": ["bg_secondary", "border_selected"],
    "focus": ["bg_input", "border_selected"],
    "disabled": ["bg_primary", "border_secondary"],
}

## What `SaThemeDefaults._box` grounded a field on before the family states, and the rim it
## took from `BOX_COLORS`. The focus state has no ground, which is the pair Godot
## draws over the state box rather than instead of it.
const FIELD_BEFORE := {
    "normal": ["bg_input", "border_primary"],
    "read_only": ["bg_secondary", "border_secondary"],
    "focus": ["", "border_selected"],
}

var _saved_theme: String = "default"
var _saved_path: String = ""
var _saved_shared: Theme = null


func before_each() -> void:
    _saved_theme = SaTheme.palette_id
    _saved_path = SaSettings.settings_path
    _saved_shared = SaUI.shared_theme
    SaSettings.settings_path = ProjectSettings.globalize_path(SaDataRoot.path("test_control_states.cfg"))
    _remove_forks()


func after_each() -> void:
    _remove_forks()
    SaSettings.settings_path = _saved_path
    SaTheme.use_named(_saved_theme)
    SaUI.shared_theme = _saved_shared
    DirAccess.remove_absolute(ProjectSettings.globalize_path(SaDataRoot.path("test_control_states.cfg")))


## Every fork this suite makes, and the copies `delete_custom` keeps of them.
## The page's own fork is named after the shipped palette, so its stem is swept
## as well.
func _remove_forks() -> void:
    for id in SaTheme.custom_ids():
        if id.begins_with(SaTheme.CUSTOM_PREFIX + "test-g6") or id == SaTheme.CUSTOM_PREFIX + "sara-green-(custom)":
            SaTheme.delete_custom(id)
    var kept := DirAccess.open(SaTheme.deleted_dir())
    if kept == null:
        return
    for file_name in kept.get_files():
        if file_name.begins_with("test-g6") or file_name.begins_with("sara-green-(custom)"):
            kept.remove(file_name)


## The whole of "the shipped look does not move", over every shipped palette:
## every toggle box and every push button box grounds and rims where it did
## before, but for a state the palette holds, which grounds on its own field.
func test_a_palette_with_nothing_set_draws_what_it_drew_before() -> void:
    for id: String in SaTheme.PALETTES:
        SaTheme.use_named(id)
        SaUI.init_global_theme(null)
        var theme := SaUI.shared_theme
        var held: Array = HELD.get(id, [])
        assert_eq(Array(SaTheme.palette.overridden_states), held, "%s: a shipped palette sets only its own states" % id)
        for state: String in TOGGLE_BEFORE:
            var box := SaTheme.make_toggle_style(state)
            var before: Array = TOGGLE_BEFORE[state]
            var ground := _read(SaTheme.palette, before[0], SaPalette.TOGGLE_BOXES[state]["bg_color"])
            assert_eq(box.bg_color, SaTheme.palette.get(ground), "%s: a toggle's %s ground is %s" % [id, state, ground])
            assert_eq(box.border_color, SaTheme.palette.get(before[1]), "%s: and its rim %s" % [id, before[1]])
        for state: String in BUTTON_BEFORE:
            var flat := theme.get_stylebox(state, "Button") as StyleBoxFlat
            var base := _read(SaTheme.palette, String(BUTTON_BEFORE[state]), SaPalette.BUTTON_GROUNDS[state])
            assert_not_null(flat, "%s: the theme holds a push button %s box" % [id, state])
            if flat != null:
                assert_eq(flat.bg_color, SaTheme.palette.get(base), "%s: grounded on %s" % [id, base])


## A spin box is a text field and two small buttons, and
## every part follows the palette. Every colour is a push
## button's own text colour, every filled box grounds on the push button's own
## state, and the four boxes Godot never fills stay `StyleBoxEmpty`.
func test_a_spin_boxs_arrows_read_the_push_buttons_states() -> void:
    var icon_states := [
        "up_icon_modulate",
        "up_hover_icon_modulate",
        "up_pressed_icon_modulate",
        "down_icon_modulate",
        "down_hover_icon_modulate",
        "down_pressed_icon_modulate",
    ]
    var disabled_icon_states := ["up_disabled_icon_modulate", "down_disabled_icon_modulate"]
    var filled_boxes := {
        "up_background_hovered": "hover",
        "down_background_hovered": "hover",
        "up_background_pressed": "pressed",
        "down_background_pressed": "pressed",
    }
    var empty_boxes := ["up_background", "up_background_disabled", "down_background", "down_background_disabled"]
    for id: String in SaTheme.PALETTES:
        SaTheme.use_named(id)
        SaUI.init_global_theme(null)
        var theme := SaUI.shared_theme
        for color_name: String in icon_states:
            assert_eq(
                theme.get_color(color_name, "SpinBox"),
                SaTheme.palette.text_primary,
                "%s: a spin box's %s is the same text a button reads" % [id, color_name]
            )
        for color_name: String in disabled_icon_states:
            assert_eq(
                theme.get_color(color_name, "SpinBox"),
                SaTheme.palette.text_muted,
                "%s: and a disabled arrow's %s is a button's disabled text" % [id, color_name]
            )
        for box_name: String in filled_boxes:
            var flat := theme.get_stylebox(box_name, "SpinBox") as StyleBoxFlat
            var ground := String(SaPalette.BUTTON_GROUNDS[filled_boxes[box_name]])
            assert_not_null(flat, "%s: the theme holds a spin box's %s box" % [id, box_name])
            if flat != null:
                assert_eq(flat.bg_color, SaTheme.palette.get(ground), "%s: grounded on %s" % [id, ground])
        for box_name: String in empty_boxes:
            assert_false(theme.has_stylebox(box_name, "SpinBox"), "%s: %s stays the engine's own StyleBoxEmpty" % [id, box_name])


## The tables name real fields, every field has a base, and the defaults a
## script gets agree with the bases before anything derives them.
func test_every_state_is_a_palette_colour_that_starts_at_its_base() -> void:
    var fresh := SaPalette.new()
    var keys := SaTheme.color_keys(fresh)
    for key: String in SaPalette.STATE_BASES:
        assert_true(keys.has(key), "%s is a colour field, so the Colour Themes page shows it" % key)
        assert_eq(fresh.get(key), fresh.get(String(SaPalette.STATE_BASES[key])), "%s starts at its base" % key)
    for state: String in SaPalette.BUTTON_GROUNDS:
        assert_true(SaPalette.STATE_BASES.has(SaPalette.BUTTON_GROUNDS[state]), "the button's %s ground is a state" % state)
    for state: String in SaPalette.TOGGLE_BOXES:
        var ground := String(SaPalette.TOGGLE_BOXES[state]["bg_color"])
        assert_true(SaPalette.STATE_BASES.has(ground), "the toggle's %s ground is a state" % state)
    for state: String in SaTheme.TOGGLE_STATES:
        assert_true(SaPalette.TOGGLE_BOXES.has(state), "every state the toggle door sets has a box: %s" % state)


## Every state of the five families is a colour field with a base that is itself a colour,
## and every door's own state list has a box in the family's table.
func test_every_family_names_state_fields_with_a_real_base() -> void:
    var fresh := SaPalette.new()
    var keys := SaTheme.color_keys(fresh)
    var families := _family_tables()
    for family: String in families:
        var table: Dictionary = families[family]
        for state: String in table:
            var box: Dictionary = table[state]
            if not box.has("bg_color"):
                continue
            var field := String(box["bg_color"])
            assert_true(SaPalette.STATE_BASES.has(field), "%s's %s names a state: %s" % [family, state, field])
            var base := String(SaPalette.STATE_BASES[field])
            assert_true(keys.has(base), "%s's %s derives from a colour: %s" % [family, state, base])
            assert_eq(fresh.get(field), fresh.get(base), "%s's %s starts at %s" % [family, state, base])
    for state: String in SaTheme.DROPDOWN_STATES:
        assert_true(SaPalette.DROPDOWN_BOXES.has(state), "every state the dropdown door sets has a box: %s" % state)
    for state: String in SaTheme.TAB_STATES:
        assert_true(SaPalette.TAB_BOXES.has(state), "every state a tab is drawn in has a box: %s" % state)
    for state: String in SaTheme.MENU_ROW_STATES:
        assert_true(SaPalette.MENU_ROW_BOXES.has(state), "every state a menu row is drawn in has a box: %s" % state)
    for part: String in SaTheme.SLIDER_PARTS:
        assert_true(SaPalette.SLIDER_BOXES.has(part), "every part a slider draws has a box: %s" % part)
    for cls: String in SaThemeDefaults.TAB_CLASSES:
        for state: String in SaThemeDefaults.BOXES[cls]["states"]:
            assert_true(SaPalette.TAB_BOXES.has(state), "the shared theme sets a tab's %s box from the table" % state)
    for cls: String in SaThemeDefaults.SCROLLBAR_CLASSES:
        var scrollbar: Dictionary = SaThemeDefaults.SCROLLBAR_CLASSES[cls]
        for box_name: String in scrollbar["parts"]:
            var part := String(scrollbar["parts"][box_name])
            assert_true(SaPalette.SCROLLBAR_BOXES.has(part), "%s's %s reads a box the table holds: %s" % [cls, box_name, part])


## The five families draw exactly what they drew before the state fields, on every
## shipped palette. The dropdown's match and the field's class special case are
## the two that had literals, and the strip is where the other three are seen.
func test_the_new_families_draw_what_they_drew_before() -> void:
    for id: String in SaTheme.PALETTES:
        SaTheme.use_named(id)
        SaUI.init_global_theme(null)
        var palette := SaTheme.palette
        for state: String in DROPDOWN_BEFORE:
            var box := SaTheme.make_dropdown_style(state)
            var before: Array = DROPDOWN_BEFORE[state]
            var ground := _read(palette, before[0], SaPalette.DROPDOWN_BOXES[state]["bg_color"])
            assert_eq(box.bg_color, palette.get(ground), "%s: a dropdown's %s ground is %s" % [id, state, ground])
            assert_eq(box.border_color, palette.get(before[1]), "%s: and its rim %s" % [id, before[1]])
        for state: String in FIELD_BEFORE:
            var flat := SaThemeDefaults.make_field_style(state)
            var before: Array = FIELD_BEFORE[state]
            assert_eq(flat.border_color, palette.get(before[1]), "%s: a text field's %s rim is %s" % [id, state, before[1]])
            if String(before[0]).is_empty():
                assert_eq(flat.bg_color.a, 0.0, "%s: a focused field has no ground to fill" % id)
            else:
                assert_eq(flat.bg_color, palette.get(before[0]), "%s: its ground is %s" % [id, before[0]])
        # The track is its ramp moved until the fill stands 3 to 1 on it, which on
        # every palette but Pink is the ramp as it was.
        assert_eq(SaTheme.make_slider_style("track").bg_color, palette.slider_track, "%s: a slider's track" % id)
        # The gauge rather than the orange fill, the one family that was meant to move.
        var handle := _read(palette, "accent_gauge", "slider_handle")
        assert_eq(SaTheme.make_slider_style("handle").bg_color, palette.get(handle), "%s: and its handle is %s" % [id, handle])
        var field := SaUI.shared_theme.get_stylebox("normal", "LineEdit") as StyleBoxFlat
        assert_not_null(field, "%s: the theme holds a text field's box" % id)
        if field != null:
            assert_eq(field.bg_color, palette.get("bg_input"), "%s: the field the interface draws is the same" % id)
        var menu := SaUI.shared_theme.get_stylebox("hover", "PopupMenu") as StyleBoxFlat
        assert_not_null(menu, "%s: the theme holds a menu row's hover box" % id)
        if menu != null:
            assert_eq(menu.bg_color, palette.menu_hover, "%s: and a menu's highlighted row is the family's" % id)


## Derived until set: a moved base carries a state nobody set, and leaves one
## the painter set where they set it.
func test_a_set_state_holds_and_the_others_follow_their_base() -> void:
    SaTheme.use_named("default")
    SaSettings.theme_name = SaTheme.fork("Test G6 Holds")
    var off_before := SaTheme.make_toggle_style("normal").bg_color
    var hover_before := SaTheme.make_toggle_style("hover").bg_color
    var blue := Color("#2F6FD0")

    assert_true(SaTheme.set_color("toggle_on", blue), "A state is a colour a swatch can write")
    assert_eq(SaTheme.make_toggle_style("pressed").bg_color, blue, "The pressed toggle draws it")
    assert_eq(SaTheme.make_toggle_style("normal").bg_color, off_before, "and the toggle that is off does not move")
    assert_eq(SaTheme.make_toggle_style("hover").bg_color, hover_before, "nor the hovered one")
    assert_true(SaTheme.palette.overridden_states.has("toggle_on"), "The palette records that it was set")

    SaTheme.set_color("accent_primary", Color("#C03030"))
    assert_eq(SaTheme.palette.toggle_on, blue, "A set state stays set when its base moves")

    SaTheme.set_color("bg_primary", Color("#403050"))
    assert_eq(SaTheme.palette.toggle_off, SaTheme.palette.bg_input, "A state nobody set follows its base through a slide")
    assert_true(SaTheme.palette.toggle_off != off_before, "and the slide did move it")


func test_a_set_state_comes_back_off_its_file() -> void:
    SaTheme.use_named("default")
    var id := SaTheme.fork("Test G6 File")
    var green := Color("#30A050")
    SaTheme.set_color("button_hover", green)
    SaTheme.use_named("default")
    assert_true(SaTheme.palette.button_hover != green, "The shipped palette is not the fork")
    SaTheme.use_named(id)
    assert_true(SaTheme.palette.button_hover.is_equal_approx(green), "The set state came back off disk")
    assert_true(SaTheme.palette.overridden_states.has("button_hover"), "still held")
    assert_eq(SaTheme.palette.button_normal, SaTheme.palette.bg_panel, "and its neighbour still derives")


## The page, the theme and the strip read one field: a swatch set on the page is
## the ground of the push button box every unstyled button resolves, and of the
## strip's sample, in place.
func test_the_page_the_theme_and_the_strip_read_one_field() -> void:
    SaTheme.use_named("default")
    SaUI.init_global_theme(null)
    var hover_box := SaUI.shared_theme.get_stylebox("hover", "Button") as StyleBoxFlat
    var strip := SaControlStatesStrip.new()
    var page := SaColorThemesPage.new()
    var red := Color("#B03A3A")

    page.set_swatch("button_hover", red)
    assert_true(SaTheme.is_custom(SaTheme.palette_id), "Setting a state on a shipped palette forks it first")
    assert_eq(hover_box.bg_color, red, "The theme's push button hover box was rewritten in place")
    var found: Dictionary = strip.report()
    assert_eq(String(found["button"]["hover"]["hex"]), red.to_html(), "and the strip's sample draws it")
    assert_true(bool(found["button"]["hover"]["held"]), "and says it is held")
    assert_false(bool(found["button"]["normal"]["held"]), "while its neighbour is not")
    assert_eq(String(found["toggle"]["pressed"]["field"]), "toggle_on", "The strip names the field each ground reads")

    page._on_delete_answered(SaColorThemesPage.DELETE_CONFIRM, SaTheme.palette_id)
    page.free()
    strip.free()


## The strip carries all seven families, each state names the field it draws,
## and only the focused field has none to name.
func test_the_strip_carries_every_family() -> void:
    SaTheme.use_named("default")
    SaUI.init_global_theme(null)
    var strip := SaControlStatesStrip.new()
    var found: Dictionary = strip.report()
    for family: String in SaControlStatesStrip.FAMILIES:
        assert_true(found.has(family), "the strip draws %s" % family)
        var states: Dictionary = found[family]
        for state: String in SaControlStatesStrip.FAMILIES[family]:
            assert_true(states.has(state), "and its %s state" % state)
            var field := String((states[state] as Dictionary)["field"])
            if family == "text_field" and state == "focus":
                assert_true(field.is_empty(), "a focused field has no ground to name")
            else:
                assert_true(SaPalette.STATE_BASES.has(field), "%s's %s names a state field: %s" % [family, state, field])
    strip.free()


## A row of a list reads its own family's fields, so a colour set on the page
## reaches the popup rather than only the strip.
func test_a_menu_rows_box_follows_its_own_field() -> void:
    SaTheme.use_named("default")
    SaSettings.theme_name = SaTheme.fork("Test G6 Menu Row")
    SaUI.init_global_theme(null)
    var row := SaChoiceRow.new(&"probe", "Probe")
    var button := row.label_button()
    assert_not_null(button, "a row carries a label button")
    var hover := button.get_theme_stylebox("hover") as StyleBoxFlat
    assert_not_null(hover, "and it draws a box of its own rather than the engine's")
    if hover != null:
        assert_eq(hover.bg_color, SaTheme.palette.menu_hover, "a row's hover is the menu row family's field")
    var chosen := button.get_theme_stylebox("pressed") as StyleBoxFlat
    assert_not_null(chosen, "so is its chosen state")
    if chosen != null:
        assert_eq(chosen.bg_color, SaTheme.palette.bg_secondary, "grounded on the button ramp it drew before")
    var blue := Color("#2F6FD0")
    assert_true(SaTheme.set_color("menu_hover", blue), "A menu row's hover is a colour a swatch can write")
    if hover != null:
        assert_eq(hover.bg_color, blue, "and the popup's row draws the painter's colour")
    assert_eq(SaTheme.make_menu_row_style("checked").bg_color, SaTheme.palette.bg_secondary, "the chosen state holds")
    row.free()
