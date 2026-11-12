## Everything that walks a layer's
## chunks over a rectangle places its texels by the document pixel on a double
## resolution layer, and a paste of a copy from one makes a double resolution
## layer.
##
## Each test runs one operation twice, on a layer at 1.0 and on a layer at 2.0
## holding the same picture, each in a document of its own, and finds the two
## equal at the document's resolution: the 2.0 layer's two by two texels
## averaged, which is the mean the compositor shows it by zoomed out, to
## within the rounding of that mean.
extends "res://tests/test_framework.gd"

## Chunks are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Two chunks side by side, so every rectangle below crosses a seam.
const CANVAS := Vector2i(512, 256)
## The rounding of a two by two mean of half floats, with room to spare.
const ROUNDING := 0.004

const RING := Color(0.1, 0.2, 0.9, 1.0)
const GREEN := Color(0.2, 0.8, 0.3, 1.0)

var _surface: SaSurface = null
var _machine: ToolMachine = null


func after_each() -> void:
    _close()


func _close() -> void:
    if _surface != null:
        Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


## The picture both layers hold, at a document pixel: a closed square ring for
## the bucket fill and the wand, and a patch of eight pixel blocks for the
## transform, on transparency.
static func _picture_at(x: int, y: int) -> Color:
    var ring := maxi(absi(x - 120), absi(y - 120))
    if ring >= 72 and ring < 80:
        return RING
    if x >= 300 and x < 460 and y >= 40 and y < 200:
        @warning_ignore("integer_division")
        var block := Vector2i(x / 8, y / 8)
        return Color(0.2 * (block.x % 5), 0.3 * (block.y % 3), 0.5, 1.0)
    return Color(0.0, 0.0, 0.0, 0.0)


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## A fresh document with the picture on a new active layer at *scale*, the
## double resolution one written texel for texel as its nearest upscale.
func _open(scale: float) -> SaLayer:
    _close()
    _surface = Fixtures.make_surface(CANVAS)
    _machine = Fixtures.make_bound_machine(_surface)
    var doc := _surface.get_document()
    var layer := SaLayerOps.new(doc).add(&"", null, scale)
    for gx in range(0, CANVAS.x, SaChunk.SIZE).size():
        var grid_pos := Vector2i(gx, 0)
        var chunk := layer.get_or_create_chunk(grid_pos)
        var texture := chunk.albedo()
        var image := Image.create_empty(SaChunk.SIZE, SaChunk.SIZE, false, _image_format(texture))
        for y in SaChunk.SIZE:
            for x in SaChunk.SIZE:
                image.set_pixel(x, y, _picture_at(gx * SaChunk.SIZE + x, y))
        if chunk.pixel_size() != SaChunk.SIZE:
            image.resize(chunk.pixel_size(), chunk.pixel_size(), Image.INTERPOLATE_NEAREST)
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
        layer.mark_unresolved(grid_pos)
    doc.invalidate_chunks(layer.chunks.keys())
    return layer


## *layer* at the document's resolution, premultiplied: each pixel the mean of
## the texels over it, which for a layer at 1.0 is the texel itself.
## Premultiplied because a colour under no alpha means nothing, and a kernel
## dispatched from a workgroup boundary leaves one there that another run,
## aligned on another boundary, does not.
func _seen(layer: SaLayer) -> Image:
    var seen := Image.create_empty(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBAF)
    for grid_pos: Vector2i in layer.chunks:
        var origin: Vector2i = grid_pos * SaChunk.SIZE
        if origin.x >= CANVAS.x or origin.y >= CANVAS.y or origin.x < 0 or origin.y < 0:
            continue
        var chunk: SaChunk = layer.chunks[grid_pos]
        var texture := chunk.albedo()
        var edge := chunk.pixel_size()
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var texels := Image.create_from_data(edge, edge, false, _image_format(texture), bytes)
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


