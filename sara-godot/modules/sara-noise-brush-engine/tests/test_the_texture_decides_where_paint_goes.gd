## The pressure is the cut through the texture.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Straight strokes are painted through the tool's own public calls and read
## back texel by texel against the field the kernel reads, so "a texel paints
## where the pressure reaches the field" is a comparison and not a picture
## somebody looked at.
##
## **The field is measured, not predicted.** The probe kernel reads the field
## the stroke was laid with on the GPU, in the stroke's own coordinates, along
## from its first point and across over the tip's half-width, and the suite
## reads that back. A copy of the field in GDScript would hold the suite to the
## CPU's reading, which is the dynamics suite's to hold to the kernel. No texel
## is let off for sitting near the pressure: one at or under it is at full and
## one over it by more than the band is empty, each within [constant SLACK] of
## its alpha.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")

## How far a texel's alpha may sit from full or from nothing and still read as
## either, which is a float's rounding and not a band of the field let off.
const SLACK := 0.001

## The tip's radius in pixels, and how far from the path a texel may be for the
## tip's coverage there to be one, so the cut reads the field alone.
const RADIUS := 14.0
const INSIDE := RADIUS - 4.0

## How far from the path a texel of a stroke's body may be and still be read.
## The edge of a soft stroke at a working press moves in along its length by up
## to two thirds of the half-width, `NOISE_EDGE_DEPTH` and `NOISE_EDGE_NICK` in
## `noise_edge.gmacs`, and its rim thins from there, so the body's texels lie
## inside the least outline the edge can leave. A press keeps the tip's outline
## about its start, so [constant INSIDE] holds there.
const BODY := 4.0

## Each stroke's length, laid rightwards from its start in samples
## [constant STEP] apart.
const LENGTH := 64.0
const STEP := 8.0

## Hardness a little under full, so the band below the field's value is a
## tenth of the pressure's range wide.
const HARDNESS := 0.9

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
## Chunk images already read back, by grid position, so a stroke's thousand
## texels cost one read per chunk rather than one each.
var _images: Dictionary = {}


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7
    _brush.settings.color = Color(0.2, 0.4, 0.8, 1.0)
    _brush.settings.opacity = 1.0
    _brush.settings.hardness = HARDNESS
    _brush.settings.radius = RADIUS / 256.0
    _brush.settings.texture_field = "grain"
    _brush.settings.texture_drift = 0.0
    _images.clear()


func after_each() -> void:
    _brush = null
    _images.clear()
    Fixtures.teardown(_surface)
    _surface = null


## A fresh brush shifts nothing and binds nothing to Strength, because the
## pressure is the cut itself, and leaves Opacity alone.
func test_a_fresh_brush_shifts_nothing_and_binds_no_pressure_to_strength() -> void:
    var settings := NoiseBrushSettingsScript.new()
    assert_eq(settings.strength, 0.0, "Strength starts at no shift")
    var option: SaCurveOption = settings.strength_option
    assert_false(option.enabled, "and its option is off")
    assert_null(option.sensor_for(SaSensor.Id.PRESSURE), "and carries no pressure binding")
    assert_true(settings.options().has("strength"), "while the curve editor still finds it among the brush's options")
    assert_eq(settings.opacity, 1.0, "Opacity starts at full")
    assert_false(settings.opacity_option.enabled, "and follows no sensor")


