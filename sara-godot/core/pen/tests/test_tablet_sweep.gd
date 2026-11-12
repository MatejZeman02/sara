## What three hand sweeps fit to, and what the correction then does to a
## stroke.
##
## No GPU and no pen: the sweeps are synthetic, each a known pressure shape
## along its block, and the fit is arithmetic. That is the only honest way to drive this,
## because an injected motion never reaches a `gui_input` and a suite has no
## tablet.
extends "res://tests/test_framework.gd"


## A sweep of *count* readings over *seconds*, whose raw pressure at fraction t
## is `t` raised to *shape*. A shape of 1 is a hand that already ramps evenly,
## and 2 is one that presses too little early and catches up at the end.
func _sweep(shape: float, seconds: float = 2.0, count: int = 40) -> PackedVector2Array:
    var sweep := PackedVector2Array()
    for i in range(count):
        var t := float(i) / float(count - 1)
        sweep.append(Vector2(t * seconds, pow(t, shape)))
    return sweep


func _three(shape: float) -> Array:
    return [_sweep(shape), _sweep(shape), _sweep(shape)]


func _at(table: PackedFloat32Array, pressure: float) -> float:
    return table[int(round(clampf(pressure, 0.0, 1.0) * float(table.size() - 1)))]


## A hand that already ramps evenly needs no correction, so the table comes
## back as the diagonal.
func test_an_even_hand_fits_the_diagonal() -> void:
    var table := SaTabletSweep.fit(_three(1.0))
    assert_eq(table.size(), 256, "One entry per step")
    for pressure: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
        assert_almost_eq(_at(table, float(pressure)), float(pressure), 0.02, "%.2f is left alone" % pressure)


## The correction is the inverse of what the hand did. A hand whose sweep came
## out as t squared reported a quarter at half effort, so the brush has to read
## a quarter as half.
func test_the_correction_is_the_inverse_of_the_sweep() -> void:
    var table := SaTabletSweep.fit(_three(2.0))
    assert_almost_eq(_at(table, 0.25), 0.5, 0.02, "A quarter is read as half")
    assert_almost_eq(_at(table, 0.81), 0.9, 0.02, "and 0.81 as nine tenths")
    assert_almost_eq(_at(table, 1.0), 1.0, 0.01, "with full still full")


## Three sweeps of different shapes are averaged, and each is normalised to its
## own duration first, so a slow sweep does not outvote a quick one.
func test_three_sweeps_are_averaged_after_their_own_durations() -> void:
    var quick := _sweep(2.0, 0.6)
    var slow := _sweep(2.0, 4.0)
    var mean := SaTabletSweep.mean_of([quick, slow])
    assert_almost_eq(mean[128], pow(128.0 / 255.0, 2.0), 0.01, "Two sweeps of one shape mean that shape")

    var mixed := SaTabletSweep.mean_of([_sweep(1.0), _sweep(3.0)])
    var half := 128.0 / 255.0
    assert_almost_eq(mixed[128], (half + pow(half, 3.0)) * 0.5, 0.01, "and two shapes mean the two")


## A sweep that dips is not invertible, so the fit carries the running maximum
## forward: the shape the hand made survives and only the wobble is flattened.
func test_a_wobble_is_flattened_rather_than_folded() -> void:
    var wobbly := PackedVector2Array(
        [Vector2(0.0, 0.0), Vector2(0.5, 0.3), Vector2(1.0, 0.2), Vector2(1.5, 0.6), Vector2(2.0, 1.0)]
    )
    var mean := SaTabletSweep.monotone(SaTabletSweep.resample(wobbly))
    var previous := -1.0
    for value in mean:
        assert_true(value >= previous - 1e-5, "The shape never falls back")
        previous = value


## A tap is not a sweep, and neither is a recording of three events. A fit with
## nothing usable in it comes back empty rather than as the identity, so the
## caller can tell "not calibrated" from "calibrated flat".
func test_a_tap_is_refused() -> void:
    var tap := PackedVector2Array([Vector2(0.0, 0.2), Vector2(0.05, 0.5), Vector2(0.1, 0.7)])
    assert_false(SaTabletSweep.is_usable(tap), "Three readings over a tenth of a second is not a sweep")
    assert_true(SaTabletSweep.fit([tap, tap, tap]).is_empty(), "and fits nothing")
    assert_true(SaTabletSweep.is_usable(_sweep(1.0)), "A real one is usable")


## Above the hardest reading the hand ever made there is nothing left to
## correct, so the table saturates rather than running off the end. This is
## what makes a pen whose top third is never reached usable.
func test_the_table_saturates_past_the_hardest_reading() -> void:
    var short_sweep := PackedVector2Array()
    for i in range(40):
        var t := float(i) / 39.0
        short_sweep.append(Vector2(t * 2.0, t * 0.6))
    var table := SaTabletSweep.fit([short_sweep, short_sweep, short_sweep])
    assert_almost_eq(_at(table, 0.3), 0.5, 0.02, "Half the hand's travel is half the effort")
    assert_almost_eq(_at(table, 0.8), 1.0, 0.01, "and everything past its top is full")


