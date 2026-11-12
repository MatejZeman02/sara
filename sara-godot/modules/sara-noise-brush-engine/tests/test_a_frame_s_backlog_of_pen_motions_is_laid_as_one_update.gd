## A frame's backlog of pen motions on a noise stroke is laid as one update, at
## most two compute lists, and paints what the same motions laid one a frame
## paint, within a tolerance named here.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The tablet's stutter.** On the tablet a slow frame let two dozen pen
## motions pile up, and the next frame laid each of them as an update of its
## own, about a millisecond apiece with up to 82 compute lists, so that frame
## was slow too. The brush now sweeps every motion as it comes and lays the
## frame's at the frame. The suite plays Wet Into Wet, which smudges and so sends
## its body in the smudge stage's list, with a pen's press held for the first
## motion, its S with the pressure up and back down and a report every 4 ms.
## It folds the frames into `SaStrokeLedger` itself, since a test function
## cannot wait for one, and the frame with 25 motions in it is read off the
## ledger's window figures.
##
## **The paint.** The same motions are laid one a frame on a fresh surface, the
## route before the change, and both layers are read back as floats. A gathered
## update writes one stretch where the motions wrote several and picks the
## smudge's carry up once at its newest point where each motion picked it up at
## its own, so a few texels at the joins take a slightly different share.
## [constant MOVED_SHARE] is the share of painted texels that may move by more
## than [constant NOTICED] in any channel, a step a painter could see on a flat
## colour. Measured on one card it was one texel of 7837, the rim of a hole
## the cut lays a texel later, and every other texel moved by less than the
## step. A chunk the gathered update's larger box reaches and no paint lands in
## reads as empty, as it does on the layer.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")

const CANVAS := Vector2i(768, 384)
## The motions of the stroke, and which of them arrive together in one frame.
const MOTIONS: int = 60
const BACKLOG_FROM: int = 15
const BACKLOG: int = 25
## A pen's report every 4 ms, and the frame a 60 Hz display gives.
const REPORT_MS: float = 4.0
const FRAME_USEC: int = 16667
const INK := Color(0.12, 0.25, 0.6, 1.0)
## The share of painted texels that may move by more than [constant NOTICED]
## in any channel between the two routes, and that step.
const MOVED_SHARE: float = 0.005
const NOTICED: float = 0.02

var _surfaces: Array[SaSurface] = []


func after_each() -> void:
    for surface: SaSurface in _surfaces:
        Fixtures.teardown(surface)
    _surfaces.clear()


## Where the S is at *t*, across the canvas.
static func point_at(t: float) -> Vector2:
    var inset := float(CANVAS.y) * 0.25
    var x := inset + t * (float(CANVAS.x) - 2.0 * inset)
    var y := float(CANVAS.y) * 0.5 - sin(t * TAU) * (float(CANVAS.y) * 0.5 - inset)
    return Vector2(x, y)


static func pressure_at(t: float) -> float:
    return 0.3 + 0.6 * sin(t * PI)


## A Wet Into Wet brush on a fresh surface.
func _brush() -> StateNoiseBrushScript:
    var entry: Dictionary = {}
    for one: Dictionary in NoisePresetsScript.entries():
        if one["name"] == "Wet Into Wet":
            entry = one
    assert_false(entry.is_empty(), "Wet Into Wet ships")
    var surface := Fixtures.make_surface(CANVAS)
    _surfaces.append(surface)
    var brush := StateNoiseBrushScript.new()
    brush.surface = surface
    brush.stroke_seed = 1
    var settings: Resource = NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
    settings.color = INK
    brush.settings = settings
    return brush


