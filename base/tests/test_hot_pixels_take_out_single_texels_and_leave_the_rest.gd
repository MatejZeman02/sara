## Hot Pixels replaces a texel that stands apart from every one of
## its neighbours by their median and leaves every other texel as it was.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A flat layer two chunks wide takes three single bright texels, one inside the
## first chunk, one on the column the two chunks meet at and one on the canvas's
## left edge, and a bright block of three by three. After Apply the three singles
## read the flat colour and every other texel of both chunks reads the bytes it
## held before, the block's among them. A flat area at 3.0 with one texel at 9.0
## reads 3.0 everywhere, through Apply and through the compositor's chain, which
## run the same pass.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const HotPixelsFilter = preload("res://modules/sara-base-modules/base/usual/hot_pixels_filter.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const MODULE_DIR := "res://modules/sara-base-modules"

## Two chunks side by side at the default chunk size, the second cut short by
## the canvas.
const SIZE := Vector2i(384, 256)
const FLAT := Color(0.25, 0.4, 0.6, 1.0)
## Above white, so the case reads that nothing clamps on the way.
const BRIGHT := Color(4.0, 3.5, 2.0, 1.0)
## Inside the first chunk, on the last column of the first chunk so its right
## neighbours are the second chunk's, and on the canvas's left edge.
const SINGLES: Array[Vector2i] = [Vector2i(60, 70), Vector2i(255, 128), Vector2i(0, 200)]
const BLOCK := Rect2i(150, 150, 3, 3)

## The flat area above one and the texel standing six whites from it.
const LOW := Color(3.0, 3.0, 3.0, 1.0)
const HIGH := Color(9.0, 9.0, 9.0, 1.0)
const DOT := Vector2i(100, 120)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _dir_was_set: bool = false


func before_each() -> void:
    _dir_was_set = ModuleLoader.module_dirs.has(OWNER)
    if not _dir_was_set:
        ModuleLoader.module_dirs[OWNER] = MODULE_DIR
    _easel = Bench.easel(SIZE)
    _doc = _easel.document
    _layer = _doc.active_layer


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null
    if not _dir_was_set:
        ModuleLoader.module_dirs.erase(OWNER)


func _paint(rect: Rect2i, colour: Color) -> void:
    _doc.selection.select_rect(rect)
    _layer.fill(colour)
    _doc.selection.deselect()


func _apply() -> bool:
    var filter := HotPixelsFilter.new()
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, filter.title())
    if not SaFilterApply.call_run(filter, ctx):
        return false
    return SaFilterApply.apply(ctx, filter.title())


## Every allocated chunk's bytes, by its grid position.
func _bytes() -> Dictionary[Vector2i, PackedByteArray]:
    var out: Dictionary[Vector2i, PackedByteArray] = {}
    for grid: Vector2i in _layer.chunks.keys():
        out[grid] = GlobalShaderCompiler.get_rd().texture_get_data(_layer.get_field(grid).rid, 0)
    return out


## The chunk holding the document pixel *at*, its side in texels and the texel's
## index in it, asked of the chunk rather than assumed (hard rule 3).
func _place(at: Vector2i) -> Array:
    var chunk: SaChunk = _layer.chunks.values()[0]
    var side := chunk.pixel_size()
    @warning_ignore("integer_division")
    var grid := Vector2i(at.x / side, at.y / side)
    return [grid, (at.y - grid.y * side) * side + (at.x - grid.x * side)]


func _width() -> int:
    var texture := _layer.get_field(_layer.chunks.keys()[0])
    return SaFieldSpec.BYTES_PER_TEXEL.get(texture.format, 0)


func _texel(bytes: Dictionary[Vector2i, PackedByteArray], at: Vector2i) -> Color:
    var place := _place(at)
    var texture := _layer.get_field(place[0])
    return SaFieldSpec.decode_texel(bytes[place[0]], texture.format, place[1])


## *bytes* with the texel at *at* given the bytes the texel at *from* holds.
func _copied(bytes: Dictionary[Vector2i, PackedByteArray], at: Vector2i, from: Vector2i) -> void:
    var width := _width()
    var to: Array = _place(at)
    var source: Array = _place(from)
    var held: PackedByteArray = bytes[source[0]].slice(source[1] * width, (source[1] + 1) * width)
    var target: PackedByteArray = bytes[to[0]]
    for i in width:
        target[to[1] * width + i] = held[i]
    bytes[to[0]] = target