## The selection's coverage over the canvas, one pixel a document pixel.
func _selected() -> Image:
    var mask := Image.create_empty(CANVAS.x, CANVAS.y, false, Image.FORMAT_RF)
    var selection := _surface.get_document().selection
    for grid_pos: Vector2i in selection.chunks:
        var texture: SaTexture = (selection.chunks[grid_pos] as SaChunk).field(SaSelection.FIELD)
        if texture == null or texture.size.x != SaChunk.SIZE:
            continue
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var coverage := Image.create_from_data(SaChunk.SIZE, SaChunk.SIZE, false, Image.FORMAT_RF, bytes)
        mask.blit_rect(coverage, Rect2i(0, 0, SaChunk.SIZE, SaChunk.SIZE), grid_pos * SaChunk.SIZE)
    return mask


## The pixel where *a* and *b* differ most, and by how much, as
## `[difference, pixel]`.
static func _worst(a: Image, b: Image) -> Array:
    var worst := 0.0
    var at := Vector2i(-1, -1)
    for y in CANVAS.y:
        for x in CANVAS.x:
            var p := a.get_pixel(x, y)
            var q := b.get_pixel(x, y)
            var d := maxf(maxf(absf(p.r - q.r), absf(p.g - q.g)), maxf(absf(p.b - q.b), absf(p.a - q.a)))
            if d > worst:
                worst = d
                at = Vector2i(x, y)
    return [worst, at]


## Runs *operation* on the picture at 1.0 and at 2.0 and answers what each
## left, as `[plain, double]` of whatever *reading* takes from the layer.
func _both(operation: Callable, reading: Callable) -> Array:
    var answers: Array = []
    for scale: float in [1.0, 2.0]:
        var layer := _open(scale)
        operation.call(_surface.get_document(), layer)
        answers.append(reading.call(_surface.get_document(), layer))
    return answers


func _assert_same(answers: Array, what: String) -> void:
    var worst := _worst(answers[0] as Image, answers[1] as Image)
    assert_true(
        float(worst[0]) <= ROUNDING,
        "%s: the double resolution layer shows what the plain one does, worst %.4f at %s" % [what, worst[0], worst[1]]
    )


func _layer_seen(_doc: SaDocument, layer: SaLayer) -> Image:
    return _seen(layer)


func test_the_picture_itself_is_the_same_on_both() -> void:
    _assert_same(_both(func(_d: SaDocument, _l: SaLayer) -> void: pass, _layer_seen), "Before anything runs")


func test_a_fill_of_a_selection() -> void:
    var fill := func(doc: SaDocument, layer: SaLayer) -> void:
        doc.selection.select_rect(Rect2i(31, 57, 301, 97))
        layer.fill(GREEN)
    _assert_same(_both(fill, _layer_seen), "A fill of a selection over the seam")


func test_a_bucket_fill_of_a_closed_shape() -> void:
    var bucket := func(doc: SaDocument, layer: SaLayer) -> void:
        doc.active_layer = layer
        _machine.set_active_tool(&"bucket_fill")
        assert_true(int(_machine.active_tool.fill_at(Vector2i(120, 120))) > 0, "The bucket fills inside the ring")
    _assert_same(_both(bucket, _layer_seen), "A bucket fill inside the ring")


func test_a_gradient_over_a_selection() -> void:
    var ramp := SaColorRamp.from_pair(Color(1.0, 0.0, 0.0, 1.0), Color(0.0, 0.0, 1.0, 1.0))
    var gradient := func(doc: SaDocument, layer: SaLayer) -> void:
        doc.selection.select_rect(Rect2i(20, 30, 460, 180))
        var drawn := SaGradient.new(doc).apply(
            layer, Vector2(40.0, 60.0), Vector2(470.0, 190.0), ramp, SaGradient.Shape.LINEAR, SaGradient.Repeat.NONE, false
        )
        assert_true(drawn, "The gradient lands")
    _assert_same(_both(gradient, _layer_seen), "A linear gradient across the seam")


