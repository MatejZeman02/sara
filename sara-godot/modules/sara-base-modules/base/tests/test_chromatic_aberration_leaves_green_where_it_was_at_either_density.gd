## Chromatic Aberration at 64 px on a document that is not square, on a layer at
## the document's density and on one at twice it: the green of every pixel is
## what it was, the red is read from the place pushed out from the document's
## centre and the blue from the place pushed in, by the amount's share at a
## corner and at a mid-edge, no painted pixel turns empty, and the dialog's
## preview on the canvas shows what the attached filter composites.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The case is a layer at twice the document's resolution. The neighbourhood
## pass hands a kernel the chunk's corner in the chunk's own texels, and the
## kernel must not take it for document pixels, or every chunk past the first
## thinks itself twice as far from the origin, and the shift grows past the
## halo towards the bottom and the right, where the reads leave the padded
## source. Each picture here is a ramp written at the place of
## every texel's centre in document pixels, so a channel's value says where it
## was read from, and the shift is measured rather than guessed.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## Real dispatches into real chunks.
const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
## Three chunks across and two down, a landscape and not a square.
const CANVAS := Vector2i(768, 512)
## The amount the dialog shows, in document pixels at a corner.
const AMOUNT := 64.0
## How far a measured shift may stray, in document pixels: a half float holds
## a ramp near one to about a third of a pixel of this canvas.
const NEAR := 0.75
## One level of an eight bit picture, the difference a painter could see.
const LEVEL := 1.0 / 255.0
## Where the shift is measured: near the top left corner, at the middle of the
## right edge and at the middle of the bottom edge. Each lies far enough inside
## that the red pushed out from it still reads inside the document, where the
## padding is a ramp and not its nearest texel.
const CORNER := Vector2i(100, 90)
const RIGHT := Vector2i(690, 256)
const BOTTOM := Vector2i(384, 440)

var _easel: SaEasel = null
var _key: StringName = &""


func after_each() -> void:
    _close()


func _close() -> void:
    if _easel != null:
        _easel.free()
    _easel = null


## A ramp across: red and blue read the document place's x, green a ramp on
## both axes, so a green read from anywhere else would show.
static func _across(place: Vector2) -> Color:
    return Color(place.x / CANVAS.x, _green(place), place.x / CANVAS.x, 1.0)


## The same ramp down.
static func _down(place: Vector2) -> Color:
    return Color(place.y / CANVAS.y, _green(place), place.y / CANVAS.y, 1.0)


static func _green(place: Vector2) -> float:
    return 0.25 + 0.5 * (place.x + place.y) / float(CANVAS.x + CANVAS.y)


static func _image_format(format: int) -> Image.Format:
    return Image.FORMAT_RGBAH if format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## A fresh easel with the filter registered and *picture* on a new active layer
## at *scale*, every texel holding the picture at its centre's document place.
func _open(scale: float, picture: Callable) -> SaLayer:
    _close()
    _easel = SaEasel.create_default(CANVAS)
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var registry := SaFilterRegistry.new()
    var filter := SaChromaticAberrationFilter.new()
    registry.register(filter, OWNER)
    _key = SaFilterRegistry.key_for(OWNER, filter)
    _easel.compositor.filter_chain.registry = registry
    var doc := _easel.document
    doc.color_space = SaColorSpace.linear_srgb()
    var layer := SaLayerOps.new(doc).add(&"", null, scale)
    doc.active_layer = layer
    @warning_ignore("integer_division")
    var grid := Vector2i(CANVAS.x / SaChunk.SIZE, CANVAS.y / SaChunk.SIZE)
    for gy in grid.y:
        for gx in grid.x:
            var grid_pos := Vector2i(gx, gy)
            var chunk := layer.get_or_create_chunk(grid_pos)
            var texture := chunk.albedo()
            var side := chunk.pixel_size()
            var density := float(side) / SaChunk.SIZE
            var image := Image.create_empty(side, side, false, _image_format(texture.format))
            for y in side:
                for x in side:
                    var place := Vector2(grid_pos * SaChunk.SIZE) + (Vector2(x, y) + Vector2(0.5, 0.5)) / density
                    image.set_pixel(x, y, picture.call(place))
            GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
            layer.mark_unresolved(grid_pos)
    doc.invalidate_chunks(layer.chunks.keys())
    return layer


## The canvas as the easel last composited it, at the document's resolution.
func _canvas() -> Image:
    Bench.composite(_easel)
    var output := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(output.rid, 0)
    var image := Image.create_from_data(output.size.x, output.size.y, false, _image_format(output.format), bytes)
    image.convert(Image.FORMAT_RGBAF)
    return image


