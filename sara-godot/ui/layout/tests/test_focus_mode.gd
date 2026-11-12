## Tab hides the dockers that were open, brings back those and no others, and
## is left alone wherever something else is focused.
##
## All three are bugs to keep out. Tabbing back must not show every docker
## Sara has, including the ones the painter had closed. Tab pressed in the
## unsaved-changes dialog to move from Save to Discard must not hide the dockers
## as well. And once the first Tab has left the focus on a top bar button, the
## second must toggle back instead of walking the buttons.
extends "res://tests/test_framework.gd"

## Where a docker stood, in the host window's space, and a click on either side
## of its edge.
const STOOD := Rect2(Vector2(700.0, 100.0), Vector2(220.0, 140.0))
const INSIDE := Vector2(760.0, 150.0)
const OUTSIDE := Vector2(300.0, 300.0)


## Stand-ins for the docker table `ui/main/main.gd` hands the focus mode: an id and
## a Window, which is all `toggle()` reads. Detached on purpose, because a
## Window added to a headless tree hangs the run and nothing here needs one in
## the tree to carry a `visible` flag.
func _table(states: Dictionary) -> Array:
    var out: Array = []
    for docker_id: String in states:
        var window := Window.new()
        window.name = docker_id
        window.visible = states[docker_id]
        out.append({"id": docker_id, "node": window})
    return out


func _free_table(table: Array) -> void:
    for config: Dictionary in table:
        (config["node"] as Window).free()


func _visible(table: Array) -> Dictionary:
    var out: Dictionary = {}
    for config: Dictionary in table:
        out[config["id"]] = (config["node"] as Window).visible
    return out


func _tab() -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_TAB
    key.pressed = true
    return key


func before_each() -> void:
    SaFocusMode.active = false


func after_each() -> void:
    SaFocusMode.active = false


## The case that matters: the toolbox open, the colour docker closed, Tab twice, and
## the same two states. The old toggle showed everything on the way back.
func test_tab_twice_gives_back_the_dockers_that_were_open() -> void:
    var focus := SaFocusMode.new()
    var table := _table({"ToolBoxDocker": true, "ColorDocker": false, "LayersDocker": true})

    var hidden: Array = focus.toggle(table)
    assert_true(SaFocusMode.active, "The first Tab enters focus mode")
    assert_eq(hidden.size(), 2, "and reports the two it hid")
    for shown: bool in _visible(table).values():
        assert_false(shown, "with every docker hidden")

    var back: Array = focus.toggle(table)
    assert_false(SaFocusMode.active, "The second Tab leaves it")
    assert_eq(back.size(), 2, "and reports the two it showed")
    var after := _visible(table)
    assert_true(after["ToolBoxDocker"], "The toolbox is open again")
    assert_true(after["LayersDocker"], "and so are the layers")
    assert_false(after["ColorDocker"], "and the one that was closed stays closed")

    focus.free()
    _free_table(table)


## A pinned docker is neither hidden nor outlined, and the way
## back shows only what the first Tab hid. The pin itself, its button and the
## profile, is `test_a_pinned_docker_stays_through_tab.gd` beside this suite.
func test_a_pinned_docker_stays_shown_and_draws_no_outline() -> void:
    var focus := SaFocusMode.new()
    var table := _table({"SizeDocker": true, "ColorDocker": true})
    var hidden: Array = focus.toggle(table, {"SizeDocker": STOOD, "ColorDocker": STOOD}, ["ColorDocker"])
    assert_eq(hidden, ["SizeDocker"], "Tab hides the one that is not pinned")
    assert_true(_visible(table)["ColorDocker"], "and leaves the pinned one shown")
    assert_eq(focus._outlines.size(), 1, "with no outline over a docker that did not move")

    assert_eq(focus.toggle(table, {}, []), ["SizeDocker"], "The way back shows what was hidden, whatever the pins say now")
    assert_true(_visible(table)["SizeDocker"], "so the hidden one is back")
    assert_true(_visible(table)["ColorDocker"], "and the pinned one never left")
    focus.free()
    _free_table(table)


## Nothing open means nothing to come back to, so entering would be a state the
## next Tab could not leave.
func test_tab_with_every_docker_closed_does_not_enter_the_mode() -> void:
    var focus := SaFocusMode.new()
    var table := _table({"ToolBoxDocker": false, "ColorDocker": false})
    assert_true(focus.toggle(table).is_empty(), "Nothing changed")
    assert_false(SaFocusMode.active, "and the mode was not entered")
    focus.free()
    _free_table(table)


