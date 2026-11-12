## The Krita and Photoshop profiles
## shipped beside Sara Default, and the Krita importer.
extends "res://tests/test_framework.gd"

## Krita 5.2.13's stock chords, the fixture the page is fed. A
## personal export is on no machine the suite runs on, so a test that read
## one would skip.
const KRITA_EXPORT: String = "res://scenarios/fixtures/krita-stock.shortcuts"

## Where an import made here is saved, and the export holding an unbound action.
static var scratch_dir: String = SaDataRoot.path("test_krita_import_profiles")

## Applying an imported profile rebinds the live InputMap, so every test here
## puts it back the way `test_shortcut_editor.gd` does. The names as well, since
## an import run alone writes the actions it names into being, and the next
## suite would read them as chords the build never shipped.
var _saved_events: Dictionary = {}
var _saved_actions: Array[StringName] = []


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    _saved_actions.assign(InputMap.get_actions())


func after_each() -> void:
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    for action: StringName in InputMap.get_actions():
        if not _saved_actions.has(action):
            InputMap.erase_action(action)


func test_krita_and_photoshop_are_shipped_and_cannot_be_deleted() -> void:
    var profiles := SaShortcutStore.list_profiles()
    assert_true(profiles.has("Krita"), "Krita is a profile")
    assert_true(profiles.has("Photoshop"), "and so is Photoshop")
    assert_true(SaShortcutStore.is_shipped("Krita"), "Krita cannot be changed in place")
    assert_true(SaShortcutStore.is_shipped("Photoshop"), "neither can Photoshop")
    assert_false(SaShortcutStore.delete_profile("Krita"), "Delete refuses a shipped profile")
    assert_false(SaShortcutStore.save_overrides("Krita", {"select_all": ["Ctrl+A"]}), "and so does an import onto its name")


func test_the_krita_profile_answers_a_painters_own_chords() -> void:
    var overrides := SaShortcutStore.load_profile("Krita")
    assert_eq(overrides.get("layer_duplicate", []), ["Ctrl+J"], "Duplicate Layer is Ctrl+J")
    assert_eq(overrides.get("layer_group", []), ["Ctrl+G"], "Group is Ctrl+G")
    assert_eq(overrides.get("edit_undo", []), ["Ctrl+Z"], "Undo is Ctrl+Z")


func test_the_photoshop_profile_answers_its_own_chords() -> void:
    var overrides := SaShortcutStore.load_profile("Photoshop")
    assert_eq(overrides.get("select_none", []), ["Ctrl+D"], "Deselect is Ctrl+D")
    assert_eq(overrides.get("layer_via_copy", []), ["Ctrl+J"], "Layer via Copy is Ctrl+J")


## The two commands a painter arriving from Photoshop
## reaches for that Sara shared and the profile left on Sara's own chords. The
## chords are from memory of Photoshop's defaults, as the table's own note says,
## and they are Fill with Background Color and Create Clipping Mask. The Hand
## tool's H stays off the table, it is the view mirror's chord on every profile.
func test_the_photoshop_profile_holds_background_fill_and_clipping() -> void:
    var overrides := SaShortcutStore.load_profile("Photoshop")
    assert_false(overrides.has("tool_pan"), "Pan is not moved onto the view mirror's H")
    assert_eq(overrides.get("fill_background", []), ["Ctrl+Backspace"], "Fill with Background Colour is Ctrl+Backspace")
    assert_eq(overrides.get("layer_clip_to_below", []), ["Ctrl+Alt+G"], "Clip to Below is Ctrl+Alt+G")


func test_importing_the_stock_export_gives_deselect_and_duplicate() -> void:
    var overrides := SaShortcutKritaNames.parse(KRITA_EXPORT).overrides
    assert_eq(overrides.get("select_none", []), ["Ctrl+Shift+A"], "Deselect imports as Ctrl+Shift+A")
    assert_eq(overrides.get("layer_duplicate", []), ["Ctrl+J"], "Duplicate Layer imports as Ctrl+J")


func test_an_unbound_krita_action_clears_the_chord() -> void:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var path := scratch_dir.path_join("unbound.shortcuts")
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string("[Shortcuts]\nremove_layer=none\n")
    file.close()
    var overrides := SaShortcutKritaNames.parse(path).overrides
    assert_eq(overrides.get("layer_delete", ["?"]), [], "remove_layer=none clears Delete Layer")
    DirAccess.remove_absolute(path)


func test_the_page_saves_an_import_as_a_new_profile_named_after_the_file() -> void:
    SaShortcutStore.dir_override = scratch_dir
    var page := SaShortcutsPage.new()
    page.import_krita_file(KRITA_EXPORT)
    var profiles := SaShortcutStore.list_profiles()
    assert_true(profiles.has("krita-stock"), "the profile is named after the file")
    assert_eq(SaSettings.shortcuts_profile, "krita-stock", "and becomes the active one")

    page.free()
    SaShortcutStore.delete_profile("krita-stock")
    SaShortcutStore.dir_override = ""
    SaSettings.shortcuts_profile = SaShortcutStore.DEFAULT_PROFILE
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
