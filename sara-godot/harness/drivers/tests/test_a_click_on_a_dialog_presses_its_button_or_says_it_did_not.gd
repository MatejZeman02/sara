## A scenario's click on a dialog presses its button or says it did not.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A script's click on Later in
## the "Recovered work" question answered `ok: true` and "in main", and the
## question stood on. Measured on the running app, the click had pressed Later,
## and what stood on was the boot's second question, one per recovery copy, in
## the first one's place. So the click's line now names the dialog the point
## lands on, embedded or not, the button it pressed and each dialog the press
## opened, and a click on a dialog that pressed nothing is an error, which a
## door's answer carries in `errors`.
##
## The question is built by `confirm` with the recovery's title and its three
## labels under a host of this suite's own, the way
## `ui/dialogs/tests/test_second_question_behind_the_first.gd` builds its pair.
## Only with the root embedding, because a suite that adds a `Window` while the
## root does not maps a real window and stalls the run. A window of its own is
## the capture's half,
## `scenarios/a-click-that-lands-on-a-dialog-presses-its-button-or-says-it-did-not.json`.
## A test function cannot await a frame, and the click flushes what it parsed
## itself, so everything here is read straight after the step.
extends "res://tests/test_framework.gd"

const InputDriver := preload("res://harness/drivers/sa_input_driver.gd")
const PointerAim := preload("res://harness/drivers/aim/sa_pointer_aim.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")

const TITLE := "Recovered work"
const LATER := 2

var _previous_embedding: bool = true
var _host: Node = null
var _driver: SaInputDriver = null
## Every index a question answered, in order.
var _answers: Array[int] = []


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "D21ClickTestHost"
    EventBus.add_child(_host)
    _driver = InputDriver.new(CaptureRun.new())
    _answers = []


## Every question still up is closed rather than left for the host's free, for
## the reason `ui/dialogs/tests/test_second_question_behind_the_first.gd`
## gives: a window freed under `confirm`'s connection leaks its viewport's RIDs.
func after_each() -> void:
    _driver = null
    var tree := Engine.get_main_loop() as SceneTree
    for _attempt in 4:
        if SaMessage.live_dialog(tree) == null:
            break
        SaMessage.capture_message(tree, {"close": "escape"})
    if _host != null:
        _host.free()
        _host = null
    tree.root.gui_embed_subwindows = _previous_embedding


## The recovery question, as `MainDialogs.offer_recoveries` asks it, with *then*
## run from its answer the way the boot raises the next copy's question.
func _ask(then: Callable = Callable()) -> SaMessage:
    var dialog := SaMessage.confirm(
        _host,
        TITLE,
        "Sara kept a recovery copy of an unsaved document from a session that did not end properly.",
        PackedStringArray(["Open", "Delete", "Later"]),
        func(index: int) -> void:
            _answers.append(index)
            if then.is_valid():
                then.call(),
        LATER,
        0
    )
    # Laid out by hand, the way the other dialog suites do it, because the app sorts
    # the row on the frame after the question opens and a suite cannot await
    # it. Unsorted, every button stands at the row's corner.
    _sort_children(dialog.content)
    dialog.fit_opening_size()
    _sort_children(dialog.content)
    return dialog


func _sort_children(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)


## *local*, a point in *dialog*'s own units, in root units, the arithmetic the
## driver aims a named control in an embedded window with.
func _in_root(dialog: Window, local: Vector2) -> Vector2:
    return Vector2(dialog.position) + dialog.get_final_transform() * local


## Clicks at *at* with a logger attached, and answers what it heard.
func _click(at: Vector2) -> SaErrorCatcher:
    var lines := SaErrorCatcher.new()
    OS.add_logger(lines)
    _driver.click({"at": [at.x, at.y]})
    OS.remove_logger(lines)
    return lines


func _naming(found: PackedStringArray, needle: String) -> PackedStringArray:
    var out := PackedStringArray()
    for line in found:
        if line.contains(needle):
            out.append(line)
    return out


