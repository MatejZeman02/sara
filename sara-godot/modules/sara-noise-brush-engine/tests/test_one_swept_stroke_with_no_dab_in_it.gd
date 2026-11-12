## The noise brush paints one swept stroke with no dab in it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The strokes are painted through the tool's own public calls on a real
## surface, a sample every few pixels as a pen lays them, and read back texel
## by texel, colour and height. A dab walk shows its period where a texel's
## coverage depends on how far it is from the nearest dab, so the straight
## stroke is read at nine tenths of its radius under a soft tip, where the
## coverage still falls, and in the relief, which climbs with every evaluation
## a texel gets and so shows a joint between two updates that the colour's
## ceiling hides.
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
## One step of an 8-bit channel, and a twentieth of one. The dab walk this
## stroke replaced kept the alpha along the straight stroke inside one step,
## 0.56905 to 0.57075, because twenty dabs crossed every texel, but not inside
## a twentieth of one, and its height ran from 0.339 to 0.358 mm.
const STEP_8_BIT := 1.0 / 255.0
const TWENTIETH_STEP := STEP_8_BIT / 20.0
## Virtual millimetres at full, and the most two texels of one height may
## differ by in the half float the height is kept in at about this height.
const THICKNESS := 1.0
const HALF_FLOAT_STEP := 0.0005

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7
    _brush.settings.color = Color(0.2, 0.4, 0.8, 1.0)
    _brush.settings.opacity = 1.0
    _brush.settings.radius = RADIUS / 256.0
    # A flat field, the grain at no contrast, which reads one half everywhere.
    _brush.settings.texture_field = "grain"
    _brush.settings.grain_contrast = 0.0
    _brush.settings.thickness = 0.0


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null


## A straight stroke at a constant pressure through a flat field: along a line
## parallel to it at nine tenths of the radius, the alpha is one number between
## the two caps, to within an 8-bit step, and so is the height. The tip is the
## Soft Curve's straight falloff, so nine tenths of the radius is partly covered
## and a texel's alpha says how near the path it is. The Hardness is one, since
## below one the grain thins towards the rim and a
## stroke at nought lays next to nothing that far out.
func test_a_straight_stroke_has_no_period_along_it() -> void:
    _brush.settings.tip.generator = SaDabGeometry.Generator.SOFT
    _brush.settings.hardness = 1.0
    _brush.settings.strength = 0.5
    _brush.settings.strength_option.enabled = false
    _brush.settings.thickness = THICKNESS
    _line(FROM, TO, 1.0)
    var layer := _surface.easel.document.active_layer
    var images := {}
    var heights := {}
    for side: float in [-1.0, 1.0]:
        var y := int(FROM.y + side * 0.9 * RADIUS)
        var alphas := PackedFloat32Array()
        var stood := PackedFloat32Array()
        for x in range(int(FROM.x + RADIUS), int(TO.x - RADIUS) + 1):
            alphas.append(_texel(layer, Vector2i(x, y), images).a)
            stood.append(_height(layer, Vector2i(x, y), heights))
        var low: float = Array(alphas).min()
        var high: float = Array(alphas).max()
        assert_true(
            low > 0.05 and high < 0.95, "At nine tenths of the radius the tip is partly covered, alpha %.4f to %.4f" % [low, high]
        )
        assert_true(
            high - low <= STEP_8_BIT, "and the alpha is one number between the caps, %.5f to %.5f, side %d" % [low, high, side]
        )
        assert_true(high - low <= TWENTIETH_STEP, "closer than any dab walk kept it, %.5f to %.5f" % [low, high])
        var lowest: float = Array(stood).min()
        var highest: float = Array(stood).max()
        assert_true(lowest > 0.01, "The stroke stood paint there, %.4f mm at least" % lowest)
        assert_true(highest - lowest <= HALF_FLOAT_STEP, "and the height is one number too, %.4f to %.4f mm" % [lowest, highest])


## A stroke at Opacity 50 % that crosses itself reads one alpha at the crossing
## and on either arm: a texel the path covers twice takes the stroke once.
func test_a_stroke_that_crosses_itself_reads_one_alpha() -> void:
    _brush.settings.opacity = 0.5
    _brush.settings.hardness = 1.0
    _brush.settings.strength = 0.0
    _brush.settings.strength_option.enabled = false
    var path := PackedVector2Array(
        [Vector2(40.0, 128.0), Vector2(200.0, 128.0), Vector2(200.0, 60.0), Vector2(120.0, 60.0), Vector2(120.0, 210.0)]
    )
    _path(path, 1.0)
    var layer := _surface.easel.document.active_layer
    var images := {}
    var crossing := _texel(layer, Vector2i(120, 128), images).a
    var first_arm := _texel(layer, Vector2i(70, 128), images).a
    var second_arm := _texel(layer, Vector2i(120, 180), images).a
    assert_almost_eq(first_arm, 0.5, STEP_8_BIT, "The first arm stands at the stroke's opacity")
    assert_almost_eq(second_arm, first_arm, STEP_8_BIT, "and so does the arm that crosses it")
    assert_almost_eq(crossing, first_arm, STEP_8_BIT, "and the crossing, which the path covers twice")


