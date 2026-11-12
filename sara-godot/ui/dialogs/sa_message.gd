## The one dialog for errors and questions.
##
## Two jobs, on the same window. As the problem sink it shows what
## `SaProblems.report` collects, one line per report, growing rather than
## stacking when several arrive at once, because a save that fails on every
## chunk is one problem and not sixty windows. As a question it shows a row of
## buttons and answers with the index of the one pressed, through a Callable,
## and answers with the cancel index when it is closed without choosing.
##
## Answerable from the keyboard: the default button takes focus when the window
## opens, so Enter presses it and Tab walks the row, and Escape is the cancel
## answer rather than a silent close, because it closes the window as the × does
## and every close that is not a button answers Cancel. Sara's own chrome from `SaDialogWindow`,
## so the pointer stays visible over it and it can be dragged and resized.
##
## Beside the window it owns a second, quieter surface: `notice`, a line in the
## canvas corner that goes away by itself, `SaNotice` in its own file. A refusal
## the painter can act on is not a fault to collect and not a question to
## answer, so a window with a button in it would be the wrong shape for it, and
## a `push_error` nobody is watching leaves a refusal unseen. Both are
## reached through this class because there should be one answer to "how does
## Sara tell the painter something".
##
## **Which of the two a report lands on is the call site's word, not this
## file's**. `deliver` is the sink `install` attaches, and it reads the kind
## `SaProblems` hands it beside the line: a fault grows the window, a refusal
## goes to the corner, rather than every report opening a dialog whatever it
## has to say, which puts "there is no selection to patch" up as a modal window
## over the canvas with an OK button on it.
@tool
class_name SaMessage
extends SaDialogWindow

## Emitted with the index of the button pressed, or the cancel index when the
## window was closed without one. The Callable handed to `ask` is the usual way
## to hear it, this is for whoever wants both.
signal answered(index: int)

## Opens at the floor's height and grows to its text, because the fit grows a
## window and never shrinks it, and a taller floor would leave a short question
## blank below its buttons. The floor is below what a line of text
## and the button row need, so what the window says sets its height and the floor
## never adds a blank strip of its own.
const DEFAULT_SIZE := Vector2i(520, 100)
const MIN_SIZE := Vector2i(360, 100)

## The problem dialog stops growing here and counts the rest, so a fault that
## repeats per chunk does not become a window taller than the screen.
const MAX_LINES: int = 12

## The three ways out of a message window a `close` step can name. Anything
## else falls back to `hide`, which is the route that works whatever state the
## window is in.
const CLOSE_ROUTES := ["escape", "button", "hide"]

## The problem dialog `install` creates. One per process.
static var _problems: SaMessage = null

## The transient notice `install` creates, over the same window. One per
## process, and null until then, so `notice` before boot is silent rather than
## a Control nobody would ever look at.
static var _notice: SaNotice = null

## What the last question the capture door opened answered with, so its `close`
## step can say so in one line. A capture is one scenario at a time, hence a
## static, and it is never read outside `capture_message`.
static var _capture_answers: Array = []

## The question the capture door's `ask` step built, so its `close` step reaches
## that one rather than whichever `Question` the tree happens to hold. Sara opens
## the recovery prompt under that same name at boot, and without this the first
## `close` of a scenario answered the recovery prompt instead.
static var _capture_question: SaMessage = null

## The text a painter reads, and can select and copy. A `RichTextLabel` with
## bbcode off rather than a `Label`, because Godot 4's `Label` has no selection
## of any kind: it draws glyphs and answers no gesture. Both writers still
## assign plain text to `text`, so nothing that reads it back had to change.
var text_label: RichTextLabel
var button_row: HBoxContainer
var buttons: Array[Button] = []

## The Copy button, on the row and outside `buttons` so `_set_buttons` leaves it
## where it is and the answer indices a question hands out are the ones its own
## labels earned. Shown for a problem and hidden for a question: a problem's
## whole text is what a painter passes on, and a quit prompt with a Copy button beside Cancel
## is a button nobody wants.
var copy_button: Button

var _lines: PackedStringArray = PackedStringArray()
var _overflow: int = 0
var _on_answer: Callable = Callable()
var cancel_index: int = 0
var _default_index: int = 0
var _answered: bool = false

