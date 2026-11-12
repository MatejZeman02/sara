## A command that ships no chord can still be found and bound.
##
## F1 registers one `SaCommandDescriptor` per filter and none of them carries a
## default chord, so before this the registry never made their `InputMap`
## action, the Keyboard Shortcuts page had nothing to list, and the command was
## reachable from a menu and from nowhere else for the life of the install.
##
## `tool_zoom` is the shipped part that was already in that state, which is what
## makes this a defect and not a design for the future.
extends "res://tests/test_framework.gd"

## The action the fixture command below claims. Under `filter_` so it lands in
## a section the page already draws, which is what
## `SaFilterRegistry.COMMAND_PREFIX` is for.
const QUIET := &"filter_q1-fixture_quiet"

var _fired: Array[bool] = [false]
var _registries: SaRegistries = null


func before_each() -> void:
    _fired[0] = false
    _registries = SaRegistries.new()
    _registries.build_context(func() -> Variant: return null, func() -> Array: return [])


func after_each() -> void:
    _registries = null
    if InputMap.has_action(QUIET):
        InputMap.erase_action(QUIET)


## Registers a command with no `default_events`, the way `register_filter` does.
func _register_quiet() -> SaCommandRegistry:
    var fired := _fired
    var command := SaCommandDescriptor.create(QUIET, "Quiet Filter", func() -> void: fired[0] = true)
    command.category = &"filter"
    _registries.context.for_module(&"q1-fixture").register_command(command)
    return _registries.commands


# ---------------------------------------------------------------------------
# The action
# ---------------------------------------------------------------------------


func test_a_command_with_no_chord_still_gets_its_action() -> void:
    _register_quiet()

    assert_true(InputMap.has_action(QUIET), "There is something for a surface to list and for a rebind to write")
    assert_true(SaShortcutStore.chords_for(QUIET).is_empty(), "and it answers to nothing, which is what unbound means")


func test_an_empty_action_dispatches_nothing() -> void:
    var commands := _register_quiet()
    var event := InputEventKey.new()
    event.keycode = KEY_Q
    event.pressed = true

    assert_false(commands.try_handle_input(event), "An action with no events matches no key")
    assert_false(_fired[0], "so adding the action fired nothing that was not fired before")


# ---------------------------------------------------------------------------
# The surface
# ---------------------------------------------------------------------------


func test_the_page_lists_a_command_that_has_no_chord() -> void:
    _register_quiet()

    var actions := SaShortcutRows.actions_for("filter_")

    assert_true(actions.has(QUIET), "The page's list is what can be bound, not what already is")


func test_the_help_list_still_leaves_it_out() -> void:
    _register_quiet()

    var labels: Array = []
    for row: Array in SaShortcutRows.rows_for("filter_"):
        labels.append(row[0])

    assert_false(labels.has("Quiet Filter"), "Help prints keys, and a line naming no key claims nothing")


func test_the_shipped_chordless_tool_has_a_row_at_last() -> void:
    assert_true(InputMap.has_action(&"tool_zoom"), "The zoom tool's action is in the map")
    assert_true(SaShortcutStore.chords_for(&"tool_zoom").is_empty(), "with no chord, which is how it shipped")
    assert_true(SaShortcutRows.actions_for("tool_").has(&"tool_zoom"), "and it is now something a painter can bind")


func test_an_unbound_row_reads_set_rather_than_crashing() -> void:
    _register_quiet()

    var page := SaShortcutsPage.new()

    assert_eq(page.chord_shown(QUIET), SaShortcutsPage.NO_CHORD_TEXT, "The row is there and offers to set a chord")
    page.free()


# ---------------------------------------------------------------------------
# Binding it
# ---------------------------------------------------------------------------


func test_binding_an_unbound_command_from_the_page_makes_it_fire() -> void:
    var commands := _register_quiet()
    var page := SaShortcutsPage.new()

    page.rebind(QUIET, "Ctrl+Alt+Q")

    assert_eq(page.chord_shown(QUIET), "Ctrl+Alt+Q", "The row shows the chord it was given")
    var event := InputEventKey.new()
    event.keycode = KEY_Q
    event.ctrl_pressed = true
    event.alt_pressed = true
    event.pressed = true
    assert_true(commands.try_handle_input(event), "and the command answers to it")
    assert_true(_fired[0], "which is the filter running from a key for the first time")
    page.free()


func test_a_command_cleared_of_its_chord_keeps_its_row() -> void:
    _register_quiet()
    var page := SaShortcutsPage.new()
    page.rebind(QUIET, "Ctrl+Alt+Q")

    page.rebind(QUIET, "")

    assert_eq(page.chord_shown(QUIET), SaShortcutsPage.NO_CHORD_TEXT, "Clearing a chord leaves the row that can put one back")
    assert_true(SaShortcutRows.actions_for("filter_").has(QUIET), "and a page built again still lists it")
    page.free()
