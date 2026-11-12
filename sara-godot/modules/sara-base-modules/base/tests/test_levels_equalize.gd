## Levels' Equalize: the map the button fills from the layer's
## cumulative distribution, and what the `levels` kernel does with it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The layer is four chunks side by side, each one level of a narrow band, so
## the histogram has four spikes a few bins apart and an equalized layer has
## them at a lightness of black, a third, two thirds and white. The map is
## Oklab L's whatever channel the handles are on, so the counts
## are the Lightness row, taken the way the panel takes them, a histogram pass
## over the layer read back once, and the map goes through the panel so the
## press and the kernel are one path. The band's greys are on levels of the
## sRGB curve and between levels of Oklab L, which is where a painted colour
## usually sits, and the map still lands each on its own share.
extends "res://tests/test_framework.gd"

## Real dispatches into real chunks.
const REQUIRES_GPU := true

## The band, four sRGB levels a few bins apart, whose Oklab lightness falls
## between two bins, the case the map's empty levels under paint are for.
const BAND_BINS: Array[int] = [102, 108, 114, 120]

## A half float stores a level to about a four-thousandth, which moves the
## read a fraction of a bin, and a spike's neighbouring entry is a third away.
const TOLERANCE := 0.03


func _level(bin: int) -> float:
    return float(bin) / 255.0


func _easel(space: SaColorSpace = SaColorSpace.srgb()) -> SaEasel:
    var side := SaChunk.SIZE
    return SaEasel.create_default(Vector2i(side * BAND_BINS.size(), side), null, space)


## The band on every channel for Master, or on red alone with green and blue
## held at *rest* for a colour channel.
func _paint_band(easel: SaEasel, red_only: bool, rest: float = 0.3) -> SaLayer:
    var layer := easel.document.get_node_or_null("Layer 1") as SaLayer
    for index in BAND_BINS.size():
        var v := _level(BAND_BINS[index])
        var colour := Color(v, rest, rest, 1.0) if red_only else Color(v, v, v, 1.0)
        layer.get_or_create_chunk(Vector2i(index, 0)).clear(colour)
    easel.document.set_active_layer(layer)
    return layer


func _counts(layer: SaLayer, channel: String, space: SaColorSpace = SaColorSpace.srgb()) -> PackedInt32Array:
    var plot := SaGraphPlot.new()
    plot.scale = "linear"
    plot.histogram_channel = channel
    assert_true(plot.run_over_layer(layer, space, "histogram"), "The %s pass runs" % channel)
    return plot.read_counts()


## The lowest and highest occupied bin of *row*, as levels.
func _span(counts: PackedInt32Array, row: int) -> Vector2:
    var low := -1
    var high := -1
    for bin in 256:
        if counts[row * 256 + bin] > 0:
            if low < 0:
                low = bin
            high = bin
    return Vector2(float(low) / 255.0, float(high) / 255.0)


func _texel(layer: SaLayer, chunk: int) -> Color:
    var texture := layer.get_field(Vector2i(chunk, 0))
    @warning_ignore("static_called_on_instance")
    return SaExport.get_texture_image_float(texture).get_pixel(8, 8)


## The Oklab lightness of *chunk*'s texel in a document of *space*.
func _lightness(layer: SaLayer, chunk: int, space: SaColorSpace = SaColorSpace.srgb()) -> float:
    var texel := _texel(layer, chunk)
    var curve := space.transfer
    var light := Vector3(curve.decode(texel.r), curve.decode(texel.g), curve.decode(texel.b))
    return SaOklab.from_linear_srgb(space.to_linear_srgb_matrix() * light).x


## The panel on *channel* pressed over *layer*'s Lightness counts, the ones
## its press asks the door for, with *handles* typed after.
func _pressed(layer: SaLayer, channel: String, handles: Dictionary = {}, space := SaColorSpace.srgb()) -> Dictionary:
    var panel := SaLevelsPanel.new()
    panel.set_parameters({"channel": channel})
    var counts := _counts(layer, SaLevelsPanel.MAP_CHANNEL, space)
    assert_true(panel.equalize_from_counts(counts), "Equalize takes a map with the handles on %s" % channel)
    if not handles.is_empty():
        panel.set_values(handles)
    var out := panel.values()
    panel.free()
    return out


func _apply(easel: SaEasel, layer: SaLayer, values: Dictionary) -> void:
    var filter := SaLevelsFilter.new()
    filter.set_parameters(values)
    var ran := SaPointAdjust.new().apply(easel.document, layer, SaPointAdjust.LEVELS, filter.values(), "Levels")
    assert_true(ran, "The pass runs")


