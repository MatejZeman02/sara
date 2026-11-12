## A sample square at a stroke's soft edge picks the stroke's colour.
##
## A texel is stored straight, so a transparent one still carries a colour, the
## black of a chunk's clear. The square's mean took it at full weight, and a
## three by three pick beside one red texel came back a ninth red, a dark
## maroon, where the only colour in the square was red. The mean is weighted
## by alpha now: the transparent texels add coverage and no hue.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)


## One red texel at *at* of *target*, the rest of which the caller has cleared.
func _dot(target: SaTexture, at: Vector2i) -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var dot := SaTexture.new(Vector2i.ONE, target.format)
    rd.texture_clear(dot.rid, RED, 0, 1, 0, 1)
    rd.texture_copy(dot.rid, target.rid, Vector3.ZERO, Vector3(at.x, at.y, 0), Vector3.ONE, 0, 0, 0, 0)


func test_a_layer_square_beside_a_red_texel_picks_red() -> void:
    var surface := Fixtures.make_surface(Vector2i(64, 64))
    var layer: SaLayer = surface.get_document().active_layer
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    chunk.clear(Color(0.0, 0.0, 0.0, 0.0))
    _dot(chunk.field(SaFieldSpec.ALBEDO), Vector2i(32, 32))

    var eyedropper := StateEyedropperScript.new()
    eyedropper.surface = surface
    eyedropper.sample_from = StateEyedropperScript.SampleFrom.LAYER
    eyedropper.sample_size = 3
    var picked: Color = eyedropper.pick_color_at_pos(Vector2(32, 32))
    assert_almost_eq(picked.r, 1.0, 0.01, "The one colour in the square is red, and the pick is red")
    assert_almost_eq(picked.g, 0.0, 0.01, "with no green")
    assert_almost_eq(picked.a, 1.0 / 9.0, 0.01, "and the square's coverage, one texel in nine")

    surface.get_document().free()
    Fixtures.teardown(surface)


func test_a_merged_square_beside_a_red_texel_picks_red() -> void:
    var surface := Fixtures.make_surface(Vector2i(64, 64))
    var rd := GlobalShaderCompiler.get_rd()
    rd.texture_clear(surface.easel.output.rid, Color(0.0, 0.0, 0.0, 0.0), 0, 1, 0, 1)
    _dot(surface.easel.output, Vector2i(32, 32))

    var eyedropper := StateEyedropperScript.new()
    eyedropper.surface = surface
    eyedropper.sample_from = StateEyedropperScript.SampleFrom.VIEW
    eyedropper.sample_size = 3
    var picked: Color = eyedropper.pick_color_at_pos(Vector2(32, 32))
    assert_almost_eq(picked.r, 1.0, 0.01, "The composite's square picks red as well")
    assert_almost_eq(picked.a, 1.0 / 9.0, 0.01, "at a ninth of full coverage")

    surface.get_document().free()
    surface.easel.free()


func test_a_square_of_nothing_is_transparent() -> void:
    var surface := Fixtures.make_surface(Vector2i(64, 64))
    var layer: SaLayer = surface.get_document().active_layer
    layer.get_or_create_chunk(Vector2i.ZERO).clear(Color(0.0, 0.0, 0.0, 0.0))

    var eyedropper := StateEyedropperScript.new()
    eyedropper.surface = surface
    eyedropper.sample_from = StateEyedropperScript.SampleFrom.LAYER
    eyedropper.sample_size = 3
    var picked: Color = eyedropper.pick_color_at_pos(Vector2(10, 10))
    assert_almost_eq(picked.a, 0.0, 0.001, "A square with no coverage reads as nothing")
    assert_false(is_nan(picked.r), "and its colour is a number, not a division by zero")

    surface.get_document().free()
    Fixtures.teardown(surface)
