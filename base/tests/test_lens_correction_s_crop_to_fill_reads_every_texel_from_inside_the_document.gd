## Lens Correction's Crop to fill scales the corrected picture
## up so every texel of the document reads from a place inside it, and a picture
## drawn in shows no streaked edge. With the switch off the edges read from
## outside as they did. A record saved before the switch reads it as off, and a
## document saved before it loads and shows the pixels it showed. Nothing holds
## the slider, so on a photograph it reaches the amount typed either way
## and the kernel is handed that amount.
##
## The layer is a ramp that says where each texel stands, red the column and
## green the row, so a texel of the composite says where it read from. A read
## inside the document lands where it was asked to, on the texel's own radius
## from the centre and at full alpha. A read from outside is either transparent
## or the edge's texel smeared outwards, which is off the radius, so either way
## it is found.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## Real dispatches into real chunks.
const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
## Two chunks on a side, the centre the corner four of them share.
const SIZE := Vector2i(512, 512)
## A drawn-in amount the switch is read at, and the strongest a typed value takes.
const DRAWN_IN := -20.0
const STRONGEST := -30.0
## How far off its radius, in document pixels, a read may land and still be the
## texel's own. A smeared edge is tens of pixels off.
const OFF_RADIUS := 0.05
## How far past the middle of an edge texel a read may fall to the float's
## error, in document pixels.
const PAST_THE_EDGE := 0.01
## The alpha a read wholly inside keeps.
const WHOLE := 0.9999
## Texels this near the centre say nothing of a radius.
const NEAR_THE_CENTRE := 2.0
## The document saved by the code before this row, Lens Correction at -15
## attached over a checker, and the composite it showed at every eighth texel
## from the third, four floats a texel.
const SAVED := "res://modules/sara-base-modules/base/tests/data/lens_correction_saved_before_crop_to_fill.sad"
const SHOWN := "res://modules/sara-base-modules/base/tests/data/lens_correction_saved_before_crop_to_fill.bin"
const SAMPLE_FROM := 3
const SAMPLE_EVERY := 8
## A photograph, whose half diagonal of 2500 pixels moves a corner 750 at the
## strongest amount, three chunks.
const PHOTO := Vector2i(4000, 3000)

var _easel: SaEasel = null
var _filter: SaLensCorrectionFilter = null
var _key: StringName = &""


func before_each() -> void:
    _easel = Bench.easel(SIZE)
    var registry := SaFilterRegistry.new()
    _filter = SaLensCorrectionFilter.new()
    registry.register(_filter, OWNER)
    _key = SaFilterRegistry.key_for(OWNER, _filter)
    _easel.compositor.filter_chain.registry = registry


func after_each() -> void:
    _easel.free()
    _easel = null
    _filter = null


## The Background as the ramp, over all four chunks.
func _paint_the_ramp() -> SaLayer:
    var layer := _easel.document.get_node("Background") as SaLayer
    for y in 2:
        for x in 2:
            var grid_pos := Vector2i(x, y)
            var chunk := layer.get_or_create_chunk(grid_pos)
            var side := chunk.pixel_size()
            var values := PackedFloat32Array()
            values.resize(side * side * 4)
            for py in side:
                for px in side:
                    var at := grid_pos * SaChunk.SIZE + Vector2i(px, py)
                    var i := (py * side + px) * 4
                    values[i] = (float(at.x) + 0.5) / float(SIZE.x)
                    values[i + 1] = (float(at.y) + 0.5) / float(SIZE.y)
                    values[i + 2] = 0.5
                    values[i + 3] = 1.0
            GlobalShaderCompiler.get_rd().texture_update(chunk.field(SaFieldSpec.ALBEDO).rid, 0, values.to_byte_array())
    return layer


