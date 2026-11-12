## Add Noise after Grain became its Film grain type. White
## under Monochrome draws one grain for all three channels, the Colour row
## scales the grain by a colour in light, the darks control keeps the grain to
## the dark end of a ramp, and at nought every type paints the numbers pinned
## below. A Random record and a record saved under Grain's key load as the
## merged filter and paint those numbers, and the module registers no Grain.
extends "res://tests/test_framework.gd"

const RoundTrip = preload("res://modules/sara-base-modules/base/tests/attached_round_trip.gd")
const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")

## Real dispatches into real chunks.
const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const MODULE_DIR := "res://modules/sara-base-modules/base"
const GREY := Color(0.5, 0.5, 0.5, 1.0)
const GRID := Vector2i.ZERO
## Where the ramp is read, and what each type reads there for Amount 40 and
## Seed 3 since every draw hashes integers. The float hash before it drew rows
## 97 apart alike past a seed of about 3000, and the merge of Grain kept its
## numbers until then.
const AT: Array[Vector2i] = [
    Vector2i(3, 5), Vector2i(40, 77), Vector2i(97, 130), Vector2i(128, 128), Vector2i(171, 9), Vector2i(250, 251)
]
const BEFORE := {
    "white":
    [
        Color(0.3025550, -0.0464579, 0.3949505),
        Color(-0.2354912, -0.1658351, -0.0440045),
        Color(0.6955371, 0.5345696, 0.4349368),
        Color(0.2412870, 0.7132769, 0.5004265),
        Color(0.9825094, 0.9302304, 0.9637697),
        Color(0.9059308, 1.3209968, 0.7222263),
    ],
    "random":
    [
        Color(0.3025550, 0.3025550, 0.3025550),
        Color(-0.2354912, -0.2354912, -0.2354912),
        Color(0.6955371, 0.6955371, 0.6955371),
        Color(0.2412870, 0.2412870, 0.2412870),
        Color(0.9825094, 0.9825094, 0.9825094),
        Color(0.9059308, 0.9059308, 0.9059308),
    ],
    "cmos":
    [
        Color(-0.0318524, -0.0410260, 0.0531052),
        Color(0.2582809, 0.2040357, 0.0995859),
        Color(0.1850898, 0.2364521, 0.1459876),
        Color(0.4060518, 0.3802246, 0.7709545),
        Color(0.4374694, 0.8045580, 1.0865282),
        Color(1.5274131, 0.9637436, 0.4119968),
    ],
    "salt_and_pepper":
    [
        Color(0.0117647, 0.0117647, 0.0117647),
        Color(1.0, 1.0, 1.0),
        Color(0.3803922, 0.3803922, 0.3803922),
        Color(1.0, 1.0, 1.0),
        Color(0.6705883, 0.6705883, 0.6705883),
        Color(0.9803922, 0.9803922, 0.9803922),
    ],
}
## What a record of Filter > Noise > Grain reads at [const AT] on the ramp for
## Amount 40, Size 2 and Seed 3, under its Monochrome type and its Colour type,
## as Film grain draws it on its integer lattice.
const GRAIN_BEFORE := {
    "monochrome":
    [
        Color(0.0148602, 0.0148602, 0.0148602),
        Color(0.1026745, 0.1026745, 0.1026745),
        Color(0.3512342, 0.3512338, 0.3512336),
        Color(0.5123103, 0.5123103, 0.5123100),
        Color(0.6504788, 0.6504796, 0.6504791),
        Color(0.9802257, 0.9802268, 0.9802263),
    ],
    "color":
    [
        Color(0.0115452, 0.0094495, 0.0083493),
        Color(0.1163313, 0.1683740, 0.2179010),
        Color(0.4626355, 0.3083998, 0.3525160),
        Color(0.4913155, 0.5482498, 0.4439101),
        Color(0.6385940, 0.7412198, 0.6726300),
        Color(0.9846727, 0.9784865, 0.9757445),
    ],
}
## How far a read may sit from the numbers above on another GPU, whose hash is
## the same integers and whose float maths after it may round otherwise.
const BEFORE_BOUND := 1e-4

