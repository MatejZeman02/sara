## Hue/Saturation/Lightness's Saturation, and Desaturate, keep the brightness a
## colour shows: CAM16's J_HK with the Helmholtz-Kohlrausch effect of Hellwig,
## Stolitzka and Fairchild counted, read by `cam16_reference.gd` from the
## texels the kernel wrote. Oklab's scale at a fixed L, which records made
## before the J_HK model keep, makes the same colours look brighter, and a file saved
## with such records shows the pixels it showed.
extends "res://tests/test_framework.gd"

const Cam16 = preload("res://modules/sara-base-modules/base/tests/cam16_reference.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

## Saturated colours near mid lightness, linear sRGB, the fixtures of the
## library's own suite.
const COLOURS := {
    "red": Vector3(0.6, 0.06, 0.05),
    "yellow": Vector3(0.5, 0.42, 0.03),
    "cyan": Vector3(0.03, 0.32, 0.38),
    "blue": Vector3(0.05, 0.08, 0.6),
}
const HELD := 1e-4
## How far a hue may move, in radians: a hundredth of a degree.
const HUE_HELD := 2e-4
## How much brighter, in J_HK, Oklab's 150 % at least makes each colour look.
const OKLAB_LIFT := 0.5

const MODULE := &"sara-base-modules"
const KEY := &"sara-base-modules.hue_saturation_lightness"
const AT := Vector2i(100, 100)

var _easel: SaEasel = null
var _engine: SaPointAdjust = null
var _registries: SaRegistries = null
var _paths: Array[String] = []


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(256, 256))
    _engine = SaPointAdjust.new()
    _paths = []


func after_each() -> void:
    for path in _paths:
        DirAccess.remove_absolute(path)
    _engine = null
    _registries = null
    _easel.free()
    _easel = null


## The sRGB curve mirrored through nought, as the kernels' transfer is, so a
## colour pushed past the gamut with a negative channel reads as it is.
static func _encoded(linear: Vector3) -> Color:
    var e := Vector3.ZERO
    for i in 3:
        e[i] = signf(linear[i]) * OkhsvConversions.channel_rgb_to_srgb(absf(linear[i]))
    return Color(e.x, e.y, e.z, 1.0)


static func _decoded(c: Color) -> Vector3:
    var out := Vector3.ZERO
    for i in 3:
        out[i] = signf(c[i]) * OkhsvConversions.channel_srgb_to_rgb(absf(c[i]))
    return out


func _texel() -> Vector3:
    var doc := _easel.document
    var texture := doc.active_layer.get_field(Vector2i.ZERO)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var c := SaFieldSpec.decode_texel(bytes, texture.format, AT.y * texture.size.x + AT.x)
    return _decoded(c)


## *linear* painted, *values* applied as one step, and the linear colour that
## came out. The step is undone after, so the next call paints afresh.
func _through(linear: Vector3, values: Dictionary) -> Vector3:
    var doc := _easel.document
    doc.active_layer.fill(_encoded(linear))
    assert_true(
        _engine.apply(doc, doc.active_layer, SaPointAdjust.HUE_SATURATION_LIGHTNESS, values, "Hue/Saturation/Lightness"),
        "Applied"
    )
    var out := _texel()
    doc.undo()
    return out


static func _saturation(factor: float, model: float) -> Dictionary:
    return {"hue": 0.0, "saturation": factor, "lightness": 0.0, SaPointAdjust.SATURATION_MODEL: model}


func test_saturation_at_150_and_50_percent_keeps_each_colour_s_j_hk_and_hue() -> void:
    for factor: float in [1.5, 0.5]:
        for name: String in COLOURS:
            var before: Vector3 = COLOURS[name]
            var after := _through(before, _saturation(factor, SaPointAdjust.SATURATION_IN_CAM16))
            var was := Cam16.jch(before)
            var now := Cam16.jch(after)
            var label := "%s at %d %%" % [name, roundi(factor * 100.0)]
            assert_almost_eq(Cam16.lightness_hk(after), Cam16.lightness_hk(before), HELD, "%s keeps its J_HK" % label)
            assert_almost_eq(now.z, was.z, HUE_HELD, "%s keeps its hue" % label)
            assert_almost_eq(now.y, was.y * factor, 1e-3, "%s takes the chroma asked" % label)
            if factor > 1.0:
                assert_true(now.x < was.x, "%s gains chroma and loses J, %.3f from %.3f" % [label, now.x, was.x])


func test_oklab_s_150_percent_makes_the_same_colours_look_brighter() -> void:
    for name: String in COLOURS:
        var before: Vector3 = COLOURS[name]
        var after := _through(before, _saturation(1.5, SaPointAdjust.SATURATION_IN_OKLAB))
        var was := Cam16.lightness_hk(before)
        var now := Cam16.lightness_hk(after)
        assert_true(now > was + OKLAB_LIFT, "Oklab's 150 %% lifts %s's J_HK from %.3f to %.3f" % [name, was, now])


func test_desaturate_takes_the_blue_to_the_grey_as_bright_as_it_looked() -> void:
    var blue: Vector3 = COLOURS["blue"]
    var grey := _through(blue, SaDesaturateFilter.VALUES)
    var oklab_grey := _through(blue, _saturation(0.0, SaPointAdjust.SATURATION_IN_OKLAB))
    assert_almost_eq(grey.x, grey.z, 1e-6, "Desaturate gives a grey, red %.6f against blue %.6f" % [grey.x, grey.z])
    assert_almost_eq(Cam16.jch(grey).x, Cam16.lightness_hk(blue), HELD, "whose J is the blue's J_HK")
    var today := Cam16.jch(oklab_grey).x
    assert_true(Cam16.jch(grey).x > today + 1.0, "lighter than Oklab's grey, J %.3f against %.3f" % [Cam16.jch(grey).x, today])


