## The Colour Themes page groups by control.
##
## The page's sections are named for their controls and not for ramps, so a
## painter looking for the toggle's pressed colour finds the toggle.
## What is held here: every state field of the palette reaches a row of its own
## under its control, the controls come before the ramps, a state is spelled out,
## and the sample beside a swatch is the box the interface draws, moving with the
## swatch while nothing beside it does.
extends "res://tests/test_framework.gd"

var _saved_theme: String = "default"
var _saved_path: String = ""
var _saved_shared: Theme = null


func before_each() -> void:
    _saved_theme = SaTheme.palette_id
    _saved_path = SaSettings.settings_path
    _saved_shared = SaUI.shared_theme
    SaSettings.settings_path = ProjectSettings.globalize_path(SaDataRoot.path("test_colour_themes_by_control.cfg"))
    _remove_forks()


func after_each() -> void:
    _remove_forks()
    SaSettings.settings_path = _saved_path
    SaTheme.use_named(_saved_theme)
    SaUI.shared_theme = _saved_shared
    DirAccess.remove_absolute(ProjectSettings.globalize_path(SaDataRoot.path("test_colour_themes_by_control.cfg")))


## The page's own fork is named after the shipped palette, so its stem is swept,
## and so are the copies `delete_custom` keeps.
func _remove_forks() -> void:
    for id in SaTheme.custom_ids():
        if id == SaTheme.CUSTOM_PREFIX + "sara-green-(custom)":
            SaTheme.delete_custom(id)
    var kept := DirAccess.open(SaTheme.deleted_dir())
    if kept == null:
        return
    for file_name in kept.get_files():
        if file_name.begins_with("sara-green-(custom)"):
            kept.remove(file_name)


func _built() -> SaColorThemesPage:
    SaTheme.use_named("default")
    SaUI.init_global_theme(null)
    return SaColorThemesPage.new()


func _row_of(page: SaColorThemesPage, key: String) -> Dictionary:
    for row: Dictionary in page._rows:
        if (row["keys"] as Array).has(key):
            return row
    return {}


## The box a family's own door makes for *state*, which is what the page's
## sample has to be. The two oldest families are asked by name in the test
## itself, and these five through here.
static func _door_box(family: String, state: String) -> StyleBox:
    match family:
        "switch":
            return SaUI.shared_theme.get_stylebox(state, "CheckButton")
        "dropdown":
            return SaTheme.make_dropdown_style(state)
        "slider":
            return SaTheme.make_slider_style(state)
        "scrollbar":
            return SaThemeDefaults.make_scrollbar_style(state)
        "tab":
            return SaTheme.make_tab_style(state)
        "menu_row":
            return SaTheme.make_menu_row_style(state)
        "text_field":
            return SaThemeDefaults.make_field_style(state)
    return null


## A state field added to the palette later cannot go
## missing from the page, because every one of them is asked for by name.
func test_every_state_field_of_the_palette_reaches_a_row() -> void:
    var page := _built()
    var state_rows := 0
    for row: Dictionary in page._rows:
        if row.has("state"):
            state_rows += 1
    assert_eq(state_rows, SaPalette.STATE_BASES.size(), "A row per state field, and no more")
    for key: String in SaPalette.STATE_BASES:
        var row := _row_of(page, key)
        assert_false(row.is_empty(), "%s has a row" % key)
        assert_eq(row.get("keys", []), [key], "%s has the row to itself" % key)
        assert_true(page._swatches.has(key), "%s has a swatch" % key)
        assert_true(page._samples.has(key), "%s has a sample of the box it grounds" % key)
    page.free()


func test_the_controls_come_before_the_ramps() -> void:
    var page := _built()
    assert_true(page._rows[0].has("state"), "The first row of the page is a control's")
    var ramps_started := false
    var control_sections: Array[String] = []
    for row: Dictionary in page._rows:
        if row.has("state"):
            assert_false(ramps_started, "%s is not under a ramp" % row["keys"][0])
            if not control_sections.has(String(row["section"])):
                control_sections.append(String(row["section"]))
        else:
            ramps_started = true
            assert_false(control_sections.has(String(row["section"])), "%s is in no control's section" % row["title"])
    assert_eq(
        control_sections,
        (
            [
                "Push button",
                "Toggle button",
                "Switch",
                "Dropdown",
                "Slider",
                "Scroll bar",
                "Tab",
                "Menu row",
                "Text field",
                "Hover rim",
                "Title bar"
            ]
            as Array[String]
        ),
        "The palette's control families, in the order it declares them"
    )
    assert_true(ramps_started, "and the ramps are still on the page under them")
    page.free()


