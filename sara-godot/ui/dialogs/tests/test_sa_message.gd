## The one message surface: problems reach the screen, and a question is
## answered from the keyboard as well as the pointer.
##
## Before this there were 73 `push_error` calls and no dialog anywhere, so a
## failed save or a kernel that did not compile was a line in a terminal the
## painter was not watching. The dialog is opened inside the real tree with
## subwindows embedded, the way `test_windows_open.gd` does, because focus and
## visibility only mean anything in a tree.
extends "res://tests/test_framework.gd"

## The break hook is an inner class of the compiler, its one user, so it is reached through the compiler's script.
const Compiler := preload("res://core/custom-shader/compiler/global_shader_compiler.gd")

var _previous_embedding: bool = true
var _host: Node = null


func before_each() -> void:
    SaProblems.announce = false
    SaProblems.detach_sink()
    SaProblems.pending = PackedStringArray()
    SaProblems.pending_refusals = PackedStringArray()
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "MessageTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
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


func _escape() -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_ESCAPE
    key.pressed = true
    return key


## The shader compiler runs as an autoload before any window exists, so its
## problems have nowhere to go yet. They are kept, not dropped.
func test_a_report_with_no_sink_is_kept() -> void:
    SaProblems.report("Src", "something failed")
    assert_eq(SaProblems.pending.size(), 1, "Kept for later")
    assert_eq(SaProblems.pending[0], "Src: something failed", "with who and what")


func test_attaching_a_sink_drains_what_was_kept_in_order() -> void:
    SaProblems.report("A", "first")
    SaProblems.report("B", "second")
    var seen: Array[String] = []
    SaProblems.attach_sink(func(line: String, _kind: SaProblems.Kind) -> void: seen.append(line))
    assert_eq(seen, ["A: first", "B: second"], "Delivered in the order reported")
    assert_true(SaProblems.pending.is_empty(), "and nothing is kept twice")

    SaProblems.report("C", "third")
    assert_eq(seen.size(), 3, "A report after the sink is up goes straight through")
    assert_true(SaProblems.pending.is_empty(), "rather than being kept")


## Boot failures reach the screen: what was kept shows in one dialog the moment
## the main window installs it.
func test_install_shows_the_kept_problems_in_one_dialog() -> void:
    SaProblems.report("GlobalShaderCompiler", "kernel 'x' did not compile.")
    SaProblems.report("SaTexture", "could not allocate a 256x256 texture.")
    SaMessage.install(_host)

    var dialog := SaMessage.problem_dialog()
    assert_not_null(dialog, "Installing makes the problem dialog")
    assert_true(dialog.visible, "and it opens at once, because there was something to show")
    assert_true(dialog.text_label.text.contains("kernel 'x'"), "with the first problem")
    assert_true(dialog.text_label.text.contains("256x256"), "and the second, in the same window")
    assert_eq(dialog.buttons.size(), 1, "A problem has one way out")
    assert_true(SaProblems.has_sink(), "and reports from now on go to it")

    _host.free()
    _host = null
    assert_false(SaProblems.has_sink(), "Freeing the host takes the sink with it")
    assert_null(SaMessage.problem_dialog(), "and forgets the dialog")


func test_a_problem_repeated_is_one_line_and_a_new_one_is_added() -> void:
    SaMessage.install(_host)
    SaProblems.report("SaTexture", "could not allocate")
    SaProblems.report("SaTexture", "could not allocate")
    SaProblems.report("SaCompute", "cannot run")
    var text := SaMessage.problem_dialog().text_label.text
    assert_eq(text.count("could not allocate"), 1, "The same fault sixty times is one line")
    assert_true(text.contains("cannot run"), "and a different one is another line")


func test_problems_past_the_cap_are_counted_rather_than_shown() -> void:
    SaMessage.install(_host)
    for i in SaMessage.MAX_LINES + 3:
        SaProblems.report("Src", "fault %d" % i)
    var text := SaMessage.problem_dialog().text_label.text
    assert_true(text.contains("fault %d" % (SaMessage.MAX_LINES - 1)), "The last line under the cap is shown")
    assert_false(text.contains("fault %d" % SaMessage.MAX_LINES), "the first one over it is not")
    assert_true(text.contains("3 more"), "and the window says how many it is not showing")


