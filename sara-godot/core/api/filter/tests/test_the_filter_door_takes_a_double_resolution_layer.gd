## A filter run on a layer at twice
## the document's resolution reads and writes the layer at its own density, and
## its preview shows what it will write.
##
## Each case runs one filter twice, on a layer at 1.0 and on a layer at 2.0
## holding the same picture, each in an easel of its own, through the dialog's
## Apply (`SaFilterOps.one_shot`), and finds the two equal at the document's
## resolution: the 2.0 layer's two by two texels averaged, premultiplied, which
## is the mean the compositor composites it by zoomed out, to within the rounding of that
## mean. The invert is the point fixture, the blur is the box blur.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const InvertFilter = preload("res://tests/fixtures/modules/point-fixture/invert_filter.gd")
const BoxBlurFilter = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")

const REQUIRES_GPU := true

## Two chunks side by side, so every run crosses a seam.
const CANVAS := Vector2i(512, 256)
## The rounding of a two by two mean of half floats, with room to spare.
const ROUNDING := 0.004
## The blur's radius, in document pixels, as the painter sets it.
const RADIUS := 4
## A selection over the seam, its edges on no chunk boundary.
const SELECTED := Rect2i(37, 41, 402, 150)

var _easel: SaEasel = null


func after_each() -> void:
    _close()


func _close() -> void:
    if _easel != null:
        _easel.free()
    _easel = null


