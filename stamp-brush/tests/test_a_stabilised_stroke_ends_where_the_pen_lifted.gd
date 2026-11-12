## A stabilised preset must not drop the end of a fast stroke. The Average lags the pointer by its
## window, and the release laid
## nothing between the last smoothed point and the pen, so Paint and Inked Pen
## ended near 1100 of a stroke to 1160 at 60 events and at 940 with four.
##
## This drives the real walk, the real stabiliser and the real finish of each
## shipped preset, as `test_a_fast_pencil_stroke_is_solid.gd` does, with only
## the GPU dispatch replaced by a note of where each dab went and the step it
## asked for. The release is `_walk_stabilizer_finish` and then
## `_finish_stroke_interpolation`, which is what the release branch of
## `_handle_stroke_state` does before it hands the stroke to the document.
##
## No GPU. The picture is `scenarios/a-stabilised-stroke-ends-where-the-pen-lifted.json`.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## The shipped preset that carries the Average. Paint ships with the
## stabiliser off.
const STABILISED: Array[String] = ["Inked Pen"]
## The stroke under test, in document pixels.
const FROM: float = 560.0
const TO: float = 1160.0
const ROW: float = 300.0
## The note's two rates.
const RATES: Array[int] = [60, 4]


## A brush whose dispatch is a note in an array, the way the fast pencil suite
## records one.
class RecordingBrush:
    extends StateBrushScript

    ## One entry per dab the real dispatch would have drawn: where after the
    ## snap to the grid and the spacing it asked for, in pixels.
    var dabs: Array[Dictionary] = []

    func _dispatch_brush(dab: SaDabParams) -> void:
        var pos := SaDabGeometry.snap_to_pixels(dab.position + dab.scatter, clampf(dab.sharpness, 0.0, 1.0), dab.size)
        var tip: Resource = _tip()
        tip.diameter = SaDabGeometry.drawn_diameter(maxf(0.1, dab.size))
        tip.spacing = settings.spacing
        var step := _step_for(tip, dab)
        var drawn := dab.size >= MIN_DAB_DIAMETER
        stroke_distance.register_dab(pos, step, dab.color.a, SaDabCadence.interval_for(settings), drawn)
        if drawn:
            # One spacing is the longer axis of the step, or a texel on the grid.
            var spacing := 1.0 if step.pixel_grid else maxf(step.distance.x, step.distance.y)
            dabs.append({"at": pos, "step": spacing})


func _brush(preset_name: String) -> RecordingBrush:
    var brush := RecordingBrush.new()
    for entry: Dictionary in SaShippedPresets.entries():
        if String(entry["name"]) == preset_name:
            brush.settings = SaShippedPresets.build(StateBrushScript.BrushSettingsScript, entry)
    assert_not_null(brush.settings, "%s is a shipped recipe the settings script can carry" % preset_name)
    brush.stroke_seed = 30
    return brush


## Strokes FROM to TO in *events* motions after the press, a mouse at full
## pressure, and releases. *finished* false leaves out the stabiliser's finish,
## which is the release as it stood before this row.
func _stroke(brush: RecordingBrush, events: int, finished: bool) -> void:
    var settings := brush.settings
    brush.is_drawing = true
    brush.stabilizer.reset()
    brush.stabilizer.mode = settings.stabilizer_mode
    brush.stabilizer.amount = settings.stabilizer_amount
    brush.stroke_distance.reset()
    brush.dynamics.settings = settings
    brush.dynamics.begin_stroke()
    var start := brush.stabilizer.feed(Vector2(FROM, ROW))
    brush.stroke_info.begin(start, brush.stroke_seed)
    brush.has_last_pos = true
    brush.last_mouse_pos = start
    brush.last_pressure = 1.0
    brush._stamp_brush(start, 1.0)
    for i in range(1, events + 1):
        var at := Vector2(lerpf(FROM, TO, float(i) / float(events)), ROW)
        brush._process_stroke_interpolation(brush.stabilizer.feed(at), 1.0, Vector2.ZERO)
    if finished:
        brush._walk_stabilizer_finish()
    brush._finish_stroke_interpolation()


## The row's promise: Paint and Inked Pen end within one spacing of the release
## point at 60 events and at four, where they stopped near 1100 and at 940.
func test_the_stabilised_presets_end_where_the_pen_lifted() -> void:
    for preset_name in STABILISED:
        for events in RATES:
            var brush := _brush(preset_name)
            assert_true(brush.settings.stabilizer_mode != 0, "%s carries a stabiliser" % preset_name)
            _stroke(brush, events, true)
            var last: Dictionary = brush.dabs[-1]
            var short := TO - Vector2(last["at"]).x
            var ends := Vector2(last["at"]).x
            var said := "%s at %d events ends at %.1f, step %.2f" % [preset_name, events, ends, float(last["step"])]
            assert_true(absf(short) <= float(last["step"]), "%s, within one spacing of %d" % [said, int(TO)])


## The same strokes without the finish stop short, which is the note, so the
## promise above cannot pass by measuring nothing.
func test_without_the_finish_they_stop_short() -> void:
    for preset_name in STABILISED:
        for events in RATES:
            var brush := _brush(preset_name)
            _stroke(brush, events, false)
            var last: Dictionary = brush.dabs[-1]
            var short := TO - Vector2(last["at"]).x
            assert_true(short > 4.0 * float(last["step"]), "%s at %d events stops %.1f short" % [preset_name, events, short])


## Pencil carries no stabiliser, so its finish answers nothing and it lays the
## dabs the release laid before this row, one for one, at both rates.
func test_pencil_lays_the_dabs_it_always_laid() -> void:
    for events in RATES:
        var before := _brush("Pencil")
        assert_eq(before.settings.stabilizer_mode, 0, "Pencil carries no stabiliser")
        _stroke(before, events, false)
        var after := _brush("Pencil")
        _stroke(after, events, true)
        assert_true(after.dabs.size() > events, "Pencil at %d events lays dabs between its events" % events)
        assert_eq(after.dabs.size(), before.dabs.size(), "Pencil at %d events lays as many dabs" % events)
        var same := after.dabs.size() == before.dabs.size()
        for i in mini(after.dabs.size(), before.dabs.size()):
            same = same and Vector2(after.dabs[i]["at"]) == Vector2(before.dabs[i]["at"])
        assert_true(same, "Pencil at %d events lays every dab where it did" % events)