## The correction is applied in the one place the maximum is applied, between
## the rescale and the brush's own gamma.
func test_the_correction_lands_in_the_stroke() -> void:
    var was := SaTablet.correction
    SaTablet.correction = SaTabletSweep.fit(_three(2.0))
    assert_almost_eq(SaTablet.normalize(0.25, 1.0, 1.0), 0.5, 0.02, "A quarter of the range is half a stroke")
    assert_almost_eq(SaTablet.normalize(0.25, 1.0, 2.0), 0.25, 0.02, "and the gamma still runs after it")

    SaTablet.correction = PackedFloat32Array()
    assert_almost_eq(SaTablet.normalize(0.25, 1.0, 1.0), 0.25, 1e-4, "An uncalibrated pen is untouched")
    SaTablet.correction = was


## A NaN is still zero rather than a laundered pressure, whatever the curve
## says, because the correction runs after that check and not before it.
func test_a_nan_is_still_refused() -> void:
    var was := SaTablet.correction
    SaTablet.correction = SaTabletSweep.fit(_three(2.0))
    assert_eq(SaTablet.normalize(NAN, 1.0, 1.0), 0.0, "A driver reporting nothing paints nothing")
    SaTablet.correction = was


## The table survives a round trip through the settings folder, and an
## identity one removes the file instead of writing a straight line nobody
## needs to load.
func test_the_table_round_trips_and_a_reset_removes_it() -> void:
    var was := SaTablet.correction
    var fitted := SaTabletSweep.fit(_three(2.0))
    SaTablet.save_correction(fitted)
    assert_true(FileAccess.file_exists(SaTablet.curve_path()), "The curve is beside the settings file")

    SaTablet.correction = PackedFloat32Array()
    SaTablet.load_correction()
    assert_eq(SaTablet.correction.size(), fitted.size(), "and it comes back the same size")
    assert_almost_eq(SaTablet.correction[64], fitted[64], 1e-5, "with the same numbers in it")

    SaTablet.save_correction(SaTabletSweep.identity())
    assert_false(FileAccess.file_exists(SaTablet.curve_path()), "A reset leaves no file behind")
    assert_true(SaTablet.correction.is_empty(), "and no correction")
    SaTablet.correction = was


## Try It is the point of the whole game: the same hand, through the fitted
## correction, paints over the coat the gradient the first pass revealed, the
## sweep's full being the gradient's white.
func test_the_try_it_pass_paints_the_corrected_hand_as_the_gradient() -> void:
    var was := SaTablet.correction
    var dialog := SaTabletSweepDialog.new()
    dialog.size_strips_for_host(1080.0)
    for index in range(3):
        _sweep_into(dialog, index, 2.0)
    assert_eq(dialog.phase, SaTabletSweepDialog.Phase.REVIEW, "Three sweeps fit")

    dialog.enter_test()
    assert_eq(dialog.phase, SaTabletSweepDialog.Phase.TEST, "and Try It puts the coats back")
    var strip: SaTabletSweepStrip = dialog._strips[0]
    assert_eq(strip.painted_at(strip.point_at(0.5)).a, 0.0, "with nothing on them")
    assert_eq(strip.scratched_at(strip.point_at(0.5)), 0.0, "and the coat whole")

    _sweep_into(dialog, 0, 2.0)
    for along: float in [0.25, 0.5, 0.75]:
        assert_almost_eq(
            dialog.lightness_of(along * along), along, 0.07, "The hand at %.2f of the block paints %.2f" % [along, along]
        )
        var painted := strip.painted_at(strip.point_at(along))
        var meant := SaTabletSweepStrip.ramp_color(dialog.lightness_of(along * along))
        assert_almost_eq(painted.r, meant.r, 0.02, "and the dab there is that lightness")
    assert_eq(strip.scratched_at(strip.point_at(0.5)), 0.0, "Painting never scratches")
    dialog.free()
    SaTablet.correction = was


