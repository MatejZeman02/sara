## Ctrl+R walks back through the Recent Presets list while Ctrl
## is held, as Alt+Tab walks the windows, and the list keeps its order until
## Ctrl is let go, when the preset reached goes to the top.
##
## The bar's preset group is built bare in front of a stamp brush's settings,
## its store in a scratch folder, the way the swap's suite beside it builds it,
## and the docker beside it keeps its list in the same folder. Ctrl goes down
## and up through the engine, so the walk reads the keyboard's state the way it
## does in the app, and each R is the chord a keyboard sends, struck through the
## command registry. The scenario of the same name strikes the keys over the
## booted app.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## The docker is a Window and its `_init` builds real controls.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_recent_walk")

var _settings: Resource = null
var _box: ToolOptionsPresets = null
var _docker: HistoryDocker = null
var _registries: SaRegistries = null
var _saved_events: Dictionary = {}


func before_each() -> void:
    ScratchFolder.empty(scratch_dir)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch_dir))
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    _registries = Fixtures.make_menu_registries()
    _settings = StampSettingsScript.new()
    _box = ToolOptionsPresets.new()
    _box.preset_store.dir = scratch_dir
    _box.settings_source = func() -> Resource: return _settings
    for entry: Array in [["A", 0.01], ["B", 0.02], ["C", 0.03], ["D", 0.04]]:
        var recipe := StampSettingsScript.new()
        recipe.radius = entry[1]
        _box.preset_store.save_preset(String(entry[0]), recipe)
    EventBus.add_child(_box)
    _docker = HistoryDocker.new()
    _docker.path = scratch_dir.path_join("recent.cfg")
    _docker.store.dir = scratch_dir
    EventBus.add_child(_docker)
    _docker.entries = PackedStringArray()


func after_each() -> void:
    _ctrl(false)
    var walk := EventBus.get_node_or_null(SaRecentPresetWalk.NODE_NAME)
    if walk != null:
        EventBus.remove_child(walk)
        walk.free()
    for node: Node in [_box, _docker]:
        if node.is_inside_tree():
            node.get_parent().remove_child(node)
        node.free()
    _box = null
    _docker = null
    _registries = null
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        if not InputMap.has_action(action):
            continue
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    ScratchFolder.empty(scratch_dir)


## Ctrl down or up through the engine, the edge a keyboard sends.
func _ctrl(down: bool) -> void:
    var event := InputEventKey.new()
    event.keycode = KEY_CTRL
    event.physical_keycode = KEY_CTRL
    event.ctrl_pressed = down
    event.pressed = down
    Input.parse_input_event(event)
    Input.flush_buffered_events()


## R with Ctrl held, as a keyboard sends it, struck through the commands.
func _r() -> bool:
    var event := InputEventKey.new()
    event.keycode = KEY_R
    event.physical_keycode = KEY_R
    event.ctrl_pressed = true
    event.pressed = true
    return _registries.commands.try_handle_input(event)


## Ctrl let go, and the frame's look at the keyboard the walk makes.
func _let_go() -> void:
    _ctrl(false)
    var walk := EventBus.get_node_or_null(SaRecentPresetWalk.NODE_NAME) as SaRecentPresetWalk
    if walk != null:
        walk.poll()


func _load(names: Array[String]) -> void:
    for preset_name: String in names:
        assert_true(_box.load_preset(preset_name), "%s loads" % preset_name)


func _lit_rows() -> Array[String]:
    var lit: Array[String] = []
    for child in _docker.rows.get_children():
        var button := child as Button
        if button != null and not button.is_queued_for_deletion() and button.button_pressed:
            lit.append(button.text)
    return lit


