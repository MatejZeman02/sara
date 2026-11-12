## The pattern store remembers a file it could not read: the
## file is opened once, the refusal is said once through `SaProblems`, a
## second listing and a rescan add nothing, and a file rewritten on disk is
## read again. The store is one per module, so the dab and the chooser read
## the store the settings carry rather than making their own.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Taken from the Gemini CLI trial of 2026-09-13, `trial/gemini-pattern-store`,
## which proved the right two things through five static doors on the class.
## The observations here are the two the private-member rule leaves: problem
## reports counted through a sink, and the store's own `_failed` read from
## outside, which the rule allows and a getter would not add to.
##
## Broken `.pat` files rather than a torn `.png`, because `SaImageImport`
## reports a picture it cannot read on its own and the count would then be
## two lines per file, one of them not this unit's.
extends "res://tests/test_framework.gd"

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## The dab holds a tone pass, which holds a compute.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_pattern_store")
const TORN := "torn_paper.pat"
const TORN_NAME := "Torn Paper"

var _reports: PackedStringArray = PackedStringArray()


func before_each() -> void:
    SaProblems.announce = false
    SaProblems.attach_sink(_keep)
    _reports = PackedStringArray()
    DirAccess.make_dir_recursive_absolute(scratch_dir)


func after_each() -> void:
    SaProblems.detach_sink()
    SaProblems.announce = true
    if DirAccess.dir_exists_absolute(scratch_dir):
        var dir := DirAccess.open(scratch_dir)
        for file in dir.get_files():
            dir.remove(file)
        DirAccess.remove_absolute(scratch_dir)


func _keep(line: String, _kind: int) -> void:
    _reports.append(line)


func _write(file_name: String, bytes: PackedByteArray) -> String:
    var path := scratch_dir.path_join(file_name)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(bytes)
    file.close()
    return path


func test_a_file_that_cannot_be_read_is_read_once_and_said_once() -> void:
    var path := _write(TORN, PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]))
    var store := SaPatternStore.new([scratch_dir])
    assert_true(store.has(TORN_NAME), "A file the reader will refuse is listed, because listing opens nothing")
    assert_eq(_reports.size(), 0, "and listing says nothing")

    var pattern := store.pattern(TORN_NAME)
    assert_null(pattern.image_at(48), "The first ask for its picture answers nothing")
    assert_true(pattern.error.contains("too short"), "and quotes the reader's reason: %s" % pattern.error)
    assert_eq(_reports.size(), 1, "The refusal is said once")
    assert_true(_reports[0].contains(TORN), "naming the file: %s" % _reports[0])
    assert_true(store._failed.has(path), "and the store remembers the path")
    assert_eq(String(store._failed[path]["reason"]), pattern.error, "with the reason")

    assert_null(pattern.image_at(48), "The second ask answers nothing")
    assert_null(pattern.texture(), "and so does the texture")
    assert_eq(_reports.size(), 1, "with no second report")
    store.names()
    store.names()
    assert_eq(_reports.size(), 1, "and two listings after it add none")


func test_a_rescan_lists_the_file_again_and_reads_it_no_more() -> void:
    var path := _write(TORN, PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]))
    var store := SaPatternStore.new([scratch_dir])
    var first := store.pattern(TORN_NAME)
    first.image_at(48)
    assert_eq(_reports.size(), 1, "The first pattern object reports the read")

    store.rescan()
    assert_true(store.has(TORN_NAME), "After a rescan the file is still listed")
    var second := store.pattern(TORN_NAME)
    assert_true(second != first, "as a new pattern object")
    assert_null(second.image_at(48), "which answers nothing")
    assert_eq(second.error, first.error, "with the reason the store kept")
    assert_eq(_reports.size(), 1, "and no report, because the file was not opened")
    assert_true(store._failed.has(path), "and the record stands")


func test_a_file_rewritten_on_disk_is_read_again() -> void:
    var path := _write(TORN, PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]))
    var store := SaPatternStore.new([scratch_dir])
    store.pattern(TORN_NAME).image_at(48)
    assert_eq(_reports.size(), 1, "The first read is reported")

    # A different length, because a rewrite inside the same second keeps the
    # modification time and the size is the second half of the stamp.
    _write(TORN, PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]))
    store.rescan()
    var again := store.pattern(TORN_NAME)
    assert_null(again.image_at(48), "The rewritten file is read and refused again")
    assert_eq(_reports.size(), 2, "and said again, because it is a different file now")
    assert_true(store._failed.has(path), "and the record is the new file's")
    assert_eq(int(store._failed[path].stamp["size"]), 12, "at its new size")


func test_a_mended_file_is_read_again_and_drops_its_record() -> void:
    var path := _write(TORN, PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]))
    var store := SaPatternStore.new([scratch_dir])
    store.pattern(TORN_NAME).image_at(48)
    assert_eq(_reports.size(), 1, "The torn file is reported")

    var texels := PackedByteArray()
    texels.resize(4 * 4)
    texels.fill(128)
    _write(TORN, _pat_bytes(4, 4, 1, "Mended", texels))
    store.rescan()
    var mended := store.pattern(TORN_NAME)
    assert_not_null(mended.image_at(4), "The mended file reads")
    assert_eq(mended.error, "", "with nothing wrong")
    assert_false(store._failed.has(path), "and the record is gone")
    assert_eq(_reports.size(), 1, "with nothing new said")


func test_the_dab_and_the_chooser_read_the_store_the_settings_carry() -> void:
    var store := SaPatternStore.new([scratch_dir])
    var settings := SettingsScript.new()
    settings.pattern_store = store
    settings.pattern_name = TORN_NAME
    var dab := SaDabPattern.new()
    dab.texture(settings)
    assert_true(dab.store() == store, "The dab resolves the settings' store")
    var handed := SaDabPattern.new(SaPatternStore.new([scratch_dir]))
    handed.texture(settings)
    assert_true(handed.store() != store, "and a store handed to the constructor wins over it")
    var chooser := SaTexturePage.build_chooser(null, Callable(), store) as SaPatternChooser
    assert_true(chooser.store == store, "The page's chooser lists from the store bound into its factory")
    chooser.free()
    var own := SaTexturePage.build_chooser(null, Callable()) as SaPatternChooser
    assert_not_null(own.store, "and one built without a store makes its own")
    own.free()


func _pat_bytes(width: int, height: int, channels: int, pat_name: String, texels: PackedByteArray) -> PackedByteArray:
    var name_bytes := pat_name.to_utf8_buffer()
    name_bytes.append(0)
    var out := PackedByteArray()
    var header := [
        SaPatternPat.HEADER_BYTES + name_bytes.size(), SaPatternPat.VERSION, width, height, channels, SaPatternPat.MAGIC
    ]
    for word: int in header:
        out.append_array(PackedByteArray([(word >> 24) & 0xFF, (word >> 16) & 0xFF, (word >> 8) & 0xFF, word & 0xFF]))
    out.append_array(name_bytes)
    out.append_array(texels)
    return out
