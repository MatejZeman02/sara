## An Exposure filter moves the values by stops, through Bake, Attach and Layer
## alike.
##
## The rule: "'normal exposure' is the same exposure
## slider as inside the darktable. It is a filter that bakes/attach/layer
## changes the exposure of the values. It is not just for viewing on canvas, it
## physically moves the values." The filter multiplies every channel by two to
## the power of its stops in linear light.
##
## A linear document holds (0.25, 0.5, -0.1), the negative channel being one a
## clamp would lose, and +2 stops reads (1.0, 2.0, -0.4) from the baked layer,
## from the composite with the record attached and from the composite under a
## filter layer. A document on the sRGB curve is decoded, scaled and encoded
## again, so -1 stop halves the light it decodes to. A group carrying the record
## shows its composite scaled and leaves its layers' own pixels alone.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const SIZE := Vector2i(256, 256)
const PROBE := Vector2i(100, 100)
const TOLERANCE := 1.0e-3

const PAINT := Color(0.25, 0.5, -0.1, 1.0)
const PLUS_TWO := Color(1.0, 2.0, -0.4, 1.0)
## A colour as the sRGB curve stores it, whose light is read back through the
## curve and not assumed.
const ENCODED := Color(0.7, 0.4, 0.2, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _types: SaLayerTypeRegistry = null


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types


func after_each() -> void:
    if _easel != null:
        _easel.free()
    _easel = null
    _doc = null
    _layer = null


## A document in *space* with its one paint layer filled with *colour* and its
## grey background hidden, the exposure registered in the compositor's chain.
func _painting(space: SaColorSpace, colour: Color) -> void:
    _easel = SaEasel.create_default(SIZE, null, space)
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var filters := SaFilterRegistry.new()
    filters.register(SaExposureFilter.new(), OWNER)
    _easel.compositor.filter_chain.registry = filters
    _doc = _easel.document
    (_doc.get_node("Background") as SaLayer).visible = false
    _layer = _doc.get_node("Layer 1") as SaLayer
    _doc.set_active_layer(_layer)
    _layer.get_or_create_chunk(Vector2i.ZERO).clear(colour)


func _key() -> StringName:
    return SaFilterRegistry.key_for(OWNER, SaExposureFilter.new())


func _shown() -> Color:
    _doc.invalidate_chunks([Vector2i.ZERO])
    Bench.composite(_easel)
    return Bench.texel(_easel.output, PROBE)


func _stored(layer: SaLayer) -> Color:
    return Bench.texel(layer.chunks[Vector2i.ZERO].albedo(), PROBE)


func _apart(a: Color, b: Color) -> float:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


func _near(found: Color, wanted: Color, what: String) -> void:
    assert_true(_apart(found, wanted) <= TOLERANCE, "%s: %s against %s" % [what, found, wanted])


func _light(encoded: Color) -> Color:
    var linear := OkhsvConversions.srgb_transfer_function_inv(Vector3(encoded.r, encoded.g, encoded.b))
    return Color(linear.x, linear.y, linear.z, encoded.a)


func test_the_slider_reaches_four_stops_either_way_and_rests_at_zero() -> void:
    var filter := SaExposureFilter.new()
    var row: Dictionary = filter.rows()[0]
    assert_eq(float(row["default"]), 0.0, "Stops rests at 0")
    assert_true(float(row["min"]) <= -4.0 and float(row["max"]) >= 4.0, "and reaches four stops either way")
    assert_eq(float(filter.to_pass_units({"stops": 0.0})["brightness"]), 1.0, "0 stops is a factor of one")
    assert_eq(float(filter.to_pass_units({"stops": 2.0})["brightness"]), 4.0, "+2 stops is four times the light")
    assert_eq(float(filter.to_pass_units({"stops": -1.0})["brightness"]), 0.5, "-1 stop is half of it")


func test_bake_writes_the_scaled_values_into_the_layer() -> void:
    _painting(SaColorSpace.linear_srgb(), PAINT)
    assert_true(SaFilterOps.new(_doc).apply_once(_layer, _key(), {"stops": 2.0}, "Exposure"), "The bake writes")
    _near(_stored(_layer), PLUS_TWO, "The baked layer holds +2 stops")
    _near(_shown(), PLUS_TWO, "and so does the composite")


func test_attach_scales_the_composite_and_leaves_the_paint() -> void:
    _painting(SaColorSpace.linear_srgb(), PAINT)
    assert_not_null(SaFilterOps.new(_doc).attach(_layer, _key(), {"stops": 2.0}), "The record attaches")
    _near(_shown(), PLUS_TWO, "The composite with the record attached reads +2 stops")
    _near(_stored(_layer), PAINT, "while the layer's own pixels are as painted")


func test_a_filter_layer_scales_what_lies_under_it() -> void:
    _painting(SaColorSpace.linear_srgb(), PAINT)
    var adjust := SaLayerOps.new(_doc).add(SaBackdropLayer.TYPE_ID, _types)
    assert_not_null(SaFilterOps.new(_doc).attach(adjust, _key(), {"stops": 2.0}), "The record attaches to the filter layer")
    _near(_shown(), PLUS_TWO, "The composite under the filter layer reads +2 stops")
    _near(_stored(_layer), PAINT, "and the paint below it is untouched")


func test_alpha_is_not_touched() -> void:
    _painting(SaColorSpace.linear_srgb(), Color(0.25, 0.5, 0.125, 0.5))
    SaFilterOps.new(_doc).apply_once(_layer, _key(), {"stops": 1.0}, "Exposure")
    var stored := _stored(_layer)
    assert_true(absf(stored.a - 0.5) <= TOLERANCE, "A half-covered texel keeps its alpha, %s" % stored.a)
    _near(Color(stored.r, stored.g, stored.b, 1.0), Color(0.5, 1.0, 0.25, 1.0), "and its colour doubles")


func test_a_document_on_the_srgb_curve_is_scaled_in_light() -> void:
    _painting(SaColorSpace.srgb(), ENCODED)
    SaFilterOps.new(_doc).apply_once(_layer, _key(), {"stops": -1.0}, "Exposure")
    var before := _light(ENCODED)
    var after := _light(_stored(_layer))
    _near(
        after, Color(before.r * 0.5, before.g * 0.5, before.b * 0.5, 1.0), "-1 stop halves the light the stored colour decodes to"
    )
    assert_true(_stored(_layer).r > ENCODED.r * 0.5, "and not the encoded number, which would have halved it")


func test_attached_to_a_group_it_scales_the_composite_and_not_the_layers() -> void:
    _painting(SaColorSpace.linear_srgb(), PAINT)
    var group := SaLayerOps.new(_doc).group_active()
    assert_not_null(group, "The layer is grouped")
    assert_not_null(SaFilterOps.new(_doc).attach(group, _key(), {"stops": 2.0}), "The record attaches to the group")
    _near(_shown(), PLUS_TWO, "The group's composite reads +2 stops")
    _near(_stored(_layer), PAINT, "and its layer's own pixels are as painted")