## A drag of the curve during Try It is the live curve, and every stroke over
## the coats is laid again through it at once.
func test_a_drag_during_try_it_repaints_the_strokes_through_it() -> void:
    var was := SaTablet.correction
    var dialog := SaTabletSweepDialog.new()
    dialog.size_strips_for_host(1080.0)
    for index in range(3):
        _sweep_into(dialog, index, 2.0)
    var editor := dialog.find_child("FittedCurve", true, false) as SaCurveEditor
    assert_not_null(editor, "The curve editor is on the dialog")
    assert_true(editor.visible, "and is shown in review")
    assert_eq(editor.mouse_filter, Control.MOUSE_FILTER_STOP, "and takes the mouse, because it is meant to be dragged")

    dialog.enter_test()
    assert_true(editor.visible, "It stays through Try It")
    _sweep_into(dialog, 1, 2.0)
    editor.set_points(PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 1.0)]))
    assert_almost_eq(SaTablet.correct(0.25), 0.25, 0.01, "The dragged curve is the live one")
    var strip: SaTabletSweepStrip = dialog._strips[1]
    var painted := strip.painted_at(strip.point_at(0.5))
    var meant := SaTabletSweepStrip.ramp_color(0.25 / SaTabletSweep.SWEEP_PEAK)
    assert_almost_eq(painted.r, meant.r, 0.02, "and the stroke is laid again through it")
    dialog.free()
    SaTablet.correction = was


## The three bands are one size: a third of the height the dialog opens
## into and one thickness, with every slot the box its band turns into, at a
## short host and a tall one. Without the fix one dialog drew them 496, 199 and 301
## long, each whatever its slot had over.
##
## The window's own size is proved by the scenario rather than here: a Control
## out of the tree never refreshes its cached minimum size, so a dialog the
## suite builds reports the same content height at both.
func test_the_three_bands_are_one_size_at_two_host_heights() -> void:
    var dialog := SaTabletSweepDialog.new()
    for host: float in [900.0, 1440.0]:
        dialog.size_strips_for_host(host)
        var band := Vector2(roundf(host / 3.0), SaUI.pxf(SaTabletSweepDialog.STRIP_THICKNESS))
        assert_eq(dialog.strip_length, band.x, "At %d the length is a third of the host" % int(host))
        for index in range(3):
            var strip: SaTabletSweepStrip = dialog._strips[index]
            assert_eq(strip.size, band, "At %d, strip %d is a third of it long and one thickness" % [int(host), index])
            var degrees := float(SaTabletSweepDialog.STRIPS[index]["angle"])
            var slot := strip.get_parent() as Control
            assert_eq(
                slot.custom_minimum_size, SaTabletSweepDialog.turned_box(band, degrees), "and its slot is the box it turns into"
            )
    dialog.free()


## Every label stands under its own strip at the width of the strip's box, and
## wraps between words only, so "Top to bottom" cannot come out a letter a line.
func test_each_label_stands_under_its_strip_at_its_width() -> void:
    var dialog := SaTabletSweepDialog.new()
    dialog.size_strips_for_host(1080.0)
    for index in range(3):
        var strip: SaTabletSweepStrip = dialog._strips[index]
        var slot := strip.get_parent() as Control
        var label := dialog.find_child("Strip%dLabel" % index, true, false) as Label
        assert_eq(label.get_parent(), slot.get_parent(), "Label %d stands in its strip's column" % index)
        assert_eq(label.get_index(), slot.get_index() + 1, "right under the strip")
        assert_eq(label.custom_minimum_size.x, slot.custom_minimum_size.x, "as wide as the strip's box")
        assert_eq(label.autowrap_mode, TextServer.AUTOWRAP_WORD, "and never breaks inside a word")
    dialog.free()


## One synthetic sweep of *shape* fed into *dialog*'s strip *index* from the
## dot to the far end, the way the capture harness feeds one, ending with the
## lift.
func _sweep_into(dialog: SaTabletSweepDialog, index: int, shape: float) -> void:
    dialog.begin_sweep(index)
    for i in range(40):
        var t := float(i) / 39.0
        dialog.feed(index, t, pow(t, shape))
    dialog.end_sweep(index)


## The dialog records against where the pen is and fits when all three blocks
## are done, which is the whole of the game's state machine.
func test_the_dialog_fits_once_all_three_are_scratched() -> void:
    var dialog := SaTabletSweepDialog.new()
    assert_eq(dialog.phase, SaTabletSweepDialog.Phase.RECORD, "It opens ready to record")

    for index in range(3):
        _sweep_into(dialog, index, 2.0)
        if index < 2:
            assert_eq(dialog.phase, SaTabletSweepDialog.Phase.RECORD, "Strip %d alone is not a calibration" % index)

    assert_eq(dialog.phase, SaTabletSweepDialog.Phase.REVIEW, "The third one fits")
    var meant := lerpf(SaTabletSweep.FLOOR, SaTabletSweep.SWEEP_PEAK, 0.5)
    assert_almost_eq(_at(dialog.fitted, 0.25), meant, 0.02, "to the inverse of what was fed, under the room")

    dialog.restart()
    assert_eq(dialog.phase, SaTabletSweepDialog.Phase.RECORD, "Start Again clears it")
    assert_true(dialog.fitted.is_empty(), "and throws the fit away")
    dialog.free()
