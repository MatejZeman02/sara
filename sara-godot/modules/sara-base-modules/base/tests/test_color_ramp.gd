## The colour ramp behind the gradient tool.
##
## A colour ramp like Blender's dictates how the gradient looks. It has alpha
## control as well so a one-sided gradient can be made. The default when opened
## is the two selected colours on each end.
##
## Two halves. The model, which needs no GPU, and one dispatch that shows a third
## stop and a zero-alpha end reaching the canvas, because a ramp that is right in
## GDScript and never reaches the kernel is the bug this is written against.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The second half lays a ramp with the real kernel.
const REQUIRES_GPU := true

const CANVAS := Vector2i(512, 256)


func _pair() -> SaColorRamp:
    return SaColorRamp.from_pair(Color.BLACK, Color.WHITE)


# --- The model -----------------------------------------------------------------


func test_a_ramp_opens_as_the_two_picked_colours() -> void:
    var ramp := SaColorRamp.from_pair(Color.RED, Color.BLUE)

    assert_eq(ramp.size(), 2, "Two stops")
    assert_eq(ramp.position_of(0), 0.0, "one at the press end")
    assert_eq(ramp.position_of(1), 1.0, "and one at the release end")
    assert_eq(ramp.color_of(0), Color.RED, "the foreground at the press")
    assert_eq(ramp.color_of(1), Color.BLUE, "and the background at the release")


## Adding a stop is a handle to drag, not a change to the picture, so it takes
## the colour the ramp already has where it lands.
func test_adding_a_stop_does_not_change_the_ramp() -> void:
    var ramp := _pair()
    var before := ramp.display_at(0.5)

    var index := ramp.add_stop(0.5)

    assert_eq(ramp.size(), 3, "Three stops now")
    assert_eq(index, 1, "and the new one is the middle")
    assert_true(ramp.display_at(0.5).is_equal_approx(before), "with the ramp unmoved at that point")


func test_a_ramp_cannot_go_below_two_stops() -> void:
    var ramp := _pair()

    assert_false(ramp.remove_stop(0), "The last two stay")
    assert_eq(ramp.size(), 2, "however hard the button is pressed")

    ramp.add_stop(0.5)
    assert_true(ramp.remove_stop(1), "A third one goes")
    assert_eq(ramp.size(), 2, "back to the two")


## Dragging a stop past its neighbour reorders the list, so the index a caller
## holds has to come back from the move rather than be assumed.
func test_dragging_a_stop_past_another_answers_its_new_index() -> void:
    var ramp := _pair()
    ramp.add_stop(0.25, Color.RED)
    ramp.add_stop(0.5, Color.GREEN)
    assert_eq(ramp.color_of(1), Color.RED, "The red stop is the second of four")

    var moved := ramp.move_stop(1, 0.75)

    assert_eq(moved, 2, "and it is the third after being dragged past the green one")
    assert_eq(ramp.color_of(2), Color.RED, "still red")
    assert_eq(ramp.color_of(1), Color.GREEN, "with green now the second")


func test_a_stop_is_clamped_to_the_ramp() -> void:
    var ramp := _pair()
    ramp.add_stop(0.5)

    ramp.move_stop(1, 4.0)
    assert_eq(ramp.position_of(2), 1.0, "Past the end is the end")
    ramp.move_stop(2, -4.0)
    assert_eq(ramp.position_of(0), 0.0, "and before the start is the start")


## The one-sided gradient: alpha belongs to a stop, and it
## is interpolated on its own so a fade does not drag the hue anywhere.
func test_alpha_is_a_stop_s_own_and_is_walked_separately() -> void:
    var ramp := SaColorRamp.from_pair(Color.RED, Color.RED)
    ramp.set_stop_alpha(1, 0.0)

    assert_almost_eq(ramp.display_at(0.0).a, 1.0, 1e-4, "Opaque at the press")
    assert_almost_eq(ramp.display_at(0.5).a, 0.5, 1e-3, "half way at the middle")
    assert_almost_eq(ramp.display_at(1.0).a, 0.0, 1e-4, "and gone at the release")
    var middle := ramp.display_at(0.5)
    assert_almost_eq(middle.r, 1.0, 2e-3, "with the colour still the red it started as")
    assert_almost_eq(middle.g, 0.0, 2e-3, "and nothing in green")