var _easel: SaEasel = null
var _document: SaDocument = null
var _layer: SaLayer = null
var _filter: SaAddNoiseFilter = null


func before_each() -> void:
    if not ModuleLoader.module_dirs.has(OWNER):
        ModuleLoader.module_dirs[OWNER] = MODULE_DIR
    var space := SaColorSpace.linear_srgb()
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE, SaChunk.SIZE), null, space)
    _document = _easel.document
    _document.color_space = space
    _layer = _document.get_node("Layer 1") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    _filter = SaAddNoiseFilter.new()


func after_each() -> void:
    _layer = null
    _document = null
    _filter = null
    _easel.free()
    _easel = null


## The chunk in one *colour*.
func _fill(colour: Color) -> void:
    _layer.get_or_create_chunk(GRID).clear(colour)


## The chunk as a ramp from black at its left edge to white at its right, in
## light, the same in every row.
func _ramp() -> void:
    var texture := _layer.get_or_create_chunk(GRID).field(SaFieldSpec.ALBEDO)
    var values := PackedFloat32Array()
    values.resize(texture.size.x * texture.size.y * 4)
    for y in texture.size.y:
        for x in texture.size.x:
            var v := float(x) / float(texture.size.x - 1)
            var i := (y * texture.size.x + x) * 4
            values[i] = v
            values[i + 1] = v
            values[i + 2] = v
            values[i + 3] = 1.0
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, values.to_byte_array())


## Runs Add Noise one-shot with *values* over the chunk, as Apply does.
func _apply(values: Dictionary) -> bool:
    _filter.set_parameters(values)
    var ctx := SaFilterContext.new(_document, _layer, OWNER, _filter.title())
    if not SaFilterApply.call_run(_filter, ctx):
        return false
    return SaFilterApply.apply(ctx, _filter.title())


## Every texel of the chunk, row by row.
func _texels() -> Array[Color]:
    var texture := (_layer.chunks[GRID] as SaChunk).field(SaFieldSpec.ALBEDO)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out: Array[Color] = []
    for i in texture.size.x * texture.size.y:
        out.append(SaFieldSpec.decode_texel(bytes, texture.format, i))
    return out


## The side of the chunk in texels, asked of the chunk (hard rule 3).
func _side() -> int:
    return (_layer.chunks[GRID] as SaChunk).pixel_size()


## The largest channel distance between the chunk at [const AT] and *was*.
func _worst_from(was: Array) -> float:
    var texels := _texels()
    var worst := 0.0
    for index in AT.size():
        var c := texels[AT[index].y * _side() + AT[index].x]
        var then: Color = was[index]
        worst = maxf(worst, maxf(absf(c.r - then.r), maxf(absf(c.g - then.g), absf(c.b - then.b))))
    return worst


## The spread of what the grain added to the red channel over the columns from
## *first* up to *past*, every row, against the ramp's value there.
func _added_spread(texels: Array[Color], first: int, past: int) -> float:
    var side := _side()
    var sum := 0.0
    var count := 0
    for y in side:
        for x in range(first, past):
            var added := texels[y * side + x].r - float(x) / float(side - 1)
            sum += added * added
            count += 1
    return sqrt(sum / float(count))


func test_white_under_monochrome_grains_three_channels_alike_and_off_grains_each_apart() -> void:
    _fill(GREY)
    assert_true(_apply({"kind": "white", "monochrome": true, "amount": 40.0, "seed": 3.0}), "White applies")
    var widest := 0.0
    var moved := 0
    for c in _texels():
        widest = maxf(widest, maxf(absf(c.r - c.g), absf(c.g - c.b)))
        if absf(c.r - GREY.r) > 1e-3:
            moved += 1
    assert_eq(widest, 0.0, "Under Monochrome every texel's three channels are equal")
    assert_true(moved > 1000, "and the grain moved them, %d texels" % moved)
    _fill(GREY)
    assert_true(_apply({"kind": "white", "monochrome": false, "amount": 40.0, "seed": 3.0}), "White applies again")
    var apart := 0
    for c in _texels():
        if absf(c.r - c.g) > 1e-4 or absf(c.g - c.b) > 1e-4:
            apart += 1
    assert_true(apart * 2 > _side() * _side(), "With Monochrome off most texels' channels differ, %d" % apart)


