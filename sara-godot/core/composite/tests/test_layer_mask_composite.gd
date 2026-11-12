## The composite reads a layer's mask: the layer's alpha is
## multiplied by the mask's coverage per chunk and per dirty rectangle, a mask
## switched off reads as one, and a layer that is masked and clipped is a chain
## through the mask's scratch onto its base's plate.
##
## Every case runs twice, once with the masked layer folded into a cache and once
## with it as the active layer, because those are two of the four places a chunk
## becomes a source and each applies the mask on its own.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const RED := Color(1, 0, 0, 1)
const BLUE := Color(0, 0, 1, 1)

## The three columns of the first chunk the painted mask holds, and a texel in
## each: shown, hidden, half.
const SHOWN_AT := Vector2i(40, 10)
const HIDDEN_AT := Vector2i(120, 10)
const HALF_AT := Vector2i(200, 10)
## A texel of the second chunk, where the mask was never painted.
const UNPAINTED_AT := Vector2i(300, 10)


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(512, 256))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


func _texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


func _composite(easel: SaEasel) -> void:
    easel.document.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()


## Writes the three columns into *layer*'s mask at the first chunk: one up to
## x 85, zero up to 170, a half beyond.
func _paint_mask(layer: SaLayer) -> void:
    var texture := layer.add_mask().get_or_create(Vector2i(0, 0))
    var values := PackedFloat32Array()
    values.resize(texture.size.x * texture.size.y)
    for y in texture.size.y:
        for x in texture.size.x:
            values[y * texture.size.x + x] = 1.0 if x < 85 else (0.0 if x < 170 else 0.5)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, values.to_byte_array())


func _add(doc: SaDocument, layer_name: String) -> SaLayer:
    var layer := SaLayerOps.new(doc).add()
    layer.name = layer_name
    return layer


func _assert_colour(actual: Color, expected: Color, what: String) -> void:
    assert_almost_eq(actual.r, expected.r, 0.02, what + ", red")
    assert_almost_eq(actual.g, expected.g, 0.02, what + ", green")
    assert_almost_eq(actual.b, expected.b, 0.02, what + ", blue")


## Red over the grey background, with the painted mask. *active* picks the
## masked layer rather than Layer 1 under it.
func _masked_red(active: bool) -> SaEasel:
    var easel := _easel()
    var doc := easel.document
    var masked := _add(doc, "Masked")
    doc.fill_layer(RED, masked)
    _paint_mask(masked)
    doc.set_active_layer(masked if active else doc.get_node("Layer 1") as SaLayer)
    return easel


func _check_masked_red(active: bool) -> void:
    var where := " (active)" if active else " (folded)"
    var easel := _masked_red(active)
    _composite(easel)
    _assert_colour(_texel(easel.output, SHOWN_AT), RED, "Where the mask is one the layer shows whole" + where)
    _assert_colour(_texel(easel.output, HIDDEN_AT), Color(0.5, 0.5, 0.5), "Where it is zero the background shows" + where)
    _assert_colour(_texel(easel.output, HALF_AT), Color(0.75, 0.25, 0.25), "Where it is a half, half the layer" + where)
    _assert_colour(_texel(easel.output, UNPAINTED_AT), RED, "A chunk the mask never held there shows whole" + where)

    var masked := easel.document.get_node("Masked") as SaLayer
    masked.mask.enabled = false
    _composite(easel)
    for at: Vector2i in [SHOWN_AT, HIDDEN_AT, HALF_AT]:
        _assert_colour(_texel(easel.output, at), RED, "A mask switched off reads as one at %s%s" % [at, where])
    easel.free()


func test_the_composite_multiplies_the_alpha_by_the_mask_folded() -> void:
    _check_masked_red(false)


func test_the_composite_multiplies_the_alpha_by_the_mask_active() -> void:
    _check_masked_red(true)


## A red base with the painted mask and a blue layer clipped to it: the clip
## follows what the base shows, so the blue is hidden where the base is, and
## where the base is half shown the group is blue at half over the grey, with
## none of the red, as a clip group composites.
func _check_masked_base_under_a_clip(clipped_active: bool) -> void:
    var where := " (active)" if clipped_active else " (folded)"
    var easel := _easel()
    var doc := easel.document
    var base := _add(doc, "Base")
    doc.fill_layer(RED, base)
    _paint_mask(base)
    var clipped := _add(doc, "Clipped")
    doc.fill_layer(BLUE, clipped)
    SaLayerStack.set_clip_to_below(doc, clipped, true)
    doc.set_active_layer(clipped if clipped_active else doc.get_node("Layer 1") as SaLayer)
    _composite(easel)
    _assert_colour(_texel(easel.output, SHOWN_AT), BLUE, "Over the shown base the clipped layer shows" + where)
    _assert_colour(_texel(easel.output, HIDDEN_AT), Color(0.5, 0.5, 0.5), "Where the base is hidden so is the clip" + where)
    _assert_colour(_texel(easel.output, HALF_AT), Color(0.25, 0.25, 0.75), "Over a half-shown base, half the clip" + where)
    easel.free()


func test_a_masked_layer_under_a_clipped_layer_folded() -> void:
    _check_masked_base_under_a_clip(false)


func test_a_masked_layer_under_a_clipped_layer_active() -> void:
    _check_masked_base_under_a_clip(true)


## A red base filled everywhere and a blue layer clipped to it that carries the
## painted mask: mask first, then laid on the base's plate.
func _check_a_masked_layer_that_is_clipped(clipped_active: bool) -> void:
    var where := " (active)" if clipped_active else " (folded)"
    var easel := _easel()
    var doc := easel.document
    var base := _add(doc, "Base")
    doc.fill_layer(RED, base)
    var clipped := _add(doc, "Clipped")
    doc.fill_layer(BLUE, clipped)
    SaLayerStack.set_clip_to_below(doc, clipped, true)
    _paint_mask(clipped)
    doc.set_active_layer(clipped if clipped_active else doc.get_node("Layer 1") as SaLayer)
    _composite(easel)
    _assert_colour(_texel(easel.output, SHOWN_AT), BLUE, "Where its mask is one the clipped layer shows" + where)
    _assert_colour(_texel(easel.output, HIDDEN_AT), RED, "Where it is zero the base shows" + where)
    _assert_colour(_texel(easel.output, HALF_AT), Color(0.5, 0, 0.5), "Where it is a half, half of it" + where)
    easel.free()


func test_a_masked_layer_that_is_itself_clipped_folded() -> void:
    _check_a_masked_layer_that_is_clipped(false)


func test_a_masked_layer_that_is_itself_clipped_active() -> void:
    _check_a_masked_layer_that_is_clipped(true)


## An unmasked layer, and one whose mask is off, take no mask pass: the scratch
## is never allocated, which is the dispatch count of an unmasked document.
func test_an_unmasked_document_takes_no_mask_pass() -> void:
    var easel := _easel()
    var doc := easel.document
    var plain := _add(doc, "Plain")
    doc.fill_layer(RED, plain)
    _composite(easel)
    doc.set_active_layer(plain)
    _composite(easel)
    assert_null(easel.compositor._flat._mask_scratch, "No mask, no mask scratch")
    var masked := _add(doc, "Masked")
    doc.fill_layer(BLUE, masked)
    masked.add_mask()
    masked.mask.enabled = false
    _composite(easel)
    doc.set_active_layer(masked)
    _composite(easel)
    assert_null(easel.compositor._flat._mask_scratch, "A mask switched off takes no pass either")
    easel.free()
