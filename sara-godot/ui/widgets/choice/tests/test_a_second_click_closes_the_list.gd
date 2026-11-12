## A second click on an open dropdown's button closes it.
##
## A second click on the blend mode dropdown reopened it instead of closing it.
## The click outside the list closes it on the press, deferred, and a `Button`
## answered on the release, by which time the list was gone and the button
## opened it again. Both dropdown classes stand on `SaDropdownButton` now, which
## answers on the press, the way an `OptionButton` does, and remembers the frame
## its list was hidden in so a press in that frame is the close and not a reopen.
##
## `scenarios/a-second-click-on-an-open-dropdown-closes-it.json` is the
## running app: a press and a release two frames apart on each button, twice,
## with the open lists dumped after each.
##
## **A guard out of the tree proves nothing**. The frame guard's
## test built the button outside any tree, and `SaChoicePopup.open_under` returns
## at once for a popup that is not in one, so the list was never visible and the
## same assertion passed with the guard deleted. The fixture stands in a tree
## now, so a guard-less `toggle_list()` opens a window the test can see.
##
## **The frame after the close is a scenario's to ask.** A synchronous suite
## cannot advance a frame, and a test that awaits one drops every assertion
## after the await. The suite below holds the same frame, and
## `scenarios/the-frame-guard-of-the-second-click.json` asks the running app
## what a toggle on a later frame does, which is the half that says the guard is
## not a latch.
extends "res://tests/test_framework.gd"

## A real `Window` goes in the tree, the second test opening one.
const REQUIRES_GPU := true


func test_both_dropdowns_answer_on_the_press() -> void:
    for button: SaDropdownButton in [SaChoiceButton.new(), BlendModeButton.new()]:
        assert_eq(
            button.action_mode,
            BaseButton.ACTION_MODE_BUTTON_PRESS,
            "%s opens and closes its list on the press, the frame the outside click closes it in" % button.get_class()
        )
        assert_eq(button.focus_mode, Control.FOCUS_NONE, "and still takes no focus")
        assert_not_null(button.popup, "and carries its list")
        button.free()


## The frame guard: a press in the frame the list was hidden in is that same
## close and not a reopen, and the press answers on the button's own signal
## because that is what a hand does.
##
## The third press is the one the guard is for. With the button in the tree a
## press with no guard opens the list again, so the assertion fails when
## `closed_this_frame()` is short-circuited, which it did not while the fixture
## was detached.
func test_a_press_in_the_frame_the_list_closed_in_is_the_close() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This suite needs the real scene tree to open a window in")
    if tree == null:
        return

    # Embedding forced for the reason `test_windows_open.gd` gives: a Window
    # added to a root that does not embed maps an OS window and the run blocks
    # until the watchdog fires. It is a user setting, so it is put back after.
    var previous_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true

    # Not `tree.root`, which is mid-`_ready` when a suite runs.
    var host := Control.new()
    host.name = "B2SecondClickHost"
    EventBus.add_child(host)

    var button := SaChoiceButton.new()
    button.set_choices([{"id": 1, "label": "First"}, {"id": 2, "label": "Second"}])
    host.add_child(button)

    assert_false(button.closed_this_frame(), "A list never hidden was not hidden this frame")

    button.pressed.emit()
    assert_true(button.popup.visible, "A press on the closed list opens it")

    button.pressed.emit()
    assert_false(button.popup.visible, "A press on the open list closes it")
    assert_true(button.closed_this_frame(), "and the frame of the hide is remembered")

    button.pressed.emit()
    assert_false(button.popup.visible, "and a second press in that frame is the close, not a reopen")

    host.free()
    tree.root.gui_embed_subwindows = previous_embedding
