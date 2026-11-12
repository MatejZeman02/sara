## Firm Fill's grain stays on the canvas where a stroke turns, so a turned
## stroke lays the grain a straight one does, with no arcs and no holes.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Firm Fill paints two strokes on fresh surfaces at one pressure and one seed:
## a straight one [constant LEG] twice over, and one that runs [constant LEG]
## and turns through 90 degrees at its middle to run [constant LEG] again. The
## body of each, the texels within [constant BODY] of the tip's radius of the
## path and within two thirds of a leg either side of the turn, or of the
## straight stroke's middle, is read back.
##
## **What is held.** The turned stroke's painted share and the spread of its
## painted texels' lightness each lie within [constant WITHIN] of the straight
## stroke's, as a share of the straight stroke's. No slice across the turned
## stroke's body is wholly unpainted where the straight stroke has none. And
## the grain is not pulled: the mean step in lightness between neighbouring
## texels along x and along y, over the square round the turn, each lies within
## [constant WITHIN] of the straight stroke's own along its body, because a
## grain dragged into arcs round the joint changes little from one texel to the
## next along an arc and a great deal across it.
##
## **Why these.** The grain is read at a texel's place, and a stroke's place
## used to be its stroke coordinates, how far along the path and how far out
## from it. Every texel out on the side a turn opens is nearest the joint, so
## it read one along and an across that grew with its distance, and the grain
## there was drawn out into rays round the joint. Past the turn the stroke
## coordinates are another frame, so a dab before it and one after met a field
## that did not continue.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

const CANVAS := Vector2i(1024, 1024)
const PRESET := "Firm Fill"
const PRESSURE := 0.6
const SEED := 7
const COLOUR := Color(0.2, 0.4, 0.8, 1.0)
## Where both strokes start, each leg's length and the gap between two samples,
## in pixels, and how far apart in time two samples are, in milliseconds.
const FROM := Vector2(200.0, 200.0)
const LEG := 300.0
const SPACING := 1.5
const SAMPLE_MS := 8.0
## The share of the tip's radius either side of the path that is read, the
## share of a leg either side of the turn, how far the turned stroke may read
## from the straight one as a share of it, and the alpha a texel is painted at.
const BODY := 0.7
const NEAR_TURN := 2.0 / 3.0
const WITHIN := 0.05
const PAINTED := 0.5

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
## Chunk images already read back, by grid position.
var _images: Dictionary = {}


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    _images.clear()


func after_each() -> void:
    _brush = null
    _images.clear()
    Fixtures.teardown(_surface)
    _surface = null


func test_a_turned_stroke_lays_the_share_and_the_spread_of_a_straight_one() -> void:
    var straight := _read(false)
    _fresh()
    var turned := _read(true)
    assert_true(float(straight["share"]) > 0.5, "The straight stroke paints its body, %.4f" % straight["share"])
    assert_true(float(straight["spread"]) > 0.005, "The straight stroke shows its grain, a spread of %.4f" % straight["spread"])
    print("straight %s, turned %s" % [straight, turned])
    for key: String in ["share", "spread", "round_turn", "outward"]:
        var off: float = absf(turned[key] - straight[key]) / straight[key]
        assert_true(
            off <= WITHIN,
            (
                "The turned stroke's %s is %.4f against the straight stroke's %.4f, %.1f percent off"
                % [key, turned[key], straight[key], off * 100.0]
            )
        )


func test_a_turned_stroke_has_no_unpainted_slice_where_a_straight_one_has_none() -> void:
    var straight := _read(false)
    _fresh()
    var turned := _read(true)
    if straight["empty"] == 0:
        assert_eq(turned["empty"], 0, "Slices across the turned stroke's body with no paint at all")


func _fresh() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    _images.clear()


func _use() -> void:
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = SEED
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == PRESET:
            _brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
    _brush.settings.color = COLOUR
    _brush.settings.size_option.enabled = false


func _radius() -> float:
    return _brush.settings.radius * mini(CANVAS.x, CANVAS.y)


## The point *travelled* pixels along the stroke, which turns down at its
## middle when *turned*.
func _at(turned: bool, travelled: float) -> Vector2:
    if not turned or travelled <= LEG:
        return FROM + Vector2(travelled, 0.0)
    return FROM + Vector2(LEG, travelled - LEG)


