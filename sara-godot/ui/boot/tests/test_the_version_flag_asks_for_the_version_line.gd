## `sara --version` prints the version and the commit, and exits.
##
## The flag reaches the app past the `--` the launch wrapper puts before the
## user's words, so the boot reads it from the user arguments, and it answers
## to that flag and no other. These cases feed it lists, since a suite cannot
## start a process. The wrapper's `--headless` and the exit are proved against
## an export, in the unit's record.
extends "res://tests/test_framework.gd"

static var scratch_probe: String = SaDataRoot.path("version_flag_probe.sad")


func before_each() -> void:
    var file := FileAccess.open(scratch_probe, FileAccess.WRITE)
    file.store_string("not really a document")
    file.close()


func after_each() -> void:
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_probe))


func test_the_flag_among_the_user_arguments_asks_for_the_line() -> void:
    assert_true(SaBoot.version_requested(PackedStringArray(["--version"])), "On its own")
    assert_true(SaBoot.version_requested(PackedStringArray([scratch_probe, "--version"])), "after a path")
    var before_an_option := PackedStringArray(["--version", "--capture=/tmp/scenario.json"])
    assert_true(SaBoot.version_requested(before_an_option), "before another option")


func test_a_document_path_alone_does_not_ask_for_it() -> void:
    assert_false(SaBoot.version_requested(PackedStringArray([scratch_probe])), "A path from a file manager")
    assert_false(SaBoot.version_requested(PackedStringArray()), "no arguments at all")
    assert_false(SaBoot.version_requested(PackedStringArray(["--agent-help"])), "or another flag")


## Only the flag itself answers: a longer option that begins the same way, a
## value that holds the word, and a file named after it are not the flag.
func test_only_the_whole_flag_asks() -> void:
    assert_false(SaBoot.version_requested(PackedStringArray(["--versions"])), "a longer option")
    assert_false(SaBoot.version_requested(PackedStringArray(["--version=1"])), "a flag with a value")
    assert_false(SaBoot.version_requested(PackedStringArray(["version"])), "the bare word")
    assert_false(SaBoot.version_requested(PackedStringArray(["-version"])), "one dash")


## A path beside the flag is still a path, and the flag is not mistaken for one.
func test_the_flag_is_not_a_document_path() -> void:
    assert_eq(SaBoot.document_path(PackedStringArray(["--version"])), "", "begins with a dash, so it names no file")
