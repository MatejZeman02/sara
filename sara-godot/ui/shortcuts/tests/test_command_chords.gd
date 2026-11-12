## Every registered command answers to a chord, and the toolbox says which.
##
## A painter who reaches for a chord used in Krita should find it, and the app
## should say what a chord is. A command with no chord is a menu entry the keyboard
## cannot reach, so this fails the run.
##
## The three symmetry switches are the exception and carry none on purpose:
## Krita ships none for them either.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const SkeletonModuleScript = preload("res://core/loader/skeleton_module.gd")
const BlendModeCommandsScript = preload("res://core/loader/skeleton_blend_mode_commands.gd")
const ToolBoxDockerScript = preload("res://ui/dockers/toolbox/toolbox_docker.gd")

## The chords taken from a Krita export, so a later edit that moves one has to
## say so here. Deselect has Krita's Ctrl+Shift+A beside Ctrl+D and Lock Alpha
## is on Ctrl+Alt+A, the docker chords sit off the right hand, which the suite
## beside this one holds, the clear has both bare keys, Krita's and
## Photoshop's, and Reselect and the layer's rename have the chords Krita
## ships for them.
const EXPECTED_CHORDS := {
    "select_all": "Ctrl+A",
    "select_none": "Ctrl+D, Ctrl+Shift+A",
    "select_reselect": "Ctrl+Shift+D",
    "layer_rename": "F2",
    "layer_lock": "Ctrl+Shift+L",
    "layer_alpha_lock": "Ctrl+Alt+A",
    "layer_clear": "Backspace, Delete",
    "select_invert": "Ctrl+Shift+I",
    "select_quick_mask": "Alt+Q",
    "layer_clip_to_below": "Ctrl+Shift+G",
    "layer_mask_add": "Ctrl+Shift+M",
    "edit_preferences": "Ctrl+,",
    # The five point adjustments are the base module's filters, and `base/tests/test_adjust_filters.gd` and
    # `base/tests/test_levels_and_curves_filters.gd` hold their chords.
    "docker_recorder": "Shift+X",
    # Blender's three. Shift+Q is off the quick mask and Shift+R off the
    # recorder for them.
    "edit_search_commands": "F3",
    "edit_quick_favourites": "Shift+Q",
    "edit_repeat_last": "Shift+R",
    "docker_minimap": "Shift+V",
    "docker_graph": "Shift+A",
    # Krita's Ctrl+Shift+E merges what is visible, and the
    # brush editor took Krita's own F5 for it.
    "layer_merge_visible": "Ctrl+Shift+E",
    "edit_brush": "F5",
}

## The docker toggles the Shift cycle of a tool family took the chord of. Each
## is still reached by its Window menu row and its Alt+Shift summon.
const TOGGLE_WITHOUT_CHORD: Array[StringName] = [&"docker_history", &"docker_palette"]

## The mask's operations that carry no chord: only the add takes one, and neither Krita nor Photoshop ships a chord for
## the other six.
const MASK_WITHOUT_CHORD: Array[StringName] = [
    &"layer_mask_add_from_selection",
    &"layer_mask_delete",
    &"layer_mask_apply",
    &"layer_mask_invert",
    &"layer_mask_disable",
    &"layer_mask_to_selection",
]


## Every command the running app has: the skeleton's built-ins, the
## application's own, and the router's view, interface and clipboard chords.
## The router has to be passed in and freed by the caller, because the registry
## holds handlers bound to it.
func _commands(router: ShortcutRouter, toggled: Array = []) -> SaCommandRegistry:
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(docker_id: StringName) -> void: toggled.append(docker_id))
    if router != null:
        router.bind_commands(registries.commands)
    return registries.commands


