## One press, one answer, where the maximise and the quick zoom share Ctrl+Space.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The docker maximise sits on Ctrl+Space, which `tool_zoom_quick` also
## holds, and the two are kept apart by focus. Only on its own side:
## `ShortcutRouter._maximise_focused` declines with nothing focused, so the chord
## does nothing over the canvas, but nothing kept the quick zoom off a focused
## docker. A painter who had clicked the Layers docker and then pressed
## Ctrl+Space got both, which showed as the navigate group's face turning from
## `pan` to `zoom` one chord later.
##
## The other half is what `SaShortcutStore` has to know for the
## shipped map to stay clean, which was one rule too wide: "a command never
## collides with a quick tool" also hid a command that had landed on Alt or Space
## by accident. That is `GESTURE_PAIRS` now, one named sharing rather than a
## class of them, and it is what most of this file is about.
##
## The half no headless run can show is the focused docker itself, because a
## `DockerWindow` in the tree maps a real OS window and hangs the runner, which
## is the reason `test_docker_maximise.gd` gives for the same split. That is
## `scenarios/ctrl-space-is-both-the-maximise-and-the-held-quick-zoom.json`.
extends "res://tests/test_framework.gd"


func _source(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    return file.get_as_text() if file != null else ""


## One function's body out of *source*, to the next one or to the end of the
## file. The last function in a file has no next one, and `find` answers -1
## there, which `substr` would read from the wrong length.
func _body(source: String, signature: String) -> String:
    var at := source.find(signature)
    if at == -1:
        return ""
    var next := source.find("\nfunc ", at + 1)
    return source.substr(at) if next == -1 else source.substr(at, next - at)


# --- What the page reports -----------------------------------------------------


func test_the_two_that_share_ctrl_space_are_declared_and_read_both_ways() -> void:
    assert_true(
        SaShortcutStore.gesture_paired_with(&"docker_maximise").has(&"tool_zoom_quick"),
        "The maximise is declared as sharing its key with the quick zoom"
    )
    assert_true(
        SaShortcutStore.gesture_paired_with(&"tool_zoom_quick").has(&"docker_maximise"), "and the declaration reads both ways"
    )
    assert_true(SaShortcutStore.gesture_paired_with(&"tool_pan_quick").is_empty(), "and no other quick tool shares one")


## The defect: the rule hid every command that had landed on a
## quick tool's key, not only the pair that was decided. Read from an action that
## is nothing to do with either, so what is being asked is "does the walk report
## the quick zoom at all".
func test_a_command_that_lands_on_a_quick_tools_key_is_reported_again() -> void:
    var clashing := SaShortcutStore.conflicts("Ctrl+Space", &"edit_undo")

    assert_true(clashing.has("tool_zoom_quick"), "The quick zoom is named to a command that took its key: %s" % str(clashing))
    assert_true(clashing.has("docker_maximise"), "and so is the maximise, which is on the same chord")


## And the one sharing that was decided is still not marked, or the Keyboard
## Shortcuts page would tell a painter their map is broken while it is doing what
## item 34 asked for.
func test_the_declared_pair_is_still_not_a_conflict() -> void:
    assert_true(
        SaShortcutStore.conflicts("Ctrl+Space", &"docker_maximise").is_empty(),
        "The maximise is clear of the quick zoom it shares the key with"
    )
    assert_true(
        SaShortcutStore.conflicts("Ctrl+Space", &"tool_zoom_quick").is_empty(), "and the quick zoom is clear of the maximise"
    )
    var clashes := SaShortcutStore.all_conflicts()
    assert_eq(clashes.keys().size(), 0, "so the shipped map still collides with nothing: %s" % str(clashes.keys()))


# --- What the router does with the press ---------------------------------------


func _router() -> ShortcutRouter:
    var router := ShortcutRouter.new()
    router.canvas_provider = func() -> SaCanvas: return null
    router.tool_machine_provider = func() -> ToolMachine: return null
    return router


func _key(keycode: Key, ctrl: bool, pressed: bool = true) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.ctrl_pressed = ctrl
    event.pressed = pressed
    return event


## Ctrl+Space over the canvas is the quick zoom and nothing else, which is the
## quick zoom's half of the split. Nothing is focused in a headless run, so this is the canvas case.
func test_the_quick_tools_keep_the_chord_when_no_window_holds_the_keyboard() -> void:
    var router := _router()
    EventBus.add_child(router)

    assert_false(router._focused_window_answers(_key(KEY_SPACE, true)), "nothing focused means the quick zoom keeps the press")

    router.free()


## Space is the quick pan and Alt the quick eyedropper, and neither is a chord a
## window answers, so a focused docker does not take them. Written down because
## the fix reads the press rather than the tool: a guard on "is a quick tool key"
## would have cost the pan its docker case, which the forwarder was built for.
func test_the_plain_held_keys_are_left_alone() -> void:
    var router := _router()
    EventBus.add_child(router)

    assert_false(router._focused_window_answers(_key(KEY_SPACE, false)), "a bare Space is nobody's window chord")
    assert_false(router._focused_window_answers(_key(KEY_ALT, false)), "and neither is Alt")
    assert_false(router._focused_window_answers(_key(KEY_SPACE, true, false)), "and a release is not a press")

    router.free()


## The forwarder asks before it hands the key over, which is the fix itself. A
## source claim, because the true branch of that question needs a focused
## subwindow and the scenario is where one exists.
func test_the_forwarder_stands_down_for_a_press_a_window_answers() -> void:
    var router := _source("res://ui/shortcuts/shortcut_router.gd")
    var body := _body(router, "func _forward_to_tool_machine(")

    assert_false(body.is_empty(), "The forwarder is where a key reaches the quick tools")
    assert_true(body.contains("_focused_window_answers(event)"), "and it asks whether a focused window answers the press first")
    assert_true(body.contains("return false"), "declining rather than forwarding when one does")


## The question is the one `_maximise_focused` asks, not a second reading of it,
## so the two can never disagree about which press the maximise takes.
func test_both_halves_read_the_same_focused_window() -> void:
    var router := _source("res://ui/shortcuts/shortcut_router.gd")
    for name: String in ["func _focused_window_answers(", "func _maximise_focused("]:
        var body := _body(router, name)
        assert_false(body.is_empty(), "%s is in the router" % name)
        assert_true(body.contains("SaDockerMaximise.focused_window(get_tree())"), "%s reads the focused window" % name)
