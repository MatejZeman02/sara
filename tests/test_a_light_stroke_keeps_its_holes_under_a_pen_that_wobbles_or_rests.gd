## A light noise stroke keeps its holes under a pen that wobbles or rests.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Grain Round at a light pressure is painted three ways, a clean straight line
## with a sample every pixel, the same line with each sample moved across it by
## up to 0.8 pixels, and a pen held for 300 samples within 0.8 pixels of one
## spot. The wobbling line's body covers what the clean line's does and the held
## pen's disc what a single tap's does, each within 0.03. Before the change a texel took
## the field again at every update and kept the most of what it read, so the
## wobble's swinging headings filled the line to 0.73 against the clean 0.31 and
## a held pen painted a solid disc.
##
## Coverage is the mean alpha read back off the layer over the body, the texels
## a tip's radius in from either end of the line and three pixels in from its
## sides, and over the disc three pixels in from the tip's rim. Each wobble is
## painted under three seeds, and the clean line and the tap are held to leave
## holes, so a stroke painted solid every way cannot pass.
##
## A Grain is read on the canvas, in the frame of the stroke's first point and
## the heading its path takes over its first few pixels (`field_axis` in
## `dab_list/noise_stretch.gd`). A wobble tilts that heading, by 3.5 degrees
## under seed 13, so over the line's 256 pixels the wobbling line reads a strip
## of the grain up to 15 pixels across from the clean line's. Strips of the same
## grain cover from 0.24 to 0.31 under stroke seeds 1 to 7, past the 0.03 held
## here, so a line compared against another strip fails on the grain and not on
## its holes. Each wobble is therefore held against a clean line that takes the
## wobble's samples until the stroke has taken its frame and runs straight
## after, which reads the same strip. With the frame held level the wobbling
## line covers what the clean one does within 0.0005 under every seed.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

const CANVAS := Vector2i(384, 256)
## The preset's radius as a share of the canvas's smaller side, the 25.6 pixels
## a typical brush size, and the light pressure.
const RADIUS := 0.1
const PRESSURE := 0.2
## How far a sample strays, and how far apart two coverages may be.
const WOBBLE := 0.8
const WITHIN := 0.03
## The line, a sample a pixel along y = 128, and the held pen's spot and samples.
const FROM := Vector2(64.0, 128.0)
const LENGTH := 256
const SPOT := Vector2(192.0, 128.0)
const HELD := 300
## The texels in from the tip's rim a coverage is read over.
const INSET := 3.0
const SEEDS: Array[int] = [11, 12, 13]

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
## Chunk images already read back, by grid position.
var _images: Dictionary = {}
## The samples the last line took before its Grain had a frame.
var _framed: int = 0


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == "Grain Round":
            _brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
    _brush.settings.radius = RADIUS
    # Grain Round tapers with the pen, which
    # would paint this light pressure at a third of the radius it is
    # tested at. What is held here is the grain, so the taper is turned off.
    _brush.settings.size_option.enabled = false
    _brush.settings.color = Color(0.0, 0.0, 0.0, 1.0)
    _images.clear()


func after_each() -> void:
    _brush = null
    _images.clear()
    Fixtures.teardown(_surface)
    _surface = null


func test_a_wobbling_line_covers_what_a_clean_line_covers() -> void:
    var straight := _line(PackedFloat32Array(), 0)
    assert_true(straight > 0.1 and straight < 0.6, "the clean line leaves holes, %.4f" % straight)
    for rng_seed: int in SEEDS:
        var rng := RandomNumberGenerator.new()
        rng.seed = rng_seed
        var acrosses := PackedFloat32Array()
        for x in LENGTH:
            acrosses.append(rng.randf_range(-WOBBLE, WOBBLE))
        _clear()
        var wobbly := _line(acrosses, LENGTH)
        _clear()
        var clean := _line(acrosses, _framed)
        assert_true(
            absf(wobbly - clean) <= WITHIN,
            "the wobbling line under seed %d covers %.4f against the clean line's %.4f" % [rng_seed, wobbly, clean]
        )


func test_a_held_pen_covers_what_a_tap_covers() -> void:
    _brush.begin_stroke(SPOT, PRESSURE)
    _brush.end_stroke()
    var tap := _disc()
    assert_true(tap > 0.1 and tap < 0.6, "the tap leaves holes, %.4f" % tap)
    for rng_seed: int in SEEDS:
        var rng := RandomNumberGenerator.new()
        rng.seed = rng_seed
        _clear()
        _brush.begin_stroke(SPOT, PRESSURE)
        for i in HELD:
            _brush.add_sample(SPOT + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, WOBBLE), PRESSURE)
        _brush.end_stroke()
        var held := _disc()
        assert_true(
            absf(held - tap) <= WITHIN, "the pen held under seed %d covers %.4f against the tap's %.4f" % [rng_seed, held, tap]
        )


## A fresh surface under the brush.
func _clear() -> void:
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    _brush.surface = _surface
    _images.clear()


func _radius() -> float:
    return RADIUS * mini(CANVAS.x, CANVAS.y)


## The line painted, its first *moved* samples moved across it by *acrosses*
## and the rest straight, and the coverage of its body. Notes in
## [member _framed] how many samples the stroke took before it had the frame a
## Grain is read in.
func _line(acrosses: PackedFloat32Array, moved: int) -> float:
    _framed = 0
    _brush.begin_stroke(FROM, PRESSURE)
    for x in range(1, LENGTH + 1):
        var across := acrosses[x - 1] if x <= moved else 0.0
        _brush.add_sample(FROM + Vector2(x, across), PRESSURE)
        if _framed == 0 and _brush.dab_list.stretch.field_axis != Vector2.ZERO:
            _framed = x
    _brush.end_stroke()
    var r := _radius()
    var inside := int(r - INSET)
    var total := 0.0
    var count := 0
    for x in range(int(FROM.x + r), int(FROM.x + LENGTH - r)):
        for y in range(int(FROM.y) - inside, int(FROM.y) + inside + 1):
            total += _texel(Vector2i(x, y)).a
            count += 1
    return total / count


## The coverage of the disc a tap at the spot paints.
func _disc() -> float:
    var inside := _radius() - INSET
    var total := 0.0
    var count := 0
    for y in range(int(SPOT.y - inside), int(SPOT.y + inside) + 1):
        for x in range(int(SPOT.x - inside), int(SPOT.x + inside) + 1):
            if Vector2(x, y).distance_to(SPOT) > inside:
                continue
            total += _texel(Vector2i(x, y)).a
            count += 1
    return total / count


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
