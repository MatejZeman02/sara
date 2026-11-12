## Oil Smudge's dilution and length are on as it ships.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Oil Smudge shipped its dilution at 0.5 and its smear length at 0.75 with
## neither option ticked, so both numbers did nothing: an option that is off
## answers its neutral one, a carry laid in full that never fades. Both are on
## now, and this reads them on as the recipe builds and paints the difference.
## The dilution is Colour Rate, the same mix read from the
## other end, and unticked it reads nought, the same carry laid in full.
##
## Every stroke is laid through the brush's own input, as the smudge's height
## suite lays its own, left to right from a field of paint the first chunk
## holds and on over the bare canvas past it, once with Oil Smudge as it ships
## and once with the two options switched back off. Over the paint the dilution
## mixes the brush's own colour into what it drags, and past the paint's edge
## the length fades what it carried, so each half of the stroke is read on its
## own as well as the whole. The no-strength-on-an-option-off scan over every
## shelf is `tests/` own, `test_no_shipped_preset_sets_a_strength_on_an_option_left_off.gd`.
extends "res://tests/test_framework.gd"

## Paints and reads back the canvas.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## Two chunks across, the first painted and the second bare, whose short side
## Oil Smudge's radius is a fraction of: a dab about fourteen pixels across.
const CANVAS := Vector2i(512, 256)
## The stroke's row, and how far it runs either side of the paint's edge.
const ROW: float = 128.0
const REACH: float = 120.0
const STEPS: int = 60

## The paint the stroke drags, and the brush's own colour, far apart in every
## channel so a mix of the two reads in each.
const GROUND := Color(0.85, 0.15, 0.1, 1.0)
const INK := Color(0.1, 0.2, 0.8, 1.0)

## How far apart the two strokes have to read, as the mean of the largest
## channel difference over the texels either stroke touched. A stroke of the
## same settings twice reads 0.
const APART: float = 0.05
## How far one option alone has to move its half. The length alone moves the
## stroke past the paint by about 0.05, much less than the dilution moves it
## over the paint, because the pickup reads the stroke's own trail behind each
## dab and keeps topping the carry up, so what fades is mostly refilled.
const ALONE: float = 0.02

## Where the paint ends, the first chunk's own side, read off the chunk the
## ground was painted into.
var _side: int = 0
## The canvas as it stands before any stroke, the ground and the bare chunk.
var _bare: Image = null


## The row's first clause, first half: the recipe builds with both on, at the
## strengths its author wrote.
func test_oil_smudge_builds_with_its_dilution_and_length_on() -> void:
    var settings := _oil_smudge()
    assert_true(settings.smudge_pickup_option.enabled, "Its pickup is on, as it always was")
    assert_true(settings.smudge_color_rate_option.enabled, "Its colour rate, once its dilution, is on")
    assert_almost_eq(settings.smudge_color_rate_option.strength, 0.5, 1e-6, "at one less the 0.5 its author wrote")
    assert_true(settings.smudge_length_option.enabled, "Its smear length is on")
    assert_almost_eq(settings.smudge_length_option.strength, 0.75, 1e-6, "at the 0.75 its author wrote")


## The row's first clause, second half: a stroke of Oil Smudge as it ships
## reads different from the same stroke with both off, over the paint and past
## it.
func test_a_stroke_of_it_differs_from_the_same_stroke_with_both_off() -> void:
    var shipped := _stroke(true, true)
    var both_off := _stroke(false, false)
    var edge := _side
    var whole := _apart(shipped, both_off, 0, CANVAS.x)
    var over := _apart(shipped, both_off, 0, edge)
    var past := _apart(shipped, both_off, edge, CANVAS.x)
    assert_true(whole > APART, "The stroke as it ships and with both off read %.3f apart" % whole)
    assert_true(over > APART, "over the paint, %.3f" % over)
    assert_true(past > APART, "and past its edge, %.3f" % past)


## Each option alone moves the half of the stroke it is for: the dilution the
## half over the paint, where the carry is strong, and the length the half
## past it, where only what was carried is left.
func test_each_option_moves_its_own_half() -> void:
    var both_off := _stroke(false, false)
    var edge := _side
    var dilution := _apart(_stroke(true, false), both_off, 0, edge)
    var length := _apart(_stroke(false, true), both_off, edge, CANVAS.x)
    assert_true(dilution > ALONE, "The dilution alone moves the stroke over the paint by %.3f" % dilution)
    assert_true(length > ALONE, "and the length alone moves it past the paint by %.3f" % length)


