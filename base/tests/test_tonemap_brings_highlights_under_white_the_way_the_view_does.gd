## A Tonemap filter brings a layer's highlights under white the
## way the view does.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Four flat layers of an sRGB float document, at 0.25, 1.0, 4.0 and 16.0, are
## baked through Tonemap at the view's defaults. The first, under the knee, has
## to read back bit for bit, every channel of the other three at or under one,
## and the 16.0 layer no darker than the 4.0 one. A hot colour has to keep its
## Oklab hue, a colour under the knee with a channel below zero has to be left
## as stored, the attached composite has to be the baked layer's, the defaults
## have to be the view's, and the kernel's rolloff has to be the view's body
## read as text, since a CanvasItem shader and the dialect share no include.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const SIZE := Vector2i(SaChunk.SIZE, SaChunk.SIZE)
const VIEW_SHADER := "res://shaders/canvas/tonemap.gdshader"
const KERNEL := "res://modules/sara-base-modules/base/shaders/tonemap.gmacs"
const FILTER_SCRIPT := "res://modules/sara-base-modules/base/usual/tonemap_filter.gd"
## The rolloff and the six functions of the gamut map it calls, which the view
## and this kernel share.
const SHARED: Array[String] = [
    "in_display_gamut",
    "with_chroma_scale",
    "signed_cbrt",
    "largest_cubic_root",
    "channel_exit",
    "gamut_map",
    "held_ratios",
    "highlight_rolloff",
]
## The four flat layers the row names, in stored sRGB-curve numbers.
const FLATS: Array[float] = [0.25, 1.0, 4.0, 16.0]
## A degree of Oklab hue, in radians, which is far finer than an eye tells.
const HUE_HELD := 0.02
const BAKED_AGAINST_ATTACHED := 1e-4

var _easel: SaEasel = null
var _doc: SaDocument = null
var _key: StringName = &""


func before_each() -> void:
    _easel = Bench.easel(SIZE)
    _doc = _easel.document
    (_doc.get_node("Background") as SaLayer).visible = false
    var filter := SaTonemapFilter.new()
    _easel.compositor.filter_chain.registry.register(filter, OWNER)
    _key = SaFilterRegistry.key_for(OWNER, filter)


func after_each() -> void:
    if _easel != null:
        _easel.free()
        _easel = null
    _doc = null


## A layer of its own above the others, every texel *color*.
func _flat(layer_name: String, color: Color) -> SaLayer:
    var layer := SaLayer.new()
    layer.name = layer_name
    _doc.add_child(layer)
    layer.fill(color)
    return layer


## The layer's texel at document pixel *at*, read back.
static func _texel(layer: SaLayer, at: Vector2i) -> Color:
    var texture := layer.get_field(Vector2i.ZERO)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


func _baked(layer: SaLayer, values: Dictionary = {}) -> Color:
    assert_true(SaFilterOps.new(_doc).apply_once(layer, _key, values, "Tonemap"), "Bake writes %s" % layer.name)
    return _texel(layer, Vector2i(40, 30))


## The colour in Oklab, from the stored sRGB-curve numbers.
static func _oklab(c: Color) -> Vector3:
    return OkhsvConversions.linear_srgb_to_oklab(Vector3(_decode(c.r), _decode(c.g), _decode(c.b)))


static func _hue(c: Color) -> float:
    var lab := _oklab(c)
    return atan2(lab.z, lab.y)


static func _lightness(c: Color) -> float:
    return _oklab(c).x


## The sRGB curve, mirrored through nought, as the kernels decode it.
static func _decode(v: float) -> float:
    var a := absf(v)
    var out := a / 12.92 if a <= 0.04045 else pow((a + 0.055) / 1.055, 2.4)
    return signf(v) * out


func test_four_flat_layers_come_out_under_white_and_the_first_unchanged() -> void:
    var read: Array[Color] = []
    for v: float in FLATS:
        read.append(_baked(_flat("Flat %s" % v, Color(v, v, v, 1.0))))
    var first := read[0]
    var under := first.r == FLATS[0] and first.g == FLATS[0] and first.b == FLATS[0] and first.a == 1.0
    assert_true(under, "0.25 is under the knee and reads back as stored: %s" % first)
    for i in range(1, read.size()):
        var c := read[i]
        var peak := maxf(c.r, maxf(c.g, c.b))
        assert_true(peak <= 1.0, "%s comes out at or under one, its peak %s" % [FLATS[i], peak])
        assert_true(c.a == 1.0, "and alpha is kept")
    var four := _lightness(read[2])
    var sixteen := _lightness(read[3])
    var said := "16.0 reads an Oklab lightness of %s, no darker than 4.0's %s" % [sixteen, four]
    assert_true(sixteen >= four, said)


func test_a_hot_colour_goes_towards_white_with_its_hue_held() -> void:
    var hot := Color(4.0, 1.0, 0.25, 1.0)
    var c := _baked(_flat("Hot", hot))
    assert_true(maxf(c.r, maxf(c.g, c.b)) <= 1.0, "The hot orange comes under white: %s" % c)
    var turned := absf(angle_difference(_hue(hot), _hue(c)))
    assert_true(turned <= HUE_HELD, "with its Oklab hue held, turned %s radians" % turned)
    assert_true(c.b > hot.b, "and its lowest channel lifted towards white: %s" % c.b)


