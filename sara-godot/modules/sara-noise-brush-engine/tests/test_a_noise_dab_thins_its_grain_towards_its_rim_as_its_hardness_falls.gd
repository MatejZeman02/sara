## A noise dab thins its grain towards its rim as its hardness falls.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## At hardness 1, 0.5, 0.2 and 0 alike a noise stroke's change from the ground
## was flat out to its edge and nothing past it, so rows of strokes read as
## stripes. Below a Hardness of one the kernel now raises the value a texel
## needs of the pressure the further out it lies past Hardness of the way to
## the rim, so the grain thins to nothing there. Straight Grain strokes of
## radius 40 are painted through the tool's own public calls on a real surface
## and read back texel by texel, and each is cut into bands four pixels wide by
## their distance from the path. A band's mean alpha is its mean change from
## the ground over the colour's own distance from it, since the stroke lays one
## colour on a bare layer. The path at y = 128 runs through texel centres, so a
## row's distance from it is a whole number of pixels.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")

## The canvas, wide enough that the read stays a radius and more off both caps.
const CANVAS := Vector2i(512, 256)
## The tip's radius in pixels, a typical brush radius.
const RADIUS := 40.0
## The straight stroke along y = 128, the columns read, well inside its two
## caps, and the pixels between two samples.
const FROM := Vector2(60.0, 128.0)
const TO := Vector2(452.0, 128.0)
const READ_FROM := 110
const READ_TO := 402
const SAMPLE_STEP := 4.0
## How wide a band is, in pixels, so the radius is ten bands.
const BAND := 4
## A pressure that leaves the grain's holes open, so a band's mean is the share
## of the grain it keeps, and a full press, which fills a hard stroke solid.
const LIGHT := 0.5
const FULL := 1.0

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
## Chunk images already read back, by grid position.
var _images: Dictionary = {}


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7
    _brush.settings.color = Color(0.2, 0.4, 0.8, 1.0)
    _brush.settings.opacity = 1.0
    _brush.settings.radius = RADIUS / float(mini(CANVAS.x, CANVAS.y))
    _brush.settings.texture_field = "grain"
    _brush.settings.texture_drift = 0.0
    _brush.settings.thickness = 0.0
    _images.clear()


func after_each() -> void:
    _brush = null
    _images.clear()
    Fixtures.teardown(_surface)
    _surface = null


## At hardness 1 the grain is flat out to the edge: every band out to the last
## one inside the rim keeps the share of the grain the band down the path
## keeps, to within the grain's own scatter over a band, and the rim's band,
## whose last pixel is the tip's antialiasing, keeps most of it. The dab is the
## one it was, so the stroke's edge is where the grain stops dead.
func test_a_hard_stroke_keeps_its_grain_flat_out_to_its_edge() -> void:
    var means := _bands_of_a_stroke(1.0, LIGHT)
    var middle: float = means[0]
    assert_true(
        middle > 0.2 and middle < 0.9,
        "A light hard stroke keeps some of its grain and opens some holes, %.3f down the path (%s)" % [middle, _said(means)]
    )
    for band in range(1, means.size() - 1):
        var mean: float = means[band]
        assert_true(
            absf(mean - middle) <= 0.15 * middle,
            (
                "and the band %d to %d px out keeps as much as the middle, %.3f against %.3f"
                % [band * BAND, (band + 1) * BAND, mean, middle]
            )
        )
    var rim: float = means[means.size() - 1]
    assert_true(
        rim >= 0.7 * middle,
        (
            "and the rim's band keeps most of it, %.3f against %.3f, so the grain stops dead at the edge (%s)"
            % [rim, middle, _said(means)]
        )
    )


## At hardness 0 the grain thins from the path out: down the path the stroke
## keeps what a hard one keeps there or more, at two thirds of the radius it
## has already fallen, every band past that keeps less than the one inside it,
## and the rim's band keeps next to nothing. So the fall runs over at least the
## outer third of the radius.
func test_a_soft_stroke_thins_its_grain_over_the_outer_third_to_nothing() -> void:
    var hard := _bands_of_a_stroke(1.0, LIGHT)
    _reset()
    var means := _bands_of_a_stroke(0.0, LIGHT)
    _assert_thins(means, "A light soft stroke")
    assert_true(
        means[0] >= hard[0],
        "and down the path it keeps at least what a hard stroke keeps, %.3f against %.3f" % [means[0], hard[0]]
    )


