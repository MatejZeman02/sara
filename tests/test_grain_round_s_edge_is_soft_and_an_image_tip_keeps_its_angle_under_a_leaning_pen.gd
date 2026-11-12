## Grain Round's edge is soft and an image tip keeps its angle under a leaning
## pen.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Grain Round's round mask must not be strict, with harsh edges where no
## opacity is in play, and a brush tip used instead must stay upright rather
## than rotate with the pen. The row's clauses, each a test: the stretch keeps
## a picture tip's angle and answers a round tip as it did, a stroke through a
## picture under a turning lean lays every point at the tip's own angle, and a
## Grain Round tap falls off before its rim. The angles and the tap's centre
## and radius are read off the points the brush handed its stretch, and the
## alpha off the layer, so each is what the kernel was given or wrote.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const NoiseStretchScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_stretch.gd")
const NoiseTipScript = preload("res://modules/sara-noise-brush-engine/tip/noise_tip.gd")
const TipRowScript = preload("res://modules/sara-noise-brush-engine/tip/tip_row.gd")

## The row's picture, its angle and the lean of the row's first clause.
const CORNER := "res://tips/corner.png"
const ANGLE := 0.3
const LEAN := Vector2(30.0, 30.0)
const AMOUNT := 0.5

## The canvas the strokes are painted on, large enough that Grain Round's
## radius, a fiftieth of the smaller side, is twenty pixels.
const CANVAS := Vector2i(1024, 1024)
const CENTRE := Vector2(512.0, 512.0)
## How far the pen leans in degrees while its azimuth turns, and the samples
## the turn takes.
const TILT := 45.0
const SAMPLES := 24
## How far a texel's centre may lie from a ring's radius in pixels and be read
## as on it.
const RING_WIDTH := 0.35

var _surface: SaSurface = null
## Chunk images already read back, by grid position.
var _images: Dictionary = {}


## A stretch that remembers every point the brush hands it, before it holds
## any back, so a test reads what each point was laid with.
class RecordingStretch:
    extends "res://modules/sara-noise-brush-engine/dab_list/noise_stretch.gd"

    var seen: Array[PackedFloat32Array] = []

    func add(values: PackedFloat32Array, reach: Rect2, tip_reach: float = 0.0) -> void:
        seen.append(values.duplicate())
        super.add(values, reach, tip_reach)


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    _images.clear()
    SaBrushTipMask.forget_loaded_elsewhere()


func after_each() -> void:
    _images.clear()
    SaBrushTipMask.forget_loaded_elsewhere()
    Fixtures.teardown(_surface)
    _surface = null


## The first clause: a picture tip of equal half extents at 0.3 radians under
## a lean of (30, 30) degrees at an amount of 0.5 comes back at 0.3, and a
## round tip gets the answer it got before the row, the ellipse along the lean.
func test_the_stretch_keeps_a_picture_tip_s_angle_and_leans_a_round_one() -> void:
    var picture: Resource = NoiseBrushSettingsScript.new().tip
    picture.generator = SaDabGeometry.Generator.IMAGE
    picture.image_path = CORNER
    var half_extent := Vector2(10.0, 10.0)
    assert_true(NoiseTipScript.shows_angle(picture, picture.effective_generator(), half_extent), "A picture shows its angle")
    var kept: Vector3 = NoiseTipScript.stretch(half_extent, ANGLE, LEAN, AMOUNT, true)
    assert_almost_eq(kept.z, ANGLE, 0.00001, "The picture keeps its own angle under the lean, %s" % kept)
    var grow := AMOUNT * NoiseBrushSettingsScript.TILT_STRETCH
    assert_true(kept.x > 10.0 and kept.x < 10.0 * (1.0 + grow), "and the lean stretches it along its own x, %.3f" % kept.x)
    assert_true(kept.y > 10.0 and kept.y < 10.0 * (1.0 + grow), "and its own y, %.3f" % kept.y)
    var turned: Vector3 = NoiseTipScript.stretch(half_extent, ANGLE, LEAN, AMOUNT)
    assert_true(absf(turned.z - ANGLE) > 0.4, "The answer before the row turned it to the lean, %.3f" % turned.z)

    var round_tip: Resource = NoiseBrushSettingsScript.new().tip
    assert_false(NoiseTipScript.shows_angle(round_tip, round_tip.effective_generator(), half_extent), "A circle shows none")
    var ellipse := Vector2(10.0, 6.0)
    assert_true(NoiseTipScript.shows_angle(round_tip, round_tip.effective_generator(), ellipse), "and an ellipse shows its own")
    var leaned: Vector3 = NoiseTipScript.stretch(half_extent, ANGLE, LEAN, AMOUNT, false)
    assert_true(
        leaned.is_equal_approx(NoiseTipScript.stretch(half_extent, ANGLE, LEAN, AMOUNT)), "A round tip gets today's answer"
    )
    assert_almost_eq(leaned.x, 10.0 * (1.0 + grow), 0.001, "the circle grown along the lean, %s" % leaned)
    assert_almost_eq(leaned.y, 10.0, 0.001, "and as wide across it")
    assert_almost_eq(absf(sin(leaned.z - LEAN.angle())), 0.0, 0.001, "its long axis down the lean")


