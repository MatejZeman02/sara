## What Sara opens when a path arrives on the command line.
##
## The bug was that nothing read the command line at all, so "Open with > Sara"
## from a file manager started an empty canvas. The parsing is tested here from
## a list rather than from a process, because a suite cannot launch one, and
## the loading itself is already covered by the export suites.
extends "res://tests/test_framework.gd"

static var scratch_probe: String = SaDataRoot.path("main_arguments_probe.sad")


func before_each() -> void:
    var file := FileAccess.open(scratch_probe, FileAccess.WRITE)
    file.store_string("not really a document")
    file.close()


func after_each() -> void:
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_probe))


func test_the_first_argument_that_names_a_file_is_the_document() -> void:
    assert_eq(SaBoot.document_path(PackedStringArray([scratch_probe])), scratch_probe, "A path on its own")
    assert_eq(
        SaBoot.document_path(PackedStringArray(["--capture", scratch_probe])),
        scratch_probe,
        "and after an option that takes none"
    )


func test_an_option_is_never_read_as_a_path() -> void:
    var only_options := PackedStringArray(["--capture=scenarios/probe.json", "--capture-out=/tmp/out", "-v"])
    assert_eq(SaBoot.document_path(only_options), "", "Nothing here names a file")
    assert_eq(SaBoot.document_path(PackedStringArray()), "", "and neither does an empty command line")


## A typo at a terminal opens no empty canvas and is not silent.
func test_a_path_that_is_not_there_is_reported_rather_than_ignored() -> void:
    var reported_before: int = SaProblems.pending.size()
    SaProblems.announce = false
    var opened := SaBoot.document_path(PackedStringArray([SaDataRoot.path("no_such_file.sad")]))
    SaProblems.announce = true

    assert_eq(opened, "", "Nothing is opened")
    assert_eq(SaProblems.pending.size(), reported_before + 1, "and the painter is told why")


## The first path is the one `document_path` answers, and a second that is not
## there is reported without taking it away. Every path
## opens in a tab of its own, which `document_paths` lists.
func test_only_the_first_path_is_taken() -> void:
    var both := PackedStringArray([scratch_probe, SaDataRoot.path("no_such_file.sad")])
    SaProblems.announce = false
    assert_eq(SaBoot.document_path(both), scratch_probe, "The first one names the document")
    SaProblems.announce = true
