## Sara shows its welcome window before the rest of the boot.
##
## `SaBoot` shows the window and then builds `Main` in stages behind it, so for a
## few seconds the window is up and nothing it opens into exists yet. What it
## offers in that time waits for `EventBus.boot_finished`: the recent cards are
## dimmed and hold the one chosen, New and Open are disabled, and the recovery
## row's Open is too. The boot itself, from the first frame to the ready mark,
## is measured on the running app by
## `scenarios/sara-shows-its-welcome-window-before-the-rest-of-the-boot.json`.
##
## Each test emits `boot_finished` itself, the way `Main` does at the end of its
## last stage, and builds only what it asks about.
extends "res://tests/test_framework.gd"

static var scratch_first: String = SaDataRoot.path("q21-first.sad")
static var scratch_second: String = SaDataRoot.path("q21-second.sad")


## The document flow with its open recorded rather than performed, as
## `test_recent_grid.gd` records it.
class RecordingFiles:
    extends SaDocumentFiles

    var opened: Array[String] = []

    func open_path(path: String) -> void:
        opened.append(path)


var _saved_recent: Array = []


func before_each() -> void:
    _saved_recent = SaSettings.recent_files()
    for path: String in _saved_recent:
        SaSettings.remove_recent_file(str(path))
    for path: String in [scratch_second, scratch_first]:
        var file := FileAccess.open(path, FileAccess.WRITE)
        file.store_string("a document the card only has to find")
        file.close()
        SaSettings.add_recent_file(path)


func after_each() -> void:
    for path: String in [scratch_first, scratch_second]:
        SaSettings.remove_recent_file(path)
        DirAccess.remove_absolute(path)
    for i in range(_saved_recent.size() - 1, -1, -1):
        SaSettings.add_recent_file(str(_saved_recent[i]))


func test_a_recent_document_chosen_during_the_boot_opens_once_it_is_done() -> void:
    var files := RecordingFiles.new()
    var grid := WelcomeRecentGrid.new(files, true)
    assert_eq(grid.cards.size(), 2, "one card a recent document")
    for row: Dictionary in grid.row_report():
        assert_true(row["held"], "every card is held while Sara boots: %s" % row["path"])
    assert_true(grid.cards[0].get_parent().modulate.a < 1.0, "and drawn dimmed")

    grid.cards[1].pressed.emit()
    assert_eq(files.opened.size(), 0, "a card chosen during the boot opens nothing yet")
    var report := grid.row_report()
    assert_false(report[1]["held"], "the chosen card is drawn whole")
    assert_true(report[0]["held"], "and the others stay dimmed")
    assert_eq(grid.cards[1].get_parent().modulate.a, 1.0, "the chosen card's box is not faded")

    EventBus.boot_finished.emit()
    assert_eq(files.opened, [scratch_second] as Array[String], "the boot is done and the chosen document opens")
    for row: Dictionary in grid.row_report():
        assert_false(row["held"], "and no card is held any more: %s" % row["path"])

    grid.cards[0].pressed.emit()
    assert_eq(files.opened, [scratch_second, scratch_first] as Array[String], "a card pressed after the boot opens at once")
    grid.free()
    files.free()


func test_a_card_chosen_twice_during_the_boot_opens_the_last_one_only() -> void:
    var files := RecordingFiles.new()
    var grid := WelcomeRecentGrid.new(files, true)
    grid.cards[0].pressed.emit()
    grid.cards[1].pressed.emit()
    EventBus.boot_finished.emit()
    assert_eq(files.opened, [scratch_second] as Array[String], "the painter changed their mind, and the last choice is the one")
    grid.free()
    files.free()


func test_a_grid_built_after_the_boot_holds_nothing() -> void:
    var files := RecordingFiles.new()
    var grid := WelcomeRecentGrid.new(files)
    for row: Dictionary in grid.row_report():
        assert_false(row["held"], "Help's welcome window is built after the boot: %s" % row["path"])
    grid.cards[0].pressed.emit()
    assert_eq(files.opened, [scratch_first] as Array[String], "and a card opens on the press")
    grid.free()
    files.free()


