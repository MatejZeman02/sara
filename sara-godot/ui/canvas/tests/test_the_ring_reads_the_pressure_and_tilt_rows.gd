## The ring reads the pressure and tilt rows when the weights
## carry them.
##
## A weights file fitted with pressure and tilt is worth nothing until
## `learned_lead` feeds them, and a file without them has to give the ring it
## gives today. The files read here are what `scripts/train_cursor_lead.py`
## wrote over synthetic strokes, kept under [constant FIXTURES]:
## `pressure_weights.txt` is `main` over the 60 strokes whose speed follows the
## pressure, `PRESSED` in `scripts/test_the_training_script_fits_the_lead_with_pressure_and_tilt.py`,
## and `tilt_weights.txt` over its `leaning_stroke` of the seeds 0 to 59, each
## written through that suite's `write_recording` as one recording. The script
## writes both again byte for byte. `weights_before_the_change.txt` is a shipped
## file from before the inputs existed, which names none.
##
## A fixture is the file as the script writes it, `class_name` and all, so it is
## compiled here under no global name rather than loaded, which would make it a
## second `SaCursorLeadWeights`, and it is named `.txt` so the editor never
## takes it for a script of the project.
extends "res://tests/test_framework.gd"

const FIXTURES := "res://tests/fixtures/cursor-lead-weights/"

## The horizons today's lead was read at, in milliseconds: every fitted one,
## one between each pair, and one past the last.
const TODAY_MS: Array[float] = [8.0, 12.0, 16.0, 25.0, 33.0, 50.0, 60.0]

## The lead at each of [constant TODAY_MS] for [method _arc] under the shipped
## weights, read from the version of `learned_lead` that
## read no pressure and no tilt.
const TODAY_LEAD: Array[Vector2] = [
    Vector2(3.811880350, 3.194902420),
    Vector2(5.605290890, 4.648296356),
    Vector2(7.398701191, 6.101689816),
    Vector2(10.272781372, 8.276913643),
    Vector2(12.827519417, 10.210446358),
    Vector2(15.860328674, 11.765820503),
    Vector2(19.032394409, 14.118985176),
]

## The pressures and tilts one motion is fed at, light and heavy, and leaning
## left and right.
const LIGHT := 0.2
const HEAVY := 0.9
const LEFT := Vector2(-0.6, 0.1)
const RIGHT := Vector2(0.6, 0.1)


## The constants of the weights file *file_name* under [constant FIXTURES].
func _weights(file_name: String) -> Dictionary:
    var script := GDScript.new()
    var text := FileAccess.get_file_as_string(FIXTURES + file_name)
    script.source_code = text.replace("class_name SaCursorLeadWeights\n", "")
    assert_eq(script.reload(), OK, "%s compiles" % file_name)
    return script.get_script_constant_map()


## A predictor applying *rows* that read *inputs*, its pen at *pressure* and
## leaning *tilt*, fed one arc of radius 300 at 700 pixels a second for 0.3
## seconds, sampled the way a frame loop at sixty hertz would.
func _arc(rows: Array, inputs: Array, pressure: float, tilt: Vector2) -> SaCursorPrediction:
    var prediction := SaCursorPrediction.new(rows, inputs)
    var pen := InputEventMouseMotion.new()
    pen.pressure = pressure
    pen.tilt = tilt
    prediction.note_pen(pen)
    for i in 19:
        var at := float(i) / 60.0
        var angle := 700.0 * at / 300.0
        var point := Vector2(600.0, 400.0) + Vector2(sin(angle), 1.0 - cos(angle)) * 300.0
        prediction.sample(point, int(at * 1_000_000.0) + 1_000_000)
    return prediction


## How many columns *input* takes in a row, as the script lays them out.
func _width(input: String) -> int:
    var taps := 2 * SaCursorLeadWeights.TAPS
    return {"displacements": taps, "edges": SaCursorPrediction.EDGE_COUNT, "pressure": 1 + taps, "tilt": 2}[input]


## What the pressure's columns read at *pressure* over the displacements
## *steps*: the pressure, then it times each displacement number.
func _pressed(pressure: float, steps: PackedFloat32Array) -> PackedFloat32Array:
    var out := PackedFloat32Array([pressure])
    for step: float in steps:
        out.append(pressure * step)
    return out


