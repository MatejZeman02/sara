## A ribbon pen that is lifted leaves no dab cut in half.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Ribbon Pen's radius follows the pressure. A sample less than a step past the
## newest point the stroke took is held back, and one that pressed harder was
## written onto that point, so a pen that pressed harder as it lifted grew the
## stroke's last point to the lift's size: the body behind it at the light
## press, the end at the hard one, and a cut across between them where the
## body's last update stopped. Now only the press takes a harder press at its
## spot, and a point held back is drawn at the newest taken point's size, in
## the front and when the lift takes it.
##
## **Lifted harder.** A stroke runs at 0.3 a pixel a sample over several steps
## and its last sample, a pixel on, is at 0.9. Nothing it paints lies farther
## from that last sample than the body's radius and a texel, and its painted
## width there is within a tenth of its width a step back.
##
## **Lifted lighter.** The same with the last sample at 0.05, which drew a
## small end on a large body before.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

const CANVAS := Vector2i(256, 256)
## The preset's radius as a share of the canvas's side, 20.48 pixels at a full
## press, so the body at 0.3 is about seven pixels across each side.
const RADIUS := 0.08
const START := Vector2(40.0, 128.0)
const LENGTH := 60
const BODY := 0.3
const HARD := 0.9
const LIGHT := 0.05
const TEXEL := 1.0
## The share the width at the last dab may differ by from a step back.
const WIDTH_SHARE := 0.1
## The alpha a texel counts as painted from.
const PAINTED := 0.02

var _surface: SaSurface = null


func after_each() -> void:
    Fixtures.teardown(_surface)
    _surface = null


func test_a_stroke_lifted_harder_ends_at_its_body_s_size() -> void:
    _lift_at(HARD)


func test_a_stroke_lifted_lighter_ends_at_its_body_s_size() -> void:
    _lift_at(LIGHT)


## Paints the stroke at [constant BODY] with its last sample at *last*, and
## measures its end against its body.
func _lift_at(last: float) -> void:
    var brush := _fresh_brush()
    var at := START
    brush.begin_stroke(at, BODY)
    for i in LENGTH:
        at.x += 1.0
        brush.add_sample(at, BODY)
    var body: float = brush.dab_list.stretch.newest_radius
    assert_true(body > 2.0, "the body at %.1f is %.2f pixels across each side" % [BODY, body])
    at.x += 1.0
    brush.add_sample(at, last)
    brush.end_stroke()
    var columns := _columns(_document().active_layer)
    var ends := at.x
    var farthest := -1
    for x: int in columns:
        farthest = maxi(farthest, x)
    var beyond := float(farthest) + 0.5 - ends - body
    assert_true(
        beyond <= TEXEL,
        "lifted at %.2f the stroke paints %.2f pixels past its last dab's reach, at most %.1f" % [last, beyond, TEXEL]
    )
    var step := ceilf(sqrt(2.0 * body))
    var here: int = columns.get(int(ends), 0)
    var before: int = columns.get(int(ends - step), 0)
    assert_true(before > 0, "the stroke is painted a step of %.0f pixels back from its end" % step)
    var share := absf(float(here - before)) / maxf(1.0, float(before))
    assert_true(
        share <= WIDTH_SHARE,
        "lifted at %.2f its width at the last dab is %d against %d a step back, a share of %.2f" % [last, here, before, share]
    )


func _fresh_brush() -> StateNoiseBrushScript:
    _surface = Fixtures.make_surface(CANVAS)
    var brush := StateNoiseBrushScript.new()
    brush.surface = _surface
    brush.stroke_seed = 7
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == "Ribbon Pen":
            brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
    brush.settings.radius = RADIUS
    brush.settings.color = Color(0.0, 0.0, 0.0, 1.0)
    return brush


func _document() -> SaDocument:
    return _surface.easel.document


## The painted width of each column of *layer*, from its highest painted texel
## to its lowest, by the column's x in pixels.
func _columns(layer: SaLayer) -> Dictionary[int, int]:
    var low: Dictionary[int, int] = {}
    var high: Dictionary[int, int] = {}
    for grid: Vector2i in layer.chunks:
        var side := (layer.chunks[grid] as SaChunk).pixel_size()
        @warning_ignore("static_called_on_instance")
        var image := SaExport.get_texture_image_float(layer.get_field(grid))
        for y in side:
            for x in side:
                if image.get_pixel(x, y).a <= PAINTED:
                    continue
                var at := grid * side + Vector2i(x, y)
                low[at.x] = mini(low.get(at.x, at.y), at.y)
                high[at.x] = maxi(high.get(at.x, at.y), at.y)
    var out: Dictionary[int, int] = {}
    for x: int in low:
        out[x] = high[x] - low[x] + 1
    return out
