## Red-eye Removal brings a red pupil's red down to its green
## and blue in linear light and leaves skin and grey as they were.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The layer is one chunk in vertical bands, one colour each, baked through
## `SaFilterOps.apply_once` as the Filter menu's Apply does. Every reading is
## taken back to linear light through the document's own transfer curve, the
## light the kernel works in, so the sums below are the kernel's.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const SIZE := Vector2i(SaChunk.SIZE, SaChunk.SIZE)
const CHUNK := Vector2i(0, 0)

## The three texels, as the painter sees them on the sRGB curve: a
## flash's saturated red, a skin tone and a mid grey.
const RED := Color(0.8, 0.1, 0.1, 1.0)
const SKIN := Color(0.88, 0.67, 0.55, 1.0)
const GREY := Color(0.5, 0.5, 0.5, 1.0)
## A red past white over a dim green and blue, and one over a green and blue
## below nought, both still red eyes.
const BRIGHT_RED := Color(4.0, 0.3, 0.2, 1.0)
const RED_OVER_NEGATIVE := Color(0.9, -0.05, -0.05, 1.0)

## How far a reading may sit from the kernel's sum, float32 on the GPU against
## the double here, through a transfer curve each way.
const NEAR := 1e-4

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _key: StringName = &""


func before_each() -> void:
    _open(null)


func after_each() -> void:
    _close()


## An easel of one chunk stored in *space*, the bench's float sRGB one for
## null, with Red-eye Removal registered in its chain.
func _open(space: SaColorSpace) -> void:
    _close()
    if space == null:
        _easel = Bench.easel(SIZE)
    else:
        _easel = SaEasel.create_default(SIZE, null, space)
        _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
        _easel.compositor.filter_chain.registry = SaFilterRegistry.new()
    _doc = _easel.document
    (_doc.get_node("Background") as SaLayer).visible = false
    _layer = _doc.get_node("Layer 1") as SaLayer
    _doc.set_active_layer(_layer)
    var filter := SaRedEyeRemovalFilter.new()
    _easel.compositor.filter_chain.registry.register(filter, OWNER)
    _key = SaFilterRegistry.key_for(OWNER, filter)


func _close() -> void:
    if _easel != null:
        _easel.free()
        _easel = null
    _doc = null
    _layer = null


## The layer's chunk painted in as many vertical bands as *bands* has colours,
## each written as stored, left to right.
func _paint_bands(bands: Array[Color]) -> void:
    var texture := _layer.get_or_create_chunk(CHUNK).field(SaFieldSpec.ALBEDO)
    var values := PackedFloat32Array()
    values.resize(texture.size.x * texture.size.y * 4)
    for y in texture.size.y:
        for x in texture.size.x:
            var c: Color = bands[mini(floori(float(x * bands.size()) / float(texture.size.x)), bands.size() - 1)]
            var i := (y * texture.size.x + x) * 4
            values[i] = c.r
            values[i + 1] = c.g
            values[i + 2] = c.b
            values[i + 3] = c.a
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, values.to_byte_array())
    _doc.history.reset()
    _doc.undo_redo.clear_history()


## The stored texel in the middle of band *index* of *count*.
func _band(index: int, count: int) -> Color:
    var texture := _layer.get_field(CHUNK)
    var across := float((2 * index + 1) * texture.size.x) / float(2 * count)
    var at := Vector2i(floori(across), floori(float(texture.size.y) / 2.0))
    return Bench.texel(texture, at)


## *stored* taken off the sRGB curve, channel by channel, alpha kept.
func _light(stored: Color) -> Color:
    var curve := _doc.color_space.transfer
    return Color(curve.decode(stored.r), curve.decode(stored.g), curve.decode(stored.b), stored.a)


func _bake(values: Dictionary) -> bool:
    return SaFilterOps.new(_doc).apply_once(_layer, _key, values, "Red-eye Removal")


static func _apart(a: Color, b: Color) -> float:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


func test_a_red_pupil_turns_a_dark_neutral_and_skin_and_grey_are_left() -> void:
    var bands: Array[Color] = [RED, SKIN, GREY]
    _paint_bands(bands)
    var before: Array[Color] = [_band(0, 3), _band(1, 3), _band(2, 3)]
    var threshold: float = SaRedEyeRemovalFilter.DEFAULTS["threshold"]
    var red_before := _light(before[0])
    assert_true(red_before.r > threshold * maxf(red_before.g, red_before.b), "The red stands past the threshold before")
    var skin_light := _light(before[1])
    var skin_ratio := skin_light.r / maxf(skin_light.g, skin_light.b)
    assert_true(skin_ratio < threshold, "and the skin's red is %s times its green, under the threshold" % skin_ratio)
    assert_true(_bake({}), "Bake writes the layer at the default sliders")
    var red := _light(_band(0, 3))
    var neutral := 0.5 * (red_before.g + red_before.b)
    assert_true(red.r <= threshold * maxf(red.g, red.b), "The red's red is within its threshold of green and blue: %s" % red)
    assert_true(absf(red.r - neutral) <= NEAR, "and at full strength on their mean, %s against %s" % [red.r, neutral])
    assert_true(absf(red.g - red_before.g) <= NEAR and absf(red.b - red_before.b) <= NEAR, "Its green and blue are kept")
    assert_true(maxf(red.r, maxf(red.g, red.b)) < 0.02, "so it is a dark neutral, %s" % red)
    assert_eq(_band(1, 3), before[1], "The skin tone is exactly as it was")
    assert_eq(_band(2, 3), before[2], "and so is the grey")
    assert_eq(_band(0, 3).a, 1.0, "Alpha is kept")