## What the columns of *name* in *row* add for *values*, the numbers those
## columns read, worked out here rather than through the predictor: the x
## weights stand first and the y weights after the x bias.
func _terms(row: Array, inputs: Array, name: String, values: PackedFloat32Array) -> Vector2:
    var start := 0
    for input: String in inputs:
        if input == name:
            break
        start += _width(input)
    var width := int(row.size() / 2.0) - 1
    var out := Vector2.ZERO
    for i in values.size():
        out.x += float(row[start + i]) * values[i]
        out.y += float(row[width + 1 + start + i]) * values[i]
    return out


## What the columns of *name* add at *horizon_ms*, interpolated between the two
## fitted horizons around it as the ring interpolates whole rows.
func _terms_at(weights: Dictionary, name: String, values: PackedFloat32Array, horizon_ms: float) -> Vector2:
    var horizons: Array = weights["HORIZONS_MS"]
    var rows: Array = weights["WEIGHTS"]
    var inputs: Array = weights["INPUTS"]
    var upper := 1
    while float(horizons[upper]) < horizon_ms:
        upper += 1
    var t := (horizon_ms - float(horizons[upper - 1])) / (float(horizons[upper]) - float(horizons[upper - 1]))
    return _terms(rows[upper - 1], inputs, name, values).lerp(_terms(rows[upper], inputs, name, values), t)


## The fixtures were written with the grid and the horizons the ring reads off
## the shipped file, which is what lets a suite hand the predictor their rows.
func test_the_fixtures_share_the_shipped_grid_and_horizons() -> void:
    for file_name: String in ["pressure_weights.txt", "tilt_weights.txt", "weights_before_the_change.txt"]:
        var weights := _weights(file_name)
        assert_eq(int(weights["TAPS"]), SaCursorLeadWeights.TAPS, "%s: the taps" % file_name)
        assert_eq(float(weights["GRID_HZ"]), SaCursorLeadWeights.GRID_HZ, "%s: the grid" % file_name)
        assert_eq(weights["HORIZONS_MS"], SaCursorLeadWeights.HORIZONS_MS, "%s: the horizons" % file_name)
    assert_eq(_weights("pressure_weights.txt")["INPUTS"], ["displacements", "edges", "pressure"])
    assert_eq(_weights("tilt_weights.txt")["INPUTS"], ["displacements", "edges", "tilt"])
    assert_false(_weights("weights_before_the_change.txt").has("INPUTS"), "the file from before the inputs names none")


## One motion at a light and at a heavy pressure, and the
## two leads differ by what the pressure's columns give for the pressure and
## the pressure times each displacement, at a fitted horizon and between two.
func test_a_light_and_a_heavy_pressure_lead_apart_by_the_pressure_terms() -> void:
    var weights := _weights("pressure_weights.txt")
    var light := _arc(weights["WEIGHTS"], weights["INPUTS"], LIGHT, Vector2.ZERO)
    var heavy := _arc(weights["WEIGHTS"], weights["INPUTS"], HEAVY, Vector2.ZERO)
    var steps := light.grid_displacements()
    assert_eq(steps, heavy.grid_displacements(), "the two motions are one motion")
    assert_eq(SaCursorPrediction.lead_fraction(light.speed()), 1.0, "fast enough for the whole lead")
    for horizon_ms: float in [16.0, 25.0]:
        var gap := heavy.learned_lead(horizon_ms / 1000.0) - light.learned_lead(horizon_ms / 1000.0)
        var light_terms := _terms_at(weights, "pressure", _pressed(LIGHT, steps), horizon_ms)
        var heavy_terms := _terms_at(weights, "pressure", _pressed(HEAVY, steps), horizon_ms)
        var expected := heavy_terms - light_terms
        assert_true(expected.length() > 0.5, "%.0f ms: the terms move the ring by %.2f pixels" % [horizon_ms, expected.length()])
        assert_almost_eq(gap.x, expected.x, 0.001, "%.0f ms across: %.4f against %.4f" % [horizon_ms, gap.x, expected.x])
        assert_almost_eq(gap.y, expected.y, 0.001, "%.0f ms down: %.4f against %.4f" % [horizon_ms, gap.y, expected.y])


## A hand that settles towards the speed its pressure sets, as the synthetic strokes do,
## is about to slow down when it is pressing lightly and moving fast: the light
## pressure's lead is the shorter of the two.
func test_the_lighter_pressure_leads_less_on_a_fast_arc() -> void:
    var weights := _weights("pressure_weights.txt")
    var light := _arc(weights["WEIGHTS"], weights["INPUTS"], LIGHT, Vector2.ZERO).learned_lead(0.016)
    var heavy := _arc(weights["WEIGHTS"], weights["INPUTS"], HEAVY, Vector2.ZERO).learned_lead(0.016)
    assert_true(light.length() < heavy.length(), "%.2f against %.2f pixels" % [light.length(), heavy.length()])


