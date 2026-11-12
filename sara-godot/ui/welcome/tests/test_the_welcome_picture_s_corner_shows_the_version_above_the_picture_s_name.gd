## The welcome picture's corner shows the version above the
## picture's name, the shorter line first.
##
## The window is built and never added to a tree, for the reason
## `test_welcome_window.gd` gives, so the order of the corner's lines is what is
## read here. How the corner looks is the shot of
## `scenarios/the-welcome-window-opens-on-a-painted-picture.json`.
extends "res://tests/test_framework.gd"


func test_the_version_line_stands_before_the_credit_line() -> void:
    var window := SaWelcomeWindow.new()
    var words := window.band.get_node("Words") as VBoxContainer
    assert_not_null(words, "the corner's words stand in a column named Words")
    var version := words.get_node("VersionLine") as Control
    var credit := words.get_node("CreditLine") as Control
    assert_eq(version, window.band.version_line, "the column holds the version line")
    assert_eq(credit, window.band.credit_line, "and the credit line")
    assert_true(version.get_index() < credit.get_index(), "the version comes first, the name under it")
    window.free()


func test_both_lines_stay_right_aligned() -> void:
    var window := SaWelcomeWindow.new()
    assert_eq(window.band.version_line.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT, "the version keeps to the right")
    assert_eq(window.band.credit_line.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT, "and so does the name")
    window.free()