## Attaches the filter over the ramp with *values* and answers how many texels
## of the composite read from a place outside the document, with the first
## found named.
func _texels_reading_outside(values: Dictionary) -> Array:
    SaFilterOps.new(_easel.document).attach(_paint_the_ramp(), _key, values)
    Bench.composite(_easel)
    var texture := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var centre := Vector2(SIZE) * 0.5
    var outside := 0
    var first := ""
    for y in SIZE.y:
        for x in SIZE.x:
            var read := SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x)
            var own := Vector2(x, y) + Vector2(0.5, 0.5)
            var place := Vector2(read.r * SIZE.x, read.g * SIZE.y)
            var why := _why_outside(read.a, own - centre, place - centre, place)
            if why.is_empty():
                continue
            outside += 1
            if first.is_empty():
                first = "%s, %s" % [Vector2i(x, y), why]
    return [outside, first]


## Why a texel whose own place is *own* from the centre read from outside,
## having read *alpha* at *place*, *seen* from the centre, or "" when it read
## from inside the document.
static func _why_outside(alpha: float, own: Vector2, seen: Vector2, place: Vector2) -> String:
    if alpha < WHOLE:
        return "read at alpha %f" % alpha
    var low := 0.5 - PAST_THE_EDGE
    var high := Vector2(SIZE) - Vector2(low, low)
    if place.x < low or place.y < low or place.x > high.x or place.y > high.y:
        return "read at %s" % place
    if own.length() > NEAR_THE_CENTRE:
        var off := absf(own.normalized().cross(seen))
        if off > OFF_RADIUS:
            return "read %.3f off its radius, at %s" % [off, place]
    return ""


func test_with_crop_to_fill_every_texel_reads_from_inside_the_document() -> void:
    var found := _texels_reading_outside({"amount": DRAWN_IN, String(SaLensCorrectionFilter.CROP): true})
    assert_eq(int(found[0]), 0, "At %.0f with Crop to fill no texel reads from outside: %s" % [DRAWN_IN, found[1]])


func test_at_the_strongest_amount_crop_to_fill_still_reads_from_inside() -> void:
    var found := _texels_reading_outside({"amount": STRONGEST, String(SaLensCorrectionFilter.CROP): true})
    assert_eq(int(found[0]), 0, "At %.0f with Crop to fill no texel reads from outside: %s" % [STRONGEST, found[1]])


func test_with_the_switch_off_the_edges_read_from_outside_as_before() -> void:
    var found := _texels_reading_outside({"amount": DRAWN_IN, String(SaLensCorrectionFilter.CROP): false})
    assert_true(int(found[0]) > 1000, "At %.0f with the switch off the edges read from outside: %d texels" % [DRAWN_IN, found[0]])


func test_a_new_filter_crops_and_a_record_without_the_switch_does_not() -> void:
    var fresh := SaLensCorrectionFilter.new()
    assert_true(SaTyped.flag(fresh.parameter(SaLensCorrectionFilter.CROP)), "A new filter has Crop to fill on")
    fresh.set_parameters({"amount": -15.0})
    assert_false(SaTyped.flag(fresh.parameter(SaLensCorrectionFilter.CROP)), "and a record saved before the switch reads it off")
    var params := SaLensCorrectionFilter.pass_params(fresh.parameters(), SIZE)
    assert_eq(float(params["zoom"]), 1.0, "so the kernel is handed no crop")
    var cropped := SaLensCorrectionFilter.pass_params({"amount": -15.0, "crop_to_fill": true}, SIZE)
    assert_true(float(cropped["zoom"]) > 1.0, "where the switch on scales it up: %f" % cropped["zoom"])
    var spread := SaLensCorrectionFilter.pass_params({"amount": 15.0, "crop_to_fill": true}, SIZE)
    assert_eq(float(spread["zoom"]), 1.0, "and above nought, where every read already falls inside, not at all")