## The tilt's two columns, across and down, read the pen's lean the same way:
## one motion leaning left and leaning right leads apart by what they give.
func test_a_lean_left_and_right_lead_apart_by_the_tilt_terms() -> void:
    var weights := _weights("tilt_weights.txt")
    var left := _arc(weights["WEIGHTS"], weights["INPUTS"], 0.5, LEFT)
    var right := _arc(weights["WEIGHTS"], weights["INPUTS"], 0.5, RIGHT)
    for horizon_ms: float in [16.0, 25.0]:
        var gap := right.learned_lead(horizon_ms / 1000.0) - left.learned_lead(horizon_ms / 1000.0)
        var expected := _terms_at(weights, "tilt", PackedFloat32Array([RIGHT.x - LEFT.x, RIGHT.y - LEFT.y]), horizon_ms)
        assert_true(expected.length() > 0.5, "%.0f ms: the terms move the ring by %.2f pixels" % [horizon_ms, expected.length()])
        assert_almost_eq(gap.x, expected.x, 0.001, "%.0f ms across: %.4f against %.4f" % [horizon_ms, gap.x, expected.x])
        assert_almost_eq(gap.y, expected.y, 0.001, "%.0f ms down: %.4f against %.4f" % [horizon_ms, gap.y, expected.y])


## The shipped weights fed the same motion lead as they did before the inputs
## existed, to a thousandth of a pixel, whatever the pen presses or leans.
## Once the shipped file is fitted again the claim is read off the copy of the
## rows the numbers were measured on instead.
func test_the_shipped_weights_lead_as_today() -> void:
    if SaCursorLeadWeights.WEIGHTS != _weights("weights_before_the_change.txt")["WEIGHTS"]:
        skip("the shipped weights were fitted again, so today's lead is read off the copy of the rows it was measured on")
        return
    for pen: Array in [[LIGHT, Vector2.ZERO], [HEAVY, Vector2.ZERO], [0.5, LEFT], [0.5, RIGHT]]:
        var prediction := _arc(SaCursorLeadWeights.WEIGHTS, SaCursorLeadWeights.INPUTS, float(pen[0]), pen[1] as Vector2)
        for i in TODAY_MS.size():
            var lead := prediction.learned_lead(TODAY_MS[i] / 1000.0)
            var label := "pressure %.1f, tilt %s, %.0f ms" % [float(pen[0]), pen[1] as Vector2, TODAY_MS[i]]
            assert_almost_eq(lead.x, TODAY_LEAD[i].x, 0.001, label + " across")
            assert_almost_eq(lead.y, TODAY_LEAD[i].y, 0.001, label + " down")


## A file that names no inputs reads as its width says, which for the rows
## shipped before the inputs existed is the displacements alone, and leads as it did then.
func test_a_file_that_names_no_inputs_leads_as_before_q2() -> void:
    var rows: Array = _weights("weights_before_the_change.txt")["WEIGHTS"]
    assert_eq(SaCursorPrediction.row_inputs(rows), ["displacements"])
    for pen: Array in [[LIGHT, Vector2.ZERO], [HEAVY, LEFT]]:
        var prediction := _arc(rows, [], float(pen[0]), pen[1] as Vector2)
        for i in TODAY_MS.size():
            var lead := prediction.learned_lead(TODAY_MS[i] / 1000.0)
            assert_almost_eq(lead.x, TODAY_LEAD[i].x, 0.001, "%.0f ms across" % TODAY_MS[i])
            assert_almost_eq(lead.y, TODAY_LEAD[i].y, 0.001, "%.0f ms down" % TODAY_MS[i])


## The shipped file now names its inputs, and what it names is what its width
## said before it named them.
func test_the_shipped_file_names_what_its_width_says() -> void:
    assert_eq(
        SaCursorPrediction.row_inputs(SaCursorLeadWeights.WEIGHTS, SaCursorLeadWeights.INPUTS),
        SaCursorPrediction.row_inputs(SaCursorLeadWeights.WEIGHTS)
    )


## A file naming an input this code cannot build is the fit's answer rather
## than its rows applied to numbers they were not fitted on.
func test_an_input_the_ring_cannot_build_is_the_fits_answer() -> void:
    var weights := _weights("pressure_weights.txt")
    var prediction := _arc(weights["WEIGHTS"], ["displacements", "edges", "speed"], HEAVY, Vector2.ZERO)
    assert_eq(prediction.learned_lead(0.016), prediction.lead(0.016))
