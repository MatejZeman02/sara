## Every action with a chord has a section on the Keyboard Shortcuts page.
##
## `SaShortcutRows.GROUPS` is a list of action prefixes, and the page draws a
## section per prefix and nothing else. A prefix missing from it is not an empty
## section: it is an action that answers to a key, appears nowhere in
## Preferences, and cannot be rebound or even found. Six were once in that state, `image_crop_to_selection`,
## `image_canvas_size`, `image_size`,
## `fill_foreground`, `fill_background` and `window_fullscreen`, the oldest of
## them since the crop tool landed.
##
## The check is not "the six are listed" but "nothing is unlisted", so the next
## command with a new prefix fails the run rather than going quiet.
extends "res://tests/test_framework.gd"

## A registered command builds an InputMap action, so the actions this suite
## looks for only exist once the commands have been registered.
const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")

## Godot's own, and Sara's held keys, which are gestures rather than chords: a
## quick tool is a modifier you lean on, not a row a painter rebinds. The page
## has always left them out and this suite is not the place to change that.
const NOT_ROWS := ["tool_pan_quick", "tool_zoom_quick", "tool_eyedropper_quick", "toggle_dockers"]

var _router: ShortcutRouter = null


func before_each() -> void:
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    _router = ShortcutRouter.new()
    _router.bind_commands(registries.commands)


func after_each() -> void:
    if _router != null:
        _router.free()
        _router = null


func _prefix_of(action: String) -> String:
    for group: Array in SaShortcutRows.GROUPS:
        var prefix := String(group[0])
        if action.begins_with(prefix) or (prefix == "docker_" and action.ends_with("_docker")):
            return prefix
    return ""


func test_no_action_with_a_chord_is_left_out_of_every_section() -> void:
    var homeless: Array[String] = []
    for action: StringName in InputMap.get_actions():
        var name := String(action)
        if SaShortcutStore.is_engine_action(action) or NOT_ROWS.has(name):
            continue
        if SaShortcutStore.chords_for(action).is_empty():
            continue
        if _prefix_of(name).is_empty():
            homeless.append(name)
    assert_true(
        homeless.is_empty(),
        "These answer to a key and have no section, so Preferences cannot show or rebind them: %s" % ", ".join(homeless)
    )


## The six the check was written for, named so a later reader can tell what it
## caught rather than only that it passes.
func test_the_six_that_were_missing_have_a_row_now() -> void:
    for action: String in [
        "image_crop_to_selection",
        "image_canvas_size",
        "image_size",
        "fill_foreground",
        "fill_background",
        "window_fullscreen",
    ]:
        assert_true(InputMap.has_action(StringName(action)), "%s is an action" % action)
        assert_false(_prefix_of(action).is_empty(), "%s has a section to be drawn in" % action)
        assert_true(SaShortcutRows.actions_for(_prefix_of(action)).has(StringName(action)), "and its section lists it")


## Every prefix draws something. A group whose prefix matches no action is a
## title with nothing under it, which is the mirror of the bug above and reads
## as a feature that was removed.
func test_every_section_has_at_least_one_row() -> void:
    var empty: Array[String] = []
    for group: Array in SaShortcutRows.GROUPS:
        if SaShortcutRows.actions_for(String(group[0])).is_empty():
            empty.append(String(group[1]))
    assert_true(empty.is_empty(), "A section with no rows: %s" % ", ".join(empty))


## SaShortcutStore.UI_ACTIONS is what says a `ui_` action is Sara's own
## rather than the engine's, and SaShortcutRows.ORDER is where the page puts
## it, so a name in one and not the other is either offered with no place of its
## own or has a place nobody can reach. Its words are its command's title, which
## `test_a_menu_is_a_list_of_commands.gd` holds.
func test_every_ui_action_the_store_offers_has_a_label() -> void:
    var unlabelled: Array[String] = []
    for action: String in SaShortcutStore.UI_ACTIONS:
        if not SaShortcutRows.ORDER.has(StringName(action)):
            unlabelled.append(action)
    assert_true(unlabelled.is_empty(), "These have no row to be shown under: %s" % ", ".join(unlabelled))
