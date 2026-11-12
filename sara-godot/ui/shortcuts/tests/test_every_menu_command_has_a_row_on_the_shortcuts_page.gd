## Every menu command has a row on the Keyboard Shortcuts page.
##
## The File, Edit, View, Image and Help commands had no row, so a painter could
## not give Fit, Centre or Reset Rotation a key. It looked like a command with
## no chord making no action, but the registry makes an
## action for any command that names one, chord or not. What named none was
## `SaMenuCommands.commands()`, and the skeleton module for the Layer menu's
## four, which blanked the action on every row. Each is an action now, Sara
## Default ships F for Fit, R for Reset Rotation and V for Centre View, and the
## branch the router kept for two actions nothing bound is gone.
##
## The bar is built detached and the page never joins the tree, the way
## `ui/menus/tests/test_menu_chords_read_like_the_shortcuts_page.gd` builds them.
## The two base modules register through the door, so the map a profile is laid
## over is the one the app boots with. The scenario of the same name presses the
## three keys over the booted app and gives Fit a chord on the page.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

const MODULES: Array[String] = [
    "res://modules/sara-base-modules/base/module.gd",
    "res://modules/sara-base-modules/stamp-brush/module.gd",
]

## The keys of the three view rows under each shipped profile. Krita's table
## gives F to the bucket fill, which takes it off Fit there.
const VIEW_CHORDS := {
    "Sara Default": {&"view_fit": ["F"], &"view_rotate_reset": ["R"], &"view_center": ["V"]},
    "Krita": {&"view_fit": [], &"view_rotate_reset": ["R"], &"view_center": ["V"]},
    "Photoshop": {&"view_fit": ["F"], &"view_rotate_reset": ["R"], &"view_center": ["V"]},
}

var _saved_events: Dictionary = {}
var _saved_profile: String = ""

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _router: ShortcutRouter = null
var _note_mode: SaNoteMode = null


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    SaShortcutStore.dir_override = SaDataRoot.path("test_n43_shortcut_profiles")
    SaShortcutStore.capture_defaults()
    _saved_profile = SaSettings.shortcuts_profile
    SaSettings.shortcuts_profile = SaShortcutStore.DEFAULT_PROFILE

    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    _modules.clear()
    for path: String in MODULES:
        var module: SaModule = load(path).new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    SaAppCommands.register_all(_registries, func(_docker_id: StringName) -> void: pass)
    _note_mode = SaNoteMode.new()
    SaNoteMode.register_command(_registries.commands, _note_mode)
    _machine = Fixtures.make_bound_machine(_surface)
    _router = ShortcutRouter.new()
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return _machine
    _router.bind_commands(_registries.commands)


func after_each() -> void:
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    for module: SaModule in _modules:
        module.unregister(_registries.context)
    _modules.clear()
    Fixtures.teardown(_surface, _machine)
    _router.free()
    _note_mode.free()
    _router = null
    _note_mode = null
    _machine = null
    _registries = null
    _surface = null

    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    SaSettings.shortcuts_profile = _saved_profile
    SaShortcutStore.dir_override = ""
    var dir := DirAccess.open(SaDataRoot.path("test_n43_shortcut_profiles"))
    if dir != null:
        for file: String in dir.get_files():
            dir.remove(file)


## The page as Preferences builds it, over this suite's registries.
func _page() -> SaShortcutsPage:
    var page := SaShortcutsPage.new()
    page.bind_tools(_registries.tools, _registries.filters, _registries.commands)
    return page


## Every command a row of a menu runs, by menu, read off the rows the bar drew.
## `command_at` rather than a list of ids, because the Layer menu draws its rows
## from a list of its own and answers the command behind each the same way.
func _menu_commands() -> Dictionary:
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(_registries.commands)
    var out := {}
    for menu_name: String in TopMenuBar.MENU_NAMES:
        var menu := bar.menu(menu_name)
        var ids: Array[StringName] = []
        for list: SaChoicePopup in SaMenu.lists_of(menu.popup) if menu != null else []:
            for row_id: StringName in list.row_ids():
                var command := menu.command_at(SaMenu.id_of(row_id))
                if not command.is_empty():
                    ids.append(command)
        out[menu_name] = ids
    bar.free()
    return out


