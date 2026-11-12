## The Graph docker offers Reference and Both only while a reference is selected.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The options to select the Reference are dimmed (not clickable) when no
## reference is selected. Dimmed and
## not clickable are one state in Sara's choice list, a disabled row, so these
## read both halves: the row says it is disabled and a press on it chooses
## nothing.
##
## Both dockers are built and never added to the tree, because a `Window` in the
## tree hangs a headless run, which is `test_reference_compare_and_graphs.gd`'s
## reason too. So the Graph docker is handed the Reference docker's selection
## through `follow_reference`, the call its own `_process` makes with what it
## finds in the tree, and
## `scenarios/the-graph-docker-offers-the-reference-when-there-is-none.json`
## is the poll on the running app.
extends "res://tests/test_framework.gd"

const REFERENCE_IMAGE := "res://ui/icon.png"

const DIMMED: Array[StringName] = [&"reference", &"both"]


func test_with_no_reference_the_two_rows_are_dimmed_and_say_why() -> void:
    var graph := GraphDocker.new()
    var list := graph._source_button.popup
    assert_false(graph._offers_reference, "A docker built with no reference offers none")
    assert_false(list.is_disabled(&"canvas"), "The canvas is always offered")
    for id in DIMMED:
        assert_true(list.is_disabled(id), "%s is dimmed" % id)
        assert_false(list.press_row(id), "and a press on %s chooses nothing" % id)
        assert_eq(graph.source, "canvas", "so the graph stays on the canvas")
        assert_true(
            list.label_button(id).tooltip_text.contains("Reference docker"), "and hovering %s says what would offer it" % id
        )
    assert_false(bool(graph.view_report()["offers_reference"]), "which the dump says")
    graph.free()


func test_the_rows_follow_the_selection_as_it_changes() -> void:
    var board_docker := ReferenceDocker.new()
    board_docker.board_view.size = Vector2(200, 200)
    var graph := GraphDocker.new()
    var list := graph._source_button.popup

    graph.follow_reference(board_docker.board_view.selected())
    assert_true(list.is_disabled(&"reference"), "An empty board offers nothing")

    board_docker.open_paths(PackedStringArray([REFERENCE_IMAGE]))
    assert_not_null(board_docker.board_view.selected(), "A picture opened is the selected one")
    graph.follow_reference(board_docker.board_view.selected())
    assert_true(graph._offers_reference, "so the Graph docker offers the reference")
    for id in DIMMED:
        assert_false(list.is_disabled(id), "%s comes live" % id)
        assert_false(list.label_button(id).tooltip_text.contains("Reference docker"), "and %s stops asking for one" % id)
    assert_true(list.press_row(&"both"), "A press on Both takes")
    assert_eq(graph.source, "both", "and moves the graph to both")

    board_docker.clear()
    assert_null(board_docker.board_view.selected(), "A cleared board has nothing selected")
    graph.follow_reference(board_docker.board_view.selected())
    for id in DIMMED:
        assert_true(list.is_disabled(id), "%s is dimmed again" % id)
    assert_eq(graph.source, "both", "and the painter is left on the source they chose rather than moved")
    assert_eq(graph._source_button.selected_value(), "both", "which the button still names")

    board_docker.free()
    graph.free()
