## The autosave fires on quiet, never inside a stroke, and writes where the
## settings send it.
##
## The clock is handed to `tick()`, so minutes pass in a call and
## the suite stays quick. The quiet the save waits for is the Idle After
## preference's, read from it, so the suite holds at whatever the profile
## sets. Every path here is under `user://`, which an offscreen run keeps under
## the checkout's own scratch directory.
extends "res://tests/test_framework.gd"

## The reopen case embeds a real `Window`, because `visibility_changed` is
## not emitted off one outside the tree, and only a run with a RenderingDevice
## has a root to embed it into.
const REQUIRES_GPU := true

static var scratch_doc_path: String = SaDataRoot.path("autosave_probe.sad")


func _remove(path: String) -> void:
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _make() -> Array:
    var easel := SaEasel.create_default(Vector2i(128, 128))
    var autosave := SaAutosave.new()
    autosave.follow_settings = false
    autosave.interval_seconds = 60.0
    autosave.attach(easel.document)
    easel.add_child(autosave)
    return [easel, autosave]


## The Idle After preference's seconds in the milliseconds `tick()` is handed.
func _quiet_msec() -> int:
    return int(SaSettings.idle_after_seconds * 1000.0)


func after_each() -> void:
    _remove(scratch_doc_path)
    _remove(SaAutosave.recovery_path_for(scratch_doc_path))


func test_a_clean_document_is_never_autosaved() -> void:
    var pair := _make()
    var autosave: SaAutosave = pair[1]
    assert_false(autosave.tick(600.0, 1_000_000), "Nothing to write, however long it waits")
    pair[0].free()


func test_the_interval_arms_and_the_quiet_time_fires() -> void:
    var pair := _make()
    var doc: SaDocument = pair[0].document
    var autosave: SaAutosave = pair[1]
    var quiet := _quiet_msec()
    doc.fill_layer(Color.RED)
    autosave.note_activity(10_000)
    assert_false(autosave.tick(30.0, 10_100), "Half the interval is not enough")
    assert_false(autosave.tick(30.0, 10_000 + quiet - 500), "The interval has passed but the painter was busy too lately")
    assert_true(autosave.tick(0.1, 10_000 + quiet + 100), "The Idle After preference's quiet, and it fires")
    assert_true(SaSadFile.finish_saves(), "and the save in the background ends")
    assert_true(FileAccess.file_exists(autosave.last_written), "onto disk")
    assert_true(autosave.last_written.begins_with(SaAutosave.recovery_dir()), "under the data root, for an untitled document")
    assert_true(doc.modified, "and the document still has unsaved changes, because this was not a Save")
    assert_eq(doc.file_path, "", "and still belongs to no file")
    autosave.discard_recovery()
    assert_false(FileAccess.file_exists(autosave.last_written) or autosave.last_written != "", "Discarding removes it")
    pair[0].free()


func test_it_never_fires_inside_a_stroke() -> void:
    var pair := _make()
    var doc: SaDocument = pair[0].document
    var autosave: SaAutosave = pair[1]
    var quiet := _quiet_msec()
    doc.fill_layer(Color.RED)
    doc.begin_stroke(1.0, &"normal")
    doc.stroke_layer.get_or_create_chunk(Vector2i.ZERO)
    autosave.note_activity(0)
    assert_true(autosave.is_stroke_open(), "A dab has landed in the stroke buffer")
    assert_false(autosave.tick(600.0, 900_000), "Ten quiet minutes inside a stroke, and it waits")
    doc.commit_stroke()
    autosave.note_activity(900_000)
    assert_false(autosave.tick(0.1, 900_100), "The commit was a tenth of a second ago")
    assert_true(autosave.tick(0.1, 900_000 + quiet + 200), "and the quiet time after the commit it fires")
    assert_true(SaSadFile.finish_saves(), "and the save in the background ends")
    autosave.discard_recovery()
    pair[0].free()


func test_a_saved_document_gets_its_copy_beside_it() -> void:
    var pair := _make()
    var doc: SaDocument = pair[0].document
    var autosave: SaAutosave = pair[1]
    assert_eq(SaExport.save_sad(doc, scratch_doc_path, 0), OK, "Saved once")
    doc.mark_saved(scratch_doc_path)
    doc.fill_layer(Color.BLUE)
    assert_eq(autosave.save_now(), OK, "The autosave writes")
    assert_true(SaSadFile.finish_saves(), "and the save in the background ends")
    assert_eq(
        autosave.last_written, SaDataRoot.path("autosave_probe.autosave.sad"), "beside the document, as <name>.autosave.sad"
    )
    assert_true(FileAccess.file_exists(autosave.last_written), "and the copy exists")
    assert_true(doc.modified, "The document is still modified")

    doc.mark_saved(scratch_doc_path)
    assert_false(FileAccess.file_exists(SaDataRoot.path("autosave_probe.autosave.sad")), "A real save retires the copy")
    assert_eq(autosave.last_written, "", "and the autosave forgets it")
    pair[0].free()