func test_the_map_is_the_share_above_the_darkest_level() -> void:
    var row := PackedInt32Array()
    row.resize(256)
    row[10] = 2
    row[20] = 1
    row[30] = 1
    var map := SaLevelsFilter.cdf_map(row)
    assert_eq(map.size(), 256, "One entry a level")
    assert_almost_eq(float(map[0]), 0.0, 1e-6, "Below the paint is black")
    assert_almost_eq(float(map[10]), 0.0, 1e-6, "the darkest painted level comes out black")
    assert_almost_eq(float(map[20]), 0.5, 1e-6, "the next holds half of what is above it")
    assert_almost_eq(float(map[30]), 1.0, 1e-6, "and the brightest is white")
    assert_almost_eq(float(map[255]), 1.0, 1e-6, "as is everything above it")

    assert_almost_eq(float(map[19]), 0.5, 1e-6, "An empty level just under paint takes the paint's share")
    assert_almost_eq(float(map[29]), 1.0, 1e-6, "the brightest's too")
    assert_almost_eq(float(map[15]), 0.0, 1e-6, "and one further under keeps the share below it")

    var one := PackedInt32Array()
    one.resize(256)
    one[40] = 9
    assert_eq(SaLevelsFilter.cdf_map(one), [], "One level has no spread to make")


func test_master_spreads_a_narrow_band_of_lightness_across_the_range() -> void:
    var easel := _easel()
    var layer := _paint_band(easel, false)
    var before := _span(_counts(layer, "lightness"), SaAdjustGraph.LUMA_ROW)
    assert_true(before.y - before.x < 0.1, "The band is narrow before, %s" % before)

    _apply(easel, layer, _pressed(layer, "master"))

    var after := _span(_counts(layer, "lightness"), SaAdjustGraph.LUMA_ROW)
    assert_true(after.x < 0.02 and after.y > 0.98, "Equalized, its lightness spans the range, %s" % after)
    for index in BAND_BINS.size():
        var texel := _texel(layer, index)
        var wanted := float(index) / float(BAND_BINS.size() - 1)
        assert_almost_eq(_lightness(layer, index), wanted, TOLERANCE, "Level %d lands at %.3f" % [index, wanted])
        assert_almost_eq(texel.r, texel.b, 1e-3, "and stays grey")
    easel.free()


## Every channel the handles can be on takes the one map, Oklab L's, and says
## so under "equalize_channel".
func test_the_map_is_the_lightness_map_whatever_channel_the_handles_are_on() -> void:
    var easel := _easel()
    var layer := _paint_band(easel, true)
    var master := _pressed(layer, "master")
    for channel: String in SaPointAdjust.CHANNELS:
        var values := _pressed(layer, channel)
        assert_eq(values["equalize"], master["equalize"], "On %s the map is Master's" % channel)
        assert_eq(values["equalize_channel"], "lightness", "counted on Oklab L")
    easel.free()


## The channel row still chooses what the handles move: a red black point over
## an equalized layer moves red and leaves green and blue where Equalize put
## them. Equalizing the lightness of a red sends some of it past one, which the
## handle carries on along its line rather than pinning.
func test_a_red_handle_over_the_equalized_layer_moves_red_alone() -> void:
    var plain := _easel()
    var plain_layer := _paint_band(plain, true)
    _apply(plain, plain_layer, _pressed(plain_layer, "red"))
    var handled := _easel()
    var handled_layer := _paint_band(handled, true)
    _apply(handled, handled_layer, _pressed(handled_layer, "red", {"in_black": 0.2}))

    for index in BAND_BINS.size():
        var equalized := _texel(plain_layer, index)
        var moved := _texel(handled_layer, index)
        assert_almost_eq(moved.g, equalized.g, 1e-3, "Green of level %d stays where Equalize put it" % index)
        assert_almost_eq(moved.b, equalized.b, 1e-3, "and blue")
        var wanted := (equalized.r - 0.2) / 0.8
        assert_almost_eq(moved.r, wanted, 2e-3, "and red takes the black point, unclamped above one")
    plain.free()
    handled.free()


