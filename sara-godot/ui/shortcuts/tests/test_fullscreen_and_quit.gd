## The Window menu's Fullscreen row and the File menu's Quit row.
##
## Neither claim can be proved by looking at a window in this suite: a headless
## run has a dummy DisplayServer that accepts `window_set_mode` and reports the
## mode back unchanged, so the real toggle is the scenario's job. What is tested
## here is what a display cannot answer either way: the mode arithmetic, that
## the Quit row asks rather than quits, and that the fullscreen command exists
## with a chord on it so the Keyboard Shortcuts page can list and rebind it.
extends "res://tests/test_framework.gd"


## Windowed goes to fullscreen and fullscreen comes back to whatever it left.
func test_fullscreen_goes_out_and_comes_back_to_the_mode_it_left() -> void:
    assert_eq(
        SaAppCommands.fullscreen_target(DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_WINDOWED),
        DisplayServer.WINDOW_MODE_FULLSCREEN,
        "A windowed window goes fullscreen"
    )
    assert_eq(
        SaAppCommands.fullscreen_target(DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_WINDOWED),
        DisplayServer.WINDOW_MODE_WINDOWED,
        "and a fullscreen one comes back"
    )


## The reason the restore mode is remembered rather than assumed. A painter who
## maximised the window and then went fullscreen would otherwise get a small
## floating rectangle back, which reads as the toggle having lost their layout.
func test_a_maximised_window_comes_back_maximised() -> void:
    assert_eq(
        SaAppCommands.fullscreen_target(DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_MAXIMIZED),
        DisplayServer.WINDOW_MODE_MAXIMIZED,
        "The mode it left is the mode it returns to"
    )
    assert_eq(
        SaAppCommands.fullscreen_target(DisplayServer.WINDOW_MODE_MAXIMIZED, DisplayServer.WINDOW_MODE_WINDOWED),
        DisplayServer.WINDOW_MODE_FULLSCREEN,
        "and maximised is not fullscreen, so it toggles out rather than in"
    )


## Exclusive fullscreen is the mode a window manager can hand back without
## Sara ever asking for it, and reading it as "not fullscreen" would make the
## toggle push further out instead of coming back.
func test_exclusive_fullscreen_counts_as_fullscreen() -> void:
    assert_eq(
        SaAppCommands.fullscreen_target(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN, DisplayServer.WINDOW_MODE_WINDOWED),
        DisplayServer.WINDOW_MODE_WINDOWED,
        "Either fullscreen mode toggles back out"
    )


## A stand-in for the main window that does what a real desktop does, which the
## headless DisplayServer will not. It honours a request unless it is told to
## lose the returns, which replays a real fault: the window is asked for
## maximised on its way out of fullscreen and says windowed instead.
class FakeDisplay:
    extends RefCounted

    signal frame

    var mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_MAXIMIZED
    var requests: Array[int] = []

    ## How many requests for maximised it answers with windowed.
    var lose_returns: int = 0

    func get_mode() -> DisplayServer.WindowMode:
        return mode

    func set_mode(requested: DisplayServer.WindowMode) -> void:
        requests.append(requested)
        if requested == DisplayServer.WINDOW_MODE_MAXIMIZED and lose_returns > 0:
            lose_returns -= 1
            mode = DisplayServer.WINDOW_MODE_WINDOWED
            return
        mode = requested


func _toggle_over(display: FakeDisplay) -> SaAppCommands.Fullscreen:
    return SaAppCommands.Fullscreen.new(display.get_mode, display.set_mode)


## The two ways round. From a maximised window and from a
## windowed one, F11 goes fullscreen and the second press gives the same mode
## back.
func test_f11_twice_from_a_maximised_window_leaves_it_maximised() -> void:
    var display := FakeDisplay.new()
    var toggle := _toggle_over(display)

    toggle.toggle()
    assert_eq(display.mode, DisplayServer.WINDOW_MODE_FULLSCREEN, "The first press fills the screen")
    toggle.toggle()
    assert_eq(display.mode, DisplayServer.WINDOW_MODE_MAXIMIZED, "and the second gives back the maximised window")
    toggle.settle()
    assert_eq(display.requests.size(), 2, "with no third ask, since the window took it")


