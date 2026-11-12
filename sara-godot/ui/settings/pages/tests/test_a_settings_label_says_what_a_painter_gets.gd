## A Preferences label says what a painter gets.
##
## The sweep read "Light mode", which elsewhere is a pale theme, "Both, to see
## the lag (debugging)" among a painter's pointer choices, "Auto (Left on
## macOS)" on Linux, a readout of pixels spent per row, three words in the Wider
## display list with nothing on them, swatch hints naming the palette's keys and
## "None" on a chord button. Each new text is read here off the page a painter
## opens, the readout's sentences off the function the live readout is written
## by, because no suite has a top bar to measure.
extends "res://tests/test_framework.gd"

const PERFORMANCE := [
    "painting_frame_rate", "half_size_view_while_moving", "thumbnails_while_painting", "history_depth", "light_mode_offer"
]

var _saved: Dictionary = {}


func before_each() -> void:
    _saved = {"advanced_options": SaSettings.advanced_options, "software_cursor": SaSettings.software_cursor}
    for property: String in PERFORMANCE:
        _saved[property] = SaSettings.get(property)
    SaSettingsPerformance.apply_defaults(SaSettings)


func after_each() -> void:
    for key: String in _saved:
        SaSettings.set(key, _saved[key])
    SaWeakGpu.forget()


# --- (a) the settings for a weak GPU ---------------------------------------------


func test_the_performance_section_and_its_button_name_a_weak_gpu() -> void:
    var page := SaPerformancePage.new()
    assert_eq(page.page.sections[0].title, "Settings for a weak GPU", "the section says what it holds")
    var button := page.find_child("LightModeButton", true, false) as Button
    assert_eq(button.text if button != null else "", "Apply", "and its button what a press does")
    page.press_light()
    var summary := page.find_child("PerformanceSummary", true, false) as Label
    assert_true(summary.text.begins_with("The settings for a weak GPU are in use:\n"), summary.text)
    page.press_light()
    assert_true(summary.text.begins_with("The settings for a weak GPU are already in use"), summary.text)
    for label: Label in page.find_children("*", "Label", true, false):
        assert_false(label.text.to_lower().contains("light mode"), "no line says light mode: %s" % label.text)
    page.free()


func test_the_offer_says_the_pages_words() -> void:
    SaWeakGpu.fake("integrated", 8 * 1024 * 1024 * 1024)
    SaSettings.light_mode_offer = ""
    var row := SaLightModeOffer.new()
    assert_true((row.get_node("Sentence") as Label).text.contains("settings for a weak GPU"), "the sentence names them")
    assert_eq((row.get_node("LightModeOfferOn") as Button).text, "Apply", "and its button is the page's")
    assert_false((row.get_node("LightModeOfferNotNow") as Button).tooltip_text.contains("light mode"), "as is the other")
    row.free()


# --- (c) Both under Advanced options ------------------------------------------------


func test_both_is_offered_only_under_advanced_options() -> void:
    SaSettings.software_cursor = "auto"
    SaSettings.advanced_options = false
    assert_false(_pointer_ids().has("both"), "Both is not a painter's choice with advanced options off")
    assert_eq(_pointer_ids(), ["auto", "always", "never"], "and the other three stay in their order")
    SaSettings.advanced_options = true
    assert_eq(_pointer_ids(), ["auto", "always", "never", "both"], "with them on it is offered last")


func test_a_profile_set_to_both_still_sees_it() -> void:
    SaSettings.advanced_options = false
    SaSettings.software_cursor = "both"
    assert_true(_pointer_ids().has("both"), "a row never opens on a choice it does not list")


func _pointer_ids() -> Array:
    var page := SaTabletPage.new()
    var option := page.find_child("SoftwarePointerMode", true, false) as SaChoiceButton
    var ids := option.choice_values() if option != null else []
    page.free()
    return ids


# --- (d) and (e) the Top Menu Bar page --------------------------------------------


