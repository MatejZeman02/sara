## A colours file a crash or a hand edit has broken is moved aside, the swatches
## come back from the backup the last save kept, and the painter is told where
## the broken file is. A missing file is a first run and says nothing.
extends "res://tests/test_framework.gd"

const GARBAGE := "this is not a colours file ][ = ="

static var scratch_path: String = SaDataRoot.path("test_colors.cfg")


func _siblings() -> Array[String]:
    return [
        scratch_path,
        scratch_path + SaConfigLadder.BACKUP_SUFFIX,
        scratch_path + SaConfigLadder.BROKEN_SUFFIX,
        scratch_path + SaConfigLadder.TEMP_SUFFIX,
    ]


func after_each() -> void:
    for path: String in _siblings():
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _store() -> SaColorStore:
    var store := SaColorStore.new()
    store.path = scratch_path
    return store


func _write(path: String, text: String) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(text)
    file.close()


func _read(path: String) -> String:
    return FileAccess.get_file_as_string(path)


## Every fault a body provokes, with the log left quiet. `attach_sink` drains
## what was kept before it, which is another suite's and not this one's.
func _reports(body: Callable) -> PackedStringArray:
    var lines := PackedStringArray()
    var announcing := SaProblems.announce
    SaProblems.announce = false
    SaProblems.attach_sink(func(line: String, _kind: SaProblems.Kind) -> void: lines.append(line))
    lines.clear()
    body.call()
    SaProblems.detach_sink()
    SaProblems.announce = announcing
    return lines


## A store whose every edit saved, so the backup holds the colours before the
## last edit, which are the ones a crash in the middle of its save would leave.
func _saved_twice() -> void:
    var store := _store()
    store.add_swatch(Color.RED, "Brick")
    store.add_swatch(Color.GREEN, "Moss")
    store.note_used(Color.BLUE)
    store.add_swatch(Color.YELLOW, "Straw")
    store.free()


func test_a_broken_file_is_kept_aside_and_the_swatches_come_back_from_the_backup() -> void:
    _saved_twice()
    assert_true(FileAccess.file_exists(scratch_path + SaConfigLadder.BACKUP_SUFFIX), "The second save kept the first as a backup")
    _write(scratch_path, GARBAGE)

    var store := _store()
    var lines := _reports(func() -> void: store.load_from(scratch_path))

    assert_eq(store.swatches, [Color.RED, Color.GREEN] as Array[Color], "The swatches came back from the backup")
    assert_eq(store.swatch_names, ["Brick", "Moss"] as Array[String], "and their names")
    assert_eq(store.recent.front(), Color.BLUE, "and the recent list")
    assert_eq(_read(scratch_path + SaConfigLadder.BROKEN_SUFFIX), GARBAGE, "The garbage is kept beside it as the broken file")
    assert_eq(lines.size(), 1, "One report says so: %s" % [lines])
    assert_true(lines.size() == 1 and lines[0].contains(scratch_path + SaConfigLadder.BROKEN_SUFFIX), "and names the broken file")
    assert_true(lines.size() == 1 and lines[0].contains("came back"), "and says the swatches were restored")

    var again := _store()
    again.load_from(scratch_path)
    assert_eq(again.swatches, [Color.RED, Color.GREEN] as Array[Color], "The restored colours were written back at once")
    store.free()
    again.free()


func test_a_broken_file_with_no_backup_leaves_defaults_and_the_broken_file_survives_a_pick() -> void:
    _write(scratch_path, GARBAGE)

    var store := _store()
    var lines := _reports(func() -> void: store.load_from(scratch_path))

    assert_eq(store.foreground, SaColorStore.DEFAULT_FOREGROUND, "The default foreground is in use")
    assert_eq(store.background, SaColorStore.DEFAULT_BACKGROUND, "over the default background")
    assert_true(store.swatches.is_empty(), "with no swatches")
    assert_eq(lines.size(), 1, "One report says so: %s" % [lines])
    assert_true(lines.size() == 1 and lines[0].contains(scratch_path + SaConfigLadder.BROKEN_SUFFIX), "and names the broken file")

    store.note_used(Color.ORANGE)
    var kept := _read(scratch_path + SaConfigLadder.BROKEN_SUFFIX)
    assert_eq(kept, GARBAGE, "The broken file still holds the garbage after a pick saved")
    store.free()


func test_a_missing_file_says_nothing_and_a_save_leaves_no_temporary_file() -> void:
    var store := _store()
    var lines := _reports(func() -> void: store.load_from(scratch_path))
    assert_eq(lines.size(), 0, "A first run is no fault: %s" % [lines])
    assert_eq(store.foreground, SaColorStore.DEFAULT_FOREGROUND, "and starts on the defaults")

    store.add_swatch(Color.PURPLE, "Plum")
    assert_true(FileAccess.file_exists(scratch_path), "The swatch's save wrote the file")
    assert_false(FileAccess.file_exists(scratch_path + SaConfigLadder.TEMP_SUFFIX), "and left no temporary file behind")
    store.free()
