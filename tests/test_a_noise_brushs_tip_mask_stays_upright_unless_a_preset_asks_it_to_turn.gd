## A noise brush's tip mask stays upright unless a preset asks
## it to turn.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The tip mask does not rotate with the pen by default. The lean's stretch
## must not hand its angle back as the tip's. A picture's half extents are
## round unless its ratio says otherwise, so the stretch draws a round tip out
## along the lean without turning the mask with the pen's tilt. The heading steers only the field and the twist reached nothing.
##
## Each shipped preset takes a shipped picture through the Tip row's own two
## properties and lays a stroke along a bend with the pen's tilt and twist
## changing at every sample, and every point the state hands its stretch is
## recorded on the way in: each carries the tip's own angle. The Rotation
## option, the stamp's under the stamp's name, then gets a sensor, and the
## points turn with the lean, the heading or the twist it reads. Taps through a
## bar the suite draws read the turn off the layer, so what the points carry is
## what the kernel paints.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const NoiseStretchScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_stretch.gd")
const TipRowScript = preload("res://modules/sara-noise-brush-engine/tip/tip_row.gd")

## A shipped picture with a long axis, picked from the Tip Image grid.
const RIDGE := "res://tips/ridge.png"
## The bend: three quarters of a circle about the canvas's middle, sampled
## every [constant SAMPLE_MS] milliseconds.
const CENTRE := Vector2(128.0, 128.0)
const BEND_RADIUS := 70.0
const SAMPLES := 48
const SAMPLE_MS := 8.0
## The taps' tip radius in pixels, and the half side of the square their
## coverage is read over, which the longest stretch stays inside.
const TAP_RADIUS := 36.0
const WINDOW := 100
## Leans in degrees the taps are pressed at, upright first, and a twist with each.
const LEANS: Array[Vector2] = [Vector2.ZERO, Vector2(55.0, 0.0), Vector2(0.0, 55.0), Vector2(40.0, 40.0), Vector2(-40.0, 35.0)]
const TWISTS: Array[float] = [0.0, 120.0, -90.0, 45.0, 170.0]
## How far two angles may differ and still be one, in radians: a float's
## rounding for a turn the state carries, and a couple of degrees for one read
## off the paint, whose texels are a grid.
const SAME_TURN := 0.0001
const SAME_PAINTED := 0.04


## The noise stretch with every point the state adds recorded on the way in,
## its turn and its half extents, so a suite reads what each point of the
## stroke carries before the kernel paints it.
class RecordedStretch:
    extends "res://modules/sara-noise-brush-engine/dab_list/noise_stretch.gd"

    var turns := PackedFloat32Array()
    var radii := PackedVector2Array()

    func add(values: PackedFloat32Array, reach: Rect2, tip_reach: float = 0.0) -> void:
        turns.append(atan2(values[ROTATION + 1], values[ROTATION]))
        radii.append(Vector2(values[HALF_EXTENT], values[HALF_EXTENT + 1]))
        super(values, reach, tip_reach)


var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
var _recorded: RecordedStretch = null
var _dir: String = SaDataRoot.path("test_b26_the_tip_mask_stays_upright")


func before_each() -> void:
    _surface = Fixtures.make_surface()
    DirAccess.make_dir_recursive_absolute(_dir)


func after_each() -> void:
    _brush = null
    _recorded = null
    Fixtures.teardown(_surface)
    _surface = null
    if not DirAccess.dir_exists_absolute(_dir):
        return
    for file_name: String in DirAccess.get_files_at(_dir):
        DirAccess.remove_absolute(_dir.path_join(file_name))
    DirAccess.remove_absolute(_dir)


