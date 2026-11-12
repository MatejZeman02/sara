## The canvas view dithers by half a level so a soft edge on mid
## grey shows no step. The default background is 0.5, which an eight-bit screen
## shows at 127.5 of 255, so the faintest paint over it rounds a texel to the
## other step: a wide Gaussian showed its square support as a rounded square
## one level off the grey, however low the bell stood at its edge.
##
## A field of that grey with black at an alpha of 1e-6 over its right half is
## drawn through the canvas's own material the way a painter sees it, and again
## with the material's `display_dither` off, which rounds to the nearest step
## with nothing added. Then it is exported to an eight-bit PNG and to a 32-bit
## float TIFF, which the row leaves as they were: an export dithers only when the
## painter asks for it, which a separate option does, so the PNG keeps the nearest step at every
## texel. The scenario named after this suite is a wide blur read the same three
## ways.
##
## Not through no material at all for the read without the dither, the frame
## before the dither. This machine's SubViewport rounds 127.53 down, so the grey and the
## faint half both drew 127 there, and the read said nothing about the dither.
extends "res://tests/test_framework.gd"

## The field is composited, drawn and exported on a real device.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Each half four of the dither's eight-pixel tiles across and two down, so a
## half's mean holds every threshold alike.
const FIELD := Vector2i(64, 16)
const HALF := 32

## The alpha of the black laid over the right half.
const FAINT := 1e-6

## How far apart the halves' means may read with the dither.
const QUARTER_LEVEL := 0.25

## Numbers already on an eight-bit step, which the dither may not move.
const ON_A_STEP: Array[int] = [0, 1, 51, 127, 128, 200, 254, 255]

var _registries: SaRegistries = null
var _easels: Array[SaEasel] = []
var _canvases: Array[SaCanvas] = []
var _scratch_png := SaDataRoot.path("d15-field.png")
var _scratch_tiff := SaDataRoot.path("d15-field.tif")
var _saved_tonemap := false


func before_each() -> void:
    _saved_tonemap = SaSettings.tonemap_highlights
    SaSettings.tonemap_highlights = false
    _registries = Fixtures.make_picture_registries()


func after_each() -> void:
    for canvas: SaCanvas in _canvases:
        canvas.free()
    _canvases.clear()
    for easel: SaEasel in _easels:
        easel.free()
    _easels.clear()
    _registries = null
    SaSettings.tonemap_highlights = _saved_tonemap
    for path: String in [_scratch_png, _scratch_tiff]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## An sRGB document on its default grey with *image* put down over it the way an
## import puts a picture down, composited.
func _easel(image: Image) -> SaEasel:
    var space := SaColorSpace.srgb()
    var easel := SaEasel.create_default(image.get_size(), null, space)
    easel.compositor.set_registry(_registries.blend_modes)
    _easels.append(easel)
    var layer := SaImageImport.place(easel.document, image, "d15", space, SaImageImport.Fit.ORIGIN)
    assert_not_null(layer, "The picture is put down as a layer")
    easel.request_full_composite()
    easel.process_pending_composite()
    return easel


## The grey with black at an alpha of FAINT over its right half.
func _faint_half_easel() -> SaEasel:
    var image := Image.create_empty(FIELD.x, FIELD.y, false, Image.FORMAT_RGBAF)
    image.fill_rect(Rect2i(HALF, 0, FIELD.x - HALF, FIELD.y), Color(0.0, 0.0, 0.0, FAINT))
    return _easel(image)


func _canvas(easel: SaEasel) -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = easel.document.canvas_size
    canvas.easel = easel
    canvas.sync_tonemap()
    _canvases.append(canvas)
    return canvas


