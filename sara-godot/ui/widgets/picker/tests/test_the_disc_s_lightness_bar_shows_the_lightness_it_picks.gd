## The OK-HSL lightness slider shows the lightness and is not a simple slider.
##
## The OK-HSL disc's third axis is a bar drawn the way the HSL square's hue bar
## is: black at the foot to white at the head through every lightness of the
## colour's own hue and saturation, with a cursor line at the colour's
## lightness. GDScript cannot call into a shader, so what the bar shows is read
## through `lightness_bar_colour`, its twin, and the shader's source is read
## for the mode and the uniform the twin stands for. The shot shows the pixels.
extends "res://tests/test_framework.gd"

const SaColorPickerScript = preload("res://ui/dockers/color/sa_color_picker.gd")
const OkhslConversionsScript = preload("res://utils/okhsl_conversions.gd")

const OKHSV_SHADER := "res://shaders/ui/okhsv_picker.gdshader"

var _shape_setting: String = ""
var _committed: Array[Color] = []


func before_each() -> void:
    _shape_setting = SaSettings.color_picker_shape
    _committed.clear()


func after_each() -> void:
    SaSettings.color_picker_shape = _shape_setting


func _disc(holder: Control) -> SaColorPicker:
    SaSettings.color_picker_shape = "okhsl"
    var picker: SaColorPicker = SaColorPickerScript.new()
    holder.add_child(picker)
    picker._ready()
    picker.apply_shape_setting()
    picker.shape.lightness_bar.size = Vector2(18.0, 200.0)
    picker.shape.color_committed.connect(func(c: Color) -> void: _committed.append(c))
    return picker


func _press(y: float, pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = Vector2(9.0, y)
    return event


func _drag_to(y: float) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.position = Vector2(9.0, y)
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    return event


func _near(got: Color, want: Color, tolerance: float, what: String) -> void:
    assert_almost_eq(got.r, want.r, tolerance, "%s: red" % what)
    assert_almost_eq(got.g, want.g, tolerance, "%s: green" % what)
    assert_almost_eq(got.b, want.b, tolerance, "%s: blue" % what)


func test_the_bar_runs_from_black_through_the_colour_to_white() -> void:
    var holder := Control.new()
    var picker := _disc(holder)
    var orange := OkhslConversionsScript.okhsl_to_srgb(0.15, 0.9, 0.5)
    picker.shape.set_from_color(orange)
    var shape: SaPickerShape = picker.shape

    var foot := shape.lightness_bar_colour(0.0)
    var head := shape.lightness_bar_colour(1.0)
    assert_true(foot.r < 0.02 and foot.g < 0.02 and foot.b < 0.02, "The foot is near black")
    assert_true(head.r > 0.98 and head.g > 0.98 and head.b > 0.98, "and the head near white")
    _near(shape.lightness_bar_colour(0.5), orange, 0.02, "The middle is the orange at OK-HSL lightness 0.5")

    shape.set_from_color(OkhslConversionsScript.okhsl_to_srgb(0.73, 0.9, 0.5))
    var blue := OkhslConversionsScript.okhsl_to_srgb(0.73, 0.9, 0.5)
    _near(shape.lightness_bar_colour(0.5), blue, 0.02, "Turned to blue, the middle is the blue")
    assert_true(shape.lightness_bar_colour(0.5).b > shape.lightness_bar_colour(0.5).r, "and it is a blue")
    holder.free()


func test_the_shader_has_a_bar_mode_the_twin_stands_for() -> void:
    var source := FileAccess.get_file_as_string(OKHSV_SHADER)
    assert_true(source.contains("picker_mode == %d" % SaPickerShape.LIGHTNESS_BAR_MODE), "The Oklab shader draws the bar mode")
    assert_true(source.contains("uniform float bar_saturation"), "from the saturation it is handed")
    var holder := Control.new()
    var picker := _disc(holder)
    var mat: ShaderMaterial = picker.shape.lightness_bar.material
    var mode := int(mat.get_shader_parameter("picker_mode"))
    assert_eq(mode, SaPickerShape.LIGHTNESS_BAR_MODE, "and the bar's material asks for it")
    holder.free()


func test_the_bar_follows_the_hue_and_the_saturation() -> void:
    var holder := Control.new()
    var picker := _disc(holder)
    picker.shape.set_from_color(OkhslConversionsScript.okhsl_to_srgb(0.15, 0.9, 0.5))
    var mat: ShaderMaterial = picker.shape.lightness_bar.material
    var drawn_hue := float(mat.get_shader_parameter("current_hue"))
    assert_almost_eq(drawn_hue, picker.shape.hue, 0.0001, "The bar is drawn at the colour's hue")
    assert_almost_eq(float(mat.get_shader_parameter("bar_saturation")), 0.9, 0.01, "and at its saturation")
    picker.shape.set_from_color(OkhslConversionsScript.okhsl_to_srgb(0.73, 0.4, 0.5))
    drawn_hue = float(mat.get_shader_parameter("current_hue"))
    assert_almost_eq(drawn_hue, picker.shape.hue, 0.0001, "A new hue redraws it")
    assert_almost_eq(float(mat.get_shader_parameter("bar_saturation")), 0.4, 0.01, "and a new saturation")
    holder.free()


func test_a_press_a_quarter_of_the_way_up_picks_a_quarter_lightness() -> void:
    var holder := Control.new()
    var picker := _disc(holder)
    picker.shape.set_from_color(OkhslConversionsScript.okhsl_to_srgb(0.15, 0.9, 0.5))
    picker.shape.lightness_bar.gui_input.emit(_press(150.0, true))
    var lightness := OkhslConversionsScript.srgb_to_okhsl(picker.shape.color()).z
    assert_almost_eq(lightness, 0.25, 0.01, "The picked colour's OK-HSL lightness is a quarter")
    holder.free()


func test_a_drag_commits_one_colour_when_it_ends() -> void:
    var holder := Control.new()
    var picker := _disc(holder)
    picker.shape.set_from_color(OkhslConversionsScript.okhsl_to_srgb(0.15, 0.9, 0.5))
    var bar: Control = picker.shape.lightness_bar
    bar.gui_input.emit(_press(100.0, true))
    bar.gui_input.emit(_drag_to(80.0))
    bar.gui_input.emit(_drag_to(40.0))
    assert_eq(_committed.size(), 0, "Nothing is committed while the drag goes on")
    bar.gui_input.emit(_press(40.0, false))
    assert_eq(_committed.size(), 1, "One colour is committed after it")
    assert_almost_eq(OkhslConversionsScript.srgb_to_okhsl(_committed[0]).z, 0.8, 0.01, "at the lightness it ended on")
    holder.free()


func test_a_wheel_notch_nudges_the_lightness() -> void:
    var holder := Control.new()
    var picker := _disc(holder)
    picker.shape.set_from_color(OkhslConversionsScript.okhsl_to_srgb(0.15, 0.9, 0.5))
    var notch := InputEventMouseButton.new()
    notch.button_index = MOUSE_BUTTON_WHEEL_UP
    notch.pressed = true
    picker.shape.lightness_bar.gui_input.emit(notch)
    var lifted := 0.5 + SaPickerShape.LIGHTNESS_WHEEL_STEP
    assert_almost_eq(float(picker.shape.report()["lightness_slider"]), lifted, 0.001, "A notch up lifts it")
    notch.button_index = MOUSE_BUTTON_WHEEL_DOWN
    picker.shape.lightness_bar.gui_input.emit(notch)
    assert_almost_eq(float(picker.shape.report()["lightness_slider"]), 0.5, 0.001, "and a notch down puts it back")
    holder.free()