func test_new_and_open_wait_for_the_boot() -> void:
    var window := SaWelcomeWindow.new(true)
    var new_button := window.find_child("NewButton", true, false) as Button
    var open_button := window.find_child("OpenButton", true, false) as Button
    assert_true(new_button.disabled, "nothing answers New before the File menu exists")
    assert_true(open_button.disabled, "nor Open")
    EventBus.boot_finished.emit()
    assert_false(new_button.disabled, "both work once Sara is whole")
    assert_false(open_button.disabled, "Open as well")
    window.free()

    var later := SaWelcomeWindow.new()
    assert_false((later.find_child("NewButton", true, false) as Button).disabled, "a window built after the boot is live at once")
    later.free()


func test_the_recovery_rows_open_waits_for_the_boot() -> void:
    var row := WelcomeRecoveryRow.new(true)
    row.refresh([{"copy": SaDataRoot.path("q21-no-copy.sad"), "original": scratch_first}])
    var open := row.find_child("RecoveryOpen0", true, false) as Button
    assert_true(open != null and open.disabled, "the autosave that opens a copy does not exist yet")
    EventBus.boot_finished.emit()
    open = row.find_child("RecoveryOpen0", true, false) as Button
    assert_true(open != null and not open.disabled, "and the row is drawn again with Open live")
    row.free()


func test_the_boot_reads_the_capture_flags_without_the_harness() -> void:
    assert_true(SaBoot.capture_requested(PackedStringArray(["--capture"])), "a bare capture flag")
    assert_true(SaBoot.capture_requested(PackedStringArray(["--capture=/tmp/x.json"])), "a capture with its scenario")
    assert_true(SaBoot.capture_requested(PackedStringArray(["--agent-socket=/tmp/door"])), "a door session")
    assert_false(SaBoot.capture_requested(PackedStringArray(["--agent-socket="])), "an empty socket opens no door")
    assert_false(SaBoot.capture_requested(PackedStringArray([scratch_first])), "a document is not a capture")


func test_a_batch_announces_its_commands_once() -> void:
    var registry := SaCommandRegistry.new()
    var announced: Array[int] = [0]
    registry.changed.connect(func() -> void: announced[0] += 1)
    var register_three := func() -> void:
        for i in 3:
            var descriptor := SaCommandDescriptor.new()
            descriptor.id = StringName("q21_batch_%d" % i)
            descriptor.title = "Batch %d" % i
            registry.register(descriptor)
    registry.batch(register_three)
    assert_eq(announced[0], 1, "three commands in a batch, one announcement")
    assert_true(registry.has(&"q21_batch_2"), "and every one of them is in the registry")

    var single := SaCommandDescriptor.new()
    single.id = &"q21_single"
    single.title = "Single"
    registry.register(single)
    assert_eq(announced[0], 2, "outside a batch each register announces as before")


func test_the_kernels_stage_ends_once_and_answers_done_after() -> void:
    assert_true(GlobalShaderCompiler.compile_kernels(), "the gate's runner compiled every kernel before its suites")
    assert_true(GlobalShaderCompiler.compile_kernels(0), "and asking again with no time at all is done at once")
    assert_true(SaBootMarks.has_mark(&"kernels_end"), "the stage marked its end")


func test_the_module_scripts_the_boot_loads_early_are_the_packaged_modules() -> void:
    var paths := ModuleLoader.packaged_script_paths()
    assert_true(paths.size() > 0, "Sara ships modules")
    for path: String in paths:
        assert_true(path.get_file() == "module.gd" and ResourceLoader.exists(path), "each a module script: %s" % path)


func test_the_longest_boot_frame_is_kept() -> void:
    SaBootMarks.boot_frame()
    OS.delay_usec(50)  # two calls inside one microsecond made no wait at all
    SaBootMarks.boot_frame()
    var t := SaBootMarks.table()
    assert_true(t.has("longest_boot_frame_ms"), "two frames make a wait between them")
    assert_true(float(t["longest_boot_frame_from_ms"]) > 0.0, "and it says when that wait began")
