## The lead is trained and chosen in Preferences.
##
## The lead is an option in Preferences, auto by default, where it only triggers
## when there is actual delay, like on Wayland. Four claims are checkable without a pointer:
## the Auto rule over its four cases, the setting's three values, the weights
## file's shape against what the ring reads of it, and the learned lead on a
## known motion under the same guards as the fit.
##
## The ring itself is drawn against `DisplayServer.mouse_get_position`, which
## Wayland lets no capture write, so the scenario reads the lead through the
## `ring_predict` step and the setting through the page.
extends "res://tests/test_framework.gd"

var _saved_mode: String
var _saved_ms: float


func before_each() -> void:
    _saved_mode = SaSettings.cursor_lead
    _saved_ms = SaSettings.cursor_prediction_ms


func after_each() -> void:
    SaSettings.cursor_lead = _saved_mode
    SaSettings.cursor_prediction_ms = _saved_ms


## The rule as the two Linux drivers read it: under Wayland in the default mode
## Sara draws the pen's pointer and the lead is on, and on X11 the hardware
## cursor is the pointer, so a pen sits on it. The second argument is whether
## Sara draws the pointer, the gate's second question, and the driver is not
## named here at all.
func test_auto_leads_for_a_tablet_where_sara_draws_the_pointer() -> void:
    assert_true(SaCursorPrediction.auto_lead_on(true, true), "a pen under Wayland has no OS cursor, so the ring leads")
    assert_false(SaCursorPrediction.auto_lead_on(false, true), "a mouse under Wayland has the system's pointer")
    assert_false(SaCursorPrediction.auto_lead_on(true, false), "a pen on X11 has the system's pointer")
    assert_false(SaCursorPrediction.auto_lead_on(false, false), "a mouse on X11 has the system's pointer")


## "on" and "off" are the painter's word and consult nothing.
func test_on_and_off_ignore_the_device_and_the_driver() -> void:
    SaSettings.cursor_lead = "on"
    assert_true(SaCursorPrediction.lead_enabled(), "On is on, whatever the driver is")
    SaSettings.cursor_lead = "off"
    assert_false(SaCursorPrediction.lead_enabled(), "Off is off, whatever the driver is")
    SaSettings.cursor_lead = "auto"
    assert_eq(
        SaCursorPrediction.lead_enabled(),
        SaCursorPrediction.auto_lead_on(SaCursorPolicy.pointer_is_tablet, SaCursorPolicy.software_pointer_mode_active()),
        "Auto is the rule read off this machine"
    )


## The setting holds one of the three modes and falls back to Auto for
## anything else, so a hand-edited file cannot switch the ring into a fourth
## state the row has no word for.
func test_the_setting_holds_the_three_modes_and_defaults_to_auto() -> void:
    assert_eq(SaCursorPrediction.LEAD_MODES.size(), 3, "Auto, On and Off")
    assert_eq(String(SaCursorPrediction.LEAD_MODES[0]["id"]), "auto", "Auto is first, being the default")
    SaSettings.cursor_lead = "sideways"
    assert_eq(SaSettings.cursor_lead, "auto", "an unknown word is Auto")
    SaSettings.cursor_lead = "off"
    assert_eq(SaSettings.cursor_lead, "off")


## The weights file is generated, so its shape is asserted against what the
## ring reads of it rather than trusted: one row per horizon, and a row is the
## x weights over the taps and the edges when it reads them, the x bias, the y
## weights and the y bias.
func test_the_weights_file_has_a_row_per_horizon_of_the_right_width() -> void:
    var horizons: Array = SaCursorLeadWeights.HORIZONS_MS
    var rows: Array = SaCursorLeadWeights.WEIGHTS
    assert_true(horizons.size() >= 2, "at least two horizons to interpolate between")
    assert_eq(rows.size(), horizons.size(), "one row per horizon")
    var width := 2 * (2 * SaCursorLeadWeights.TAPS + SaCursorPrediction.row_edges(rows) + 1)
    for i in rows.size():
        assert_eq((rows[i] as Array).size(), width, "row %d is %d numbers" % [i, width])
        if i > 0:
            assert_true(float(horizons[i]) > float(horizons[i - 1]), "horizons ascend")


