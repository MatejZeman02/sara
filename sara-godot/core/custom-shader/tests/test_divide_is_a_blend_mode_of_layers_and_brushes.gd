## Divide is a blend mode of layers and brushes.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter's note of 2026-10-26: "divide blending mode is missing". Divide
## is the backdrop over the source, channel by channel, as Krita and Photoshop
## define it, with nothing clamped, and a source at or under 2^-10 divides by
## that epsilon, `divide_blended` of `libs/composite_blend_modes.gmacs`, so no
## texel is an infinity or a NaN. The layer's composite and
## the brush's commit are one formula, so the suite reads both against the
## same arithmetic, over a ramp that holds 0, negative sources, sources under
## the epsilon and values over 1 on either side.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The composite and the commit are compute passes over real textures.
const REQUIRES_GPU := true

## The kernel's epsilon, 2^-10, a literal in `divide_blended`, written again
## so the suite holds the number rather than reading it from the kernel.
const DIVIDE_SOURCE_EPSILON: float = 0.0009765625
const SIDE: int = 256
## What float precision is taken to be: one quotient of 32-bit floats is a
## rounding or two from the exact one, so the bound is relative to the answer.
const RELATIVE: float = 1e-6
## The bound on a document with a curve, where the GPU's pow() decodes both
## sides and encodes the quotient. Measured on the reference GPU, its worst was
## 2.7e-3 of the answer, at an encoded 575 from a quotient of 3.7 million in
## light, and 2.2e-5 at an encoded 19, white over black. GDScript's pow() in
## doubles is the reference, so the bound is the device's curve and not
## Divide's.
const RELATIVE_THROUGH_A_CURVE: float = 5e-3
## Backdrops, black and values past white among them.
const BACKDROPS: Array[float] = [0.0, 0.001, 0.2, 0.5, 1.0, 1.5, 4.0, 32.0]
## Sources, a negative one, black, two under the epsilon, the epsilon itself and
## values past white among them.
const SOURCES: Array[float] = [-0.25, 0.0, 0.0001, 0.0009, DIVIDE_SOURCE_EPSILON, 0.002, 0.25, 0.5, 1.0, 1.75, 6.0]


## The skeleton registers Divide for layers and brushes alike, under the same
## descriptor as the others, and every menu lists it straight after Colour
## Dodge.
func test_divide_is_registered_beside_colour_dodge_for_layers_and_brushes() -> void:
    var registry: SaBlendModeRegistry = Fixtures.make_registries().blend_modes
    assert_true(registry.has(&"divide"), "Divide is a registered mode")
    var descriptor := registry.get_descriptor(&"divide")
    if descriptor == null:
        return
    assert_eq(descriptor.display_name, "Divide", "It is named Divide")
    assert_false(descriptor.hidden_in_layer_list, "A layer's list offers it")
    assert_false(descriptor.internal, "and the brush's list does too")
    assert_true(descriptor.sentence != "", "Its row has a hover that says what it does")
    assert_true(registry.resolve_kernel(&"divide") >= 0, "Its kernel compiles and resolves")
    for in_layers: bool in [true, false]:
        var ids: Array[StringName] = []
        for entry: SaBlendModeDescriptor in registry.list_ui_entries(in_layers):
            ids.append(entry.id)
        assert_eq(ids.find(&"divide"), ids.find(&"color_dodge") + 1, "Divide follows Colour Dodge in the menu")


## A layer in Divide composites every texel of the ramp to the backdrop over
## the source, with no NaN and no infinity, on a linear document.
func test_a_divide_layer_is_the_backdrop_over_the_source_at_every_texel() -> void:
    _assert_quotients(_composite(SaColorSpace.linear_srgb()), SaTransferFunction.linear(), "The layer's composite")


## On a document that stores encoded sRGB the quotient is taken in linear
## light, the curve off both sides and put back on the answer.
func test_on_an_srgb_document_divide_divides_the_light_and_not_the_encoded_numbers() -> void:
    _assert_quotients(_composite(SaColorSpace.srgb()), SaTransferFunction.srgb(), "The layer's composite on sRGB")


