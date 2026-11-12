## A noise stroke that turns sharply paints a half width past the turn.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A round tip drawn through a point paints a half width round it, whatever
## way the path leaves it. The noise brush draws a turn round an arc, whose
## outer edge alone stops short of the joint by the arc's distance from it,
## more the sharper the turn and nothing at all at the mitre a turn past the
## sharpest arc keeps, so a hairpin's point would go blunt and two zigzags a
## few degrees apart would look different. The arc carries a spur out to the
## pen's turning point and back at its middle, so the turn's outside is the
## round tip's outline there.
##
## **How far.** The noise brush at its default settings strokes along a level
## leg, a sample every [constant SPACING] pixels, through a joint and turns by
## an angle. The layer is read along the outer bisector from the joint, and
## the reach is the farthest point read there whose texel is at least
## [constant PAINTED] covered. At 90, 120, 150 and 165 degrees the texel a half
## width less one pixel past the joint is painted, and the reach at 165 degrees
## and at 175, past the sharpest arc, lie within a pixel of each other.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")

## The joint, the gap between two samples and how many each leg takes.
const JOINT := Vector2(150.0, 128.0)
const SPACING := 8.0
const FIRST_LEG := 12
const SECOND_LEG := 8
## The gap between two samples in milliseconds, so the pen's speed, and with
## it the stroke, is the same at every run.
const SAMPLE_MS := 8.0
## The stroke's seed, so the grain at the tip's rim is the same at every run.
const SEED := 7
## The share of the ground a texel's paint covers to count as painted, and the
## step the bisector is read at.
const PAINTED := 0.5
const READ_STEP := 0.25

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = SEED
    _brush.settings.color = Color.BLACK


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null


func test_a_turn_paints_the_texel_a_half_width_less_a_pixel_past_the_joint() -> void:
    var radius := _brush.get_cursor_radius()
    for turn: float in [90.0, 120.0, 150.0, 165.0]:
        var image := _stroke(turn)
        var at := JOINT + _outward(turn) * (radius - 1.0)
        assert_true(
            _mark(image, at) >= PAINTED,
            (
                "A turn of %d degrees paints %.2f pixels past the joint, a half width of %.2f less one, covered %.2f"
                % [turn, radius - 1.0, radius, _mark(image, at)]
            )
        )


func test_turns_either_side_of_the_sharpest_arc_reach_alike() -> void:
    var radius := _brush.get_cursor_radius()
    var line := "radius %.2f, reach past the joint by turn:" % radius
    for turn: float in [60.0, 90.0, 120.0, 150.0, 165.0, 175.0]:
        line += " %d=%.2f" % [turn, _reach(_stroke(turn), turn)]
    print(line)
    var sharp := _reach(_stroke(165.0), 165.0)
    var sharper := _reach(_stroke(175.0), 175.0)
    assert_true(
        absf(sharp - sharper) <= 1.0,
        "A turn of 165 degrees reaches %.2f pixels past the joint and one of 175 reaches %.2f" % [sharp, sharper]
    )
    assert_true(
        sharp >= radius - 1.0,
        "A turn of 165 degrees reaches %.2f pixels past the joint, near the half width of %.2f" % [sharp, radius]
    )


## The layer after a stroke through the joint turning by *turn* degrees,
## which is then undone.
func _stroke(turn: float) -> Image:
    var into := Vector2.RIGHT
    var away := into.rotated(deg_to_rad(turn))
    var clock := 1000.0
    _brush.begin_stroke(JOINT - into * SPACING * FIRST_LEG, 1.0, Vector2.ZERO, clock)
    for i in range(FIRST_LEG - 1, -1, -1):
        clock += SAMPLE_MS
        _brush.add_sample(JOINT - into * SPACING * i, 1.0, Vector2.ZERO, clock)
    for i in range(1, SECOND_LEG + 1):
        clock += SAMPLE_MS
        _brush.add_sample(JOINT + away * SPACING * i, 1.0, Vector2.ZERO, clock)
    _brush.end_stroke()
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()
    var image := SaExport.get_easel_image_float(_surface.easel)
    _surface.easel.document.undo_redo.undo()
    return image


## The outer bisector of a turn by *turn* degrees, away from the joint.
func _outward(turn: float) -> Vector2:
    var away := Vector2.RIGHT.rotated(deg_to_rad(turn))
    return (Vector2.RIGHT - away).normalized()


## The farthest point along the outer bisector of a turn by *turn* degrees,
## in pixels from the joint, whose texel in *image* is painted.
func _reach(image: Image, turn: float) -> float:
    var reach := 0.0
    for step in 80:
        var distance := READ_STEP * step
        if _mark(image, JOINT + _outward(turn) * distance) >= PAINTED:
            reach = distance
    return reach


## How much of the ground's brightness the paint at *at* in *image* covers.
func _mark(image: Image, at: Vector2) -> float:
    var ground := image.get_pixel(250, 250).r
    var p := Vector2i(at.round())
    if p.x < 0 or p.y < 0 or p.x >= image.get_width() or p.y >= image.get_height():
        return 0.0
    return (ground - image.get_pixelv(p).r) / maxf(ground, 1e-4)
