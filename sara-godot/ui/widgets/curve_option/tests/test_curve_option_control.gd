## The control that edits one `SaCurveOption`.
##
## The control lives in the widget toolkit, `ui/widgets/curve_option`, so its
## suite is a skeleton suite and needs no module.
##
## Every test here is the same question asked twice: what the control shows, and
## what the option holds. A graph drawn from a curve the control then failed to
## write back looks right in a screenshot and is wrong in the brush, so the two
## are asserted as a pair rather than one standing in for the other.
extends "res://tests/test_framework.gd"

const CurveOptionControlScript = preload("res://ui/widgets/curve_option/sa_curve_option_control.gd")

## The control under test, rebuilt per test and freed after it.
##
## Freed by hand rather than queued, because a suite runs with no scene tree and
## `queue_free` there is a leak the runner counts and the suite line does not
## mention.
var built: Control = null


func before_each() -> void:
    built = CurveOptionControlScript.new()
    built.bind_option(SaCurveOption.create_default(), "Size")


func after_each() -> void:
    if built != null:
        built.free()
        built = null


# --- The eight preset shapes ------------------------------------------------------


func test_the_eight_presets_are_kritas_own_points() -> void:
    var presets: Dictionary = CurveOptionControlScript.PRESETS

    assert_eq(presets.size(), 8, "Eight shapes, no more")
    assert_eq(CurveOptionControlScript.PRESET_ORDER.size(), 8, "and eight buttons in the row")
    assert_eq(
        Array(presets["s"]),
        [Vector2(0.0, 0.0), Vector2(0.25, 0.1), Vector2(0.75, 0.9), Vector2(1.0, 1.0)],
        "S is Krita's two inner points at 0.1 and 0.9, not a tidied cubic"
    )
    assert_eq(Array(presets["l"]), [Vector2(0.0, 1.0), Vector2(0.25, 0.48), Vector2(1.0, 0.0)], "and L its 0.48")


func test_every_preset_order_entry_has_points() -> void:
    for preset: String in CurveOptionControlScript.PRESET_ORDER:
        assert_true(CurveOptionControlScript.PRESETS.has(preset), "%s has points" % preset)
        assert_true(CurveOptionControlScript.PRESET_TIPS.has(preset), "and a sentence for its tooltip")


func test_pressing_a_preset_writes_the_points_and_the_graph_shows_them() -> void:
    var control := built

    assert_true(control.apply_preset("arch"), "Arch is one of the eight")

    var report: Dictionary = control.option_report()
    assert_eq(report["curve"], [[0.0, 0.0], [0.5, 1.0], [1.0, 0.0]], "The option holds the arch")
    assert_eq(report["shown_curve"], report["curve"], "and the graph shows what the option holds")


func test_a_preset_that_is_not_one_of_the_eight_is_refused() -> void:
    var control := built

    assert_false(control.apply_preset("sawtooth"), "Nothing else is a preset")
    assert_eq(control.option_report()["curve"], [[0.0, 0.0], [1.0, 1.0]], "and the curve is untouched")


# --- Dragging the graph -----------------------------------------------------------


func test_a_moved_point_reaches_the_option() -> void:
    var control := built

    control.set_curve(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.4, 0.8), Vector2(1.0, 1.0)]))

    var option: SaCurveOption = control.option
    assert_eq(option.common_curve.size(), 3, "Three points on the shared curve")
    assert_true(option.common_curve[1].is_equal_approx(Vector2(0.4, 0.8)), "and the middle one is where it was put")


## With the curve shared, one graph edits `common_curve`. With it off, the graph
## edits whichever sensor is selected, which is the whole of what the checkbox
## under it means.
func test_sharing_off_puts_the_curve_on_the_selected_sensor() -> void:
    var control := built
    control.set_sensor_active("speed", true)
    control.set_use_same_curve(false)
    control.select_sensor("speed")

    control.apply_preset("u")

    var option: SaCurveOption = control.option
    var speed := option.sensor_for(SaSensor.Id.SPEED)
    assert_not_null(speed, "The speed sensor exists once it is ticked")
    assert_eq(speed.curve.size(), 3, "and the U landed on its own curve")
    assert_eq(option.common_curve.size(), 2, "leaving the shared curve the identity")


# --- The sensor list --------------------------------------------------------------


func test_ticking_a_sensor_makes_it_active() -> void:
    var control := built

    assert_true(control.set_sensor_active("tilt_x", true), "Tilt X is takeable")

    var report: Dictionary = control.option_report()
    assert_true("tilt_x" in report["active"], "The option reads it as active")
    assert_true("tilt_x" in report["ticked"], "and the checkbox shows it ticked")