func test_a_value_under_the_knee_is_left_as_stored_a_negative_channel_too() -> void:
    var odd := Color(0.6, -0.1, 0.3, 1.0)
    var c := _baked(_flat("Odd", odd))
    assert_eq(c, odd, "A colour whose peak is under the knee is the document's and stays as stored")


func test_a_higher_knee_leaves_more_alone() -> void:
    var bright := Color(0.7, 0.7, 0.7, 1.0)
    var c := _baked(_flat("Grey", bright), {"knee": 0.6, "desaturation": 1.0})
    assert_eq(c, bright, "A grey of 0.7 is 0.45 in light, under a knee of 0.6, and stays")


func test_attached_the_composite_equals_the_baked_layer() -> void:
    var layer := _flat("Hot", Color(3.0, 0.8, 0.2, 1.0))
    SaFilterOps.new(_doc).attach(layer, _key, {})
    var attached := _composite()
    SaFilterOps.new(_doc).detach(layer, layer.filters[0])
    _baked(layer)
    var baked := _composite()
    var worst := 0.0
    for i: int in [0, 1, 2, 3]:
        worst = maxf(worst, absf(attached[i] - baked[i]))
    assert_true(worst <= BAKED_AGAINST_ATTACHED, "The attached composite is the baked layer's, worst %s" % worst)
    assert_true(maxf(attached.r, maxf(attached.g, attached.b)) <= 1.0, "and is under white: %s" % attached)


func _composite() -> Color:
    _doc.invalidate_chunks([Vector2i.ZERO])
    Bench.composite(_easel)
    var texture := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, 30 * texture.size.x + 40)


func test_the_defaults_are_the_views_and_the_record_keeps_them() -> void:
    var fresh := SaSettingsValues.new()
    var values := SaTonemapFilter.new().parameters()
    assert_almost_eq(float(values["knee"]), fresh.tonemap_knee, 1e-6, "Knee defaults to the view's")
    var said := "Desaturation defaults to the view's"
    assert_almost_eq(float(values["desaturation"]), fresh.tonemap_desaturation, 1e-6, said)
    fresh.free()


## The knee and desaturation come from the record and from nowhere else, so a
## saved document reads the same on a machine whose view is tuned otherwise.
func test_the_filter_and_its_kernel_never_read_the_live_settings() -> void:
    for path: String in [FILTER_SCRIPT, KERNEL]:
        var text := FileAccess.get_file_as_string(path)
        assert_false(text.is_empty(), "%s is read" % path.get_file())
        assert_false(text.contains("SaSettings"), "%s names no live setting" % path.get_file())


func test_the_kernels_rolloff_is_the_views() -> void:
    var view := FileAccess.get_file_as_string(VIEW_SHADER)
    var kernel := FileAccess.get_file_as_string(KERNEL)
    for function: String in SHARED:
        var in_view := " ".join(_body(view, function, false))
        var in_kernel := " ".join(_body(kernel, function, true))
        assert_false(in_view.is_empty(), "%s is read out of the view shader" % function)
        assert_eq(in_kernel, in_view, "%s in tonemap.gmacs is the view's" % function)


func test_the_filter_browser_finds_it_under_tone() -> void:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    var mod := BaseModule.new()
    mod.register(registries.context.for_module(mod.get_id()))
    var docker := FiltersDocker.new()
    docker.browser.watch(registries.filters, registries.commands)
    docker.browser.search_for("tonemap")
    var listed: Array = docker.describe()["listed"]
    var key := SaFilterRegistry.key_for(mod.get_id(), SaTonemapFilter.new())
    assert_eq(listed, [String(key)], "Searching 'tonemap' lists Tonemap alone: %s" % [listed])
    assert_eq(registries.filters.section_of(key), &"tone", "under Tone")
    docker.free()
    mod.unregister(registries.context.for_module(mod.get_id()))


## The body of *function* in *source*, one statement a line, the two syntaxes
## written one way: no comments, no braces, no semicolons, and the dialect's
## words for GLSL's operators. The same reading the gamut mapping preference's
## suite gives the export's copy.
static func _body(source: String, function: String, dialect: bool) -> Array[String]:
    var lines: Array[String] = []
    var header := ("def %s(" if dialect else " %s(") % function
    var inside := false
    for raw: String in source.split("\n"):
        var comment := raw.find("#" if dialect else "//")
        var line := (raw.substr(0, comment) if comment >= 0 else raw).strip_edges()
        if not inside:
            if dialect:
                inside = raw.begins_with("def ") and raw.contains(header)
            else:
                inside = not raw.begins_with(" ") and raw.contains(header) and line.ends_with("{")
            continue
        if line.is_empty():
            continue
        if (dialect and not raw.begins_with(" ")) or (not dialect and raw.begins_with("}")):
            break
        var written := _one_syntax(line)
        if not written.is_empty():
            lines.append(written)
    return lines


static func _one_syntax(line: String) -> String:
    var out := line.trim_suffix(";").trim_suffix("{").trim_suffix(":").strip_edges()
    out = out.trim_prefix("}").strip_edges()
    for pair: Array in [
        ["greaterThanEqual", "greater_than_equal"],
        ["lessThanEqual", "less_than_equal"],
        ["&&", "and"],
        ["||", "or"],
    ]:
        out = out.replace(pair[0], pair[1])
    if out.begins_with("if (") and out.ends_with(")"):
        out = "if " + out.substr(4, out.length() - 5)
    return out
