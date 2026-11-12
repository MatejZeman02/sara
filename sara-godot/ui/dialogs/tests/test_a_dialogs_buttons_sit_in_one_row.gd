## A dialog's buttons sit in one row pinned to its bottom edge, the way out first
## and the default last.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Export, New Document and the filters pinned their buttons to the bottom edge
## while Canvas Size and the unsaved changes question put theirs under the
## content, the question read "Save, Discard, Cancel" where the rest read Cancel
## then the action, and Rename Layer said OK. The row is now
## `SaDialogWindow.pinned_buttons`, and `SaMessage._set_buttons` lays a question
## out in the order every other row reads.
##
## The dialogs are opened embedded in the real tree and laid out by hand, for the
## reason `test_a_dialog_opens_to_show_its_own_buttons` gives: no frame passes
## inside a test, and a container sorts its children when it is told to. A
## tool script, because the two stub dialogs below extend one.
@tool
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## How much taller than it opened a dialog is dragged, in logical units, to show
## the row follows the bottom edge rather than the content.
const DRAGGED_TALLER := 160

## The screen every dialog here opens on, in logical units, a `SubViewport` with
## its subwindows embedded, so the room a dialog is fitted to is the same on
## every machine the gate runs on.
const SCREEN := Vector2i(1280, 800)


## A dialog of two fixed rows and the button row, the shape About and New
## Module have.
class FixedDialog:
    extends SaDialogWindow

    func _init() -> void:
        _init_dialog("N100FixedDialog", "Fixed", Vector2i(360, 240), Vector2i(300, 200))
        var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
        margin.set_anchors_preset(Control.PRESET_FULL_RECT)
        var column := SaMake.column(margin, "Column", SaTheme.GAP)
        SaMake.label(column, "First", "One row")
        SaMake.label(column, "Second", "and another")
        SaMake.button(pinned_buttons(column), "DoneButton", "Done")


## A dialog whose list grows with the window, the shape the Manual has.
class GrowingDialog:
    extends SaDialogWindow

    func _init() -> void:
        _init_dialog("N100GrowingDialog", "Growing", Vector2i(360, 240), Vector2i(300, 200))
        var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
        margin.set_anchors_preset(Control.PRESET_FULL_RECT)
        var column := SaMake.column(margin, "Column", SaTheme.GAP)
        var list := ItemList.new()
        list.name = "List"
        list.size_flags_vertical = Control.SIZE_EXPAND_FILL
        column.add_child(list)
        SaMake.button(pinned_buttons(column), "DoneButton", "Done")


var _kept_embedding: bool = true
var _kept_correction: PackedFloat32Array = PackedFloat32Array()
var _host: Node = null


func before_each() -> void:
    _kept_correction = SaTablet.correction.duplicate()
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    # A Window added without embedding maps a real OS window and blocks the run.
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "N100ButtonRowTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    SaTablet.correction = _kept_correction


## The unsaved changes question, asked with the labels and the two indices
## `SaDocumentFiles.confirm_discard` asks with, reads Cancel, Discard, Save from
## left to right, and every button still answers the index it was given.
func test_the_question_reads_cancel_discard_save_and_keeps_its_indices() -> void:
    var labels := PackedStringArray(["Save", "Discard", "Cancel"])
    for pressed: int in range(labels.size()):
        var answers: Array[int] = []
        var question := SaMessage.confirm(
            _host,
            "Unsaved changes",
            "Save the changes to Untitled before quitting?",
            labels,
            func(index: int) -> void: answers.append(index),
            SaDocumentFiles.PROMPT_CANCEL,
            SaDocumentFiles.PROMPT_SAVE
        )
        _sort(question)
        assert_eq(_row_words(question.button_row), ["Cancel", "Discard", "Save"], "The way out first and the default last")
        assert_true(_left_to_right(question.button_row), "and the row draws them in that order")
        assert_eq(question.buttons[pressed].text, labels[pressed], "Button %d is still the answer it was asked with" % pressed)
        question.buttons[pressed].pressed.emit()
        assert_eq(answers, [pressed], "and %s answers %d, as it did before the row moved" % [labels[pressed], pressed])