func test_the_last_active_sensor_cannot_be_unticked() -> void:
    var control := built
    var report: Dictionary = control.option_report()
    assert_eq(report["active"], ["pressure"], "A default option listens to pressure alone")

    assert_false(control.set_sensor_active("pressure", false), "and the last one is refused")

    report = control.option_report()
    assert_eq(report["active"], ["pressure"], "so it stays active")
    assert_true("pressure" in report["ticked"], "and the checkbox goes back on rather than lying")


func test_a_sensor_can_be_unticked_once_a_second_one_is_on() -> void:
    var control := built
    control.set_sensor_active("speed", true)

    assert_true(control.set_sensor_active("pressure", false), "Two active, so one can go")
    assert_eq(control.option_report()["active"], ["speed"], "leaving the other")


# --- The rest of the rows ---------------------------------------------------------


func test_the_strength_slider_shows_a_percentage_of_the_option() -> void:
    var control := built

    control.set_strength(0.35)

    var report: Dictionary = control.option_report()
    assert_almost_eq(float(report["strength"]), 0.35, 0.0001, "The option holds the fraction")
    assert_almost_eq(float(report["shown_strength"]), 0.35, 0.0001, "and the slider holds the same number")


func test_strength_is_clamped_to_the_options_own_bounds() -> void:
    var control := built
    var option: SaCurveOption = control.option
    option.strength_min = 0.1
    option.strength_max = 0.8
    control.sync()

    control.set_strength(2.0)

    assert_almost_eq(float(control.option_report()["strength"]), 0.8, 0.0001, "The option's own range wins")


func test_the_combination_mode_and_the_two_checkboxes_write_through() -> void:
    var control := built

    control.set_combine(SaCurveOption.Combine.MAXIMUM)
    control.set_use_curve(false)
    control.set_use_same_curve(false)

    var report: Dictionary = control.option_report()
    assert_eq(int(report["combine"]), int(SaCurveOption.Combine.MAXIMUM), "Maximum on the option")
    assert_eq(int(report["shown_combine"]), int(SaCurveOption.Combine.MAXIMUM), "and on the dropdown")
    assert_false(bool(report["use_curve"]), "Enable pen settings off")
    assert_false(bool(report["use_same_curve"]), "and the curve no longer shared")


func test_a_sweeping_sensor_shows_its_length_and_periodic() -> void:
    var control := built
    control.set_sensor_active("distance", true)
    control.select_sensor("distance")

    control.set_length(240)
    control.set_periodic(false)

    var settings: Dictionary = control.option_report()["sensor_settings"]
    assert_eq(int(settings["length"]), 240, "The distance sensor's own length")
    assert_false(bool(settings["periodic"]), "and its periodic flag")


func test_the_drawing_angle_shows_its_offset_and_lock() -> void:
    var control := built
    control.set_sensor_active("drawing_angle", true)
    control.select_sensor("drawing_angle")

    control.set_angle_offset(45.0)
    control.set_lock_angle(true)

    var settings: Dictionary = control.option_report()["sensor_settings"]
    assert_almost_eq(float(settings["angle_offset"]), 45.0, 0.0001, "The offset in degrees")
    assert_true(bool(settings["lock_angle"]), "and the lock")


# --- The graph beside the sensor list, square at any width -------------------


## `scenarios/curve-graph-square.json` is the proof a real layout pass can
## give and a detached control cannot: `graph_rect` reads square at two
## widths and `sensors_rect` reads beside it in both. What a headless test
## can hold instead is the structure that answers a real width, an
## `AspectRatioContainer` around the graph rather than the graph sized
## straight into the row.
func test_the_graph_sits_in_a_square_aspect_container_beside_the_sensor_list() -> void:
    var control := built
    var row := control.get_node("CurveRow") as HBoxContainer
    assert_not_null(row, "the graph and the sensor list share one row")

    var aspect := row.get_node("GraphAspect") as AspectRatioContainer
    assert_not_null(aspect, "the graph is wrapped rather than dropped straight into the row")
    assert_almost_eq(aspect.ratio, 1.0, 0.0001, "square, whatever width the row is given")
    assert_eq(aspect.get_node("CurveGraph"), control._graph, "and the wrapped node is the control's own graph")

    var sensors_index := row.get_child(row.get_child_count() - 1)
    assert_eq(sensors_index, control._sensors, "the sensor list is the row's other child, beside the graph")


# --- The spec fields the editor builds itself from --------------------------------


func test_the_spec_carries_a_page_and_the_new_kind() -> void:
    var spec := SaOptionSpec.make(&"size_dynamics", "Size", SaOptionSpec.Kind.CURVE_OPTION)
    spec.page = "Size"

    assert_eq(spec.kind, SaOptionSpec.Kind.CURVE_OPTION, "The kind exists")
    assert_eq(spec.page, "Size", "and a row knows which page it is on")
    assert_true(
        int(SaOptionSpec.Kind.CURVE) < int(SaOptionSpec.Kind.CURVE_OPTION),
        "and CURVE keeps its ordinal, the new kind being added after it rather than in the middle"
    )
