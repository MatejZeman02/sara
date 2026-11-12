## Flat Brush's turned tip lies across the stroke at full width
## from its first dab.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A Flat Brush with the rotation on must lay a level stroke as the full
## rectangle, a stroke at 30 to 60 degrees at its full width, and no knob or
## notch at the first point of a slanted one. Two things guard that.
##
## **The width.** The rotation option answers Krita's turn, which is
## anticlockwise on the screen, and the dab kernel draws a positive angle
## clockwise, from the document's x towards its y, which runs down. So a tip
## that follows the stroke turned the other way from it: right at nought and at
## a quarter turn, where the mirror of the heading is the heading again, a sixth
## of a turn off it at 30 and 60 degrees, and lying along the stroke at 45.
## `SaDynamics.evaluate` answers the dab's turn in the kernel's frame.
##
## **The first dab.** Laid at the press, before the stroke has a direction, it
## would stand at the angle of a stroke going right, and the corner
## fan would then sweep from there to the stroke's own heading at the first point.
## The press dab of a tip that turns with the stroke waits for the first
## span the walk is handed and takes that span's heading, `SaStrokeTurn`.
##
## Every stroke is laid through the brush's own `handle_input`, the press, the
## motions and the release, by a mouse and by a pen, since a pen's press waits
## for its first motion and a mouse's does not, and read back off the
## composite. The picture is
## `scenarios/flat-brush-s-turned-tip-lies-across-the-stroke-at-full-width-from-its-first-dab.json`.
extends "res://tests/test_framework.gd"

## Paints and reads back the canvas.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## The canvas, whose short side Flat Brush's radius is a fraction of: a tip
## about 30 pixels long and 6 deep.
const SIDE: int = 512
## How far each stroke runs, and how many motions carry it after the press.
const LENGTH: float = 200.0
const MOTIONS: int = 8
## The angles the row names, in degrees from the document's x towards its y.
const ANGLES: Array[float] = [0.0, 30.0, 45.0, 60.0, 90.0]
## How far a stroke's width may stand from the level stroke's.
const WIDTH_TOLERANCE: float = 0.1
## How far past an edge a texel is read as standing off the stroke rather than
## being its soft edge, in pixels.
const MARGIN: float = 2.0
## The step the coverage is read at, in pixels.
const STEP: float = 0.25

const INK := Color(0.05, 0.1, 0.4, 1.0)
const HOVER_TILT := Vector2(0.2, 0.1)

var _surface: SaSurface = null
## How many dabs the last stroke laid.
var _brush_dabs: int = 0


func after_each() -> void:
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = null


# --- The row's two asks -------------------------------------------------------


## "A suite lays Flat Brush as it ships, rotation on, at 0, 30, 45, 60 and 90
## degrees, and reads each stroke's width across its direction within 10 % of
## the level stroke's", by a mouse and by a pen.
func test_a_turned_stroke_is_as_wide_as_the_level_one_at_every_angle() -> void:
    for pen: bool in [false, true]:
        var hand := "a pen" if pen else "a mouse"
        var level := _width(_stroke(0.0, pen, true), 0.0)
        var long_side := _long_side()
        assert_true(
            absf(level - long_side) <= WIDTH_TOLERANCE * long_side,
            "The level stroke by %s is the tip's long side wide, %.1f of %.1f" % [hand, level, long_side]
        )
        for degrees: float in ANGLES:
            var width := _width(_stroke(degrees, pen, true), degrees)
            assert_true(
                absf(width - level) <= WIDTH_TOLERANCE * level,
                "At %.0f degrees by %s the stroke is %.1f wide, the level one %.1f" % [degrees, hand, width, level]
            )


## "and no knob or notch at its first point": the paint at the first point is
## the turned tip and nothing else, nothing behind it or off either side, and
## no bite out of it.
func test_the_first_point_is_the_tip_turned_like_the_rest() -> void:
    for pen: bool in [false, true]:
        var hand := "a pen" if pen else "a mouse"
        var level := _width(_stroke(0.0, pen, true), 0.0)
        for degrees: float in ANGLES:
            var picture := _stroke(degrees, pen, true)
            var found := _first_point(picture, degrees, level)
            var said := "At %.0f degrees by %s, %s" % [degrees, hand, found]
            assert_eq(int(found["knob"]), 0, "%s, nothing stands off the first point" % said)
            assert_eq(int(found["notch"]), 0, "%s, and nothing is bitten out of it" % said)


