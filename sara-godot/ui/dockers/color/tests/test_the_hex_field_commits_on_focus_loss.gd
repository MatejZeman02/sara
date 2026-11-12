extends "res://tests/test_framework.gd"

## A hex code typed and left by a click elsewhere applies the way Enter
## does. Before it the field went back to the old colour and the foreground
## never moved. The suite emits `focus_exited` on the field, which is what a
## click on the canvas or a swatch does to it.

const SaColorPickerScript = preload("res://ui/dockers/color/sa_color_picker.gd")


func _picker() -> SaColorPicker:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    picker.color = Color8(51, 153, 230)
    return picker


func _free(picker: SaColorPicker) -> void:
    picker.get_parent().free()


func _commits(picker: SaColorPicker) -> Array:
    var out: Array = []
    picker.color_committed.connect(func(c: Color) -> void: out.append(c))
    return out


func test_a_code_left_by_a_click_away_is_picked() -> void:
    var picker := _picker()
    var changed: Array = []
    picker.color_changed.connect(func(c: Color) -> void: changed.append(c))
    var commits := _commits(picker)
    picker.hex_input.text = "#e8431c"
    picker.hex_input.focus_exited.emit()
    var want := Color.html("#e8431c")
    assert_true(picker.color.is_equal_approx(want), "The foreground takes the typed code")
    assert_true(picker.foreground_swatch.color.is_equal_approx(want), "and its swatch shows it")
    assert_true(picker.rgb_sliders._color.is_equal_approx(want), "and the sliders show it")
    assert_eq(picker.hex_input.text, "#e8431c", "The field keeps the code")
    assert_eq(changed.size(), 1, "The docker hears one change, which reaches the brush")
    assert_eq(commits.size(), 1, "and the recent row hears it once")
    _free(picker)


func test_enter_then_the_focus_it_releases_picks_once() -> void:
    var picker := _picker()
    var commits := _commits(picker)
    picker.hex_input.text = "e8431c"
    picker.hex_input.text_submitted.emit(picker.hex_input.text)
    picker.hex_input.focus_exited.emit()
    assert_eq(commits.size(), 1, "Enter and the focus it lets go of are one pick")
    _free(picker)


func test_a_bad_code_left_by_a_click_away_puts_the_colour_back() -> void:
    var picker := _picker()
    var commits := _commits(picker)
    picker.hex_input.text = "#zz12"
    picker.hex_input.focus_exited.emit()
    assert_eq(picker.hex_input.text, "#3399e6", "The field shows the picker's colour again")
    assert_true(picker.color.is_equal_approx(Color8(51, 153, 230)), "and the foreground did not move")
    assert_true(commits.is_empty(), "and nothing was committed")
    _free(picker)


func test_a_click_in_and_out_with_no_edit_changes_nothing() -> void:
    var picker := _picker()
    var changed: Array = []
    picker.color_changed.connect(func(c: Color) -> void: changed.append(c))
    var commits := _commits(picker)
    picker.hex_input.focus_exited.emit()
    assert_true(changed.is_empty() and commits.is_empty(), "No edit means no pick and no recent chip")
    _free(picker)


func test_escape_still_cancels() -> void:
    var picker := _picker()
    var commits := _commits(picker)
    picker.hex_input.text = "#e8431c"
    var esc := InputEventKey.new()
    esc.keycode = KEY_ESCAPE
    esc.pressed = true
    picker.hex_input.gui_input.emit(esc)
    picker.hex_input.focus_exited.emit()
    assert_eq(picker.hex_input.text, "#3399e6", "Escape puts the shown colour back")
    assert_true(picker.color.is_equal_approx(Color8(51, 153, 230)), "and the focus it lets go of picks nothing")
    assert_true(commits.is_empty(), "and nothing was committed")
    _free(picker)


func test_the_tooltip_says_a_click_elsewhere_applies_it() -> void:
    var picker := _picker()
    assert_true(picker.hex_input.tooltip_text.contains("click elsewhere"), "The tooltip names the click away")
    _free(picker)


## The canvas takes no focus, so a click on it moved none and the field's
## `focus_exited` never came in the running app. The root window's
## `window_input` is where the picker hears that press. A picker parented to
## an autoload is in the tree, because the runner rejects `add_child` on a
## parent in its own `_ready`.
func test_a_press_the_root_hears_outside_the_field_applies_the_code() -> void:
    var picker := SaColorPickerScript.new()
    EventBus.add_child(picker)
    picker.color = Color8(51, 153, 230)
    picker.hex_row.visible = true
    picker.hex_input.size = Vector2(120, 30)
    picker.hex_input.grab_focus()
    assert_true(picker.hex_input.has_focus(), "The field holds the keyboard")
    var commits := _commits(picker)
    picker.hex_input.text = "#e8431c"

    var inside := InputEventMouseButton.new()
    inside.button_index = MOUSE_BUTTON_LEFT
    inside.pressed = true
    inside.position = picker.hex_input.get_screen_transform() * Vector2(60, 15)
    picker.get_tree().root.window_input.emit(inside)
    assert_true(picker.hex_input.has_focus(), "A press on the field itself leaves it the keyboard")
    assert_true(commits.is_empty(), "and applies nothing yet")

    var away: InputEventMouseButton = inside.duplicate()
    away.position = inside.position + Vector2(0, 400)
    picker.get_tree().root.window_input.emit(away)
    assert_false(picker.hex_input.has_focus(), "A press elsewhere takes the keyboard from the field")
    assert_true(picker.color.is_equal_approx(Color.html("#e8431c")), "and the code it held is the foreground")
    assert_eq(commits.size(), 1, "picked once")
    picker.free()