func test_the_working_file_mode_saves_the_document_itself() -> void:
    var pair := _make()
    var doc: SaDocument = pair[0].document
    var autosave: SaAutosave = pair[1]
    autosave.write_working_file = true
    assert_eq(SaExport.save_sad(doc, scratch_doc_path, 0), OK, "Saved once")
    doc.mark_saved(scratch_doc_path)
    var before := FileAccess.get_file_as_bytes(scratch_doc_path)
    doc.fill_layer(Color.GREEN)
    assert_eq(autosave.save_now(), OK, "The autosave writes")
    assert_true(SaSadFile.finish_saves(), "and the save in the background ends")
    assert_false(doc.modified, "as a Save would, so the flag clears")
    assert_true(FileAccess.get_file_as_bytes(scratch_doc_path) != before, "and the file on disk moved")
    assert_false(
        FileAccess.file_exists(SaAutosave.recovery_path_for(scratch_doc_path)), "with no recovery copy, the file is its own"
    )
    _remove(scratch_doc_path + "1")
    pair[0].free()


func test_an_untitled_document_falls_back_to_a_recovery_copy_in_working_file_mode() -> void:
    var pair := _make()
    var doc: SaDocument = pair[0].document
    var autosave: SaAutosave = pair[1]
    autosave.write_working_file = true
    doc.fill_layer(Color.GREEN)
    assert_eq(autosave.save_now(), OK, "Nothing to write over, so it writes a copy")
    assert_true(SaSadFile.finish_saves(), "and the save in the background ends")
    assert_true(autosave.last_written.begins_with(SaAutosave.recovery_dir()), "under the user directory")
    assert_true(doc.modified, "and claims nothing")
    autosave.discard_recovery()
    pair[0].free()


func test_the_launch_offer_lists_untitled_copies_and_newer_copies_beside_recent_files() -> void:
    # Two documents, because saving the first one would retire its untitled
    # copy, which is the behaviour the previous test pins.
    var untitled_pair := _make()
    untitled_pair[0].document.fill_layer(Color.RED)
    assert_eq(untitled_pair[1].save_now(), OK, "An untitled copy exists")
    assert_true(SaSadFile.finish_saves(), "and the save in the background ends")
    var untitled: String = untitled_pair[1].last_written

    var pair := _make()
    var doc: SaDocument = pair[0].document
    var autosave: SaAutosave = pair[1]
    assert_eq(SaExport.save_sad(doc, scratch_doc_path, 0), OK, "A saved document")
    doc.mark_saved(scratch_doc_path)
    doc.fill_layer(Color.BLUE)
    assert_eq(autosave.save_now(), OK, "with a copy beside it, written after the file")
    assert_true(SaSadFile.finish_saves(), "and the save in the background ends")
    var beside := autosave.last_written

    var found := SaAutosave.find_recoveries([scratch_doc_path, SaDataRoot.path("nowhere.sad")])
    var copies: Array = found.map(func(entry: Dictionary) -> String: return entry["copy"])
    assert_true(copies.has(untitled), "The untitled copy is offered, it shadows nothing")
    assert_true(copies.has(beside), "and the copy newer than its file is offered")
    for entry: Dictionary in found:
        if entry["copy"] == beside:
            assert_eq(entry["original"], scratch_doc_path, "naming the file it belongs to")

    # A copy older than its file is stale. The times are whole seconds, so the
    # copy is dated two seconds before the file by hand rather than waited for.
    var stale := SaAutosave.recovery_path_for(SaDataRoot.path("autosave_stale.sad"))
    assert_eq(SaExport.save_sad(doc, stale, 0), OK, "A copy")
    assert_eq(SaExport.save_sad(doc, SaDataRoot.path("autosave_stale.sad"), 0), OK, "and its file")
    _touch(stale, FileAccess.get_modified_time(SaDataRoot.path("autosave_stale.sad")) - 2)
    var again := SaAutosave.find_recoveries([SaDataRoot.path("autosave_stale.sad")])
    assert_false(
        again.map(func(entry: Dictionary) -> String: return entry["copy"]).has(stale), "A copy older than its file is not offered"
    )

    _remove(untitled)
    _remove(beside)
    _remove(stale)
    _remove(SaDataRoot.path("autosave_stale.sad"))
    untitled_pair[0].free()
    pair[0].free()