## The press a keyboard sends: the character, its position and its label all
## set, rather than the one field a chord's text parses to.
func _press(chord: String) -> InputEventKey:
    var parsed := SaShortcutStore.parse_chord(chord)
    var event := InputEventKey.new()
    event.keycode = parsed.keycode
    event.physical_keycode = parsed.keycode
    event.key_label = parsed.keycode
    event.ctrl_pressed = parsed.ctrl_pressed
    event.shift_pressed = parsed.shift_pressed
    event.alt_pressed = parsed.alt_pressed
    event.pressed = true
    return event


## The view turned, zoomed out and pushed off to one side, the state each key
## is pressed on.
func _turned_and_zoomed() -> SaTestFixtures.FakeView:
    var view := _surface.view as SaTestFixtures.FakeView
    view.set_zoom(0.4)
    view.set_rotation(0.6)
    view.set_pan(Vector2(90, -140))
    return view


## Where the middle of the document is on screen, which is the middle of the
## view once it is centred.
func _middle_on_screen(view: SaView) -> Vector2:
    return view.document_to_screen(Vector2(_surface.get_canvas_size()) * 0.5)


## The zoom a fit settles on for the view's present turn.
func _fitted_zoom(view: SaView) -> float:
    var extent := SaView.rotated_extent(Vector2(_surface.get_canvas_size()), view.get_rotation())
    var area := view.get_free_rect().size
    return minf(area.x / extent.x, area.y / extent.y)


func test_every_menu_command_has_an_action_and_a_row_on_the_page() -> void:
    var page := _page()
    var by_menu := _menu_commands()
    var counted := 0
    var no_action: Array[String] = []
    var no_row: Array[String] = []
    for menu_name: String in by_menu:
        for command: StringName in by_menu[menu_name]:
            counted += 1
            if not InputMap.has_action(command):
                no_action.append("%s > %s" % [menu_name, command])
            elif not page.row_shown(command):
                no_row.append("%s > %s" % [menu_name, command])
    assert_true(counted > 60, "The bar draws its command rows, %d of them" % counted)
    var were_missing: Array[StringName] = [
        &"view_fit", &"view_center", &"view_rotate_reset", &"file_export", &"help_about", &"layer_flatten"
    ]
    for wanted: StringName in were_missing:
        var found := false
        for menu_name: String in by_menu:
            found = found or (by_menu[menu_name] as Array).has(wanted)
        assert_true(found, "%s is a row of a menu" % wanted)
    assert_eq(no_action, [] as Array[String], "Every menu command is an action")
    assert_eq(no_row, [] as Array[String], "and every one has a row on the page")
    page.free()


## The Help rows are a section of their own, the old Settings menu's two among
## them, rather than rows with no section to be drawn in.
func test_the_help_rows_are_grouped_under_help() -> void:
    var help := SaShortcutRows.actions_for("help_")
    for action: StringName in [&"help_display", &"help_tablet", &"help_shortcuts", &"help_manual", &"help_about"]:
        assert_true(help.has(action), "%s is under Help" % action)
    var titles: Array[String] = []
    for group: Array in SaShortcutRows.GROUPS:
        titles.append(String(group[1]))
    assert_true(titles.has("Help"), "and Help is a section of the page")


## The seven the router answers itself keep no action on their command, or a
## press would run them twice, and still show the chord `project.godot` gives.
func test_the_seven_the_router_answers_keep_their_chords_and_one_answer() -> void:
    for command: StringName in SaMenuCommands.ROUTER_ACTIONS:
        var descriptor := _registries.commands.get_descriptor(command)
        assert_not_null(descriptor, "%s is a command" % command)
        if descriptor != null:
            assert_eq(descriptor.action, &"", "%s leaves its key to the router" % command)
        assert_false(SaShortcutStore.chords_for(command).is_empty(), "and %s still answers its key" % command)


