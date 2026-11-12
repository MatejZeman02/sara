## The Laplacian sharpens the picture itself, with the raw map
## one switch away.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The filter lays its map over the picture in Overlay on its own, rather than
## tell the painter to. So Apply on a
## soft edge pushes the two sides apart and leaves a flat area as it was, and
## what it writes is what a duplicate holding the raw map would composite to,
## laid above the layer in Overlay at the Amount's opacity. That equality is
## read through the compositor's own Overlay, on an RGB document under white,
## above white under a wider blend white, and on an Oklab document. The map's
## neutral is half the blend white, so a flat area is left as it was under a
## wider white too. With Show the raw map ticked the filter writes the map
## it builds.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const NEUTRAL := SaLaplacianFilter.NEUTRAL

const SIZE := Vector2i(512, 256)
## A soft edge in mid tones, where Overlay moves a backdrop the most, and in
## three channels apart so each is read on its own.
const DARK := Color(0.3, 0.25, 0.35, 1.0)
const BRIGHT := Color(0.7, 0.75, 0.6, 1.0)
## The same edge with its bright side above white in every channel.
const SUN := Color(1.8, 1.5, 1.2, 1.0)

## The soft edge: a ramp of RAMP_WIDTH columns from the dark side to the bright,
## one fill each, starting at RAMP_FROM.
const RAMP_FROM := 124
const RAMP_WIDTH := 3
## A row well inside the layer, and the columns read across the edge.
const ROW := 100
const ACROSS_FROM := RAMP_FROM - 4
const ACROSS := RAMP_WIDTH + 8
## Points far from the edge, either side of it and across a chunk's seam.
const FLAT_POINTS: Array[Vector2i] = [Vector2i(20, 30), Vector2i(60, 200), Vector2i(300, 100), Vector2i(500, 250)]

## The settings of the equality cases, away from the defaults so a default
## standing in for a setting would show.
const STRENGTH := 2.0
const AMOUNT := 60

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func before_each() -> void:
    _open(null)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


## A fresh easel over a document in *space*, gamma sRGB when null.
func _open(space: SaColorSpace) -> void:
    if _easel != null:
        _easel.free()
    _easel = Bench.easel(SIZE) if space == null else SaEasel.create_default(SIZE, null, space)
    if space != null:
        _easel.compositor.set_registry(Bench.Fixtures.make_registries().blend_modes)
    _doc = _easel.document
    _layer = _doc.active_layer


## *dark*, then *bright*, with RAMP_WIDTH columns of colours between, each in
## the document's own numbers.
func _soft_edge(dark: Color, bright: Color) -> void:
    var space := _doc.color_space
    _layer.fill(space.from_display(dark))
    for column in RAMP_WIDTH:
        _doc.selection.select_rect(Rect2i(RAMP_FROM + column, 0, 1, SIZE.y))
        _layer.fill(space.from_display(dark.lerp(bright, float(column + 1) / float(RAMP_WIDTH + 1))))
    _doc.selection.select_rect(Rect2i(RAMP_FROM + RAMP_WIDTH, 0, SIZE.x - RAMP_FROM - RAMP_WIDTH, SIZE.y))
    _layer.fill(space.from_display(bright))
    _doc.selection.deselect()


func _apply(layer: SaLayer, values: Dictionary) -> bool:
    var filter := SaLaplacianFilter.new()
    filter.set_parameters(values)
    var ctx := SaFilterContext.new(_doc, layer, OWNER, filter.title())
    if not SaFilterApply.call_run(filter, ctx):
        return false
    return SaFilterApply.apply(ctx, filter.title())