func test_a_red_past_white_comes_down_and_nothing_clamps() -> void:
    var bands: Array[Color] = [BRIGHT_RED, RED_OVER_NEGATIVE]
    _paint_bands(bands)
    var bright_before := _light(_band(0, 2))
    var negative_before := _light(_band(1, 2))
    assert_true(_bake({}), "Bake")
    var bright := _light(_band(0, 2))
    var bright_neutral := 0.5 * (bright_before.g + bright_before.b)
    assert_true(
        absf(bright.r - bright_neutral) <= NEAR, "A red of %s lands on %s, read %s" % [bright_before.r, bright_neutral, bright.r]
    )
    var negative := _light(_band(1, 2))
    assert_true(negative.r < 0.0, "A red over a green and blue below nought goes below nought with them, %s" % negative.r)
    assert_true(absf(negative.r - 0.5 * (negative_before.g + negative_before.b)) <= NEAR, "on their mean")


func test_half_strength_takes_half_the_red_away() -> void:
    var bands: Array[Color] = [RED, SKIN]
    _paint_bands(bands)
    var before := _light(_band(0, 2))
    var skin := _band(1, 2)
    assert_true(_bake({"threshold": 4.0, "strength": 50}), "Bake at half strength")
    var after := _light(_band(0, 2))
    var halfway := lerpf(before.r, 0.5 * (before.g + before.b), 0.5)
    assert_true(absf(after.r - halfway) <= NEAR, "The red is halfway to the neutral, %s against %s" % [after.r, halfway])
    assert_eq(_band(1, 2), skin, "and the skin is untouched")


func test_a_threshold_above_the_red_leaves_it_alone() -> void:
    var bands: Array[Color] = [RED]
    _paint_bands(bands)
    var before := _band(0, 1)
    var light := _light(before)
    var ratio := light.r / maxf(light.g, light.b)
    assert_true(_bake({"threshold": ratio + 1.0, "strength": 100}), "Bake with the threshold past the red's ratio")
    assert_eq(_band(0, 1), before, "A red under the threshold is not an eye and is left as it was")


func test_it_works_in_linear_light_on_an_oklab_document() -> void:
    _open(SaColorSpace.oklab())
    _layer.fill(_doc.color_space.from_display(RED))
    var lit_before := _display_light(_doc.color_space.to_display(Bench.texel(_layer.get_field(CHUNK), Vector2i(100, 100))))
    assert_true(_bake({}), "Bake on an Oklab document")
    var lit := _display_light(_doc.color_space.to_display(Bench.texel(_layer.get_field(CHUNK), Vector2i(100, 100))))
    var neutral := 0.5 * (lit_before.g + lit_before.b)
    assert_true(
        absf(lit.r - neutral) <= 1e-3, "The red in light lands on its green and blue's mean, %s against %s" % [lit.r, neutral]
    )
    assert_true(absf(lit.g - lit_before.g) <= 1e-3 and absf(lit.b - lit_before.b) <= 1e-3, "which are kept, %s" % lit)


## A colour as displayed on the sRGB curve, in linear light.
static func _display_light(shown: Color) -> Color:
    var curve := SaTransferFunction.srgb()
    return Color(curve.decode(shown.r), curve.decode(shown.g), curve.decode(shown.b), shown.a)


func test_the_filter_browser_finds_it_under_colour_by_red_eye() -> void:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    var mod := BaseModule.new()
    mod.register(registries.context.for_module(mod.get_id()))
    var browser := SaFilterBrowser.new()
    browser.watch(registries.filters, registries.commands)
    browser.search_for("red-eye")
    var listed: Array = browser.describe()["listed"]
    var key := SaFilterRegistry.key_for(mod.get_id(), SaRedEyeRemovalFilter.new())
    assert_eq(listed, [String(key)], "Searching 'red-eye' lists Red-eye Removal alone: %s" % [listed])
    assert_eq(registries.filters.section_of(key), &"color", "under Colour")
    browser.free()
    mod.unregister(registries.context.for_module(mod.get_id()))