func test_f11_twice_from_a_windowed_window_leaves_it_windowed() -> void:
    var display := FakeDisplay.new()
    display.mode = DisplayServer.WINDOW_MODE_WINDOWED
    var toggle := _toggle_over(display)

    toggle.toggle()
    assert_eq(display.mode, DisplayServer.WINDOW_MODE_FULLSCREEN, "The first press fills the screen")
    toggle.toggle()
    assert_eq(display.mode, DisplayServer.WINDOW_MODE_WINDOWED, "and the second gives back the windowed one, not a maximised one")


## The mode is read on every way in rather than once, so a painter who
## un-maximises between two fullscreens is not sent back to maximised, and one
## who maximises is not sent back to windowed.
func test_the_mode_left_is_remembered_afresh_each_time() -> void:
    var display := FakeDisplay.new()
    var toggle := _toggle_over(display)

    toggle.toggle()
    toggle.toggle()
    assert_eq(display.mode, DisplayServer.WINDOW_MODE_MAXIMIZED, "Maximised comes back maximised")

    display.mode = DisplayServer.WINDOW_MODE_WINDOWED
    toggle.toggle()
    toggle.toggle()
    assert_eq(display.mode, DisplayServer.WINDOW_MODE_WINDOWED, "then a window the painter un-maximised comes back windowed")

    display.mode = DisplayServer.WINDOW_MODE_MAXIMIZED
    toggle.toggle()
    toggle.toggle()
    assert_eq(display.mode, DisplayServer.WINDOW_MODE_MAXIMIZED, "and one they maximised again comes back maximised")


## A window that is already fullscreen when the first press comes, from the
## command line or the desktop, was never seen leaving anything. It comes back
## windowed, which is the one mode that is always a mode to be in, and the
## exclusive kind counts the same as the plain one.
func test_a_fullscreen_nobody_saw_begin_comes_back_windowed() -> void:
    for start: DisplayServer.WindowMode in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
        var display := FakeDisplay.new()
        display.mode = start
        var toggle := _toggle_over(display)

        toggle.toggle()
        assert_eq(
            display.mode, DisplayServer.WINDOW_MODE_WINDOWED, "The first press leaves fullscreen mode %d for windowed" % start
        )


## The fault of step 13 as a display can make it: the window is asked for
## maximised, says windowed, and the toggle asks again on the next frame.
func test_a_return_the_window_does_not_keep_is_asked_for_again() -> void:
    var display := FakeDisplay.new()
    display.lose_returns = 1
    var toggle := _toggle_over(display)

    toggle.toggle()
    toggle.toggle()
    assert_eq(display.mode, DisplayServer.WINDOW_MODE_WINDOWED, "The second press is answered with windowed, which is the fault")

    toggle.settle()
    assert_eq(display.mode, DisplayServer.WINDOW_MODE_MAXIMIZED, "and the frame after it asks again and gets maximised")
    toggle.settle()
    assert_eq(display.requests.size(), 3, "Once it holds nothing more is asked")


## A window that refuses every time is asked twice more and then left alone, so
## a compositor that keeps its own counsel does not get a request a frame for
## as long as Sara runs.
func test_a_window_that_never_keeps_it_is_given_up_on() -> void:
    var display := FakeDisplay.new()
    display.lose_returns = 99
    var toggle := _toggle_over(display)

    toggle.toggle()
    toggle.toggle()
    for _frame in 6:
        toggle.settle()

    assert_eq(
        display.requests.size(), 2 + SaAppCommands.Fullscreen.RETRIES, "Two presses and the retries the toggle allows itself"
    )
    assert_eq(display.mode, DisplayServer.WINDOW_MODE_WINDOWED, "and the window is left where it says it is")


