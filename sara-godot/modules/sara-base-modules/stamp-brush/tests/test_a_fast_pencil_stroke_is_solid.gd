## The Windows sweep's fast stroke: 520 pixels in 30 events, for the four thin
## presets it saw break into dashes.
##
## The cause was the capture and not the brush. On Windows the harness warped
## the system pointer before every motion it injected, and the display server
## answered each warp with a mouse motion of its own at the same point and zero
## pressure. The brush read that as the pen lifting between every two events, so
## each segment ramped up from nothing and the line came out as dashes the
## length of the gap between events. Wayland refuses the warp, so the same
## scenario was solid on Linux.
##
## This drives the real walk, the real stabiliser and the real dynamics of each
## shipped preset, with only the GPU dispatch replaced by a note of what it would
## have painted and the step the real dispatch registers. A gap is two dabs in a
## row whose discs do not touch, or, for a tip small enough to paint one whole
## texel, two texels in a row that are not neighbours. A faint dab is one at
## under half the stroke's strongest opacity. The first test is the row's promise. The second
## feeds the answered warps and proves the count sees the fault the sweep filed,
## so the first cannot pass by measuring nothing.
##
## No GPU. The picture is `scenarios/a-fast-pencil-stroke-is-solid.json`.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## The four presets the sweep saw dashed.
const PRESETS: Array[String] = ["Pencil", "Grainy Pencil", "Sketch", "Inked Pen"]
## The sweep's stroke, in document pixels.
const LENGTH: float = 520.0
const SPARSE_EVENTS: int = 30
## The same stroke as the sweep's dense row, which was solid on Windows too.
const DENSE_EVENTS: int = 120
## The sweep's pressure.
const PRESSURE: float = 0.75


## A brush whose dispatch is a note in an array.
##
## `_dispatch_brush` is replaced rather than extended, which is the point here as
## it is in `test_fan_corners.gd`: everything it does past sizing the tip is
## GPU work. What it tells the walk, `register_dab` with the step this dab asked
## for, is done exactly as the real one does it, including the quiet skip of a
## dab too small to draw.
class RecordingBrush:
    extends StateBrushScript

    ## One entry per dab the real dispatch would have drawn: where after the
    ## snap to the grid, how wide, whether it is one whole texel, and how opaque.
    var dabs: Array[Dictionary] = []

    func _dispatch_brush(dab: SaDabParams) -> void:
        var pos := SaDabGeometry.snap_to_pixels(dab.position + dab.scatter, clampf(dab.sharpness, 0.0, 1.0), dab.size)
        var tip: Resource = _tip()
        tip.diameter = SaDabGeometry.drawn_diameter(maxf(0.1, dab.size))
        tip.spacing = settings.spacing
        var drawn := dab.size >= MIN_DAB_DIAMETER
        stroke_distance.register_dab(pos, _step_for(tip, dab), dab.color.a, SaDabCadence.interval_for(settings), drawn)
        if drawn:
            (
                dabs
                . append(
                    {
                        "at": pos,
                        "diameter": float(tip.diameter),
                        "texel": SaDabGeometry.is_pixel_mode(dab.size),
                        "alpha": dab.color.a,
                    }
                )
            )


## A brush holding the shipped recipe *preset_name*, with no document, so the
## radius falls back to the 1080 pixel short side `_base_radius` assumes.
func _brush(preset_name: String) -> RecordingBrush:
    var brush := RecordingBrush.new()
    for entry: Dictionary in SaShippedPresets.entries():
        if String(entry["name"]) == preset_name:
            brush.settings = SaShippedPresets.build(StateBrushScript.BrushSettingsScript, entry)
    assert_not_null(brush.settings, "%s is a shipped recipe the settings script can carry" % preset_name)
    brush.stroke_seed = 15
    return brush


