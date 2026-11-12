## A filter attached to a layer at
## twice the document's resolution is evaluated at the layer's own density, as
## the one-shot from the Filter menu is, and the dialog's preview on the canvas
## under a selection reads the selection by the pixel on such a layer.
##
## Each case attaches one filter to a layer at 1.0 and to a layer at 2.0 holding
## the same picture, the second written as the first's nearest upscale, each in
## an easel of its own, and finds the two canvases equal within the rounding of
## a two by two mean. A flatten of the record is then held against the one-shot
## on the same layer, and the canvas preview against what Apply writes.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const InvertFilter = preload("res://tests/fixtures/modules/point-fixture/invert_filter.gd")
const BoxBlurFilter = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")
const WholeShiftFilter = preload("res://tests/fixtures/modules/whole-fixture/whole_shift_filter.gd")

const REQUIRES_GPU := true

## Two chunks side by side, so every blur crosses a seam.
const CANVAS := Vector2i(512, 256)
## The rounding of a two by two mean of half floats, with room to spare.
const ROUNDING := 0.004
## The blur's radius, in document pixels, as the painter sets it.
const RADIUS := 4
const BLUR_OWNER: StringName = &"sara-base-modules"
const WHOLE_OWNER: StringName = &"whole-fixture"
const WHOLE_KEY: StringName = &"whole-fixture.whole_fixture_shift"
## A selection over the seam, its edges on no chunk boundary and on odd pixels,
## so a mask read at the texel and not the pixel shows.
const SELECTED := Rect2i(37, 41, 403, 151)

var _easel: SaEasel = null


func after_each() -> void:
    _close()


func _close() -> void:
    if _easel != null:
        _easel.free()
    _easel = null