func test_the_darks_control_keeps_the_grain_to_the_dark_end_of_a_ramp() -> void:
    _ramp()
    var values := {"kind": "white", "monochrome": true, "amount": 40.0, "seed": 3.0, "darks": 100.0}
    assert_true(_apply(values), "White applies with the darks control at 100")
    var texels := _texels()
    var quarter := _side() >> 2
    var dark := _added_spread(texels, 0, quarter)
    var light := _added_spread(texels, _side() - quarter, _side())
    assert_true(dark > 0.05, "The dark end takes the grain, a spread of %f" % dark)
    assert_true(dark >= 4.0 * light, "at least four times the light end's, %f against %f" % [dark, light])
    var below := 0
    for c in texels:
        if c.r < 0.0:
            below += 1
    assert_true(below > 0, "and nothing clamps, %d texels below nought" % below)


func test_at_nought_every_type_paints_what_it_painted_before() -> void:
    for kind: String in ["white", "cmos", "salt_and_pepper"]:
        _ramp()
        var values := {"kind": kind, "monochrome": false, "amount": 40.0, "seed": 3.0, "darks": 0.0}
        assert_true(_apply(values), "%s applies" % kind)
        var worst := _worst_from(BEFORE[kind])
        assert_true(worst < BEFORE_BOUND, "%s at nought paints as before, off by %f" % [kind, worst])


func test_a_random_record_paints_as_white_under_monochrome() -> void:
    var read := SaAddNoiseFilter.upgraded(SaAddNoiseFilter.OWN_ID, {"kind": "random", "amount": 40.0, "seed": 3.0})
    assert_eq(read.get("kind"), "white", "A Random record reads as White")
    assert_eq(read.get("monochrome"), true, "with Monochrome on")
    _ramp()
    assert_true(_apply(read), "and applies")
    var worst := _worst_from(BEFORE["random"])
    assert_true(worst < BEFORE_BOUND, "painting what Random painted, off by %f" % worst)


func test_a_grain_record_paints_what_grain_painted() -> void:
    for kind: String in ["monochrome", "color"]:
        var read := SaAddNoiseFilter.upgraded(SaAddNoiseFilter.GRAIN_ID, {"kind": kind, "amount": 40.0, "size": 2.0, "seed": 3.0})
        assert_eq(read.get("kind"), "film_grain", "A Grain record of %s reads as Film grain" % kind)
        assert_eq(read.get("monochrome"), kind == "monochrome", "with the switch as its type said")
        _ramp()
        assert_true(_apply(read), "and applies")
        var worst := _worst_from(GRAIN_BEFORE[kind])
        assert_true(worst < BEFORE_BOUND, "painting what Grain's %s painted, off by %f" % [kind, worst])
        _document.undo()


func test_a_colour_scales_the_grain_in_its_ratio_in_light() -> void:
    _fill(GREY)
    # The row holds a colour as the picker shows it, which the filter takes to
    # light, so the colour whose light is (1, 0.5, 0.25) is picked.
    var picked := Color(1.0, 0.5, 0.25).linear_to_srgb()
    var values := {"kind": "white", "monochrome": true, "amount": 40.0, "seed": 3.0, "color": picked}
    assert_true(_apply(values), "White applies in a colour")
    var red := 0.0
    var green := 0.0
    var blue := 0.0
    for c in _texels():
        red += absf(c.r - GREY.r)
        green += absf(c.g - GREY.g)
        blue += absf(c.b - GREY.b)
    assert_true(red > 100.0, "The grain moved red, %f in all" % red)
    # A record keeps a colour as eight-bit text, so the light it holds is the
    # asked one to within a step of eight bits, and the grain keeps that ratio.
    var held := SaAddNoiseFilter.colour_of(_filter.parameters()["color"]).srgb_to_linear()
    assert_almost_eq(held.g, 0.5, 5e-3, "The record holds green at half in light, %f" % held.g)
    assert_almost_eq(held.b, 0.25, 5e-3, "and blue at a quarter, %f" % held.b)
    assert_almost_eq(green / red, held.g, 1e-4, "The grain moves green by half as much as red")
    assert_almost_eq(blue / red, held.b, 1e-4, "and blue by a quarter")