## The welcome window's recovery row draws exactly what
## `find_recoveries` found, and its Delete and Later do what the chain's do.
func test_the_recovery_row_draws_what_find_recoveries_found_entry_for_entry() -> void:
    var probe_dir := SaDataRoot.path("w4_recovery_probe")
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(probe_dir))
    var saved := probe_dir.path_join("saved.sad")
    var gone := probe_dir.path_join("gone.sad")
    var pair := _make()
    var doc: SaDocument = pair[0].document
    assert_eq(SaExport.save_sad(doc, saved, 0), OK, "A recent file")
    assert_eq(SaExport.save_sad(doc, SaAutosave.recovery_path_for(saved), 0), OK, "with a copy beside it, written after it")
    assert_eq(SaExport.save_sad(doc, SaAutosave.recovery_path_for(gone), 0), OK, "and a copy whose file is gone")

    var recent := [saved, gone, probe_dir.path_join("never.sad")]
    var found := SaAutosave.find_recoveries(recent)
    var row := WelcomeRecoveryRow.new()
    row.refresh(found)
    var report := row.row_report()
    assert_eq(report.size(), found.size(), "one row per copy found, no more and no fewer")
    assert_eq(row.get_child_count(), found.size(), "and each of them drawn")
    for i in found.size():
        assert_eq(report[i]["copy"], found[i]["copy"], "row %d names the copy find_recoveries gave, in its order" % i)
        assert_eq(report[i]["original"], found[i]["original"], "and the file it shadows")
    var beside_index := -1
    for i in report.size():
        if report[i]["original"] == saved:
            beside_index = i
            assert_eq(report[i]["name"], "saved.sad", "A copy beside a file is named for the file")
            assert_false(String(report[i]["modified"]).is_empty(), "and carries the copy's time")
        elif report[i]["original"] == "":
            assert_eq(report[i]["name"], "an unsaved document", "An untitled copy is named as the chain names it")
    assert_true(beside_index >= 0, "the copy beside the saved file is among them")

    var beside: String = report[beside_index]["copy"]
    var later := row.find_child("RecoveryLater%d" % beside_index, true, false) as Button
    later.pressed.emit()
    assert_true(row.row_report()[beside_index]["put_off"], "Later puts the row off")
    assert_eq(row.get_child_count(), found.size() - 1, "and takes it out of sight")
    assert_true(FileAccess.file_exists(beside), "and leaves the file alone")

    # A fresh row, because Later holds its row off until the window opens again.
    row.free()
    row = WelcomeRecoveryRow.new()
    row.refresh(found)
    var delete := row.find_child("RecoveryDelete%d" % beside_index, true, false) as Button
    delete.pressed.emit()
    assert_false(FileAccess.file_exists(beside), "Delete removes the copy")
    assert_eq(row.row_report().size(), found.size() - 1, "and the row with it")
    assert_eq(
        row.row_report().map(func(entry: Dictionary) -> String: return entry["copy"]).has(beside), false, "that row, not another"
    )

    _remove(saved)
    _remove(SaAutosave.recovery_path_for(gone))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(probe_dir))
    row.free()
    pair[0].free()


## With no copy the row and the container it sits in take no height, and the
## pane asks for the same list the chain would.
func test_an_empty_recovery_row_collapses_its_container() -> void:
    var window := SaWelcomeWindow.new()
    var row := window.recent_pane.recovery_row.get_child(0) as WelcomeRecoveryRow
    assert_not_null(row, "The Recent pane's RecoveryRow holds the row")
    row.refresh([])
    assert_false(row.visible, "Nothing to offer draws nothing")
    assert_false(window.recent_pane.recovery_row.visible, "and its container takes no height")
    row.refresh([{"copy": SaDataRoot.path("nowhere.autosave.sad"), "original": SaDataRoot.path("nowhere.sad")}])
    assert_true(window.recent_pane.recovery_row.visible, "and one copy brings both back")
    window.free()


