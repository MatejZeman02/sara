## The News pane of the welcome window: which sections it shows
## for the version a painter last saw, and where it reads them from.
##
## The pane is built and never added to a tree, for the reason
## `test_welcome_window.gd` gives: a `Window` in a suite hangs the whole run.
## Its `_init` reaches the changelog and draws, which is what makes a detached
## one worth building here.
##
## The file it reads is the checkout's own `CHANGELOG.md` in this run, because
## an editor run has no packed copy under `res://`. The one test that
## depends on which tree it is in asserts whichever answer it gets rather than
## skipping, the way `test_sa_changelog.gd` does.
extends "res://tests/test_framework.gd"

## Four versions with their sections, newest first, which is the shape
## `SaChangelog` hands back. Deliberately written out of order, because the
## reader sorts by the version's numbers and a pane that trusted the file's
## order would draw them wrong.
const FIXTURE: String = """# Changelog

## 0.10.1

A line for ten one.

## 0.11.1

The newest line.

## 0.10.0

A line for ten.

## 0.11.0

A line for eleven.
"""

## The running version the fixture's own pane is read as: the version Sara is
## on is not this suite's to name, so the report is asked for a version the
## fixture carries.
const RUNNING: String = "0.11.1"


## The three settings values the pane answers for: an empty one, which is a
## profile that has never seen a news pane, an older one, and the running one.
func test_the_report_for_the_three_settings_values() -> void:
    var all := SaChangelog.parse(FIXTURE)

    var first := WelcomeNewsPane.report_for(all, RUNNING, "")
    assert_eq(first["sections"], ["0.11.1", "0.11.0", "0.10.1", "0.10.0"], "an empty setting shows every section, newest first")
    assert_false(first["already_installed"], "and nothing is standing in for a newer version")

    var older := WelcomeNewsPane.report_for(all, RUNNING, "0.10.0")
    assert_eq(older["sections"], ["0.11.1", "0.11.0", "0.10.1"], "an older setting shows the three since it, and not itself")
    assert_false(older["already_installed"], "the running version's notes are news to this painter")

    var seen := WelcomeNewsPane.report_for(all, RUNNING, RUNNING)
    assert_eq(seen["sections"], ["0.11.1"], "a setting on the running version shows that version's own section")
    assert_true(seen["already_installed"], "with the line saying it is what is already installed")


## A version the file does not carry and a file with nothing in it are the same
## empty answer, which is the one a build with no changelog draws its sentence
## for. It is not an error, and the pane says so rather than raising.
func test_nothing_to_show_is_an_empty_list_and_not_a_fault() -> void:
    var all := SaChangelog.parse(FIXTURE)
    var unknown := WelcomeNewsPane.report_for(all, "9.9.9", "9.9.9")
    assert_eq(unknown["sections"], [], "a version the file does not carry shows nothing")
    assert_false(unknown["already_installed"], "and nothing stands in for it")
    assert_eq(WelcomeNewsPane.report_for([], RUNNING, "")["sections"], [], "and neither does a file with no sections")


## "The empty setting shows every section the reader has" for the real file,
## whichever tree this run is in.
func test_an_empty_setting_shows_every_section_this_tree_carries() -> void:
    var found := SaChangelog.read()
    var all: Array = found["sections"]
    assert_true(found.has("source"), "the reader names where the sections came from")
    assert_eq(
        (WelcomeNewsPane.report_for(all, RUNNING, "")["sections"] as Array).size(),
        all.size(),
        "an empty setting is every section the reader found, %d of them from %s" % [all.size(), found["source"]]
    )
    if found["source"] == "none":
        assert_eq(all, [], "nothing to read and no complaint")
        return
    assert_true(all.size() > 0, "a changelog was found, so it carries sections")


## The packed copy is the build's and wins whenever it is there, and the
## checkout's is what an editor run reads instead. Which of the two a run is
## decides the answer, so the test asserts the pair rather than one of them.
func test_the_packed_file_is_read_first_and_the_checkout_is_the_editor_answer() -> void:
    var found := SaChangelog.read()
    if FileAccess.file_exists(SaChangelog.PATH):
        assert_eq(found["source"], "build", "a packed changelog is the source a build reads")
        return
    assert_eq(found["source"], "checkout", "an editor run reads the checkout's own CHANGELOG.md")
    var checkout := str(found["path"])
    assert_true(checkout.ends_with("CHANGELOG.md"), "which is the repository's file, named at %s" % checkout)
    assert_true(FileAccess.file_exists(checkout), "and it is a real file in a clone")


## The setting the pane writes and the boot of the window read: one string under
## `ui`, empty for a profile that has never seen one.
func test_the_version_last_seen_is_stored_under_the_ui_section() -> void:
    assert_true(SaSettingsKeys.KEYS.has("last_version_seen"), "the version has a section and a key")
    assert_eq(SaSettingsKeys.KEYS["last_version_seen"], ["ui", "last_version_seen"], "under ui, spelled as the row asks for it")
    var fresh := SaSettingsValues.new()
    assert_eq(fresh.last_version_seen, "", "and a profile with no key yet gets the empty string")
    fresh.free()


## The pane a running app builds is a reader of that file and a report of what
## it read: the source its line names is the source the reader answered with,
## and the version it is on is the running one.
func test_the_pane_reports_what_the_reader_answered() -> void:
    var pane := WelcomeNewsPane.new()
    var shown := pane.report()
    var found := SaChangelog.read()
    assert_eq(shown["source"], found["source"], "the report names the file the reader read")
    assert_eq(shown["running"], SaBuildInfo.version(), "and the version this build is")
    assert_eq(shown["last_seen"], SaSettings.last_version_seen, "and what the settings say was last seen")
    assert_eq((shown["sections"] as Array).size(), (found["sections"] as Array).size(), "the sections on screen are the reader's")
    pane.free()
