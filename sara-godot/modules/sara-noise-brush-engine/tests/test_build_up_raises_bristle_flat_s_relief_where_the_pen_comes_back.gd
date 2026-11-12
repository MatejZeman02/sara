## Build Up at its top raises Bristle Flat's relief where the pen comes back
## over its stroke, and lays no less paint there than at its bottom.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The path of a matched pair of strokes: right, back left and
## right again, one stroke at [constant PRESSURE] with legs of six radii.
## Bristle Flat as it ships less the radius taper paints it with Build Up at
## nought and at one, on [constant SEEDS] seeds. Over the overlapped part, the
## stretch all three legs cross whole within [constant BODY] of the half-width
## either side of the path, the suite reads the layer's mean height off the
## relief, the painted share and the mean alpha. Its strands lie opaque on
## lines a return keeps, so a return cannot thicken them in alpha without
## bending the streaks, and the paint a return adds stands higher instead.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

const PRESET := "Bristle Flat"
const PRESSURE := 0.5
const CANVAS := Vector2i(512, 256)
const RADIUS := 24.0
const SPACING := 4.0
const SAMPLE_MS := 8.0
const SEEDS: Array[int] = [7, 19, 31]
## The legs' ends, a leg six radii long, on the canvas's middle row.
const LEFT := 184.0
const RIGHT := 328.0
const ROW := 128.0
## How far in from where the legs turn the overlapped part starts, in radii,
## so a turn's own round end is not read.
const MARGIN := 1.0
const BODY := 0.6
## The alpha a texel holds to count as painted.
const PAINTED := 0.05
## How many times the overlap's mean height at Build Up nought it holds at
## one. A return at one aims a quarter of the thickness above the brush's own
## height, flat across the strand, and the paint moves towards that aim by its
## alpha, so the overlap stands short of the aim and above the wash. Measured
## at 1.36 on the three seeds.
const RAISED := 1.2

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


## At one the overlap stands at least [constant RAISED] times as high as at
## nought, and the stroke paints no less of its box and no less alpha there.
func test_build_up_at_its_top_raises_the_overlap_and_paints_no_less() -> void:
    var low := _reading(0.0)
    var high := _reading(1.0)
    print(
        (
            # gdlint:ignore=max-line-length
            "Build Up: %s's overlap stands %.4f high at 0 and %.4f at 1, it paints %.3f of its box and %.3f, its mean alpha %.3f and %.3f"
            % [PRESET, low.z, high.z, low.x, high.x, low.y, high.y]
        )
    )
    assert_true(low.z > 0.0, "%s lays a relief at Build Up 0, %.4f over the overlap" % [PRESET, low.z])
    assert_true(
        high.z >= low.z * RAISED,
        "%s's overlap stands %.4f high at Build Up 1, at least %.1f times the %.4f at 0" % [PRESET, high.z, RAISED, low.z]
    )
    assert_true(
        high.x >= low.x, "%s at Build Up 1 paints %.3f of its box, at least the %.3f it paints at 0" % [PRESET, high.x, low.x]
    )
    assert_true(
        high.y >= low.y, "%s's overlap holds a mean alpha of %.3f at Build Up 1, at least the %.3f at 0" % [PRESET, high.y, low.y]
    )


## The painted share of the box, the overlap's mean alpha and its mean height,
## as the mean over [constant SEEDS], at Build Up *rate*.
func _reading(rate: float) -> Vector3:
    var sum := Vector3.ZERO
    for stroke_seed: int in SEEDS:
        _fresh(rate, stroke_seed)
        _paint(PackedVector2Array([Vector2(LEFT, ROW), Vector2(RIGHT, ROW), Vector2(LEFT, ROW), Vector2(RIGHT, ROW)]))
        sum += Vector3(_painted_share(), _overlap_alpha(), _overlap_height())
    return sum / SEEDS.size()


func _painted_share() -> float:
    var painted := 0
    var count := 0
    for x in range(int(LEFT - RADIUS), int(RIGHT + RADIUS)):
        for y in range(int(ROW - RADIUS), int(ROW + RADIUS)):
            count += 1
            if _texel(Vector2i(x, y)).a > PAINTED:
                painted += 1
    return float(painted) / count


func _overlap() -> Rect2i:
    var reach := int(RADIUS * BODY)
    var from := Vector2i(int(LEFT + MARGIN * RADIUS), int(ROW) - reach)
    return Rect2i(from, Vector2i(int(RIGHT - MARGIN * RADIUS) - from.x, 2 * reach + 1))


func _overlap_alpha() -> float:
    var rect := _overlap()
    var total := 0.0
    for x in range(rect.position.x, rect.end.x):
        for y in range(rect.position.y, rect.end.y):
            total += _texel(Vector2i(x, y)).a
    return total / rect.get_area()


## The mean of the surface the view sums over the overlap, in virtual
## millimetres, read off the relief after a full composite.
func _overlap_height() -> float:
    var easel := _surface.easel
    easel.request_full_composite()
    easel.process_pending_composite()
    var heights := easel.relief.heights
    if heights == null:
        return 0.0
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(heights.rid, 0)
    var rect := _overlap()
    var total := 0.0
    for x in range(rect.position.x, rect.end.x):
        for y in range(rect.position.y, rect.end.y):
            total += bytes.decode_half((y * heights.size.x + x) * 2)
    return total / rect.get_area()


## A fresh canvas and the preset as it ships without its radius taper, at
## [constant RADIUS], Build Up *rate* and *stroke_seed*, in black.
func _fresh(rate: float, stroke_seed: int) -> void:
    _albedo.clear()
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = stroke_seed
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == PRESET:
            var untapered := entry.duplicate(true)
            (untapered["pressure"] as Dictionary).erase("radius")
            _brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, untapered)
    _brush.settings.color = Color(0.0, 0.0, 0.0, 1.0)
    _brush.settings.radius = RADIUS / mini(CANVAS.x, CANVAS.y)
    _brush.settings.build_up = rate


## One stroke through the corners of *path* at [constant PRESSURE], a sample
## every [constant SPACING] pixels.
func _paint(path: PackedVector2Array) -> void:
    var clock := 1000.0
    _brush.begin_stroke(path[0], PRESSURE, Vector2.ZERO, clock)
    for leg in range(1, path.size()):
        var from := path[leg - 1]
        var steps := ceili(from.distance_to(path[leg]) / SPACING)
        for i in range(1, steps + 1):
            clock += SAMPLE_MS
            _brush.add_sample(from.lerp(path[leg], float(i) / steps), PRESSURE, Vector2.ZERO, clock)
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