## The boot offers on one surface: the welcome window's row when it opens, and
## the chain of windows every time it does not, so turning the window off never
## loses a painter their work.
func test_the_chain_still_runs_whenever_the_welcome_window_does_not_open() -> void:
    assert_eq(SaAutosave.surface_at_start(SaWelcomeWindow.wanted_at_start(false, "", false, false)), "chain", "Setting off")
    assert_eq(
        SaAutosave.surface_at_start(SaWelcomeWindow.wanted_at_start(true, "/tmp/a.sad", false, false)), "chain", "A document"
    )
    assert_eq(SaAutosave.surface_at_start(SaWelcomeWindow.wanted_at_start(true, "", true, false)), "chain", "A capture")
    assert_eq(SaAutosave.surface_at_start(SaWelcomeWindow.wanted_at_start(true, "", false, false)), "pane", "A plain start")

    var pair := _make()
    var autosave: SaAutosave = pair[1]
    var recent := [SaDataRoot.path("nowhere.sad")]
    assert_eq(autosave.recoveries_for_pane(recent), SaAutosave.find_recoveries(recent), "The pane asks the chain's own question")
    assert_eq(autosave.offer_surfaces, ["pane"] as Array[String], "and says it did, for the dump")
    pair[0].free()


## Later's row comes back once the window that offered it has closed and
## opened again, driven through the real mechanism rather than by calling the
## private handler that clears it directly. The embedding is
## `test_preferences_chrome.gd`'s `_open_window`, copied rather than
## shared, for the reason it gives: `visibility_changed` is not emitted off a
## `Window` outside the tree, and `tree.root.add_child` fails silently while
## the suite's own root is mid-`_ready`, so the window is hung off `EventBus`
## instead.
func test_later_puts_the_row_off_and_the_window_reopening_clears_it() -> void:
    var pair := _make()
    var doc: SaDocument = pair[0].document
    var autosave: SaAutosave = pair[1]
    doc.fill_layer(Color.RED)
    assert_eq(autosave.save_now(), OK, "an untitled copy on disk, for the window to find on its own")
    assert_true(SaSadFile.finish_saves(), "and the save in the background ends")
    var copy := autosave.last_written
    var last_version_seen := SaSettings.last_version_seen

    var opened := _open_welcome_window()
    var window := opened[0] as SaWelcomeWindow
    var row := window.recent_pane.recovery_row.get_child(0) as WelcomeRecoveryRow
    row.refresh(SaAutosave.find_recoveries(SaSettings.recent_files()))
    var index := _row_index_for(row, copy)
    assert_true(index >= 0, "the copy this test wrote is among what the row found on its own")
    var later := row.find_child("RecoveryLater%d" % index, true, false) as Button
    assert_not_null(later, "the row it belongs to has a Later button")
    later.pressed.emit()
    assert_true(row.row_report()[_row_index_for(row, copy)]["put_off"], "Later puts it off")
    assert_null(row.find_child("RecoveryLater%d" % index, true, false), "and its row leaves the list")

    window.hide()
    window.show()
    var again := _row_index_for(row, copy)
    assert_true(again >= 0, "the reopen finds the same copy again")
    assert_false(row.row_report()[again]["put_off"], "no longer put off, because opening the window clears it")
    assert_not_null(row.find_child("RecoveryLater%d" % again, true, false), "and its row is drawn once more")

    _close_welcome_window(opened)
    SaSettings.last_version_seen = last_version_seen
    autosave.discard_recovery()
    pair[0].free()


## The position in `row_report()` naming *copy*, or -1. Never assumed to be a
## fixed index, because the reopen replaces `entries` with a fresh scan.
func _row_index_for(row: WelcomeRecoveryRow, copy: String) -> int:
    var report := row.row_report()
    for i in report.size():
        if String(report[i]["copy"]) == copy:
            return i
    return -1


## A welcome window in the tree, embedded, with a host to free it by.
func _open_welcome_window() -> Array:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return []
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true

    var host := Node.new()
    host.name = "WelcomeReopenTestHost"
    EventBus.add_child(host)

    var window := SaWelcomeWindow.new()
    host.add_child(window)
    window.show()
    return [window, host, was_embedding]


func _close_welcome_window(opened: Array) -> void:
    if opened.is_empty():
        return
    var window := opened[0] as Window
    if is_instance_valid(window):
        window.hide()
    var host := opened[1] as Node
    host.free()
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = bool(opened[2])


## Sets a file's modification time, the way `touch -d` would. Windows has no
## `touch`, so there PowerShell sets the same time.
func _touch(path: String, unix_time: int) -> void:
    var absolute := ProjectSettings.globalize_path(path)
    if OS.get_name() == "Windows":
        var script := "(Get-Item -LiteralPath '%s').LastWriteTimeUtc = [DateTimeOffset]::FromUnixTimeSeconds(%d).UtcDateTime"
        OS.execute("powershell", ["-NoProfile", "-NonInteractive", "-Command", script % [absolute, unix_time]])
        return
    OS.execute("touch", ["-d", "@%d" % unix_time, absolute])
