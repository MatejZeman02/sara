## The shipped Krita profile is Krita's, read out of Krita rather than
## remembered.
##
## `KRITA_DEFAULTS` was 23 entries typed from a painter's own exported map,
## which is one painter's file and not Krita's stock one, so a chord Krita ships
## and a painter never rebound was in neither table. It is rebuilt from Krita
## 5.2.13's `krita/krita.action`, `krita/kritamenu.action`,
## `krita/data/actions/*.action` and `plugins/**/*.action`, the 201 actions among
## them with a non-empty `<shortcut>`.
##
## What this suite holds is the shape of the table rather than its contents: an
## entry that names nothing, or spells a chord in a way `parse_chord` cannot
## read, is a line in a profile that silently does nothing. The mapping itself,
## which Krita action each row came from, is the record and is prose because it
## is a judgement about two programs rather than a fact about this one.
extends "res://tests/test_framework.gd"

## A registered command builds an InputMap action, so the actions this suite
## looks for only exist once the commands have been registered. Same fixture
## `ui/shortcuts/tests/test_command_chords.gd` uses, and the same reason: `project.godot`
## carries the tools and the brush keys, the registry carries everything else.
const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")

## The base module as well, through the door the app uses, because four rows of
## the Krita table are its filters. Run alone, as the area gate runs it, the
## suite found no action for them: only another suite's leftovers had put them
## in the InputMap.
const BASE_MODULE := "res://modules/sara-base-modules/base/module.gd"


func before_each() -> void:
    var registries := Fixtures.make_registries()
    _base = load(BASE_MODULE).new()
    _base.register(registries.context.for_module(_base.get_id()))
    _context = registries.context
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    _router = ShortcutRouter.new()
    _router.bind_commands(registries.commands)
    # After the commands, so the restore keeps the actions they made, which the
    # suites after this one find already there and never make again.
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()


func after_each() -> void:
    if _base != null:
        _base.unregister(_context)
    _base = null
    _context = null
    if _router != null:
        _router.free()
        _router = null
    # A case that switched profiles leaves the map as it found it, Sara Default
    # and no action a table wrote into being.
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)


var _router: ShortcutRouter = null
var _saved_events: Dictionary = {}

## Krita 5.2.13's stock chords, the fixture fed Import from Krita.
const STOCK: String = "res://scenarios/fixtures/krita-stock.shortcuts"

## Where the cases save an import and write the exports they read.
static var scratch_profiles: String = SaDataRoot.path("test_krita_profile_imports")

## The document the case saves with Ctrl+Alt+S, and its size.
static var scratch_document: String = SaDataRoot.path("n59-saved-with-ctrl-alt-s.sad")
const SAVE_SIZE := Vector2i(64, 64)
var _base: SaModule = null
var _context: SaContext = null

## Krita chords a Sara action deliberately does not take. Each is a key Krita
## spends on something Sara does not have, so the profile leaves Sara's own
## chord in place and this list is why that is not an omission.
const NOT_TAKEN := {
    "Ctrl+Shift+Y": "Krita's gamut warning. Sara's Ctrl+Shift+Y is the minimap proof, which is a different question.",
    "Tab": "Krita's Show Canvas Only. Sara's Tab already toggles every docker, which is the same gesture under another name.",
}


func _tables() -> Array:
    return [["Krita", SaShortcutStore.KRITA_DEFAULTS], ["Photoshop", SaShortcutStore.PHOTOSHOP_DEFAULTS]]


## The requirement: every entry names something the InputMap has, so a
## profile switch reaches an action rather than writing into a name nobody
## answers to.
func test_every_profile_entry_names_an_action_the_build_has() -> void:
    for table: Array in _tables():
        var missing: Array[String] = []
        for action: String in table[1] as Dictionary:
            if not InputMap.has_action(StringName(action)):
                missing.append(action)
        assert_true(missing.is_empty(), "%s names an action this build does not have: %s" % [table[0], ", ".join(missing)])


