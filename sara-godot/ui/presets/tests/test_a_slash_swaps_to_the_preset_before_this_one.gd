## `/`, Krita's Switch to Previous Preset, changes the preset, and
## no row on the Keyboard Shortcuts page offered the job. The bar's preset group
## remembers the preset loaded before the one in hand, and a command on `/`
## loads it, so two presses come back.
##
## The group is built bare in front of a stamp brush's settings, with its store
## in a scratch folder, the way the suite on a tool that takes no presets builds
## it. The scenario of the same name strikes `/` over the booted app.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## The command's id, as the Keyboard Shortcuts page and the profiles know it.
const COMMAND := &"brush_preset_previous"

static var scratch_dir: String = SaDataRoot.path("test_n30_previous_preset")

## The settings in front of the group, which a load writes and the suite reads.
var _settings: Resource = null
## The groups built by one test, so a failing assertion leaves no node behind.
var _boxes: Array[ToolOptionsPresets] = []
## Every action's events before a test registered the commands, put back after.
var _saved_events: Dictionary = {}


func before_each() -> void:
    ScratchFolder.empty(scratch_dir)
    _settings = StampSettingsScript.new()
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()


func after_each() -> void:
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    for box: ToolOptionsPresets in _boxes:
        if box.is_inside_tree():
            box.get_parent().remove_child(box)
        box.free()
    _boxes.clear()
    ScratchFolder.empty(scratch_dir)
    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        if not InputMap.has_action(action):
            continue
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)


## A group in front of `_settings` whose store holds A, B and C, each saved at a
## radius of its own so a load can be told by the brush and not only by the name.
func _box() -> ToolOptionsPresets:
    var box := ToolOptionsPresets.new()
    box.preset_store.dir = scratch_dir
    box.settings_source = func() -> Resource: return _settings
    _boxes.append(box)
    for entry: Array in [["A", 0.01], ["B", 0.02], ["C", 0.03]]:
        var recipe := StampSettingsScript.new()
        recipe.radius = entry[1]
        box.preset_store.save_preset(String(entry[0]), recipe)
    return box


func _radius() -> float:
    return float(_settings.get("radius"))


func test_the_swap_loads_the_one_before_and_a_second_comes_back() -> void:
    var box := _box()
    assert_true(box.load_preset("A"), "A loads")
    assert_true(box.load_preset("B"), "and then B")
    assert_eq(box.previous_preset, "A", "B remembers A")

    assert_true(box.load_previous_preset(), "The swap loads")
    assert_eq(box.selected_preset, "A", "and A is in the hand")
    assert_almost_eq(_radius(), 0.01, 0.0001, "with A's radius on the brush")
    assert_eq(box.previous_preset, "B", "and B remembered")

    assert_true(box.load_previous_preset(), "A second swap loads")
    assert_eq(box.selected_preset, "B", "and B is back")
    assert_almost_eq(_radius(), 0.02, 0.0001, "with B's radius")
    assert_eq(box.previous_preset, "A", "and A remembered again")


func test_a_failed_load_leaves_the_memory_as_it_was() -> void:
    var box := _box()
    box.load_preset("A")
    box.load_preset("B")
    assert_false(box.load_preset("Not a preset"), "A name the store lacks does not load")
    assert_eq(box.selected_preset, "B", "so B stays in the hand")
    assert_eq(box.previous_preset, "A", "and A stays remembered")
    assert_true(box.load_previous_preset(), "and the swap still goes back")
    assert_eq(box.selected_preset, "A", "to A")


func test_with_nothing_to_go_back_to_the_swap_does_nothing() -> void:
    var box := _box()
    assert_false(box.load_previous_preset(), "A fresh group has nothing to go back to")
    box.load_preset("A")
    assert_false(box.load_previous_preset(), "nor has one that loaded a single preset")
    box.load_preset("A")
    assert_eq(box.previous_preset, "", "A preset loaded again over itself is not remembered")
    assert_false(box.load_previous_preset(), "so the swap still has nothing")
    assert_eq(box.selected_preset, "A", "and A stays in the hand")


## A remembered preset deleted since fails in the load, which keeps the memory.
func test_a_deleted_previous_preset_does_not_load() -> void:
    var box := _box()
    box.load_preset("A")
    box.load_preset("B")
    box.preset_store.delete_preset("A")
    assert_false(box.load_previous_preset(), "A gone does not load")
    assert_eq(box.selected_preset, "B", "and B stays in the hand")
    assert_almost_eq(_radius(), 0.02, 0.0001, "with B's radius")


## New's defaults are no preset, so the one they replaced is what the swap goes
## back to, and a load after them remembers it still.
func test_new_remembers_the_preset_it_replaced() -> void:
    var box := _box()
    box.load_preset("A")
    box.load_preset("B")
    assert_true(box.new_preset(), "New builds the defaults")
    assert_eq(box.previous_preset, "B", "and remembers B")
    box.load_preset("C")
    assert_eq(box.previous_preset, "B", "C after the defaults goes back to B")
    assert_true(box.load_previous_preset(), "The swap loads")
    assert_eq(box.selected_preset, "B", "B")


## Krita puts the command on `/` and nothing else there. Sara Default gave `/`
## to Isolate Active Layer, so the swap has no chord of its own,
## and Photoshop, which ships no such command and names none, keeps Sara's
## silence for it and Sara's `/` for the isolation.
func test_krita_puts_the_swap_on_slash_and_sara_puts_isolation_there() -> void:
    var registries := Fixtures.make_menu_registries()
    assert_true(registries.commands.has(COMMAND), "The command is registered with the application's")
    assert_eq(String(registries.commands.get_descriptor(COMMAND).category), "brush", "in the brush's category")
    SaShortcutStore.apply_profile("Krita")
    assert_eq(SaShortcutStore.chords_for(COMMAND), ["/"] as Array[String], "Krita: the swap is on /")
    assert_eq(SaShortcutStore.holders("/"), [String(COMMAND)] as Array[String], "Krita: and / is the swap's alone")
    for profile: String in [SaShortcutStore.DEFAULT_PROFILE, "Photoshop"]:
        SaShortcutStore.apply_profile(profile)
        assert_eq(SaShortcutStore.chords_for(COMMAND), [] as Array[String], "%s: the swap has no chord" % profile)
        var isolation: Array[String] = ["view_isolate_active_layer"]
        assert_eq(SaShortcutStore.holders("/"), isolation, "%s: and / isolates the active layer" % profile)


## `/` struck through the registry under the Krita profile, with the bar's group
## in the tree, swaps, and with nothing to go back to it is declined rather than
## swallowed.
func test_slash_runs_the_swap_and_declines_with_nothing_to_swap() -> void:
    var registries := Fixtures.make_menu_registries()
    SaShortcutStore.apply_profile("Krita")
    var box := _box()
    EventBus.add_child(box)
    var slash := InputEventKey.new()
    slash.keycode = KEY_SLASH
    slash.pressed = true

    box.load_preset("A")
    assert_false(registries.commands.try_handle_input(slash), "With one preset loaded / is declined")
    assert_eq(box.selected_preset, "A", "and A stays in the hand")

    box.load_preset("B")
    assert_true(registries.commands.try_handle_input(slash), "With two, / is taken")
    assert_eq(box.selected_preset, "A", "and A is back")
    assert_true(registries.commands.try_handle_input(slash), "and a second / is taken")
    assert_eq(box.selected_preset, "B", "and B is back")
