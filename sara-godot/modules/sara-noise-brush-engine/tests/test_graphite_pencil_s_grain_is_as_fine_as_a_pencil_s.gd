## Graphite Pencil's grain is as fine as a pencil's.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A pencil on paper catches the paper's tooth, specks a small share of the
## line's width, and Graphite Pencil's line at size 21.6 must not break
## into blotches about as wide as the line. The preset as it ships, at
## a radius of [constant RADIUS] pixels and a press of [constant PRESSURE],
## paints one level line in an ochre over a clear
## layer, and the lightness the
## line would show over white paper is read along every row of the line's
## inner half. Its autocorrelation length, the first lag at which the
## autocorrelation about the row's mean falls under 1/e, averaged over those
## rows, is at most [constant SHARE] of the line's width, the span across
## which the line lays paint.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

const PRESET := "Graphite Pencil"
const PRESSURE := 0.6
const CANVAS := Vector2i(1024, 256)
## The radius of size 21.6, which the options bar shows as
## Radius 10.8 px, in document pixels.
const RADIUS := 10.8
const LENGTH := 600
const FROM := Vector2(212.0, 128.0)
const SPACING := 2.0
const SAMPLE_MS := 8.0
const SEED := 7
## The ochre of the line.
const OCHRE := Color(0.8, 0.55, 0.2, 1.0)
## The alpha a texel holds to count as inside the line's span.
const LAID := 0.05
## The greatest autocorrelation length as a share of the line's width, the
## fifth the note asks for.
const SHARE := 0.2
## How far from either end of the line the reading starts, so the stroke's
## first and last dabs, which a lift and a press shape, are not read.
const MARGIN := 40

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
var _albedo: Dictionary = {}


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)


func after_each() -> void:
    _brush = null
    _albedo.clear()
    Fixtures.teardown(_surface)
    _surface = null


## The line's lightness changes over at most a fifth of its width.
func test_the_grain_along_the_line_is_at_most_a_fifth_of_its_width() -> void:
    _use()
    _stroke()
    var width := _width()
    assert_true(width > 4.0, "the line lays paint across %.1f px, a line and not nothing" % width)
    var lengths := PackedFloat32Array()
    var half := int(width / 4.0)
    for dy in range(-half, half + 1):
        var length := _correlation_length(_lightness(int(FROM.y) + dy))
        if length > 0.0:
            lengths.append(length)
    assert_true(lengths.size() > 0, "some row of the line's inner half varies at all")
    var mean := _mean(lengths)
    print(
        (
            "Graphite Pencil at size %.1f, press %.1f: width %.1f px, grain length %.2f px over %d rows, %.3f of the width"
            % [2.0 * RADIUS, PRESSURE, width, mean, lengths.size(), mean / width]
        )
    )
    assert_true(
        mean <= SHARE * width,
        "the grain runs %.2f px along the line, at most %.2f, a fifth of its %.1f px width" % [mean, SHARE * width, width]
    )


## The median, over the columns read, of the span from the outermost texel
## laid on one side of the path to the outermost on the other.
func _width() -> float:
    var spans := PackedFloat32Array()
    var reach := int(RADIUS) + 6
    for x: int in _columns():
        var top := 0
        var bottom := 0
        for d in range(reach, -1, -1):
            if _texel(Vector2i(x, int(FROM.y) - d)).a >= LAID:
                top = d
                break
        for d in range(reach, -1, -1):
            if _texel(Vector2i(x, int(FROM.y) + d)).a >= LAID:
                bottom = d
                break
        spans.append(top + bottom + 1)
    spans.sort()
    return spans[floori(spans.size() / 2.0)]


## The lightness of row *y* over white paper, one to a column read.
func _lightness(y: int) -> PackedFloat32Array:
    var row := PackedFloat32Array()
    for x: int in _columns():
        var texel := _texel(Vector2i(x, y))
        var paint := Color(texel.r, texel.g, texel.b).get_luminance()
        row.append(lerpf(1.0, paint, texel.a))
    return row


func _columns() -> Array:
    return range(int(FROM.x) + MARGIN, int(FROM.x) + LENGTH - MARGIN)


## The first lag at which *values*' autocorrelation about their mean falls
## under 1/e, read between whole lags, or nought for a row with no change.
static func _correlation_length(values: PackedFloat32Array) -> float:
    var mean := _mean(values)
    var power := 0.0
    for v: float in values:
        power += (v - mean) * (v - mean)
    if power <= 1e-6:
        return 0.0
    var threshold := exp(-1.0)
    var before := 1.0
    for lag in range(1, floori(values.size() / 2.0)):
        var sum := 0.0
        for i in range(values.size() - lag):
            sum += (values[i] - mean) * (values[i + lag] - mean)
        var here := sum / power
        if here < threshold:
            return lag - 1 + (before - threshold) / maxf(before - here, 1e-6)
        before = here
    return values.size() / 2.0


static func _mean(values: PackedFloat32Array) -> float:
    var sum := 0.0
    for v: float in values:
        sum += v
    return sum / maxi(values.size(), 1)


## The preset as it ships at [constant RADIUS] and [constant SEED], in
## [constant OCHRE].
func _use() -> void:
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = SEED
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == PRESET:
            _brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
    _brush.settings.color = OCHRE
    _brush.settings.radius = RADIUS / mini(CANVAS.x, CANVAS.y)


## The level line of [constant LENGTH] at [constant PRESSURE], a sample every
## [constant SPACING] pixels.
func _stroke() -> void:
    var to := FROM + Vector2(LENGTH, 0.0)
    var clock := 1000.0
    _brush.begin_stroke(FROM, PRESSURE, Vector2.ZERO, clock)
    var steps := ceili(LENGTH / SPACING)
    for i in range(1, steps + 1):
        clock += SAMPLE_MS
        _brush.add_sample(FROM.lerp(to, float(i) / steps), PRESSURE, Vector2.ZERO, clock)
    _brush.end_stroke()


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
