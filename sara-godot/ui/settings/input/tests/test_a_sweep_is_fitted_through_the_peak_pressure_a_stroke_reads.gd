## A sweep is read through the painter's peak pressure, as a stroke is.
##
## A stroke divides the raw pressure by the peak the painter set under
## Preferences > Tablet and only then reads the correction. A pen whose hand
## reaches a fifth of the hardware's range, with the peak set to a quarter,
## sweeps to about 0.8 of that scale, so the fitted curve must reach its own
## peak there and not at a fifth, where a stroke would run full at a light touch.
extends "res://tests/test_framework.gd"

var _dialog: SaTabletSweepDialog = null
var _had_maximum := 1.0
var _had_correction := PackedFloat32Array()


func before_each() -> void:
    _had_maximum = SaSettings.tablet_max_pressure
    _had_correction = SaTablet.correction.duplicate()
    _dialog = SaTabletSweepDialog.new()
    _dialog.size_strips_for_host(1080.0)


func after_each() -> void:
    _dialog.free()
    _dialog = null
    SaSettings.tablet_max_pressure = _had_maximum
    SaTablet.correction = _had_correction


## Three even sweeps from nothing to *top* raw pressure, as the pen reports it.
func _sweep_three(top: float) -> void:
    for index in range(3):
        _dialog.begin_sweep(index)
        for i in range(40):
            var t := float(i) / 39.0
            _dialog.feed(index, t, t * top)
        _dialog.end_sweep(index)


func _at(table: PackedFloat32Array, pressure: float) -> float:
    return table[int(round(clampf(pressure, 0.0, 1.0) * float(table.size() - 1)))]


func test_a_hand_that_reaches_its_peak_pressure_fits_a_curve_near_the_diagonal() -> void:
    SaSettings.tablet_max_pressure = 0.25
    _sweep_three(0.2)
    var table := _dialog.fitted
    assert_eq(table.size(), SaTabletSweep.SAMPLES, "Three counted sweeps fit a curve")
    assert_almost_eq(_at(table, 0.4), 0.4, 0.05, "Half the sweep's peak paints about what it did")
    assert_almost_eq(_at(table, 0.8), SaTabletSweep.SWEEP_PEAK, 0.03, "The sweep's peak paints the sweep peak")
    assert_true(_at(table, 0.3) < 0.5, "and a light press is not read as most of full")


func test_a_stroke_at_the_sweep_s_peak_paints_the_sweep_peak() -> void:
    SaSettings.tablet_max_pressure = 0.25
    _sweep_three(0.2)
    var painted := SaTablet.normalize(0.2, SaSettings.tablet_max_pressure, 1.0, _dialog.fitted)
    assert_almost_eq(painted, SaTabletSweep.SWEEP_PEAK, 0.03, "The raw reading the hand swept to paints 0.8")
    var light := SaTablet.normalize(0.05, SaSettings.tablet_max_pressure, 1.0, _dialog.fitted)
    assert_almost_eq(light, 0.2, 0.05, "and a quarter of it paints about a quarter of that")