## Blocks of eight pixels in colours that differ, for the invert, whose every
## texel reads only itself.
static func _blocks(x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var block := Vector2i(x / 8, y / 8)
    return Color(0.2 * (block.x % 5), 0.3 * (block.y % 3), 0.5, 0.5 + 0.1 * (block.x % 4))


## A ramp across and down, opaque, for the blur. A box blur of a ramp is the
## ramp, and of the ramp's nearest upscale it is the ramp again once two by two
## texels are averaged, so the two runs agree to the rounding wherever the blur
## reads no edge of the canvas.
static func _ramp(x: int, y: int) -> Color:
    return Color(float(x) / CANVAS.x, float(y) / CANVAS.y, 0.25 + 0.5 * float(x + y) / (CANVAS.x + CANVAS.y), 1.0)


## An opaque square on transparency, whose blurred edge says how far the blur
## reached.
static func _square(x: int, y: int) -> Color:
    if x >= 200 and x < 330 and y >= 60 and y < 190:
        return Color(0.9, 0.3, 0.1, 1.0)
    return Color(0.0, 0.0, 0.0, 0.0)


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## A fresh easel with *picture* on a new active layer at *scale*, the double
## resolution one written texel for texel as its nearest upscale.
func _open(scale: float, picture: Callable) -> SaLayer:
    _close()
    _easel = Bench.easel(CANVAS)
    var doc := _easel.document
    var layer := SaLayerOps.new(doc).add(&"", null, scale)
    doc.active_layer = layer
    for gx in range(0, CANVAS.x, SaChunk.SIZE).size():
        var grid_pos := Vector2i(gx, 0)
        var chunk := layer.get_or_create_chunk(grid_pos)
        var texture := chunk.albedo()
        var image := Image.create_empty(SaChunk.SIZE, SaChunk.SIZE, false, _image_format(texture))
        for y in SaChunk.SIZE:
            for x in SaChunk.SIZE:
                image.set_pixel(x, y, picture.call(gx * SaChunk.SIZE + x, y))
        if chunk.pixel_size() != SaChunk.SIZE:
            image.resize(chunk.pixel_size(), chunk.pixel_size(), Image.INTERPOLATE_NEAREST)
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
        layer.mark_unresolved(grid_pos)
    doc.invalidate_chunks(layer.chunks.keys())
    return layer


## The chunk at *grid_pos* of *layer* as an image of its own texels.
static func _texels(layer: SaLayer, grid_pos: Vector2i) -> Image:
    var chunk: SaChunk = layer.chunks.get(grid_pos, null)
    if chunk == null:
        return null
    var texture := chunk.albedo()
    var edge := chunk.pixel_size()
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return Image.create_from_data(edge, edge, false, _image_format(texture), bytes)


## *layer* at the document's resolution, premultiplied: each pixel the mean of
## the texels over it, which for a layer at 1.0 is the texel itself.
static func _seen(layer: SaLayer) -> Image:
    var seen := Image.create_empty(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBAF)
    for grid_pos: Vector2i in layer.chunks:
        var origin: Vector2i = grid_pos * SaChunk.SIZE
        if origin.x >= CANVAS.x or origin.y >= CANVAS.y or origin.x < 0 or origin.y < 0:
            continue
        var texels := _texels(layer, grid_pos)
        @warning_ignore("integer_division")
        var t := texels.get_width() / SaChunk.SIZE
        for y in SaChunk.SIZE:
            for x in SaChunk.SIZE:
                var sum := Color(0.0, 0.0, 0.0, 0.0)
                for dy in t:
                    for dx in t:
                        var texel := texels.get_pixel(x * t + dx, y * t + dy)
                        sum += Color(texel.r * texel.a, texel.g * texel.a, texel.b * texel.a, texel.a)
                seen.set_pixel(origin.x + x, origin.y + y, sum / float(t * t))
    return seen


## The pixel inside *within* where *a* and *b* differ most, and by how much,
## as `[difference, pixel]`.
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


## A context over *layer* for *filter* of the module *owner*, run once the way
## the dialog runs it on open.
func _run(layer: SaLayer, filter: SaFilter, owner: StringName) -> SaFilterContext:
    var ctx := SaFilterContext.new(_easel.document, layer, owner, filter.title(), true)
    assert_true(SaFilterApply.call_run(filter, ctx), "%s runs clean" % filter.title())
    return ctx


func _invert() -> SaFilter:
    return InvertFilter.new()


func _blur() -> SaFilter:
    ModuleLoader.module_dirs[&"sara-base-modules"] = "res://modules/sara-base-modules/base"
    var blur := BoxBlurFilter.new()
    blur.write_parameter(&"radius", RADIUS)
    return blur


## Runs *filter* over *picture* at 1.0 and at 2.0 through the dialog's Apply,
## under *selected* when it is not empty, and answers `[plain, double]` as the
## document shows them. Each run is one step, and its undo gives back the
## picture as it was.
func _both(picture: Callable, make: Callable, owner: StringName, selected: Rect2i) -> Array:
    var answers: Array = []
    for scale: float in [1.0, 2.0]:
        var layer := _open(scale, picture)
        var doc := _easel.document
        if selected.has_area():
            doc.selection.select_rect(selected)
        var before := _seen(layer)
        var filter: SaFilter = make.call()
        var ctx := _run(layer, filter, owner)
        assert_eq(ctx.scale, scale, "The context carries the layer's scale")
        var steps := doc.history.step_count()
        assert_true(SaFilterOps.one_shot(ctx, filter), "Apply writes at %.1f" % scale)
        assert_eq(doc.history.step_count(), steps + 1, "as one step at %.1f" % scale)
        for chunk: SaChunk in layer.chunks.values():
            assert_eq(chunk.resolution_scale, scale, "and every chunk it wrote is at the layer's scale")
        answers.append(_seen(layer))
        assert_true(doc.undo(), "which undoes at %.1f" % scale)
        var undone := _worst(before, _seen(layer), Rect2i(Vector2i.ZERO, CANVAS))
        assert_true(float(undone[0]) <= 1e-6, "One undo takes it back at %.1f, worst %.5f at %s" % [scale, undone[0], undone[1]])
    return answers


func _assert_same(answers: Array, within: Rect2i, what: String) -> void:
    var worst := _worst(answers[0] as Image, answers[1] as Image, within)
    assert_true(
        float(worst[0]) <= ROUNDING,
        "%s: the double resolution layer shows what the plain one does, worst %.4f at %s" % [what, worst[0], worst[1]]
    )


## The canvas less the blur's reach from its edge, where the padding reads the
## nearest texel inside and a ramp stops being a ramp.
static func _inside() -> Rect2i:
    return Rect2i(Vector2i(RADIUS + 1, RADIUS + 1), CANVAS - Vector2i(RADIUS + 1, RADIUS + 1) * 2)


func test_an_invert_writes_the_same_picture_at_both_densities() -> void:
    _assert_same(_both(_blocks, _invert, Bench.OWNER, Rect2i()), Rect2i(Vector2i.ZERO, CANVAS), "The invert")


func test_an_invert_under_a_selection() -> void:
    _assert_same(_both(_blocks, _invert, Bench.OWNER, SELECTED), Rect2i(Vector2i.ZERO, CANVAS), "The invert, selected")


func test_a_box_blur_writes_the_same_picture_at_both_densities() -> void:
    _assert_same(_both(_ramp, _blur, &"sara-base-modules", Rect2i()), _inside(), "The box blur")


func test_a_box_blur_under_a_selection() -> void:
    _assert_same(_both(_ramp, _blur, &"sara-base-modules", SELECTED), _inside(), "The box blur, selected")


## The first pixel of row *y* from the left whose alpha is above zero.
static func _first_painted(seen: Image, y: int) -> int:
    for x in CANVAS.x:
        if seen.get_pixel(x, y).a > 1e-4:
            return x
    return -1


func test_the_blur_reaches_as_far_in_document_pixels() -> void:
    var answers := _both(_square, _blur, &"sara-base-modules", Rect2i())
    var plain := _first_painted(answers[0] as Image, 120)
    var double := _first_painted(answers[1] as Image, 120)
    assert_eq(plain, 200 - RADIUS, "The plain blur reaches its radius past the square")
    assert_eq(double, plain, "and the double resolution one reaches as far on the canvas, not half as far")


## The texels *layer* holds over *rect* at its own density, as one image.
static func _written(layer: SaLayer, rect: Rect2i) -> Image:
    var side := SaFilterDensity.side_of(layer)
    var size := SaFilterDensity.texels(rect, side)
    var out := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBAF)
    for grid_pos: Vector2i in SaChunkWalk.positions_in(rect):
        var texels := _texels(layer, grid_pos)
        if texels == null:
            continue
        texels.convert(Image.FORMAT_RGBAF)
        var placed := SaFilterDensity.place(grid_pos, rect, side)
        var local: Rect2i = placed[0]
        if local.has_area():
            out.blit_rect(texels, local, (placed[1] as Rect2i).position)
    return out