## Paints the stroke and reads its body: the painted share, the spread of the
## painted texels' lightness, the mean step in lightness between neighbours
## along x and along y, and how many slices across the body hold no paint.
func _read(turned: bool) -> Dictionary:
    _use()
    var clock := 1000.0
    _brush.begin_stroke(_at(turned, 0.0), PRESSURE, Vector2.ZERO, clock)
    var travelled := SPACING
    while travelled <= 2.0 * LEG:
        clock += SAMPLE_MS
        _brush.add_sample(_at(turned, travelled), PRESSURE, Vector2.ZERO, clock)
        travelled += SPACING
    _brush.end_stroke()
    var r := _radius()
    var reach := LEG * NEAR_TURN
    var painted := 0
    var count := 0
    var lights := PackedFloat64Array()
    var box := Rect2(_at(turned, LEG - reach), Vector2.ZERO).expand(_at(turned, LEG + reach)).grow(r)
    for y in range(int(box.position.y), int(box.end.y)):
        for x in range(int(box.position.x), int(box.end.x)):
            if not _in_body(turned, Vector2(x, y), r * BODY, reach):
                continue
            count += 1
            var texel := _texel(Vector2i(x, y))
            if texel.a >= PAINTED:
                painted += 1
                lights.append(_lightness(texel))
    var mean := 0.0
    for light: float in lights:
        mean += light
    mean /= maxf(lights.size(), 1.0)
    var spread := 0.0
    for light: float in lights:
        spread += (light - mean) * (light - mean)
    spread = sqrt(spread / maxf(lights.size(), 1.0))
    var steps := _steps(turned, r * BODY, reach)
    return {
        "share": float(painted) / maxf(count, 1.0),
        "spread": spread,
        "round_turn": steps.x,
        "outward": steps.y,
        "empty": _empty_slices(turned, r * BODY, reach),
    }


## Whether *p* is within *half* of the path and within *reach* of the turn, or
## of the straight stroke's middle, along it.
func _in_body(turned: bool, p: Vector2, half: float, reach: float) -> bool:
    var joint := _at(turned, LEG)
    if not turned:
        return absf(p.y - FROM.y) <= half and absf(p.x - joint.x) <= reach
    var first := p.x <= joint.x and p.x >= joint.x - reach and absf(p.y - FROM.y) <= half
    var second := p.y >= joint.y and p.y <= joint.y + reach and absf(p.x - joint.x) <= half
    var corner := p.distance_to(joint) <= half
    return first or second or corner


## The mean step in lightness to the next painted texel round the turn and
## the mean step away from it, over the quarter disc of radius *half* on the
## side the turn opens, or the same quarter round the straight stroke's
## middle, as x and y.
func _steps(turned: bool, half: float, _reach: float) -> Vector2:
    var joint := _at(turned, LEG)
    var sums := Vector2.ZERO
    var counts := Vector2.ZERO
    for y in range(int(joint.y - half), int(joint.y)):
        for x in range(int(joint.x), int(joint.x + half)):
            var offset := Vector2(x, y) - joint
            var distance := offset.length()
            if distance < 3.0 or distance > half - 2.0:
                continue
            var here := _texel(Vector2i(x, y))
            if here.a < PAINTED:
                continue
            var outward := offset / distance
            var round_turn := outward.orthogonal()
            for pair: Array in [[round_turn, 0], [outward, 1]]:
                var there := _texel(Vector2i((Vector2(x, y) + (pair[0] as Vector2) * 1.5).round()))
                if there.a < PAINTED:
                    continue
                sums[pair[1]] += absf(_lightness(there) - _lightness(here))
                counts[pair[1]] += 1.0
    return Vector2(sums.x / maxf(counts.x, 1.0), sums.y / maxf(counts.y, 1.0))


## How many slices square to the path across the body, one a pixel along each
## leg within *reach* of the turn, hold no texel painted at all.
func _empty_slices(turned: bool, half: float, reach: float) -> int:
    var joint := _at(turned, LEG)
    var empty := 0
    for step in range(int(-reach), int(reach)):
        var centre := joint + Vector2(step, 0.0)
        var across := Vector2(0.0, 1.0)
        if turned and step >= 0:
            centre = joint + Vector2(0.0, step)
            across = Vector2(1.0, 0.0)
        var any := false
        for side in range(int(-half), int(half) + 1):
            if _texel(Vector2i(centre + across * side)).a > 0.0:
                any = true
                break
        if not any:
            empty += 1
    return empty


static func _lightness(texel: Color) -> float:
    return 0.2126 * texel.r + 0.7152 * texel.g + 0.0722 * texel.b


## The active layer's texel at *pixel*.
func _texel(pixel: Vector2i) -> Color:
    var layer := _surface.easel.document.active_layer
    var side := 0
    for grid: Vector2i in layer.chunks:
        side = (layer.chunks[grid] as SaChunk).pixel_size()
        break
    if side == 0:
        return Color.TRANSPARENT
    var grid := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
    if not layer.chunks.has(grid):
        return Color.TRANSPARENT
    if not _images.has(grid):
        @warning_ignore("static_called_on_instance")
        _images[grid] = SaExport.get_texture_image_float(layer.get_field(grid))
    return (_images[grid] as Image).get_pixelv(pixel - grid * side)
