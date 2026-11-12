## What the word History means in Sara, and that it means one thing.
##
## It once meant three at once: the docker a painter can open listed the
## brush presets last loaded, while the Info docker's History section and the
## `history` block of every state dump were the undo stack. The one surface
## reachable from a menu was the only one that was not the stack, which is how a
## reviewer files a bug against the wrong docker.
##
## The answer is the rename rather than a new docker. Every case here asks a surface for its own words rather
## than asking the source for a string. What the Dockers menu draws is a
## registration only main builds, so that half is in
## `scenarios/history-docker-is-not-the-history.json` instead.
extends "res://tests/test_framework.gd"

## The docker is a Window and its `_init` builds real controls.
const REQUIRES_GPU := true


## The trail of presets says what it holds, in the title and in the bar a painter
## drags it by. Two separate strings, and both were the wrong word.
func test_the_preset_trail_is_called_recent_presets() -> void:
    var docker := HistoryDocker.new()
    assert_eq(String(docker.title), "Recent Presets", "The window says what it lists")

    var said: Array[String] = []
    for node in docker.find_children("*", "Label", true, false):
        var label := node as Label
        if label != null and not label.text.is_empty():
            said.append(label.text)
    # The drag bar draws a grip before the words and the label holds the title
    # alone.
    var handle := ""
    for text in said:
        if text.contains("Recent Presets") or text.contains("History"):
            handle = text
    assert_true(handle.ends_with("Recent Presets"), "and so does the bar a painter drags it by: %s" % [said])
    assert_false(handle.contains("History"), "with the word gone from it")
    docker.free()


## The Info docker's History section is the undo stack and keeps the word, which
## is the point of the rename rather than a second casualty of it: after the rename
## every surface still called History is the stack, so the name means one thing.
func test_the_info_dockers_history_section_is_the_undo_stack() -> void:
    var rows: Array = []
    for section: Array in InfoDocker.SECTIONS:
        if String(section[0]) == "History":
            rows = section[1]
    assert_eq(
        rows,
        ["Steps", "Paint", "Layer pool", "Widest step", "Dropped"],
        "The one History left on screen reads the undo stack's own numbers"
    )


## The shortcut a painter presses to open it says the same word as the docker.
## It is a third string, in a third file, and it is the one a reader of the
## Shortcuts page sees.
func test_the_shortcut_is_named_after_the_docker() -> void:
    var found := ""
    for entry: Array in SaAppCommands.DOCKER_COMMANDS:
        if String(entry[1]) == "HistoryDocker":
            found = String(entry[2])
    assert_eq(found, "Recent Presets docker", "The command opens what its name says")
