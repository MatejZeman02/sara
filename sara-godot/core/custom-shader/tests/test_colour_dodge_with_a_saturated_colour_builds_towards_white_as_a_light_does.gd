## Colour Dodge with a saturated colour builds towards white, as a light
## does.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter's note of 2026-10-27: "If I pick orange colour and paint with it,
## it should get to white at some point". The W3C quotient clamped each channel
## on its own, so a channel the colour held none of never rose. Now the light the
## clamp cut off is counted and the colour is mixed towards white by it,
## `dodge_spilled` of `libs/composite_blend_modes.gmacs`. The layer's composite
## and the brush's commit are one formula, so both are read here, pass after
## pass, each over its own result.
##
## The grey is the middle grey of light, 0.18, on a linear document. Over an
## encoded 0.5 the W3C quotient alone already puts orange's green at white and
## its red past it, so one pass there is white under this rule and the first
## pass in its own hue is not seen.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The composite and the commit are compute passes over real textures.
const REQUIRES_GPU := true

const SIDE: int = 8
const PASSES: int = 20
const ORANGE := Color(1.0, 0.5, 0.0, 1.0)
const MIDDLE_GREY := Color(0.18, 0.18, 0.18, 1.0)
## How close the last pass must come to white, the row's 0.02.
const WHITE_WITHIN: float = 0.02
## Float rounding between two passes that should hold a value still.
const STILL: float = 1e-5


## Orange dodged over middle grey twenty times as a layer: the brightness never
## falls, the saturation falls from the pass after a channel reached white, and
## the last pass is white.
func test_orange_dodged_over_a_grey_layer_again_and_again_ends_white() -> void:
    _assert_builds_to_white(_layer_passes(SaColorSpace.linear_srgb()), "The layer")


## The same as a brush's commit, the stroke over the layer's own paint.
func test_an_orange_dodge_stroke_laid_again_and_again_ends_white() -> void:
    _assert_builds_to_white(_stroke_passes(), "The brush")


## One pass is orange in hue, the hue the W3C quotient gives, which the spill
## keeps: red the brightest channel, blue the darkest, between red and yellow.
func test_one_pass_of_orange_over_middle_grey_is_orange() -> void:
    var first: Color = _layer_passes(SaColorSpace.linear_srgb())[0]
    assert_true(first.r >= first.g and first.g > first.b, "Red leads and blue trails, read %s" % first)
    var hue := first.h * 360.0
    assert_true(hue > 10.0 and hue < 45.0, "One pass is orange in hue, read %.1f degrees" % hue)
    assert_true(first.s < 0.82 - 0.05, "and already paler than the clamp's (1, 0.36, 0.18), read %s" % first)


## A black backdrop stays black under any source, and a pixel with no channel
## past white keeps the W3C numbers exactly.
func test_black_stays_black_and_a_pixel_under_white_keeps_the_formula() -> void:
    var black := _dodge_once(ORANGE, Color(0, 0, 0, 1), SaColorSpace.linear_srgb())
    assert_almost_eq(maxf(black.r, maxf(black.g, black.b)), 0.0, STILL, "Black stays black, read %s" % black)
    var under := _dodge_once(Color(0.5, 0.25, 0.0, 1.0), Color(0.2, 0.3, 0.4, 1.0), SaColorSpace.linear_srgb())
    assert_almost_eq(under.r, 0.4, STILL, "Red is 0.2 / (1 - 0.5)")
    assert_almost_eq(under.g, 0.4, STILL, "Green is 0.3 / (1 - 0.25)")
    assert_almost_eq(under.b, 0.4, STILL, "Blue is the backdrop under a black source")


## A grey source over a grey backdrop is grey at every pass, so the spill never
## tints a colourless light.
func test_a_grey_light_stays_grey() -> void:
    var out := _dodge_once(Color(0.75, 0.75, 0.75, 1.0), Color(0.5, 0.5, 0.5, 1.0), SaColorSpace.srgb())
    assert_almost_eq(out.r, 1.0, STILL, "0.5 / 0.25 passes white, and the grey reads white")
    assert_almost_eq(out.g, out.r, STILL, "Green as red")
    assert_almost_eq(out.b, out.r, STILL, "Blue as red")