## A stroke of the same settings twice is the same stroke, so the difference
## above is the options' and not the run's.
func test_the_same_stroke_twice_reads_the_same() -> void:
    var again := _apart(_stroke(true, true), _stroke(true, true), 0, CANVAS.x)
    assert_almost_eq(again, 0.0, 1e-6, "Oil Smudge twice reads %.6f apart" % again)


# --- Painting -----------------------------------------------------------------


## Oil Smudge as the stamp's shelf ships it, in the suite's ink.
func _oil_smudge() -> SaStampBrushSettings:
    for entry: Dictionary in SaShippedPresets.entries():
        if String(entry["name"]) == "Oil Smudge":
            var settings := SaShippedPresets.build(StateBrushScript.BrushSettingsScript, entry) as SaStampBrushSettings
            assert_not_null(settings, "Oil Smudge builds")
            settings.color = INK
            return settings
    assert_true(false, "Oil Smudge is a shipped recipe")
    return SaStampBrushSettings.new()


## A fresh canvas with its first chunk painted, composited, since the pickup
## reads the composite and a composite never drawn is bare canvas to it.
func _ground() -> SaSurface:
    var surface := Fixtures.make_surface(CANVAS)
    var document := surface.get_document()
    var chunk := document.active_layer.get_or_create_chunk(Vector2i.ZERO)
    chunk.clear(GROUND)
    _side = chunk.pixel_size()
    document.invalidate_chunks([Vector2i.ZERO])
    surface.easel.request_full_composite()
    surface.easel.process_pending_composite()
    if _bare == null:
        _bare = SaExport.get_easel_image_float(surface.easel)
    return surface


## One stroke of Oil Smudge through the paint's edge on a fresh canvas, its
## dilution and length on or off, and the composite it leaves.
func _stroke(dilution: bool, length: bool) -> Image:
    var surface := _ground()
    var edge := float(_side)
    var brush := StateBrushScript.new()
    brush.surface = surface
    brush.settings = _oil_smudge()
    brush.settings.smudge_color_rate_option.enabled = dilution
    brush.settings.smudge_length_option.enabled = length
    brush.stroke_seed = 30
    var from := Vector2(edge - REACH, ROW)
    var to := Vector2(edge + REACH, ROW)
    for i in range(STEPS + 1):
        surface.view.mouse_position = from.lerp(to, float(i) / float(STEPS))
        var event: InputEvent
        if i == 0:
            event = _button(true)
        else:
            var motion := InputEventMouseMotion.new()
            motion.button_mask = MOUSE_BUTTON_MASK_LEFT
            motion.pressure = 1.0
            event = motion
        brush.handle_input(event)
    brush.handle_input(_button(false))
    surface.easel.request_full_composite()
    surface.easel.process_pending_composite()
    var image := SaExport.get_easel_image_float(surface.easel)
    assert_not_null(image, "The canvas reads back")
    Fixtures.teardown(surface)
    return image


func _button(pressed: bool) -> InputEventMouseButton:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = pressed
    return button


# --- Reading ------------------------------------------------------------------


## The mean of the largest channel difference between *a* and *b* over the
## texels of columns *from* to *to* that either moved off the canvas as it was
## before a stroke, which is the stroke and nothing else.
func _apart(a: Image, b: Image, from: int, to: int) -> float:
    var total := 0.0
    var count := 0
    for y in range(int(ROW) - 24, int(ROW) + 25):
        for x in range(from, to):
            var bare := _bare.get_pixel(x, y)
            var left := a.get_pixel(x, y)
            var right := b.get_pixel(x, y)
            if _distance(left, bare) < 1e-4 and _distance(right, bare) < 1e-4:
                continue
            total += _distance(left, right)
            count += 1
    assert_true(count > 0, "The stroke touched columns %d to %d" % [from, to])
    return total / maxf(float(count), 1.0)


static func _distance(a: Color, b: Color) -> float:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))
