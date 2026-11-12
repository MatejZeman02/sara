## The Radius slider keeps its width while dragged and always shows two
## decimals.
##
## A slider that changes size when dragged is jarring, and the decimals should
## be fixed. The Radius row once trimmed its noughts, so its text went from "25 px" to "112.37 px" and the slider asked
## for the width of the text it showed now, while its widest end, "540 px",
## was narrower than the values between. The row shows two decimals always
## and the slider asks for the widest text its whole drag can show.
## `scenarios/the-radius-slider-keeps-its-width-while-dragged-and-always-shows-two-decimals.json`
## is the same bar on the running app at radius 5 and 500.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar builds from every registered tool's descriptor, which needs a
## machine, a surface and therefore a device.
const REQUIRES_GPU := true

## How many places along the drag the suite stops at, bottom and top included.
const STEPS := 60

var _host: Node = null
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _bar: ToolOptionsBar = null


func before_each() -> void:
    _host = Node.new()
    _host.name = "U367TestHost"
    EventBus.add_child(_host)
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _registries = Fixtures.make_registries(_surface)
    _bar = ToolOptionsBar.new()
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar._ready()
    _bar.bind_registries(_registries.blend_modes)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    _bar = null
    Fixtures.teardown(_surface, _machine)
    _registries = null


func _radius() -> FactorSlider:
    return _bar.control_for(&"radius") as FactorSlider


## The drag's own places from its floor to its ceiling, geometric as the row is.
func _places(slider: FactorSlider) -> Array[float]:
    var out: Array[float] = []
    var bottom := slider.drag_min()
    var top := slider.drag_max()
    for i in range(STEPS + 1):
        out.append(bottom * pow(top / bottom, float(i) / float(STEPS)))
    return out


func test_the_radius_keeps_one_width_and_two_decimals_from_its_floor_to_its_ceiling() -> void:
    var slider := _radius()
    assert_not_null(slider, "The brush's bar carries a Radius slider")
    if slider == null:
        return
    assert_true(slider.logarithmic, "and it is the geometric row the painter drags")
    var two_decimals := RegEx.create_from_string("^Radius: -?[0-9]+\\.[0-9]{2} px$")
    var widths: Dictionary[float, bool] = {}
    var wrong: Array[String] = []
    for place in _places(slider):
        slider.set_value_no_signal(place)
        widths[slider.get_combined_minimum_size().x] = true
        if two_decimals.search(slider._label.text) == null:
            wrong.append(slider._label.text)
    assert_eq(widths.size(), 1, "One width at every one of %d places along the drag: %s" % [STEPS + 1, widths.keys()])
    assert_eq(wrong, [] as Array[String], "and every text carries two decimals")


## The width the row asks for is the widest text it can show, so the slider is
## never narrower than what it draws.
func test_the_width_holds_the_widest_text_the_drag_shows() -> void:
    var slider := _radius()
    var font := slider._label.label_settings.font
    var size := slider._label.label_settings.font_size
    var widest := 0.0
    for place in _places(slider):
        slider.set_value_no_signal(place)
        widest = maxf(widest, font.get_string_size(slider._label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x)
    var measured := slider.text_width()
    assert_true(measured >= widest, "The measured width %.1f holds the widest text drawn, %.1f" % [measured, widest])


## A whole size reads with its noughts now, and Left still steps a pixel.
func test_a_whole_size_reads_two_decimals_and_a_key_steps_a_pixel() -> void:
    var slider := _radius()
    var per_pixel := 1.0 / slider.display_value_multiplier
    slider.set_value_no_signal(25.0 * per_pixel)
    assert_eq(slider._label.text, "Radius: 25.00 px", "Twenty-five pixels read 25.00")
    assert_true(slider.steps_by_whole_units, "The row asks for whole steps")
    assert_almost_eq(slider.display_unit() / per_pixel, 1.0, 1e-6, "so one press is one pixel and not a hundredth of one")
