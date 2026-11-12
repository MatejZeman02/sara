## An impasto stroke pushes the old height ahead of it: the surface it crosses
## is picked up under one stretch and laid down ahead along the motion before
## the brush's own height is mixed in.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A ridge is painted, and the same brush is dragged across it. The strip of
## one radius past the ridge's far side stands higher after the drag than
## before it, and higher than the same drag leaves over no ridge, so what is
## there is the ridge's height moved and not the drag's own. The strip of one
## radius before the near side stands as the drag leaves it over no ridge,
## since the push goes with the motion and never against it, and dragged the
## other way the two strips change places. A square tip, whose stretches paint
## a trail of the path again, pushes the same way. Every surface is read off
## the relief the view sums, so it is what the card holds.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")

const RADIUS := 14.0
## The ridge, a stroke down x = 100 across the drag's path, and the drag, a
## stroke along y = 60 that crosses it and runs on well past it.
const RIDGE_X := 100.0
const RIDGE_FROM := Vector2(RIDGE_X, 10.0)
const RIDGE_TO := Vector2(RIDGE_X, 110.0)
const DRAG_FROM := Vector2(20.0, 60.0)
const DRAG_TO := Vector2(200.0, 60.0)
## The strips of one radius either side of the ridge, across the drag's width
## less a texel at each rim: past the far side, which the ridge's own paint
## ends at, and before the near side.
const FAR := Rect2i(int(RIDGE_X + RADIUS) + 1, 47, int(RADIUS), 27)
const NEAR := Rect2i(int(RIDGE_X - RADIUS) - int(RADIUS) - 1, 47, int(RADIUS), 27)
## Virtual millimetres at full, for the ridge and the drag alike.
const THICKNESS := 1.0
## The tip's rectangle shape, `Shape.RECTANGLE` of `sa_brush_tip.gd`.
const RECTANGLE := 1

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null


func before_each() -> void:
    _fresh()


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null


## Dragged left to right across the ridge, the strip past its far side stands
## higher than before the drag and higher than the drag stands over no ridge,
## and the strip before its near side stands as the drag over no ridge leaves
## it.
func test_a_drag_across_a_ridge_lays_its_height_past_the_far_side() -> void:
    _stroke(RIDGE_FROM, RIDGE_TO)
    var before := _summed(FAR)
    _stroke(DRAG_FROM, DRAG_TO)
    var far := _summed(FAR)
    var near := _summed(NEAR)
    _fresh()
    _stroke(DRAG_FROM, DRAG_TO)
    var bare_far := _summed(FAR)
    var bare_near := _summed(NEAR)
    assert_true(far > before, "The strip past the far side holds %.2f after the drag, %.2f before it" % [far, before])
    assert_true(
        far > bare_far * 1.05,
        "and more than the %.2f the same drag lays over no ridge, so the ridge's height moved there, %.2f" % [bare_far, far]
    )
    assert_almost_eq(near, bare_near, 0.01, "The strip before the near side holds what the drag lays over no ridge")


## Dragged right to left, the ridge's height goes the other way: the strip
## past the ridge on the left stands higher than the drag leaves it over no
## ridge, and the strip on the right, which the drag reached first, as the
## drag over no ridge leaves it.
func test_dragged_the_other_way_the_push_goes_the_other_way() -> void:
    _stroke(RIDGE_FROM, RIDGE_TO)
    _stroke(DRAG_TO, DRAG_FROM)
    var left := _summed(NEAR)
    var right := _summed(FAR)
    _fresh()
    _stroke(DRAG_TO, DRAG_FROM)
    var bare_left := _summed(NEAR)
    var bare_right := _summed(FAR)
    assert_true(
        left > bare_left * 1.05, "The strip past the ridge on the left holds %.2f, over no ridge %.2f" % [left, bare_left]
    )
    assert_almost_eq(right, bare_right, 0.01, "and the strip on the right what the drag lays over no ridge")


## A square tip carries a trail of the path behind it, whose texels each
## stretch sees again, and pushes the ridge past its far side
## as the round tip does. The strip before the near side stands as the drag
## leaves it over no ridge, so the stroke picks up none of its own paint where
## it paints the trail again.
func test_a_tip_that_carries_a_trail_pushes_the_ridge_the_same_way() -> void:
    _brush.settings.tip.shape = RECTANGLE
    _stroke(RIDGE_FROM, RIDGE_TO)
    _stroke(DRAG_FROM, DRAG_TO)
    var far := _summed(FAR)
    var near := _summed(NEAR)
    _fresh()
    _brush.settings.tip.shape = RECTANGLE
    _stroke(DRAG_FROM, DRAG_TO)
    var bare_far := _summed(FAR)
    var bare_near := _summed(NEAR)
    assert_true(far > bare_far * 1.05, "The strip past the far side holds %.2f, over no ridge %.2f" % [far, bare_far])
    assert_almost_eq(near, bare_near, 0.01, "and the strip before the near side what the drag lays over no ridge")


## A brush on a fresh document, the noise brush's grain field read for its
## lightness, so the brush's own height varies along the stroke and a ridge
## pushed under it shows where the brush stands lower than the ridge.
func _fresh() -> void:
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface()
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7
    _brush.settings.color = Color(0.2, 0.4, 0.8, 1.0)
    _brush.settings.opacity = 1.0
    _brush.settings.hardness = 1.0
    # No shift, so a full press paints every texel the tip reaches at full
    # alpha.
    _brush.settings.strength = 0.0
    _brush.settings.strength_option.enabled = false
    _brush.settings.radius = RADIUS / 256.0
    _brush.settings.texture_field = "grain"
    _brush.settings.texture_channels = 2
    _brush.settings.texture_relief = 1.0
    _brush.settings.thickness = THICKNESS


## A stroke from *from* to *to* at full pressure, sample by sample a few pixels
## apart, as a pen would lay it.
func _stroke(from: Vector2, to: Vector2) -> void:
    _brush.begin_stroke(from, 1.0)
    var steps := ceili(from.distance_to(to) / 4.0)
    for i in range(1, steps + 1):
        _brush.add_sample(from.lerp(to, float(i) / steps), 1.0)
    _brush.end_stroke()


## The surface the view sums over *rect*, added up texel by texel, in virtual
## millimetres, read off the relief after a full composite.
func _summed(rect: Rect2i) -> float:
    var easel := _surface.easel
    easel.request_full_composite()
    easel.process_pending_composite()
    var heights := easel.relief.heights
    if heights == null:
        return 0.0
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(heights.rid, 0)
    var sum := 0.0
    for y in rect.size.y:
        for x in rect.size.x:
            var at := rect.position + Vector2i(x, y)
            sum += bytes.decode_half((at.y * heights.size.x + at.x) * 2)
    return sum