## A tap with no motion is a stretch of one point and paints the tip once, its
## whole disc and nothing past it.
func test_a_tap_paints_the_tip_once() -> void:
    _brush.settings.hardness = 1.0
    _brush.settings.strength = 0.0
    _brush.settings.strength_option.enabled = false
    var at := Vector2(100.0, 100.0)
    _brush.begin_stroke(at, 1.0)
    _brush.end_stroke()
    var layer := _surface.easel.document.active_layer
    var images := {}
    assert_almost_eq(_texel(layer, Vector2i(at), images).a, 1.0, STEP_8_BIT, "The tap paints its centre")
    assert_almost_eq(_texel(layer, Vector2i(at + Vector2(0.0, RADIUS - 2.0)), images).a, 1.0, STEP_8_BIT, "and its disc")
    assert_almost_eq(_texel(layer, Vector2i(at + Vector2(RADIUS + 2.0, 0.0)), images).a, 0.0, 1e-4, "and nothing past it")


## The stroke's last update paints the end cap the others leave to the next,
## so a stroke ends in the tip's own round end, as far past its last sample as
## it starts before its first.
func test_a_stroke_ends_in_the_tips_round_end() -> void:
    _brush.settings.hardness = 1.0
    _brush.settings.strength = 0.0
    _brush.settings.strength_option.enabled = false
    _line(FROM, TO, 1.0)
    var layer := _surface.easel.document.active_layer
    var images := {}
    for reach: float in [RADIUS - 2.0, 0.7 * RADIUS]:
        var start := _texel(layer, Vector2i(FROM - Vector2(reach, 0.0)), images).a
        var end := _texel(layer, Vector2i(TO + Vector2(reach, 0.0)), images).a
        assert_almost_eq(start, 1.0, STEP_8_BIT, "The press paints %.0f pixels behind the stroke's start" % reach)
        assert_almost_eq(end, start, STEP_8_BIT, "and the end cap as far past its end")
    var diagonal := Vector2(RADIUS - 3.0, RADIUS - 3.0).normalized() * (RADIUS - 2.0)
    assert_almost_eq(
        _texel(layer, Vector2i(TO + diagonal), images).a, 1.0, STEP_8_BIT, "The cap is round, painted on its diagonal"
    )
    assert_almost_eq(
        _texel(layer, Vector2i(TO + Vector2(RADIUS, RADIUS) * 0.9), images).a, 0.0, 1e-4, "and not in the corner of its box"
    )


## A mirrored stroke is the path mirrored, not its box moved: a diagonal under
## a vertical mirror paints the other diagonal across the axis.
func test_a_mirror_paints_the_stroke_mirrored() -> void:
    _brush.settings.hardness = 1.0
    _brush.settings.strength = 0.0
    _brush.settings.strength_option.enabled = false
    _brush.settings.radius = 4.0 / 256.0
    var symmetry := _surface.easel.document.symmetry
    symmetry.center = Vector2(128.0, 128.0)
    symmetry.mirror_horizontal = true
    _line(Vector2(40.0, 40.0), Vector2(100.0, 100.0), 1.0)
    symmetry.mirror_horizontal = false
    var layer := _surface.easel.document.active_layer
    var images := {}
    assert_almost_eq(_texel(layer, Vector2i(50, 50), images).a, 1.0, STEP_8_BIT, "The stroke paints its own diagonal")
    assert_almost_eq(
        _texel(layer, Vector2i(206, 50), images).a, 1.0, STEP_8_BIT, "and the mirror the diagonal reflected across the axis"
    )
    assert_almost_eq(_texel(layer, Vector2i(166, 50), images).a, 0.0, 1e-4, "and not the same diagonal moved over")


## A straight stroke from *from* to *to* at *pressure*, a sample every
## [constant SAMPLE_STEP] pixels and a frame of the pen's time apart.
func _line(from: Vector2, to: Vector2, pressure: float) -> void:
    _path(PackedVector2Array([from, to]), pressure)


## A stroke along the polyline *path* at *pressure*, sampled as [method _line]
## samples.
func _path(path: PackedVector2Array, pressure: float) -> void:
    var time := 0.0
    _brush.begin_stroke(path[0], pressure, Vector2.ZERO, time)
    for leg in range(1, path.size()):
        var from := path[leg - 1]
        var to := path[leg]
        var steps := maxi(1, ceili(from.distance_to(to) / SAMPLE_STEP))
        for step in range(1, steps + 1):
            time += 1000.0 / 60.0
            _brush.add_sample(from.lerp(to, float(step) / steps), pressure, Vector2.ZERO, time)
    _brush.end_stroke()


## The layer's colour at *pixel*, transparent where it holds no chunk. *images*
## keeps each chunk read once.
func _texel(layer: SaLayer, pixel: Vector2i, images: Dictionary) -> Color:
    var side := _side(layer)
    var grid := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
    if not layer.chunks.has(grid):
        return Color.TRANSPARENT
    if not images.has(grid):
        @warning_ignore("static_called_on_instance")
        images[grid] = SaExport.get_texture_image_float(layer.get_field(grid))
    return (images[grid] as Image).get_pixelv(pixel - grid * side)


## The layer's height at *pixel* in virtual millimetres, nought where it holds
## none. *read* keeps each chunk's bytes read once.
func _height(layer: SaLayer, pixel: Vector2i, read: Dictionary) -> float:
    var side := _side(layer)
    var grid := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
    var texture := layer.get_field(grid, SaFieldSpec.HEIGHT)
    if texture == null:
        return 0.0
    if not read.has(grid):
        read[grid] = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local := pixel - grid * side
    return (read[grid] as PackedByteArray).decode_half((local.y * texture.size.x + local.x) * 2)


## The side of the layer's chunks in pixels, asked of a chunk rather than
## assumed, by hard rule 3 (sparse chunks).
func _side(layer: SaLayer) -> int:
    for grid: Vector2i in layer.chunks:
        return (layer.chunks[grid] as SaChunk).pixel_size()
    return 1