## The main window keeps its focused control's Tab, which is how the unsaved
## changes dialog was walked before the router declined a dialog outright, and a
## docker gives the Tab to the mode whatever holds the focus but a text field
## (the cases are in `test_tab_in_a_docker_toggles_the_dockers.gd`).
func test_a_focused_control_keeps_its_own_tab() -> void:
    var button := Button.new()
    assert_true(ShortcutRouter._focus_blocks_tab(button, false), "A button focused in the main window keeps Tab")
    assert_false(ShortcutRouter._focus_blocks_tab(button, true), "and one focused in a docker does not")
    button.free()

    assert_false(ShortcutRouter._focus_blocks_tab(null, false), "Nothing focused means the canvas has it")
    assert_false(ShortcutRouter._focus_blocks_tab(null, true), "in a docker too")

    var canvas := SaCanvas.new()
    assert_false(ShortcutRouter._focus_blocks_tab(canvas, false), "and the canvas itself is where the mode belongs")
    canvas.free()

    var line := LineEdit.new()
    assert_true(ShortcutRouter._focus_blocks_tab(line, true), "A text field keeps Tab in a docker")
    assert_true(ShortcutRouter._focus_blocks_tab(line, false), "and in the main window")
    line.free()


## End to end through the router, which is where the two halves meet: the same
## Tab event reaches the toggle from an unfocused main window and does not from
## a focused one.
func test_the_main_window_only_toggles_when_nothing_is_focused() -> void:
    var host := Node.new()
    host.name = "FocusModeTestHost"
    EventBus.add_child(host)
    var viewport := SubViewport.new()
    host.add_child(viewport)
    var button := Button.new()
    viewport.add_child(button)

    var toggles := [0]
    var router := ShortcutRouter.new()
    router.toggle_all_dockers = func() -> void: toggles[0] += 1

    router.handle_viewport_input(_tab(), viewport)
    assert_eq(toggles[0], 1, "With nothing focused, Tab is the mode")

    button.grab_focus()
    assert_eq(viewport.gui_get_focus_owner(), button, "The button really holds the focus")
    router.handle_viewport_input(_tab(), viewport)
    assert_eq(toggles[0], 1, "and with a button focused in the main window it is focus traversal, so the dockers are untouched")

    # ShortcutRouter is a Node, and one built here is never in the tree, so it
    # is freed by hand or the run ends with leaked objects.
    router.free()
    host.free()