func test_dismissing_the_problem_dialog_starts_the_next_one_fresh() -> void:
    SaMessage.install(_host)
    SaProblems.report("Src", "old fault")
    var dialog := SaMessage.problem_dialog()
    dialog.buttons[0].pressed.emit()
    assert_false(dialog.visible, "OK closes it")

    SaProblems.report("Src", "new fault")
    assert_true(dialog.visible, "A later problem opens it again")
    assert_false(dialog.text_label.text.contains("old fault"), "without the one already dismissed")


func test_ask_answers_with_the_button_pressed() -> void:
    var dialog := _dialog()
    var answers: Array[int] = []
    dialog.ask(
        "Unsaved", "Save first?", PackedStringArray(["Save", "Discard", "Cancel"]), func(i: int) -> void: answers.append(i)
    )
    assert_eq(dialog.buttons.size(), 3, "One button per label")
    assert_eq(dialog.buttons[1].text, "Discard", "in the order given")
    assert_true(dialog.visible, "and the question is up")

    dialog.buttons[1].pressed.emit()
    assert_eq(answers, [1], "The answer is the index of the button pressed")
    assert_false(dialog.visible, "and the window closes")

    dialog.buttons[0].pressed.emit()
    assert_eq(answers, [1], "A second press after the answer changes nothing")


func test_the_default_button_takes_focus_so_enter_answers() -> void:
    var dialog := _dialog()
    dialog.ask("T", "text", PackedStringArray(["Yes", "No"]), func(_i: int) -> void: pass, -1, 1)
    dialog._focus_default()
    assert_eq(dialog.gui_get_focus_owner(), dialog.buttons[1], "The default button has focus, which is what Enter presses")


## Escape is an answer, not a silent close. Otherwise a quit prompt closed with
## the keyboard would leave the caller waiting forever.
func test_escape_answers_the_cancel_index() -> void:
    var dialog := _dialog()
    var answers: Array[int] = []
    dialog.ask("T", "text", PackedStringArray(["Save", "Discard", "Cancel"]), func(i: int) -> void: answers.append(i))
    # The router's step for a dialog, which reads the key from the window's
    # `window_input` before a `SpinBox`'s field could eat it. Every dialog
    # closes on Escape, so the question answers through its ×.
    ShortcutRouter.escape_in_a_dialog(_escape(), dialog)
    assert_eq(answers, [2], "Escape is the last button unless told otherwise")
    assert_false(dialog.visible, "and the window is gone")


func test_the_cancel_index_can_be_chosen() -> void:
    var dialog := _dialog()
    var answers: Array[int] = []
    dialog.ask("T", "text", PackedStringArray(["Cancel", "Quit"]), func(i: int) -> void: answers.append(i), 0)
    dialog.hide()
    assert_eq(answers, [0], "Hiding by any route answers the chosen cancel index")


func test_confirm_makes_a_window_and_frees_it_after_the_answer() -> void:
    var answers: Array[int] = []
    var dialog := SaMessage.confirm(_host, "T", "text", PackedStringArray(["OK"]), func(i: int) -> void: answers.append(i))
    assert_true(dialog.is_inside_tree(), "The question is parented to the host")
    dialog.buttons[0].pressed.emit()
    assert_eq(answers, [0], "answered")
    assert_true(dialog.is_queued_for_deletion(), "and on its way out, so nothing has to remember it")


