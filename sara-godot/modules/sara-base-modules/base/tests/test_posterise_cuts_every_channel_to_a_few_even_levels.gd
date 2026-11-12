## Posterise in the Filter menu cuts every channel to a few even
## levels, runs where it stands in a chain, and the filter browser finds it by
## the word.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The layer is a ramp across two chunks, 0 to 1.4 along the row, so the cases
## read a value past one as well as the span below it. Baked, three levels leave
## every channel at 0, 0.5 or 1 and a texel of 1.4 above 1, and attached, the
## composite is the baked layer's.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const SIZE := Vector2i(2 * SaChunk.SIZE, SaChunk.SIZE)
const CHUNKS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
## The ramp's top, past white.
const PEAK := 1.4
## How far a channel may sit from a level and still be on it.
const ON_LEVEL := 1e-3
const BAKED_AGAINST_ATTACHED := 1e-4

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _key: StringName = &""


func before_each() -> void:
    _open(null)


func after_each() -> void:
    _close()


## An easel of two chunks stored in *space*, the bench's float sRGB one for
## null, with Posterise registered in its chain.
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
    var filter := SaPosteriseFilter.new()
    _easel.compositor.filter_chain.registry.register(filter, OWNER)
    _key = SaFilterRegistry.key_for(OWNER, filter)


func _close() -> void:
    if _easel != null:
        _easel.free()
        _easel = null
    _doc = null
    _layer = null


## The ramp's value at document column *x*, the same in all three channels.
static func _ramp(x: int) -> float:
    return float(x) / float(SIZE.x - 1) * PEAK


func _paint_ramp() -> void:
    for grid_pos: Vector2i in CHUNKS:
        var texture := _layer.get_or_create_chunk(grid_pos).field(SaFieldSpec.ALBEDO)
        var values := PackedFloat32Array()
        values.resize(texture.size.x * texture.size.y * 4)
        for y in texture.size.y:
            for x in texture.size.x:
                var v := _ramp(grid_pos.x * texture.size.x + x)
                var i := (y * texture.size.x + x) * 4
                values[i] = v
                values[i + 1] = v
                values[i + 2] = v
                values[i + 3] = 1.0
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, values.to_byte_array())
    _doc.history.reset()
    _doc.undo_redo.clear_history()


## The layer's own texels by document pixel, read back.
func _texels() -> Dictionary:
    var out := {}
    var rd := GlobalShaderCompiler.get_rd()
    for grid_pos: Vector2i in _layer.chunks.keys():
        var texture := _layer.get_field(grid_pos)
        var bytes := rd.texture_get_data(texture.rid, 0)
        for y in texture.size.y:
            for x in texture.size.x:
                out[grid_pos * texture.size + Vector2i(x, y)] = SaFieldSpec.decode_texel(
                    bytes, texture.format, y * texture.size.x + x
                )
    return out


## The composite by document pixel after a full composite.
func _output() -> Dictionary:
    _doc.invalidate_chunks(CHUNKS)
    Bench.composite(_easel)
    var texture := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out := {}
    for y in SIZE.y:
        for x in SIZE.x:
            out[Vector2i(x, y)] = SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x)
    return out


## How far the nearest of the three levels is from *v*, for the 3 level cases.
static func _off_three(v: float) -> float:
    return minf(minf(absf(v), absf(v - 0.5)), absf(v - 1.0))


func test_three_levels_leave_every_channel_at_nought_a_half_or_one() -> void:
    _paint_ramp()
    assert_true(SaFilterOps.new(_doc).apply_once(_layer, _key, {"levels": 3}, "Posterise"), "Bake writes the layer")
    var texels := _texels()
    var worst := 0.0
    var above_one := 0.0
    for at: Vector2i in texels:
        var c: Color = texels[at]
        if at.x >= SIZE.x - 1 - 2:
            above_one = maxf(above_one, c.r)
        if at.y % 37 != 0 or at.x > SIZE.x - 1 - 150:
            continue
        for v: float in [c.r, c.g, c.b]:
            worst = maxf(worst, _off_three(v))
    assert_true(worst <= ON_LEVEL, "Every channel below the ramp's top is on a level, worst %s" % worst)
    var top: Color = texels[Vector2i(SIZE.x - 1, 0)]
    assert_true(top.r > 1.0, "A texel of %s stays above 1 and reads %s" % [PEAK, top.r])
    assert_true(absf(top.r - 1.5) <= ON_LEVEL, "on the step beyond one, 1.5, and nothing clamped: %s" % top.r)
    assert_true(above_one > 1.0, "and the top of the ramp is past one")
    var half := floori(SIZE.x / 2.0)
    var middle: Color = texels[Vector2i(half, 3)]
    var said := "A value of %s rounds to the middle level, read %s" % [_ramp(half), middle.r]
    assert_true(absf(middle.r - 0.5) <= ON_LEVEL, said)
    var bottom: Color = texels[Vector2i(0, 0)]
    assert_true(bottom.r == 0.0 and bottom.a == 1.0, "Black stays black and alpha is kept")