func test_the_dialog_has_the_switch_the_colour_the_darks_and_a_tooltip_for_each_type() -> void:
    var host := VBoxContainer.new()
    var dialog := SaDialog.new(_filter.build)
    dialog.declare_rows()
    dialog.realize(host)
    for name: StringName in [&"monochrome", &"color", &"darks", &"size"]:
        assert_not_null(dialog.row(name), "The dialog has a %s row" % name)
    var kind := dialog.row(&"kind")
    var titles: Array[String] = []
    for entry: Dictionary in kind.choices:
        titles.append(String(entry.get("label", "")))
        assert_true(String(entry.get("tooltip", "")).ends_with("."), "%s says what it does" % entry.get("label"))
    assert_eq(titles, ["White", "Film grain", "Sensor (CMOS)", "Salt and pepper"] as Array[String], "in four types")
    host.free()


func test_a_document_saved_with_random_loads_as_white_under_monochrome() -> void:
    var trip := RoundTrip.new(SaAddNoiseFilter.new(), OWNER)
    trip.attach({"kind": "white", "monochrome": true, "amount": 40.0, "seed": 3.0})
    var before := trip.texels()
    var old: Dictionary[String, Variant] = {"kind": "random", "amount": 40.0, "seed": 3.0}
    trip.record.parameters = old
    var loaded := trip.round_trip({"kind": "cmos", "amount": 0.0})
    assert_eq(loaded.get("kind"), "white", "The loaded record is White")
    assert_eq(loaded.get("monochrome"), true, "with Monochrome on")
    assert_true(RoundTrip.distance(before, trip.texels()) < 1e-5, "and draws as it did")
    trip.release()


func test_a_document_saved_with_an_attached_grain_loads_as_film_grain() -> void:
    var trip := RoundTrip.new(SaAddNoiseFilter.new(), OWNER)
    trip.attach({"kind": "film_grain", "monochrome": true, "amount": 60.0, "size": 4.0, "seed": 5.0})
    var before := trip.texels()
    var old: Dictionary[String, Variant] = {"amount": 60.0, "size": 4.0, "seed": 5.0}
    trip.record.key = SaFilterRegistry.key_of(OWNER, SaAddNoiseFilter.GRAIN_ID)
    trip.record.parameters = old
    var loaded := trip.round_trip({"kind": "white", "monochrome": false, "amount": 0.0})
    assert_eq(trip.record.key if trip.record != null else &"", trip.key, "The loaded record is Add Noise's")
    assert_eq(loaded.get("kind"), "film_grain", "of the Film grain type")
    assert_eq(loaded.get("monochrome"), true, "with Monochrome on")
    assert_true(RoundTrip.distance(before, trip.texels()) < 1e-5, "and draws as it did")
    trip.release()


func test_the_filter_menu_lists_no_grain() -> void:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    var mod := BaseModule.new()
    mod.register(registries.context.for_module(mod.get_id()))
    var keys: Array[String] = []
    for key: StringName in registries.filters.list_keys():
        keys.append(String(key))
    assert_true(keys.has("sara-base-modules.add_noise"), "The module registers Add Noise")
    assert_false(keys.has("sara-base-modules.grain"), "and no Grain")
    assert_true(keys.has("sara-base-modules.drifting_noise"), "and Drifting Noise stays its own filter")
