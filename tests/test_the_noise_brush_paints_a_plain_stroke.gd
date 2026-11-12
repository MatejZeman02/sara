## The noise brush paints a plain stroke.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The stroke is painted through the tool's own public calls on a real
## surface and read back texel by texel, because a wash that stacked would
## look like a darker stroke and nothing else. The registration half is read
## off the descriptor the module hands the registry, the way the toolbox and
## the preset store read it.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")

## Where the strokes land, inside the first chunk whatever its size, and the
## stroke's reach either side of it.
const SPOT := Vector2(40.0, 40.0)
const REACH := 20.0

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7
    _brush.settings.color = Color(0.2, 0.4, 0.8, 1.0)
    _brush.settings.opacity = 0.5
    _brush.settings.hardness = 1.0
    # Twelve pixels across, on a canvas whose smaller side is 256.
    _brush.settings.radius = 6.0 / 256.0


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null


## The active layer's texel at *at*, in document pixels.
func _texel(at: Vector2) -> Color:
    var layer := _surface.easel.document.active_layer
    var side := 0
    for grid: Vector2i in layer.chunks:
        side = (layer.chunks[grid] as SaChunk).pixel_size()
        break
    if side == 0:
        return Color.TRANSPARENT
    var pixel := Vector2i(at.floor())
    var grid := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
    if not layer.chunks.has(grid):
        return Color.TRANSPARENT
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(layer.get_field(grid))
    return image.get_pixelv(pixel - grid * side)


## A press and a release at *at*: the tip once, nothing swept.
func _press(at: Vector2, pressure: float = 1.0) -> void:
    _brush.begin_stroke(at, pressure)
    _brush.end_stroke()


## One stroke that crosses *at* *passes* times, left to right and back, at
## the pen's usual rate of a sample every few pixels.
func _scrub(at: Vector2, passes: int, pressure: float = 1.0) -> void:
    var left := at - Vector2(REACH, 0.0)
    var right := at + Vector2(REACH, 0.0)
    _brush.begin_stroke(left, pressure)
    var from := left
    for i in passes:
        var to := right if i % 2 == 0 else left
        for step in range(1, 11):
            _brush.add_sample(from.lerp(to, step / 10.0), pressure)
        from = to
    _brush.end_stroke()


func test_a_press_paints_the_colour_at_the_strokes_opacity() -> void:
    _press(SPOT)
    var texel := _texel(SPOT)
    assert_almost_eq(texel.a, 0.5, 0.01, "A press at half opacity leaves half alpha under its centre")
    # The layer keeps straight colour, so the channels are the picked ones.
    var colour := _surface.easel.document.color_space.from_display(_brush.settings.color)
    assert_almost_eq(texel.r, colour.r, 0.01, "in the picked colour, red")
    assert_almost_eq(texel.b, colour.b, 0.01, "and blue")
    assert_almost_eq(_texel(SPOT + Vector2(REACH, 0.0)).a, 0.0, 1e-4, "and nothing outside the tip")


## The ceiling: a texel five passes of one stroke cross is stronger than the
## same texel under one press, since a pen that comes back over the stroke's
## own paint builds it up, and stops at the stroke's opacity, which the buffer
## lands at. At half pressure, so one pass is half strong in the buffer and the
## passes have room to climb.
##
## Pressure drives the cut rather than the opacity, so this case puts
## pressure back on Opacity and the cut at nought, which leaves the texture out
## of it and keeps the ceiling what is measured.
func test_many_passes_build_up_to_the_strokes_opacity_and_no_further() -> void:
    _brush.settings.strength = 0.0
    _brush.settings.opacity_option = SaCurveOption.create_default()
    _press(SPOT, 0.5)
    var once := _texel(SPOT).a
    var other := SPOT + Vector2(0.0, 60.0)
    _scrub(other, 5, 0.5)
    var many := _texel(other).a
    assert_true(once > 0.1 and once < 0.45, "One half-pressure press reached %.4f, under the stroke's opacity" % once)
    assert_true(many > once + 0.1, "Under five passes the texel is %.4f, stronger than %.4f under one" % [many, once])
    assert_almost_eq(many, _brush.settings.opacity, 0.01, "and as strong as the stroke's opacity, which it stops at")


## The stroke is one swept shape, so a line has no gap anywhere along it.
func test_a_line_has_no_gaps() -> void:
    _scrub(SPOT, 1)
    var weakest := 1.0
    for x in range(-int(REACH) + 2, int(REACH) - 1):
        weakest = minf(weakest, _texel(SPOT + Vector2(x, 0.0)).a)
    assert_almost_eq(weakest, 0.5, 0.01, "Every texel along the line's middle is at the stroke's opacity")


func test_the_module_registers_a_noise_brush_through_the_door() -> void:
    var registries := Fixtures.make_registries(_surface)
    var module := NoiseModuleScript.new()
    module.register(registries.context)
    var descriptor: SaToolDescriptor = registries.tools.get_descriptor(NoiseModuleScript.TOOL_ID)
    assert_not_null(descriptor, "The noise brush registers through the door")
    assert_true(descriptor.is_brush_engine, "as an engine of the Brush rather than a tool of its own")
    assert_eq(descriptor.display_name, "Noise Brush", "by its name")
    assert_eq(descriptor.preset_engine, &"noise", "whose presets carry the engine's name")
    assert_eq(
        SaPresetStore.preset_engine_of(descriptor.shared_settings), &"noise", "and the store reads the same name off its settings"
    )
    assert_not_null(SaUI.get_icon(descriptor.icon_name), "with its own icon, from the module")
    var keys: Array[StringName] = []
    for spec: SaOptionSpec in descriptor.options:
        # The randomise rows sit under the sliders and have a suite of their own.
        if not String(spec.key).ends_with("_random"):
            keys.append(spec.key)
    var rows: Array[StringName] = [&"radius", &"opacity", &"paint_and_smudge", &"hardness", &"tip_generator", &"noise_tip_edge"]
    rows.append_array([&"tip_angle", &"tip_image_path", &"tip_load", &"texture_field", &"strength"] as Array[StringName])
    rows.append_array([&"thickness", &"thickness_lean", &"push_colour_below"] as Array[StringName])
    rows.append_array([&"randomness", &"blend_mode"] as Array[StringName])
    assert_eq(
        keys.slice(0, 16),
        rows,
        (
            # gdlint:ignore=max-line-length
            "and the five rows of the first brush with Paint and Smudge, Edge Hardness, Angle, Tip Image and Load Tip, Texture, Strength, "
            + "Thickness, Tilt Thickness, Push Colour Below and Randomness"
        )
    )
    assert_true(keys.has(&"strength_option"), "and Strength's curve option")
    assert_false(keys.has(&"spacing"), "Spacing is not on the page")