## Paints the sweep's stroke with *events* motions after the press. *answered*
## follows every motion with the display server's answer to a warp, a motion to
## the same point at zero pressure, which is what the capture sent on Windows.
##
## The press and each motion go through what `_handle_stroke_state` and
## `_handle_stroke_motion` do with them, the stabiliser included, without the
## document those two open a stroke on.
func _paint(brush: RecordingBrush, events: int, answered: bool) -> void:
    var settings := brush.settings
    brush.is_drawing = true
    brush.stabilizer.reset()
    brush.stabilizer.mode = settings.stabilizer_mode
    brush.stabilizer.amount = settings.stabilizer_amount
    brush.stroke_distance.reset()
    brush.dynamics.settings = settings
    brush.dynamics.begin_stroke()
    var start := brush.stabilizer.feed(Vector2.ZERO)
    brush.stroke_info.begin(start, brush.stroke_seed)
    brush.has_last_pos = true
    brush.last_mouse_pos = start
    brush.last_pressure = PRESSURE
    brush._stamp_brush(start, PRESSURE)
    for i in range(1, events + 1):
        var at := Vector2(LENGTH * float(i) / float(events), 0.0)
        brush._process_stroke_interpolation(brush.stabilizer.feed(at), PRESSURE, Vector2.ZERO)
        if answered:
            brush._process_stroke_interpolation(brush.stabilizer.feed(at), 0.0, Vector2.ZERO)


## How many times two dabs in a row fail to touch, and how many dabs are under
## half the strongest one's opacity.
static func _breaks(dabs: Array[Dictionary]) -> Dictionary:
    var gaps := 0
    var widest := 0.0
    var strongest := 0.0
    for dab: Dictionary in dabs:
        strongest = maxf(strongest, float(dab["alpha"]))
    var faint := 0
    for i in dabs.size():
        if float(dabs[i]["alpha"]) < 0.5 * strongest:
            faint += 1
        if i == 0:
            continue
        var step := Vector2(dabs[i]["at"]) - Vector2(dabs[i - 1]["at"])
        var apart := step.length()
        var reach := 0.5 * (float(dabs[i]["diameter"]) + float(dabs[i - 1]["diameter"]))
        # The pixel mode paints the one texel the snapped centre is in, however
        # small the disc, so two of them touch when their texels are neighbours.
        if bool(dabs[i]["texel"]) and bool(dabs[i - 1]["texel"]):
            apart = maxf(absf(step.x), absf(step.y))
            reach = 1.0
        if apart > reach + 0.001:
            gaps += 1
            widest = maxf(widest, apart - reach)
    return {"gaps": gaps, "widest": widest, "faint": faint, "dabs": dabs.size()}


## The row's promise: 30 events of pen input make a solid line with every one
## of the four, and so do 120.
##
## Pencil's tip is under three pixels at this pressure, so it paints one texel
## a dab, and before this row it left a one-texel hole in a third of its
## segments at either density. That was the walk's anchor and not the capture,
## and [method SaStrokeDistance._next_point_pixel] says why.
func test_the_sweeps_fast_stroke_is_solid_for_all_four() -> void:
    for preset_name in PRESETS:
        for events: int in [SPARSE_EVENTS, DENSE_EVENTS]:
            var brush := _brush(preset_name)
            _paint(brush, events, false)
            var found := _breaks(brush.dabs)
            var said := "%s, 520 px in %d events, %s" % [preset_name, events, found]
            assert_true(int(found["dabs"]) > events, "%s lays dabs between its events" % said)
            assert_eq(int(found["gaps"]), 0, "%s leaves no gap" % said)
            assert_eq(int(found["faint"]), 0, "%s has no faint stretch either" % said)


## The sweep's dashes, made the way the capture made them on Windows. Every
## preset breaks, which is what says the count above looks at the right thing.
func test_an_answered_warp_after_every_event_breaks_the_line() -> void:
    for preset_name in PRESETS:
        var brush := _brush(preset_name)
        _paint(brush, SPARSE_EVENTS, true)
        var found := _breaks(brush.dabs)
        assert_true(
            2 * (int(found["gaps"]) + int(found["faint"])) >= SPARSE_EVENTS,
            "%s breaks up under a zero-pressure motion after every event, %s" % [preset_name, found]
        )
