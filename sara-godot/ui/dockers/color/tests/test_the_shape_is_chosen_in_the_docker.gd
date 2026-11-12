## The picker's shape is chosen from the docker by a right press, and the OKHSV
## row says whose H, S and V it shows.
##
## Preferences was the only way to switch the shape and three bare letters sat
## over the OKHSV sliders. A right press on the shape
## now lists the seven shapes and a pick writes the one setting the Preferences
## row reads, and a muted caption sits over the OKHSV row.
## `scenarios/the-picker-s-shape-is-chosen-in-the-docker.json` is the half
## that has to be photographed.
extends "res://tests/test_framework.gd"

const SaColorPickerScript = preload("res://ui/dockers/color/sa_color_picker.gd")
const SaPickerShapeScript = preload("res://ui/widgets/picker/sa_picker_shape.gd")

var _saved_shape: String = ""


func before_each() -> void:
    _saved_shape = SaSettings.color_picker_shape


func after_each() -> void:
    SaSettings.color_picker_shape = _saved_shape


## A picker whose `_ready` has run, so the Preferences row is registered. Out
## of the tree, because a popup that opens in a suite's tree blocks the run, and
## the list is filled before the picker asks whether it can open. The holder is
## the caller's to free.
func _picker_in(holder: Control) -> SaColorPicker:
    var picker: SaColorPicker = SaColorPickerScript.new()
    holder.add_child(picker)
    picker._ready()
    return picker


func _right_press() -> InputEventMouseButton:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_RIGHT
    press.pressed = true
    press.position = Vector2(10, 10)
    return press


func test_a_right_press_on_the_shape_lists_the_seven_shapes_with_the_current_marked() -> void:
    SaSettings.color_picker_shape = "okhsl"
    var holder := Control.new()
    var picker := _picker_in(holder)
    assert_eq(picker.shape_menu.row_ids().size(), 0, "The list is empty until it is asked for")

    picker.shape.frame.gui_input.emit(_right_press())

    var labels: Array[String] = []
    for label: String in SaPickerShapeScript.KIND_LABELS:
        labels.append(label)
    assert_eq(picker.shape_menu.row_labels(), labels, "A right press lists the seven shapes by their labels")
    assert_eq(picker.shape_menu.current, &"okhsl", "and marks the one the picker is")
    holder.free()


func test_the_bar_beside_the_disc_opens_the_list_as_well() -> void:
    SaSettings.color_picker_shape = "okhsl"
    var holder := Control.new()
    var picker := _picker_in(holder)
    picker.shape.hue_bar.gui_input.emit(_right_press())
    picker.shape.lightness_bar.gui_input.emit(_right_press())
    assert_eq(picker.shape_menu.row_ids().size(), SaPickerShapeScript.KIND_KEYS.size(), "Every part of the shape answers it")
    holder.free()


func test_a_left_press_is_the_shapes_own_and_opens_nothing() -> void:
    var holder := Control.new()
    var picker := _picker_in(holder)
    var press := _right_press()
    press.button_index = MOUSE_BUTTON_LEFT
    picker.shape.frame.gui_input.emit(press)
    assert_eq(picker.shape_menu.row_ids().size(), 0, "A left press leaves the list alone")
    holder.free()


func test_choosing_hsv_triangle_moves_the_picker_and_the_preferences_row() -> void:
    SaSettings.color_picker_shape = "wheel"
    var holder := Control.new()
    var picker := _picker_in(holder)
    picker.shape.frame.gui_input.emit(_right_press())

    assert_true(picker.shape_menu.press_row(&"hsv_triangle"), "The HSV triangle row takes a press")

    assert_eq(SaSettings.color_picker_shape, "hsv_triangle", "The pick writes the one setting")
    assert_eq(picker.shape.kind_key(), "hsv_triangle", "and the picker is drawn as it")
    assert_eq(SaSettings.get_docker_option("ColorPicker", "shape"), "hsv_triangle", "and the Preferences row reads the same")
    holder.free()


func test_the_wheel_says_how_to_change_it() -> void:
    var picker: SaColorPicker = SaColorPickerScript.new()
    assert_eq(picker.shape.frame.tooltip_text, "Right-click to change the shape.", "The wheel's hover names the gesture")
    picker.free()


func test_the_okhsv_row_carries_its_caption_and_the_rgb_row_none() -> void:
    var okhsv := SaPickerSliders.make(SaPickerSliders.Model.OKHSV)
    var rgb := SaPickerSliders.make(SaPickerSliders.Model.RGB)
    assert_true(okhsv.caption != null, "The OKHSV row has a caption")
    assert_eq(okhsv.caption.text, "OKHSV, hue, saturation and value as Oklab sees them", "which says whose letters these are")
    assert_eq(okhsv.caption.get_parent(), okhsv, "a child of the row, so it shows and hides with it")
    assert_eq(okhsv.get_child(0), okhsv.caption, "above the sliders")
    assert_eq(okhsv.caption.autowrap_mode, TextServer.AUTOWRAP_OFF, "one line")
    assert_true(okhsv.caption.clip_text, "clipped rather than widening the column")
    assert_eq(okhsv.caption.tooltip_text, okhsv.caption.text, "and the hover holds the whole sentence")
    assert_true(rgb.caption == null, "The RGB row has none")
    assert_eq(okhsv.sliders.size(), 3, "and the three sliders are still the row's")
    okhsv.free()
    rgb.free()
