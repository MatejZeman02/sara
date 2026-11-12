## The curve editor builds over a settings resource that is not the stamp
## brush's.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `SaCurveOptionControl` and `SaSensorList` live in the widget toolkit,
## `ui/widgets/curve_option`, and not in the stamp brush's `ui/`, so the noise
## brush's page draws the curve editor a painter already knows from the stamp's. The
## stamp's own suites prove its pages still build. This one proves the other
## half, that nothing in the control needs the stamp: a settings resource of its
## own, declared below the way a second engine would declare one, carries two
## curve options, and the brush editor's page machinery builds, binds and edits
## them through the three doors the control hands a spec.
extends "res://tests/test_framework.gd"

## The widget files, read as text for the one question a parse cannot answer:
## whether they name anything of the stamp brush's.
const WIDGET_FILES: Array[String] = [
    "res://ui/widgets/curve_option/sa_curve_option_control.gd",
    "res://ui/widgets/curve_option/sa_sensor_list.gd",
]


## A second engine's settings, the shape the noise brush's will have: two
## modulated parameters and nothing of the stamp's.
class GrainSettings:
    extends Resource

    @export var grain_option: SaCurveOption = SaCurveOption.create_default()
    @export var drift_option: SaCurveOption = SaCurveOption.create_default()


var _page_before: String = ""


func before_each() -> void:
    # `show_page` writes the page it opened into the profile, and a suite has no
    # business leaving one of its own titles there.
    _page_before = SaSettings.brush_editor_page


func after_each() -> void:
    SaSettings.brush_editor_page = _page_before


## A curve option spec as an engine outside the stamp declares one: its key,
## the page it is, and the control's three doors.
func _spec(key: StringName, label: String) -> SaOptionSpec:
    var spec := SaOptionSpec.make(key, label, SaOptionSpec.Kind.CURVE_OPTION)
    spec.build_control = SaCurveOptionControl.build_control
    spec.bind_value = SaCurveOptionControl.bind_control.bind(label)
    spec.describe_value = SaCurveOptionControl.describe
    return spec


func _specs() -> Array[SaOptionSpec]:
    var specs: Array[SaOptionSpec] = [_spec(&"grain_option", "Grain"), _spec(&"drift_option", "Drift")]
    return specs


## The editor's pages take the foreign settings as their own: a page per option,
## each with its tick read off that option, and the page built on the right is
## the toolkit's control bound to the settings' own resource rather than to a
## copy or a throwaway.
func test_the_editor_pages_build_the_control_over_foreign_settings() -> void:
    var settings := GrainSettings.new()
    settings.drift_option.enabled = false
    var box := VBoxContainer.new()
    var pages := SaBrushEditorPages.new(box)
    var rows: Array = pages.bind_specs(_specs(), ToolState.new(), settings, 0.0)

    assert_eq(rows.size(), 2, "two curve options, two pages")
    assert_eq(String(rows[0]["title"]), "Grain", "in the order the settings' engine declared them")
    assert_true(bool(rows[0]["switch"]), "a curve option page carries its switch")
    assert_false(bool(rows[1]["on"]), "read off the foreign option's own enabled")

    pages.show_page(0)
    var control := pages.curve_control as SaCurveOptionControl
    assert_not_null(control, "the page is the toolkit's curve editor")
    assert_true(control.option == settings.grain_option, "bound to the settings' own option, edited in place")
    var report := control.option_report()
    assert_eq(String(report["page"]), "Grain", "reporting the page the spec named")
    assert_eq(String(report["selected"]), "pressure", "with the option's one sensor picked")
    box.free()


## An edit in the control lands on the foreign settings and reaches the editor
## through the write door, which is how its dirty flag and its preview hear.
func test_an_edit_lands_on_the_foreign_settings_and_is_reported() -> void:
    var settings := GrainSettings.new()
    var box := VBoxContainer.new()
    var pages := SaBrushEditorPages.new(box)
    pages.bind_specs(_specs(), ToolState.new(), settings, 0.0)
    var written: Array[StringName] = []
    pages.option_written.connect(func(key: StringName, _value: Variant) -> void: written.append(key))
    pages.show_page(1)
    var control := pages.curve_control as SaCurveOptionControl

    assert_true(control.apply_preset("s"), "the S preset applies")
    assert_eq(settings.drift_option.common_curve.size(), 4, "the S shape's four points are on the drift option")
    assert_true(control.set_sensor_active("speed", true), "Speed ticks")
    assert_true(settings.drift_option.active_sensors().size() == 2, "and joins Pressure on the foreign option")
    assert_eq(settings.grain_option.active_sensors().size(), 1, "while the other page's option is untouched")
    assert_true(written.has(&"drift_option"), "and every edit told the editor, under the option's key")
    box.free()


## The Tool Options docker's row text comes off the same doors, over any option.
func test_the_row_text_describes_a_foreign_option() -> void:
    var settings := GrainSettings.new()
    var spec := _spec(&"grain_option", "Grain")
    settings.grain_option.strength = 0.4
    assert_eq(spec.describe_value.call(settings.grain_option), "40%, Pressure", "strength and sensor, as the stamp's rows read")
    settings.grain_option.enabled = false
    assert_eq(spec.describe_value.call(settings.grain_option), "Off", "and a switched-off option reads Off")


## The toolkit's curve editor names nothing of the stamp brush's, which is what
## lets the noise brush draw it without reaching into another module.
func test_the_widgets_name_nothing_of_the_stamp() -> void:
    for path: String in WIDGET_FILES:
        var text := FileAccess.get_file_as_string(path)
        assert_false(text.is_empty(), "%s is readable" % path)
        assert_false(text.contains("res://modules"), "%s loads nothing from a module" % path)
        assert_false(text.contains("SaStampBrush"), "%s names no stamp brush class" % path)
