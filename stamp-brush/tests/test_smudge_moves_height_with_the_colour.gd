## Smudge moves height with the colour: a smudge stroke through
## a ridge of thick paint drags the ridge along the stroke, and the sum of the
## heights stays what it was.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A stroke through the brush's own input**, the way the preset thumbnails
## drive one, over a layer painted grey with a ridge standing across the path.
## The height is read back here, which a test may do and the brush never does.
## The picture is `scenarios/smudge-moves-height-with-the-colour.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const CANVAS := Vector2i(512, 256)
## One chunk's side, which the canvas is two of across.
const CHUNK: int = 256
## The ridge: a band of paint this high, across the stroke's path.
const RIDGE_FROM: int = 96
const RIDGE_TO: int = 112
const RIDGE_HEIGHT: float = 1.0
## The stroke, left to right through the ridge and well past it, into the
## second chunk, where the layer holds no paint and no height until the stroke
## reaches it.
const FROM := Vector2(56.0, 128.0)
const TO := Vector2(300.0, 128.0)
const STEPS: int = 60
## The dab's radius in document pixels.
const RADIUS: float = 10.0

const GREY := Color(0.5, 0.5, 0.5, 1.0)


func _surface() -> SaSurface:
    var surface := Fixtures.make_surface(CANVAS)
    var document := surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i.ZERO).clear(GREY)
    # Composited before the stroke, because the pickup reads the composite and
    # a composite never drawn is bare canvas to it.
    document.invalidate_chunks([Vector2i.ZERO])
    surface.easel.request_full_composite()
    surface.easel.process_pending_composite()
    return surface


## Gives the active layer its height, with the ridge standing in it.
func _ridge(document: SaDocument) -> void:
    var layer := document.active_layer
    assert_true(SaHeightOps.new(document).gain(layer), "The layer gains its height")
    var height := layer.get_or_create_field(Vector2i.ZERO, SaFieldSpec.HEIGHT)
    var bytes := PackedByteArray()
    bytes.resize(CHUNK * CHUNK * 2)
    for y in range(CHUNK):
        for x in range(RIDGE_FROM, RIDGE_TO):
            bytes.encode_half((y * CHUNK + x) * 2, RIDGE_HEIGHT)
    GlobalShaderCompiler.get_rd().texture_update(height.rid, 0, bytes)


## Every texel's height over the canvas, in row order, nought where the layer
## holds none.
func _heights(document: SaDocument) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    out.resize(CANVAS.x * CANVAS.y)
    for cx in range(int(CANVAS.x / float(CHUNK))):
        var height := document.active_layer.get_field(Vector2i(cx, 0), SaFieldSpec.HEIGHT)
        if height == null:
            continue
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(height.rid, 0)
        for y in range(CHUNK):
            for x in range(CHUNK):
                out[y * CANVAS.x + cx * CHUNK + x] = bytes.decode_half((y * CHUNK + x) * 2)
    return out


func _sum(heights: PackedFloat32Array) -> float:
    var total := 0.0
    for value in heights:
        total += value
    return total


## Where the height stands along the stroke, the mean of x weighted by it,
## over the rows the dab's core crosses. The rows at the dab's rim are touched
## at a fraction of the rate, and would dilute the drag this reads.
func _centre(heights: PackedFloat32Array) -> float:
    var weighted := 0.0
    var total := 0.0
    for y in range(int(FROM.y - RADIUS * 0.5), int(FROM.y + RADIUS * 0.5) + 1):
        for x in range(CANVAS.x):
            var value := heights[y * CANVAS.x + x]
            weighted += value * float(x)
            total += value
    return weighted / total if total > 0.0 else 0.0


## The height past the ridge on the stroke's line, where only a drag can put it.
func _past_ridge(heights: PackedFloat32Array) -> float:
    var total := 0.0
    for x in range(RIDGE_TO + 2, RIDGE_TO + 30):
        total += heights[int(FROM.y) * CANVAS.x + x]
    return total