## The Done when: strokes at a quarter, a half and a full press through one
## field at Strength's default. A texel whose field is at or under the
## pressure takes full alpha, one above it by more than the band takes none,
## and a firmer press paints more of the stroke, the full one all of it.
func test_a_texel_paints_where_the_pressure_reaches_the_field() -> void:
    var pressures := [0.3, 0.5, 1.0]
    var band := _brush.band_for(SaDabParams.new())
    assert_almost_eq(band, 1.0 - HARDNESS, 1e-4, "the band is what Hardness leaves of one")
    var counts: Array[int] = []
    for index in pressures.size():
        var pressure: float = pressures[index]
        var start := Vector2(32.0, 40.0 + 48.0 * index)
        var reading := _stroke_against_its_field(start, pressure, 0.0, band)
        var label := "At a pressure of %.2f" % pressure
        assert_true(reading["below"] > 20, "%s some texels' field is under it, %d" % [label, reading["below"]])
        assert_eq(reading["not_full"], 0, "%s every texel whose field it reaches is at full (%s)" % [label, reading["example"]])
        assert_eq(
            reading["not_empty"],
            0,
            "%s no texel whose field is over it by more than the band paints (%s)" % [label, reading["example"]]
        )
        counts.append(reading["painted"])
        if pressure < 1.0:
            assert_true(
                reading["above"] > 20, "%s some texels' field is over it by more than the band, %d" % [label, reading["above"]]
            )
    var total := _body_count()
    assert_true(counts[0] < counts[1] and counts[1] < counts[2], "A firmer press paints more, %s of %d" % [counts, total])
    assert_eq(counts[2], total, "and a full one paints the whole stroke")


## Strength shifts the field against the pressure: above nought a full press
## leaves the field's top open, below nought a half press paints past its
## half.
func test_strength_shifts_the_field_against_the_pressure() -> void:
    var band := _brush.band_for(SaDabParams.new())
    var cases := [[1.0, 0.3], [0.5, -0.3]]
    for index in cases.size():
        var pressure: float = cases[index][0]
        var shift: float = cases[index][1]
        _brush.settings.strength = shift
        var start := Vector2(32.0, 40.0 + 48.0 * index)
        var reading := _stroke_against_its_field(start, pressure, shift, band)
        var label := "At a pressure of %.2f shifted %.2f" % [pressure, shift]
        assert_true(
            reading["below"] > 20 and reading["above"] > 20,
            "%s the field falls both sides, %d and %d" % [label, reading["below"], reading["above"]]
        )
        assert_eq(
            reading["not_full"], 0, "%s every texel the shifted field lets in is at full (%s)" % [label, reading["example"]]
        )
        assert_eq(reading["not_empty"], 0, "%s and none it shuts out paints (%s)" % [label, reading["example"]])


## The soft band: with Hardness at nought a texel whose field is over the
## pressure is partly painted, which is where a light stroke's softness comes
## from.
func test_a_soft_hardness_fades_texels_in_below_their_value() -> void:
    _brush.settings.hardness = 0.0
    var start := Vector2(32.0, 40.0)
    var image := _stroke(start, 0.5)
    var partial := 0
    for offset: Vector2i in _body_offsets():
        var field := image.get_pixelv(offset - _body_origin()).r
        var alpha := _texel(Vector2i(start) + offset).a
        if field > 0.55 and field < 1.0 and alpha > 0.02 and alpha < 0.98:
            partial += 1
    assert_true(partial > 10, "Texels whose field the pressure falls short of are partly painted, %d of them" % partial)