func test_automatic_names_what_it_picks_on_this_computer() -> void:
    var page := SaDockersPage.new()
    var section := SaTopBarSection.new()
    assert_eq(section.automatic_position_label("Linux"), "Automatic (right on this computer)", "Linux puts them right")
    assert_eq(section.automatic_position_label("Windows"), "Automatic (right on this computer)", "so does Windows")
    assert_eq(section.automatic_position_label("macOS"), "Automatic (left on this computer)", "and macOS left")
    assert_eq(section.automatic_style_label("Linux"), "Automatic (icons on this computer)", "Linux draws icons")
    assert_eq(section.automatic_style_label("macOS"), "Automatic (traffic lights on this computer)", "macOS the lights")
    var position := page.find_child("WindowButtonPositionOpt", true, false) as SaChoiceButton
    var style := page.find_child("WindowButtonStyleOpt", true, false) as SaChoiceButton
    assert_eq(position.choice_labels()[0], section.automatic_position_label(OS.get_name()), "the row names the running one")
    assert_eq(style.choice_labels()[0], section.automatic_style_label(OS.get_name()), "and so does the style row")
    for option: SaChoiceButton in [position, style]:
        for label: String in option.choice_labels():
            assert_false(label.contains("Auto ("), "no entry reads Auto: %s" % label)
    page.free()


func test_the_readout_says_what_fits_and_holds_no_pixels() -> void:
    var was := SaSettings.second_row
    SaSettings.second_row = false
    var page := SaTopBarPage.new()
    var said: Array[String] = [
        page.fit_sentence(0, [], ""),
        page.fit_sentence(1, [], ""),
        page.fit_sentence(2, [], ""),
        page.fit_sentence(0, [2], ""),
        page.fit_sentence(0, [], page.forced_second_row_note(133.0)),
        (page.find_child("RowWidthReadout", true, false) as Label).text,
    ]
    assert_eq(said[0], "Everything fits on the top bar.", "nothing held and nothing scrolling")
    assert_eq(said[1], "1 control is in the overflow list, behind the button at the end of the bar.", "one held")
    assert_eq(said[2], "2 controls are in the overflow list, behind the button at the end of the bar.", "two held")
    assert_eq(said[3], "The second row does not fit, so it scrolls.", "a row that scrolls says so")
    assert_true(said[4].contains("133") and said[4].contains("second row stays"), said[4])
    for sentence: String in said:
        assert_false(sentence.contains("px"), "no px in: %s" % sentence)
    page.free()
    SaSettings.second_row = was


# --- (f) Wider display --------------------------------------------------------------


func test_each_wider_display_entry_says_what_it_does() -> void:
    var page := SaDisplayPage.new()
    var option := page.page.row(&"display_fill").control as SaChoiceButton
    assert_eq(option.choice_labels(), ["Converted", "Unconverted", "Even stretch"] as Array[String], "named for what each does")
    for fill_id: String in SaSettings.DISPLAY_FILLS:
        var row := option.popup.label_button(SaChoiceButton.row_id_of(fill_id))
        var tip := row.tooltip_text if row != null else ""
        assert_eq(tip, SaDisplayPage.FILL_SENTENCES[fill_id], "%s carries its sentence" % fill_id)
        assert_true(tip.length() > 40, "a sentence and not its word: %s" % tip)
    page.free()


# --- (g) the swatch hints ------------------------------------------------------------


func test_a_swatch_hint_names_its_base_by_the_name_on_the_page() -> void:
    var page := SaColorThemesPage.new()
    var hint := page.page.row(&"button_normal").explanation
    assert_true(hint.ends_with("Until you set it, it is the same as Panel background."), hint)
    var swatch := page.find_child("BgPanelSwatch", true, false) as ColorPickerButton
    assert_true(swatch != null and swatch.tooltip_text.begins_with("Panel background"), "the swatch goes by that name")
    var gauge := page.page.row(&"accent_gauge")
    assert_eq(gauge.label if gauge != null else "", "Gauge accent", "and a lone row is titled the same way")
    for key: String in SaPalette.STATE_BASES:
        var row := page.page.row(StringName(key))
        if row == null:
            continue
        assert_false(row.explanation.contains("follows Bg"), "no hint names a key: %s" % row.explanation)
        var base := SaColorThemesPage.swatch_title(String(SaPalette.STATE_BASES[key]))
        assert_true(row.explanation.contains("the same as %s." % base), row.explanation)
    page.free()


# --- (h) the empty chord button -----------------------------------------------------


func test_an_empty_chord_button_reads_set() -> void:
    var page := SaShortcutsPage.new()
    var met := 0
    for group: Array in SaShortcutsPage.GROUPS:
        for action: StringName in SaShortcutsPage.actions_for(String(group[0])):
            if SaShortcutStore.chords_for(action).is_empty():
                met += 1
                assert_eq(page.chords_shown(action), ["Set..."] as Array[String], "%s offers to set a chord" % action)
    assert_true(met > 0, "the shipped map has a command with no chord, tool_zoom at least")
    page.free()