func test_every_registered_command_has_a_chord() -> void:
    var router := ShortcutRouter.new()
    var commands := _commands(router)
    # The menu rows that became commands so a menu could be a list of them. Each
    # has an action and a row on the Shortcuts page a painter can give a key, and
    # one ships for Fit, Centre and Reset Rotation alone. New,
    # Open, Save, Undo and the rest are the router's, under `project.godot`'s.
    var menu_rows: Array[StringName] = []
    for command: SaCommandDescriptor in SaMenuCommands.new(Callable(), Callable(), Callable(), Callable()).commands():
        menu_rows.append(command.id)
    for entry: Array in SkeletonModuleScript.LAYER_MENU_COMMANDS:
        menu_rows.append(entry[0])
    # View > Show Status Line, a row set once, which ships no chord either.
    menu_rows.append(SaStatusLine.COMMAND)
    # Search..., the loupe's command, which opens the one search F3 opens and
    # leaves F3 its chord.
    menu_rows.append(&"help_search")
    # Switch to Previous Preset gives `/` to Isolate Active Layer and keeps it
    # under the Krita profile alone.
    menu_rows.append(&"brush_preset_previous")
    # Export Effects as LUT, a Layer menu row with a dialog,
    # which ships no chord as the layer menu's own rows do not.
    menu_rows.append(SaEffectsLut.COMMAND)
    menu_rows.append(SaEditSmartLayerContents.COMMAND)
    # Krita's blending mode commands, which Sara's own map
    # leaves unbound and the Krita profile alone gives Krita's chords.
    for entry: Array in BlendModeCommandsScript.STEPS + BlendModeCommandsScript.PICKS:
        menu_rows.append(entry[0])
    # Wrap Around Mode, on Shift+W under the Krita profile alone.
    menu_rows.append(SaTopBarPageEdgesCommand.COMMAND)
    # View > Page Edges' four modes and Double Resolution, View
    # rows beside a bar button, which ship no chord as the bar's toggles do not.
    for mode_command: StringName in SaTopBarPageEdges.MODE_COMMANDS.values():
        menu_rows.append(mode_command)
    menu_rows.append(SaTopBarDoubleResolution.COMMAND)
    var chordless: Array[String] = []
    for command_id: StringName in commands.list_ids():
        var descriptor := commands.get_descriptor(command_id)
        if descriptor.category == &"symmetry" or MASK_WITHOUT_CHORD.has(command_id):
            continue
        if TOGGLE_WITHOUT_CHORD.has(command_id):
            continue
        if menu_rows.has(command_id):
            continue
        if not commands.has_chord(command_id):
            chordless.append(String(command_id))
    assert_true(chordless.is_empty(), "A command the keyboard cannot reach: %s" % ", ".join(chordless))
    router.free()


## The symmetry three are the stated exception, so the test above has to keep
## being able to fail: if they ever gain a chord, the exemption is dead code.
func test_the_symmetry_switches_are_the_only_ones_without_one() -> void:
    var commands := _commands(null)
    for command_id: StringName in [&"symmetry_horizontal", &"symmetry_vertical", &"symmetry_radial"]:
        assert_true(commands.has(command_id), "%s is registered" % command_id)
        assert_false(commands.has_chord(command_id), "%s carries no chord, as Krita ships none" % command_id)


func test_the_chords_are_the_ones_the_plan_named() -> void:
    var router := ShortcutRouter.new()
    var commands := _commands(router)
    for command_id: String in EXPECTED_CHORDS:
        assert_true(commands.has(StringName(command_id)), "%s is registered" % command_id)
        assert_eq(commands.chord_text(StringName(command_id)), EXPECTED_CHORDS[command_id], "%s answers to it" % command_id)
    router.free()


## Two commands on one chord means the second never fires, and the painter has
## no way to see why. Key by key, because a command may answer several: zoom in
## takes the top row's plus and the keypad's.
func test_no_two_commands_share_a_chord() -> void:
    var router := ShortcutRouter.new()
    var commands := _commands(router)
    var seen: Dictionary = {}
    var clashes: Array[String] = []
    for command_id: StringName in commands.list_ids():
        for chord in commands.chord_text(command_id).split(", ", false):
            if seen.has(chord):
                clashes.append("%s and %s both answer %s" % [seen[chord], command_id, chord])
            seen[chord] = command_id
    assert_true(clashes.is_empty(), ", and ".join(clashes))
    router.free()


## A menu writes an entry's chord from the registry rather than a string
## of its own, so this checks every menu against the registry it was built
## from, not against a chord typed a second time here.
func test_menu_items_show_their_registered_chord() -> void:
    var router := ShortcutRouter.new()
    var commands := _commands(router)
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(commands)

    var checks := {
        "Select":
        {200: &"select_all", 201: &"select_none", 205: &"select_reselect", 202: &"select_invert", 203: &"select_quick_mask"},
        "Edit": {104: &"edit_cut", 105: &"edit_copy", 106: &"edit_paste", 100: &"edit_preferences"},
        "View":
        {10: &"view_zoom_in", 11: &"view_zoom_out", 12: &"view_zoom_100", 15: &"view_rotate_left", 16: &"view_rotate_right"},
    }
    for menu_name: String in checks:
        var popup: SaChoicePopup = bar.menus[menu_name]
        var ids: Dictionary = checks[menu_name]
        for item_id: int in ids:
            var command_id: StringName = ids[item_id]
            # The chord is the row's own hint column. `hint` in the row report is
            # what a painter reads at the row's right. Only the first chord shows,
            # the Shortcuts page being where every one is listed.
            var hint := _hint_of(popup, SaMenu.key(item_id))
            assert_true(
                hint == commands.chord_text(command_id, 1),
                "%s > %s should show %s's chord: %s" % [menu_name, item_id, command_id, hint]
            )

    bar.free()
    router.free()


