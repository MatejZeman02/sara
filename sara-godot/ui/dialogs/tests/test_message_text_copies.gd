## A problem's text can be selected and copied.
##
## The dialog is opened inside the real tree with subwindows embedded, the way
## `test_sa_message.gd` does, because focus and a selection only mean anything
## in a tree.
##
## **The pointer's own drag and the Ctrl+C after it cannot be driven at all**,
## here or from a scenario: an event pushed into a `Window` reaches its `_input`
## and never the `_gui_input` of the control under the pointer
## (an engine limitation), and the offscreen runner has no clipboard, so
## `clipboard_get` answers the empty string whatever was set. So the three
## properties those two gestures need are read here one by one, what the window
## handed over is read instead of the clipboard, and
## `scenarios/a-problems-text-can-be-copied.json` shows the dialog and its
## button on the running app.
extends "res://tests/test_framework.gd"

var _previous_embedding: bool = true
var _previous_clipboard: String = ""
var _host: Node = null


func before_each() -> void:
    SaProblems.announce = false
    SaProblems.detach_sink()
    SaProblems.pending = PackedStringArray()
    SaProblems.pending_refusals = PackedStringArray()
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    # Put back in `after_each`, because a suite that leaves the machine's
    # clipboard holding a test fixture is a suite with a side effect on the
    # person running it. The offscreen runner has no clipboard at all, which is
    # why nothing below grades the copy on `clipboard_get`: it answers the empty
    # string there whatever was set. `SaMessage._copied` is what the class did,
    # and the clipboard itself is proved on the running app by the scenario.
    _previous_clipboard = DisplayServer.clipboard_get()
    _host = Node.new()
    _host.name = "CopyTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    DisplayServer.clipboard_set(_previous_clipboard)
    SaProblems.detach_sink()
    SaProblems.pending = PackedStringArray()
    SaProblems.pending_refusals = PackedStringArray()
    SaProblems.announce = true
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _previous_embedding


func _dialog() -> SaMessage:
    var dialog := SaMessage.new()
    _host.add_child(dialog)
    return dialog


# --- The text itself ------------------------------------------------------------


## Selecting the text. A `Label` has no selection of any
## kind and defaults to a mouse filter that never sees a drag.
func test_the_message_text_can_be_selected() -> void:
    var dialog := _dialog()
    dialog.show_problem("Export: the file could not be written")

    assert_true(dialog.text_label is RichTextLabel, "The text is a control that can hold a selection")
    assert_true(dialog.text_label.selection_enabled, "and selection is on")
    assert_true(dialog.text_label.shortcut_keys_enabled, "and Ctrl+C is its own")
    assert_eq(dialog.text_label.mouse_filter, Control.MOUSE_FILTER_STOP, "and a drag over it arrives")
    assert_eq(dialog.text_label.focus_mode, Control.FOCUS_CLICK, "and a click gives it the focus Ctrl+C needs")


## Both writers still hand it plain text, which is what keeps every reader of
## `text_label.text` in the tree working.
func test_the_text_is_still_the_plain_line() -> void:
    var dialog := _dialog()
    dialog.show_problem("Export: the file could not be written")
    var problem := dialog.text_label.text
    dialog.ask("Quit", "Save before quitting?", PackedStringArray(["Cancel", "Quit"]), Callable())
    var question := dialog.text_label.text

    assert_eq(problem, "Export: the file could not be written", "The problem reads as written")
    assert_eq(question, "Save before quitting?", "and so does the question")
    assert_false(dialog.text_label.bbcode_enabled, "with bbcode off, so brackets in a compiler message survive")


## A message with square brackets in it is the case bbcode would eat, and a
## compiler message is full of them.
func test_brackets_in_a_message_survive() -> void:
    var dialog := _dialog()
    dialog.show_problem("SaCompute: [b] is not a kernel")

    assert_eq(dialog.text_label.text, "SaCompute: [b] is not a kernel", "read back exactly as reported")


# --- Copying --------------------------------------------------------------------


func test_the_copy_button_puts_the_whole_message_on_the_clipboard() -> void:
    var dialog := _dialog()
    dialog.show_problem("Export: the file could not be written")

    dialog.copy_button.pressed.emit()

    assert_eq(dialog._copied, "Export: the file could not be written", "The lot, not a selection")