static func _picture_image(picture: SaTexture) -> Image:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(picture.rid, 0)
    var image := Image.create_from_data(picture.size.x, picture.size.y, false, _image_format(picture), bytes)
    image.convert(Image.FORMAT_RGBAF)
    return image


## The browser's picture of a run on a layer at 2.0 against what Apply then
## writes there, texel for texel.
func _assert_preview_is_written(picture: Callable, make: Callable, owner: StringName, selected: Rect2i) -> void:
    var layer := _open(2.0, picture)
    var doc := _easel.document
    if selected.has_area():
        doc.selection.select_rect(selected)
    var filter: SaFilter = make.call()
    var ctx := _run(layer, filter, owner)
    var shown := SaFilterBrowser.picture_of(ctx)
    assert_not_null(shown, "The browser has a picture of %s" % filter.title())
    if shown == null:
        return
    assert_eq(shown.size, ctx.rect.size * 2, "at the layer's density, twice the run's rectangle")
    var previewed := _picture_image(shown)
    assert_true(SaFilterOps.one_shot(ctx, filter), "and Apply writes")
    var written := _written(layer, ctx.rect)
    var worst := 0.0
    var at := Vector2i(-1, -1)
    for y in previewed.get_height():
        for x in previewed.get_width():
            var p := previewed.get_pixel(x, y)
            var q := written.get_pixel(x, y)
            var d := maxf(maxf(absf(p.r - q.r), absf(p.g - q.g)), maxf(absf(p.b - q.b), absf(p.a - q.a)))
            if d > worst:
                worst = d
                at = Vector2i(x, y)
    assert_true(worst <= 1e-3, "%s: the preview is the texture Apply writes, worst %.5f at %s" % [filter.title(), worst, at])


func test_the_browsers_preview_of_the_invert_is_what_apply_writes() -> void:
    _assert_preview_is_written(_blocks, _invert, Bench.OWNER, Rect2i())
    _assert_preview_is_written(_blocks, _invert, Bench.OWNER, SELECTED)


func test_the_browsers_preview_of_the_blur_is_what_apply_writes() -> void:
    _assert_preview_is_written(_ramp, _blur, &"sara-base-modules", Rect2i())
    _assert_preview_is_written(_ramp, _blur, &"sara-base-modules", SELECTED)


func test_a_texture_shown_by_the_run_is_at_the_layers_density() -> void:
    var layer := _open(2.0, _blocks)
    var ctx := SaFilterContext.new(_easel.document, layer, Bench.OWNER, "Copy", true)
    var pixels := ctx.layer_pixels()
    assert_eq(pixels.size, ctx.rect.size * 2, "layer_pixels hands the layer's texels, twice the rectangle")
    var handed := _picture_image(pixels)
    var held := _written(layer, ctx.rect)
    assert_eq(handed.get_pixel(301, 77), held.get_pixel(301, 77), "texel for texel")
    ctx.show(pixels)
    assert_true(SaFilterApply.apply(ctx, "Copy"), "and a texture shown at that density applies")
    var after := _written(layer, ctx.rect)
    assert_eq(after.get_pixel(301, 77), held.get_pixel(301, 77), "back where it was read from")
