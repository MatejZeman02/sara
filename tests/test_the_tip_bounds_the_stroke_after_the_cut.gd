## The tip bounds the stroke after the cut.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The cut is made on the field against the pressure alone, and the tip's
## coverage multiplies what passed. Straight strokes are painted through the
## tool's own public calls on a real surface and read back texel by texel, the
## tip's coverage taken from its own formula written out here rather than from
## the kernel that is being held to it. A path at y = 128 runs through texel
## centres, so a texel row's distance from it is a whole number of pixels and
## nothing is read between two of them.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")

## The tip's radius in pixels, on a canvas whose smaller side is 256.
const RADIUS := 20.0
## The straight stroke, along y = 128, and the pixels between two samples.
const FROM := Vector2(40.0, 128.0)
const TO := Vector2(216.0, 128.0)
const SAMPLE_STEP := 4.0
## One step of an 8-bit channel.
const STEP_8_BIT := 1.0 / 255.0
## The door's rectangle shape, the tip's `Shape.RECTANGLE`.
const RECTANGLE := 1
## How far the Gaussian's falloff is let to fall: the fade the tip is given, so
## the edge is a blur wide enough to read.
const FADE := 0.5

## The Gaussian generator's own numbers, the library's `brush_tip.gmacs` and
## `erf.gmacs`, written out so the kernel is held to a second reading.
const GAUSS_BLUR := 0.27044
const GAUSS_TAIL := 2.5
const GAUSS_MIN_FADE := 0.05
const ERF_P := 0.3275911
const ERF_A := [0.254829592, -0.284496736, 1.421413741, -1.453152027, 1.061405429]

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
## Chunk images already read back, by grid position.
var _images: Dictionary = {}


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7
    _brush.settings.color = Color(0.2, 0.4, 0.8, 1.0)
    _brush.settings.opacity = 1.0
    _brush.settings.hardness = 1.0
    _brush.settings.radius = RADIUS / 256.0
    _brush.settings.texture_field = "grain"
    _brush.settings.texture_drift = 0.0
    _brush.settings.thickness = 0.0
    _images.clear()


func after_each() -> void:
    _brush = null
    _images.clear()
    Fixtures.teardown(_surface)
    _surface = null


## A Gaussian tip through a field of nought paints the alpha across the stroke
## the tip's own falloff gives, to within one 8-bit step, at every distance
## from the path inside its rim. A flat grain reads one half, and a shift of
## minus a half makes every texel need nothing, so the cut lets all of the tip
## through and what is left is the tip.
func test_a_gaussian_tip_through_a_field_of_nought_follows_its_own_falloff() -> void:
    _brush.settings.tip.generator = SaDabGeometry.Generator.GAUSS
    _brush.settings.tip.horizontal_fade = FADE
    _brush.settings.tip.vertical_fade = FADE
    _brush.settings.grain_contrast = 0.0
    _brush.settings.strength = -0.5
    _line(FROM, TO, 1.0)
    var radius: float = _brush.settings.tip.half_extent().x
    var middle := int(0.5 * (FROM.x + TO.x))
    var worst := 0.0
    for offset in range(-int(radius) + 2, int(radius) - 1):
        var alpha := _texel(Vector2i(middle, int(FROM.y) + offset)).a
        worst = maxf(worst, absf(alpha - _gaussian(absf(float(offset)), radius, FADE)))
    assert_true(worst <= STEP_8_BIT, "The alpha across the stroke is the Gaussian's, off by %.5f at most" % worst)
    assert_true(
        _gaussian(0.9 * radius, radius, FADE) < 0.9, "and the tip's edge falls, so the read is of a falloff and not of a disc"
    )


## Through a noisy field the tip is still the stroke's outer edge: no texel the
## tip does not reach takes paint, and one it does reach takes either nothing,
## where the field stops it, or the tip's own coverage, never less and never
## more. A tip cut with the field, as the product inside the cut did, gives a
## coverage that a texel's field value moves in and out.
func test_no_texel_outside_the_tips_mask_takes_paint_through_a_noisy_field() -> void:
    _brush.settings.tip.generator = SaDabGeometry.Generator.GAUSS
    _brush.settings.tip.horizontal_fade = FADE
    _brush.settings.tip.vertical_fade = FADE
    _brush.settings.grain_scale = 3.0
    _brush.settings.grain_contrast = 2.5
    _line(FROM, TO, 0.5)
    var radius: float = _brush.settings.tip.half_extent().x
    var outside := 0
    var stopped := 0
    var through := 0
    var wrong := PackedStringArray()
    for x in range(int(FROM.x) - int(radius) - 4, int(TO.x) + int(radius) + 5):
        for y in range(int(FROM.y) - int(radius) - 4, int(FROM.y) + int(radius) + 5):
            var at := Vector2(x, y)
            var distance := at.distance_to(Geometry2D.get_closest_point_to_segment(at, FROM, TO))
            var alpha := _texel(Vector2i(x, y)).a
            if distance >= radius + 1.0:
                outside += 1
                if alpha > 1e-4:
                    wrong.append("texel (%d, %d) is %.1f from the path and has alpha %.4f" % [x, y, distance, alpha])
                continue
            if distance > radius - 1.0:
                continue
            var wanted := _gaussian(distance, radius, FADE)
            if alpha < 1e-4:
                if wanted > 0.5:
                    stopped += 1
                continue
            if wanted > 0.5:
                through += 1
            if absf(alpha - wanted) > STEP_8_BIT:
                wrong.append("texel (%d, %d) alpha %.4f, tip %.4f" % [x, y, alpha, wanted])
    assert_true(outside > 1000, "Texels past the tip's rim were read, %d" % outside)
    assert_true(
        stopped > 100 and through > 100,
        "and the field stopped some of the tip's texels and let others through, %d and %d" % [stopped, through]
    )
    assert_eq(
        wrong.size(),
        0,
        (
            "and every texel past the rim is bare and every texel with paint holds exactly the tip's coverage (%s)"
            % [wrong.slice(0, 3)]
        )
    )