## "A stroke with the rotation off still lays its tip at the preset's fixed
## angle." Flat Brush's is nought, its long side along the document's x, so an
## upright stroke is the long side wide and a level one the short side.
func test_with_the_rotation_off_the_tip_keeps_the_presets_angle() -> void:
    var long_side := _long_side()
    var upright := _width(_stroke(90.0, false, false), 90.0)
    var level := _width(_stroke(0.0, false, false), 0.0)
    assert_true(
        absf(upright - long_side) <= WIDTH_TOLERANCE * long_side,
        "With the rotation off an upright stroke is the long side wide, %.1f of %.1f" % [upright, long_side]
    )
    assert_true(level < 0.4 * long_side, "and a level one only the short side, %.1f" % level)


## The fixed angle is read in the kernel's frame, from x towards y, and a tap
## lays one dab standing at it with the rotation off, at Flat Brush's nought and
## at a twelfth of a turn set by hand.
func test_a_tap_with_the_rotation_off_stands_at_the_tips_own_angle() -> void:
    for degrees: float in [0.0, 30.0]:
        var picture := _tap(false, deg_to_rad(degrees))
        var axis := _long_axis_degrees(picture)
        assert_almost_eq(axis, degrees, 1.0, "One dab at a resting angle of %.0f degrees stands at %.2f" % [degrees, axis])


## A tap with the rotation on has no direction to wait for, so it is laid at
## the lift, still one dab, and turned as a stroke going right would turn it,
## which for Flat Brush is its long side upright.
func test_a_tap_with_the_rotation_on_still_lays_its_dab() -> void:
    var picture := _tap(true, 0.0)
    assert_eq(_brush_dabs, 1, "A tap lays its one dab")
    assert_almost_eq(absf(_long_axis_degrees(picture)), 90.0, 1.0, "standing across a level stroke")


## The turn the rotation option answers for a stroke heading along *degrees*,
## without the GPU: the heading plus the preset's quarter turn, in the kernel's
## frame, not the mirror of that.
func test_the_option_answers_the_heading_in_the_kernels_frame() -> void:
    var settings := _recipe()
    var dynamics := SaDynamics.new(settings)
    dynamics.begin_stroke()
    for degrees: float in [10.0, 30.0, 45.0, 60.0, 120.0, -30.0]:
        var info := SaStrokeInfo.new()
        info.begin(Vector2.ZERO, 4242)
        info.hovering = false
        info.feed_dab(Vector2.from_angle(deg_to_rad(degrees)) * 10.0, 1.0, Vector2.ZERO, 0.0, 0.0)
        var turn := dynamics.evaluate(info, 30.0).rotation
        var off := rad_to_deg(angle_difference(deg_to_rad(degrees + 90.0), turn))
        assert_almost_eq(off, 0.0, 1e-3, "A heading of %.0f degrees turns the tip to %.3f" % [degrees, rad_to_deg(turn)])


# --- Painting -----------------------------------------------------------------


## Flat Brush as it ships, in the suite's ink.
func _recipe() -> SaStampBrushSettings:
    for entry: Dictionary in SaShippedPresets.entries():
        if String(entry["name"]) == "Flat Brush":
            var settings := SaShippedPresets.build(StateBrushScript.BrushSettingsScript, entry) as SaStampBrushSettings
            settings.color = INK
            return settings
    assert_true(false, "Flat Brush is a shipped recipe")
    return SaStampBrushSettings.new()


## The tip's long side on this canvas, which is what a stroke laid across is
## wide.
func _long_side() -> float:
    return 2.0 * _recipe().radius * float(SIDE)


## A fresh canvas and a brush on it holding Flat Brush, its rotation on or off,
## told a mouse or a pen is in the hand by the hovers before the press.
func _brush(pen: bool, rotation_on: bool) -> Object:
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(Vector2i(SIDE, SIDE))
    var brush := StateBrushScript.new()
    brush.surface = _surface
    brush.settings = _recipe()
    brush.settings.rotation_option.enabled = rotation_on
    brush.stroke_seed = 20
    for i in 12:
        var hover := InputEventMouseMotion.new()
        hover.tilt = HOVER_TILT if pen else Vector2.ZERO
        _view().mouse_position = Vector2(8 + i, 8)
        brush.handle_input(hover)
    assert_eq(brush.is_tablet, pen, "The brush reads the hand it was given")
    return brush


func _view() -> Fixtures.FakeView:
    return _surface.view as Fixtures.FakeView


## A stroke of `LENGTH` through the canvas's middle heading along *degrees*,
## and the composite it leaves.
func _stroke(degrees: float, pen: bool, rotation_on: bool) -> Image:
    var brush := _brush(pen, rotation_on)
    var heading := Vector2.from_angle(deg_to_rad(degrees))
    var start := _middle() - heading * LENGTH * 0.5
    _view().mouse_position = start
    brush.handle_input(_button(true))
    for i in range(1, MOTIONS + 1):
        var motion := InputEventMouseMotion.new()
        motion.pressure = 1.0
        motion.tilt = HOVER_TILT if pen else Vector2.ZERO
        _view().mouse_position = start + heading * LENGTH * float(i) / float(MOTIONS)
        brush.handle_input(motion)
    brush.handle_input(_button(false))
    _brush_dabs = brush.stroke_info.dab_index
    return _picture()