## What this window's last copy put on the clipboard, written by `copy_text`
## alone.
##
## Beside the `DisplayServer` call rather than instead of it. The clipboard is
## the operating system's and a headless run has none: `clipboard_get` answers
## the empty string there whatever was set, so a suite that graded the copy on
## it would grade every run the same. This is what the window did, the clipboard
## is what the machine took, and the dump carries both.
var _copied: String = ""


func _init() -> void:
    _init_dialog("SaMessage", tr("Message"), DEFAULT_SIZE, MIN_SIZE)
    # A Window is visible the moment it joins the tree. This one is installed
    # at boot and must wait to be asked, or it opens blank in the corner.
    visible = false

    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(margin, "Column", 10)

    # A scroll view rather than the label straight in the column. A Window does
    # not clip, and a VBoxContainer demands the sum of its children, so a long
    # compiler message would push the buttons off the bottom edge. It is
    # the window's scrolling body, so the fit gives it the height its text needs
    # and the host has, and the window opens at the height of what it says.
    var scroll := SaMake.scroll(column, "Scroll")
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scrolling_body = scroll

    text_label = RichTextLabel.new()
    text_label.name = "Text"
    # Off, because every writer hands this plain prose. A compiler message full
    # of square brackets would otherwise be read as markup and disappear.
    text_label.bbcode_enabled = false
    text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    text_label.selection_enabled = true
    # The control takes Ctrl+C itself once it has focus, and focus arrives on a
    # click, which is the same gesture that starts a selection. Without the
    # filter the drag never reaches it, and without the focus mode the copy
    # keystroke goes to the button that has focus instead.
    text_label.shortcut_keys_enabled = true
    text_label.focus_mode = Control.FOCUS_CLICK
    text_label.mouse_filter = Control.MOUSE_FILTER_STOP
    # The scroll container gives its child no height of its own, so the text has
    # to ask for the room its lines need or a `RichTextLabel` draws one line.
    text_label.fit_content = true
    text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.add_child(text_label)

    button_row = pinned_buttons(column)

    # Added before any `_set_buttons` call, so it stays at the left of the row
    # whatever a question puts beside it.
    copy_button = SaMake.button(button_row, "CopyButton", tr("Copy"), tr("Copy the whole message to the clipboard"))
    copy_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    copy_button.visible = false
    copy_button.pressed.connect(copy_text)

    # No `visibility_changed.connect` here. `_init_dialog` already connected the
    # signal to `_on_visibility_changed`, and this class overrides that method,
    # so a second connect names one method on one instance: the engine refuses
    # it and prints "already connected" on every launch and every quit. The
    # override below is what makes closing by any route the cancel answer.


## Shows `text` under `title` with the given buttons, and calls `on_answer`
## with the index of the one pressed. Escape, the close button and hiding by
## any other route answer `cancel_at`, which is the last button unless said
## otherwise. `default_index` is the button Enter presses.
func ask(
    title_text: String, text: String, labels: PackedStringArray, on_answer: Callable, cancel_at: int = -1, default_index: int = 0
) -> void:
    retitle(title_text)
    text_label.text = text
    _on_answer = on_answer
    cancel_index = cancel_at if cancel_at >= 0 else labels.size() - 1
    _default_index = clampi(default_index, 0, maxi(labels.size() - 1, 0))
    _set_buttons(labels)
    if copy_button != null:
        copy_button.visible = false
    _answered = false
    _lines = PackedStringArray()
    _overflow = 0
    _open()


## The problem sink: one line and the kind its call site gave it. A fault grows
## the window, a refusal says its line in the corner and takes it away again.
##
## The kind rather than the text, because the text is a sentence a painter reads
## and not a severity a program can trust: "could not" appears in refusals and
## faults alike, and a sink that guessed would have to be re-guessed every time
## someone rewrote a message.
func deliver(line: String, kind: SaProblems.Kind) -> void:
    if kind == SaProblems.Kind.REFUSAL:
        SaMessage.notice(line)
        return
    show_problem(line)