## The filing. A click at Later's centre either answers the cancel index or
## raises an error naming the question, never neither and never both, and its
## line names the dialog rather than "main".
func test_a_click_at_laters_centre_answers_later_or_says_it_did_not() -> void:
    var dialog := _ask()
    var later := dialog.buttons[LATER]
    var lines := _click(_in_root(dialog, later.get_global_rect().get_center()))
    var said := _naming(lines.texts([SaErrorCatcher.ERROR]), TITLE)
    if _answers.is_empty():
        var caught := lines.texts([SaErrorCatcher.ERROR])
        assert_eq(said.size(), 1, "a press that did not land says so, naming the question: %s" % [caught])
    else:
        assert_eq(_answers.size(), 1, "the click answered the question once")
        assert_eq(_answers[0], LATER, "with Later, the cancel answer")
        assert_eq(said.size(), 0, "and a click that pressed its button raises nothing: %s" % [said])
    var clicks := _naming(lines.printed(), "SaCapture: click")
    assert_eq(clicks.size(), 1, "the click printed one line")
    if clicks.size() == 1:
        assert_true(clicks[0].contains('"%s" (%s)' % [TITLE, dialog.name]), "which names the dialog: %s" % clicks[0])
        assert_false(clicks[0].contains(" in main "), "and not the main window under it")
        assert_true(clicks[0].contains("'Later'"), "and the button the point was on")


## A click in the button row clear of every button pressed nothing, and the
## error names the question by its title and the step that answers it, with
## the button that route presses.
func test_a_click_beside_the_buttons_says_it_pressed_nothing() -> void:
    var dialog := _ask()
    var row := dialog.button_row.get_global_rect()
    var local := Vector2(row.position.x + 4.0, row.get_center().y)
    for button in dialog.buttons:
        assert_false(button.get_global_rect().has_point(local), "the point is clear of '%s'" % button.text)
    var lines := _click(_in_root(dialog, local))
    assert_eq(_answers.size(), 0, "nothing answered the question")
    var said := _naming(lines.texts([SaErrorCatcher.ERROR]), TITLE)
    assert_eq(said.size(), 1, "one error names the question: %s" % [lines.texts([SaErrorCatcher.ERROR])])
    if said.size() == 1:
        assert_true(said[0].contains("pressed nothing"), "and says the click pressed nothing: %s" % said[0])
        assert_true(said[0].contains('{"message": {"close": "escape"}}'), "and names the step that answers it")
        assert_true(said[0].contains("'Later'"), "and the button that route presses")
    assert_true(dialog.visible, "the question is still up")


## A click on a button that is off answers nothing and the error says why.
func test_a_click_on_a_disabled_button_says_it_is_disabled() -> void:
    var dialog := _ask()
    var open := dialog.buttons[0]
    open.disabled = true
    var lines := _click(_in_root(dialog, open.get_global_rect().get_center()))
    assert_eq(_answers.size(), 0, "a disabled Open answered nothing")
    var said := _naming(lines.texts([SaErrorCatcher.ERROR]), TITLE)
    assert_eq(said.size(), 1, "one error names the question: %s" % [lines.texts([SaErrorCatcher.ERROR])])
    if said.size() == 1:
        assert_true(said[0].contains("'Open' and it is disabled"), "and says the button is off: %s" % said[0])


## The fault itself: Later answers the first question, the second copy's
## question opens in its place, and the line says a question opened, so an
## script reads that the question in front of it is a new one.
func test_a_press_that_opens_the_next_question_names_it() -> void:
    var dialog := _ask(func() -> void: _ask())
    var lines := _click(_in_root(dialog, dialog.buttons[LATER].get_global_rect().get_center()))
    if _answers.is_empty():
        skip("the press did not land in this run, which the first case reports")
        return
    var clicks := _naming(lines.printed(), "SaCapture: click")
    assert_eq(clicks.size(), 1, "the click printed one line")
    if clicks.size() == 1:
        assert_true(clicks[0].contains("pressed 'Later', then \"%s\"" % TITLE), "naming the question it opened: %s" % clicks[0])
    assert_eq(_naming(lines.texts([SaErrorCatcher.ERROR]), TITLE).size(), 0, "and raises nothing, since Later was pressed")


## A point on an embedded dialog is the main window's to route to, and a
## click's report still names the dialog.
func test_an_embedded_dialog_is_found_only_when_asked_for() -> void:
    var dialog := _ask()
    var root := (Engine.get_main_loop() as SceneTree).root
    var at := _in_root(dialog, dialog.buttons[LATER].get_global_rect().get_center())
    assert_null(PointerAim.window_under(root, at), "an event over it is still the main window's")
    assert_eq(PointerAim.window_under(root, at, true), dialog, "and the report finds the dialog")
    var local := PointerAim.point_in(root, dialog, at)
    assert_eq(PointerAim.control_under(dialog, local), dialog.buttons[LATER], "and Later under the point")
    assert_eq(PointerAim.window_label(dialog), '"%s" (%s)' % [TITLE, dialog.name], "by its title and its name")
    assert_eq(PointerAim.window_label(null), "main", "and the main window as before")
