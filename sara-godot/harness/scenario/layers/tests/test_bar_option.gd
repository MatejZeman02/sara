## The tool options bar's own capture door: the `bar_option` step that
## moves one of its controls by option key, and the `options` block of
## `bar_report()` that says what the bar shows beside what the tool holds.
##
## The docker's twin of this is `ToolOptionsDocker.capture_option`, and the gap
## was that the bar had neither half.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A machine holding the built-in tools needs a surface, which needs a device.
const REQUIRES_GPU := true

static var scratch_profile: String = SaDataRoot.path("test_bar_option.cfg")

var _saved_path: String = ""
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _bar: ToolOptionsBar = null


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()
    SaSettings.load_settings()
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _registries = Fixtures.make_registries(_surface)
    _bar = ToolOptionsBar.new()
    _bar.target_tool_machine = _machine
    _bar._ready()
    _bar.bind_registries(_registries.blend_modes)


func after_each() -> void:
    _bar.free()
    Fixtures.teardown(_surface, _machine)
    _registries = null
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


func _brush() -> ToolState:
    return _machine.get_tool("brush")


## The step's own arithmetic, on a slider: the value is clamped to the range the
## spec declares and the control's signal carries it to the tool. `radius` is a
## fraction of the canvas rather than pixels, so 0.05 is what a scenario writes.
func test_a_slider_is_driven_and_the_tool_follows() -> void:
    var slider := _bar.control_for(&"radius") as FactorSlider
    assert_not_null(slider, "The brush declares Size for the bar")
    assert_true(SaCaptureLayers._drive_bar_control(slider, 0.05), "The step knows how to move a slider")
    assert_almost_eq(slider.value, 0.05, 0.0001, "The control shows what it was written")
    assert_almost_eq(float(_brush().settings.radius), 0.05, 0.0001, "and the brush holds it")


## Past the spec's ceiling the step clamps rather than refusing, the way the
## docker's step does, because a scenario asking for a size larger than the
## slider offers wants the largest size and not an error line.
func test_a_value_past_the_range_is_clamped() -> void:
    var slider := _bar.control_for(&"radius") as FactorSlider
    assert_true(SaCaptureLayers._drive_bar_control(slider, 99.0), "The write lands")
    assert_almost_eq(slider.value, slider.max_value, 0.0001, "at the top of the slider's range")
    assert_almost_eq(float(_brush().settings.radius), slider.max_value, 0.0001, "and the brush holds that")


## A value the control already holds is still written, because Godot drops a
## `value_changed` for a value that did not change and a scenario that set the
## opacity twice would silently do it once.
func test_writing_the_value_already_there_still_reaches_the_tool() -> void:
    var slider := _bar.control_for(&"opacity") as FactorSlider
    assert_true(SaCaptureLayers._drive_bar_control(slider, 0.4), "The first write lands")
    _brush().settings.opacity = 0.9
    assert_true(SaCaptureLayers._drive_bar_control(slider, 0.4), "and so does the second")
    assert_almost_eq(float(_brush().settings.opacity), 0.4, 0.0001, "which put the bar's value back on the brush")


## The toggle and the dropdown go through the same door. `eraser_toggled` sits
## on the tool rather than on its settings, which is what makes it worth having
## in this test beside a settings field.
func test_a_toggle_and_a_dropdown_are_driven_too() -> void:
    var toggle := _bar.control_for(&"eraser_toggled") as Button
    assert_not_null(toggle, "The brush declares Erase for the bar")
    assert_true(SaCaptureLayers._drive_bar_control(toggle, true), "The step knows how to move a toggle")
    assert_true(bool(_brush().eraser_toggled), "and the tool holds it")
    var choice := _bar.control_for(&"stabilizer_mode") as SaChoiceButton
    assert_not_null(choice, "The brush declares Stabilizer for the bar")
    assert_true(SaCaptureLayers._drive_bar_control(choice, 2), "The step knows how to move a dropdown")
    assert_eq(int(_brush().settings.stabilizer_mode), 2, "and the brush holds the id behind the row")


## A control nothing here knows how to move says so rather than reporting a
## write that did not happen.
func test_an_undrivable_control_is_refused() -> void:
    var label := Label.new()
    assert_false(SaCaptureLayers._drive_bar_control(label, 1.0), "A label takes nothing")
    label.free()


## The report is the other half: a row per built control, carrying what the bar
## shows and what the tool holds as two readings rather than one.
func test_the_report_carries_the_bar_and_the_tool_apart() -> void:
    var slider := _bar.control_for(&"radius") as FactorSlider
    SaCaptureLayers._drive_bar_control(slider, 0.05)
    var report: Dictionary = _bar.bar_report()
    assert_true(report.has("options"), "The dump's bar block carries the options")
    var rows: Dictionary = report["options"]
    assert_true(rows.has("radius"), "with a row for a key that is not the stabilizer")
    var row: Dictionary = rows["radius"]
    assert_almost_eq(float(row["shown"]), 0.05, 0.0001, "what the bar shows")
    assert_almost_eq(float(row["tool"]), 0.05, 0.0001, "and what the brush holds")
    assert_true(bool(row["declared"]), "declared by the shown tool")
    assert_true(rows.has("opacity"), "and a row for Opacity, the other key the note names")


## The two readings are what makes the report worth taking. A control moved
## behind the tool's back reads as the disagreement it is, which one reading
## could not show.
func test_a_bar_that_stopped_following_its_tool_reads_as_two_numbers() -> void:
    var slider := _bar.control_for(&"radius") as FactorSlider
    SaCaptureLayers._drive_bar_control(slider, 0.05)
    slider.set_value_no_signal(0.12)
    var row: Dictionary = (_bar.bar_report()["options"] as Dictionary)["radius"]
    assert_almost_eq(float(row["shown"]), 0.12, 0.0001, "The bar shows the number nothing wrote")
    assert_almost_eq(float(row["tool"]), 0.05, 0.0001, "and the brush still holds the one that was")


## The kinds that hold no value answer null rather than a made up reading, and
## the ramp is the one the bar could build: `ramp` is its step, not this one.
func test_a_control_that_holds_no_value_reads_null() -> void:
    assert_null(_bar.control_value(&"no_such_option"), "A key with no control reads null")
