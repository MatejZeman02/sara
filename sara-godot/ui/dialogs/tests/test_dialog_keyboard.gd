## Where focus starts in a dialog, without building a dialog.
##
## Adding a `Window` to the tree in a headless test hangs
## in the engine, so the two statics that decide the
## Tab walk are tested on a plain Control tree. The controls are put in the real
## tree the way `test_sa_message.gd` does, because `is_visible_in_tree()` is
## false for a Control that has no tree and every one of them would then look
## unreachable. The rest, that Escape and Enter reach the dialog at all,
## is input routing and belongs to `scenarios/keyboard-reach.json`.
extends "res://tests/test_framework.gd"

var _host: Node = null


func before_each() -> void:
    _host = Node.new()
    _host.name = "DialogKeyboardTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


func test_a_control_that_takes_no_focus_is_not_in_the_tab_walk() -> void:
    var label := Label.new()
    _host.add_child(label)
    assert_false(SaDialogWindow.is_focusable(label), "A Label takes no focus")
    assert_false(SaDialogWindow.is_focusable(null), "and neither does nothing")

    var button := Button.new()
    _host.add_child(button)
    assert_true(SaDialogWindow.is_focusable(button), "A Button does")

    button.disabled = true
    assert_false(SaDialogWindow.is_focusable(button), "unless it is disabled")
    button.disabled = false

    button.focus_mode = Control.FOCUS_NONE
    assert_false(SaDialogWindow.is_focusable(button), "or has been taken out of the walk")
    button.focus_mode = Control.FOCUS_ALL

    button.hide()
    assert_false(SaDialogWindow.is_focusable(button), "or is not on screen, which is how a hidden options row is skipped")


func test_focus_starts_on_the_first_control_the_walk_would_reach() -> void:
    var root := Control.new()
    _host.add_child(root)
    var row := HBoxContainer.new()
    root.add_child(row)

    row.add_child(Label.new())
    var skipped := Button.new()
    skipped.focus_mode = Control.FOCUS_NONE
    row.add_child(skipped)
    var wanted := Button.new()
    wanted.name = "Wanted"
    row.add_child(wanted)
    row.add_child(Button.new())

    assert_eq(SaDialogWindow.first_focusable(root), wanted, "The first the walk can land on, past the label and the skipped one")
    assert_null(SaDialogWindow.first_focusable(null), "Nothing under nothing")


func test_a_dialog_with_nothing_focusable_leaves_focus_alone() -> void:
    var root := Control.new()
    _host.add_child(root)
    root.add_child(Label.new())
    var closed := Button.new()
    closed.focus_mode = Control.FOCUS_NONE
    root.add_child(closed)

    assert_null(SaDialogWindow.first_focusable(root), "A dialog of labels has nowhere to put the keyboard")