## The notice is the other surface: a refusal says one line and takes it away
## again, with nothing to press. It exists because a stroke on a locked
## layer would otherwise do nothing at all, silently.
func test_a_refusal_says_one_line_in_the_corner() -> void:
    assert_null(SaMessage.notice_widget(), "There is no notice before the window installs one")
    SaMessage.notice("nobody is listening yet")

    SaMessage.install(_host)
    var notice := SaMessage.notice_widget()
    assert_not_null(notice, "Installing makes it")
    assert_false(notice.showing(), "and it says nothing until something is refused")

    EventBus.paint_refused.emit("This layer is locked.")
    assert_true(notice.showing(), "A refusal on the bus puts a line up")
    assert_true(notice.label.text.contains("locked"), "saying why")


## The fill with nothing selected is no refusal and says its line in the same
## corner, by a route of its own.
func test_a_corner_notice_says_its_line_without_being_a_refusal() -> void:
    SaMessage.install(_host)
    var notice := SaMessage.notice_widget()
    EventBus.corner_notice.emit("Nothing was selected, so the fill covered the whole layer.")
    assert_true(notice.showing(), "A line on the notice route puts one up")
    assert_true(notice.label.text.contains("whole layer"), "saying what it was given")


## A stroke refused at tablet rate is one message. The timer is restarted
## rather than a second panel added, so the line cannot stack into a wall.
func test_the_same_refusal_repeated_is_still_one_line() -> void:
    SaMessage.install(_host)
    var notice := SaMessage.notice_widget()
    for i in 40:
        EventBus.paint_refused.emit("This layer is locked.")
    assert_eq(notice.label.text, "This layer is locked.", "Forty refusals are one line")
    assert_eq(notice.panel.get_child_count(), 1, "in the one label the panel was built with")


## The whole point of the two doors: the sink is asked for the kind the call
## site gave, and never for the text. Both lines here read like a fault and one
## of them is a refusal, so a sink that guessed from the words would sort them
## together and put the refusal in a window over the canvas, which is the
## fault the two doors exist to prevent.
func test_the_sink_is_asked_for_the_kind_and_not_for_the_text() -> void:
    var kinds: Array[int] = []
    var lines: Array[String] = []
    SaProblems.attach_sink(
        func(line: String, kind: SaProblems.Kind) -> void:
            lines.append(line)
            kinds.append(int(kind))
    )

    SaProblems.report("SaFileMenu", "Could not open 'sky.sad' (File not found).")
    SaProblems.refuse("Patch", "Could not patch: there is no selection. Draw one first.")

    assert_eq(lines.size(), 2, "Both doors reach the one sink")
    assert_eq(kinds[0], int(SaProblems.Kind.FAULT), "report says fault")
    assert_eq(kinds[1], int(SaProblems.Kind.REFUSAL), "and refuse says refusal, though both lines say 'Could not'")


## The two records are kept apart before a sink exists, so the drain can send
## each to the surface it belongs on rather than to whichever one is first.
func test_a_refusal_before_the_window_is_kept_apart_from_the_faults() -> void:
    SaProblems.report("SaTexture", "could not allocate a 256x256 texture.")
    SaProblems.refuse("SaRecorder", "There is no canvas to record.")

    assert_eq(SaProblems.pending.size(), 1, "The fault is kept")
    assert_eq(SaProblems.pending_refusals.size(), 1, "and the refusal is kept in its own record")
    assert_true(SaProblems.pending_refusals[0].contains("no canvas"), "with who and what")

    var kinds: Array[int] = []
    SaProblems.attach_sink(func(_line: String, kind: SaProblems.Kind) -> void: kinds.append(int(kind)))
    assert_eq(kinds, [int(SaProblems.Kind.FAULT), int(SaProblems.Kind.REFUSAL)], "and each is drained as what it is")
    assert_true(SaProblems.pending_refusals.is_empty(), "with nothing kept twice")


## The note of 08:32:20, whole: a problem the painter can act on is the corner
## line, not a window with an OK button in it.
func test_a_refusal_goes_to_the_corner_and_leaves_the_window_shut() -> void:
    SaMessage.install(_host)
    SaProblems.refuse("Patch", "there is no selection to patch. Draw one first.")

    var notice := SaMessage.notice_widget()
    assert_true(notice.showing(), "The refusal is a line in the corner")
    assert_true(notice.label.text.contains("no selection to patch"), "saying what to do about it")
    assert_false(SaMessage.problem_dialog().visible, "and no window opened over the canvas")