func test_f_r_and_v_answer_fit_reset_rotation_and_centre() -> void:
    var wanted: Dictionary = VIEW_CHORDS[SaShortcutStore.DEFAULT_PROFILE]
    for command: StringName in wanted:
        assert_eq(SaShortcutStore.chords_for(command), wanted[command] as Array[String], "%s ships its key" % command)

    var view := _turned_and_zoomed()
    assert_true(_router.handle(_press("F")), "F is answered")
    assert_eq(_router.commands.last_command, &"view_fit", "by Fit")
    assert_almost_eq(view.get_rotation(), 0.6, 0.0001, "A fit keeps the turn")
    assert_almost_eq(view.get_zoom(), _fitted_zoom(view), 0.0001, "and zooms the turned document into the view")
    assert_true(_middle_on_screen(view).distance_to(view.get_free_rect().get_center()) < 0.01, "with its middle in the middle")

    view = _turned_and_zoomed()
    assert_true(_router.handle(_press("R")), "R is answered")
    assert_eq(_router.commands.last_command, &"view_rotate_reset", "by Reset Rotation")
    assert_almost_eq(view.get_rotation(), 0.0, 0.0001, "which puts the view upright")
    assert_almost_eq(view.get_zoom(), 0.4, 0.0001, "at the zoom it had")

    view = _turned_and_zoomed()
    assert_true(_router.handle(_press("V")), "V is answered")
    assert_eq(_router.commands.last_command, &"view_center", "by Centre View")
    assert_true(_middle_on_screen(view).distance_to(view.get_free_rect().get_center()) < 0.01, "which centres the document")
    assert_almost_eq(view.get_zoom(), 0.4, 0.0001, "at the zoom it had")
    assert_almost_eq(view.get_rotation(), 0.6, 0.0001, "and the turn it had")


## Shift with each letter toggles a docker and Ctrl+V pastes, and the bare
## letters take none of them.
func test_the_chords_beside_the_three_keys_stay_where_they_were() -> void:
    for chord: String in ["Shift+F", "Shift+R", "Shift+V", "Ctrl+V"]:
        var holders := SaShortcutStore.holders(chord)
        for command: StringName in [&"view_fit", &"view_rotate_reset", &"view_center"]:
            assert_false(holders.has(String(command)), "%s is not %s" % [chord, command])
    assert_true(SaShortcutStore.holders("Ctrl+V").has("edit_paste"), "Ctrl+V still pastes")


func test_no_two_actions_of_any_shipped_profile_share_a_chord() -> void:
    for profile: String in VIEW_CHORDS:
        SaShortcutStore.apply_profile(profile)
        var clashes := SaShortcutStore.all_conflicts()
        assert_eq(clashes.keys(), [], "%s gives no chord to two actions: %s" % [profile, str(clashes)])
        var wanted: Dictionary = VIEW_CHORDS[profile]
        for command: StringName in wanted:
            assert_eq(SaShortcutStore.chords_for(command), wanted[command] as Array[String], "%s: %s" % [profile, command])
    SaShortcutStore.apply_profile("Krita")
    assert_eq(SaShortcutStore.holders("F"), ["tool_bucket_fill"] as Array[String], "Under Krita F is the bucket fill alone")


func test_a_chord_given_to_fit_on_the_page_fits_the_view() -> void:
    var page := _page()
    assert_eq(page.chords_shown(&"view_fit"), ["F"] as Array[String], "Fit's row shows the F it ships")
    assert_eq(SaShortcutStore.holders("Ctrl+Alt+F"), [] as Array[String], "and nothing holds Ctrl+Alt+F")
    page.rebind(&"view_fit", "Ctrl+Alt+F")
    assert_eq(page.chords_shown(&"view_fit"), ["Ctrl+Alt+F"] as Array[String], "The row shows the chord it was given")

    var view := _turned_and_zoomed()
    _router.handle(_press("F"))
    assert_almost_eq(view.get_zoom(), 0.4, 0.0001, "F no longer fits")
    assert_true(_router.handle(_press("Ctrl+Alt+F")), "Ctrl+Alt+F is answered")
    assert_eq(_router.commands.last_command, &"view_fit", "by Fit")
    assert_almost_eq(view.get_zoom(), _fitted_zoom(view), 0.0001, "and it fits the view")
    page.free()