## The canvas with the filter at [const AMOUNT] attached to a layer of
## *picture* at *scale*.
func _attached(scale: float, picture: Callable) -> Image:
    var layer := _open(scale, picture)
    var record := SaFilterOps.new(_easel.document).attach(layer, _key, {"amount": AMOUNT})
    assert_not_null(record, "The filter attaches at %.1f" % scale)
    return _canvas()


## The shift the kernel is asked for at the centre of *pixel*, in document
## pixels: the distance from the centre over the half diagonal, times the amount,
## along the line from the centre.
static func _expected(pixel: Vector2i) -> Vector2:
    var centre := Vector2(CANVAS) * 0.5
    return (Vector2(pixel) + Vector2(0.5, 0.5) - centre) / centre.length() * AMOUNT


## Every pixel's green against the picture's, and its alpha against one,
## as the first failure found or an empty string.
static func _green_and_alpha(seen: Image, picture: Callable) -> String:
    for y in CANVAS.y:
        for x in CANVAS.x:
            var pixel := seen.get_pixel(x, y)
            var was: Color = picture.call(Vector2(x, y) + Vector2(0.5, 0.5))
            if absf(pixel.g - was.g) > LEVEL:
                return "green at %s is %.4f where it was %.4f" % [Vector2i(x, y), pixel.g, was.g]
            if pixel.a < 1.0 - LEVEL:
                return "the pixel at %s has an alpha of %.4f" % [Vector2i(x, y), pixel.a]
    return ""


func _check_density(scale: float) -> void:
    var across := _attached(scale, _across)
    var down := _attached(scale, _down)
    for pair: Array in [[across, _across, "across"], [down, _down, "down"]]:
        var found := _green_and_alpha(pair[0] as Image, pair[1] as Callable)
        assert_eq(found, "", "At %.1f on the ramp %s every green is where it was and every pixel painted" % [scale, pair[2]])
    @warning_ignore("integer_division")
    for pixel: Vector2i in [CORNER, RIGHT, BOTTOM, CANVAS / 2]:
        var here := Vector2(pixel) + Vector2(0.5, 0.5)
        var wanted := _expected(pixel)
        var x_reads := across.get_pixel(pixel.x, pixel.y)
        var y_reads := down.get_pixel(pixel.x, pixel.y)
        var red := Vector2(x_reads.r * CANVAS.x, y_reads.r * CANVAS.y) - here
        var blue := Vector2(x_reads.b * CANVAS.x, y_reads.b * CANVAS.y) - here
        assert_true(
            red.distance_to(wanted) <= NEAR, "At %.1f the red at %s is read from %s away, out by %s" % [scale, pixel, red, wanted]
        )
        assert_true(blue.distance_to(-wanted) <= NEAR, "and the blue from %s away, in by %s" % [blue, -wanted])


func test_at_the_document_s_density_green_stays_and_red_and_blue_part_by_the_amount() -> void:
    _check_density(1.0)


func test_at_twice_the_document_s_density_green_stays_and_red_and_blue_part_by_the_amount() -> void:
    _check_density(2.0)


## The dialog's preview on the canvas against the attached record, on a layer
## at twice the document's resolution, which is where the two could part.
func test_the_preview_on_the_canvas_is_the_attached_filter_s_composite() -> void:
    for scale: float in [1.0, 2.0]:
        var layer := _open(scale, _across)
        var doc := _easel.document
        var filter := _easel.compositor.filter_chain.registry.get_filter(_key) as SaChromaticAberrationFilter
        filter.set_parameters({"amount": AMOUNT})
        var ctx := SaFilterContext.new(doc, layer, OWNER, filter.title(), true)
        assert_true(SaFilterApply.call_run(filter, ctx), "The filter runs clean at %.1f" % scale)
        _easel.compositor.point_preview.set_pass(doc, ctx.point)
        doc.invalidate_chunks(layer.chunks.keys())
        var previewed := _canvas()
        _easel.compositor.point_preview.clear(doc)
        SaFilterOps.new(doc).attach(layer, _key, {"amount": AMOUNT})
        var attached := _canvas()
        var worst := 0.0
        var at := Vector2i(-1, -1)
        for y in CANVAS.y:
            for x in CANVAS.x:
                var p := previewed.get_pixel(x, y)
                var q := attached.get_pixel(x, y)
                var d := maxf(maxf(absf(p.r - q.r), absf(p.g - q.g)), maxf(absf(p.b - q.b), absf(p.a - q.a)))
                if d > worst:
                    worst = d
                    at = Vector2i(x, y)
        var words := "At %.1f the preview is the attached composite within a level, worst %.5f at %s"
        assert_true(worst <= LEVEL, words % [scale, worst, at])