## The other half, unchanged: a fault still grows the window, and it does it
## without saying anything in the corner.
func test_a_fault_opens_the_window_and_leaves_the_corner_quiet() -> void:
    SaMessage.install(_host)
    SaProblems.report("SaTexture", "could not allocate a 256x256 texture.")

    assert_true(SaMessage.problem_dialog().visible, "A fault is still the window")
    assert_true(SaMessage.problem_dialog().text_label.text.contains("256x256"), "with the line in it")
    assert_false(SaMessage.notice_widget().showing(), "and the corner stays quiet")


## Freeing the host takes the notice with it and forgets the connection, or the
## next install connects one callable twice and the engine says so.
func test_freeing_the_host_forgets_the_notice() -> void:
    SaMessage.install(_host)
    assert_true(EventBus.paint_refused.is_connected(SaMessage.notice), "Install listens for a refusal")
    assert_true(EventBus.corner_notice.is_connected(SaMessage.notice), "and for a line that is no refusal")
    _host.free()
    _host = null
    assert_null(SaMessage.notice_widget(), "Freeing the host forgets the notice")
    assert_false(EventBus.paint_refused.is_connected(SaMessage.notice), "and stops listening")
    assert_false(EventBus.corner_notice.is_connected(SaMessage.notice), "to both")


## A question up when a problem arrives is cancelled rather than overwritten
## under the pointer, and the problem then shows.
func test_a_problem_interrupts_a_question_as_a_cancel() -> void:
    SaMessage.install(_host)
    var dialog := SaMessage.problem_dialog()
    var answers: Array[int] = []
    dialog.ask("T", "text", PackedStringArray(["Go", "Stop"]), func(i: int) -> void: answers.append(i))
    SaProblems.report("Src", "fault")
    assert_eq(answers, [1], "The question was answered as cancelled")
    assert_true(dialog.visible, "and the problem is what is showing")
    assert_true(dialog.text_label.text.contains("fault"), "in words")


## The creation guards used to be asserts, which release builds strip. A kernel
## that does not compile now reports through the same door, with glslang's
## message, so the painter sees it rather than an empty canvas.
func test_a_kernel_that_does_not_compile_is_reported() -> void:
    var source := "#version 450\nvoid main() { this is not glsl }"
    var rid: RID = GlobalShaderCompiler._compile_spirv(source, "test_kernel_broken")
    assert_false(rid.is_valid(), "No shader comes out of that")
    assert_eq(SaProblems.pending.size(), 1, "and the failure is reported once")
    assert_true(SaProblems.pending[0].contains("test_kernel_broken"), "naming the kernel")


func test_the_break_hook_only_touches_the_kernel_it_names() -> void:
    var previous: String = Compiler.KernelBreak.kernel
    Compiler.KernelBreak.kernel = "paint"
    assert_eq(Compiler.KernelBreak.apply("src", "clear_chunk"), "src", "Other kernels compile as written")
    assert_true(Compiler.KernelBreak.apply("src", "paint").contains("#error"), "the named one cannot")
    Compiler.KernelBreak.kernel = previous


## `SaDialogWindow._init_dialog` connects `visibility_changed` and this
## class overrides the method it connects to, so a second connect in `_init`
## named one method on one instance: the engine refused it and printed
## "already connected" on every launch and every quit.
##
## Counted rather than watched for the warning, because a `push_error` from the
## engine is not something a suite can assert on and the count is the fact
## underneath it.
func test_the_visibility_signal_is_connected_once() -> void:
    var dialog := SaMessage.new()
    _host.add_child(dialog)

    var mine := 0
    for entry: Dictionary in dialog.get_signal_connection_list(&"visibility_changed"):
        if (entry["callable"] as Callable).get_object() == dialog:
            mine += 1
    assert_eq(mine, 1, "One connection to this window's own handler, not two")

    dialog.queue_free()