## Blocks of eight pixels in colours that differ, for the invert.
static func _blocks(x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var block := Vector2i(x / 8, y / 8)
    return Color(0.2 * (block.x % 5), 0.3 * (block.y % 3), 0.5, 0.5 + 0.1 * (block.x % 4))


## An opaque ramp across and down, for the blur: a box blur of a ramp is the
## ramp, and of its nearest upscale the ramp again once two by two texels are
## averaged, wherever the blur reads no edge of the canvas.
static func _ramp(x: int, y: int) -> Color:
    return Color(float(x) / CANVAS.x, float(y) / CANVAS.y, 0.25 + 0.5 * float(x + y) / (CANVAS.x + CANVAS.y), 1.0)


static func _image_format(format: int) -> Image.Format:
    return Image.FORMAT_RGBAH if format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## A fresh easel whose chain answers the invert, the box blur and the whole-node
## shift, with *picture* on a new active layer at *scale*.
func _open(scale: float, picture: Callable) -> SaLayer:
    _close()
    ModuleLoader.module_dirs[BLUR_OWNER] = "res://modules/sara-base-modules/base"
    _easel = Bench.easel(CANVAS)
    var registry := _easel.compositor.filter_chain.registry
    registry.register(_blur(), BLUR_OWNER)
    registry.register(WholeShiftFilter.new(), WHOLE_OWNER)
    var doc := _easel.document
    var layer := SaLayerOps.new(doc).add(&"", null, scale)
    doc.active_layer = layer
    for gx in range(0, CANVAS.x, SaChunk.SIZE).size():
        var grid_pos := Vector2i(gx, 0)
        var chunk := layer.get_or_create_chunk(grid_pos)
        var texture := chunk.albedo()
        var image := Image.create_empty(SaChunk.SIZE, SaChunk.SIZE, false, _image_format(texture.format))
        for y in SaChunk.SIZE:
            for x in SaChunk.SIZE:
                image.set_pixel(x, y, picture.call(gx * SaChunk.SIZE + x, y))
        if chunk.pixel_size() != SaChunk.SIZE:
            image.resize(chunk.pixel_size(), chunk.pixel_size(), Image.INTERPOLATE_NEAREST)
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
        layer.mark_unresolved(grid_pos)
    doc.invalidate_chunks(layer.chunks.keys())
    return layer


func _blur() -> SaFilter:
    var blur := BoxBlurFilter.new()
    blur.write_parameter(&"radius", RADIUS)
    return blur


func _blur_key() -> StringName:
    return SaFilterRegistry.key_for(BLUR_OWNER, _blur())


## The values a record of *key* is attached with: the blur's radius as the
## one-shot sets it, and nothing for the invert.
func _values_of(key: StringName) -> Dictionary:
    return _blur().parameters() if key == _blur_key() else {}


## The canvas as the easel last composited it.
func _canvas() -> Image:
    Bench.composite(_easel)
    var output := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(output.rid, 0)
    var image := Image.create_from_data(output.size.x, output.size.y, false, _image_format(output.format), bytes)
    image.convert(Image.FORMAT_RGBAF)
    return image


## *layer* at the document's resolution, premultiplied: each pixel the mean of
## the texels over it.
static func _seen(layer: SaLayer) -> Image:
    var seen := Image.create_empty(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBAF)
    for grid_pos: Vector2i in layer.chunks:
        var origin: Vector2i = grid_pos * SaChunk.SIZE
        if origin.x >= CANVAS.x or origin.y >= CANVAS.y or origin.x < 0 or origin.y < 0:
            continue
        var chunk: SaChunk = layer.chunks[grid_pos]
        var edge := chunk.pixel_size()
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(chunk.albedo().rid, 0)
        var texels := Image.create_from_data(edge, edge, false, _image_format(chunk.albedo().format), bytes)
        @warning_ignore("integer_division")
        var t := edge / SaChunk.SIZE
        for y in SaChunk.SIZE:
            for x in SaChunk.SIZE:
                var sum := Color(0.0, 0.0, 0.0, 0.0)
                for dy in t:
                    for dx in t:
                        var texel := texels.get_pixel(x * t + dx, y * t + dy)
                        sum += Color(texel.r * texel.a, texel.g * texel.a, texel.b * texel.a, texel.a)
                seen.set_pixel(origin.x + x, origin.y + y, sum / float(t * t))
    return seen


## The pixel inside *within* where *a* and *b* differ most, and by how much, as
## `[difference, pixel]`.
static func _worst(a: Image, b: Image, within: Rect2i) -> Array:
    var worst := 0.0
    var at := Vector2i(-1, -1)
    for y in range(within.position.y, within.end.y):
        for x in range(within.position.x, within.end.x):
            var p := a.get_pixel(x, y)
            var q := b.get_pixel(x, y)
            var d := maxf(maxf(absf(p.r - q.r), absf(p.g - q.g)), maxf(absf(p.b - q.b), absf(p.a - q.a)))
            if d > worst:
                worst = d
                at = Vector2i(x, y)
    return [worst, at]


func _assert_near(a: Image, b: Image, within: Rect2i, limit: float, what: String) -> void:
    var worst := _worst(a, b, within)
    assert_true(float(worst[0]) <= limit, "%s, worst %.5f at %s" % [what, worst[0], worst[1]])


## The canvas less the blur's reach from its edge, where the padding reads the
## nearest texel inside and a ramp stops being a ramp.
static func _inside() -> Rect2i:
    return Rect2i(Vector2i(RADIUS + 1, RADIUS + 1), CANVAS - Vector2i(RADIUS + 1, RADIUS + 1) * 2)


## The canvas with the filter under *key* attached to a layer of *picture*, at
## 1.0 and at 2.0, as `[plain, double]`.
func _attached_canvases(picture: Callable, key: Callable) -> Array:
    var answers: Array = []
    for scale: float in [1.0, 2.0]:
        var layer := _open(scale, picture)
        var record := SaFilterOps.new(_easel.document).attach(layer, key.call(), _values_of(key.call()))
        assert_not_null(record, "The filter attaches at %.1f" % scale)
        answers.append(_canvas())
    return answers


func _invert_key() -> StringName:
    return Bench.INVERT


func test_an_attached_invert_shows_the_same_canvas_at_both_densities() -> void:
    var canvases := _attached_canvases(_blocks, _invert_key)
    _assert_near(canvases[0], canvases[1], Rect2i(Vector2i.ZERO, CANVAS), ROUNDING, "The attached invert")


func test_an_attached_box_blur_shows_the_same_canvas_at_both_densities() -> void:
    var canvases := _attached_canvases(_ramp, _blur_key)
    _assert_near(canvases[0], canvases[1], _inside(), ROUNDING, "The attached box blur")


## The blur of a double resolution layer reaches as far on the canvas as the
## plain one does, not half as far, which is the radius taken to the texels.
func test_the_attached_blur_reaches_as_far_in_document_pixels() -> void:
    var answers: Array = []
    for scale: float in [1.0, 2.0]:
        var layer := _open(scale, _ramp)
        for grid_pos: Vector2i in layer.chunks.keys():
            layer.set_chunk(grid_pos, null)
        var chunk := layer.get_or_create_chunk(Vector2i(1, 0))
        chunk.clear(Color(0.9, 0.3, 0.1, 1.0))
        _easel.document.invalidate_chunks([Vector2i(1, 0)])
        SaFilterOps.new(_easel.document).attach(layer, _blur_key(), _values_of(_blur_key()))
        answers.append(_canvas())
    var plain := _first_painted(answers[0] as Image, 120)
    assert_eq(plain, SaChunk.SIZE - RADIUS, "The plain blur carries the paint its radius past the chunk")
    assert_eq(_first_painted(answers[1] as Image, 120), plain, "and the double one as far, not half as far")


## The first pixel of row *y* from the left that differs from the background
## the canvas shows at its left edge.
static func _first_painted(seen: Image, y: int) -> int:
    var ground := seen.get_pixel(0, y)
    for x in CANVAS.x:
        if not seen.get_pixel(x, y).is_equal_approx(ground):
            return x
    return -1


## A flatten of the record against the one-shot of the same filter on the same
## picture at the same density, as the layer shows them.
func _flatten_against_one_shot(picture: Callable, key: StringName, make: Callable, owner: StringName, within: Rect2i) -> void:
    for scale: float in [1.0, 2.0]:
        var layer := _open(scale, picture)
        var doc := _easel.document
        var ops := SaFilterOps.new(doc)
        var record := ops.attach(layer, key, _values_of(key))
        assert_true(ops.flatten(layer, record), "The record flattens at %.1f" % scale)
        for chunk: SaChunk in layer.chunks.values():
            assert_eq(chunk.resolution_scale, scale, "into chunks at the layer's scale")
        var flattened := _seen(layer)
        layer = _open(scale, picture)
        var filter: SaFilter = make.call()
        var ctx := SaFilterContext.new(_easel.document, layer, owner, filter.title(), true)
        assert_true(SaFilterApply.call_run(filter, ctx), "%s runs clean" % filter.title())
        assert_true(SaFilterOps.one_shot(ctx, filter), "and Apply writes at %.1f" % scale)
        _assert_near(flattened, _seen(layer), within, 1e-3, "%s flattened is its one-shot at %.1f" % [filter.title(), scale])


func _invert() -> SaFilter:
    return InvertFilter.new()


func test_a_flattened_invert_is_the_one_shot() -> void:
    _flatten_against_one_shot(_blocks, Bench.INVERT, _invert, Bench.OWNER, Rect2i(Vector2i.ZERO, CANVAS))


func test_a_flattened_box_blur_is_the_one_shot() -> void:
    _flatten_against_one_shot(_ramp, _blur_key(), _blur, BLUR_OWNER, Rect2i(Vector2i.ZERO, CANVAS))


## The dialog's preview of *make* on the canvas over a layer at 2.0 under
## [const SELECTED], against the canvas after Apply writes the same run.
func _preview_against_apply(picture: Callable, make: Callable, owner: StringName, within: Rect2i) -> void:
    var layer := _open(2.0, picture)
    var doc := _easel.document
    doc.selection.select_rect(SELECTED)
    var filter: SaFilter = make.call()
    var ctx := SaFilterContext.new(doc, layer, owner, filter.title(), true)
    assert_true(SaFilterApply.call_run(filter, ctx), "%s runs clean" % filter.title())
    _easel.compositor.point_preview.set_pass(doc, ctx.point)
    doc.invalidate_chunks(layer.chunks.keys())
    var previewed := _canvas()
    _easel.compositor.point_preview.clear(doc)
    assert_true(SaFilterOps.one_shot(ctx, filter), "Apply writes")
    _assert_near(previewed, _canvas(), within, ROUNDING, "%s: the preview on the canvas is what Apply writes" % filter.title())


func test_the_canvas_preview_of_the_invert_reads_the_selection_by_the_pixel() -> void:
    _preview_against_apply(_blocks, _invert, Bench.OWNER, Rect2i(Vector2i.ZERO, CANVAS))


func test_the_canvas_preview_of_the_blur_reads_the_selection_by_the_pixel() -> void:
    _preview_against_apply(_ramp, _blur, BLUR_OWNER, Rect2i(Vector2i.ZERO, CANVAS))


func test_a_filter_attaches_to_a_double_resolution_layer() -> void:
    var layer := _open(2.0, _blocks)
    var before := SaProblems.pending_refusals.size()
    assert_not_null(SaFilterOps.new(_easel.document).attach(layer, Bench.INVERT), "The attach takes")
    assert_eq(SaProblems.pending_refusals.size(), before, "with no refusal")


func test_a_filter_that_reads_the_whole_layer_is_refused_there_with_a_line() -> void:
    var layer := _open(2.0, _blocks)
    var before := SaProblems.pending_refusals.size()
    var values := {"offset_x": 256.0, "offset_y": 0.0, "mode": 0, "reach": SaNeighbourhoodPass.WHOLE_NODE}
    assert_null(SaFilterOps.new(_easel.document).attach(layer, WHOLE_KEY, values), "The whole-node attach is refused")
    assert_true(layer.filters.is_empty(), "and nothing hangs on the layer")
    assert_eq(SaProblems.pending_refusals.size(), before + 1, "with a line the painter reads")
    var plain := _open(1.0, _blocks)
    assert_not_null(SaFilterOps.new(_easel.document).attach(plain, WHOLE_KEY, values), "while a plain layer takes it")