## The Done when's first clause, for every shipped preset: a stroke along the
## bend with the tilt and the twist changing at every sample, and a ridge
## picked on the Tip row, lays every point at the tip's own angle, nought and
## then a turn a converted stamp preset can carry. The points are not all one
## size, so the lean did reach them, as a stretch along the picture's axes.
func test_every_shipped_preset_lays_the_picture_at_its_own_angle() -> void:
    var entries := NoisePresetsScript.entries()
    assert_eq(entries.size(), 15, "The shelf ships fifteen presets")
    for entry: Dictionary in entries:
        for angle: float in [0.0, 0.6]:
            _fresh_brush(entry)
            _pick_on_the_tip_row(RIDGE)
            _brush.settings.tip.angle = angle
            assert_false(_brush.settings.rotation_option.enabled, "%s ships with Rotation off" % entry["name"])
            _bend()
            var label := "%s at a tip angle of %.1f" % [entry["name"], angle]
            assert_true(_recorded.turns.size() > SAMPLES, "%s laid %d points" % [label, _recorded.turns.size()])
            assert_true(_brush.settings.tip.uses_image(), "%s paints the picture" % label)
            var widest := _widest_turn_from(angle)
            assert_true(
                widest < SAME_TURN, "%s lays every point at the tip's own angle, the farthest %.6f radians off" % [label, widest]
            )
            assert_true(
                _spread_of_lengths() > 1.05,
                (
                    "%s still stretches along the picture's axes, %.3f between the longest and the shortest"
                    % [label, _spread_of_lengths()]
                )
            )


## The bend's own heading and the twist turn nothing either with the stretch
## unbound, so it is not the stretch alone that was held still.
func test_neither_the_heading_nor_the_twist_turns_the_picture() -> void:
    _fresh_brush(NoisePresetsScript.entries()[0])
    _pick_on_the_tip_row(RIDGE)
    _brush.settings.stretch_option.enabled = false
    _bend()
    assert_true(_widest_turn_from(0.0) < SAME_TURN, "No point turns, the farthest %.6f radians off" % _widest_turn_from(0.0))
    assert_true(_spread_of_lengths() < 1.0001, "and with the stretch unbound no point grows, %.4f" % _spread_of_lengths())


## The Done when's second clause: the Rotation option given a sensor turns the
## points, with the lean under Tilt Direction, with the heading under Drawing
## Angle, and with the twist under Rotation. Under Rotation with the twist held
## and the stretch unbound, every point takes one turn, so it is the twist that
## turns them and nothing else of the stroke.
func test_a_rotation_sensor_turns_the_picture_with_the_pen() -> void:
    for sensor: SaSensor.Id in [SaSensor.Id.TILT_DIRECTION, SaSensor.Id.DRAWING_ANGLE, SaSensor.Id.ROTATION]:
        _fresh_brush(NoisePresetsScript.entries()[0])
        _pick_on_the_tip_row(RIDGE)
        _turn_on(sensor)
        _bend()
        var label: String = SaSensor.Id.keys()[sensor]
        assert_true(
            _widest_turn_from(0.0) > 0.5,
            "Under %s the points turn, %.3f radians at the farthest" % [label, _widest_turn_from(0.0)]
        )
        assert_true(_distinct_turns() > 10, "and keep turning along the bend, %d turns" % _distinct_turns())
    _fresh_brush(NoisePresetsScript.entries()[0])
    _pick_on_the_tip_row(RIDGE)
    _brush.settings.stretch_option.enabled = false
    _turn_on(SaSensor.Id.ROTATION)
    _bend(false)
    var held: float = _recorded.turns[0]
    assert_true(_off_by(held, 0.0) > 0.1, "With the twist held off nought, the Rotation sensor turns the picture by it")
    assert_true(
        _widest_turn_from(held) < SAME_TURN,
        "and by the same at every point of the bend, %.6f radians apart at most" % _widest_turn_from(held)
    )


