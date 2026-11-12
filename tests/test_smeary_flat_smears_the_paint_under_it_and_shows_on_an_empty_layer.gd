## Smeary Flat smears the paint under it along the stroke, and shows on an
## empty layer.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The preset picked up 0.6 of the paint under it every update, so its carry
## was the paint where the pen stood two updates later and a stroke out of
## yellow into red laid red mixed with its own colour at once, with nothing of
## the yellow dragged along. It read the composite, which under an empty layer
## is the paper, so on an empty layer it laid its colour washed out towards
## white. On the reference card a blue stroke read 0.087 in green over the red past
## the crossing, against 0.053 with the smudge off, and on an empty layer over
## white it laid (0.69, 0.69, 0.96) for a brush of (0.05, 0.05, 0.85).
##
## The suite paints the bands on the layer the stroke paints, as a painter's
## would, and composites after every sample, as the app does every frame.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

const CANVAS := Vector2i(768, 256)
const ROW := 128.0
## The distance between the samples, which is the distance between dabs.
const SPACING := 4.0
const SAMPLE_MS := 8.0
const SEED := 7
const PRESSURE := 0.5
const YELLOW := Color(1.0, 0.85, 0.05, 1.0)
const RED := Color(0.85, 0.08, 0.05, 1.0)
## A blue with as little green as the red, so the green over the red band is
## the yellow the stroke carried there.
const PAINT := Color(0.05, 0.05, 0.85, 1.0)
## How many radii past the crossing the smear is read over.
const NEAR := 3.0
## The share of the yellow's green the smudged stroke carries over the red
## beyond the same stroke with the smudge off.
const MORE_YELLOW := 0.1
## The least mean alpha of the body on an empty layer.
const BODY_ALPHA := 0.5
## How far the body on an empty layer may stand from the same stroke's colour
## with the smudge off, in each channel.
const OWN_COLOUR := 0.05

var _surface: SaSurface = null
var _albedo: Dictionary = {}


func after_each() -> void:
    _albedo.clear()
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = null


## Out of the yellow band into the red, the stroke lays over the red, for
## [constant NEAR] radii past the crossing, more of the yellow's green than the
## same stroke with the smudge off by a tenth of the yellow's own.
func test_a_stroke_out_of_yellow_drags_the_yellow_over_the_red() -> void:
    var smeared := _over_the_red(true)
    var plain := _over_the_red(false)
    print("over the red past the crossing, smudged %s, the smudge off %s" % [smeared, plain])
    assert_true(
        smeared.g - plain.g >= MORE_YELLOW * YELLOW.g,
        (
            "the smudged stroke reads %.4f in green over the red, at least %.3f more than the smudge off's %.4f"
            % [smeared.g, MORE_YELLOW * YELLOW.g, plain.g]
        )
    )


## On an empty layer over white, the body of the stroke is at least half
## opaque.
func test_on_an_empty_layer_the_body_is_at_least_half_opaque() -> void:
    var body := _on_an_empty_layer(true, 0.7)
    print("on an empty layer, the body's mean %s" % body)
    assert_true(body.a >= BODY_ALPHA, "the body's mean alpha %.4f is at least %.2f" % [body.a, BODY_ALPHA])


## On an empty layer over white, the stroke lays its own colour, as it does
## with the smudge off, and not one washed out towards the paper.
func test_on_an_empty_layer_the_stroke_lays_its_own_colour() -> void:
    var smeared := _on_an_empty_layer(true, 0.5)
    var plain := _on_an_empty_layer(false, 0.5)
    print("on an empty layer, smudged %s, the smudge off %s" % [smeared, plain])
    for channel in 3:
        assert_true(
            absf(smeared[channel] - plain[channel]) <= OWN_COLOUR,
            (
                "channel %d reads %.4f, within %.2f of the smudge off's %.4f"
                % [channel, smeared[channel], OWN_COLOUR, plain[channel]]
            )
        )


## The mean colour the stroke leaves over the red band within [constant NEAR]
## radii past the crossing, half a radius either side of its line.
func _over_the_red(smudge: bool) -> Color:
    var side := _bands()
    var radius := _stroke(Vector2(side * 0.4, ROW), Vector2(side * 1.9, ROW), smudge)
    return _mean_over(side, side + int(radius * NEAR), radius * 0.5)


