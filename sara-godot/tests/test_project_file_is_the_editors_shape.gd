## The project file stays the shape the editor writes.
##
## Godot rewrites `project.godot` whenever the editor saves its settings, in
## its own order and without any comment below the engine's header. A section
## put somewhere else by hand, or a comment explaining a setting, comes back
## as a diff the first time anyone opens the project in the editor, which a
## newcomer does before anything else. The reason a setting is
## what it is lives beside the code that depends on it, the pacer in that
## case, and this suite fails the next hand edit before the editor undoes it.
extends "res://tests/test_framework.gd"

const PROJECT_FILE: String = "res://project.godot"


func _lines() -> PackedStringArray:
    var text := FileAccess.get_file_as_string(PROJECT_FILE)
    assert_false(text.is_empty(), "project.godot reads")
    return text.split("\n")


func _sections() -> PackedStringArray:
    var names := PackedStringArray()
    for line in _lines():
        if line.begins_with("[") and line.ends_with("]"):
            names.append(line.substr(1, line.length() - 2))
    return names


## The engine's own header is `;` lines above the first section and stays.
## Anything else starting with `;` is a comment Godot will drop.
func test_no_comment_sits_below_the_engines_header() -> void:
    var below_header := false
    var offenders := PackedStringArray()
    for line in _lines():
        if line.begins_with("["):
            below_header = true
        elif below_header and line.begins_with(";"):
            offenders.append(line)
    assert_true(offenders.is_empty(), "Comments the editor will drop: %s" % ", ".join(offenders))


## Godot writes the sections in ascending order, the header block first.
func test_the_sections_are_in_the_order_the_editor_writes() -> void:
    var names := _sections()
    var sorted_names := PackedStringArray(names)
    sorted_names.sort()
    assert_eq(names, sorted_names, "Sections out of the editor's order, so its next save moves them")


## A Sara left alone renders nothing. The frame pacer restores
## the project's low-processor mode between strokes, and the project never set
## it, so "restored" meant off and the window drew a hundred frames a second
## while idle.
func test_the_app_rests_in_low_processor_mode() -> void:
    assert_true(
        bool(ProjectSettings.get_setting("application/run/low_processor_mode", false)),
        "application/run/low_processor_mode is on, so a still Sara draws no frame"
    )
