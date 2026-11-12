## The changelog reader: the file's shape, and what a build with no copy
## anywhere answers.
##
## The fixture below is the real file's twelve versions written deliberately out
## of order, because the reader sorts by the version's numbers rather than
## trusting the order a hand-edited file happens to hold. The real file is read
## as well, in the tests below whose answer depends on whether this checkout is
## an editor run (the checkout's own `CHANGELOG.md`) or the packed
## build (the file under `res://`).
extends "res://tests/test_framework.gd"

## Every version `CHANGELOG.md` carries, newest first.
const VERSIONS: Array[String] = [
    "0.11.1",
    "0.11.0",
    "0.10.1",
    "0.10.0",
    "0.9.1",
    "0.9.0",
    "0.8.3",
    "0.8.2",
    "0.8.1",
    "0.8.0",
    "0.7.0",
    "0.6.0",
]

## Twelve sections, shuffled, with one blank line inside a section, one section
## carrying two lines and a level-one title that is not a section.
const FIXTURE: String = """# Changelog

## 0.8.1

A patch line.

## 0.11.1

The newest line.
And a second line for the same version.

## 0.6.0

The oldest line.

## 0.10.0

A line for ten.

## 0.9.1

A line for nine one.

## 0.8.0
A line with no blank line after the heading.

## 0.11.0

A line for eleven.

## 0.7.0

A line for seven.

## 0.10.1

A line for ten one.

## 0.8.2

A line for eight two.

## 0.8.3

A line for eight three.

## 0.9.0

A line for nine.
"""


func test_the_fixture_parses_twelve_sections_newest_first() -> void:
    var parsed := SaChangelog.parse(FIXTURE)
    assert_eq(parsed.size(), VERSIONS.size(), "Twelve sections, as the file has")
    var order: Array[String] = []
    for section: Dictionary in parsed:
        order.append(str(section["version"]))
    assert_eq(order, VERSIONS, "Newest first, whatever order the file writes them in")


func test_a_section_carries_its_lines_and_the_title_is_not_one() -> void:
    var parsed := SaChangelog.parse(FIXTURE)
    var by_version := {}
    for section: Dictionary in parsed:
        by_version[str(section["version"])] = section["lines"]
    assert_eq((by_version["0.11.1"] as PackedStringArray).size(), 2, "Two lines, both kept")
    assert_eq(str(by_version["0.11.1"][1]), "And a second line for the same version.", "in order")
    assert_eq((by_version["0.6.0"] as PackedStringArray).size(), 1, "One line")
    assert_false(by_version.has("Changelog"), "The level-one title is not a section")


func test_since_returns_only_the_sections_newer_than_the_one_named() -> void:
    var parsed := SaChangelog.parse(FIXTURE)
    var recent := SaChangelog.newer_than(parsed, "0.10.0")
    assert_eq(recent.size(), 3, "0.11.1, 0.11.0 and 0.10.1")
    var order: Array[String] = []
    for section: Dictionary in recent:
        order.append(str(section["version"]))
    assert_eq(order, ["0.11.1", "0.11.0", "0.10.1"], "newest first, and 0.10.0 itself left out")
    assert_eq(SaChangelog.newer_than(parsed, "0.11.1").size(), 0, "Nothing is newer than the newest")
    assert_eq(SaChangelog.newer_than(parsed, "").size(), VERSIONS.size(), "An empty ask is everything")


func test_a_version_is_compared_by_its_numbers_not_as_a_string() -> void:
    assert_true(SaChangelog.compare_versions("0.10.1", "0.9.1") > 0, "0.10.1 is above 0.9.1")
    assert_true(SaChangelog.compare_versions("0.9.1", "0.10.1") < 0, "and the other way round")
    assert_eq(SaChangelog.compare_versions("0.11.1", "0.11.1"), 0, "the same version is the same")
    var parsed := SaChangelog.parse(FIXTURE)
    var order: Array[String] = []
    for section: Dictionary in parsed:
        order.append(str(section["version"]))
    assert_true(
        order.find("0.10.1") < order.find("0.9.1"), "and the sorted list puts 0.10.1 first, where a string sort would not"
    )


func test_a_build_without_a_changelog_answers_empty_and_quiet() -> void:
    assert_eq(SaChangelog.sections("res://no_such_changelog.md"), [], "No file, no sections")
    assert_eq(SaChangelog.since("", "res://no_such_changelog.md"), [], "and no sections to filter")


## An editor run has no copy under `res://`, because the file is copied in for
## the length of an export and removed again, but now it reads the
## checkout's own copy instead of answering nothing. Both answers are correct,
## so the test asserts whichever tree it is in rather than skipping the file's
## own shape.
func test_the_changelog_in_this_tree_is_read_when_it_is_there() -> void:
    var found := SaChangelog.read()
    var parsed: Array = found["sections"]
    if found["source"] == "none":
        assert_eq(parsed, [], "No changelog beside this tree, and no complaint either")
        return
    assert_true(
        parsed.size() >= VERSIONS.size(),
        "At least the fixture's twelve versions, found %d from %s" % [parsed.size(), found["source"]]
    )
    assert_eq(str(parsed[parsed.size() - 1]["version"]), "0.6.0", "and the oldest is still last")


## The ask: `since()` with no path must not check only the packed file, or an
## editor run answers nothing at all. It falls back to the checkout the
## same way `read()` does.
func test_since_with_no_path_falls_back_to_the_checkout_in_an_editor_run() -> void:
    var found := SaChangelog.read()
    if found["source"] != "checkout":
        return
    assert_true(found["sections"].size() >= VERSIONS.size(), "the checkout copy carries at least the fixture's twelve versions")
    assert_eq(
        SaChangelog.since("").size(), found["sections"].size(), "since with no path reads through the same file read() does"
    )