## And every chord in them parses. A chord `parse_chord` cannot read is applied
## as nothing at all, which is a row in the Keyboard Shortcuts page that empties
## itself on a profile switch and says nothing about why.
func test_every_profile_chord_parses() -> void:
    for table: Array in _tables():
        var unreadable: Array[String] = []
        var chords: Dictionary = table[1]
        for action: String in chords:
            # An empty entry is deliberate: it clears Sara's own chord for an
            # action the other program does not chord at all. A list is read
            # chord by chord, Save's two under Krita among them.
            for text: String in SaShortcutStore.entry_chords(chords[action]):
                if SaShortcutStore.parse_chord(text) == null:
                    unreadable.append("%s = '%s'" % [action, text])
        assert_true(unreadable.is_empty(), "%s spells a chord nothing reads: %s" % [table[0], ", ".join(unreadable)])


## No two actions in one profile ask for the same chord. A profile that ships a
## clash is a conflict marker on the Keyboard Shortcuts page the moment it is
## selected, which is the app apologising for its own table.
func test_no_profile_puts_two_actions_on_one_chord() -> void:
    for table: Array in _tables():
        var seen: Dictionary = {}
        var clashes: Array[String] = []
        var chords: Dictionary = table[1]
        for action: String in chords:
            for text: String in SaShortcutStore.entry_chords(chords[action]):
                if seen.has(text):
                    clashes.append("%s and %s both want %s" % [seen[text], action, text])
                seen[text] = action
        assert_true(clashes.is_empty(), "%s: %s" % [table[0], ", ".join(clashes)])


## The alpha lock is cleared under Krita because Krita chords no alpha lock.
## It is not a collision the table introduces, as it would be if Sara's own map
## gave the alpha lock Krita's Deselect.
func test_the_alpha_lock_is_cleared_because_krita_chords_none() -> void:
    assert_true(SaShortcutStore.KRITA_DEFAULTS.has("layer_alpha_lock"), "The Krita profile names the alpha lock")
    assert_eq(String(SaShortcutStore.KRITA_DEFAULTS["layer_alpha_lock"]), "", "and clears it, as Krita chords no alpha lock")
    assert_eq(String(SaShortcutStore.KRITA_DEFAULTS["select_none"]), "Ctrl+Shift+A", "Deselect is Krita's Ctrl+Shift+A")


## A Krita hand pressed Ctrl+Shift+A to drop a selection in
## Sara's own map and locked the layer's alpha. Deselect answers it there now,
## beside Photoshop's Ctrl+D, and Lock Alpha moved to Ctrl+Alt+A, which Krita
## ships for nothing.
func test_sara_default_deselects_on_kritas_chord_and_locks_alpha_on_ctrl_alt_a() -> void:
    var deselect := SaShortcutStore.chords_for(&"select_none")
    assert_true(deselect.has("Ctrl+Shift+A"), "Deselect answers Ctrl+Shift+A: %s" % [deselect])
    assert_true(deselect.has("Ctrl+D"), "and still Ctrl+D: %s" % [deselect])
    var alpha := SaShortcutStore.chords_for(&"layer_alpha_lock")
    assert_eq(alpha, ["Ctrl+Alt+A"] as Array[String], "Lock Alpha answers Ctrl+Alt+A alone")
    var krita_holds: Array[String] = []
    for action: String in SaShortcutStore.KRITA_DEFAULTS:
        if SaShortcutStore.entry_chords(SaShortcutStore.KRITA_DEFAULTS[action]).has("Ctrl+Alt+A"):
            krita_holds.append(action)
    assert_eq(krita_holds, [] as Array[String], "which the Krita table gives to nothing")


## The two rows given a chord because Krita has one and Sara had none: Image
## Size and Canvas Size, which were reachable through the Image menu alone.
func test_the_two_image_dialogs_answer_to_kritas_chords() -> void:
    for pair: Array in [["image_canvas_size", "Ctrl+Alt+C"], ["image_size", "Ctrl+Alt+I"]]:
        var action := StringName(String(pair[0]))
        assert_true(InputMap.has_action(action), "%s is an action" % action)
        var events := InputMap.action_get_events(action)
        assert_false(events.is_empty(), "%s answers to a key" % action)
        var wanted := SaShortcutStore.parse_chord(String(pair[1]))
        var found := false
        for event in events:
            var key := event as InputEventKey
            if key == null:
                continue
            var same_key: bool = key.keycode == wanted.keycode or key.physical_keycode == wanted.keycode
            if (
                same_key
                and key.ctrl_pressed == wanted.ctrl_pressed
                and key.alt_pressed == wanted.alt_pressed
                and key.shift_pressed == wanted.shift_pressed
            ):
                found = true
        assert_true(found, "%s answers to %s, which is Krita's" % [action, pair[1]])


