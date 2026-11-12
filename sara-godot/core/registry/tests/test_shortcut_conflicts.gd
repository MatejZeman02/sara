## E, and the conflict the Keyboard Shortcuts page reports over it, as the Preferences pages show it.
##
## `tool_eraser` and `brush_toggle_eraser` are both bound to E on purpose: the
## stamp-brush module registers a `brush_toggle_eraser` command whose handler
## toggles the brush's eraser mode when the brush is active and picks the
## Eraser tool when it is not, and `ShortcutRouter` tries the registered
## commands before the generic tool-switch loop that `tool_eraser` would
## otherwise reach, so the command always answers first. The page had no way
## to know the two were one gesture and marked both rows, which told a painter
## their map was broken while it was doing what it was built to do. The store has
## a table of the pairs it answers as one gesture, so the two are no
## longer a conflict with each other and a rebind moves both.
extends "res://tests/test_framework.gd"


func _source(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    return file.get_as_text() if file != null else ""


func test_the_two_eraser_actions_share_one_key() -> void:
    for action: StringName in [&"tool_eraser", &"brush_toggle_eraser"]:
        assert_true(InputMap.has_action(action), "%s is an action this build ships" % action)
    var tool_events := InputMap.action_get_events(&"tool_eraser")
    var toggle_events := InputMap.action_get_events(&"brush_toggle_eraser")
    assert_false(tool_events.is_empty(), "The Eraser tool answers to a key")
    assert_false(toggle_events.is_empty(), "and so does the brush's eraser toggle")
    var tool_key := tool_events[0] as InputEventKey
    var toggle_key := toggle_events[0] as InputEventKey
    assert_true(tool_key != null and toggle_key != null, "both by keyboard")
    assert_eq(tool_key.physical_keycode, KEY_E, "The Eraser tool is on E")
    assert_eq(toggle_key.physical_keycode, KEY_E, "and the brush toggle is on the same E")


func test_the_command_still_answers_both_the_toggle_and_the_switch() -> void:
    var source := _source("res://modules/sara-base-modules/stamp-brush/module.gd")
    var at := source.find("func _toggle_eraser(")
    assert_true(at != -1, "The command's handler lives with the tools it switches, not with the router")
    var stop := source.find("\nfunc ", at + 1)
    var body := source.substr(at, stop - at) if stop != -1 else source.substr(at)
    assert_true(body.contains("toggle_eraser()"), "toggling the brush when the brush is active")
    assert_true(body.contains('set_active_tool("eraser")'), "and picking the tool when it is not")


## The store knows the two are one gesture, which is what stops the page marking
## them. Written as the declaration rather than as the absence of a mark, because
## a pair that fell out of the table would otherwise read as a pass.
func test_the_store_declares_the_pair_as_one_gesture() -> void:
    assert_true(
        SaShortcutStore.paired_with(&"tool_eraser").has(&"brush_toggle_eraser"),
        "The Eraser tool is declared one gesture with the brush toggle"
    )
    assert_true(SaShortcutStore.paired_with(&"brush_toggle_eraser").has(&"tool_eraser"), "and the declaration reads both ways")
    assert_true(SaShortcutStore.paired_with(&"tool_brush").is_empty(), "and nothing else on the map is paired")


## The page painted both rows in the drag colour and hung "Also used by" on
## each, which scenarios/preferences.json photographed under
## shortcuts-rebound.png. A pair the router treats as one gesture is not
## something a painter has to act on.
##
## Asserting the marking would pin the bug in place, so this asserts its
## absence.
func test_a_deliberate_pair_is_not_drawn_as_a_conflict() -> void:
    var clashes := SaShortcutStore.all_conflicts()
    assert_false(clashes.has("tool_eraser"), "The Eraser tool's row is left alone")
    assert_false(clashes.has("brush_toggle_eraser"), "and so is the brush toggle's")


## A pair that came apart on a rebind would be two commands on two chords with
## the router still answering one branch, which is the same defect wearing the
## other face.
func test_a_rebind_moves_the_whole_pair() -> void:
    # The events themselves, not the chords they spell. `chords_for` reads only
    # what `chord_text` can name, so restoring through `set_chords` would erase
    # a binding it could not spell and leave E on nothing: the run after this one
    # failed in `test_ui_components`, three suites later, on a press of E that
    # reached no tool.
    var was: Dictionary = {}
    for action: StringName in [&"tool_eraser", &"brush_toggle_eraser"]:
        was[action] = InputMap.action_get_events(action).duplicate()

    # Alt+E, a chord nothing holds. Shift+E belongs to the Recent Presets docker,
    # and a rebind onto a held chord is a
    # conflict this case is not about.
    SaShortcutStore.set_chords(&"tool_eraser", ["Alt+E"])
    assert_eq(SaShortcutStore.chords_for(&"tool_eraser"), ["Alt+E"] as Array[String], "The rebound half moved")
    assert_eq(SaShortcutStore.chords_for(&"brush_toggle_eraser"), ["Alt+E"] as Array[String], "and the other half moved with it")
    assert_false(SaShortcutStore.all_conflicts().has("tool_eraser"), "and the pair is still not a conflict")

    for action: StringName in was:
        InputMap.action_erase_events(action)
        for event: InputEvent in was[action]:
            InputMap.action_add_event(action, event)