## The window grows rather than stacking, so the copy has to be the whole of
## what is on screen and not the last line reported.
func test_a_grown_problem_copies_every_line() -> void:
    var dialog := _dialog()
    dialog.show_problem("first fault")
    dialog.show_problem("second fault")

    dialog.copy_text()

    var copied := dialog._copied
    assert_true(copied.contains("first fault"), "The first line was copied")
    assert_true(copied.contains("second fault"), "and so was the second")


func test_selecting_takes_the_whole_message() -> void:
    var dialog := _dialog()
    dialog.show_problem("Export: the file could not be written")

    dialog.select_text()

    assert_eq(dialog.text_label.get_selected_text(), "Export: the file could not be written", "select_text selects the lot")


# --- Which dialogs carry the button ---------------------------------------------


## The note asks for every problem text. A question is a different shape: its
## buttons are the answer, and a Copy beside Cancel is a button nobody wants.
func test_the_copy_button_is_a_problems_and_not_a_questions() -> void:
    var dialog := _dialog()
    dialog.show_problem("Export: the file could not be written")
    var on_problem := dialog.copy_button.visible
    dialog.ask("Quit", "Save before quitting?", PackedStringArray(["Cancel", "Quit"]), Callable())
    var on_question := dialog.copy_button.visible

    assert_true(on_problem, "A problem offers the button")
    assert_false(on_question, "and a question does not")


## The button is outside `buttons`, so a question's answer indices are the ones
## its own labels earned and Cancel is still the last of them.
func test_the_copy_button_does_not_move_a_questions_answers() -> void:
    var dialog := _dialog()
    var answers: Array = []
    dialog.ask(
        "Quit", "Save before quitting?", PackedStringArray(["Cancel", "Quit"]), func(index: int) -> void: answers.append(index)
    )

    assert_eq(dialog.buttons.size(), 2, "Two answer buttons")
    dialog.buttons[1].pressed.emit()
    assert_eq(answers, [1], "and the second one answers 1")


# --- What the dump says ---------------------------------------------------------


func test_the_dump_says_whether_the_clipboard_holds_the_message() -> void:
    var dialog := _dialog()
    DisplayServer.clipboard_set("something else entirely")
    dialog.show_problem("Export: the file could not be written")

    var before := SaMessage.message_state()
    dialog.copy_text()
    var after := SaMessage.message_state()

    assert_eq(before["text"], "Export: the file could not be written", "The dump carries the message")
    assert_true(before["selection_enabled"], "and says the text can be selected")
    assert_true(before["copy_button"], "and that the button is there")
    assert_eq(before["copied"], "", "Nothing had been copied yet")
    assert_eq(after["copied"], "Export: the file could not be written", "and the message after the copy")


## The clipboard itself never reaches the dump, because a dump lands in a review
## folder that gets pushed and a run on a desktop reads the person's own.
func test_the_dump_carries_no_clipboard_text() -> void:
    var dialog := _dialog()
    DisplayServer.clipboard_set("a private thing")
    dialog.show_problem("Export: the file could not be written")

    var state := SaMessage.message_state()

    for key: String in state:
        assert_false(str(state[key]).contains("a private thing"), "no key carries the clipboard, %s" % key)
    assert_true(state.has("clipboard_chars"), "only its length, and that under its own key")


# --- The capture step -----------------------------------------------------------


## The step a scenario uses, driven here so the reply's wording is fixed by a
## test rather than by whoever reads the scenario's output next.
func test_the_capture_step_selects_and_copies() -> void:
    var dialog := _dialog()
    dialog.show_problem("Export: the file could not be written")
    DisplayServer.clipboard_set("something else entirely")
    var tree := Engine.get_main_loop() as SceneTree

    var said := SaMessage.capture_message(tree, {"select": true, "copy": "button"})

    assert_true(said.contains("selected 37 char(s)"), "It says how much it selected: %s" % said)
    assert_true(said.contains("copied by the button"), "and which route it copied by")
    assert_true(said.contains("last copy was 37 char(s)"), "and how much the copy took: %s" % said)


func test_the_capture_step_needs_a_window_to_copy_from() -> void:
    var tree := Engine.get_main_loop() as SceneTree

    var said := SaMessage.capture_message(tree, {"copy": "button"})

    assert_eq(said, "SaCapture: no message window is up to copy from", "and says so rather than failing quietly")
