## A simulation plays at a speed in steps a second, counted in
## steps rather than clock time, and a stroke pressed on its layer pauses it
## before the first dab, the stroke's paint being the seed from then on.
##
## Frames are handed to [method SaSimulation.play_frame] by the suite with a
## delta of its own, so the count a speed gives is exact and no clock decides
## it. The press is the stamp brush's own, through `handle_input`, so the pause
## is the one a painter's pen meets.
extends "res://tests/test_framework.gd"

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

const REQUIRES_GPU := true

const CANVAS := Vector2i(512, 256)
const FRAME := 1.0 / 60.0
const OCHRE := Color(0.8, 0.4, 0.2, 1.0)
const BLUE := Color(0.1, 0.2, 0.9, 1.0)

var _surface: SaSurface = null
var _registries: SaRegistries = null


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    _surface = Fixtures.make_surface(CANVAS)
    _registries = Fixtures.make_registries(_surface)
    var base := BaseModule.new()
    base.register(_registries.context.for_module(base.get_id()))


func after_each() -> void:
    _surface.get_document().free()
    _surface.easel.free()
    _surface = null
    _registries = null


## A paint layer of its own, active, with a square of ochre in its first chunk
## for Spread to move, and Spread on it.
func _layer() -> SaLayer:
    var document := _surface.get_document()
    var layer := SaLayerOps.new(document).add(&"")
    document.set_active_layer(layer)
    var texture := layer.get_or_create_chunk(Vector2i(0, 0)).albedo()
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
    image.fill(Color(0.0, 0.0, 0.0, 0.0))
    image.fill_rect(Rect2i(20, 20, 8, 8), OCHRE)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    var spread := _registries.simulation_rules.find(&"spread")
    assert_not_null(spread, "The base module registers Spread")
    assert_not_null(SaSimulation.put_on(layer, spread), "Spread goes on a paint layer")
    return layer


## *frames* frames of *delta* seconds, and how many steps they ran.
func _play(layer: SaLayer, frames: int, delta: float = FRAME) -> int:
    var taken := 0
    for _i in frames:
        taken += SaSimulation.play_frame(_surface.get_document(), layer, _registries.simulation_rules, Rect2(), delta)
    return taken


func _bytes(layer: SaLayer) -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in layer.chunks:
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data((layer.chunks[grid_pos] as SaChunk).albedo().rid, 0)
    return out


func _texel(layer: SaLayer, at: Vector2i) -> Color:
    var texture := layer.get_field(Vector2i(0, 0))
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


func _brush() -> ToolState:
    var brush := StateBrushScript.new()
    brush.surface = _surface
    brush.settings.color = BLUE
    brush.settings.radius = 12.0 / float(mini(CANVAS.x, CANVAS.y))
    brush.settings.hardness = GammaFloat.new(1.0, 1.0)
    brush.settings.opacity_by_pressure = false
    brush.settings.spacing = 0.1
    return brush


func _button(pressed: bool, at: Vector2) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = at
    return event


func test_ten_steps_a_second_over_sixty_frames_of_a_sixtieth_run_ten_steps() -> void:
    var layer := _layer()
    var record := SaSimulation.record_of(layer)
    assert_eq(record.speed, SaSimulation.DEFAULT_SPEED, "A record starts at ten steps a second")
    assert_eq(_play(layer, 60), 0, "Paused, sixty frames run nothing")
    assert_true(SaSimulation.play(layer), "Play is taken on a layer with a simulation")
    assert_true(record.playing, "and the record plays")
    assert_eq(_play(layer, 30), 5, "Thirty frames of a sixtieth at ten a second run five steps")
    assert_eq(_play(layer, 30), 5, "and thirty more five again")
    assert_eq(record.steps, 10, "Sixty frames at ten a second count ten steps")
    record.speed = 30.0
    assert_eq(_play(layer, 60), 30, "At thirty a second the same sixty frames run thirty")
    assert_eq(record.steps, 40, "and the count goes on from ten")


func test_a_slow_frame_runs_fewer_steps_than_its_clock_time_and_the_count_stays_honest() -> void:
    var layer := _layer()
    var record := SaSimulation.record_of(layer)
    SaSimulation.play(layer)
    var taken := _play(layer, 6, 0.5)
    assert_true(taken < 30, "Six frames of half a second run fewer than the thirty three seconds would, ran %d" % taken)
    assert_eq(taken, 2, "Each counts a thirtieth of a second, a third of a step at ten a second")
    assert_eq(record.steps, taken, "The count is the steps run, which is the picture on the canvas")
    SaSimulation.pause(layer)
    assert_false(record.playing, "Pause stops it")
    assert_eq(_play(layer, 60), 0, "and paused frames run nothing")


func test_a_press_on_the_layer_pauses_it_and_the_strokes_paint_is_the_seed() -> void:
    var layer := _layer()
    var record := SaSimulation.record_of(layer)
    SaSimulation.play(layer)
    assert_eq(_play(layer, 30), 5, "It plays five steps first")
    var brush := _brush()
    var from := Vector2(100.0, 120.0)
    var to := Vector2(300.0, 120.0)
    var was := SaColors.foreground
    SaColors.foreground = BLUE
    _surface.view.mouse_position = from
    brush.handle_input(_button(true, from))
    assert_false(record.playing, "The press pauses it, before any dab")
    assert_eq(record.steps, 5, "and no step ran between")
    for i in range(1, 41):
        _surface.view.mouse_position = from.lerp(to, float(i) / 40.0)
        assert_eq(_play(layer, 1), 0, "A frame during the stroke runs no step")
        var motion := InputEventMouseMotion.new()
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.position = _surface.view.mouse_position
        motion.pressure = 1.0
        brush.handle_input(motion)
    brush.handle_input(_button(false, to))
    SaColors.foreground = was
    assert_false(record.playing, "It is still paused after the stroke")
    assert_eq(record.steps, 0, "and the count starts again from the new seed")
    var under := _texel(layer, Vector2i(200, 120))
    assert_true(under.a > 0.9 and under.b > under.r, "The stroke painted blue at (200, 120), read %s" % under)
    var painted := _bytes(layer)
    assert_true(SaSimulation.step(_surface.get_document(), layer, _registries.simulation_rules), "A step is taken")
    assert_false(_bytes(layer) == painted, "and moves the paint")
    assert_true(SaSimulation.reset(_surface.get_document(), layer), "Reset is taken")
    assert_eq(_bytes(layer), painted, "Reset returns the stroke over the five steps, the seed the painter last painted")
    assert_true(SaSimulation.play(layer), "Play goes on from there")
    assert_eq(_play(layer, 6), 1, "and steps again")
