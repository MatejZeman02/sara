## A second question raised behind the first has to be answerable too.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `MainDialogs.offer_recoveries` raises the next
## recovery prompt from the answer callback of the one before it, so for a
## moment two questions are children of the same host, and `SaMessage.confirm`
## calls both of them `Question`. Godot renames the second to keep the name
## unique, and `live_dialog` walked `find_children("Question", ...)`, which
## matches a name exactly: it answered "no message window is up to close" with a
## dialog on the screen, and every shot after it carried that dialog over the
## middle of the canvas.
##
## The shape here is `offer_recoveries`'s own and not the recovery prompt itself: two
## questions, the second raised from the first's answer, which is the thing that
## produces the renamed child. The recovery prompt needs two stale files in
## `user://autosave/` to reproduce and a suite that writes those is testing the
## fixture rather than the walk.
##
## The dialogs are built by `confirm` under a host of this suite's own and the
## closes go through `capture_message`, both for the reasons
## `test_message_close_by_button.gd` gives beside it.
extends "res://tests/test_framework.gd"

var _previous_embedding: bool = true
var _host: Node = null
## Every index the two questions answered, in order, so a test can say which one
## was closed rather than only that something was.
var _answers: Array[int] = []


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "D14QuestionTestHost"
    EventBus.add_child(_host)
    _answers = []


func after_each() -> void:
    # Every question still up is closed rather than left for the host's free to
    # take, because `confirm` connects `answered` to `queue_free` and a window
    # freed out from under that connection leaks its viewport's RIDs. The bound
    # is the number a test can raise, not a guess.
    var tree := Engine.get_main_loop() as SceneTree
    for _attempt in 4:
        if SaMessage.live_dialog(tree) == null:
            break
        _close()
    if _host != null:
        _host.free()
        _host = null
    tree.root.gui_embed_subwindows = _previous_embedding


## A question that raises *next* from its own answer, the way `offer_recoveries`
## chains one recovery prompt onto the last.
func _chained(label: String, next: Callable) -> SaMessage:
    return SaMessage.confirm(
        _host,
        label,
        label,
        PackedStringArray(["Open", "Delete", "Later"]),
        func(index: int) -> void:
            _answers.append(index)
            next.call(),
        2,
        0
    )


func _close() -> String:
    return SaMessage.capture_message(Engine.get_main_loop() as SceneTree, {"close": "escape"})


## The filing, as one run. Two questions, the second behind the first, and both
## have to close.
func test_the_second_question_closes_after_the_first() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var second: Array[SaMessage] = []
    _chained("First", func() -> void: second.append(_chained("Second", func() -> void: pass)))

    var said_first := _close()
    assert_eq(said_first, "SaCapture: message closed by escape, answered 2", "the first answers: %s" % said_first)
    assert_eq(_answers, [2] as Array[int], "and it is the first that answered")
    assert_eq(second.size(), 1, "which raised the second")
    assert_true(second[0].visible, "and the second is on the screen")

    var found := SaMessage.live_dialog(tree)
    assert_true(found == second[0], "the live dialog is the second question, whatever it is called")

    var said_second := _close()
    assert_eq(said_second, "SaCapture: message closed by escape, answered 2", "the second answers: %s" % said_second)
    assert_eq(_answers, [2, 2] as Array[int], "so both of them answered")
    assert_null(SaMessage.live_dialog(tree), "and nothing is left up")


## The name is the thing that was wrong, so it is worth asserting the second one
## really does get another. A run where Godot stopped renaming would make the
## test above pass for the wrong reason.
func test_the_second_question_is_not_called_question() -> void:
    var second: Array[SaMessage] = []
    var first := _chained("First", func() -> void: second.append(_chained("Second", func() -> void: pass)))
    _close()

    assert_eq(String(first.name), "Question", "the first keeps the name confirm gives it")
    assert_eq(second.size(), 1, "the second exists")
    assert_true(String(second[0].name) != "Question", "and Godot gave it another: %s" % second[0].name)


## The problem dialog still answers before the walk does, or a scenario that
## reported a problem would start closing whatever question the app has up.
## That precedence was the second of the three lines `live_dialog` reads in
## order, and widening the third must not move it.
func test_the_problem_dialog_still_answers_before_the_walk() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _chained("Raised by the app", func() -> void: pass)
    var problems := SaMessage.problem_dialog()
    if problems == null:
        # A headless suite has no `install`, so there is no problem dialog to
        # rank against. The walk's own order is what the case above covers.
        assert_true(true, "no problem dialog is installed in this run")
        return

    problems.show()
    assert_true(SaMessage.live_dialog(tree) == problems, "the problem dialog is reached first")
    problems.hide()
    assert_true(SaMessage.live_dialog(tree) != problems, "and the question behind it once it is down")


## A question `confirm` raised under a host is found by the walk even when the
## door has never opened one of its own, which is the ordinary case for
## everything Sara itself asks.
func test_a_question_the_app_raised_is_found_with_no_door_question_at_all() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var raised := _chained("Only one", func() -> void: pass)

    assert_true(SaMessage.live_dialog(tree) == raised, "the app's question is the live one")
    assert_eq(_close(), "SaCapture: message closed by escape, answered 2", "and it closes")
    assert_null(SaMessage.live_dialog(tree), "leaving nothing up")