## A bare backslash does not parse and "Backslash" does, which is why the Tool
## Options row is spelled the long way. Held here because the short spelling is
## what Krita's own file says and the next reader will try it.
func test_the_tool_options_chord_is_spelled_the_way_godot_reads_it() -> void:
    assert_null(SaShortcutStore.parse_chord("\\"), "A bare backslash reads as nothing")
    assert_not_null(SaShortcutStore.parse_chord("Backslash"), "and the word is what Godot looks up")
    assert_eq(String(SaShortcutStore.KRITA_DEFAULTS["docker_tool_options"]), "Backslash", "so the table carries the word")


## Every key Krita spends that Sara deliberately leaves alone has a reason
## written beside it, so a later reader can tell a decision from an oversight.
func test_the_chords_left_alone_each_carry_their_reason() -> void:
    for chord: String in NOT_TAKEN:
        assert_false(String(NOT_TAKEN[chord]).is_empty(), "%s says why it is not taken" % chord)
        var taken := false
        for action: String in SaShortcutStore.KRITA_DEFAULTS:
            if SaShortcutStore.entry_chords(SaShortcutStore.KRITA_DEFAULTS[action]).has(chord):
                taken = true
        assert_false(taken, "%s is not in the Krita table after all" % chord)


## Under Krita a painter's Ctrl+Alt+S, Krita's Save Incremental
## Version, saves a changed document rather than doing nothing, and the
## Reference solo it holds in Sara's map answers Ctrl+Alt+D, which no profile
## gives anything else. The solo itself on a shown docker is the unit's
## scenario, since a docker is a `Window` and this suite keeps none in the tree.
func test_ctrl_alt_s_saves_and_ctrl_alt_d_solos_under_krita() -> void:
    assert_eq(SaShortcutStore.holders("Ctrl+Alt+D"), [] as Array[String], "Sara Default gives Ctrl+Alt+D to nothing")
    SaShortcutStore.apply_profile("Photoshop")
    assert_eq(SaShortcutStore.holders("Ctrl+Alt+D"), [] as Array[String], "and nor does Photoshop")
    SaShortcutStore.apply_profile("Krita")
    var save := SaShortcutStore.chords_for(&"file_save")
    assert_eq(save, ["Ctrl+S", "Ctrl+Alt+S"] as Array[String], "Save answers both under Krita")
    assert_eq(SaShortcutStore.holders("Ctrl+Alt+S", &"file_save"), [] as Array[String], "and Ctrl+Alt+S is Save's alone")
    var solo := ReferencePictureView.SOLO_COMMAND
    assert_eq(SaShortcutStore.chords_for(solo), ["Ctrl+Alt+D"] as Array[String], "The solo moved to Ctrl+Alt+D")
    assert_eq(SaShortcutStore.holders("Ctrl+Alt+D", solo), [] as Array[String], "which nothing else answers")

    var canvas := SaCanvas.new()
    canvas.canvas_size = SAVE_SIZE
    canvas.easel = SaEasel.create_default(SAVE_SIZE, null, SaColorSpace.oklab())
    canvas.add_child(canvas.easel)
    var files := SaDocumentFiles.new(func() -> SaCanvas: return canvas)
    _router.file_command = files.run_action
    canvas.document.mark_saved(scratch_document)
    canvas.document.fill_layer(Color.RED)
    canvas.easel.request_full_composite()
    canvas.easel.process_pending_composite()
    assert_true(canvas.document.modified, "The fill is a change to the document")
    assert_true(_router.handle(_pressed("Ctrl+Alt+S")), "Ctrl+Alt+S is taken")
    assert_true(SaSadFile.finish_saves(), "The save runs in the background and ends")
    assert_false(canvas.document.modified, "and the document is saved")
    assert_true(FileAccess.file_exists(scratch_document), "to its own file")

    _router.commands.last_command = &""
    _router.handle(_pressed("Ctrl+Alt+D"))
    assert_eq(_router.commands.last_command, solo, "Ctrl+Alt+D reaches the solo")

    files.free()
    canvas.free()
    SaSettings.remove_recent_file(scratch_document)
    DirAccess.remove_absolute(scratch_document)


