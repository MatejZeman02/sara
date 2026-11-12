## What a running Sara says about which build it is.
##
## The boot header printed "v0.1.0" from a default argument while project.godot
## said "alpha", and nothing anywhere named a commit. A bug report against a
## version that maps to no commit is a report that cannot be acted on, so the
## version has one source and the commit travels with the export.
extends "res://tests/test_framework.gd"

static var scratch_stamp: String = SaDataRoot.path("test_build_info_stamp.json")
const HEX: String = "0123456789abcdef"


func after_each() -> void:
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_stamp))


func _write_stamp(text: String) -> void:
    var file := FileAccess.open(scratch_stamp, FileAccess.WRITE)
    file.store_string(text)
    file.close()


## Whether the project sits in a checkout, a `.git` folder beside it or the
## file a worktree has there instead.
func _has_git() -> bool:
    var candidate := ProjectSettings.globalize_path("res://").path_join("../.git")
    return DirAccess.dir_exists_absolute(candidate) or FileAccess.file_exists(candidate)


func _is_hex(text: String) -> bool:
    if text.is_empty():
        return false
    for ch in text:
        if not HEX.contains(ch):
            return false
    return true


func test_the_version_comes_from_project_godot_and_is_a_real_version() -> void:
    var version := SaBuildInfo.version()
    assert_eq(version, ProjectSettings.get_setting("application/config/version"), "project.godot is the source")
    var numeric := RegEx.create_from_string("^\\d+\\.\\d+\\.\\d+")
    assert_not_null(numeric.search(version), "and it is a version, not a word like alpha: %s" % version)


## No stamp is the editor's case. The checkout has a .git, so the reader names
## HEAD and says it is a working tree rather than a build. A tree copied out by
## `git archive` has none, which is how the suites run on Windows, and there
## the reader claims no commit at all.
func test_without_a_stamp_the_commit_is_read_from_the_checkout() -> void:
    var info := SaBuildInfo.read(SaDataRoot.path("does_not_exist.json"))
    assert_eq(info["version"], SaBuildInfo.version(), "The version is still the project's")
    if not _has_git():
        assert_eq(info["source"], SaBuildInfo.SOURCE_UNKNOWN, "A tree with no .git names no source")
        assert_eq(info["commit_full"], "", "and no commit")
        skip("this tree has no .git beside it, so no commit is read from one")
        return
    assert_eq(info["source"], SaBuildInfo.SOURCE_WORKING_TREE, "Read from .git, and said so")
    assert_eq(str(info["commit"]).length(), 7, "A short commit")
    assert_true(_is_hex(info["commit"]), "made of hex digits")
    assert_eq(str(info["commit_full"]).length(), 40, "with the full one beside it")
    assert_true(str(info["commit_full"]).begins_with(info["commit"]), "and the short one is its prefix")
    assert_eq(info["built"], "", "Nothing was built")
    assert_false(info["dirty"], "and nothing is claimed about a dirty tree")


func test_a_stamp_from_the_export_wins_and_is_marked_as_an_export() -> void:
    var stamp := {
        "version": "9.8.7",
        "commit": "abcdef0",
        "commit_full": "abcdef0123456789abcdef0123456789abcdef01",
        "dirty": true,
        "built": "2026-09-02T01:12:40Z",
    }
    _write_stamp(JSON.stringify(stamp))
    var info := SaBuildInfo.read(scratch_stamp)
    assert_eq(info["source"], SaBuildInfo.SOURCE_EXPORT, "A stamped build is an export")
    assert_eq(info["version"], "9.8.7", "The version the export was made from")
    assert_eq(info["commit"], "abcdef0", "the commit")
    assert_eq(info["built"], "2026-09-02T01:12:40Z", "when")
    assert_true(info["dirty"], "and whether the tree was clean")


func test_the_one_line_description_names_version_commit_and_provenance() -> void:
    var exported := SaBuildInfo.describe(
        {"version": "0.1.0", "commit": "abcdef0", "source": SaBuildInfo.SOURCE_EXPORT, "built": "2026-09-02T01:12:40Z"}
    )
    assert_eq(exported, "v0.1.0  ·  abcdef0  ·  exported 2026-09-02 01:12 UTC", "A clean export")

    var dirty := SaBuildInfo.describe(
        {"version": "0.1.0", "commit": "abcdef0", "source": SaBuildInfo.SOURCE_EXPORT, "built": "", "dirty": true}
    )
    assert_true(dirty.ends_with("development build"), "A dirty export says so at the end: %s" % dirty)
    assert_true(dirty.contains("exported"), "and still says it was exported")

    var tree := SaBuildInfo.describe({"version": "0.1.0", "commit": "abcdef0", "source": SaBuildInfo.SOURCE_WORKING_TREE})
    assert_eq(tree, "v0.1.0  ·  abcdef0  ·  development build", "An editor run is not a build")

    var unknown := SaBuildInfo.describe({"version": "0.1.0", "source": SaBuildInfo.SOURCE_UNKNOWN})
    assert_eq(unknown, "v0.1.0  ·  commit unknown", "and no commit is said to be no commit")


## What `sara --version` prints, which a script splits on spaces: the version
## and the commit the Build line shows, and "dirty" only for an export of a tree
## with edits in it.
func test_the_version_line_names_the_version_and_the_commit() -> void:
    var exported := SaBuildInfo.version_line(
        {"version": "0.17.3", "commit": "5cd5c8c", "source": SaBuildInfo.SOURCE_EXPORT, "built": "2026-09-02T01:12:40Z"}
    )
    assert_eq(exported, "Sara 0.17.3 (5cd5c8c)", "A clean export")

    var dirty := SaBuildInfo.version_line(
        {"version": "0.17.3", "commit": "5cd5c8c", "source": SaBuildInfo.SOURCE_EXPORT, "dirty": true}
    )
    assert_eq(dirty, "Sara 0.17.3 (5cd5c8c dirty)", "A dirty export says so before the bracket closes")

    var tree := SaBuildInfo.version_line({"version": "0.17.3", "commit": "5cd5c8c", "source": SaBuildInfo.SOURCE_WORKING_TREE})
    assert_eq(tree, "Sara 0.17.3 (5cd5c8c)", "An editor run names the checkout's commit")

    var unknown := SaBuildInfo.version_line({"version": "0.17.3", "source": SaBuildInfo.SOURCE_UNKNOWN})
    assert_eq(unknown, "Sara 0.17.3 (unknown)", "and no commit is said to be none")


func test_the_version_line_is_one_line_with_the_headers_version_and_commit() -> void:
    var info := SaBuildInfo.read(SaDataRoot.path("does_not_exist.json"))
    var printed := SaBuildInfo.version_line(info)
    assert_false(printed.contains("\n"), "One line")
    assert_true(printed.begins_with("Sara %s (" % info["version"]), "the project's version: %s" % printed)
    assert_true(SaBuildInfo.describe(info).contains(str(info["commit"])), "and the commit the Build line shows")


## A half-written or hand-edited stamp must not take the header down with it.
func test_a_stamp_that_is_not_a_json_object_is_ignored() -> void:
    _write_stamp("[1, 2, 3")
    var info := SaBuildInfo.read(scratch_stamp)
    assert_true(info["source"] != SaBuildInfo.SOURCE_EXPORT, "Garbage is not an export")
    assert_eq(info["version"], SaBuildInfo.version(), "and the version still comes from the project")