func test_three_rs_walk_back_to_a_and_the_release_puts_a_on_top() -> void:
    _load(["A", "B", "C", "D"] as Array[String])
    assert_eq(_docker.entries, PackedStringArray(["D", "C", "B", "A"]), "The list is D, C, B, A")

    _ctrl(true)
    assert_true(_r(), "Ctrl+R is taken")
    assert_eq(_box.selected_preset, "C", "the first R loads C")
    assert_eq(_lit_rows(), ["C"] as Array[String], "and lights C's row")
    assert_true(_r(), "a second R is taken")
    assert_eq(_box.selected_preset, "B", "and loads B")
    assert_true(_r(), "a third R is taken")
    assert_eq(_box.selected_preset, "A", "and loads A")
    assert_almost_eq(float(_settings.get("radius")), 0.01, 0.0001, "with A's radius on the brush")
    assert_eq(_docker.entries, PackedStringArray(["D", "C", "B", "A"]), "and the list is still D, C, B, A")
    assert_eq(_lit_rows(), ["A"] as Array[String], "with A's row lit")

    _let_go()
    assert_eq(_docker.entries, PackedStringArray(["A", "D", "C", "B"]), "Letting go of Ctrl reads A, D, C, B")
    assert_eq(_box.selected_preset, "A", "with A in the hand")
    assert_eq(_lit_rows(), [] as Array[String], "and no row lit")
    assert_eq(_box.previous_preset, "D", "and the swap goes back to D, where the walk began")
    var stored := ConfigFile.new()
    stored.load(_docker.path)
    assert_eq(
        stored.get_value(HistoryDocker.SECTION, HistoryDocker.KEY, PackedStringArray()),
        PackedStringArray(["A", "D", "C", "B"]),
        "and the file holds the new order"
    )


func test_a_fourth_r_wraps_to_the_top_row() -> void:
    _load(["A", "B", "C", "D"] as Array[String])
    _ctrl(true)
    for _i in 4:
        _r()
    assert_eq(_box.selected_preset, "D", "Past the last row the walk wraps to D")
    _let_go()
    assert_eq(_docker.entries, PackedStringArray(["D", "C", "B", "A"]), "and the list is as it was")


## One Ctrl+R and release is the swap `brush_preset_previous` makes: the same
## preset in the hand, the same one to go back to, the same list.
func test_one_ctrl_r_is_the_swap() -> void:
    _load(["A", "B", "C", "D"] as Array[String])
    assert_true(_box.load_previous_preset(), "The swap loads")
    var swapped := [_box.selected_preset, _box.previous_preset, _docker.entries]
    _load(["D"] as Array[String])
    assert_eq(_docker.entries, PackedStringArray(["D", "C", "B", "A"]), "D back on top")

    _ctrl(true)
    assert_true(_r(), "Ctrl+R is taken")
    _let_go()
    assert_eq([_box.selected_preset, _box.previous_preset, _docker.entries], swapped, "One Ctrl+R and release is the swap")
    assert_eq(swapped[0], "C", "which loads C")


func test_with_one_preset_ctrl_r_is_declined() -> void:
    _load(["A"] as Array[String])
    _ctrl(true)
    assert_false(_r(), "With nothing behind the preset in hand Ctrl+R is declined")
    assert_eq(_box.selected_preset, "A", "and A stays")


## The docker closed, the list beside the pointer shows the walk and goes with
## Ctrl.
func test_with_the_docker_closed_a_list_beside_the_pointer_shows_the_walk() -> void:
    _load(["A", "B", "C"] as Array[String])
    _ctrl(true)
    _r()
    var walk := EventBus.get_node(SaRecentPresetWalk.NODE_NAME) as SaRecentPresetWalk
    var shown := walk.get_node("RecentPresetWalkList") as Control
    assert_true(shown.visible, "The list beside the pointer shows")
    var lit: Array[String] = []
    for row: Button in shown.find_children("Row_*", "Button", true, false):
        if row.button_pressed:
            lit.append(row.text)
    assert_eq(lit, ["B"] as Array[String], "with B lit")
    _let_go()
    assert_false(shown.visible, "and goes when Ctrl is let go")


func test_sara_and_photoshop_put_the_walk_on_ctrl_r_and_krita_on_nothing() -> void:
    var command := SaRecentPresetWalk.COMMAND
    assert_true(_registries.commands.has(command), "The walk is registered with the application's commands")
    assert_eq(String(_registries.commands.get_descriptor(command).category), "brush", "in the brush's category")
    for profile: String in [SaShortcutStore.DEFAULT_PROFILE, "Photoshop"]:
        SaShortcutStore.apply_profile(profile)
        assert_eq(SaShortcutStore.chords_for(command), ["Ctrl+R"] as Array[String], "%s: the walk is on Ctrl+R" % profile)
        assert_eq(
            SaShortcutStore.holders("Ctrl+R"), [String(command)] as Array[String], "%s: and Ctrl+R is the walk's alone" % profile
        )
    SaShortcutStore.apply_profile("Krita")
    assert_eq(SaShortcutStore.chords_for(command), [] as Array[String], "Krita: the walk has no chord")
    assert_eq(SaShortcutStore.holders("Ctrl+R"), ["tool_marquee"] as Array[String], "Krita: Ctrl+R stays the selection tool's")
