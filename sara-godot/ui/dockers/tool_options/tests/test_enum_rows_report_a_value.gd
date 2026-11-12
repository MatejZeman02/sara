## A dump says which item a Tool Options dropdown has selected, by id.
##
## `SaCaptureDumpDockers._row_value` cast every row to `FactorSlider` and gave
## up, so every enum, every blend chooser and every toggle in the docker read
## `"value": null`. Five dumps of `scenarios/transform-modes.json` taken with
## the mode set to Normal, Shear and Perspective in turn could not be told apart
## on that field, and what named the mode was the run log's write rather than any
## read.
##
## The rows are built here the way `ToolOptionsDocker._place_control` builds
## them, a label column and the control beside it in an HBox, because the docker
## itself needs a bound tool machine and a registry and this is a test about one
## reader.
extends "res://tests/test_framework.gd"

## The three ids `StateTransform.Mode` gives the transform's own enum, in the
## order the spec lists them. Numbers here on purpose: the point is
## that a dump carries these rather than 0, 1 and 2.
const NORMAL := 0
const PERSPECTIVE := 1
const SHEAR := 2


## A row as the docker builds one for anything that is not a slider.
func _row(control: Control) -> HBoxContainer:
    var box := HBoxContainer.new()
    box.name = "TransformModeRow"
    var label := Label.new()
    label.name = "Label"
    label.text = "Mode"
    box.add_child(label)
    box.add_child(control)
    return box


## An enum row's control, with the ids on the item metadata the way
## `ToolOptionControls._build_choice` puts them there.
func _modes(selected: int) -> OptionButton:
    var option := OptionButton.new()
    option.name = "TransformModeOpt"
    for choice: Array in [[NORMAL, "Normal"], [PERSPECTIVE, "Perspective"], [SHEAR, "Shear"]]:
        option.add_item(String(choice[1]))
        option.set_item_metadata(option.item_count - 1, choice[0])
    option.select(selected)
    return option


func test_each_item_of_an_enum_reads_a_different_value() -> void:
    var seen: Array = []
    for index in 3:
        var row := _row(_modes(index))
        seen.append(ToolOptionsDocker.row_value(row))
        row.free()
    assert_eq(seen, [NORMAL, PERSPECTIVE, SHEAR], "Three modes, three values, and none of them null")


func test_the_value_is_the_choice_id_and_not_the_item_index() -> void:
    var option := OptionButton.new()
    option.name = "FilterOpt"
    # Ids that are not their own indices, which is the whole difference. A dump
    # reading 2 here cannot say whether the enum has been reordered since.
    for choice: Array in [[10, "Nearest"], [20, "Bilinear"], [30, "Bicubic"]]:
        option.add_item(String(choice[1]))
        option.set_item_metadata(option.item_count - 1, choice[0])
    option.select(2)
    var row := _row(option)

    assert_eq(ToolOptionsDocker.row_value(row), 30, "The id behind the item, not its place in the list")
    row.free()


func test_a_dropdown_with_nothing_selected_is_null_rather_than_a_guess() -> void:
    var option := _modes(0)
    option.select(-1)
    var row := _row(option)

    assert_null(ToolOptionsDocker.row_value(row), "Nothing selected is nothing to report")
    row.free()


## An action row has no label column, since the button's word would be the
## label's word said again. The button's word is the row's only text, so it is
## what the dump has to carry.
func test_a_toggle_reads_its_state_and_an_action_reads_its_word() -> void:
    var toggle := Button.new()
    toggle.name = "MirrorBtn"
    toggle.toggle_mode = true
    toggle.button_pressed = true
    var toggle_row := _row(toggle)
    assert_eq(ToolOptionsDocker.row_value(toggle_row), true, "A toggle row says whether it is down")
    toggle_row.free()

    var action := Button.new()
    action.name = "CropAction"
    action.text = "Crop"
    var action_row := _row(action)
    assert_eq(ToolOptionsDocker.row_value(action_row), "Crop", "An action row holds no value and says the word on its button")
    action_row.free()


func test_a_slider_still_reads_its_number_and_is_still_its_own_row() -> void:
    var slider := FactorSlider.new()
    slider.name = "RadiusSlider"
    slider.min_value = 0.0
    slider.max_value = 100.0
    slider.value = 42.0

    assert_almost_eq(float(ToolOptionsDocker.row_value(slider)), 42.0, 0.001, "A slider is the row and reads as it always did")
    slider.free()


func test_the_label_column_is_never_mistaken_for_the_control() -> void:
    ## A Label sits before the control in every non-slider row, so a reader that
    ## took the first child would answer about the label and never about the
    ## dropdown.
    var row := _row(_modes(SHEAR))
    assert_eq(row.get_child(0).name, StringName("Label"), "The label really is first")
    assert_eq(ToolOptionsDocker.row_value(row), SHEAR, "and the value comes from the control behind it")
    row.free()


func test_a_row_with_no_control_at_all_is_null() -> void:
    var box := HBoxContainer.new()
    box.name = "EmptyRow"
    var label := Label.new()
    label.name = "Label"
    box.add_child(label)

    assert_null(ToolOptionsDocker.row_value(box), "A row holding nothing to read is null, not an error")
    box.free()


func test_a_curve_option_row_reads_the_summary_its_button_carries() -> void:
    ## The option's state is written onto the button, and the dump reads it, so
    ## the nine curve option rows of the brush's page do not read null. The name is what tells the two plain buttons apart, and
    ## `ToolOptionControls._node_name` is what guarantees the suffix.
    var button := Button.new()
    button.name = "SizeCurve"
    button.text = "60%, Pressure"
    var row := _row(button)

    assert_eq(ToolOptionsDocker.row_value(row), "60%, Pressure", "The button's summary is what the row is set to")
    row.free()
