## The Quick settings pane of the welcome window: the five rows
## it declares, the language among them, and the one setting each of them writes.
##
## The pane is built and never added to a tree, for the reason
## `test_welcome_window.gd` gives: a `Window` in a suite hangs the whole run,
## and the pane's host is one.
##
## **Out of the tree, writing `Range.value` delivers no `value_changed`**
## (an engine quirk), so every control here is driven the
## way `ui/settings/look/tests/test_display_page.gd` drives one: `set_value_no_signal` and then
## the signal a real drag delivers. A test that wrote the value alone would
## prove that Godot stores numbers.
extends "res://tests/test_framework.gd"

## The pane's own source, for the one claim a run of it cannot answer: that
## nothing in it writes the window scale by hand.
const PANE_SOURCE: String = "res://ui/welcome/quick_settings/quick_settings_pane.gd"

var _pane: WelcomeQuickSettingsPane = null
var _saved_scale: float = 1.0
var _saved_theme: String = ""
var _saved_pressure: float = 1.0
var _saved_embed: bool = true


func before_each() -> void:
    _saved_scale = SaSettings.ui_scale
    _saved_theme = SaSettings.theme_name
    _saved_pressure = SaSettings.tablet_max_pressure
    _saved_embed = SaSettings.embed_subwindows
    _pane = WelcomeQuickSettingsPane.new()


## Every one of the four is restored even when an assertion has already failed,
## because they are the running app's settings and not this suite's.
func after_each() -> void:
    SaSettings.ui_scale = _saved_scale
    SaSettings.theme_name = _saved_theme
    SaSettings.tablet_max_pressure = _saved_pressure
    SaSettings.embed_subwindows = _saved_embed
    if _pane != null:
        _pane.free()
        _pane = null


## Seven rows and no eighth: the language first, then the
## four in the order the release page names them, UI scale, the colour theme,
## the pressure calibration, the embedded subwindows switch, and last the
## display profile and the colour picker's shape.
##
## The count is the half that matters. A row added later without a setting behind
## it, or a control that drifted in beside one of the four, shows up here as a
## number rather than as a row nobody reads.
func test_the_pane_declares_seven_rows_in_order() -> void:
    var titles: Array[String] = []
    for node in _pane.find_children("*", "HBoxContainer", true, false):
        if node.has_meta(SaSettingsRows.ROW_META):
            titles.append(String(node.get_meta(SaSettingsRows.TITLE_META)))
    assert_eq(
        titles,
        [
            "I'm coming from",
            "Language",
            "UI scale",
            "Font size",
            "Colour theme",
            "Pen pressure",
            "Dockers inside the main window",
            "Display profile",
            "Colour picker",
        ],
        "the language, the four the release page lists in its order, then the display profile and the picker's shape"
    )


## The scale row is the Workspace page's control, name and all, so the same
## capture step can drive either one.
func test_the_scale_row_writes_the_ui_scale() -> void:
    assert_eq(_pane.scale_slider.name, "UiScaleSlider", "the same name the Workspace page's slider carries")
    SaSettings.ui_scale = 1.0
    _pane.scale_slider.set_value_no_signal(1.4)
    _pane.scale_slider.value_changed.emit(1.4)
    assert_almost_eq(SaSettings.ui_scale, 1.4, 0.0001, "the slider writes the one setting behind it")


## The theme row carries the palette's id and not a position in the list, which
## is what lets the handler write what it was handed.
func test_the_theme_row_writes_the_theme_name() -> void:
    var wanted := ""
    for entry: Dictionary in SaTheme.available():
        if String(entry["id"]) != SaSettings.theme_name:
            wanted = String(entry["id"])
            break
    assert_false(wanted.is_empty(), "a second palette exists to pick")
    _pane.theme_opt.choice_picked.emit(wanted)
    assert_eq(SaSettings.theme_name, wanted, "the button writes the palette it was handed")


## The row's control is `SaTabletCalibration` itself rather than a smaller copy
## of it, so its own slider is the writer and the strip above it is the strip.
func test_the_pressure_row_writes_the_tablet_maximum() -> void:
    var slider := _pane.calibration.find_child("MaxPressureSlider", true, false) as HSlider
    assert_not_null(slider, "the row carries the calibration's own slider")
    slider.set_value_no_signal(0.7)
    slider.value_changed.emit(0.7)
    assert_almost_eq(SaSettings.tablet_max_pressure, 0.7, 0.0001, "the calibration writes the ceiling behind it")


## The switch writes the setting the Workspace page's own switch writes, both
## ways, so the pane cannot turn it on and never off.
func test_the_embed_row_writes_the_embedded_subwindows_switch() -> void:
    SaSettings.embed_subwindows = true
    _pane.embed_check.set_pressed_no_signal(false)
    _pane.embed_check.toggled.emit(false)
    assert_false(SaSettings.embed_subwindows, "off is written")
    _pane.embed_check.set_pressed_no_signal(true)
    _pane.embed_check.toggled.emit(true)
    assert_true(SaSettings.embed_subwindows, "and on again")


## The pane is re-read when the window it lives in is shown again, which is what
## keeps a slider built once from disagreeing with the setting the Preferences
## page moved in between.
func test_the_pane_reads_the_settings_back_when_it_refreshes() -> void:
    SaSettings.ui_scale = 1.25
    SaSettings.embed_subwindows = false
    _pane.refresh()
    assert_almost_eq(_pane.scale_slider.value, 1.25, 0.0001, "the slider follows the setting")
    assert_false(_pane.embed_check.button_pressed, "and so does the switch")
    assert_eq(_pane.theme_opt.selected_value(), SaTheme.palette_id, "the button shows the palette the app is drawn with")


## The one-writer rule for UI scale read over the pane: the scale reaches `Window.content_scale_factor`
## through `SaUI.apply_to_window()` and nowhere else, so this file may not assign
## it. Comments are dropped first, because the doc comment above the class says
## in words that the pane does not.
func test_the_pane_never_writes_the_content_scale_factor() -> void:
    var code: Array[String] = []
    for line in _read_pane_source().split("\n"):
        if not line.strip_edges().begins_with("#"):
            code.append(line)
    var assignment := RegEx.create_from_string("content_scale_factor\\s*=[^=]")
    assert_null(assignment.search("\n".join(code)), "the pane writes SaSettings.ui_scale and never the window scale")


func _read_pane_source() -> String:
    var file := FileAccess.open(ProjectSettings.globalize_path(PANE_SOURCE), FileAccess.READ)
    if file == null:
        return ""
    return file.get_as_text()
