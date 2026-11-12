## The filter dialog waits to be asked.
##
## `SaFilterDialogWindow.install` runs at boot and a Window is visible the
## moment it joins the tree, so the one window every filter shares opened blank
## over the top left of the canvas on every run, an untitled 660 by 640 box
## that took every press aimed under it and that `{"docker": "park"}` could
## not move because it is not a docker. Built and never added to the tree, the
## way `test_filter_dialog.gd` explains: a Window in the tree maps an OS
## window and hangs the offscreen runner.
extends "res://tests/test_framework.gd"


func test_a_freshly_built_filter_dialog_is_hidden() -> void:
    var window := SaFilterDialogWindow.new()
    assert_false(window.visible, "the shared filter window starts hidden, like SaMessage")
    assert_eq(window.name, "FilterDialog", "and keeps the name install looks for")
    window.free()


## A third window on the bootstrap is
## the Filters docker, which is built at boot with the rest and is a `Window`
## all the same, so it owes the same case rather than a raised count.
func test_a_freshly_built_filter_browser_is_hidden() -> void:
    var docker := FiltersDocker.new()
    assert_false(docker.visible, "the Filters docker starts hidden, like the dialog it opens")
    assert_eq(docker.name, String(SaDockerIds.FILTERS), "and keeps the id the layout files it under")
    docker.free()


func test_the_message_dialog_starts_hidden_too() -> void:
    var window := SaMessage.new()
    assert_false(window.visible, "SaMessage is the shape the filter window copies")
    window.free()


## A fourth window on the bootstrap is the editor a double click
## on an attached filter's row opens, and a `Window` at boot owes the same case
## as the three above for the same reason.
func test_a_freshly_built_filter_editor_is_hidden() -> void:
    var window := SaFilterEditWindow.new()
    assert_false(window.visible, "the editor starts hidden, like the dialog it edits beside")
    assert_eq(window.name, "FilterEdit", "and keeps the name install looks for")
    window.free()


## The same defect showed from the other side in `scenarios/clipboard.json`
## losing its opening stroke to the same box, and this is the case that keeps the
## three above from going stale. They name three dialogs because `Main`'s boot
## installs three. A fourth `install` line is a fourth dialog nobody is asking
## the question of, which is how a filter window goes unasked, so the count is
## read off the bootstrap rather than trusted. The browser has no `install` line,
## since the docker is built by the docker registry with every other, which leaves
## three: the dialog, the message and the editor.
func test_the_three_cases_are_what_the_bootstrap_installs() -> void:
    var source := FileAccess.get_file_as_string("res://ui/main/main.gd")
    assert_false(source.is_empty(), "main.gd is readable")
    var installs := 0
    for line in source.split("\n"):
        if line.strip_edges().ends_with(".install(self)"):
            installs += 1
    assert_eq(installs, 3, "every dialog the bootstrap installs has a case above")
