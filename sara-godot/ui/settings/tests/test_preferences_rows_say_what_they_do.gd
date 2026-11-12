## Preferences rows say what they do: eight small faults a first
## reader tripped on, one test each, reading the row's text, control or style.
extends "res://tests/test_framework.gd"

const PINNED_ONLY := "PinnedOnly"
const DRAG_NOTE := "Drag a row anywhere to reorder it, or switch it off to hide it."

var _pressure: float = 0.0


func before_each() -> void:
    _pressure = SaSettings.tablet_max_pressure


func after_each() -> void:
    SaSettings.tablet_max_pressure = _pressure
    SaSettings.unregister_layout_category(PINNED_ONLY)


## Whether *page* declares the note about dragging.
static func _offers_drag(page: SaSettingsPage) -> bool:
    for row in page.page.rows():
        if row.kind == SaPageRow.Kind.NOTE and row.explanation == DRAG_NOTE:
            return true
    return false


## F16. Nine docker pages list only Drag Handle and Resizer, and neither moves.
func test_a_page_with_nothing_to_drag_says_nothing_about_a_drag() -> void:
    assert_true(SaSettings.register_layout_category(PINNED_ONLY, "Pinned only", ["Drag Handle", "Resizer"]), "Registered")
    var pinned := SaLayoutPage.new(PINNED_ONLY)
    assert_false(pinned.has_draggable_row(), "The pinned pair cannot be picked up")
    assert_false(_offers_drag(pinned), "so the page does not offer a drag")
    pinned.free()
    var picker := SaLayoutPage.new("ColorPicker")
    assert_true(picker.has_draggable_row(), "The picker's rows can be picked up")
    assert_true(_offers_drag(picker), "and its page still says how")
    picker.free()


## The cap is whole megabytes.
func test_the_timelapse_cap_reads_whole_megabytes() -> void:
    var page := SaRecorderPage.new()
    var cap := page.page.row(&"cap")
    assert_eq(cap.decimal_places, 0, "The cap shows no decimals")
    var shown := "%.*f" % [cap.decimal_places, cap.shown_value(1024.0 * 1048576.0)]
    assert_eq(shown, "1024", "and 1024 MB reads 1024")
    page.free()


## The folder is chosen the way General's is.
func test_the_timelapse_folder_has_a_choose_button() -> void:
    var page := SaRecorderPage.new()
    assert_eq(page.page.row(&"folder").kind, SaPageRow.Kind.PATH, "The folder is a path row")
    assert_not_null(page.find_child("ChooseButton", true, false), "with its Choose button")
    page.free()


## The title says what the number is, so the header carries the number.
func test_the_pressure_header_is_the_number_alone() -> void:
    SaSettings.tablet_max_pressure = 0.75
    var calibration := SaTabletCalibration.new()
    calibration.refresh()
    var header := calibration.find_child("MaximumLabel", true, false) as Label
    assert_eq(header.text, "0.75", "The header shows the reading and not the title again")
    calibration.free()


## The Disabled sample reads in the grey a disabled button has.
func test_the_disabled_sample_is_drawn_disabled() -> void:
    var page := SaColorThemesPage.new()
    var found := 0
    for node in page.find_children("*Sample", "Button", true, false):
        var sample := node as Button
        var is_disabled_state := String(sample.name).ends_with("DisabledSample")
        assert_eq(sample.disabled, is_disabled_state, "%s is drawn disabled only when it is the Disabled state" % sample.name)
        if is_disabled_state:
            found += 1
    assert_true(found > 0, "The page has a Disabled sample")
    page.free()


## F32. Advanced options is a switch like its neighbours.
func test_advanced_options_is_a_switch() -> void:
    var page := SaGeneralPage.new()
    var control := page.find_child("AdvancedOptionsCheck", true, false)
    assert_true(control is CheckButton, "A switch and not a check box")
    assert_false(control is CheckBox, "and not a check box")
    page.free()


## Nothing imported is a hint, not a row title.
func test_nothing_imported_is_a_hint() -> void:
    var page := SaBrushPresetsPage.new()
    var empty := page.find_child("PresetsImportEmpty", true, false) as Label
    var summary := page.find_child("PresetsImportSummary", true, false) as Label
    assert_true(empty.visible, "The empty line shows")
    assert_false(summary.visible, "and the bold summary does not")
    assert_false(empty.has_theme_font_override("font"), "The empty line is not in the bold face")
    assert_true(empty.has_theme_font_size_override("font_size"), "and is in the hint's smaller size")
    page.free()


## The locked Edit switch says why.
func test_the_locked_edit_switch_says_why() -> void:
    var page := SaLayoutPage.new("TopMenuBar")
    var edit: SaLayoutPage.DragRow = null
    for node in page.find_children("*", "PanelContainer", true, false):
        var row := node as SaLayoutPage.DragRow
        if row != null and row.element_name == "Edit":
            edit = row
    assert_not_null(edit, "The top bar page lists Edit")
    assert_true(edit.check_button.disabled, "Its switch is locked")
    assert_true(edit.check_button.tooltip_text.contains("Preferences"), "and says Edit holds Preferences")
    page.free()
