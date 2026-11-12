## The eyedropper picks from a layer stored finer than the document at the
## pixel under the pen.
##
## A layer at twice the resolution holds 512 texels across a chunk. The pick
## took the pixel's place in document pixels as a texel's, so at (100, 100) it
## read the texel at (100, 100), which lies under the document pixel (50, 50),
## and picked a colour from somewhere else on the canvas.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)


## *colour* over *rect* of *target*, in texels.
func _patch(target: SaTexture, rect: Rect2i, colour: Color) -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var patch := SaTexture.new(rect.size, target.format)
    rd.texture_clear(patch.rid, colour, 0, 1, 0, 1)
    var at := Vector3(rect.position.x, rect.position.y, 0)
    rd.texture_copy(patch.rid, target.rid, Vector3.ZERO, at, Vector3(rect.size.x, rect.size.y, 1), 0, 0, 0, 0)


## A layer at twice the resolution, blue where the document pixel (50, 50) is
## and red under the pixels from (98, 98) to (102, 102).
func _fine_layer(surface: Object) -> SaLayer:
    var layer: SaLayer = surface.get_document().active_layer
    layer.resolution_scale = 2.0
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    chunk.clear(Color(0.0, 0.0, 0.0, 0.0))
    var albedo := chunk.field(SaFieldSpec.ALBEDO)
    _patch(albedo, Rect2i(100, 100, 2, 2), BLUE)
    _patch(albedo, Rect2i(196, 196, 10, 10), RED)
    return layer


func _eyedropper(surface: Object, side: int) -> Object:
    var eyedropper := StateEyedropperScript.new()
    eyedropper.surface = surface
    eyedropper.sample_from = StateEyedropperScript.SampleFrom.LAYER
    eyedropper.sample_size = side
    return eyedropper


func test_a_single_pick_reads_the_texels_under_the_pixel() -> void:
    var surface := Fixtures.make_surface(Vector2i(256, 256))
    var layer := _fine_layer(surface)
    assert_eq(layer.get_field(Vector2i.ZERO).size.x, 512, "The layer holds two texels for each pixel")

    var picked: Color = _eyedropper(surface, 1).pick_color_at_pos(Vector2(100, 100))
    assert_almost_eq(picked.r, 1.0, 0.01, "The pixel under the pen is red")
    assert_almost_eq(picked.b, 0.0, 0.01, "not the blue at texel (100, 100)")
    assert_almost_eq(picked.a, 1.0, 0.01, "and all four texels under it are covered")

    var blue: Color = _eyedropper(surface, 1).pick_color_at_pos(Vector2(50, 50))
    assert_almost_eq(blue.b, 1.0, 0.01, "The blue texels are under the pixel (50, 50)")

    surface.get_document().free()
    Fixtures.teardown(surface)


func test_a_square_pick_reads_the_texels_under_the_square() -> void:
    var surface := Fixtures.make_surface(Vector2i(256, 256))
    _fine_layer(surface)

    var picked: Color = _eyedropper(surface, 3).pick_color_at_pos(Vector2(100, 100))
    assert_almost_eq(picked.r, 1.0, 0.01, "The square round (100, 100) is all red")
    assert_almost_eq(picked.a, 1.0, 0.01, "and fully covered")

    var edge: Color = _eyedropper(surface, 3).pick_color_at_pos(Vector2(103, 100))
    assert_almost_eq(edge.r, 1.0, 0.01, "A square mostly off the red picks red")
    assert_almost_eq(edge.a, 1.0 / 3.0, 0.01, "at a third of full coverage, the red ending at pixel 102")

    surface.get_document().free()
    Fixtures.teardown(surface)
