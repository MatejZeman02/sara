## Levels says what it does.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Moved from the skeleton's suites with the Levels filter. The controls are
## `SaLevelsPanel`'s, the custom row the filter hands its page, and the
## Preview box and the two buttons are the filter window's.
##
## The note is "missing a proper tooltip for explanation." The dialog's number
## fields carry no visible caption at all, so the tooltip is not an extra on
## top of a label, it is the only label there is, and until this it repeated
## the word "Black" at a painter who was pointing at the box because they did
## not know what black meant here. The Channel row had nothing at all.
##
## `scenarios/levels-says-what-it-does.json` reads every line back off the
## running dialog, which is the proof, because a tooltip is the one thing a
## screenshot of a dialog cannot show. This file is the part that has to hold
## whatever a scenario happens to hover: every control a painter can point at
## carries a sentence, and no sentence is the word already written on the
## control.
extends "res://tests/test_framework.gd"


## The panel, built and never put in the tree: `tooltip_report` walks the
## panel's own children and asks a control's class and its `tooltip_text` and
## nothing about visibility, so a panel outside the tree answers the same.
func _dialog() -> SaLevelsPanel:
    return SaLevelsPanel.new()


## The panel's own controls, which is what `tooltip_report` walks.
func _controls(dialog: Control) -> Array[Control]:
    var out: Array[Control] = []
    for child in dialog.find_children("*", "Control", true, false):
        var control := child as Control
        if control != null and SaLevelsPanel.worth_a_tooltip(control):
            out.append(control)
    return out


func test_every_control_a_painter_points_at_carries_a_sentence() -> void:
    var dialog := _dialog()

    var controls := _controls(dialog)
    # Eleven: the Preview box and the two buttons were the dialog's and are the
    # filter window's now, and the last case holds the two buttons' sentences.
    assert_true(controls.size() >= 11, "the panel holds the eleven controls the note is about, found %d" % controls.size())
    for control in controls:
        assert_false(control.tooltip_text.strip_edges().is_empty(), "%s says what it does" % control.name)
        assert_true(
            control.tooltip_text.length() > 20,
            "%s says it in a sentence rather than a word: %s" % [control.name, control.tooltip_text]
        )
    dialog.free()


## The fault the note names. A tooltip that repeats the text already on the
## control tells a painter nothing they could not already see.
func test_no_tooltip_repeats_the_text_on_its_own_control() -> void:
    var dialog := _dialog()

    for control in _controls(dialog):
        var written := ""
        if control is Label:
            written = (control as Label).text
        elif control is Button:
            written = (control as Button).text
        if written.is_empty():
            continue
        assert_true(control.tooltip_text != written, "%s explains rather than repeating '%s'" % [control.name, written])
    dialog.free()


## The five fields are the case the note was written about: no caption, so the
## tooltip is the caption, and it has to open with the name before it explains.
func test_each_field_names_itself_and_then_explains() -> void:
    var dialog := _dialog()

    for row: Dictionary in SaLevelsPanel.ROWS:
        var field := dialog.find_child(String(row["key"]).capitalize().replace(" ", "") + "Field", true, false) as SpinBox
        assert_not_null(field, "the %s field is there" % row["key"])
        var hint := String(row["hint"])
        assert_eq(field.tooltip_text, hint, "and carries its own hint")
        assert_true(hint.length() > String(row["label"]).length() + 20, "which is longer than the label it replaced")
        assert_true(hint.ends_with("."), "and is a sentence: %s" % hint)
    dialog.free()


## A `Label` ignores the pointer by default and never shows a tooltip it
## carries. Both labels that gained one had to be told to stop it, and a later
## edit that drops the line would leave a sentence nobody can reach with
## nothing red anywhere.
func test_a_label_that_carries_a_sentence_takes_the_pointer() -> void:
    var dialog := _dialog()

    for name: String in ["ChannelLabel", "OutputLabel"]:
        var label := dialog.find_child(name, true, false) as Label
        assert_not_null(label, "%s is there" % name)
        assert_false(label.tooltip_text.is_empty(), "and carries a sentence")
        assert_true(label.mouse_filter != Control.MOUSE_FILTER_IGNORE, "and does not let the pointer through it")
    dialog.free()


## The Channel row is the note's own path, and the two halves of it say the
## same thing because a painter points at whichever half their eye landed on.
func test_the_channel_label_and_its_dropdown_explain_the_same_thing() -> void:
    var dialog := _dialog()

    var label := dialog.find_child("ChannelLabel", true, false) as Label
    var button := dialog.find_child("ChannelButton", true, false) as SaChoiceButton

    assert_eq(label.tooltip_text, button.tooltip_text, "the label and the dropdown carry one sentence")
    assert_true(label.tooltip_text.contains("Oklab"), "which says what the Oklab entry means")
    assert_true(label.tooltip_text.contains("Master"), "and what Master does")
    dialog.free()


## The report the scenario reads. It has to name every control it walked and
## carry each tooltip, or the scenario proves nothing about the ones it missed.
func test_the_capture_door_reports_every_control_and_its_tooltip() -> void:
    var dialog := _dialog()

    var report: String = dialog.tooltip_report()

    for control in _controls(dialog):
        assert_true(report.contains(String(control.name)), "%s is on the report" % control.name)
        assert_true(report.contains(control.tooltip_text), "with the sentence it carries")
    dialog.free()


## The two buttons are the filter window's, and the filter's `build` gives them
## the sentences the dialog's own buttons carried, so pointing at Cancel still
## says what it costs.
func test_the_filter_gives_the_windows_buttons_their_sentences() -> void:
    var ui := SaDialog.new()
    SaLevelsFilter.new().build(ui)
    assert_true(ui.cancel_button.tooltip_text.length() > 20, "Cancel says what it does: %s" % ui.cancel_button.tooltip_text)
    assert_true(ui.apply_button.tooltip_text.length() > 20, "and so does Apply: %s" % ui.apply_button.tooltip_text)
    # Never realized, so the preview, the Preview box and the row that holds
    # the two buttons have to be freed by hand.
    ui.apply_button.get_parent().free()
    ui.preview_control.free()
    ui.canvas_box.free()