## The held eyedropper under Krita is Alt and Ctrl, as Krita's canvas samples on
## Ctrl, and Sara Default keeps Alt alone. A bare modifier reads as that key
## rather than as a modifier holding no key, which is what lets
## `ToolMachine._is_action_held` ask whether it is down.
func test_the_held_eyedropper_is_alt_and_ctrl_under_krita() -> void:
    var ctrl := SaShortcutStore.parse_chord("Ctrl")
    assert_eq(ctrl.keycode, KEY_CTRL, "Ctrl alone is the Ctrl key")
    assert_false(ctrl.ctrl_pressed, "and not a Ctrl with no key")
    var krita := SaShortcutStore.load_profile("Krita")
    assert_eq(krita.get("tool_eyedropper_quick", []), ["Alt", "Ctrl"], "Krita's held eyedropper is Alt and Ctrl")
    var sara := SaShortcutStore.load_profile(SaShortcutStore.DEFAULT_PROFILE)
    assert_false(sara.has("tool_eyedropper_quick"), "and Sara Default names none, so it keeps Alt alone")


## Import from Krita and the Krita
## profile read one table. Every profile row has its row in the action column,
## in the profile's order, so an import reaches every command the profile
## moves. Every Krita action the column names is one row's, Krita chords it
## exactly when the profile gives the row a chord, and a row naming two actions
## lists a chord for each.
func test_every_profile_row_names_its_krita_action_and_every_action_its_row() -> void:
    var chords := SaShortcutKritaTable.CHORDS
    var actions := SaShortcutKritaTable.ACTIONS
    var profile_rows: Array = actions.keys().filter(func(command: String) -> bool: return chords.has(command))
    assert_eq(profile_rows, chords.keys(), "the action column holds every profile row, in the profile's order")
    var stock := _stock_actions()
    var row_of: Dictionary[String, String] = {}
    var wrong: Array[String] = []
    for command: String in actions:
        if not InputMap.has_action(StringName(command)):
            wrong.append("%s is no command this build has" % command)
        var named := SaShortcutKritaTable.actions_of(command)
        for action: String in named:
            if row_of.has(action):
                wrong.append("%s is the row of %s and of %s" % [action, row_of[action], command])
            row_of[action] = command
            if stock.has(action) and not chords.has(command):
                wrong.append("Krita chords %s and the profile leaves %s to Sara" % [action, command])
            elif chords.has(command) and not stock.has(action):
                wrong.append("Krita ships %s unbound and the profile gives %s a chord" % [action, command])
        if named.size() > 1 and SaShortcutStore.entry_chords(chords.get(command, "")).size() != named.size():
            wrong.append("%s names %d actions and lists another number of chords" % [command, named.size()])
    assert_eq(wrong, [] as Array[String], "the two columns are one table")
    var save := SaShortcutKritaTable.actions_of("file_save")
    assert_eq(save, ["file_save", "save_incremental_version"] as Array[String], "Save answers two")
    assert_eq(SaShortcutKritaTable.actions_of("docker_reference_solo"), [] as Array[String], "and the solo none")
    # The rows found the import without.
    for pair: Array in [
        ["view_mirror_horizontal", "mirror_canvas"],
        ["window_fullscreen", "fullscreen"],
        ["docker_tool_options", "show_tool_options"],
        ["docker_color_selector", "show_color_selector"],
        ["view_rotate_left", "rotate_canvas_left"],
        ["view_soft_proof", "softProof"],
        ["layer_select_above", "activateNextLayer"],
        ["brush_preset_previous", "previous_preset"],
    ]:
        assert_eq(row_of.get(String(pair[1]), ""), String(pair[0]), "%s is the row of %s" % [pair[1], pair[0]])