func _brush(surface: SaSurface, move_height: bool) -> ToolState:
    var brush := StateBrushScript.new()
    brush.surface = surface
    brush.settings.color = Color(0.2, 0.3, 0.8, 1.0)
    brush.settings.radius = RADIUS / float(CANVAS.x)
    brush.settings.hardness = GammaFloat.new(1.0, 1.0)
    brush.settings.opacity_by_pressure = false
    brush.settings.smudge_pickup_option.enabled = true
    brush.settings.smudge_color_rate_option.enabled = true
    brush.settings.smudge_color_rate_option.strength = 0.2
    brush.settings.smudge_length_option.enabled = true
    brush.settings.smudge_move_height = move_height
    return brush


## A stroke from [constant FROM] to [constant TO] through the brush's own input.
func _stroke(surface: SaSurface, brush: ToolState) -> void:
    var view := surface.view
    for i in range(STEPS + 1):
        view.mouse_position = FROM.lerp(TO, float(i) / float(STEPS))
        var event: InputEvent
        if i == 0:
            var press := InputEventMouseButton.new()
            press.button_index = MOUSE_BUTTON_LEFT
            press.pressed = true
            event = press
        else:
            var motion := InputEventMouseMotion.new()
            motion.button_mask = MOUSE_BUTTON_MASK_LEFT
            motion.pressure = 1.0
            event = motion
        brush.handle_input(event)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    brush.handle_input(release)


func _free(surface: SaSurface) -> void:
    surface.get_document().free()
    surface.easel.free()


func test_a_smudge_drags_the_ridge_along_and_keeps_its_sum() -> void:
    var surface := _surface()
    var document := surface.get_document()
    _ridge(document)
    var before := _heights(document)

    _stroke(surface, _brush(surface, true))
    var after := _heights(document)

    var moved := _centre(after) - _centre(before)
    assert_true(moved > 4.0, "The ridge's height moved along the stroke, to the right, by %.2f texels" % moved)
    var past := _past_ridge(after)
    assert_true(past > 0.5, "and stands past the ridge where there was none, %.3f of it" % past)
    var drift := absf(_sum(after) - _sum(before)) / _sum(before)
    assert_true(drift < 0.03, "The sum over the region is within three per cent of before, %.4f of it changed" % drift)
    for value in after:
        if value > RIDGE_HEIGHT + 0.01:
            assert_true(false, "No texel rose above the tallest paint the stroke met, %.4f" % value)
            break
    # The second chunk's height is allocated by the stroke, and has to start
    # blank: a height allocated inside the dab's compute list was left
    # undefined, and read 0.598 millimetres across a whole chunk the stroke
    # barely touched.
    var reached := document.active_layer.get_field(Vector2i(1, 0), SaFieldSpec.HEIGHT)
    assert_true(reached != null, "The stroke reached the second chunk")
    var stray := 0.0
    for y in range(0, 64):
        for x in range(CHUNK, CANVAS.x):
            stray = maxf(stray, absf(after[y * CANVAS.x + x]))
    assert_eq(stray, 0.0, "and its height is nought away from the stroke")

    assert_true(document.undo(), "Undo takes the stroke back")
    var undone := _heights(document)
    assert_almost_eq(_sum(undone), _sum(before), 0.01, "and the height with it")
    assert_almost_eq(_centre(undone), _centre(before), 0.01, "where it stood")
    _free(surface)


func test_move_height_off_leaves_the_relief_where_it_stands() -> void:
    var surface := _surface()
    var document := surface.get_document()
    _ridge(document)
    var before := _heights(document)

    _stroke(surface, _brush(surface, false))
    var after := _heights(document)

    assert_eq(after, before, "With Move Height off the smudge moves the colour and no height")
    _free(surface)


func test_a_layer_without_height_gains_none_from_a_smudge() -> void:
    var surface := _surface()
    var document := surface.get_document()

    _stroke(surface, _brush(surface, true))

    assert_false(document.active_layer.carries_height(), "A smudge never gives a layer a height it did not have")
    _free(surface)


func test_a_new_brush_has_move_height_on() -> void:
    var settings := SaStampBrushSettings.new()
    assert_true(settings.smudge_move_height, "The switch is on by default, and moves only a height that is there")
