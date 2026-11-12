## Height piles at a stroke's edges only under a hard press: above a pressure
## threshold the two sides of the footprint, across the direction of travel,
## stand higher than the stroke's middle, and below it nothing piles, the pile
## of the impasto design.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One stroke at a light pressure and one at a full one, each over a flat
## height: a brush of one height wherever it covers, and a shift low enough
## that every texel takes paint at any pressure, so the two strokes differ in
## their pressure alone. The profile across a stroke is the mean of the surface
## the view sums, taken down every row of a window along the stroke's middle
## stretch, away from its two ends. The light stroke's sides stand no higher
## than its middle, and the hard one's stand higher while its middle stands where
## the light one's does. A pressure between the two piles part of the way, so
## the pile grows with the pressure rather than switching on.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")

const RADIUS := 14.0
## The stroke, a straight line along y = 60, and the columns of it every row is
## averaged over, clear of the round caps at both ends.
const FROM := Vector2(20.0, 60.0)
const TO := Vector2(120.0, 60.0)
const FIRST_COLUMN := 50
const COLUMNS := 40
## Virtual millimetres at full, and the brush's height with the field flat at a
## half, which is what the stroke stands at where nothing piles.
const THICKNESS := 1.0
const FLAT_HEIGHT := 0.5
## How far from the path counts as the middle and as a side, in pixels: the
## middle is the half of the footprint nearest the path and a side the last
## third before its rim, the rim's own texel left out.
const MIDDLE := 7
const SIDE_FROM := 10
const SIDE_TO := 13
## A pressure that is light, one between the threshold and a full press, and a
## full one.
const LIGHT := 0.3
const FIRM := 0.85
const HARD := 1.0

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null


func before_each() -> void:
    _fresh()


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null


## At a light pressure the sides stand no higher than the middle, and the
## stroke is the flat height of the brush all the way across.
func test_a_light_stroke_piles_nothing_at_its_sides() -> void:
    _stroke(LIGHT)
    var profile := _profile()
    var middle := _middle(profile)
    var sides := _sides(profile)
    assert_true(sides <= middle + 0.001, "The light stroke's sides stand at %.4f and its middle at %.4f" % [sides, middle])
    assert_almost_eq(middle, FLAT_HEIGHT, 0.01, "and the middle is the brush's own height")


## At a full pressure the sides stand higher than the middle, which stands
## where the light stroke's middle did, since the pile is laid at the sides and
## not taken from the middle.
func test_a_hard_stroke_piles_height_at_its_sides() -> void:
    _stroke(LIGHT)
    var light_middle := _middle(_profile())
    _fresh()
    _stroke(HARD)
    var profile := _profile()
    var middle := _middle(profile)
    var sides := _sides(profile)
    assert_true(sides > middle * 1.2, "The hard stroke's sides stand at %.4f, over its middle's %.4f" % [sides, middle])
    assert_almost_eq(middle, light_middle, 0.01, "and its middle stands where the light stroke's does, %.4f" % light_middle)


## A pressure past the threshold and short of a full one piles part of the way,
## so the pile grows with the pressure.
func test_the_pile_grows_with_the_pressure_past_the_threshold() -> void:
    _stroke(FIRM)
    var firm := _sides(_profile())
    _fresh()
    _stroke(HARD)
    var hard := _sides(_profile())
    _fresh()
    _stroke(LIGHT)
    var light := _sides(_profile())
    assert_true(firm > light + 0.01, "A firm stroke's sides stand at %.4f, over the light stroke's %.4f" % [firm, light])
    assert_true(hard > firm + 0.01, "and a hard stroke's at %.4f, over the firm one's %.4f" % [hard, firm])


## The pile is the stroke's own height, so a stroke that lays none, Thickness
## at nought, piles none at a full press.
func test_a_stroke_that_lays_no_height_piles_none() -> void:
    _brush.settings.thickness = 0.0
    _stroke(HARD)
    var profile := _profile()
    assert_almost_eq(_sides(profile), 0.0, 0.0001, "No height at the sides")
    assert_almost_eq(_middle(profile), 0.0, 0.0001, "and none in the middle")


## A brush on a fresh document whose own height is the same everywhere: the
## field's lightness held at a half by a relief of nought, Thickness with its
## sensors off so the pressure does not change the height, and the field
## shifted down until every texel takes paint at any pressure.
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
    _brush.settings.strength = -1.0
    _brush.settings.strength_option.enabled = false
    _brush.settings.radius = RADIUS / 256.0
    _brush.settings.texture_field = "grain"
    _brush.settings.texture_channels = 2
    _brush.settings.texture_relief = 0.0
    _brush.settings.thickness = THICKNESS
    _brush.settings.thickness_option.enabled = false


## A stroke from [constant FROM] to [constant TO] at *pressure*, sample by
## sample a few pixels apart, as a pen would lay it.
func _stroke(pressure: float) -> void:
    _brush.begin_stroke(FROM, pressure)
    var steps := ceili(FROM.distance_to(TO) / 4.0)
    for i in range(1, steps + 1):
        _brush.add_sample(FROM.lerp(TO, float(i) / steps), pressure)
    _brush.end_stroke()


## The surface the view sums, by distance from the path: element *d* is the
## mean over the columns of the window of the rows *d* pixels above and below
## the path, a pixel at a time.
func _profile() -> PackedFloat32Array:
    var easel := _surface.easel
    easel.request_full_composite()
    easel.process_pending_composite()
    var heights := easel.relief.heights
    var profile := PackedFloat32Array()
    profile.resize(int(RADIUS) + 1)
    if heights == null:
        return profile
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(heights.rid, 0)
    for d in profile.size():
        var sum := 0.0
        for x in COLUMNS:
            for y: int in [int(FROM.y) - d, int(FROM.y) + d]:
                sum += bytes.decode_half((y * heights.size.x + FIRST_COLUMN + x) * 2)
        profile[d] = sum / (COLUMNS * 2)
    return profile


## The mean height of the half of the footprint nearest the path.
func _middle(profile: PackedFloat32Array) -> float:
    return _mean(profile, 0, MIDDLE)


## The mean height of the last third of the footprint before its rim.
func _sides(profile: PackedFloat32Array) -> float:
    return _mean(profile, SIDE_FROM, SIDE_TO)


func _mean(profile: PackedFloat32Array, first: int, last: int) -> float:
    var sum := 0.0
    for d in range(first, last + 1):
        sum += profile[d]
    return sum / (last - first + 1)