func _texel(x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := _layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(
        bytes, texture.format, (y - grid.y * SaChunk.SIZE) * texture.size.x + (x - grid.x * SaChunk.SIZE)
    )


## The composite at the columns across the edge and then at the flat points.
func _composite() -> Array[Color]:
    Bench.composite(_easel)
    var read: Array[Color] = []
    for column in ACROSS:
        read.append(Bench.texel(_easel.output, Vector2i(ACROSS_FROM + column, ROW)))
    for at in FLAT_POINTS:
        read.append(Bench.texel(_easel.output, at))
    return read


## The composite with the filter applied to the layer itself, then, once that
## is undone, with the raw map on a duplicate above it in Overlay at the same
## opacity, each read by `_composite`.
func _filtered_and_laid() -> Array:
    assert_true(_apply(_layer, {"strength": STRENGTH, "amount": AMOUNT}), "The Laplacian sharpens the layer")
    var filtered := _composite()
    assert_true(_doc.undo(), "which undoes")

    var ops := SaLayerOps.new(_doc)
    var copy := ops.duplicate(_layer)
    assert_not_null(copy, "The layer is duplicated")
    assert_true(_apply(copy, {"strength": STRENGTH, "raw": true}), "and the duplicate takes the raw map")
    ops.set_blend_mode(copy, SaLayer.BLEND_MODE.OVERLAY)
    ops.set_opacity(copy, AMOUNT / 100.0)
    return [filtered, _composite()]


func _assert_the_same(pair: Array, tolerance: float, what: String) -> void:
    var filtered: Array[Color] = pair[0]
    var laid: Array[Color] = pair[1]
    assert_eq(filtered.size(), laid.size(), "Both composites are read at the same points")
    var largest := 0.0
    for i in filtered.size():
        for channel in 4:
            largest = maxf(largest, absf(filtered[i][channel] - laid[i][channel]))
    assert_true(largest <= tolerance, "%s: the filter's result is the duplicate's, the largest difference %s" % [what, largest])


func test_apply_pushes_the_two_sides_of_a_soft_edge_apart_and_leaves_a_flat_area_as_it_was() -> void:
    _soft_edge(DARK, BRIGHT)
    var dark_before := _texel(RAMP_FROM - 1, ROW)
    var bright_before := _texel(RAMP_FROM + RAMP_WIDTH, ROW)
    var flat_before: Array[Color] = []
    for at in FLAT_POINTS:
        flat_before.append(_texel(at.x, at.y))

    assert_true(_apply(_layer, {}), "The Laplacian runs at its defaults")

    var dark_after := _texel(RAMP_FROM - 1, ROW)
    var bright_after := _texel(RAMP_FROM + RAMP_WIDTH, ROW)
    for channel in 3:
        assert_true(
            dark_after[channel] < dark_before[channel] - 0.01,
            "Channel %d on the dark side falls, %s from %s" % [channel, dark_after[channel], dark_before[channel]]
        )
        assert_true(
            bright_after[channel] > bright_before[channel] + 0.01,
            "Channel %d on the bright side rises, %s from %s" % [channel, bright_after[channel], bright_before[channel]]
        )
    assert_almost_eq(dark_after.a, 1.0, 1e-6, "The dark side keeps its alpha")
    assert_almost_eq(bright_after.a, 1.0, 1e-6, "and the bright side its own")
    for i in FLAT_POINTS.size():
        var found := _texel(FLAT_POINTS[i].x, FLAT_POINTS[i].y)
        for channel in 4:
            assert_almost_eq(
                found[channel], flat_before[i][channel], 1e-5, "Channel %d at %s is as it was" % [channel, FLAT_POINTS[i]]
            )
    assert_true(absf(_texel(20, 30).r - NEUTRAL) > 0.1, "The flat dark side is not the map's grey")


func test_the_result_is_the_raw_map_laid_in_overlay_on_a_duplicate_at_the_same_opacity() -> void:
    _soft_edge(DARK, BRIGHT)

    _assert_the_same(_filtered_and_laid(), 1e-5, "Under white")


func test_above_white_under_a_wider_blend_white_it_is_still_the_duplicate_in_overlay() -> void:
    _doc.blend_reference_white = 2.0
    _soft_edge(DARK, SUN)
    assert_true(_texel(RAMP_FROM + RAMP_WIDTH, ROW).r > 1.0, "The bright side is stored above white")

    var pair := _filtered_and_laid()

    _assert_the_same(pair, 1e-5, "Above white at a blend white of 2")
    var filtered: Array[Color] = pair[0]
    var bright := filtered[RAMP_FROM + RAMP_WIDTH - ACROSS_FROM]
    assert_true(bright.r > SUN.r, "and the bright side above white still rises, %s" % bright.r)
    var far := filtered[ACROSS + 2]
    assert_almost_eq(far.r, SUN.r, 1e-5, "while the bright side far from the edge stays at %s, %s" % [SUN.r, far.r])
    var dark := filtered[ACROSS]
    assert_almost_eq(dark.r, DARK.r, 1e-5, "and the dark side at %s, %s" % [DARK.r, dark.r])


func test_on_an_oklab_document_it_is_the_duplicate_in_overlay_in_the_rgb_view() -> void:
    _open(SaColorSpace.oklab())
    _soft_edge(DARK, BRIGHT)

    _assert_the_same(_filtered_and_laid(), 1e-4, "On an Oklab document")


func test_an_amount_of_nothing_leaves_the_picture_as_it_was() -> void:
    _soft_edge(DARK, BRIGHT)
    var before := _texel(RAMP_FROM - 1, ROW)

    assert_true(_apply(_layer, {"strength": 4.0, "amount": 0}), "The Laplacian runs at an amount of 0")

    var after := _texel(RAMP_FROM - 1, ROW)
    for channel in 4:
        assert_almost_eq(after[channel], before[channel], 1e-6, "Channel %d beside the edge is as it was" % channel)


func test_show_the_raw_map_writes_the_map_around_the_neutral() -> void:
    _soft_edge(DARK, BRIGHT)

    assert_true(_apply(_layer, {"strength": 1.0, "raw": true}), "The Laplacian runs with the raw map ticked")

    for at in FLAT_POINTS:
        var found := _texel(at.x, at.y)
        for channel in 3:
            assert_almost_eq(found[channel], NEUTRAL, 1e-5, "Channel %d at %s reads the neutral" % [channel, at])
    var dark := _texel(RAMP_FROM - 1, ROW)
    var bright := _texel(RAMP_FROM + RAMP_WIDTH, ROW)
    assert_true(dark.r < NEUTRAL - 0.01, "The dark side of the edge reads below the neutral, %s" % dark.r)
    assert_true(bright.r > NEUTRAL + 0.01, "the bright side above it, %s" % bright.r)
    assert_almost_eq(dark.r, dark.b, 1e-6, "and the map is grey")