## Taps through a horizontal bar read the turn off the layer. Under the
## preset's defaults every lean and twist paints the bar level, and under Tilt
## Direction the bar lies at the turn its point carried, so the turn the
## points carry is what the kernel draws.
func test_the_paint_lies_as_the_points_turn() -> void:
    var bar := _bar_picture()
    var entry: Dictionary = NoisePresetsScript.entries()[0]
    for turning: bool in [false, true]:
        var turned := 0
        for index in LEANS.size():
            Fixtures.teardown(_surface)
            _surface = Fixtures.make_surface()
            _fresh_brush(entry)
            _brush.settings.radius = TAP_RADIUS / 256.0
            assert_true(_brush.load_tip(bar), "The bar loads through Load Tip")
            if turning:
                _turn_on(SaSensor.Id.TILT_DIRECTION)
            _brush.begin_stroke(CENTRE, 1.0, LEANS[index], 0.0, false, TWISTS[index])
            _brush.end_stroke()
            var carried: float = _recorded.turns[_recorded.turns.size() - 1]
            var painted := _painted_angle()
            var label := "A tap leaning %s with a twist of %d" % [LEANS[index], TWISTS[index]]
            if not turning:
                assert_true(absf(carried) < SAME_TURN, "%s carries the bar's own angle" % label)
                assert_true(
                    _off_by(painted, 0.0) < SAME_PAINTED,
                    "%s paints the bar level, at %.1f degrees" % [label, rad_to_deg(painted)]
                )
                continue
            assert_true(
                _off_by(painted, carried) < SAME_PAINTED,
                (
                    "%s under Tilt Direction paints the bar at its point's turn, %.1f against %.1f degrees"
                    % [label, rad_to_deg(painted), rad_to_deg(carried)]
                )
            )
            if _off_by(painted, 0.0) > 0.2:
                turned += 1
        if turning:
            assert_true(turned >= 3, "and the leans turn the bar, %d of the %d taps off level" % [turned, LEANS.size()])


## The brush editor shows the Rotation option a page of its own, after the
## stretch's, under the stamp's key, and the door's dynamics prepares it.
func test_the_rotation_option_has_its_page() -> void:
    var labels: Array[String] = []
    for spec: SaOptionSpec in NoiseModuleScript.options():
        if spec.kind == SaOptionSpec.Kind.CURVE_OPTION:
            labels.append(spec.label)
            if spec.key == NoiseModuleScript.ROTATION_OPTION:
                assert_eq(spec.label, "Rotation", "The Rotation page is named as the stamp's is")
    assert_true(labels.has("Rotation"), "The brush editor has a Rotation page")
    assert_true(labels.find("Rotation") > labels.find("Tilt Stretch"), "after Tilt Stretch")
    var settings := NoiseBrushSettingsScript.new()
    assert_true(
        settings.options().get("rotation") == settings.rotation_option, "and the door's dynamics finds it among the options"
    )
    assert_true(settings.rotation_option.active_sensors().is_empty(), "carrying no sensor in a fresh preset")


## A brush on *entry*'s recipe, built as the shelf's install builds it, its
## stretch recorded.
func _fresh_brush(entry: Dictionary) -> void:
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7
    var settings: Resource = NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
    assert_not_null(settings, "%s builds" % entry["name"])
    settings.pattern_store = SaPatternStore.new()
    _brush.settings = settings
    _recorded = RecordedStretch.new()
    _brush.dab_list.stretch = _recorded


## Picks *path* the way the Tip row and the Tip Image grid do, by writing the
## two properties their specs name.
func _pick_on_the_tip_row(path: String) -> void:
    for spec: SaOptionSpec in NoiseModuleScript.options():
        if spec.key == &"tip_generator":
            _brush.settings.set_indexed(spec.property, SaDabGeometry.Generator.IMAGE)
        elif spec.key == TipRowScript.LIST_KEY:
            _brush.settings.set_indexed(spec.property, path)


## Switches the Rotation option on with *sensor* alone, on its own line.
func _turn_on(sensor: SaSensor.Id) -> void:
    var option: SaCurveOption = _brush.settings.rotation_option
    option.enabled = true
    option.set_sensor(SaSensor.create(sensor, true))