## A flat tip turned 45 degrees to a straight path sweeps a band as wide as the
## tip's footprint across the path, all along the stroke. The tip's section
## through its centre, which is what the nearest point of the path reads, is the
## tip's thin side taken square on and so much narrower, and the band is read as
## the greatest the tip gives over the stretch's points within reach. Painted
## with a fast hand too, a sample twelve pixels from the last on a tip two and a
## half times the size, where an update is a long stretch, the tip's reach is
## several of its points and its corners reach past the box the door cuts an
## ellipse, which a smaller tip's rounding up to the dispatch's groups hid.
func test_a_flat_tip_turned_to_the_path_paints_a_band_as_wide_as_its_footprint() -> void:
    var cases := [[RADIUS, SAMPLE_STEP], [2.5 * RADIUS, 3.0 * SAMPLE_STEP]]
    for each: Array in cases:
        var radius: float = each[0]
        var step: float = each[1]
        Fixtures.teardown(_surface)
        _surface = Fixtures.make_surface()
        _brush.surface = _surface
        _brush.settings.radius = radius / 256.0
        _brush.settings.tip.shape = RECTANGLE
        _brush.settings.tip.ratio = 0.25
        _brush.settings.tip.angle = PI / 4.0
        _brush.settings.grain_contrast = 0.0
        _brush.settings.strength = -0.5
        var from := Vector2(0.4 * radius + 10.0, FROM.y)
        var to := Vector2(256.0 - 0.4 * radius - 10.0, FROM.y)
        _line(from, to, 1.0, step)
        var half_extent: Vector2 = _brush.settings.tip.half_extent()
        var footprint := (half_extent.x + half_extent.y) * sin(PI / 4.0) * 2.0
        var section := 2.0 * minf(half_extent.x, half_extent.y) / sin(PI / 4.0)
        var label := "A tip of radius %.0f at samples %.0f pixels apart" % [radius, step]
        assert_true(
            footprint - section > 8.0,
            (
                "%s: the footprint, %.1f pixels, is wider than the section the nearest point reads, %.1f"
                % [label, footprint, section]
            )
        )
        var narrowest := 1000.0
        var widest := 0.0
        for x in range(int(from.x + half_extent.x) + 4, int(to.x - half_extent.x) - 3):
            var width := _band_at(x)
            narrowest = minf(narrowest, width)
            widest = maxf(widest, width)
        assert_true(
            widest > 0.0 and absf(widest - footprint) <= 2.0,
            "%s paints a band as wide as the footprint, %.1f against %.1f, within two pixels" % [label, widest, footprint]
        )
        assert_true(absf(narrowest - footprint) <= 2.0, "all along the stroke, %.1f at the narrowest" % narrowest)


## A straight stroke from *from* to *to* at *pressure*, a sample every *step*
## pixels and a frame of the pen's time apart.
func _line(from: Vector2, to: Vector2, pressure: float, step_px: float = SAMPLE_STEP) -> void:
    _images.clear()
    var time := 0.0
    _brush.begin_stroke(from, pressure, Vector2.ZERO, time)
    var steps := maxi(1, ceili(from.distance_to(to) / step_px))
    for step in range(1, steps + 1):
        time += 1000.0 / 60.0
        _brush.add_sample(from.lerp(to, float(step) / steps), pressure, Vector2.ZERO, time)
    _brush.end_stroke()


## How wide the painted band is down the column *x*, from its first texel with
## a tenth of alpha to its last, in pixels. A corner of the tip is a point, so
## a texel at the band's very edge is a sliver of the tip and a half alpha
## would cut the band a pixel short of its footprint on either side.
func _band_at(x: int) -> float:
    var first := -1
    var last := -1
    for y in range(int(FROM.y) - 60, int(FROM.y) + 61):
        if _texel(Vector2i(x, y)).a >= 0.1:
            if first < 0:
                first = y
            last = y
    return float(last - first + 1) if first >= 0 else 0.0


## The Gaussian generator's coverage at *distance* pixels from the centre of a
## tip of the given *radius* and *fade*, the library's formula, short of the
## antialiasing ramp on the rim's last pixel, which the callers stay inside.
func _gaussian(distance: float, radius: float, fade: float) -> float:
    if distance > radius:
        return 0.0
    var blur := maxf(GAUSS_MIN_FADE, 1.0 - fade)
    var sigma := GAUSS_BLUR * blur * radius
    var core := radius - GAUSS_TAIL * sigma
    var spread := sqrt(2.0) * sigma
    var peak := 2.0 * _erf(core / spread)
    var lit := _erf((core + distance) / spread) - _erf((distance - core) / spread)
    return clampf(lit / peak, 0.0, 1.0)


## erf by Abramowitz and Stegun 7.1.26, the polynomial the kernel's library
## evaluates.
func _erf(x: float) -> float:
    var a := absf(x)
    var t := 1.0 / (1.0 + ERF_P * a)
    var poly := 0.0
    for index in range(ERF_A.size() - 1, -1, -1):
        poly = t * (float(ERF_A[index]) + poly)
    return signf(x) * (1.0 - poly * exp(-a * a))


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