## A press waits for the path to say where it goes. Painted on its own it read
## the field along the heading the pen had, rightwards at a press, and the
## stroke after it could only raise that paint, not replace it. A stroke that
## leaves leftwards and up reads, all round its start, the field along its own
## path, from a mouse's press and a pen's alike.
func test_a_press_waits_to_read_the_field_along_the_path() -> void:
    var band := _brush.band_for(SaDabParams.new())
    var start := Vector2(120.0, 120.0)
    var heading := Vector2(-6.0, -4.0)
    for held: bool in [false, true]:
        Fixtures.teardown(_surface)
        _surface = Fixtures.make_surface()
        _brush.surface = _surface
        _images.clear()
        _brush.begin_stroke(start, 0.5, Vector2.ZERO, -1.0, held)
        for step in range(1, 9):
            _brush.add_sample(start + heading * step, 0.5)
        _brush.end_stroke()
        var reach := int(INSIDE)
        var region := Rect2i(Vector2i(start) - Vector2i(reach, reach), Vector2i(2 * reach + 1, 2 * reach + 1))
        var probe: SaTexture = _brush.probe_field(region, start, heading.normalized(), 0.0, RADIUS)
        @warning_ignore("static_called_on_instance")
        var field := SaExport.get_texture_image_float(probe)
        var checked := 0
        var wrong := 0
        var example := "none"
        for y in region.size.y:
            for x in region.size.x:
                var at := region.position + Vector2i(x, y)
                if Vector2(at).distance_to(start) > INSIDE:
                    continue
                var needed := field.get_pixel(x, y).r
                var alpha := _texel(at).a
                var full := needed <= 0.5 and alpha < 1.0 - SLACK
                var empty := needed > 0.5 + band and alpha > SLACK
                checked += 1
                if full or empty:
                    wrong += 1
                    example = "texel %s needs %.4f alpha %.4f" % [at, needed, alpha]
        var label := "a pen's press" if held else "a mouse's press"
        assert_true(checked > 200, "From %s the tip about the start is read, %d texels" % [label, checked])
        assert_eq(wrong, 0, "and from %s every one of them is cut by the field along the path (%s)" % [label, example])


## Paints a straight stroke from *start* at *pressure* and reads every texel of
## its body against the field there shifted by *shift*: how many paint, how
## many are under the pressure and how many over it by more than *band*, and
## how many of each are on the wrong side.
func _stroke_against_its_field(start: Vector2, pressure: float, shift: float, band: float) -> Dictionary:
    var image := _stroke(start, pressure)
    var reading := {"painted": 0, "below": 0, "above": 0, "not_full": 0, "not_empty": 0, "example": "none"}
    for offset: Vector2i in _body_offsets():
        var needed := image.get_pixelv(offset - _body_origin()).r + shift
        var at := Vector2i(start) + offset
        var alpha := _texel(at).a
        if alpha > SLACK:
            reading["painted"] += 1
        if needed <= pressure:
            reading["below"] += 1
            if alpha < 1.0 - SLACK:
                reading["not_full"] += 1
                reading["example"] = "texel %s needs %.4f alpha %.4f" % [at, needed, alpha]
        elif needed > pressure + band:
            reading["above"] += 1
            if alpha > SLACK:
                reading["not_empty"] += 1
                reading["example"] = "texel %s needs %.4f alpha %.4f" % [at, needed, alpha]
    return reading


## Paints a straight rightward stroke from *start* at *pressure*, its samples
## [constant STEP] apart, and the field it was laid with read by the probe
## over its body, from [method _body_origin] on, along from the stroke's first
## point and across over the tip's radius, which is a round tip's half-width.
func _stroke(start: Vector2, pressure: float) -> Image:
    _images.clear()
    _brush.begin_stroke(start, pressure)
    var travelled := STEP
    while travelled <= LENGTH:
        _brush.add_sample(start + Vector2(travelled, 0.0), pressure)
        travelled += STEP
    _brush.end_stroke()
    var region := Rect2i(Vector2i(start) + _body_origin(), _body_size())
    var probe: SaTexture = _brush.probe_field(region, Vector2(Vector2i(start)), Vector2.RIGHT, 0.0, RADIUS)
    @warning_ignore("static_called_on_instance")
    return SaExport.get_texture_image_float(probe)


## The stroke's body, the texels between its two ends and within
## [constant BODY] of its path, as offsets from its start.
func _body_offsets() -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    var origin := _body_origin()
    var size := _body_size()
    for y in size.y:
        for x in size.x:
            out.append(origin + Vector2i(x, y))
    return out


func _body_origin() -> Vector2i:
    return Vector2i(0, -int(BODY))


func _body_size() -> Vector2i:
    return Vector2i(int(LENGTH) + 1, 2 * int(BODY) + 1)


func _body_count() -> int:
    return _body_offsets().size()


## The active layer's texel at a document pixel.
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