## The second half of the case: importing Krita's stock file gives the chords
## picking the Krita profile gives, every action of the map compared. Before
## the import knew thirty of Krita's actions and laid them over Sara
## Default, so the mirror stayed on H, fullscreen on F11, Tool Options on
## Shift+O, the colour selector on Sara Default's letter, and M picked the Marquee.
func test_importing_kritas_stock_file_gives_the_krita_profile() -> void:
    SaShortcutStore.dir_override = scratch_profiles
    SaShortcutStore.apply_profile("Krita")
    var profile := SaShortcutStore.current_map()
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    assert_eq(SaShortcutStore.chords_for(&"view_mirror_horizontal"), ["H"] as Array[String], "Sara Default mirrors on H")

    var reading := SaShortcutStore.import_krita(STOCK)
    var imported := SaShortcutStore.current_map()
    assert_eq(reading.profile, "krita-stock", "the import is saved and applied")
    assert_eq(reading.unread, {}, "and every chord the stock file gives a Sara command reads")
    assert_eq(_apart(profile, imported), [] as Array[String], "the import and the profile give every action the same chords")
    for pair: Array in [
        ["view_mirror_horizontal", "M"],
        ["window_fullscreen", "Ctrl+Shift+F"],
        ["docker_tool_options", "Backslash"],
        ["docker_color_selector", "Shift+I"],
        ["tool_marquee", "Ctrl+R"],
    ]:
        var chord := SaShortcutStore.chord_text(SaShortcutStore.parse_chord(String(pair[1])))
        var holds := SaShortcutStore.chords_for(StringName(String(pair[0])))
        assert_true(holds.has(chord), "%s answers %s after the import: %s" % [pair[0], chord, holds])
    assert_eq(SaShortcutStore.holders("M", &"view_mirror_horizontal"), [] as Array[String], "and M picks no Marquee")
    var zoom := SaShortcutStore.chords_for(&"view_zoom_in")
    var numpad := SaShortcutStore.chord_text(SaShortcutStore.parse_chord("Ctrl+Numpad +"))
    assert_true(zoom.has(numpad), "the numpad's plus stays beside Krita's Ctrl+= on the zoom: %s" % [zoom])

    SaShortcutStore.delete_profile("krita-stock")
    SaShortcutStore.dir_override = ""
    SaSettings.shortcuts_profile = SaShortcutStore.DEFAULT_PROFILE


## Save answers two of Krita's actions and holds both chords in the order the
## table lists them, whichever the file wrote first, and a `none` on one leaves
## the other's chord.
func test_save_reads_both_of_its_krita_actions() -> void:
    var path := _export("save.shortcuts", ["save_incremental_version=Ctrl+Alt+S", "file_save=Ctrl+S"])
    var reading := SaShortcutKritaNames.parse(path)
    assert_eq(reading.overrides.get("file_save", []), ["Ctrl+S", "Ctrl+Alt+S"], "Save holds both, Krita's Save first")
    path = _export("save-none.shortcuts", ["file_save=Ctrl+Alt+S", "save_incremental_version=none"])
    reading = SaShortcutKritaNames.parse(path)
    assert_eq(reading.overrides.get("file_save", []), ["Ctrl+Alt+S"], "a none beside a chord clears nothing")
    path = _export("unbound.shortcuts", ["remove_layer=none"])
    reading = SaShortcutKritaNames.parse(path)
    assert_eq(reading.overrides.get("layer_delete", ["?"]), [], "while a none alone still clears")
    for name: String in ["save.shortcuts", "save-none.shortcuts", "unbound.shortcuts"]:
        DirAccess.remove_absolute(scratch_profiles.path_join(name))


## Krita's Save Custom Shortcuts writes only the actions a painter changed, so a
## file can name one of Save's two actions and say nothing of the other. The
## other keeps the profile's chord: a file unbinding Save Incremental Version
## alone took Ctrl+S off Save while the painter's Krita still saved on it.
func test_a_file_naming_one_of_saves_actions_keeps_the_other() -> void:
    var path := _export("save-one.shortcuts", ["save_incremental_version=none"])
    var reading := SaShortcutKritaNames.parse(path)
    assert_eq(reading.overrides.get("file_save", []), ["Ctrl+S"], "unbinding the incremental save leaves Krita's Save on Ctrl+S")
    path = _export("save-one.shortcuts", ["save_incremental_version=F12"])
    reading = SaShortcutKritaNames.parse(path)
    assert_eq(reading.overrides.get("file_save", []), ["Ctrl+S", "F12"], "and moving it keeps Ctrl+S beside the new key")
    path = _export("save-one.shortcuts", ["file_save=F2"])
    reading = SaShortcutKritaNames.parse(path)
    assert_eq(reading.overrides.get("file_save", []), ["F2", "Ctrl+Alt+S"], "moving Save keeps the incremental save's Ctrl+Alt+S")
    DirAccess.remove_absolute(path)