func _assert_builds_to_white(passes: Array[Color], who: String) -> void:
    var reached := -1
    for at: int in passes.size():
        var now: Color = passes[at]
        if at > 0:
            var before: Color = passes[at - 1]
            for channel: int in 3:
                var said := "%s pass %d never darkens a channel, %s after %s" % [who, at + 1, now, before]
                assert_true(now[channel] >= before[channel] - STILL, said)
            if reached >= 0 and before.s > STILL:
                var paler := "%s pass %d is paler than the one before, %s after %s" % [who, at + 1, now, before]
                assert_true(now.s < before.s, paler)
        if reached < 0 and maxf(now.r, maxf(now.g, now.b)) >= 1.0 - STILL:
            reached = at
    assert_true(reached >= 0, "%s reaches white in a channel" % who)
    var last: Color = passes[passes.size() - 1]
    for channel: int in 3:
        assert_almost_eq(last[channel], 1.0, WHITE_WITHIN, "%s's last pass is white, read %s" % [who, last])


## The dodge of ORANGE over MIDDLE_GREY as a layer, PASSES times over its own
## result, each pass read.
func _layer_passes(space: SaColorSpace) -> Array[Color]:
    var canvas := SaTexture.new(Vector2i(SIDE, SIDE))
    var chunk := SaTexture.new(Vector2i(SIDE, SIDE))
    _fill(canvas, MIDDLE_GREY)
    _fill(chunk, ORANGE)
    var comp := SaCompute.new("composite")
    comp.set_texture(0, canvas.rid)
    comp.set_texture(1, chunk.rid)
    comp.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0, space))
    var out: Array[Color] = []
    for i: int in PASSES:
        comp.dispatch(comp.index_of_kernel("color_dodge"), 1, 1, 1)
        out.append(_corner(canvas))
    return out


## One dodge of *source* over *backdrop* in a document of *space*.
func _dodge_once(source: Color, backdrop: Color, space: SaColorSpace) -> Color:
    var canvas := SaTexture.new(Vector2i(SIDE, SIDE))
    var chunk := SaTexture.new(Vector2i(SIDE, SIDE))
    _fill(canvas, backdrop)
    _fill(chunk, source)
    var comp := SaCompute.new("composite")
    comp.set_texture(0, canvas.rid)
    comp.set_texture(1, chunk.rid)
    comp.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0, space))
    comp.dispatch(comp.index_of_kernel("color_dodge"), 1, 1, 1)
    return _corner(canvas)


## ORANGE committed PASSES times as a Colour Dodge stroke over MIDDLE_GREY on a
## linear document, each commit read.
func _stroke_passes() -> Array[Color]:
    var compositor := SaCompositor.new()
    compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(256, 256), compositor, SaColorSpace.linear_srgb())
    var chunk_side: int = doc.active_layer.get_or_create_chunk(Vector2i(0, 0)).pixel_size()
    _fill(doc.active_layer.get_or_create_chunk(Vector2i(0, 0)).albedo(), MIDDLE_GREY, chunk_side)
    var out: Array[Color] = []
    for i: int in PASSES:
        doc.begin_stroke(1.0, &"color_dodge")
        _fill(doc.stroke_layer.get_or_create_chunk(Vector2i(0, 0)).albedo(), ORANGE, chunk_side)
        doc.commit_stroke()
        out.append(_corner(doc.active_layer.chunks[Vector2i(0, 0)].albedo()))
    doc.free()
    return out


func _fill(texture: SaTexture, colour: Color, side: int = SIDE) -> void:
    var data := PackedFloat32Array()
    data.resize(side * side * 4)
    for at: int in side * side:
        data[at * 4] = colour.r
        data[at * 4 + 1] = colour.g
        data[at * 4 + 2] = colour.b
        data[at * 4 + 3] = colour.a
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, data.to_byte_array())


func _corner(texture: SaTexture) -> Color:
    var data := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0).to_float32_array()
    return Color(data[0], data[1], data[2], data[3])