## A full press fills a hard stroke solid, and at hardness 0 the same press
## still thins to nothing at the rim, since no pressure reaches the value the
## rim asks for. So it is the rim and not a lighter touch that thins the grain.
func test_a_full_press_fills_a_hard_stroke_and_still_thins_a_soft_one() -> void:
    var hard := _bands_of_a_stroke(1.0, FULL)
    for band in range(0, hard.size() - 1):
        assert_true(
            float(hard[band]) > 0.99,
            "A full hard press fills the band %d to %d px out, %.3f" % [band * BAND, (band + 1) * BAND, hard[band]]
        )
    _reset()
    _assert_thins(_bands_of_a_stroke(0.0, FULL), "A full soft press")


## A hardness between thins only past its own share of the radius: at 0.5 the
## bands inside half the radius keep what the middle keeps, and the rim's band
## next to nothing, as a round's soft edge starts where its hardness says.
func test_a_hardness_of_a_half_thins_only_the_outer_half() -> void:
    var means := _bands_of_a_stroke(0.5, LIGHT)
    var middle: float = means[0]
    for band in range(1, 4):
        var mean: float = means[band]
        assert_true(
            absf(mean - middle) <= 0.15 * middle,
            (
                "At hardness 0.5 the band %d to %d px out keeps as much as the middle, %.3f against %.3f"
                % [band * BAND, (band + 1) * BAND, mean, middle]
            )
        )
    var rim: float = means[means.size() - 1]
    assert_true(rim <= 0.1 * middle, "and the rim's band next to nothing, %.3f against %.3f (%s)" % [rim, middle, _said(means)])


## The bands of a soft stroke, *means*, thin over at least the outer third of
## the radius to next to nothing at the rim.
func _assert_thins(means: Array, label: String) -> void:
    var middle: float = means[0]
    assert_true(middle > 0.2, "%s lays paint down its path, %.3f (%s)" % [label, middle, _said(means)])
    var third := int(floor((2.0 * RADIUS / 3.0) / BAND)) - 1
    var at_two_thirds: float = means[third]
    assert_true(
        at_two_thirds < 0.9 * middle,
        (
            "%s has thinned by the band %d to %d px out, two thirds of the radius, %.3f against %.3f"
            % [label, third * BAND, (third + 1) * BAND, at_two_thirds, middle]
        )
    )
    for band in range(third + 1, means.size()):
        var mean: float = means[band]
        var inside: float = means[band - 1]
        var thinner := mean < inside or (inside <= 0.001 and mean <= inside)
        assert_true(
            thinner,
            (
                "and the band %d to %d px out keeps less than the one inside it, %.4f against %.4f"
                % [band * BAND, (band + 1) * BAND, mean, inside]
            )
        )
    var rim: float = means[means.size() - 1]
    assert_true(rim <= 0.1 * middle, "and the rim's band keeps next to nothing, %.3f against %.3f" % [rim, middle])


## The mean alpha of each band four pixels wide out from the path of a stroke
## laid at *hardness* and *pressure*, from the path to the rim, both sides of
## the path taken together and every column the read spans.
func _bands_of_a_stroke(hardness: float, pressure: float) -> Array:
    _brush.settings.hardness = hardness
    _line(pressure)
    var sums: Array[float] = []
    var counts: Array[int] = []
    var count := int(RADIUS / BAND)
    for band in range(count):
        sums.append(0.0)
        counts.append(0)
    for x in range(READ_FROM, READ_TO):
        for offset in range(-int(RADIUS) + 1, int(RADIUS)):
            var band := floori(absi(offset) / float(BAND))
            sums[band] += _texel(Vector2i(x, int(FROM.y) + offset)).a
            counts[band] += 1
    var means := []
    for band in range(count):
        means.append(sums[band] / float(maxi(counts[band], 1)))
    return means


## A fresh surface for the next stroke, so the two never wash over each other.
func _reset() -> void:
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    _brush.surface = _surface
    _images.clear()


## A straight stroke along the path at *pressure*, a sample every
## `SAMPLE_STEP` pixels and a frame of the pen's time apart.
func _line(pressure: float) -> void:
    _images.clear()
    var time := 0.0
    _brush.begin_stroke(FROM, pressure, Vector2.ZERO, time)
    var steps := maxi(1, ceili(FROM.distance_to(TO) / SAMPLE_STEP))
    for step in range(1, steps + 1):
        time += 1000.0 / 60.0
        _brush.add_sample(FROM.lerp(TO, float(step) / steps), pressure, Vector2.ZERO, time)
    _brush.end_stroke()


## The bands' means as one line, from the path out, for a failure's message.
func _said(means: Array) -> String:
    var parts := PackedStringArray()
    for mean: float in means:
        parts.append("%.3f" % mean)
    return ", ".join(parts)


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
