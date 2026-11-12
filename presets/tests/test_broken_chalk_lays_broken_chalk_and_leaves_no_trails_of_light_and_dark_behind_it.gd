## Broken Chalk lays broken chalk and leaves no trails of light and dark behind
## it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter painted Broken Chalk at a size of 131.4, `#2a2a2a`, and saw the
## canvas as a grey embossed relief with bright and dark edges. Nothing of a
## stroke of the shipped recipe lands farther than one tip radius from its
## path, colour or height. The recipe is a painter's own,
## which sets a thickness of 0.19, so the stroke lays height under its tip
## and only there. The
## Broken Chalk an older profile was offered is another
## preset: at a thickness of 0.1 it lays height, which the view lights as a
## relief, and a profile keeps that file, since a shipped preset is written
## once and never again.
##
## Each stroke is laid through the tool's own calls on a real surface, at the
## the painter's tip, a radius of 65.7 pixels, along an arc whose pressure rises
## and falls as a pen's does, on a layer painted flat beforehand and on one
## painted with a height. The picture and the relief the view sums are read
## before and after it at every texel farther than a tip radius from the path.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

const PRESET := "Broken Chalk"
const SIZE := Vector2i(640, 480)
## The painter's size, 131.4 across, as a radius in document pixels.
const TIP := 65.7
## The painter's colour.
const CHALK := Color("#2a2a2a")
## The flat paint laid beforehand, and the brush that lays it, wide and with no
## shift, so a full press paints every texel it reaches.
const FLAT := Color(0.62, 0.6, 0.55)
const FLAT_RADIUS := 90.0
## The arc the chalk is drawn along: its centre, its radius and the angles it
## runs between, in turns of pi, a sample every [constant STEP] pixels.
const CENTRE := Vector2(320.0, 400.0)
const ARC := 250.0
const ARC_FROM := 1.15
const ARC_TO := 1.85
const STEP := 3.0
## How far past the tip a texel is still counted as the stroke's, for the
## relief's lighting and the rounding of the path's samples.
const MARGIN := 3.0
## The earlier recipe of Broken Chalk, the one an older
## profile still holds.
const OFFERED_BEFORE := {"thickness": 0.1, "randomness": 1.0, "grain_scale": 2.0}

var _surface: SaSurface = null


func after_each() -> void:
    if _surface != null:
        Fixtures.teardown(_surface)
        _surface = null


func _entry() -> Dictionary:
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == PRESET:
            return entry
    return {}


## A fresh surface whose layer is painted flat in [constant FLAT], at
## *thickness* millimetres when it is above nought.
func _painted(thickness: float) -> void:
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(SIZE)
    SaLayerOps.new(_surface.easel.document).add()
    var brush := StateNoiseBrushScript.new()
    brush.surface = _surface
    brush.stroke_seed = 3
    brush.settings.color = FLAT
    brush.settings.opacity = 1.0
    brush.settings.hardness = 1.0
    brush.settings.strength = 0.0
    brush.settings.strength_option.enabled = false
    brush.settings.radius = FLAT_RADIUS / float(mini(SIZE.x, SIZE.y))
    brush.settings.texture_field = "grain"
    brush.settings.thickness = thickness
    if thickness > 0.0:
        brush.settings.texture_channels = 2
        brush.settings.texture_relief = 1.0
    var row := 0.0
    while row <= SIZE.y:
        _drawn(brush, [Vector2(-FLAT_RADIUS, row), Vector2(SIZE.x + FLAT_RADIUS, row)], 1.0, 1.0)
        row += FLAT_RADIUS
    _surface.easel.document.commit_stroke()


## Broken Chalk as it ships, with *changed* written over its recipe, at the
## the painter's tip and colour, drawn along the arc.
func _chalk(changed: Dictionary = {}) -> void:
    var settings := NoisePresetsScript.build(NoiseBrushSettingsScript, _entry())
    for key: String in changed:
        settings.set(key, changed[key])
    settings.color = CHALK
    settings.radius = TIP / float(mini(SIZE.x, SIZE.y))
    var brush := StateNoiseBrushScript.new()
    brush.surface = _surface
    brush.stroke_seed = 7
    brush.settings = settings
    _drawn(brush, _arc(), 0.3, 0.9)
    _surface.easel.document.commit_stroke()


## The arc's samples, [constant STEP] apart.
static func _arc() -> PackedVector2Array:
    var path := PackedVector2Array()
    var count := ceili(ARC * PI * (ARC_TO - ARC_FROM) / STEP)
    for i in count + 1:
        var angle := PI * lerpf(ARC_FROM, ARC_TO, float(i) / count)
        path.append(CENTRE + ARC * Vector2(cos(angle), sin(angle)))
    return path


## A stroke through *path*, resampled [constant STEP] apart, its pressure
## rising from *light* to *firm* at the middle and falling back.
static func _drawn(brush: StateNoiseBrushScript, path: PackedVector2Array, light: float, firm: float) -> void:
    var samples := PackedVector2Array()
    for i in path.size() - 1:
        var steps := maxi(1, ceili(path[i].distance_to(path[i + 1]) / STEP))
        for s in steps:
            samples.append(path[i].lerp(path[i + 1], float(s) / steps))
    samples.append(path[path.size() - 1])
    var last := samples.size() - 1
    brush.begin_stroke(samples[0], light)
    for i in range(1, samples.size()):
        brush.add_sample(samples[i], lerpf(light, firm, sin(PI * float(i) / last)))
    brush.end_stroke()


