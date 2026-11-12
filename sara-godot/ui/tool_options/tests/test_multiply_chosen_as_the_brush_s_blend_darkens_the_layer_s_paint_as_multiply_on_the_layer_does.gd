## Multiply chosen as the brush's blend darkens the layer's paint as
## Multiply on the layer does.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The report was that Multiply from the top menu bar paints the same colour as
## Normal for strokes, but is completely different when the whole layer's blend
## mode is Multiply.
##
## Measured through the door, the brush's Multiply is right: a
## stroke over the layer's own paint darkened it to the texel the layer's
## Multiply gave, and a stroke on an empty layer laid its own colour, which is
## what a painter sees, since an empty layer has nothing to multiply. So the
## numbers here hold the commit where it is, and the last test holds the
## sentence the bar's chip now says about it.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The commit is a compute pass over real chunks, and the bar's blend labels
## name the document's colour space.
const REQUIRES_GPU := true

const SIDE: int = 256
## What float precision is taken to be here: the kernel reads and writes
## 32-bit floats, and one product is a rounding or two away from the exact one.
const EPSILON: float = 1e-5


## Every texel of a stroke laid in Multiply over the layer's own paint is the
## product of the two, channel by channel. Both sides vary across the chunk, so
## a kernel that read one texel, or mixed as Normal, could not pass on any of
## them.
func test_a_multiply_stroke_over_the_layers_paint_is_their_product() -> void:
    var doc := _document()
    _write(doc.active_layer.get_or_create_chunk(Vector2i(0, 0)).albedo(), _paint)

    doc.begin_stroke(1.0, SaLayer.BLEND_MODE.MULTIPLY)
    assert_eq(doc.stroke_layer.blend_mode, SaLayer.BLEND_MODE.MULTIPLY, "The buffer carries the brush's Multiply to the commit")
    _write(doc.stroke_layer.get_or_create_chunk(Vector2i(0, 0)).albedo(), _stroke)
    doc.commit_stroke()

    var got := _read(doc.active_layer.chunks[Vector2i(0, 0)].albedo())
    var worst := 0.0
    var darker := 0
    for y: int in SIDE:
        for x: int in SIDE:
            var under := _paint(x, y)
            var over := _stroke(x, y)
            var texel: Color = got[y * SIDE + x]
            for channel: int in 3:
                worst = maxf(worst, absf(texel[channel] - under[channel] * over[channel]))
            worst = maxf(worst, absf(texel.a - 1.0))
            if texel.r < under.r or texel.g < under.g or texel.b < under.b:
                darker += 1
    assert_true(worst < EPSILON, "Every texel is the multiply of the layer's paint and the stroke, the worst off by %s" % worst)
    assert_true(darker * 2 > SIDE * SIDE, "and the stroke darkened the paint it landed on, at %d texels" % darker)
    doc.free()


## On an empty layer there is nothing to multiply, and the stroke lands as its
## own colour, which is what a painter sees on a fresh layer.
func test_a_multiply_stroke_on_an_empty_layer_lays_its_own_colour() -> void:
    var doc := _document()
    assert_false(doc.active_layer.chunks.has(Vector2i(0, 0)), "The layer starts with no paint here")

    doc.begin_stroke(1.0, SaLayer.BLEND_MODE.MULTIPLY)
    _write(doc.stroke_layer.get_or_create_chunk(Vector2i(0, 0)).albedo(), _stroke)
    doc.commit_stroke()

    var got := _read(doc.active_layer.chunks[Vector2i(0, 0)].albedo())
    var worst := 0.0
    for y: int in SIDE:
        for x: int in SIDE:
            var over := _stroke(x, y)
            var texel: Color = got[y * SIDE + x]
            for channel: int in 4:
                worst = maxf(worst, absf(texel[channel] - over[channel]))
    assert_true(worst < EPSILON, "Every texel is the stroke's own colour, the worst off by %s" % worst)
    doc.free()


## The bar's chip says, under the mode's own sentence, what a brush's blend
## mixes with and where Multiply with the layers below is set. The Layers
## docker's chip is a layer's blend and says nothing of the kind.
func test_the_bars_blend_chip_says_what_the_brushs_blend_mixes_with() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var registries := Fixtures.make_registries(surface)
    var bar := ToolOptionsBar.new()
    bar.target_tool_machine = machine
    bar._ready()
    bar.bind_registries(registries.blend_modes)

    var chip := bar.control_for(ToolOptionsBar.BLEND_KEY) as BlendModeButton
    assert_not_null(chip, "The bar has a blend chip")
    if chip != null:
        chip.select_mode(SaLayer.BLEND_MODE.MULTIPLY)
        assert_true(chip.tooltip_text.contains(BlendModeButton.BRUSH_SCOPE), "Its hover names what the brush's blend mixes with")
        assert_true(chip.tooltip_text.contains(BlendModeButton.BRUSH_SCOPE_BELOW), "and what mixes below")
        assert_true(chip.tooltip_text.contains("Layers docker"), "and where to set the blend that mixes with the layers below")

    var docker_chip := BlendModeButton.new()
    docker_chip.registry = registries.blend_modes
    docker_chip.refresh()
    docker_chip.select_mode(SaLayer.BLEND_MODE.MULTIPLY)
    assert_false(docker_chip.tooltip_text.contains(BlendModeButton.BRUSH_SCOPE), "A layer's chip carries no such sentence")

    docker_chip.free()
    bar.free()
    Fixtures.teardown(surface, machine)


## A document with a compositor that knows the blend modes. Without the
## registry every mode resolves to Normal, and the first test would measure
## Normal and fail for the wrong reason.
func _document() -> SaDocument:
    var compositor := SaCompositor.new()
    compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(SIDE, SIDE), compositor)
    return doc


## The layer's paint, opaque, a different colour at every texel.
func _paint(x: int, y: int) -> Color:
    return Color(0.2 + 0.7 * x / SIDE, 0.9 - 0.6 * y / SIDE, 0.5, 1.0)


## The stroke's colour, opaque and varying the other way.
func _stroke(x: int, y: int) -> Color:
    return Color(0.4 + 0.5 * y / SIDE, 0.3, 0.1 + 0.8 * x / SIDE, 1.0)


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