## Every static row is a command since the menus became lists of them, so a
## menu draws nothing it has no command for: before a registry is bound Select
## is empty rather than a row the menu wrote words for itself, and a command no
## key reaches draws its words and an empty chord column.
func test_a_row_draws_only_what_its_command_says() -> void:
    var bar := TopMenuBar.new()
    bar._ready()
    var select_popup: SaChoicePopup = bar.menus["Select"]
    assert_true(select_popup.row_ids().is_empty(), "No registry bound yet, so no rows")

    var router := ShortcutRouter.new()
    bar.bind_commands(_commands(router))
    assert_eq(select_popup.label_button(SaMenu.key(200)).text, "All", "Bound, the row reads its command's words")
    var view_popup: SaChoicePopup = bar.menus["View"]
    var zoom := SaMenu.list_holding(view_popup, SaMenu.key(13))
    assert_eq(zoom.label_button(SaMenu.key(13)).text, "Fit to View", "Fit to View is a command, under Zoom")
    assert_eq(_hint_of(view_popup, SaMenu.key(13)), "F", "with the F it ships in the column")
    assert_eq(_hint_of(view_popup, SaMenu.key(71)), "", "and Fit to Window none, as it ships no key")
    bar.free()
    router.free()


## The words a row draws at its right, which is where a chord goes.
func _hint_of(popup: SaChoicePopup, row_id: StringName) -> String:
    for list: SaChoicePopup in SaMenu.lists_of(popup):
        for entry: Dictionary in list.row_report():
            if String(entry.get("id", "")) == String(row_id):
                return String(entry.get("hint", ""))
    return ""


## The docker commands go through main's own toggle rather than setting
## `visible`, because showing a docker also restores its geometry, ticks the
## Dockers menu and saves the layout.
func test_a_docker_command_asks_for_the_docker_by_id() -> void:
    var toggled: Array = []
    var commands := _commands(null, toggled)
    assert_true(commands.execute(&"docker_minimap"), "The minimap command runs")
    assert_eq(toggled, [&"MinimapDocker"], "and names the docker it wants")


## The bracket is filled when the pointer arrives, not when the button was
## built, so a chord changed in Preferences shows without a restart.
func test_the_toolbox_tooltip_reads_the_chord_at_hover() -> void:
    var registry := Fixtures.make_tool_registry()
    var toolbox := ToolBoxDockerScript.new()
    toolbox.name = "ToolBoxDocker"
    toolbox.rebuild_from_registry(registry)
    # One button per category, so the brush is asked for by name and
    # shown on its category's button rather than owning one of its own.
    toolbox.show_tool("brush")
    var button: Button = toolbox.button_for_tool("brush")
    assert_not_null(button, "The brush has a button")
    if button == null:
        toolbox.free()
        return

    button.mouse_entered.emit()
    # Up to the sentence about the brush's group.
    assert_eq(button.tooltip_text.get_slice(". ", 0), "Brush (B)", "which says the chord it answers to")

    var moved := InputEventKey.new()
    moved.keycode = KEY_F9
    var before := InputMap.action_get_events(&"tool_brush")
    InputMap.action_erase_events(&"tool_brush")
    InputMap.action_add_event(&"tool_brush", moved)
    button.mouse_entered.emit()
    assert_eq(button.tooltip_text.get_slice(". ", 0), "Brush (F9)", "and follows a rebind with no rebuild")

    InputMap.action_erase_events(&"tool_brush")
    for event: InputEvent in before:
        InputMap.action_add_event(&"tool_brush", event)
    toolbox.free()


## A tool bound by physical keycode read "(unset)" in its own bracket, because
## the tooltip asked for the label keycode of an event that carries none.
func test_a_physically_bound_tool_still_names_its_key() -> void:
    var registry := Fixtures.make_tool_registry()
    var toolbox := ToolBoxDockerScript.new()
    toolbox.name = "ToolBoxDocker"
    toolbox.rebuild_from_registry(registry)
    toolbox.show_tool("bucket_fill")
    var button: Button = toolbox.button_for_tool("bucket_fill")
    assert_not_null(button, "The bucket fill has a button")
    var before := InputMap.action_get_events(&"tool_bucket_fill")
    var physical := InputEventKey.new()
    physical.physical_keycode = KEY_G
    physical.shift_pressed = true
    InputMap.action_erase_events(&"tool_bucket_fill")
    InputMap.action_add_event(&"tool_bucket_fill", physical)
    if button != null:
        button.mouse_entered.emit()
        assert_false(button.tooltip_text.contains("unset"), "and a readable key: %s" % button.tooltip_text)
        assert_true(button.tooltip_text.contains("Shift+G"), "which is Shift+G: %s" % button.tooltip_text)
    InputMap.action_erase_events(&"tool_bucket_fill")
    for event: InputEvent in before:
        InputMap.action_add_event(&"tool_bucket_fill", event)
    toolbox.free()