## Shows one problem with a single button to dismiss it. A second call while
## the window is open adds a line rather than a window.
func show_problem(line: String) -> void:
    if visible and _on_answer.is_valid():
        # A question is up. Answer it as cancelled rather than overwrite it
        # under the user's pointer, then show the problem.
        _answer(cancel_index)
    if not visible:
        _lines = PackedStringArray()
        _overflow = 0
    if _lines.has(line):
        return
    if _lines.size() >= MAX_LINES:
        _overflow += 1
    else:
        _lines.append(line)
    var shown := "\n".join(_lines)
    if _overflow > 0:
        shown += "\n" + tr_n("and %d more, in the log", "and %d more, in the log", _overflow) % _overflow
    var title_text := tr("Problem") if _lines.size() + _overflow == 1 else tr("Problems")
    retitle(title_text)
    text_label.text = shown
    _on_answer = Callable()
    cancel_index = 0
    _default_index = 0
    if buttons.size() != 1:
        _set_buttons(PackedStringArray([tr("OK")]))
    if copy_button != null:
        copy_button.visible = true
    _answered = false
    if not visible:
        _open()
    else:
        # A window fitted to one line grows to the next, which the fit on show
        # alone would leave scrolling in the height of the first.
        _fit_next_frame()


## Puts the whole message on the clipboard, selection or no selection.
##
## The whole of it rather than what is selected, because that is the difference
## between the button and Ctrl+C: a painter who has already selected part of the
## text presses the keys, and one who wants the lot presses the button and does
## not have to drag over twelve lines in a scrolling box first. The precedent is
## `about_dialog.gd`'s Copy Details, which copies its page rather than a
## selection for the same reason.
func copy_text() -> void:
    if text_label == null:
        return
    _copied = text_label.text
    DisplayServer.clipboard_set(_copied)


## Selects the whole message and takes focus, which is the state a painter's
## drag over the text leaves behind. Public because a capture cannot drag: a
## pointer event pushed into a `Window` reaches its `_input` and never the
## control the pointer is over.
func select_text() -> void:
    if text_label == null:
        return
    text_label.grab_focus()
    text_label.select_all()


## Copies what is selected, which is what Ctrl+C over the text does. Nothing
## selected copies nothing, the same as the keystroke.
func copy_selection() -> void:
    if text_label == null:
        return
    _copied = text_label.get_selected_text()
    DisplayServer.clipboard_set(_copied)


## What a state dump says about the message window, so a claim about copying is
## graded on numbers rather than on a screenshot of a dialog that looks the same
## either way.
##
## `clipboard_matches` rather than the clipboard itself: a dump lands in a review
## folder that gets pushed, and a run with `--watch` reads the person's own
## desktop clipboard, whatever happened to be on it. The flag says the thing the
## note asks about and carries nothing off the machine.
static func message_state() -> Dictionary:
    var dialog := live_dialog(Engine.get_main_loop() as SceneTree)
    if dialog == null:
        dialog = problem_dialog()
    if dialog == null or dialog.text_label == null:
        return {"present": false, "visible": false, "text": "", "selection_enabled": false}
    var shown := dialog.text_label.text
    return {
        "present": true,
        "visible": dialog.visible,
        "text": shown,
        "selection_enabled": dialog.text_label.selection_enabled,
        "selected": dialog.text_label.get_selected_text(),
        "copy_button": dialog.copy_button != null and dialog.copy_button.visible,
        # Focus and the rectangle, because they are what a real Ctrl+C and a
        # real drag need and no screenshot shows either.
        "focused": dialog.text_label.has_focus(),
        "text_rect": var_to_str(dialog.text_label.get_global_rect()),
        "copied": dialog._copied,
        "clipboard_matches": DisplayServer.clipboard_get() == shown,
        "clipboard_chars": DisplayServer.clipboard_get().length(),
    }


## Says one line in the canvas corner and takes it away again, with nothing to
## dismiss and nothing to answer.
##
## Silent until `install` has run. The same line arriving again while it is up
## restarts the clock rather than stacking, which is what a stroke refused at
## tablet rate would otherwise be.
static func notice(text: String) -> void:
    SaNoticeLog.record(text)
    if _notice == null or not is_instance_valid(_notice):
        return
    _notice.show_line(text)


## The notice widget, for a test or a state dump that wants to read it.
static func notice_widget() -> SaNotice:
    return _notice if _notice != null and is_instance_valid(_notice) else null