## The second clause: a stroke through `tips/corner.png` while the lean's
## azimuth turns through 90 degrees lays every point of its stretch at the
## tip's own angle, and the lean still stretches it.
func test_a_stroke_through_a_picture_keeps_its_angle_while_the_lean_turns() -> void:
    var brush := _brush()
    brush.settings.texture_field = "grain"
    brush.settings.radius = 40.0 / float(CANVAS.y)
    assert_true(brush.load_tip(CORNER), "The L loads")
    brush.settings.tip.angle = ANGLE
    var stretch := RecordingStretch.new()
    brush.dab_list.stretch = stretch
    var from := CENTRE - Vector2(200.0, 0.0)
    brush.begin_stroke(from, 1.0, _lean(0.0), 0.0)
    for i in range(1, SAMPLES + 1):
        var share := float(i) / float(SAMPLES)
        brush.add_sample(from + Vector2(400.0 * share, 0.0), 1.0, _lean(share), 16.0 * i)
    brush.end_stroke()

    assert_true(stretch.seen.size() >= SAMPLES, "The stroke laid its points, %d of them" % stretch.seen.size())
    var off := 0
    var widths := {}
    for values: PackedFloat32Array in stretch.seen:
        var turn := Vector2(values[NoiseStretchScript.ROTATION], values[NoiseStretchScript.ROTATION + 1])
        if absf(angle_difference(turn.angle(), ANGLE)) > 0.0001:
            off += 1
        widths[snappedf(values[NoiseStretchScript.HALF_EXTENT], 0.01)] = true
    assert_eq(off, 0, "Every point carries the tip's own angle while the lean turns through 90 degrees")
    assert_true(widths.size() > 1, "and the lean stretches the tip as it turns, %d half extents" % widths.size())


## The third clause: a Grain Round tap at pressure 1.0 is solid at half its
## radius and under 0.9 at nine tenths, where it was the hard disc before.
func test_a_grain_round_tap_falls_off_before_its_rim() -> void:
    var soft := _tap_alphas(-1.0)
    assert_true(soft.x >= 0.999, "Half the radius in, the tap is solid, %.3f at the least" % soft.x)
    assert_true(soft.y < 0.9, "and nine tenths out it has faded, %.3f at the most" % soft.y)
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    _images.clear()
    var hard := _tap_alphas(1.0)
    assert_true(hard.y >= 0.999, "The tip at a softness of one is the hard disc it was, %.3f" % hard.y)


## The Edge Hardness row writes the tip's softness under a key of its own, shown
## while Tip is not Image.
func test_the_tip_edge_row_writes_the_tip_s_softness() -> void:
    var edge: SaOptionSpec = null
    for spec: SaOptionSpec in TipRowScript.rows():
        if spec.key == TipRowScript.EDGE_KEY:
            edge = spec
    assert_not_null(edge, "The Tip row has an edge row")
    assert_eq(edge.property, ^"tip:softness", "writing the tip's softness")
    assert_true(edge.key != &"tip_softness", "under a key that is not the stamp's")
    var image := func(_key: StringName) -> Variant: return TipRowScript.IMAGE
    var round_tip := func(_key: StringName) -> Variant: return 0
    assert_true(edge.shown_under(round_tip), "shown while Tip is not Image")
    assert_false(edge.shown_under(image), "and not under Image")
    assert_true(edge.tooltip.contains("100") and edge.tooltip.contains("hard"), "and its tooltip says which way it runs")
    var settings := NoisePresetsScript.build(NoiseBrushSettingsScript, _grain_round())
    assert_almost_eq(settings.get_indexed(edge.property), 0.8, 0.0001, "Grain Round ships at 80")


## The least alpha half the radius in and the most nine tenths out of a Grain
## Round tap at pressure 1.0, its tip's softness *softness* or the recipe's
## when below nought.
func _tap_alphas(softness: float) -> Vector2:
    var brush := _brush()
    brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, _grain_round())
    brush.settings.color = Color(0.2, 0.4, 0.8, 1.0)
    if softness >= 0.0:
        brush.settings.tip.softness = softness
    var stretch := RecordingStretch.new()
    brush.dab_list.stretch = stretch
    brush.begin_stroke(CENTRE, 1.0, Vector2.ZERO, 0.0)
    brush.end_stroke()
    assert_false(stretch.seen.is_empty(), "The tap laid a point")
    var values: PackedFloat32Array = stretch.seen[0]
    var at := Vector2(values[NoiseStretchScript.AT], values[NoiseStretchScript.AT + 1])
    var radius := values[NoiseStretchScript.HALF_EXTENT]
    assert_true(radius > 18.0, "Grain Round's radius on this canvas, %.2f px" % radius)
    return Vector2(_ring(at, 0.5 * radius, true), _ring(at, 0.9 * radius, false))


## The least, when *least*, or the most alpha of the texels whose centres lie
## within [constant RING_WIDTH] of *distance* from *at*.
func _ring(at: Vector2, distance: float, least: bool) -> float:
    var out := 1.0 if least else 0.0
    var count := 0
    var reach := ceili(distance + 1.0)
    for y in range(floori(at.y) - reach, floori(at.y) + reach + 1):
        for x in range(floori(at.x) - reach, floori(at.x) + reach + 1):
            if absf((Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(at) - distance) > RING_WIDTH:
                continue
            var alpha := _texel(Vector2i(x, y)).a
            out = minf(out, alpha) if least else maxf(out, alpha)
            count += 1
    assert_true(count >= 8, "The ring at %.1f px holds texels, %d" % [distance, count])
    return out


func _brush() -> StateNoiseBrushScript:
    var brush := StateNoiseBrushScript.new()
    brush.surface = _surface
    brush.stroke_seed = 7
    brush.settings.color = Color(0.2, 0.4, 0.8, 1.0)
    brush.settings.hardness = 1.0
    brush.settings.strength = -0.5
    brush.settings.strength_option.enabled = false
    brush.settings.texture_drift = 0.0
    brush.settings.thickness = 0.0
    return brush


func _grain_round() -> Dictionary:
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == "Grain Round":
            return entry
    return {}


## The pen leaning [constant TILT] degrees at an azimuth *share* of the way
## through a quarter turn.
static func _lean(share: float) -> Vector2:
    return Vector2.from_angle(share * 0.5 * PI) * TILT


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
