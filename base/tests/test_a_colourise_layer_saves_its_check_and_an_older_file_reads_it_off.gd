## Hue/Saturation/Lightness's Colourise check is a value of
## the record, so an adjustment layer saved with it on opens with it on and the
## same picture, and a record saved before the check existed opens with it off.
##
## The check is read where a painter reads it, on the rows the layer's panel
## draws, and the picture on the composited output.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 256)
const MODULE := &"sara-base-modules"
const KEY := &"sara-base-modules.hue_saturation_lightness"
const RED := Color(0.85, 0.15, 0.1, 1.0)
const AT := Vector2i(100, 100)
## The rows of a Colourise record, in their own units.
const TINTED := {
    "hue": 0.0, "saturation": 100.0, "lightness": 0.0, "colorize": true, "colorize_hue": 200.0, "colorize_saturation": 50.0
}
## A record as a file written before the check holds it: no `colorize` and no
## rows of its own, a turn of forty degrees.
const OLDER := {"hue": 40.0, "saturation": 100.0, "lightness": 0.0}

var _registries: SaRegistries = null
var _paths: Array[String] = []
var _host: VBoxContainer = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _registries.filters.register(SaHueSaturationLightnessFilter.new(), MODULE)
    _paths = []


func after_each() -> void:
    for path in _paths:
        DirAccess.remove_absolute(path)
    _registries = null


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(SIZE)
    easel.compositor.set_registry(_registries.blend_modes)
    easel.compositor.filter_chain.registry = _registries.filters
    return easel


## The grey background hidden and the paint red, so the output is the red as
## the chain leaves it.
func _painting() -> SaEasel:
    var easel := _easel()
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var paint := doc.get_node("Layer 1") as SaLayer
    doc.set_active_layer(paint)
    paint.fill(RED)
    return easel


func _show(easel: SaEasel) -> PackedByteArray:
    easel.document.invalidate_chunks([Vector2i(0, 0), Vector2i(1, 0)])
    easel.document.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()
    return GlobalShaderCompiler.get_rd().texture_get_data(easel.output.rid, 0)


func _texel(easel: SaEasel, bytes: PackedByteArray) -> Color:
    return SaFieldSpec.decode_texel(bytes, easel.output.format, AT.y * easel.output.size.x + AT.x)


## What the Colourise check of *record*'s panel reads, drawn the way the
## layer's filter panel draws it.
func _check(easel: SaEasel, record: SaAttachedFilter) -> Variant:
    var filter := easel.compositor.filter_chain.registry.get_filter(record.key)
    var dialog := SaDialog.for_filter(filter)
    filter.set_parameters(record.parameters)
    _host = VBoxContainer.new()
    dialog.realize(_host)
    var row := dialog.row(&"colorize")
    var read: Variant = row.read() if row != null else null
    _host.free()
    _host = null
    return read


func _saved(easel: SaEasel, file_name: String) -> String:
    var path := ProjectSettings.globalize_path(SaDataRoot.path(file_name))
    _paths.append(path)
    assert_eq(SaExport.save_sad(easel.document, path), OK, "%s saves" % file_name)
    return path


func _opened(path: String) -> SaEasel:
    var easel := _easel()
    assert_eq(SaExport.load_sad(easel.document, path, easel.compositor), OK, "%s opens" % path.get_file())
    var layers: Array[SaLayer] = []
    for child in easel.document.get_children():
        if child is SaLayer:
            layers.append(child)
    _registries.layer_types.rebind(layers)
    return easel


func _adjustment(easel: SaEasel, values: Dictionary) -> SaLayer:
    var layer := SaFilterConversion.new(easel.document).add_holding(
        KEY, values, _registries.layer_types, "Hue/Saturation/Lightness"
    )
    assert_true(layer != null and layer.is_adjustment(), "The Layer way adds an adjustment layer")
    return layer


## Red's Oklab hue is near 30 degrees, so a blue more than red is the asked 200.
static func _bluer_than_red(texel: Color) -> bool:
    return texel.b > texel.r