## A brush stroke in Divide commits the same quotient over the layer's own
## paint, so the brush and the layer cannot disagree.
func test_a_divide_stroke_commits_the_backdrop_over_the_stroke_at_every_texel() -> void:
    var compositor := SaCompositor.new()
    compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(SIDE, SIDE), compositor)
    _write(doc.active_layer.get_or_create_chunk(Vector2i(0, 0)).albedo(), _backdrop)

    doc.begin_stroke(1.0, &"divide")
    assert_eq(doc.stroke_layer.blend_mode, &"divide", "The buffer carries the brush's Divide to the commit")
    _write(doc.stroke_layer.get_or_create_chunk(Vector2i(0, 0)).albedo(), _source)
    doc.commit_stroke()

    var curve := doc.color_space.transfer
    assert_false(curve.is_identity(), "The default document stores encoded sRGB, so the commit decodes it")
    _assert_quotients(_read(doc.active_layer.chunks[Vector2i(0, 0)].albedo()), curve, "The brush's commit")
    doc.free()


## The ramp's source composited in Divide over its backdrop, in a document of
## *space*, read back.
func _composite(space: SaColorSpace) -> Array[Color]:
    var canvas := SaTexture.new(Vector2i(SIDE, SIDE))
    var chunk := SaTexture.new(Vector2i(SIDE, SIDE))
    _write(canvas, _backdrop)
    _write(chunk, _source)
    var comp := SaCompute.new("composite")
    comp.set_texture(0, canvas.rid)
    comp.set_texture(1, chunk.rid)
    comp.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0, space))
    comp.dispatch(comp.index_of_kernel("divide"), SIDE >> 3, SIDE >> 3, 1)
    return _read(canvas)


## Reads every texel of *texels* against the formula on the ramp, taken in the
## light *curve* decodes and encoded again, and none of them a NaN or an
## infinity.
func _assert_quotients(texels: Array[Color], curve: SaTransferFunction, what: String) -> void:
    var worst := 0.0
    var not_finite := 0
    var over_white := 0
    for y: int in SIDE:
        for x: int in SIDE:
            var under := _backdrop(x, y)
            var over := _source(x, y)
            var texel: Color = texels[y * SIDE + x]
            for channel: int in 3:
                var light := curve.decode(under[channel]) / maxf(curve.decode(over[channel]), DIVIDE_SOURCE_EPSILON)
                var want := curve.encode(light)
                var got: float = texel[channel]
                if is_nan(got) or is_inf(got):
                    not_finite += 1
                    continue
                worst = maxf(worst, absf(got - want) / maxf(absf(want), 1.0))
                if got > 1.0:
                    over_white += 1
            worst = maxf(worst, absf(texel.a - 1.0))
    assert_eq(not_finite, 0, "%s has no NaN and no infinity" % what)
    var worst_said := "the worst off by %s of the answer" % worst
    var bound := RELATIVE if curve.is_identity() else RELATIVE_THROUGH_A_CURVE
    assert_true(worst < bound, "%s is the backdrop over the source at every texel, %s" % [what, worst_said])
    assert_true(over_white > 0, "%s goes past white unclamped, at %d channels" % [what, over_white])


## The backdrop at (*x*, *y*), opaque, each channel walking the ramp on its own
## step so every pair of backdrop and source meets somewhere in the chunk.
func _backdrop(x: int, y: int) -> Color:
    return Color(
        BACKDROPS[y % BACKDROPS.size()], BACKDROPS[(x + y) % BACKDROPS.size()], BACKDROPS[(5 * y + x) % BACKDROPS.size()], 1.0
    )


## The source at (*x*, *y*), opaque.
func _source(x: int, y: int) -> Color:
    return Color(SOURCES[x % SOURCES.size()], SOURCES[(3 * x + y) % SOURCES.size()], SOURCES[(x + 7 * y) % SOURCES.size()], 1.0)


## Writes *colour_at* over every texel of *texture*.
func _write(texture: SaTexture, colour_at: Callable) -> void:
    var data := PackedByteArray()
    data.resize(SIDE * SIDE * 16)
    for y: int in SIDE:
        for x: int in SIDE:
            var colour: Color = colour_at.call(x, y)
            var at := (y * SIDE + x) * 16
            data.encode_float(at, colour.r)
            data.encode_float(at + 4, colour.g)
            data.encode_float(at + 8, colour.b)
            data.encode_float(at + 12, colour.a)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, data)


## Every texel of *texture*, row by row.
func _read(texture: SaTexture) -> Array[Color]:
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var texels: Array[Color] = []
    texels.resize(SIDE * SIDE)
    for at: int in SIDE * SIDE:
        var offset := at * 16
        var red := data.decode_float(offset)
        var green := data.decode_float(offset + 4)
        var blue := data.decode_float(offset + 8)
        texels[at] = Color(red, green, blue, data.decode_float(offset + 12))
    return texels