func test_it_rounds_to_the_nearest_level_at_the_halfway_points() -> void:
    _paint_ramp()
    SaFilterOps.new(_doc).apply_once(_layer, _key, {"levels": 3}, "Posterise")
    var texels := _texels()
    for x in range(0, SIZE.x, 7):
        var v := _ramp(x)
        var want := roundf(v * 2.0) / 2.0
        if absf(v * 2.0 - floorf(v * 2.0) - 0.5) < 1e-3:
            continue
        assert_true(absf((texels[Vector2i(x, 5)] as Color).g - want) <= ON_LEVEL, "Column %d at %s reads %s" % [x, v, want])


func test_attached_the_composite_equals_the_baked_layer() -> void:
    _paint_ramp()
    var painted := _texels()
    SaFilterOps.new(_doc).attach(_layer, _key, {"levels": 3})
    var attached := _output()
    assert_true(_apart(painted, _texels()) == 0.0, "Attaching writes no paint")
    SaFilterOps.new(_doc).detach(_layer, _layer.filters[0])
    assert_true(SaFilterOps.new(_doc).apply_once(_layer, _key, {"levels": 3}, "Posterise"), "Bake")
    var baked := _output()
    var worst := _apart(attached, baked)
    assert_true(worst <= BAKED_AGAINST_ATTACHED, "The attached composite is the baked layer's, worst %s" % worst)
    var edge: Color = attached[Vector2i(SIZE.x - 1, 0)]
    assert_true(edge.r > 1.0, "and carries the value past one, %s" % edge.r)


func test_it_quantises_the_picture_the_painter_sees_on_an_oklab_document() -> void:
    _open(SaColorSpace.oklab())
    var shown := Color(0.9, 0.6, 0.1, 1.0)
    _layer.fill(_doc.color_space.from_display(shown))
    SaFilterOps.new(_doc).apply_once(_layer, _key, {"levels": 3}, "Posterise")
    var seen := _doc.color_space.to_display(_texels()[Vector2i(300, 100)] as Color)
    assert_true(absf(seen.r - 1.0) < 2e-3, "Red 0.9 rounds to 1, read %s" % seen.r)
    assert_true(absf(seen.g - 0.5) < 2e-3, "green 0.6 rounds to a half, read %s" % seen.g)
    assert_true(absf(seen.b) < 2e-3, "blue 0.1 rounds to nothing, read %s" % seen.b)


func test_the_filter_browser_finds_it_by_the_word_poster() -> void:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    var mod := BaseModule.new()
    mod.register(registries.context.for_module(mod.get_id()))
    var docker := FiltersDocker.new()
    docker.browser.watch(registries.filters, registries.commands)
    docker.browser.search_for("poster")
    var listed: Array = docker.describe()["listed"]
    var key := SaFilterRegistry.key_for(mod.get_id(), SaPosteriseFilter.new())
    assert_eq(listed, [String(key)], "Searching 'poster' lists Posterise alone: %s" % [listed])
    assert_eq(registries.filters.section_of(key), &"tone", "under Tone")
    docker.free()
    mod.unregister(registries.context.for_module(mod.get_id()))


static func _apart(a: Dictionary, b: Dictionary) -> float:
    var worst := 0.0
    for at: Vector2i in a:
        var x: Color = a[at]
        var y: Color = b.get(at, Color(INF, INF, INF, INF))
        worst = maxf(worst, maxf(maxf(absf(x.r - y.r), absf(x.g - y.g)), maxf(absf(x.b - y.b), absf(x.a - y.a))))
    return worst