## The default keeps the focus wherever the row put it, so Enter is still Save.
func test_the_default_still_holds_the_focus() -> void:
    var question := SaMessage.confirm(
        _host,
        "Unsaved changes",
        "Save?",
        PackedStringArray(["Save", "Discard", "Cancel"]),
        func(_index: int) -> void: pass,
        SaDocumentFiles.PROMPT_CANCEL,
        SaDocumentFiles.PROMPT_SAVE
    )
    question._focus_default()
    assert_eq(question.gui_get_focus_owner(), question.buttons[SaDocumentFiles.PROMPT_SAVE], "Enter presses Save")
    assert_eq(question.button_row.get_children().back(), question.buttons[SaDocumentFiles.PROMPT_SAVE], "at the end of the row")
    question.hide()


## A question whose cancel is its default, the light mode offer's, has nothing
## to put last, and a problem's one OK is the whole row bar the Copy button,
## which stays at the left of it.
func test_a_cancel_that_is_the_default_comes_first_and_copy_stays_left() -> void:
    var offer := SaMessage.confirm(
        _host, "A light mode", "Turn it on?", PackedStringArray(["Turn it on", "Not now"]), func(_i: int) -> void: pass, 1, 1
    )
    assert_eq(_row_words(offer.button_row), ["Not now", "Turn it on"], "The way out first, and the rest after it")
    offer.hide()

    var problem := SaMessage.new()
    _host.add_child(problem)
    problem.show_problem("Something failed")
    assert_eq(problem.button_row.get_child(0), problem.copy_button, "Copy keeps the left of the row")
    assert_eq(_row_words(problem.button_row), ["Copy", "OK"], "and OK is the row's one answer")
    problem.hide()


## Canvas Size's row ends at the window's bottom margin as it opens, and again
## once the window is dragged taller, which is the half a row under the content
## failed: the buttons rode up into the middle of the window.
func test_canvas_size_and_image_size_pin_their_row_to_the_bottom_edge() -> void:
    for opened: SaDialogWindow in [SaCanvasSizeDialog.new(), SaImageSizeDialog.new()]:
        var dialog := _place(opened)
        dialog.fit_opening_size()
        _sort(dialog)
        var name := String(dialog.name)
        assert_almost_eq(_row_bottom(dialog), _bottom_margin(dialog), 1.0, "%s's row ends at its bottom margin" % name)
        dialog.size = dialog.size + Vector2i(0, DRAGGED_TALLER)
        _sort(dialog)
        assert_almost_eq(_row_bottom(dialog), _bottom_margin(dialog), 1.0, "and still does dragged taller")
        var row := dialog.find_child("Buttons", true, false) as HBoxContainer
        assert_eq(row.alignment, BoxContainer.ALIGNMENT_END, "%s's row is aligned to the end" % name)
        assert_eq(row.get_children().back(), dialog.default_button, "with the default last")


## A dialog whose column has nothing that grows gets the spacer, which is what
## pins its row, and one whose column has a growing child gets none, because the
## spacer would take half of that child's room.
func test_the_helper_pins_the_row_with_a_spacer_only_where_nothing_grows() -> void:
    var fixed := _place(FixedDialog.new())
    _sort(fixed)
    assert_not_null(fixed.find_child("ButtonsSpacer", true, false), "A column of fixed rows gets the spacer")
    assert_almost_eq(_row_bottom(fixed), _bottom_margin(fixed), 1.0, "and its row ends at the bottom margin")
    fixed.size = fixed.size + Vector2i(0, DRAGGED_TALLER)
    _sort(fixed)
    assert_almost_eq(_row_bottom(fixed), _bottom_margin(fixed), 1.0, "and still does dragged taller")

    var growing := _place(GrowingDialog.new())
    _sort(growing)
    assert_null(growing.find_child("ButtonsSpacer", true, false), "A column with a growing child gets none")
    var list := growing.find_child("List", true, false) as Control
    var row := growing.find_child("Buttons", true, false) as Control
    var gap := float(growing.find_child("Column", true, false).get_theme_constant("separation"))
    assert_almost_eq(list.get_global_rect().end.y + gap, row.get_global_rect().position.y, 1.0, "The list runs down to the row")
    assert_almost_eq(_row_bottom(growing), _bottom_margin(growing), 1.0, "which ends at the bottom margin")


