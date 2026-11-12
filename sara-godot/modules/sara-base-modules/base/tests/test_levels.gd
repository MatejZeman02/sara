## What Levels does to a known value.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Moved from the skeleton's suites with the Levels filter, and read against
## the base module's `SaPointAdjust`.
##
## Every case fills a layer with one colour, runs the pass, and reads the
## texel back off the chunk rather than off the composited output, so the
## background layer and the blend have no say in the answer.
extends "res://tests/test_framework.gd"

## A real dispatch into a real chunk.
const REQUIRES_GPU := true

const CANVAS := Vector2i(64, 64)


func _texel(layer: SaLayer) -> Color:
    var texture := layer.get_field(Vector2i.ZERO)
    if texture == null:
        return Color(0.0, 0.0, 0.0, 0.0)
    @warning_ignore("static_called_on_instance")
    return SaExport.get_texture_image_float(texture).get_pixel(4, 4)


## *fill* through Levels with *values*, as the colour that comes out.
func _through(easel: SaEasel, fill: Color, values: Dictionary) -> Color:
    var layer := easel.document.get_node_or_null("Layer 1") as SaLayer
    layer.fill(fill)
    easel.document.set_active_layer(layer)
    assert_true(SaPointAdjust.new().apply(easel.document, layer, SaPointAdjust.LEVELS, values, "Levels"), "The pass runs")
    return _texel(layer)


## The black handle moved to a quarter maps the ramp onto the whole range: a
## quarter becomes nothing, one stays one, and what was below the handle comes
## out below zero rather than pinned to it, which is hard rule 5.
func test_the_black_handle_maps_the_ramp() -> void:
    for entry: Array in [[0.25, 0.0], [0.5, 1.0 / 3.0], [1.0, 1.0], [0.0, -1.0 / 3.0]]:
        var easel := SaEasel.create_default(CANVAS)
        var level := float(entry[0])
        var out := _through(easel, Color(level, level, level, 1.0), {"in_black": 0.25})
        assert_almost_eq(out.r, float(entry[1]), 2e-3, "%.2f maps to %.3f" % [level, float(entry[1])])
        easel.free()


## The gamma moves the midpoint and leaves the ends where they are, which is
## what makes it the middle handle rather than a third end.
func test_the_gamma_moves_the_middle_and_not_the_ends() -> void:
    var easel := SaEasel.create_default(CANVAS)
    assert_almost_eq(_through(easel, Color(0.25, 0.25, 0.25, 1.0), {"gamma": 2.0}).r, 0.5, 2e-3, "A quarter halves up")
    easel.free()

    easel = SaEasel.create_default(CANVAS)
    assert_almost_eq(_through(easel, Color(1.0, 1.0, 1.0, 1.0), {"gamma": 2.0}).r, 1.0, 2e-3, "White stays white")
    easel.free()

    easel = SaEasel.create_default(CANVAS)
    assert_almost_eq(_through(easel, Color(0.0, 0.0, 0.0, 1.0), {"gamma": 2.0}).r, 0.0, 2e-3, "and black stays black")
    easel.free()


## The output range is where the input range lands, so a full input range and
## a narrow output one is a flattened picture rather than a shifted one.
func test_the_output_range_is_where_the_input_lands() -> void:
    var easel := SaEasel.create_default(CANVAS)
    var values := {"out_black": 0.2, "out_white": 0.8}
    assert_almost_eq(_through(easel, Color(0.0, 0.0, 0.0, 1.0), values).r, 0.2, 2e-3, "Black lands on the output black")
    easel.free()

    easel = SaEasel.create_default(CANVAS)
    assert_almost_eq(_through(easel, Color(1.0, 1.0, 1.0, 1.0), values).r, 0.8, 2e-3, "and white on the output white")
    easel.free()


## One channel moves and the other two do not, which is the whole of the
## channel dropdown.
func test_a_channel_moves_alone() -> void:
    var easel := SaEasel.create_default(CANVAS)
    var out := _through(easel, Color(0.5, 0.5, 0.5, 1.0), {"in_black": 0.25, "channel": "red"})
    assert_almost_eq(out.r, 1.0 / 3.0, 2e-3, "Red went through the curve")
    assert_almost_eq(out.g, 0.5, 2e-3, "green did not")
    assert_almost_eq(out.b, 0.5, 2e-3, "and neither did blue")
    easel.free()


## The Oklab channel moves what the eye reads as lightness, so a mid grey
## comes back a different grey and stays grey.
func test_the_lightness_channel_is_oklab() -> void:
    var easel := SaEasel.create_default(CANVAS)
    var out := _through(easel, Color(0.5, 0.5, 0.5, 1.0), {"gamma": 2.0, "channel": "lightness"})
    assert_true(out.r > 0.55, "A mid grey came back lighter, got %.3f" % out.r)
    assert_almost_eq(out.g, out.r, 2e-3, "and it is still grey")
    assert_almost_eq(out.b, out.r, 2e-3, "on every channel")
    easel.free()


## Apply is one history step, so one undo puts the layer back whole. The same
## contract the other two adjustments hold.
func test_apply_is_one_undoable_step() -> void:
    var easel := SaEasel.create_default(CANVAS)
    var before := easel.document.history.step_count()
    var after := _through(easel, Color(0.5, 0.5, 0.5, 1.0), {"in_black": 0.25})
    assert_eq(easel.document.history.step_count(), before + 1, "One step")
    assert_almost_eq(after.r, 1.0 / 3.0, 2e-3, "and the pixels moved")
    easel.document.undo_redo.undo()
    assert_almost_eq(_texel(easel.document.get_node("Layer 1")).r, 0.5, 2e-3, "which one undo puts back")
    easel.free()


## The six numbers, and where the sixth goes. The push constant is full, so
## the channel rides in the slot the origin pair leaves over, and a kind with
## five parameters must still leave it zero.
func test_the_channel_rides_in_the_spare_slot() -> void:
    var params := SaPointAdjust.params_for(SaPointAdjust.LEVELS, {"in_black": 0.25, "channel": "blue"})
    assert_eq(params.size(), 6, "Levels has six parameters")
    assert_almost_eq(float(params[5]), 3.0, 1e-6, "and the sixth is the channel's index")

    var push := SaPointAdjust.push_constant(params, SaColorSpace.srgb())
    assert_eq(push.size(), 32, "The block is the 128 bytes Vulkan guarantees")
    assert_almost_eq(push[7], 3.0, 1e-6, "with the channel in the eighth float")

    var other := SaPointAdjust.params_for(SaPointAdjust.BRIGHTNESS_CONTRAST, {})
    assert_almost_eq(SaPointAdjust.push_constant(other, SaColorSpace.srgb())[7], 0.0, 1e-6, "and zero for a kind without one")


## A word nothing knows is not a channel, and must not index the array from
## the end the way a -1 would.
func test_an_unknown_channel_is_the_master() -> void:
    var params := SaPointAdjust.params_for(SaPointAdjust.LEVELS, {"channel": "cyan"})
    assert_almost_eq(float(params[5]), 0.0, 1e-6, "An unknown channel is the master")