## Makes `host` the parent of the problem dialog and the notice, and starts
## showing what `SaProblems` has collected, including everything reported
## before now.
static func install(host: Node) -> void:
    if _problems != null and is_instance_valid(_problems):
        return
    _problems = SaMessage.new()
    _problems.name = "ProblemDialog"
    host.add_child(_problems)
    SaProblems.attach_sink(_problems.deliver)
    _problems.tree_exiting.connect(SaMessage._uninstall)

    _notice = SaNotice.new()
    host.add_child(_notice)
    # Guarded, because `install` runs again after a host is freed and a second
    # connection to one callable is a warning the engine prints.
    if not EventBus.paint_refused.is_connected(SaMessage.notice):
        EventBus.paint_refused.connect(SaMessage.notice)
    if not EventBus.corner_notice.is_connected(SaMessage.notice):
        EventBus.corner_notice.connect(SaMessage.notice)


## Asks a question in a fresh window under `host`, freed once answered.
static func confirm(
    host: Node,
    title_text: String,
    text: String,
    labels: PackedStringArray,
    on_answer: Callable,
    cancel_at: int = -1,
    default_index: int = 0
) -> SaMessage:
    var dialog := SaMessage.new()
    dialog.name = "Question"
    host.add_child(dialog)
    dialog.answered.connect(func(_index: int) -> void: dialog.queue_free())
    dialog.ask(title_text, text, labels, on_answer, cancel_at, default_index)
    return dialog


## Drives the message window: `{"message": {"select": true}}` and `{"message":
## {"copy": "selection"}}` or `"button"` work on it.
##
## **Arguments.**
## - `close` string, `escape`, `button` or `hide`.
## - `ask` string, a question to put up, its buttons in `labels`.
## - `labels` array, the question's buttons.
##
## `{"message": {"problem": "..."}}` reports a problem, `{"message": {"ask":
## "...", "labels": ["Cancel", "Quit"], "cancel": 0}}` asks a question, and
## `{"message": {"close": "escape"}}`, `"button"` or `"hide"` closes whichever is
## up by one of the three routes a close has to leave working. Anything else
## written as `close`, a boolean, a number or a word that is not a route, hides
## the window and is quoted back. Answers what it did and what the window
## answered, so a scenario reads the result without a dump.
##
## **A `click` on one of its buttons presses it too**, embedded or a window of
## its own, and a `key` step's Escape closes an embedded one. Both were
## measured on the running app. The step is still the one route that needs no
## point, answers whichever message window is up, and says what it answered.
static func capture_message(tree: SceneTree, spec: Dictionary) -> String:
    var dialog := live_dialog(tree)
    if spec.has("problem"):
        SaProblems.report(String(spec.get("source", "SaCapture")), String(spec["problem"]))
        return "SaCapture: message problem reported"
    if spec.has("ask"):
        var labels := PackedStringArray()
        for label: Variant in spec.get("labels", ["OK"]) as Array:
            labels.append(String(label))
        var replies: Array = []
        # The window `confirm` returns, rather than a search for one: Sara's own
        # recovery prompt is a visible `Question` at boot and a search finds that.
        _capture_question = SaMessage.confirm(
            tree.root,
            String(spec.get("title", "Question")),
            String(spec["ask"]),
            labels,
            func(index: int) -> void: replies.append(index),
            int(spec.get("cancel", -1)),
            int(spec.get("default", 0))
        )
        _capture_answers = replies
        return "SaCapture: message asked %s" % JSON.stringify(Array(labels))
    # The three, all on the window that is up. `select` and `copy` answer rather
    # than close, so a scenario can select, copy by the keys, copy by the button
    # and shoot, all against one dialog.
    if spec.has("select") or spec.has("copy"):
        if dialog == null:
            return "SaCapture: no message window is up to copy from"
        return _capture_copy(dialog, spec)
    if not spec.has("close"):
        return "SaCapture: message needs 'problem', 'ask', 'select', 'copy' or 'close'"
    if dialog == null:
        return "SaCapture: no message window is up to close"
    # Listen before closing rather than reading what `ask` recorded. The problem
    # dialog has no callback and still answers its cancel index, which is half of
    # what a close has to leave working, and only the signal says so.
    _capture_answers = []
    var heard := func(index: int) -> void: _capture_answers.append(index)
    dialog.answered.connect(heard, CONNECT_ONE_SHOT)
    var route := close_route(spec["close"])
    match route:
        "escape":
            # The step the real key takes once it reaches this window, because
            # Escape is what a painter presses. An injected key reaches the main
            # window and never this one, and a suite has no router watching it.
            var event := InputEventKey.new()
            event.keycode = KEY_ESCAPE
            event.pressed = true
            ShortcutRouter.escape_in_a_dialog(event, dialog)
        "button":
            dialog.close_button.pressed.emit()
        _:
            # Only ever "hide" now that `close_route` has narrowed the word, and
            # still the default arm rather than a case, so a route added to the
            # list above and not to this match hides instead of doing nothing.
            dialog.hide()
    if dialog.answered.is_connected(heard):
        dialog.answered.disconnect(heard)
    var said := "no answer" if _capture_answers.is_empty() else str(_capture_answers[0])
    return close_reply(spec["close"], route, said)