## The stroke along the bend, the lean swinging round twice as fast as the
## path and rising and falling, and the twist running from one end of its
## range to the other unless *twisting* is false.
func _bend(twisting: bool = true) -> void:
    var tilt_at := func(t: float) -> Vector2: return Vector2.from_angle(3.0 * PI * t) * (15.0 + 40.0 * sin(PI * t))
    var twist_at := func(t: float) -> float: return -170.0 + 340.0 * t if twisting else 30.0
    _brush.begin_stroke(_on_bend(0.0), 0.8, tilt_at.call(0.0), 0.0, false, twist_at.call(0.0))
    for step in range(1, SAMPLES + 1):
        var t := float(step) / SAMPLES
        _brush.add_sample(_on_bend(t), 0.8, tilt_at.call(t), SAMPLE_MS * step, twist_at.call(t))
    _brush.end_stroke()


func _on_bend(t: float) -> Vector2:
    return CENTRE + BEND_RADIUS * Vector2.from_angle(1.5 * PI * t)


## How far the farthest recorded turn lies from *angle*, in radians, a half
## turn being the same box.
func _widest_turn_from(angle: float) -> float:
    var widest := 0.0
    for turn: float in _recorded.turns:
        widest = maxf(widest, _off_by(turn, angle))
    return widest


## How many recorded turns differ from each other by more than a degree.
func _distinct_turns() -> int:
    var seen := {}
    for turn: float in _recorded.turns:
        seen[roundi(rad_to_deg(turn))] = true
    return seen.size()


## The longest recorded major half extent over the shortest.
func _spread_of_lengths() -> float:
    var longest := 0.0
    var shortest := INF
    for radii: Vector2 in _recorded.radii:
        var major := maxf(radii.x, radii.y)
        if major <= 0.0:
            continue
        longest = maxf(longest, major)
        shortest = minf(shortest, major)
    return longest / shortest if shortest < INF else 0.0


## How far apart two axes are, in radians, a half turn apart being one axis.
static func _off_by(a: float, b: float) -> float:
    var d := fposmod(a - b, PI)
    return minf(d, PI - d)


## A long level bar on a clear ground, drawn here so its axis is exactly the
## picture's x, saved under the suite's own folder.
func _bar_picture() -> String:
    var image := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
    image.fill(Color(0.0, 0.0, 0.0, 0.0))
    image.fill_rect(Rect2i(2, 28, 60, 8), Color(0.0, 0.0, 0.0, 1.0))
    var path := _dir.path_join("level-bar.png")
    assert_eq(image.save_png(path), OK, "The bar is written")
    return path


## The axis the tap's paint lies along, from the second moments of its alpha
## over the window about the centre, in radians.
func _painted_angle() -> float:
    var layer := _surface.easel.document.active_layer
    var images := {}
    var total := 0.0
    var mean := Vector2.ZERO
    var samples: Array[Vector3] = []
    for y in range(int(CENTRE.y) - WINDOW, int(CENTRE.y) + WINDOW):
        for x in range(int(CENTRE.x) - WINDOW, int(CENTRE.x) + WINDOW):
            var a := _alpha_at(layer, Vector2i(x, y), images)
            if a <= 0.0:
                continue
            samples.append(Vector3(x + 0.5, y + 0.5, a))
            total += a
            mean += a * Vector2(x + 0.5, y + 0.5)
    if total <= 0.0:
        return NAN
    mean /= total
    var sxx := 0.0
    var syy := 0.0
    var sxy := 0.0
    for sample: Vector3 in samples:
        var dx := sample.x - mean.x
        var dy := sample.y - mean.y
        sxx += sample.z * dx * dx
        syy += sample.z * dy * dy
        sxy += sample.z * dx * dy
    return 0.5 * atan2(2.0 * sxy, sxx - syy)


## The layer's alpha at a document pixel, each chunk read back once into
## *images*.
func _alpha_at(layer: SaLayer, pixel: Vector2i, images: Dictionary) -> float:
    var side := 0
    for grid: Vector2i in layer.chunks:
        side = (layer.chunks[grid] as SaChunk).pixel_size()
        break
    if side == 0:
        return 0.0
    var grid := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
    if not layer.chunks.has(grid):
        return 0.0
    if not images.has(grid):
        @warning_ignore("static_called_on_instance")
        images[grid] = SaExport.get_texture_image_float(layer.get_field(grid))
    return (images[grid] as Image).get_pixelv(pixel - grid * side).a