func test_a_document_saved_before_crop_to_fill_loads_and_shows_the_same_pixels() -> void:
    var loaded := SaExport.load_sad(_easel.document, ProjectSettings.globalize_path(SAVED))
    assert_eq(loaded, OK, "The document saved before the switch loads")
    var layer := _easel.document.get_node_or_null("Background") as SaLayer
    assert_true(layer != null and layer.filters.size() == 1, "with its Lens Correction attached")
    if layer == null or layer.filters.size() != 1:
        return
    assert_false(layer.filters[0].parameters.has("crop_to_fill"), "and a record that never named the switch")
    Bench.composite(_easel)
    var shown := FileAccess.get_file_as_bytes(SHOWN).to_float32_array()
    var texture := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var worst := 0.0
    var index := 0
    for y in range(SAMPLE_FROM, SIZE.y, SAMPLE_EVERY):
        for x in range(SAMPLE_FROM, SIZE.x, SAMPLE_EVERY):
            var now := SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x)
            for channel in 4:
                worst = maxf(worst, absf(now[channel] - shown[index + channel]))
            index += 4
    assert_eq(index, shown.size(), "Every texel the fixture kept is read")
    assert_true(worst < 1e-6, "and each shows what it showed before the switch, off by %f at most" % worst)


## The dialog over the photograph, with the switch either way: the slider's
## ends are the hard ends, a typed 30 and -30 stay as typed, and the kernel is
## handed that amount through a pass that reads the whole node.
func test_on_a_photograph_nothing_holds_the_slider_and_the_kernel_is_handed_what_was_typed() -> void:
    var photo := SaDocument.new()
    photo.canvas_size = PHOTO
    var filter := SaLensCorrectionFilter.new()
    var dialog := SaDialog.for_filter(filter)
    var host := VBoxContainer.new()
    dialog.realize(host)
    var row := dialog.row(&"amount") as SaSlider
    for crop: bool in [false, true]:
        filter.write_parameter(SaLensCorrectionFilter.CROP, crop)
        for typed: float in [SaLensCorrectionFilter.HARD_AMOUNT, -SaLensCorrectionFilter.HARD_AMOUNT]:
            filter.write_parameter(&"amount", typed)
            var ctx := SaFilterContext.new(photo, null, OWNER, filter.title(), true)
            filter.run(ctx)
            var said := "with Crop to fill %s at %+.0f" % ["on" if crop else "off", typed]
            assert_almost_eq(float(filter.parameter(&"amount")), typed, 1e-6, "The amount stays as typed %s" % said)
            if row != null:
                assert_almost_eq(
                    float(row.max_value), SaLensCorrectionFilter.HARD_AMOUNT, 1e-6, "and the slider's top end is 30 %s" % said
                )
                assert_almost_eq(float(row.min_value), -SaLensCorrectionFilter.HARD_AMOUNT, 1e-6, "its bottom -30 %s" % said)
                assert_almost_eq(float(row.read()), typed, 1e-6, "and it shows the amount typed %s" % said)
            var recorded := ctx.point as SaNeighbourhoodPass
            assert_true(recorded != null, "The run records a pass %s" % said)
            if recorded == null:
                continue
            assert_almost_eq(float(recorded.params["amount"]) * 100.0, typed, 1e-4, "whose kernel is handed the amount %s" % said)
            # Below nought the crop pulls the corner back to its own place, and
            # the furthest read stays within a halo.
            var move := SaLensCorrectionFilter.largest_move(typed / 100.0, float(recorded.params["zoom"]), PHOTO)
            var whole := SaLensCorrectionFilter.reads_whole(move)
            assert_true(
                whole or (crop and typed < 0.0),
                "A read moving %.0f pixels %s needs the whole node unless the crop pulls it back" % [move, said]
            )
            assert_eq(recorded.whole(), whole, "and the pass reads the whole node exactly when it is %s" % said)
            if whole:
                assert_true(recorded.carries.is_valid(), "and says where a change lands %s" % said)
    assert_true(row != null, "The dialog has an Amount row")
    assert_true(dialog.row(&"hold") == null, "and no line under it saying it is held")
    host.free()
    photo.free()
