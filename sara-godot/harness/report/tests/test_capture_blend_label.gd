## The Layers docker's blend row is read off the dropdown, not off a label that
## has not been there since the word was dropped.
##
## The state report filled `layers_docker.blend_label` by walking `BlendBox` for a
## `Label`. The word "Blend:" was taken out in front of the dropdown, so the
## field was the empty string in every dump after it, including the two either
## side of a Multiply, and every capture claim about that row was graded against "".
##
## The dropdown is asked by method rather than by cast, which is the rule the
## dockers file's own `_color_theme_state` gives: a cast to a `class_name` in a
## static function leaks the script.
##
extends "res://tests/test_framework.gd"

const StateReport = preload("res://harness/report/sa_state_report.gd")


## A box holding a `BlendModeButton`, which is what the docker builds today.
func _box_with_dropdown(label_text: String) -> Node:
    var host := Control.new()
    var box := HBoxContainer.new()
    box.name = "BlendBox"
    host.add_child(box)
    var button := BlendModeButton.new()
    button.name = "BlendModeOpt"
    button.text = label_text
    box.add_child(button)
    return host


func test_the_row_reads_the_dropdowns_own_label() -> void:
    var host := _box_with_dropdown("Multiply")
    assert_eq(StateReport._blend_label_text(host), "Multiply", "A Multiply reads Multiply")
    host.free()

    var normal := _box_with_dropdown("Normal (Oklab)")
    assert_eq(
        StateReport._blend_label_text(normal),
        "Normal (Oklab)",
        "and Normal reads what the row says, brackets and all: the space is part of the label the registry builds"
    )
    normal.free()


## The old shape still answers, because a box that does carry a label is a box
## whose label is the row.
func test_a_label_in_the_box_is_still_read() -> void:
    var host := Control.new()
    var box := HBoxContainer.new()
    box.name = "BlendBox"
    host.add_child(box)
    var label := Label.new()
    label.text = "Blend:"
    box.add_child(label)
    assert_eq(StateReport._blend_label_text(host), "Blend:", "A row with a label reads it")
    host.free()


## An empty string means the row is not there, and has to keep meaning that:
## the whole cost of this bug was two boards reading "no row" as "row says
## nothing".
func test_no_blend_box_is_an_empty_string() -> void:
    var host := Control.new()
    assert_eq(StateReport._blend_label_text(host), "", "No BlendBox is empty")
    var box := HBoxContainer.new()
    box.name = "BlendBox"
    host.add_child(box)
    assert_eq(StateReport._blend_label_text(host), "", "and so is one holding neither a dropdown nor a label")
    host.free()