func test_a_conversion_of_the_documents_colour_space() -> void:
    var conversion := func(doc: SaDocument, _layer: SaLayer) -> void:
        assert_true(SaColorConversion.new(doc).convert_to(SaColorSpace.acescg()), "The conversion runs")
    _assert_same(_both(conversion, _layer_seen), "A conversion to ACEScg")


func test_a_cut_and_a_paste() -> void:
    var scales: Array = []
    # The clipboard the open documents share, which the app's `SaDocuments`
    # holds, made for this case.
    var clipboard := SaClipboard.new()
    var cut := func(doc: SaDocument, layer: SaLayer) -> void:
        doc.selection.select_rect(Rect2i(101, 33, 263, 121))
        assert_true(clipboard.cut(doc, layer), "The cut runs")
    var pasted := func(doc: SaDocument, layer: SaLayer) -> Array:
        var left := _seen(layer)
        var paste := clipboard.paste(doc)
        scales.append(paste.resolution_scale if paste != null else 0.0)
        return [left, _seen(paste) if paste != null else Image.create_empty(1, 1, false, Image.FORMAT_RGBAF)]
    var answers := _both(cut, pasted)
    _assert_same([answers[0][0], answers[1][0]], "What a cut leaves")
    _assert_same([answers[0][1], answers[1][1]], "What the paste puts down")
    assert_eq(scales, [1.0, 2.0], "and a paste of a copy from a double resolution layer is a double resolution layer")


func test_a_copy_takes_the_texels_under_the_selection() -> void:
    var clipboard := SaClipboard.new()
    var copy := func(doc: SaDocument, layer: SaLayer) -> void:
        doc.selection.select_rect(Rect2i(250, 70, 40, 30))
        assert_true(clipboard.copy(doc, layer) > 0, "The copy takes something")
    var copied := func(_doc: SaDocument, _layer: SaLayer) -> Image:
        var held := SaLayer.new()
        for grid_pos: Vector2i in clipboard.chunks:
            held.set_chunk(grid_pos, clipboard.chunks[grid_pos])
        var seen := _seen(held)
        held.chunks.clear()
        held.free()
        return seen
    _assert_same(_both(copy, copied), "What a copy holds")


func _transformed(to: Vector2i, scale: Vector2) -> Callable:
    return func(doc: SaDocument, layer: SaLayer) -> void:
        var box := Rect2i(300, 40, 160, 160)
        doc.selection.select_rect(box)
        var geometry := SaTransform.new(doc)
        geometry.filter = SaResampleKernel.Filter.NEAREST
        assert_true(geometry.lift(layer, box), "The transform lifts the blocks")
        geometry.preview_affine(to, scale, 0.0)
        geometry.tick()
        assert_true(geometry.commit(), "and puts them down moved")


func test_a_transform_that_moves_a_selection() -> void:
    _assert_same(_both(_transformed(Vector2i(-173, 29), Vector2.ONE), _layer_seen), "A move over the seam")


func test_a_transform_that_scales_a_selection() -> void:
    # Twice, nearest, about the box's whole pixel centre: each landed texel then
    # reads a texel of the source pixel the plain layer's landed pixel reads,
    # so the two agree exactly and the test sees the rectangles, not the filter.
    _assert_same(_both(_transformed(Vector2i(-150, 0), Vector2(2.0, 2.0)), _layer_seen), "A scale by two")


func test_the_wand_selects_the_same_region() -> void:
    var wand := func(doc: SaDocument, layer: SaLayer) -> void:
        var reached := SaWand.new().flood(doc, Vector2i(120, 120), 0.1, SaSelection.Mode.REPLACE, null, layer)
        assert_true(reached > 0, "The wand reaches something")
    var selected := func(_doc: SaDocument, _layer: SaLayer) -> Image: return _selected()
    _assert_same(_both(wand, selected), "The wand inside the ring")