## The mean colour and alpha of a stroke on an empty layer over white, from
## its third radius to its third last, *reach* of a radius either side of its
## line.
func _on_an_empty_layer(smudge: bool, reach: float) -> Color:
    _empty()
    var radius := _stroke(Vector2(80, ROW), Vector2(680, ROW), smudge)
    return _mean_over(80 + int(radius * 3.0), 680 - int(radius * 3.0), radius * reach)


## A yellow band from the canvas's left edge to one chunk's side and a red one
## for the next, on the ground layer the stroke paints, over white beyond.
func _bands() -> int:
    _fresh()
    var document := _surface.easel.document
    var ground := document.active_layer
    var side := ground.get_or_create_chunk(Vector2i.ZERO).pixel_size()
    var cells: Array[Vector2i] = []
    for gy in ceili(float(CANVAS.y) / side):
        for gx in ceili(float(CANVAS.x) / side):
            var colour := YELLOW if gx == 0 else (RED if gx == 1 else Color.WHITE)
            ground.get_or_create_chunk(Vector2i(gx, gy)).clear(colour)
            cells.append(Vector2i(gx, gy))
    document.invalidate_chunks(cells)
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()
    return side


## An empty layer over a white ground, the layer the stroke paints.
func _empty() -> void:
    _fresh()
    var document := _surface.easel.document
    var ground := document.active_layer
    var side := ground.get_or_create_chunk(Vector2i.ZERO).pixel_size()
    var cells: Array[Vector2i] = []
    for gy in ceili(float(CANVAS.y) / side):
        for gx in ceili(float(CANVAS.x) / side):
            ground.get_or_create_chunk(Vector2i(gx, gy)).clear(Color.WHITE)
            cells.append(Vector2i(gx, gy))
    document.invalidate_chunks(cells)
    SaLayerOps.new(document).add()
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()


## A fresh surface in place of the last one.
func _fresh() -> void:
    _albedo.clear()
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)


## Smeary Flat's entry, with its pickup and smear length off unless *smudge*.
func _entry(smudge: bool) -> Dictionary:
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == "Smeary Flat":
            var copy := entry.duplicate(true)
            if not smudge:
                copy["settings"]["smudge_pickup_option:enabled"] = false
                copy["settings"]["smudge_length_option:enabled"] = false
            return copy
    return {}


## Paints one Smeary Flat stroke from *from* to *to* at [constant PRESSURE]
## and answers the tip's radius. *smudge* off clears the preset's pickup and
## smear length.
func _stroke(from: Vector2, to: Vector2, smudge: bool) -> float:
    var brush := StateNoiseBrushScript.new()
    brush.surface = _surface
    brush.stroke_seed = SEED
    brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, _entry(smudge))
    brush.settings.color = PAINT
    var clock := 1000.0
    var steps := ceili(from.distance_to(to) / SPACING)
    brush.begin_stroke(from, 0.0, Vector2.ZERO, clock, true)
    for i in steps:
        clock += SAMPLE_MS
        brush.add_sample(from.lerp(to, float(i + 1) / steps), PRESSURE, Vector2.ZERO, clock)
        _surface.easel.request_full_composite()
        _surface.easel.process_pending_composite()
    brush.end_stroke()
    _albedo.clear()
    return brush.get_cursor_radius()


## The mean colour and alpha of the layer from column *x0* to *x1*, *half*
## pixels either side of the stroke's line.
func _mean_over(x0: int, x1: int, reach: float) -> Color:
    var half := floori(reach)
    var sum := Color(0, 0, 0, 0)
    var count := 0
    for x in range(x0, x1):
        for y in range(int(ROW) - half, int(ROW) + half + 1):
            var c := _texel(Vector2i(x, y))
            sum += c
            count += 1
    return sum / count


## The active layer's texel at *pixel*.
func _texel(pixel: Vector2i) -> Color:
    var layer := _surface.easel.document.active_layer
    for grid: Vector2i in layer.chunks:
        var side := (layer.chunks[grid] as SaChunk).pixel_size()
        var here := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
        if not layer.chunks.has(here):
            return Color.TRANSPARENT
        if not _albedo.has(here):
            @warning_ignore("static_called_on_instance")
            _albedo[here] = SaExport.get_texture_image_float(layer.get_field(here))
        return (_albedo[here] as Image).get_pixelv(pixel - here * side)
    return Color.TRANSPARENT