## A predictor fed a straight sweep at *pixels_per_second* for *seconds*,
## sampled the way a frame loop at sixty hertz would.
func _swept(pixels_per_second: float, seconds: float) -> SaCursorPrediction:
    var prediction := SaCursorPrediction.new()
    var frames := int(seconds * 60.0)
    for i in frames + 1:
        var at := float(i) / 60.0
        prediction.sample(Vector2(pixels_per_second * at, 400.0), int(at * 1_000_000.0))
    return prediction


## On a steady straight sweep the learned lead points the way the hand is
## going and lands near where the pen will be, which the fit also does: the
## learned lead earns its place on corners, and this is the case it may not
## lose. Within a third of the fit's answer either way, and never behind.
func test_the_learned_lead_follows_a_straight_sweep() -> void:
    var prediction := _swept(600.0, 0.5)
    var fit := prediction.lead(0.016)
    var learned := prediction.learned_lead(0.016)
    assert_true(learned.x > 0.0, "leads the way the hand is going")
    assert_almost_eq(learned.y, 0.0, 1.0, "and not sideways")
    assert_true(absf(learned.x - fit.x) < fit.x / 3.0, "near the fit on a straight line: %.2f against %.2f" % [learned.x, fit.x])


## The guards are the fit's: nothing at rest, and never past the cap.
func test_the_learned_lead_keeps_the_rest_and_cap_guards() -> void:
    var still := _swept(5.0, 0.5)
    assert_eq(still.learned_lead(0.016), Vector2.ZERO, "a resting hand sees the ring on the pointer")
    var warp := _swept(50_000.0, 0.5)
    assert_true(warp.learned_lead(0.05).length() <= SaCursorPrediction.MAX_LEAD + 0.001, "a warp is capped")


## The first frames of a gesture hold too little for the taps, and the answer
## is the fit's rather than nothing, so the ring does not jump when the window
## fills.
func test_a_gesture_too_short_for_the_taps_falls_back_to_the_fit() -> void:
    var prediction := SaCursorPrediction.new()
    prediction.sample(Vector2(0.0, 0.0), 1_000_000)
    prediction.sample(Vector2(10.0, 0.0), 1_016_000)
    assert_true(prediction.grid_displacements().is_empty(), "two readings a frame apart do not span the taps")
    assert_eq(prediction.learned_lead(0.016), prediction.lead(0.016), "so the fit answers")


## The horizon is interpolated between the fitted ones and scaled past the
## last, so a 144 hertz screen and a long setting both get a lead that grows
## with the horizon rather than a step at each fitted value.
func test_the_lead_grows_with_the_horizon() -> void:
    var prediction := _swept(600.0, 0.5)
    var short := prediction.learned_lead(0.007)
    var frame := prediction.learned_lead(0.016)
    var long := prediction.learned_lead(0.060)
    assert_true(short.x < frame.x and frame.x < long.x, "%.2f < %.2f < %.2f" % [short.x, frame.x, long.x])


## The Tablet page carries the row, built from the mode list, with the
## setting's value selected.
func test_the_tablet_page_has_the_row() -> void:
    SaSettings.cursor_lead = "off"
    var page := SaTabletPage.new()
    var opt := page.find_child("CursorLeadMode", true, false) as SaChoiceButton
    assert_not_null(opt, "the Cursor lead row is on the Tablet page")
    if opt != null:
        assert_eq(opt.choice_labels().size(), 3, "Auto, On and Off")
        assert_eq(String(opt.selected_value()), "off", "the row shows the setting")
        assert_true(page.lead_report().contains("'off'"), "and the capture report names it")
    page.free()