## The picture a painter sees and the relief the view sums under it, in that
## order, the relief empty while nothing shows a height.
func _read() -> Array:
    var easel := _surface.easel
    easel.request_full_composite()
    easel.process_pending_composite()
    var picture := SaExport.get_preview_image(easel)
    picture.convert(Image.FORMAT_RGBA8)
    var heights := easel.relief.heights
    var relief := PackedByteArray()
    if heights != null:
        relief = GlobalShaderCompiler.get_rd().texture_get_data(heights.rid, 0)
    return [picture.get_data(), relief]


## One byte a texel, set where the texel lies within a tip radius and the
## margin of the arc.
static func _near_path() -> PackedByteArray:
    var near := PackedByteArray()
    near.resize(SIZE.x * SIZE.y)
    var reach := TIP + MARGIN
    for at: Vector2 in _arc():
        for y in range(maxi(0, floori(at.y - reach)), mini(SIZE.y, ceili(at.y + reach) + 1)):
            for x in range(maxi(0, floori(at.x - reach)), mini(SIZE.x, ceili(at.x + reach) + 1)):
                if Vector2(x, y).distance_to(at) <= reach:
                    near[y * SIZE.x + x] = 1
    return near


## How many texels farther than a tip radius from the path changed between
## *before* and *after*, in the picture in x and in the relief in y, and the
## largest change of a channel in z, in eighths of a level, and of a height
## in w, in virtual millimetres.
static func _changed_away(before: Array, after: Array) -> Vector4:
    var near := _near_path()
    var was: PackedByteArray = before[0]
    var now: PackedByteArray = after[0]
    var was_relief: PackedByteArray = before[1]
    var now_relief: PackedByteArray = after[1]
    var out := Vector4.ZERO
    for i in near.size():
        if near[i] == 1:
            continue
        var moved := 0
        for c in 3:
            moved = maxi(moved, absi(int(now[i * 4 + c]) - int(was[i * 4 + c])))
        if moved > 0:
            out.x += 1
            out.z = maxf(out.z, moved)
        var height_was := was_relief.decode_half(i * 2) if was_relief.size() > i * 2 else 0.0
        var height_now := now_relief.decode_half(i * 2) if now_relief.size() > i * 2 else 0.0
        if height_now != height_was:
            out.y += 1
            out.w = maxf(out.w, absf(height_now - height_was))
    return out


## The highest height the relief holds anywhere, nought for none.
static func _tallest(read: Array) -> float:
    var relief: PackedByteArray = read[1]
    var tallest := 0.0
    for i in relief.size() >> 1:
        tallest = maxf(tallest, relief.decode_half(i * 2))
    return tallest


func test_broken_chalk_ships_at_the_chosen_thickness() -> void:
    var entry := _entry()
    assert_false(entry.is_empty(), "Broken Chalk is on the noise shelf")
    var settings := NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
    assert_not_null(settings, "and builds")
    if settings == null:
        return
    assert_almost_eq(settings.thickness, 0.19, 1e-6, "It ships at the painter's thickness of 0.19")


func test_over_a_layer_painted_flat_the_stroke_leaves_everything_past_its_tip_as_it_was() -> void:
    _painted(0.0)
    var before := _read()
    _chalk()
    var after := _read()
    var away := _changed_away(before, after)
    assert_eq(int(away.x), 0, "No texel farther than a tip radius changes colour, the largest change %d levels" % int(away.z))
    assert_eq(int(away.y), 0, "and none changes height, the largest change %.4f" % away.w)
    assert_true(_tallest(after) > 0.0, "The stroke lays the painter's height under its tip, %.4f at most" % _tallest(after))
    var darker := 0
    # The stroke paints: the texels on its path take the chalk.
    var was: PackedByteArray = before[0]
    var now: PackedByteArray = after[0]
    for at: Vector2 in _arc():
        var i := int(at.y) * SIZE.x + int(at.x)
        if now[i * 4] < was[i * 4]:
            darker += 1
    assert_true(
        darker * 4 > _arc().size(), "and the chalk lands on its path, darker at %d of %d samples" % [darker, _arc().size()]
    )


func test_over_a_layer_painted_with_a_height_the_stroke_leaves_everything_past_its_tip_as_it_was() -> void:
    _painted(1.0)
    var before := _read()
    assert_true(_tallest(before) > 0.0, "The layer under the chalk stands in relief")
    _chalk()
    var after := _read()
    var away := _changed_away(before, after)
    assert_eq(int(away.x), 0, "No texel farther than a tip radius changes colour, the largest change %d levels" % int(away.z))
    assert_eq(int(away.y), 0, "and none changes height, the largest change %.4f" % away.w)


func test_the_broken_chalk_a_profile_was_offered_before_lays_a_relief_and_so_does_the_painters() -> void:
    _painted(0.0)
    _chalk(OFFERED_BEFORE)
    assert_true(_tallest(_read()) > 0.0, "The earlier recipe lays a height the view lights as relief")
    _painted(0.0)
    _chalk()
    assert_true(_tallest(_read()) > 0.0, "and so does the painter's, which ships")