## The handles act on the equalized values: a black point at a half on
## Lightness sends the level Equalize put at two thirds to a third.
func test_the_black_handle_moves_over_the_equalized_layer() -> void:
    var easel := _easel()
    var layer := _paint_band(easel, false)

    _apply(easel, layer, _pressed(layer, "lightness", {"in_black": 0.5}))

    assert_almost_eq(_lightness(layer, 2), 1.0 / 3.0, TOLERANCE, "Two thirds, then the black point, is a third")
    assert_almost_eq(_lightness(layer, 3), 1.0, TOLERANCE, "white stays white")
    var black := _lightness(layer, 0)
    assert_true(black < -0.9, "and black goes below zero, unclamped, %.3f" % black)
    easel.free()


## A document whose encoded view is not the screen's, here linear light, is
## counted on Oklab L by the graph as every document is, so the map is read on
## Oklab L too. Read in the document's own view it would land the whole band
## past white, which is what the first build of this did on the default space.
func test_the_map_reads_the_levels_it_was_counted_in() -> void:
    var space := SaColorSpace.linear_srgb()
    var easel := _easel(space)
    var layer := easel.document.get_node_or_null("Layer 1") as SaLayer
    for index in BAND_BINS.size():
        var v := Color(_level(BAND_BINS[index]), 0.0, 0.0).srgb_to_linear().r
        layer.get_or_create_chunk(Vector2i(index, 0)).clear(Color(v, v, v, 1.0))
    easel.document.set_active_layer(layer)

    _apply(easel, layer, _pressed(layer, "master", {}, space))

    var after := _span(_counts(layer, "lightness", space), SaAdjustGraph.LUMA_ROW)
    assert_true(after.x < 0.02 and after.y > 0.98, "Equalized, its lightness spans the range, %s" % after)
    assert_almost_eq(_lightness(layer, 1, space), 1.0 / 3.0, TOLERANCE, "and the second level is at a third")
    easel.free()


## Hard rule 5: a level above one carries on past the map's white along the
## end's slope, one where the distribution has gone flat.
func test_a_level_off_the_map_is_not_pinned() -> void:
    var easel := _easel()
    var layer := _paint_band(easel, false)
    var values := _pressed(layer, "master")
    layer.get_or_create_chunk(Vector2i(3, 0)).clear(Color(1.5, 1.5, 1.5, 1.0))

    _apply(easel, layer, values)

    assert_almost_eq(_texel(layer, 3).r, 1.5, TOLERANCE, "One and a half stays past white")
    easel.free()


func test_apply_is_one_step_and_undo_restores_the_layer() -> void:
    var easel := _easel()
    var layer := _paint_band(easel, false)
    var values := _pressed(layer, "master")
    var steps := easel.document.history.step_count()

    _apply(easel, layer, values)

    assert_eq(easel.document.history.step_count(), steps + 1, "One step")
    easel.document.undo_redo.undo()
    assert_almost_eq(_texel(layer, 1).r, _level(BAND_BINS[1]), 2e-3, "which one undo puts back")
    easel.free()


func test_reset_drops_the_map() -> void:
    var panel := SaLevelsPanel.new()
    var row := PackedInt32Array()
    row.resize(4 * 256)
    row[3 * 256 + 10] = 1
    row[3 * 256 + 200] = 1
    assert_true(panel.equalize_from_counts(row), "A map from the Lightness row")
    assert_eq((panel.values()["equalize"] as Array).size(), 256, "which the values carry")
    assert_eq(panel.values()["equalize_channel"], "lightness", "with the channel it is counted on")
    panel.reset_equalize()
    assert_eq(panel.values()["equalize"], [], "Reset empties it")
    assert_eq(SaPointAdjust.table(panel.values())[SaPointAdjust.EQUALIZE_BASE], -1.0, "and the kernel skips it")
    panel.free()


## The kernel writes the offset out as a sum, because the palette's constants
## are declared below it, so the sum is read from the file and held to the
## class's layout here.
func test_the_kernel_finds_the_map_where_the_table_writes_it() -> void:
    var source := FileAccess.get_file_as_string("res://modules/sara-base-modules/base/shaders/adjust.gmacs")
    var found := RegEx.create_from_string("const int EQUALIZE_BASE = ([0-9 +*]+)").search(source)
    assert_true(found != null, "The kernel declares the offset")
    var sum := Expression.new()
    assert_eq(sum.parse(found.get_string(1).strip_edges()), OK, "as a sum")
    assert_eq(int(sum.execute()), SaPointAdjust.EQUALIZE_BASE, "which is where the table writes the map")
    assert_eq(SaPointAdjust.EQUALIZE_BASE, SaPointAdjust.PALETTE_BASE + SaPointAdjust.PALETTE_FLOATS, "above the palette")