## Two stops in one place are a hard edge, which is what dragging one onto
## another looks like it should do rather than a division by nothing.
func test_two_stops_in_one_place_are_a_hard_edge() -> void:
    var ramp := SaColorRamp.from_pair(Color.BLACK, Color.BLACK)
    ramp.add_stop(0.5, Color.BLACK)
    ramp.add_stop(0.5, Color.WHITE)

    assert_almost_eq(ramp.display_at(0.49).r, 0.0, 0.05, "Black up to the edge")
    assert_almost_eq(ramp.display_at(0.51).r, 1.0, 0.05, "and white after it")


## The lookup the kernel samples: one texel per column, read at the texel's own
## centre, so a sample at t reads the ramp at t.
func test_the_lookup_holds_the_ramp_at_each_texel_s_centre() -> void:
    var ramp := _pair()
    var texels := ramp.to_oklab_texels(4)

    assert_eq(texels.size(), 16, "Four texels of four floats")
    for i in 4:
        var wanted := ramp.oklab_at((float(i) + 0.5) / 4.0)
        assert_almost_eq(texels[i * 4], wanted.r, 1e-6, "texel %d holds the Oklab lightness there" % i)
        assert_almost_eq(texels[i * 4 + 3], wanted.a, 1e-6, "and the alpha at texel %d" % i)


## The stops survive a round trip through plain data, which is what a saved ramp
## keeps.
func test_a_ramp_round_trips_through_plain_data() -> void:
    var ramp := SaColorRamp.from_pair(Color.RED, Color.BLUE)
    ramp.add_stop(0.5, Color(0.2, 0.8, 0.3, 0.5))

    var back := SaColorRamp.from_array(ramp.to_array())

    assert_eq(back.size(), 3, "Three stops came back")
    assert_almost_eq(back.position_of(1), 0.5, 1e-6, "in the same places")
    assert_true(back.color_of(1).is_equal_approx(Color(0.2, 0.8, 0.3, 0.5)), "with their colours and alphas")


func test_unreadable_data_falls_back_rather_than_leaving_one_stop() -> void:
    var fallback := SaColorRamp.from_pair(Color.RED, Color.BLUE)

    var back := SaColorRamp.from_array([{"position": 0.0, "color": "not a colour"}], fallback)

    assert_eq(back, fallback, "The fallback stands in")
    assert_true(SaColorRamp.from_array([]).size() >= SaColorRamp.MIN_STOPS, "and a ramp is never below its minimum")


# --- The kernel ----------------------------------------------------------------


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(CANVAS)
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


func _texel(document: SaDocument, x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := document.active_layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(
        bytes, texture.format, (y - grid.y * SaChunk.SIZE) * texture.size.x + (x - grid.x * SaChunk.SIZE)
    )


## The whole point of the ramp: a third stop reaches the canvas, and it is the
## colour it was given rather than a mix of the two ends.
func test_a_middle_stop_reaches_the_canvas() -> void:
    var easel := _easel()
    var document := easel.document
    var ramp := SaColorRamp.from_pair(Color.BLACK, Color.BLACK)
    ramp.add_stop(0.5, Color.RED)

    var laid := SaGradient.new(document).apply(
        document.active_layer, Vector2(0.5, 0.0), Vector2(512.5, 0.0), ramp, SaGradient.Shape.LINEAR, SaGradient.Repeat.NONE, true
    )
    assert_true(laid, "A drag lays the ramp")

    var middle := _texel(document, 256, 100)
    assert_true(middle.r > 0.7, "The middle of the canvas is the red the middle stop holds")
    assert_true(middle.g < 0.3, "rather than a mix of the two black ends")
    assert_true(_texel(document, 4, 100).r < 0.2, "with black still at the press end")
    assert_true(_texel(document, 507, 100).r < 0.2, "and at the release end")

    easel.free()


## A stop at alpha zero is the one-sided gradient, on the canvas rather than in
## the model alone.
func test_a_zero_alpha_end_fades_the_ramp_out() -> void:
    var easel := _easel()
    var document := easel.document
    var ramp := SaColorRamp.from_pair(Color.RED, Color.RED)
    ramp.set_stop_alpha(1, 0.0)

    SaGradient.new(document).apply(
        document.active_layer, Vector2(0.5, 0.0), Vector2(512.5, 0.0), ramp, SaGradient.Shape.LINEAR, SaGradient.Repeat.NONE, true
    )

    assert_almost_eq(_texel(document, 4, 100).a, 1.0, 0.02, "Opaque at the press end")
    assert_almost_eq(_texel(document, 256, 100).a, 0.5, 0.02, "half way at the middle")
    assert_almost_eq(_texel(document, 507, 100).a, 0.0, 0.02, "and gone at the release end")

    easel.free()