## How many texels *found* holds that differ from *wanted*, and the first of them.
func _differences(found: Dictionary[Vector2i, PackedByteArray], wanted: Dictionary[Vector2i, PackedByteArray]) -> String:
    var width := _width()
    var count := 0
    var first := ""
    for grid: Vector2i in wanted.keys():
        var a: PackedByteArray = found.get(grid, PackedByteArray())
        var b: PackedByteArray = wanted[grid]
        if a == b:
            continue
        @warning_ignore("integer_division")
        var texels := b.size() / width
        for index in texels:
            if a.slice(index * width, (index + 1) * width) != b.slice(index * width, (index + 1) * width):
                count += 1
                if first.is_empty():
                    first = "chunk %s texel %d" % [grid, index]
    return "%d texels differ, the first %s" % [count, first] if count > 0 else ""


func test_the_filter_answers_its_threshold() -> void:
    var filter := HotPixelsFilter.new()
    assert_eq(filter.parameters(), {"threshold": 20.0}, "With no dialog it answers its default threshold")
    assert_eq(filter.family(), &"noise", "and is listed under Noise")


func test_the_single_texels_read_the_flat_colour_and_every_other_texel_is_unchanged() -> void:
    _layer.fill(FLAT)
    for at in SINGLES:
        _paint(Rect2i(at, Vector2i.ONE), BRIGHT)
    _paint(BLOCK, BRIGHT)
    var before := _bytes()
    for at in SINGLES:
        assert_almost_eq(_texel(before, at).r, BRIGHT.r, 1e-3, "The single at %s is painted bright" % at)

    assert_true(_apply(), "Hot Pixels runs over the layer")

    var after := _bytes()
    assert_eq(after.keys().size(), before.keys().size(), "and allocates no chunk")
    var wanted: Dictionary[Vector2i, PackedByteArray] = before.duplicate(true)
    var flat := _texel(before, Vector2i(30, 30))
    for at in SINGLES:
        _copied(wanted, at, Vector2i(30, 30))
        var found := _texel(after, at)
        for channel in 4:
            assert_eq(found[channel], flat[channel], "Channel %d of the single at %s reads the flat colour" % [channel, at])
    for at: Vector2i in [BLOCK.position, BLOCK.get_center(), BLOCK.end - Vector2i.ONE]:
        assert_almost_eq(_texel(after, at).r, BRIGHT.r, 1e-3, "The block keeps its texel at %s" % at)
    assert_eq(_differences(after, wanted), "", "Every texel but the three singles holds the bytes it held before")


func test_a_flat_area_at_three_with_a_texel_at_nine_reads_three_everywhere() -> void:
    _layer.fill(LOW)
    _paint(Rect2i(DOT, Vector2i.ONE), HIGH)
    var flat := _bytes()
    _copied(flat, DOT, Vector2i(10, 10))
    assert_almost_eq(_texel(_bytes(), DOT).r, HIGH.r, 1e-3, "The dot is painted at 9.0")

    assert_true(_apply(), "Hot Pixels runs over the layer")

    var after := _bytes()
    assert_eq(_texel(after, DOT), LOW, "The dot reads 3.0")
    assert_eq(_differences(after, flat), "", "and every texel reads 3.0, the flat area above one kept whole")


## The attached form through the compositor's chain, the same pass Apply runs.
func test_attached_the_texel_at_nine_reads_three() -> void:
    var filter := HotPixelsFilter.new()
    _easel.compositor.filter_chain.registry.register(filter, OWNER)
    var key := SaFilterRegistry.key_for(OWNER, filter)
    _layer.fill(LOW)
    _paint(Rect2i(DOT, Vector2i.ONE), HIGH)
    SaFilterOps.new(_doc).attach(_layer, key, {"threshold": 20.0})
    Bench.composite(_easel)
    var grid: Vector2i = _place(DOT)[0]
    var answer := _easel.compositor.filter_chain.filtered(_layer, _layer.get_field(grid), grid, SaDocument.WHOLE_CHUNK)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(answer.rid, 0)
    for at: Vector2i in [DOT, DOT + Vector2i.ONE, Vector2i(10, 10)]:
        var place := _place(at)
        var found := SaFieldSpec.decode_texel(bytes, answer.format, place[1])
        for channel in 3:
            assert_eq(found[channel], 3.0, "Channel %d at %s reads 3.0 through the chain" % [channel, at])