## What a dialog opened now writes, and what Desaturate files a layer as.
func test_a_new_dialog_and_a_new_desaturate_layer_take_cam16() -> void:
    var filter := SaHueSaturationLightnessFilter.new()
    SaDialog.declare_filter(filter)
    var made := filter.parameters()
    assert_eq(
        float(made.get(SaPointAdjust.SATURATION_MODEL, -1.0)),
        SaPointAdjust.SATURATION_IN_CAM16,
        "A dialog opened now scales saturation in CAM16"
    )
    filter.set_parameters({"hue": 0.0, "saturation": 150.0, "lightness": 0.0})
    var older := filter.values()
    assert_eq(
        float(older.get(SaPointAdjust.SATURATION_MODEL, -1.0)),
        SaPointAdjust.SATURATION_IN_OKLAB,
        "and a record with no model reads as Oklab"
    )
    var filed := SaDesaturateFilter.new().filed_as(&"sara-base-modules.desaturate")
    assert_eq(
        float(filed.parameters.get(SaPointAdjust.SATURATION_MODEL, -1.0)),
        SaPointAdjust.SATURATION_IN_CAM16,
        "A Desaturate layer made now is filed with CAM16"
    )


func _painted_with_old_records() -> SaEasel:
    _registries = Fixtures.make_registries()
    _registries.filters.register(SaHueSaturationLightnessFilter.new(), MODULE)
    var easel := SaEasel.create_default(Vector2i(512, 256))
    easel.compositor.set_registry(_registries.blend_modes)
    easel.compositor.filter_chain.registry = _registries.filters
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var paint := doc.get_node("Layer 1") as SaLayer
    doc.set_active_layer(paint)
    paint.fill(_encoded(COLOURS["blue"]))
    return easel


func _shown(easel: SaEasel) -> Color:
    easel.document.invalidate_chunks([Vector2i(0, 0), Vector2i(1, 0)])
    easel.document.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(easel.output.rid, 0)
    return SaFieldSpec.decode_texel(bytes, easel.output.format, AT.y * easel.output.size.x + AT.x)


func _reopened(easel: SaEasel, file_name: String) -> SaEasel:
    var path := ProjectSettings.globalize_path(SaDataRoot.path(file_name))
    _paths.append(path)
    assert_eq(SaExport.save_sad(easel.document, path), OK, "%s saves" % file_name)
    var opened := SaEasel.create_default(Vector2i(512, 256))
    opened.compositor.set_registry(_registries.blend_modes)
    opened.compositor.filter_chain.registry = _registries.filters
    assert_eq(SaExport.load_sad(opened.document, path, opened.compositor), OK, "%s opens" % file_name)
    var layers: Array[SaLayer] = []
    for child in opened.document.get_children():
        if child is SaLayer:
            layers.append(child)
    _registries.layer_types.rebind(layers)
    return opened


## The blue through Oklab's scale at *factor* with L kept, encoded, which is
## what a record made before the J_HK model drew.
static func _oklab_drawn(linear: Vector3, factor: float) -> Color:
    var lab := OkhsvConversions.linear_srgb_to_oklab(linear)
    return _encoded(OkhsvConversions.oklab_to_linear_srgb(Vector3(lab.x, lab.y * factor, lab.z * factor)))


static func _off(a: Color, b: Color) -> float:
    return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))


## A file saved before the J_HK model holds Hue/Saturation/Lightness records with no
## `saturation_model`: the rows and the check, as the attached record and the
## Desaturate layer of the time wrote them.
func test_a_file_with_an_attached_hue_saturation_and_a_desaturate_layer_saved_before_shows_the_same_pixels() -> void:
    var easel := _painted_with_old_records()
    var paint := easel.document.get_node("Layer 1") as SaLayer
    var attached := SaFilterOps.new(easel.document).attach(
        paint, KEY, {"hue": 0.0, "saturation": 150.0, "lightness": 0.0, "colorize": false}
    )
    assert_false(attached.parameters.has(SaPointAdjust.SATURATION_MODEL), "The attached record is the older one")
    var attached_only := _shown(easel)
    var desaturated := SaFilterConversion.new(easel.document).add_holding(
        KEY, {"hue": 0.0, "saturation": 0.0, "lightness": 0.0}, _registries.layer_types, "Desaturate"
    )
    assert_true(desaturated != null and desaturated.is_adjustment(), "and so is the Desaturate layer over it")
    var both := _shown(easel)
    var blue: Vector3 = COLOURS["blue"]
    var stronger := _decoded(_oklab_drawn(blue, 1.5))
    var tolerance := 2e-3
    assert_true(
        _off(attached_only, _oklab_drawn(blue, 1.5)) < tolerance,
        "The attached record draws Oklab's 150 %%: %s against %s" % [attached_only, _oklab_drawn(blue, 1.5)]
    )
    assert_true(
        _off(both, _oklab_drawn(stronger, 0.0)) < tolerance,
        "and the layer Oklab's grey: %s against %s" % [both, _oklab_drawn(stronger, 0.0)]
    )

    var opened := _reopened(easel, "older_saturation.sad")
    var after := _shown(opened)
    assert_true(_off(after, both) < 1e-6, "The file reopens showing the same pixels, %s against %s" % [after, both])
    opened.free()
    easel.free()