## `select` and `copy` on the window that is up.
##
## `{"select": true}` focuses the text and selects all of it, the state a drag
## leaves behind. `{"copy": "selection"}` copies what is selected, which is what
## Ctrl+C over the text does, and `{"copy": "button"}` presses the Copy button
## and takes the whole message. Anything else written as `copy` takes the
## button, and the reply says which route it took, whether the clipboard came
## out equal, and how much the copy took.
##
## **Neither route is the keystroke or the drag itself**, and this says so
## rather than pretending. A pointer or key event pushed into a `Window` reaches
## that window's `_input` and never the `_gui_input` of the control under the
## pointer: measured on the running app, a pushed press over the text left
## `focused` false and nothing selected, and a pushed press over the OK button
## pressed nothing. What the real gestures need is the three properties
## `_init` sets, and `ui/dialogs/tests/test_message_text_copies.gd` reads all three.
static func _capture_copy(dialog: SaMessage, spec: Dictionary) -> String:
    var did: Array[String] = []
    if spec.get("select", false):
        dialog.select_text()
        did.append("selected %d char(s)" % dialog.text_label.get_selected_text().length())
    if spec.has("copy"):
        var route := "selection" if str(spec["copy"]) == "selection" else "button"
        if route == "selection":
            dialog.copy_selection()
        else:
            dialog.copy_button.pressed.emit()
        did.append("copied the selection" if route == "selection" else "copied by the button")
    # Both, because they can differ: the class did the copy either way and the
    # clipboard is the machine's, which a headless run does not have.
    var same := DisplayServer.clipboard_get() == dialog.text_label.text
    did.append("clipboard matches the message" if same else "clipboard does not match the message")
    did.append("last copy was %d char(s)" % dialog._copied.length())
    return "SaCapture: message %s" % ", ".join(did)


## The route a `close` step actually takes, whatever type the scenario wrote it
## as. The coercion is `str` and not `String`, because `String` has no
## constructor for a boolean or an integer and the run died on `{"close": true}`
## with an engine error instead of closing the window. An unrecognized word is
## not a refusal either, the match's default arm hides, so this answers `hide`
## for it and the reply says which word it was.
static func close_route(asked: Variant) -> String:
    var word := str(asked)
    return word if CLOSE_ROUTES.has(word) else "hide"


## What a finished `close` step says. The route taken comes first, because that
## is the half a scenario reads back, and a word that was not a route is quoted
## after it, so a boolean or a typo answers in the step's own line rather than
## as a script error a reader has to trace to a scenario file.
static func close_reply(asked: Variant, route: String, said: String) -> String:
    var word := str(asked)
    if word == route:
        return "SaCapture: message closed by %s, answered %s" % [route, said]
    return "SaCapture: message closed by %s, '%s' is not a route, answered %s" % [route, word, said]


## Whatever message window is on screen: the question `confirm` built, or the
## problem dialog. The question first, because that is the one a scenario has
## just opened.
##
## **The walk is by type and not by name**, rather than for a child called
## `Question`, which is the name `confirm` gives every one it builds, because Godot
## renames a second child of that name to keep it unique. A question raised from another question's
## answer callback, which is exactly what `MainDialogs.offer_recoveries` does for a
## second recovery copy, is therefore called something else while the first is still
## in the tree, and a name search would walk straight past it, answering that no
## message window is up with one on the screen.
##
## The type is what the caller means. `find_children("*", "Window",...)` and a
## cast reaches every one whatever it is called, and the two lines above still
## answer first, so the question a scenario opened and the problem dialog keep
## the precedence they had. The transient notice is a `Control` on a window
## rather than a window, so the cast leaves it out without being told to.
static func live_dialog(tree: SceneTree) -> SaMessage:
    if _capture_question != null and is_instance_valid(_capture_question) and _capture_question.visible:
        return _capture_question
    var problems := problem_dialog()
    if problems != null and problems.visible:
        return problems
    for node in tree.root.find_children("*", "Window", true, false):
        var found := node as SaMessage
        if found != null and found.visible:
            return found
    return null