## The row says the state, and the field's own name stays
## in the text a Preferences search reads.
func test_a_state_is_spelled_out_and_still_found_by_its_field_name() -> void:
    var page := _built()
    assert_eq(String(_row_of(page, "toggle_on")["title"]), "On", "toggle_on is On")
    assert_eq(String(_row_of(page, "toggle_off")["title"]), "Off", "toggle_off is Off")
    assert_eq(String(_row_of(page, "toggle_hover")["title"]), "Hovered", "toggle_hover is Hovered")
    assert_eq(String(_row_of(page, "button_pressed")["title"]), "Pressed", "button_pressed is Pressed")
    assert_eq(SaColorThemesPage._state_word("button_disabled"), "disabled", "The word is the name after the control's")
    var found := false
    for node in page.find_children("*", "HBoxContainer", true, false):
        var line := node as Control
        if line.has_meta(SaSettingsRows.ROW_META) and SaSettingsSearch.row_haystack(line).contains("toggle disabled"):
            found = true
    assert_true(found, "A search for Toggle Disabled still lands on a row")
    page.free()


## "drawn through the same public call that makes its stylebox": a push button's
## sample holds the shared theme's own box object, and a toggle's is the box the
## toggle door makes.
func test_the_sample_is_the_box_the_interface_draws() -> void:
    var page := _built()
    for state: String in SaPalette.BUTTON_GROUNDS:
        var sample := page._samples[SaPalette.BUTTON_GROUNDS[state]] as Button
        var theirs := SaUI.shared_theme.get_stylebox(state, "Button")
        assert_true(sample.get_theme_stylebox("normal") == theirs, "The %s sample is the theme's own box" % state)
    for state: String in ["normal", "hover", "pressed", "disabled"]:
        var field := String(SaPalette.TOGGLE_BOXES[state]["bg_color"])
        var box := (page._samples[field] as Button).get_theme_stylebox("normal") as StyleBoxFlat
        var door := SaTheme.make_toggle_style(state)
        assert_eq(box.bg_color, door.bg_color, "The toggle's %s sample grounds as the door does" % state)
        assert_eq(box.border_color, door.border_color, "and rims as it does")
    for entry: Array in SaColorThemesPage._box_tables():
        var family := String(entry[0])
        var table: Dictionary = entry[1]
        for state: String in table:
            var state_field := String((table[state] as Dictionary).get("bg_color", ""))
            if state_field.is_empty():
                continue
            var their_box := (page._samples[state_field] as Button).get_theme_stylebox("normal") as StyleBoxFlat
            var their_door := _door_box(family, state) as StyleBoxFlat
            assert_not_null(their_door, "%s's %s has a door" % [family, state])
            assert_eq(their_box.bg_color, their_door.bg_color, "The %s's %s sample grounds as the door does" % [family, state])
            if (table[state] as Dictionary).has("border_color"):
                assert_eq(their_box.border_color, their_door.border_color, "and rims as it does")
    var preview := page.find_child("TogglePreview", true, false) as Button
    assert_not_null(preview, "The toggle section has a control to try")
    if preview != null:
        assert_true(preview.button_pressed, "switched on, so the colour asked about is showing")
        assert_true(preview.has_theme_stylebox_override("pressed"), "and made through the toggle door")
    assert_not_null(page.find_child("PushButtonPreview", true, false), "The push button section has one too")
    page.free()


## The scenario's claim as numbers: the swatch, the sample, the preview and a
## toggle elsewhere in the interface agree once the swatch is set, and nothing
## else on the page moved.
func test_a_state_set_on_the_page_moves_its_sample_and_nothing_beside_it() -> void:
    var page := _built()
    var elsewhere := Button.new()
    elsewhere.toggle_mode = true
    SaTheme.make_toggle(elsewhere)
    var before: Dictionary = {}
    for key: String in page._samples:
        before[key] = ((page._samples[key] as Button).get_theme_stylebox("normal") as StyleBoxFlat).bg_color
    var blue := Color("#2F6FD0")

    page.set_swatch("toggle_on", blue)
    assert_true(SaTheme.is_custom(SaTheme.palette_id), "A state set on a shipped palette forks it first")
    var preview := page.find_child("TogglePreview", true, false) as Button
    assert_eq((preview.get_theme_stylebox("pressed") as StyleBoxFlat).bg_color, blue, "The preview follows")
    assert_eq((elsewhere.get_theme_stylebox("pressed") as StyleBoxFlat).bg_color, blue, "and so does a toggle elsewhere")
    for key: String in page._samples:
        var now := ((page._samples[key] as Button).get_theme_stylebox("normal") as StyleBoxFlat).bg_color
        if key == "toggle_on":
            assert_eq(now, blue, "The On sample follows its swatch")
        else:
            assert_eq(now, before[key], "%s did not move" % key)
    for entry: Dictionary in page.theme_report():
        if entry.get("state", "") == "on":
            assert_eq(String(entry["colors"][0]["hex"]), blue.to_html(), "The dump's swatch is the colour set")
            assert_eq(String(entry["preview"]), blue.to_html(), "and its sample agrees")

    page._on_delete_answered(SaColorThemesPage.DELETE_CONFIRM, SaTheme.palette_id)
    elsewhere.free()
    page.free()
