## A profile saved under a name no file can take says so and keeps the one in use.
##
## `save_profile` answered 0 for a save that wrote no file, the same 0 as a
## profile with nothing changed, and Save as on the page names the profile in
## the settings whenever the answer is not below 0. A name with a `/` in it
## made a folder nobody made, so the save failed, the settings named a profile
## with no file under it, and every chord set in the session was gone at the
## next start with nothing said.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

static var scratch_dir: String = SaDataRoot.path("test_unnameable_profiles")

var _saved_events: Dictionary = {}
var _saved_profile: String = ""
var _refusals_before: PackedStringArray = PackedStringArray()
static var _commands_built: bool = false


## The app's commands in the `InputMap`, as `test_rebind_survives.gd` builds
## them, because `view_zoom_in` is one of the router's own.
func _build_app_commands() -> void:
    if _commands_built:
        return
    _commands_built = true
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var router := ShortcutRouter.new()
    router.bind_commands(registries.commands)
    router.free()


func before_each() -> void:
    _build_app_commands()
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    _saved_profile = SaSettings.shortcuts_profile
    SaShortcutStore.dir_override = scratch_dir
    SaShortcutStore.capture_defaults()
    SaSettings.shortcuts_profile = SaShortcutStore.DEFAULT_PROFILE
    _refusals_before = SaProblems.pending_refusals
    SaProblems.pending_refusals = PackedStringArray()


func after_each() -> void:
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    SaSettings.shortcuts_profile = _saved_profile
    _remove_scratch(scratch_dir)
    SaShortcutStore.dir_override = ""
    SaProblems.pending_refusals = _refusals_before


func _remove_scratch(path: String) -> void:
    var dir := DirAccess.open(path)
    if dir == null:
        return
    for sub: String in dir.get_directories():
        _remove_scratch(path.path_join(sub))
        DirAccess.remove_absolute(path.path_join(sub))
    for file: String in dir.get_files():
        dir.remove(file)


## Presses Save As as the painter would, through the button beside the name.
func _press_save_as(page: SaShortcutsPage) -> void:
    (page.save_as_name.get_parent().get_node("SaveAsButton") as Button).pressed.emit()


func _refused_naming(fragment: String) -> bool:
    for line: String in SaProblems.pending_refusals:
        if line.contains(fragment):
            return true
    return false


func test_save_as_a_name_with_a_slash_keeps_the_profile_in_use_and_says_so() -> void:
    var page := SaShortcutsPage.new()
    page.rebind(&"view_zoom_in", "Ctrl+Alt+I")
    var was := SaSettings.shortcuts_profile
    SaProblems.pending_refusals = PackedStringArray()

    page.save_as_name.text = "mine a/b"
    _press_save_as(page)

    assert_eq(SaSettings.shortcuts_profile, was, "The profile in use is the one it was before")
    assert_true(_refused_naming("mine a/b"), "and the painter is told the name could not be saved")
    assert_eq(SaShortcutStore.save_profile("mine a/b"), -1, "A save that wrote no file answers -1, not the 0 of nothing changed")
    assert_false(FileAccess.file_exists(SaShortcutStore.path_for("mine a/b")), "and no file stands under the name")
    page.free()


## A name only Windows refuses is refused here too, so a profile made on Linux
## is not one Windows cannot open.
func test_a_name_windows_refuses_is_refused_everywhere() -> void:
    SaShortcutStore.set_chords(&"view_zoom_in", ["Ctrl+Alt+I"])
    assert_eq(SaShortcutStore.save_profile("Krita: mine"), -1, "A colon gives no file")
    assert_true(_refused_naming("Krita: mine"), "and a refusal naming it")


## Through the store, as Quick Assign rebinds, because the page shows a profile
## with no file as Sara Default and puts the setting there itself.
func test_a_rebind_under_a_profile_whose_file_cannot_be_written_leaves_the_setting_and_says_so() -> void:
    SaSettings.shortcuts_profile = "mine a/b"

    SaShortcutStore.set_chords(&"view_zoom_in", ["Ctrl+Alt+I"])
    var answered := SaShortcutStore.remember_edit()

    assert_eq(SaSettings.shortcuts_profile, "mine a/b", "The setting stays where it was")
    assert_eq(answered, "mine a/b", "and remember_edit answers the profile it left in place")
    assert_true(_refused_naming("mine a/b"), "and the painter is told the save failed")


func test_save_as_a_plain_name_writes_its_file_and_becomes_the_profile_in_use() -> void:
    var page := SaShortcutsPage.new()
    page.rebind(&"view_zoom_in", "Ctrl+Alt+I")
    SaProblems.pending_refusals = PackedStringArray()

    page.save_as_name.text = "mine"
    _press_save_as(page)

    assert_eq(SaSettings.shortcuts_profile, "mine", "A plain name becomes the profile in use")
    assert_true(FileAccess.file_exists(SaShortcutStore.path_for("mine")), "with its file written")
    var stored := SaShortcutStore.load_profile("mine")
    assert_eq(stored.get("view_zoom_in", []), ["Ctrl+Alt+I"] as Array[String], "which reads the rebind back")
    assert_eq(SaProblems.pending_refusals.size(), 0, "and nothing is refused")
    page.free()