## *easel*'s output drawn one texel a pixel into an eight-bit viewport and read
## back through *material*.
func _frame(easel: SaEasel, material: Material) -> Image:
    var size := easel.document.canvas_size
    var viewport := SubViewport.new()
    viewport.size = size
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    EventBus.add_child(viewport)
    var output := Texture2DRD.new()
    output.texture_rd_rid = easel.output.rid
    var item := RenderingServer.canvas_item_create()
    RenderingServer.canvas_item_set_parent(item, viewport.find_world_2d().canvas)
    RenderingServer.canvas_item_set_material(item, material.get_rid())
    RenderingServer.canvas_item_set_default_texture_filter(item, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
    RenderingServer.canvas_item_add_texture_rect(item, Rect2(Vector2.ZERO, Vector2(size)), output.get_rid())
    RenderingServer.force_draw(false, 0.0)
    var image := viewport.get_texture().get_image()
    RenderingServer.free_rid(item)
    viewport.free()
    return image


## The field as the painter sees it, through the canvas's own material, or
## with its dither off when *dithered* is false.
func _view(easel: SaEasel, dithered: bool = true) -> Image:
    var material := _canvas(easel).material as ShaderMaterial
    material.set_shader_parameter("display_dither", dithered)
    return _frame(easel, material)


## The mean display value of each half of *image*, red, green and blue alike.
static func _half_means(image: Image) -> Vector2:
    var sums := Vector2.ZERO
    for y in image.get_height():
        for x in image.get_width():
            var c := image.get_pixel(x, y)
            var level := float(c.r8 + c.g8 + c.b8) / 3.0
            if x < HALF:
                sums.x += level
            else:
                sums.y += level
    return sums / float(HALF * image.get_height())


## Every channel of every pixel of *image* that is not *low* or *low* + 1.
static func _off_the_two_steps(image: Image, low: int) -> int:
    var off := 0
    for y in image.get_height():
        for x in image.get_width():
            var c := image.get_pixel(x, y)
            for level: int in [c.r8, c.g8, c.b8]:
                if level != low and level != low + 1:
                    off += 1
    return off


## Whether every channel of *c* is the byte *level*.
static func _is_grey(c: Color, level: int) -> bool:
    return c.r8 == level and c.g8 == level and c.b8 == level


## The written PNG at *path*, or null.
static func _written(path: String) -> Image:
    return Image.load_from_file(ProjectSettings.globalize_path(path))


func test_the_faint_half_is_stored_under_the_grey() -> void:
    var easel := _faint_half_easel()
    var stored := SaExport.get_texture_image_float(easel.output)
    var grey := stored.get_pixel(0, 0).g
    var faint := stored.get_pixel(FIELD.x - 1, 0).g
    assert_eq(grey, 0.5, "The left half holds the default grey, 127.5 of 255")
    assert_true(faint < 0.5 and faint > 0.5 - 1e-5, "and the right half a hair under it, %.9f, the premise" % faint)


func test_without_the_dither_the_halves_read_a_whole_level_apart() -> void:
    var easel := _faint_half_easel()
    var means := _half_means(_view(easel, false))
    assert_eq(means.x, 128.0, "Without the dither the grey rounds up to 128")
    assert_eq(means.y, 127.0, "and the faint half down to 127, a whole level apart, %s" % means)


func test_the_view_shows_the_halves_within_a_quarter_level() -> void:
    var easel := _faint_half_easel()
    var view := _view(easel)
    var means := _half_means(view)
    assert_true(absf(means.x - means.y) <= QUARTER_LEVEL, "The halves read %s through the view, within a quarter level" % means)
    assert_almost_eq(means.x, 127.5, QUARTER_LEVEL, "and the grey's mean is the 127.5 it stores, %s" % means)
    assert_eq(_off_the_two_steps(view, 127), 0, "and no pixel is further than the step either side")


func test_the_dither_is_fixed_per_pixel() -> void:
    var easel := _faint_half_easel()
    var first := _view(easel)
    var second := _view(easel)
    assert_eq(first.get_data(), second.get_data(), "Two frames of a still canvas are the same bytes, so nothing crawls")


func test_a_number_on_a_step_is_drawn_and_written_as_that_step() -> void:
    var image := Image.create_empty(ON_A_STEP.size(), 8, false, Image.FORMAT_RGBAF)
    for i in ON_A_STEP.size():
        var level := float(ON_A_STEP[i]) / 255.0
        image.fill_rect(Rect2i(i, 0, 1, 8), Color(level, level, level, 1.0))
    var easel := _easel(image)
    var view := _view(easel)
    assert_eq(SaExport.export_png(easel, _scratch_png), OK, "The steps export as PNG")
    var written := _written(_scratch_png)
    assert_not_null(written, "and the file reads back")
    if written == null:
        return
    for i in ON_A_STEP.size():
        for y in 8:
            var want := ON_A_STEP[i]
            assert_true(_is_grey(view.get_pixel(i, y), want), "%d at row %d is drawn as itself" % [want, y])
            assert_true(_is_grey(written.get_pixel(i, y), want), "%d at row %d is written as itself" % [want, y])


func test_an_eight_bit_png_export_keeps_the_nearest_step() -> void:
    var easel := _faint_half_easel()
    assert_eq(SaExport.export_png(easel, _scratch_png), OK, "The field exports as an eight-bit PNG")
    var written := _written(_scratch_png)
    assert_not_null(written, "and the file reads back")
    if written == null:
        return
    var stray := 0
    for y in FIELD.y:
        for x in FIELD.x:
            if not _is_grey(written.get_pixel(x, y), 128 if x < HALF else 127):
                stray += 1
    assert_eq(stray, 0, "The grey is written 128 and the faint half 127 at every texel, the export's rounding as it was")
    var view := _view(easel)
    var differ := 0
    for y in FIELD.y:
        for x in FIELD.x:
            if not _is_grey(view.get_pixel(x, y), written.get_pixel(x, y).r8):
                differ += 1
    assert_true(differ > 0, "and the view's dither reached none of it, the view drawing %d of its pixels otherwise" % differ)


func test_a_32_bit_float_tiff_holds_the_stored_numbers_to_the_bit() -> void:
    var easel := _faint_half_easel()
    var stored := SaExport.get_texture_image_float(easel.output)
    assert_eq(Fixtures.export_through(&"tiff", easel, _scratch_tiff, 32), OK, "The field exports as a 32-bit float TIFF")
    var written := SaImageImport.read(_scratch_tiff)
    assert_not_null(written, "and the file reads back")
    if written == null:
        return
    var differ := 0
    for y in FIELD.y:
        for x in FIELD.x:
            if written.get_pixel(x, y) != stored.get_pixel(x, y):
                differ += 1
    assert_eq(differ, 0, "Every texel of the file is the stored float, the faint half's included, so no dither reached it")