## A press and a release at the middle, the tip at *radians* when it rests.
func _tap(rotation_on: bool, radians: float) -> Image:
    var brush := _brush(false, rotation_on)
    brush.settings.tip.angle = radians
    _view().mouse_position = _middle()
    brush.handle_input(_button(true))
    brush.handle_input(_button(false))
    _brush_dabs = brush.stroke_info.dab_index
    return _picture()


func _middle() -> Vector2:
    return Vector2(SIDE, SIDE) * 0.5


func _button(pressed: bool) -> InputEventMouseButton:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = pressed
    return button


func _picture() -> Image:
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()
    var image := SaExport.get_easel_image_float(_surface.easel)
    assert_not_null(image, "The canvas reads back")
    return image


# --- Reading ------------------------------------------------------------------


## How much of the ink *image* holds at *at*, nought on the bare canvas and one
## at the stroke's own colour, read between the four texels around it.
func _coverage(image: Image, at: Vector2) -> float:
    var bare := image.get_pixel(0, 0)
    var full := _distance(INK, bare)
    var corner := (at - Vector2(0.5, 0.5)).floor()
    var f := at - Vector2(0.5, 0.5) - corner
    var sum := 0.0
    for dy in 2:
        for dx in 2:
            var x := clampi(int(corner.x) + dx, 0, image.get_width() - 1)
            var y := clampi(int(corner.y) + dy, 0, image.get_height() - 1)
            var weight := (f.x if dx == 1 else 1.0 - f.x) * (f.y if dy == 1 else 1.0 - f.y)
            sum += weight * _distance(image.get_pixel(x, y), bare)
    return clampf(sum / full, 0.0, 1.0)


static func _distance(a: Color, b: Color) -> float:
    return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## The stroke's width across its direction, the coverage summed along the
## normal at three places round its middle and averaged, so a soft edge counts
## for what it covers.
func _width(image: Image, degrees: float) -> float:
    var along := Vector2.from_angle(deg_to_rad(degrees))
    var across := along.orthogonal()
    var reach := _long_side()
    var total := 0.0
    for offset: float in [-12.0, 0.0, 12.0]:
        var centre := _middle() + along * offset
        var v := -reach
        while v <= reach:
            total += _coverage(image, centre + across * v) * STEP
            v += STEP
    return total / 3.0


## The texels round the first point that are not the turned tip: a knob is
## paint behind the first dab or off either side of the stroke, and a notch is
## bare canvas inside the band the stroke covers. Read in the stroke's own
## frame, *u* from the first point along the heading and *v* across it, over a
## stroke's width either way of the first point.
func _first_point(image: Image, degrees: float, width: float) -> Dictionary:
    var along := Vector2.from_angle(deg_to_rad(degrees))
    var across := along.orthogonal()
    var start := _middle() - along * LENGTH * 0.5
    var half := width * 0.5
    var depth: float = half * float(_recipe().tip.ratio)
    var knob := 0
    var notch := 0
    var u := -width
    while u <= width:
        var v := -width
        while v <= width:
            var covered := _coverage(image, start + along * u + across * v) >= 0.5
            var outside := absf(v) >= half + MARGIN or u <= -(depth + MARGIN)
            var inside := absf(v) <= half - MARGIN and u >= 0.0
            if covered and outside:
                knob += 1
            elif not covered and inside:
                notch += 1
            v += 1.0
        u += 1.0
    return {"knob": knob, "notch": notch, "width": width}


## The angle the longer axis of the paint in *image* stands at, in degrees from
## the document's x towards its y, off the second moments of its coverage.
func _long_axis_degrees(image: Image) -> float:
    var reach := int(_long_side())
    var middle := Vector2i(_middle())
    var sum := 0.0
    var mean := Vector2.ZERO
    var points: Array[Vector3] = []
    for y in range(middle.y - reach, middle.y + reach + 1):
        for x in range(middle.x - reach, middle.x + reach + 1):
            var at := Vector2(x + 0.5, y + 0.5)
            var c := _coverage(image, at)
            if c > 0.0:
                points.append(Vector3(at.x, at.y, c))
                sum += c
                mean += at * c
    assert_true(sum > 0.0, "The dab painted")
    if sum <= 0.0:
        return NAN
    mean /= sum
    var xx := 0.0
    var yy := 0.0
    var xy := 0.0
    for p: Vector3 in points:
        var d := Vector2(p.x, p.y) - mean
        xx += p.z * d.x * d.x
        yy += p.z * d.y * d.y
        xy += p.z * d.x * d.y
    return rad_to_deg(0.5 * atan2(2.0 * xy, xx - yy))