## The problem dialog, for a test that wants to look at it.
static func problem_dialog() -> SaMessage:
    return _problems if _problems != null and is_instance_valid(_problems) else null


static func _uninstall() -> void:
    SaProblems.detach_sink()
    _problems = null
    if EventBus.paint_refused.is_connected(SaMessage.notice):
        EventBus.paint_refused.disconnect(SaMessage.notice)
    if EventBus.corner_notice.is_connected(SaMessage.notice):
        EventBus.corner_notice.disconnect(SaMessage.notice)
    _notice = null


## The answers laid out in the order every dialog's row reads in: the cancel
## answer first, the default last when it is another answer, and the rest
## between them in the order they were given.
##
## Only the row is reordered. `buttons[i]` and the node `Button<i>` still answer
## *i*, so a caller and a scenario that presses `Button0` name an answer and
## not a place in the row. The Copy button was added before any of these and keeps the
## left of the row.
func _set_buttons(labels: PackedStringArray) -> void:
    for old in buttons:
        button_row.remove_child(old)
        old.queue_free()
    buttons.clear()
    for i in labels.size():
        var button := SaMake.button(button_row, "Button%d" % i, labels[i])
        button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
        button.pressed.connect(_answer.bind(i))
        buttons.append(button)
    for i in _row_order(labels.size(), cancel_index, _default_index):
        button_row.move_child(buttons[i], -1)


## The answers' indices in the order the row shows them, by the rule above.
static func _row_order(count: int, cancel_at: int, default_index: int) -> PackedInt32Array:
    var order := PackedInt32Array()
    var cancel := cancel_at if cancel_at >= 0 and cancel_at < count else -1
    var last := default_index if default_index != cancel and default_index >= 0 and default_index < count else -1
    if cancel >= 0:
        order.append(cancel)
    for i in count:
        if i != cancel and i != last:
            order.append(i)
    if last >= 0:
        order.append(last)
    return order


func _open() -> void:
    if is_inside_tree():
        popup_centered()
    else:
        show()
    _focus_default.call_deferred()


## The default button takes focus, so Enter answers. Deferred, because focus
## cannot be given to a control the window has not laid out yet.
func _focus_default() -> void:
    if not visible or _default_index >= buttons.size():
        return
    buttons[_default_index].grab_focus()


func _answer(index: int) -> void:
    if _answered:
        return
    _answered = true
    var callback := _on_answer
    _on_answer = Callable()
    hide()
    if callback.is_valid():
        callback.call(index)
    answered.emit(index)


## The two halves of this signal belong to two classes, which is why the base
## one has to run as well.
##
## The base class does the way *open*: it puts focus inside the dialog and takes
## the dots off any dropdown in it. This override does the way *closed*: any
## route out that is not a button, Escape, the close button or a plain `hide`,
## is the cancel answer. Neither is a special case of the other, so a second
## connect of the same signal, which the engine refuses as a duplicate, would
## leave one half unrun.
##
## `super()` costs nothing on the way closed, since the base's own body is
## behind `if visible`.
func _on_visibility_changed() -> void:
    super()
    if visible or _answered:
        return
    if _on_answer.is_valid() or not buttons.is_empty():
        _answer(cancel_index)


## The transient notice, for the state dump: whether it exists at all, whether a
## line is up right now, what that line says and where its panel stands in the
## window, which is what says whether a docker covers it.
## `present` is false in a run that never installed the message surfaces, which
## is not the same as a silent one.
static func notice_state() -> Dictionary:
    var widget := notice_widget()
    if widget == null:
        return {"present": false, "showing": false, "text": "", "rect": ""}
    return {
        "present": true,
        "showing": widget.showing(),
        "text": widget.label.text,
        "rect": var_to_str(widget.panel.get_global_rect()),
    }