func _click(at: Vector2, pressed: bool = true, button: MouseButton = MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = button
    event.pressed = pressed
    event.position = at
    return event


## Tab hides the dockers, and a click at once where one stood is the click
## the painter aimed at it a moment ago. It is swallowed while the outline of
## the docker shows, and the outline flashes.
func test_a_press_inside_a_hidden_dockers_place_is_swallowed_at_once() -> void:
    var focus := SaFocusMode.new()
    var table := _table({"SizeDocker": true})
    focus.toggle(table, {"SizeDocker": STOOD})
    assert_true(focus.outlines_showing(), "Tab outlines where the docker stood")

    assert_true(focus.swallows(_click(INSIDE)), "A press inside the outline is swallowed")
    assert_true(focus.swallows(_click(INSIDE, false)), "and so is the release that ends it, or the canvas is handed half a click")
    assert_false(focus.swallows(_click(INSIDE, false)), "but a release nobody pressed is the canvas's")

    focus.free()
    _free_table(table)


func test_a_press_outside_every_place_paints_at_once() -> void:
    var focus := SaFocusMode.new()
    var table := _table({"SizeDocker": true})
    focus.toggle(table, {"SizeDocker": STOOD})

    assert_false(focus.swallows(_click(OUTSIDE)), "A press outside every rectangle is the canvas's at once")
    assert_false(focus.swallows(_click(OUTSIDE, false)), "and so is its release")
    assert_false(focus.swallows(_click(INSIDE, true, MOUSE_BUTTON_RIGHT)), "and a right press is not a paint")

    focus.free()
    _free_table(table)


## After the fade the canvas paints there as it always did, which is the half of
## the behaviour that keeps hiding a docker worth doing.
func test_after_the_fade_the_place_paints_again() -> void:
    var focus := SaFocusMode.new()
    var table := _table({"SizeDocker": true})
    focus.toggle(table, {"SizeDocker": STOOD})

    focus._process(SaFocusMode.OUTLINE_SECONDS * 0.5)
    assert_true(focus.outlines_showing(), "Half way through, the outline still shows")
    assert_true(focus.swallows(_click(INSIDE)), "and still takes a press")
    focus.swallows(_click(INSIDE, false))

    focus._process(SaFocusMode.OUTLINE_SECONDS * 0.6)
    assert_false(focus.outlines_showing(), "Past the fade the outline is gone")
    assert_false(focus.swallows(_click(INSIDE)), "and the place paints as it does now")

    focus.free()
    _free_table(table)


## A press swallowed at the very end of the fade is let go of as it began, so a
## drag that follows it is not left half taken and a later click is not eaten.
func test_a_swallowed_press_is_let_go_of_by_its_release_after_the_fade() -> void:
    var focus := SaFocusMode.new()
    var table := _table({"SizeDocker": true})
    focus.toggle(table, {"SizeDocker": STOOD})
    assert_true(focus.swallows(_click(INSIDE)), "The press is swallowed")

    focus._process(SaFocusMode.OUTLINE_SECONDS + 0.1)
    assert_true(focus.swallows(_click(INSIDE, false)), "its release is too, though the outline has gone")
    assert_false(focus.swallows(_click(INSIDE)), "and the next press is the canvas's")

    focus.free()
    _free_table(table)


## The flash is a brightening and never a second of extra life: a painter
## clicking at it over and over gets the canvas back when the fade is up.
func test_a_flash_does_not_lengthen_the_outline() -> void:
    var focus := SaFocusMode.new()
    var table := _table({"SizeDocker": true})
    focus.toggle(table, {"SizeDocker": STOOD})

    focus._process(SaFocusMode.OUTLINE_SECONDS * 0.9)
    focus.swallows(_click(INSIDE))
    focus.swallows(_click(INSIDE, false))
    focus._process(SaFocusMode.OUTLINE_SECONDS * 0.2)
    assert_false(focus.outlines_showing(), "A flash at 0.9 of the fade leaves the fade its end")

    focus.free()
    _free_table(table)


## The painter found a second too slow, so the outline lasts half of one:
## at a quarter of a second it is about half strength, and at 0.6 s it is gone.
## Absolute seconds on purpose, so the case fails if the constant drifts back.
func test_the_outline_is_half_strength_at_a_quarter_second_and_gone_at_0_6() -> void:
    var focus := SaFocusMode.new()
    var table := _table({"SizeDocker": true})
    focus.toggle(table, {"SizeDocker": STOOD})

    focus._process(0.25)
    var fade: float = focus._left / SaFocusMode.OUTLINE_SECONDS
    assert_true(absf(fade - 0.5) < 0.05, "At 0.25 s the outline is about half strength, read %.3f" % fade)
    assert_true(focus.swallows(_click(INSIDE)), "A press at 0.25 s is still swallowed")
    assert_true(focus._flash > 0.0, "and lights its flash")
    focus.swallows(_click(INSIDE, false))

    focus._process(0.35)
    assert_false(focus.outlines_showing(), "At 0.6 s the outline is gone")
    assert_false(focus.swallows(_click(INSIDE)), "and the place paints")

    focus.free()
    _free_table(table)


## A press in the last tenth of the half second still finds its outline and its
## flash, which the end of the fade cuts short rather than lengthening it.
func test_a_press_late_in_the_half_second_still_flashes() -> void:
    var focus := SaFocusMode.new()
    var table := _table({"SizeDocker": true})
    focus.toggle(table, {"SizeDocker": STOOD})

    focus._process(0.42)
    assert_true(focus.swallows(_click(INSIDE)), "A press at 0.42 s is swallowed")
    assert_eq(focus._flashing, 0, "and flashes the outline it landed in")
    focus.swallows(_click(INSIDE, false))
    focus._process(0.1)
    assert_false(focus.outlines_showing(), "The flash leaves the fade its end at 0.5 s")

    focus.free()
    _free_table(table)


## Tabbing back shows the dockers, so nothing is left to swallow for.
func test_tabbing_back_takes_the_outlines_away() -> void:
    var focus := SaFocusMode.new()
    var table := _table({"SizeDocker": true})
    focus.toggle(table, {"SizeDocker": STOOD})
    focus.toggle(table, {})
    assert_false(focus.outlines_showing(), "The second Tab ends the outlines")
    assert_false(focus.swallows(_click(INSIDE)), "and a press where the docker is again is the docker's business")

    focus.free()
    _free_table(table)


## A docker that had no place to ask, or a closed one, outlines nothing.
func test_a_docker_with_no_place_and_a_closed_one_outline_nothing() -> void:
    var focus := SaFocusMode.new()
    var table := _table({"SizeDocker": true, "ColorDocker": false})
    focus.toggle(table, {"ColorDocker": STOOD, "SizeDocker": Rect2()})
    assert_false(focus.outlines_showing(), "A docker with no area, and one that was closed, give no outline")
    assert_false(focus.swallows(_click(INSIDE)), "so nothing is swallowed")

    focus.free()
    _free_table(table)


## The Info docker's line.
func test_the_status_line_reads_on_and_off() -> void:
    assert_eq(SaFocusMode.status_text(), "off", "Off by default")
    SaFocusMode.active = true
    assert_eq(SaFocusMode.status_text(), "on", "and on inside the mode")