## Paints the S on *brush*, the motions from [constant BACKLOG_FROM] for
## [constant BACKLOG] in one frame when *backlog*, every other motion a frame of
## its own, and folds each frame into the ledger. Answers the ledger's window
## figures for the frame the backlog arrived in, or for the last frame without
## one.
func _paint(brush: StateNoiseBrushScript, backlog: bool) -> Dictionary:
    var frame := 1000
    brush.begin_stroke(point_at(0.0), 0.0, Vector2.ZERO, 0.0, true)
    var read: Dictionary = {}
    var i := 1
    while i <= MOTIONS:
        var count := BACKLOG if backlog and i == BACKLOG_FROM else 1
        frame += 1
        SaStrokeLedger.reset()
        for motion in count:
            var t := float(i + motion) / float(MOTIONS)
            SaStrokeLedger.event_arrived(true, frame)
            brush.gather_sample(point_at(t), pressure_at(t), Vector2.ZERO, (i + motion) * REPORT_MS)
        brush.lay_frame()
        SaStrokeLedger.fold_frame(FRAME_USEC, 0, 0, 0, 0)
        if count > 1 or not backlog:
            read = SaStrokeLedger.block()
        i += count
    brush.end_stroke()
    return read


## Every painted chunk of the active layer as a float image, by grid position.
func _layer(brush: StateNoiseBrushScript) -> Dictionary:
    var layer := brush.surface.easel.document.active_layer
    var out := {}
    for grid: Vector2i in layer.chunks:
        out[grid] = SaExport.get_texture_image_float((layer.chunks[grid] as SaChunk).albedo())
    return out


func test_a_backlog_of_twenty_five_motions_is_one_update_of_at_most_two_lists() -> void:
    var figures := _paint(_brush(), true)
    assert_eq(int(figures.get("motions_per_frame_max", 0)), BACKLOG, "the frame took the 25 motions of the backlog")
    var lists := int(figures.get("lists_per_frame_max", -1))
    assert_true(lists >= 1 and lists <= 2, "the frame sent at most two compute lists, %d" % lists)
    assert_true(
        int(figures.get("dabs_per_frame_max", 0)) <= 2,
        "and laid the body and the front once, %d dabs" % int(figures.get("dabs_per_frame_max", 0))
    )


func test_a_motion_a_frame_is_still_at_most_two_lists_a_frame() -> void:
    var figures := _paint(_brush(), false)
    assert_eq(int(figures.get("motions_per_frame_max", 0)), 1, "the last frame took one motion")
    var lists := int(figures.get("lists_per_frame_max", -1))
    assert_true(lists >= 1 and lists <= 2, "and sent at most two compute lists, %d" % lists)


func test_the_backlog_paints_what_the_same_motions_paint_one_a_frame() -> void:
    var gathered_brush := _brush()
    _paint(gathered_brush, true)
    var gathered := _layer(gathered_brush)
    var alone_brush := _brush()
    _paint(alone_brush, false)
    var alone := _layer(alone_brush)
    assert_false(alone.is_empty(), "the stroke painted")
    var grids := alone.keys()
    for grid: Vector2i in gathered:
        if not alone.has(grid):
            grids.append(grid)
    var painted := 0
    var moved := 0
    var largest := 0.0
    for grid: Vector2i in grids:
        var one: Image = alone.get(grid)
        var other: Image = gathered.get(grid)
        var side := (one if one != null else other).get_width()
        for y in side:
            for x in side:
                var a := one.get_pixel(x, y) if one != null else Color(0, 0, 0, 0)
                var b := other.get_pixel(x, y) if other != null else Color(0, 0, 0, 0)
                if a.a <= 0.0 and b.a <= 0.0:
                    continue
                painted += 1
                var step := maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))
                largest = maxf(largest, step)
                if step > NOTICED:
                    moved += 1
    assert_true(painted > 1000, "the stroke painted %d texels" % painted)
    var share := float(moved) / float(maxi(painted, 1))
    assert_true(
        share <= MOVED_SHARE,
        "%.4f of the painted texels moved by more than %.2f, at most %.3f may" % [share, NOTICED, MOVED_SHARE]
    )
    print(
        "Backlog paint: %d texels painted, %d moved by more than %.2f, the largest step %.4f" % [painted, moved, NOTICED, largest]
    )