## The frame is a signal the toggle listens to only while a return is owed, so
## Sara does not run a callback every frame of a session for one key.
func test_the_toggle_listens_to_the_frame_only_while_a_return_is_owed() -> void:
    var display := FakeDisplay.new()
    display.lose_returns = 1
    var toggle := SaAppCommands.Fullscreen.new(display.get_mode, display.set_mode, display.frame)

    toggle.toggle()
    assert_eq(display.frame.get_connections().size(), 0, "Going in owes nothing, so nothing listens")
    toggle.toggle()
    assert_eq(display.frame.get_connections().size(), 1, "Coming out owes the mode that was left")

    display.frame.emit()
    assert_eq(display.mode, DisplayServer.WINDOW_MODE_MAXIMIZED, "and the next frame asks again on its own")
    display.frame.emit()
    assert_eq(display.frame.get_connections().size(), 0, "then the toggle stops listening once the window holds it")


## Another door, the desktop's own chord or the window menu, may put the window
## back into fullscreen before the frame that checks the return. That return
## is not owed any more, and asking for it would undo the painter's press.
func test_a_return_another_door_undid_is_not_asked_for() -> void:
    var display := FakeDisplay.new()
    var toggle := _toggle_over(display)

    toggle.toggle()
    toggle.toggle()
    display.mode = DisplayServer.WINDOW_MODE_FULLSCREEN
    toggle.settle()

    assert_eq(display.mode, DisplayServer.WINDOW_MODE_FULLSCREEN, "The window stays as the other door left it")
    assert_eq(display.requests.size(), 2, "with nothing asked for after the two presses")


## The command, not an action added to `project.godot` by hand. The registry
## builds the InputMap action itself, and a command is what the Keyboard
## Shortcuts page lists and rebinds.
func test_fullscreen_is_a_command_with_a_chord() -> void:
    var registries := SaRegistries.new()
    registries.build_context(Callable(), Callable())
    SaAppCommands.register_all(registries, Callable())
    var commands := registries.commands

    assert_true(commands.has(&"window_fullscreen"), "The command is registered")
    assert_true(commands.has_chord(&"window_fullscreen"), "and it answers to a key")
    assert_eq(commands.chord_text(&"window_fullscreen"), "F11", "on the key the rest of the desktop uses, alone (N10)")

    var descriptor := commands.get_descriptor(&"window_fullscreen")
    assert_eq(descriptor.default_events.size(), 1, "One chord, since Krita's second chord is not shipped")
    assert_eq(descriptor.default_events[0].keycode, KEY_F11, "and it is F11")
    assert_false(descriptor.default_events[0].ctrl_pressed, "the bare key, with nothing held")

    # The InputMap and not the descriptor, because the router dispatches on the
    # action: a chord that is only in `default_events` is a chord the app does
    # not answer to. This is the half no screenshot can show, the window mode
    # itself being the compositor's.
    var f11 := SaAppCommands.chord(KEY_F11)
    assert_true(InputMap.event_is_action(f11, &"window_fullscreen"), "A bare F11 is the fullscreen action")
    assert_eq(descriptor.title, "Fullscreen", "The title is what the menu row and the shortcuts page show")
    assert_eq(String(descriptor.category), "window", "under the Window category")


## The Quit row asks main rather than calling `get_tree().quit()` itself. Main
## is the only node that knows whether the recovery copy has done its job, and
## the unsaved-changes prompt has to stay in one place.
##
## The ask is deferred, which is the half this can check: a dialog opened while
## the popup is still mid-hide desynchronises the engine's popup bookkeeping,
## and the Edit menu learned that before this row existed. Nothing has emitted
## by the time `on_id_pressed` returns, and the prompt itself is what the
## scenario photographs.
func test_the_quit_row_asks_rather_than_quits() -> void:
    var popup := SaChoicePopup.new()
    var menu := SaFileMenu.new(popup)
    var asked := [0]
    var listener := func() -> void: asked[0] += 1
    EventBus.quit_requested.connect(listener)

    menu.on_id_pressed(SaFileMenu.ID_QUIT)

    assert_eq(asked[0], 0, "The row queues the ask rather than emitting inside the popup's own handler")
    assert_true(EventBus.quit_requested.get_connections().size() > 0, "and the signal the row queues is a real one")

    EventBus.quit_requested.disconnect(listener)
    popup.free()