func test_a_colourise_layer_saves_with_its_check_on_and_reopens_the_same() -> void:
    var easel := _painting()
    var adjust := _adjustment(easel, TINTED)
    if adjust == null:
        easel.free()
        return
    var shown := _show(easel)
    assert_true(_bluer_than_red(_texel(easel, shown)), "The layer tints the red towards the hue asked")
    assert_eq(_check(easel, adjust.filters[0]), true, "and its panel shows Colourise on")

    var opened := _opened(_saved(easel, "colourise_layer.sad"))
    var reopened := opened.document.get_node_or_null(NodePath(adjust.name)) as SaLayer
    assert_true(
        reopened != null and reopened.is_adjustment() and reopened.filters.size() == 1, "It reopens as the adjustment layer"
    )
    if reopened != null and reopened.filters.size() == 1:
        assert_eq(reopened.filters[0].parameters.get("colorize"), true, "whose record keeps the check")
        assert_eq(_check(opened, reopened.filters[0]), true, "and whose panel reads it on")
    assert_eq(_show(opened), shown, "and the texels are the ones it saved")
    easel.free()
    opened.free()


func test_a_record_with_no_colorize_reopens_with_the_check_off_and_turns_as_before() -> void:
    var easel := _painting()
    var adjust := _adjustment(easel, OLDER)
    if adjust == null:
        easel.free()
        return
    assert_false(adjust.filters[0].parameters.has("colorize"), "The record is the older one, with no colorize")
    var shown := _show(easel)

    var opened := _opened(_saved(easel, "older_layer.sad"))
    var reopened := opened.document.get_node_or_null(NodePath(adjust.name)) as SaLayer
    assert_true(reopened != null and reopened.filters.size() == 1, "It reopens")
    if reopened != null and reopened.filters.size() == 1:
        assert_false(reopened.filters[0].parameters.has("colorize"), "with the record as it was written")
        assert_eq(_check(opened, reopened.filters[0]), false, "and its panel reads Colourise off")
    var reread := _show(opened)
    assert_eq(reread, shown, "and the texels are the turn it saved")

    var off := _painting()
    _adjustment(off, {"hue": 40.0, "saturation": 100.0, "lightness": 0.0, "colorize": false})
    assert_eq(_show(off), reread, "which is what the check off draws")
    easel.free()
    opened.free()
    off.free()


func test_colourise_attached_to_the_paint_tints_it_and_reopens() -> void:
    var easel := _painting()
    var paint := easel.document.get_node("Layer 1") as SaLayer
    var record := SaFilterOps.new(easel.document).attach(paint, KEY, TINTED)
    assert_not_null(record, "Colourise attaches to the paint")
    var shown := _show(easel)
    assert_true(_bluer_than_red(_texel(easel, shown)), "and tints it")
    var opened := _opened(_saved(easel, "colourise_attached.sad"))
    var kept := (opened.document.get_node("Layer 1") as SaLayer).filters
    assert_eq(kept.size(), 1, "The record reopens on the paint")
    if kept.size() == 1:
        assert_eq(kept[0].parameters.get("colorize"), true, "with the check on")
    assert_eq(_show(opened), shown, "and the texels are the ones it saved")
    easel.free()
    opened.free()


## The panel the record opens in shows the turn and the scale while the check
## is off, and the absolute hue and chroma in their place once a hand ticks it.
func test_the_check_swaps_the_turn_for_the_absolute_hue_and_chroma() -> void:
    var filter := SaHueSaturationLightnessFilter.new()
    var dialog := SaDialog.for_filter(filter)
    filter.set_parameters({})
    var host := VBoxContainer.new()
    dialog.realize(host)
    var shown := func(key: StringName) -> bool: return dialog.row(key).line.visible
    assert_true(shown.call(&"colorize"), "The check is on the panel")
    assert_true(shown.call(&"hue") and shown.call(&"saturation"), "and off, the turn and the scale show")
    assert_false(shown.call(&"colorize_hue") or shown.call(&"colorize_saturation"), "and the absolute rows do not")
    dialog.row(&"colorize").drive(true)
    assert_false(shown.call(&"hue") or shown.call(&"saturation"), "Ticked, the turn and the scale go")
    assert_true(shown.call(&"colorize_hue") and shown.call(&"colorize_saturation"), "and the absolute rows show")
    assert_eq(filter.values().get("colorize"), true, "and the pass is handed Colourise")
    host.free()