## Krita's Export Scheme writes every action and `none` on each one it ships
## with no chord, which is Krita's stock as much as its chords are, so such an
## export imports as the profile too. Before, it took Ctrl+, off Preferences,
## which the profile leaves there because Krita binds nothing to it.
func test_an_export_naming_kritas_unbound_actions_gives_the_krita_profile() -> void:
    SaShortcutStore.dir_override = scratch_profiles
    SaShortcutStore.apply_profile("Krita")
    var profile := SaShortcutStore.current_map()
    var lines: Array[String] = []
    for line: String in FileAccess.get_file_as_string(STOCK).split("\n"):
        if line.contains("=") and not line.begins_with("#"):
            lines.append(line)
    var unbound := 0
    for command: String in SaShortcutKritaTable.ACTIONS:
        if not SaShortcutKritaTable.CHORDS.has(command):
            for action: String in SaShortcutKritaTable.actions_of(command):
                lines.append(action + "=none")
                unbound += 1
    lines.append("no_action_sara_has=none")
    assert_true(unbound > 0, "the table names actions Krita ships unbound, which an export writes as none")
    var path := _export("untouched-krita.shortcuts", lines)
    var reading := SaShortcutStore.import_krita(path)
    assert_eq(reading.profile, "untouched-krita", "the export is saved and applied")
    var apart := _apart(profile, SaShortcutStore.current_map())
    assert_eq(apart, [] as Array[String], "the export and the profile give every action the same chords")
    var preferences := SaShortcutStore.chords_for(&"edit_preferences")
    assert_false(preferences.is_empty(), "Preferences keeps Sara's chord through a none Krita ships: %s" % [preferences])
    SaShortcutStore.delete_profile("untouched-krita")
    DirAccess.remove_absolute(path)
    SaShortcutStore.dir_override = ""
    SaSettings.shortcuts_profile = SaShortcutStore.DEFAULT_PROFILE


## A chord the file gives one row comes off every profile row the file did not
## name. A file putting Duplicate Layer on Ctrl+Alt+D left the Reference solo,
## a row the profile places with no Krita action behind it, on the key as well.
func test_a_chord_the_file_gives_comes_off_the_profiles_own_rows() -> void:
    SaShortcutStore.dir_override = scratch_profiles
    SaShortcutStore.apply_profile("Krita")
    var chord := SaShortcutStore.chord_text(SaShortcutStore.parse_chord("Ctrl+Alt+D"))
    assert_true(SaShortcutStore.chords_for(&"docker_reference_solo").has(chord), "the Krita profile solos on Ctrl+Alt+D")
    var path := _export("duplicate.shortcuts", ["duplicatelayer=Ctrl+Alt+D"])
    var reading := SaShortcutStore.import_krita(path)
    assert_eq(reading.profile, "duplicate", "the file is saved and applied")
    var holders := SaShortcutStore.holders(chord)
    assert_eq(holders, ["layer_duplicate"] as Array[String], "Ctrl+Alt+D duplicates the layer and nothing else")
    SaShortcutStore.delete_profile("duplicate")
    DirAccess.remove_absolute(path)
    SaShortcutStore.dir_override = ""
    SaSettings.shortcuts_profile = SaShortcutStore.DEFAULT_PROFILE


## Each action of *profile* whose chords *imported* gives otherwise, in any
## order, as a line naming both.
func _apart(profile: Dictionary[String, Array], imported: Dictionary[String, Array]) -> Array[String]:
    var apart: Array[String] = []
    for action: String in profile:
        var want: Array = profile[action].duplicate()
        var got: Array = imported.get(action, []).duplicate()
        want.sort()
        got.sort()
        if want != got:
            apart.append("%s: profile %s, import %s" % [action, want, got])
    return apart


## Every Krita action the stock fixture gives a chord.
func _stock_actions() -> Dictionary[String, bool]:
    var out: Dictionary[String, bool] = {}
    var file := FileAccess.open(STOCK, FileAccess.READ)
    while file != null and not file.eof_reached():
        var line := file.get_line().strip_edges()
        var split := line.find("=")
        if split > 0 and not line.begins_with("#"):
            out[line.substr(0, split)] = true
    return out


## A `.shortcuts` file in the scratch folder holding *lines* under the section.
func _export(file_name: String, lines: Array[String]) -> String:
    DirAccess.make_dir_recursive_absolute(scratch_profiles)
    var path := scratch_profiles.path_join(file_name)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string("[Shortcuts]\n" + "\n".join(lines) + "\n")
    file.close()
    return path


## *chord* as the press a keyboard sends.
func _pressed(chord: String) -> InputEventKey:
    var event := SaShortcutStore.parse_chord(chord)
    event.pressed = true
    return event