## Rename Layer's confirming button says what it does.
func test_rename_layer_confirms_with_rename() -> void:
    var dialog := SaLayerRenameDialog.new()
    _host.add_child(dialog)
    assert_eq(dialog.default_button.text, "Rename", "Rename Layer confirms with Rename rather than OK")
    var row := dialog.default_button.get_parent()
    assert_eq(_row_words(row as HBoxContainer), ["Cancel", "Rename"], "after Cancel")
    dialog.hide()


## The Manual has a way out in the row as well as the cross, and it is the
## button Enter presses.
func test_the_manual_has_a_close() -> void:
    var manual := SaManualWindow.open_in(_host)
    var close := manual.default_button
    assert_not_null(close, "The Manual has a default button")
    assert_eq(close.text, "Close", "and it is Close")
    assert_eq(close.get_parent().name, "Buttons", "in the dialog's one button row")
    assert_true(manual.visible, "The Manual is open")
    close.pressed.emit()
    assert_false(manual.visible, "and Close shuts it")


## The tablet sweep's row starts with Cancel and ends with Keep, and Cancel after
## Try It keeps nothing: the curve Try It put live goes back to the one the
## painter had.
func test_the_tablet_sweep_starts_with_cancel_and_cancel_keeps_nothing() -> void:
    var had := PackedFloat32Array([0.0, 0.3, 1.0])
    SaTablet.correction = had.duplicate()
    var dialog := _place(SaTabletSweepDialog.new()) as SaTabletSweepDialog
    var row := dialog.find_child("Buttons", true, false) as HBoxContainer
    assert_eq(_row_words(row), ["Cancel", "Start Again", "Try It", "Keep"], "Cancel first and Keep last")

    for index in range(3):
        dialog.begin_sweep(index)
        for i in range(40):
            var t := float(i) / 39.0
            dialog.feed(index, t * 2.0, pow(t, 2.0))
        dialog.end_sweep(index)
    dialog.enter_test()
    assert_true(SaTablet.correction != had, "Try It puts the fitted curve live")

    var cancel := row.get_child(0) as Button
    cancel.pressed.emit()
    assert_false(dialog.visible, "Cancel closes the sweep")
    assert_eq(SaTablet.correction, had, "and the curve the painter had is the one live again")


## *dialog* opened on a screen of its own and laid out, the way the app shows
## one. The screen is freed with the suite's host.
func _place(dialog: SaDialogWindow) -> SaDialogWindow:
    var screen := SubViewport.new()
    screen.size = SCREEN
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    screen.add_child(dialog)
    dialog.popup_centered()
    _sort(dialog)
    return dialog


## The words on a row's visible buttons, left to right.
func _row_words(row: HBoxContainer) -> Array[String]:
    var words: Array[String] = []
    for child: Node in row.get_children():
        var button := child as Button
        if button != null and button.visible:
            words.append(button.text)
    return words


## Whether every visible button in *row* is drawn to the right of the one before.
func _left_to_right(row: HBoxContainer) -> bool:
    var last := -INF
    for child: Node in row.get_children():
        var button := child as Button
        if button == null or not button.visible:
            continue
        if button.position.x <= last:
            return false
        last = button.position.x
    return true


## Where *dialog*'s button row ends, in the window's own space.
func _row_bottom(dialog: SaDialogWindow) -> float:
    var row := dialog.find_child("Buttons", true, false) as Control
    return row.get_global_rect().end.y


## The window's bottom edge less the margin its column sits in.
func _bottom_margin(dialog: SaDialogWindow) -> float:
    var margin := dialog.content.get_child(0) as MarginContainer
    return float(dialog.size.y - margin.get_theme_constant("margin_bottom"))


## Lays *window* out the way a drawn frame would, for the reason
## `test_every_dialog_opens_inside_the_window_at_every_size_and_scale` gives
## for its own `_settle`: every container sorted outside in and every control
## asked for its minimum again, twice, because a wrapping label first answers
## the height of its whole text one character wide, and then a pixel on the
## window and back, so a control laid out by its anchors takes its size again.
func _sort(window: Window) -> void:
    for _pass in range(2):
        _sort_under(window)
        _ask_again(window)
    var kept := window.size
    window.size = kept + Vector2i.ONE
    window.size = kept
    _sort_under(window)


func _sort_under(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_under(child)


func _ask_again(node: Node) -> void:
    for child: Node in node.get_children():
        _ask_again(child)
        if child is Control:
            (child as Control).update_minimum_size()
