## A stroke under a size curve that reads zero at
## full pressure lays no dab, in the stamp brush and the noise brush alike.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The brush editor suite held this case as a walk of `SaStrokeDistance` alone,
## which counts every offer as a dab and cannot see the engines' guard, so it
## asserted through a helper that stayed green while the count was over its
## ceiling. The guard is a floor on the dab, `MIN_DAB_DIAMETER` in each engine,
## and it lives after the walk, in the stamp's `_dispatch_brush` and the noise
## brush's `_answer`. These strokes go through those, on a real surface, so a
## return of the defect turns this red.
##
## The stamp's count is the walk's own `dab_sequence`, which a dab the guard
## drops does not advance. The noise brush walks no dabs, it lays points along
## a stretch, and the guard gives a point under the floor a box of nothing, so
## its count is the points laid with a box. The ordinary stroke of each is the
## same drag with the size option off, and it has to lay over a hundred, so a
## count of nought cannot pass by painting nothing.
##
## The picture on the running app is `scenarios/curve-options.json`, whose
## stroke of 540 pixels at full pressure under the Arch curve read, on
## 2026-10-18, `stroke_walk` `dabs` 0 and `previous_dabs` 0, `brush_dabs` with
## every sampled dab at size 0.0 over a `dab_index` of 749, and `history` at 0
## steps, so the stroke painted nothing and left nothing to undo. Before the
## fix the same stroke read `previous_dabs` 1002 and 1181 GPU dispatches.
## With `MIN_DAB_DIAMETER` set to nought in both engines this suite reads 537
## dabs for the stamp and 274 boxed points of 274 for the noise brush, and
## fails, against 373 and 274 for the ordinary strokes.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")

## Wide enough for the scenario's 540 pixel drag to stay on the canvas, since a
## dab off the canvas is dropped as well and would hide the guard.
const CANVAS := Vector2i(640, 128)
const FROM := Vector2(50.0, 64.0)
const TO := Vector2(590.0, 64.0)
## Pen reports along the drag, one each [constant STEP] pixels.
const STEP := 4.0
## A tip 8 pixels across on the 128 pixel short side.
const RADIUS := 4.0 / 128.0
## The editor's Arch preset, nought at no pressure and at full pressure.
const ARCH := [Vector2(0.0, 0.0), Vector2(0.5, 1.0), Vector2(1.0, 0.0)]
## What the ordinary stroke has to lay before "at most one" means anything.
const ORDINARY := 100


## A noise brush that counts the points it lays with a box. A point under the
## floor is laid with a box of nothing, so it is not counted.
class CountingNoiseBrush:
    extends "res://modules/sara-noise-brush-engine/state_noise_brush.gd"

    var laid: int = 0
    var boxed: int = 0

    func _answer(info: SaStrokeInfo, slide: float, restating: bool) -> void:
        super(info, slide, restating)
        if restating:
            return
        laid += 1
        if _newest.half_extent != Vector2.ZERO:
            boxed += 1


var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


## A size option on the pen's pressure along the Arch curve.
static func _arch() -> SaCurveOption:
    var option := SaCurveOption.create_default()
    option.common_curve = PackedVector2Array(ARCH)
    return option


## The stamp brush's `dab_sequence` over the drag at full pressure, read before
## the lift, since the lift starts the walk afresh.
func _stamp_dabs(zero_size: bool) -> int:
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    var brush: Object = _machine.active_tool
    brush.settings.radius = RADIUS
    if zero_size:
        brush.settings.size_option = _arch()
    else:
        brush.settings.size_option.enabled = false
    _surface.view.mouse_position = FROM
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    brush.handle_input(press)
    var reports := int((TO.x - FROM.x) / STEP)
    for i in range(1, reports + 1):
        var motion := InputEventMouseMotion.new()
        motion.pressure = 1.0
        _surface.view.mouse_position = FROM.lerp(TO, float(i) / float(reports))
        brush.handle_input(motion)
    brush._walk_batch.flush()
    var dabs: int = brush.stroke_distance.dab_sequence
    var lift := InputEventMouseButton.new()
    lift.button_index = MOUSE_BUTTON_LEFT
    lift.pressed = false
    brush.handle_input(lift)
    Fixtures.teardown(null, _machine)
    _machine = null
    return dabs


## The noise brush's points laid with a box, and all its points, over the drag
## at full pressure.
func _noise_points(zero_size: bool) -> Vector2i:
    var brush := CountingNoiseBrush.new()
    brush.surface = _surface
    brush.stroke_seed = 7
    brush.settings.radius = RADIUS
    if zero_size:
        brush.settings.size_option = _arch()
    else:
        brush.settings.size_option.enabled = false
    var reports := int((TO.x - FROM.x) / STEP)
    brush.begin_stroke(FROM, 1.0)
    for i in range(1, reports + 1):
        brush.add_sample(FROM.lerp(TO, float(i) / float(reports)), 1.0)
    brush.end_stroke()
    return Vector2i(brush.boxed, brush.laid)


func test_the_stamp_brush_lays_no_dab_under_a_zero_size_curve() -> void:
    var ordinary := _stamp_dabs(false)
    assert_true(ordinary > ORDINARY, "540 pixels of an 8 pixel tip lay %d dabs, over %d" % [ordinary, ORDINARY])
    var zero := _stamp_dabs(true)
    assert_true(zero <= 1, "and under a size curve that reads nought at full pressure they lay %d, at most 1" % zero)


func test_the_noise_brush_lays_no_point_under_a_zero_size_curve() -> void:
    var ordinary := _noise_points(false)
    assert_true(ordinary.x > ORDINARY, "540 pixels of an 8 pixel tip lay %d points with a box, over %d" % [ordinary.x, ORDINARY])
    var zero := _noise_points(true)
    assert_true(zero.y > ORDINARY, "Under a size curve that reads nought the walk still lays %d points" % zero.y)
    assert_true(zero.x <= 1, "and %d of them with a box, at most 1" % zero.x)
