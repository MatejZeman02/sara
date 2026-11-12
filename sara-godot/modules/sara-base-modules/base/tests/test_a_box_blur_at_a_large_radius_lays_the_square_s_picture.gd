## Box Blur's three steps lay the square's picture at a small radius and a
## large one, at the document's edge and through a selection.
##
## The square is the formula Box Blur ran before its pass was cut in steps,
## every texel of the (2r + 1) square summed, in both the forms it shipped: the
## written kernel `old_blur.gmacs` and the pixel function
## `pixel_blur.gmacs`, both kept beside this suite. The picture is noise in
## colour and in alpha over the four chunks at the document's corner, so the
## reads cross chunk seams, clamp at the document's edge and premultiply
## wherever alpha varies.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const MODULE_DIR := "res://modules/sara-base-modules/base"
const SaExportScript = preload("res://core/export/sa_export.gd")
## Half precision's step at one. The three steps store their means twice
## between them where the square stored once, and a texel may part from the
## square's by no more than this.
const HALF_STEP := 1.0 / 1024.0
## The chunks the noise is painted in, at the document's corner.
const PAINTED: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
## The chunks read after a run: the painted ones and the ring a radius of 40
## spills into.
const READ: Array[Vector2i] = [
    Vector2i(0, 0),
    Vector2i(1, 0),
    Vector2i(2, 0),
    Vector2i(0, 1),
    Vector2i(1, 1),
    Vector2i(2, 1),
    Vector2i(0, 2),
    Vector2i(1, 2),
    Vector2i(2, 2),
]
## A selection whose edges cross the noise inside chunk (0, 0) and chunk (1, 1),
## so the work stops short of a chunk's sides.
const SELECTED := Rect2i(100, 60, 300, 250)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(1024, 1024))
    _doc = _easel.document
    _layer = _doc.active_layer
    ModuleLoader.module_dirs[&"sara-base-modules"] = MODULE_DIR
    _paint_noise()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


func test_at_radius_3_the_three_steps_lay_the_squares_picture() -> void:
    _compare(3, false)


func test_at_radius_40_the_three_steps_lay_the_squares_picture() -> void:
    _compare(40, false)


func test_through_a_selection_the_three_steps_lay_the_squares_picture() -> void:
    _doc.selection.select_rect(SELECTED)
    _compare(40, true)


## Box Blur at *radius*, then the written square and the pixel function at the
## same radius, each applied to the noise and undone, and every texel of the
## three read and held together.
func _compare(radius: int, selected: bool) -> void:
    var shipped: SaFilter = load(MODULE_DIR.path_join("usual/box_blur_filter.gd")).new()
    shipped.set_parameters({"radius": radius})
    var now := _applied(shipped, radius)
    var square := _applied(null, radius)
    var pixel := SaPixelFilter.new(MODULE_DIR.path_join("tests/pixel_blur.gmacs"), "Box Blur", 0, &"blur")
    pixel.set_parameters({"radius": radius})
    var pixel_laid := _applied(pixel, radius)
    var label := "radius %d%s" % [radius, " through a selection" if selected else ""]
    if now.size() != READ.size() or square.size() != READ.size() or pixel_laid.size() != READ.size():
        return
    var most := 0.0
    var most_pixel := 0.0
    var moved := 0.0
    for index in READ.size():
        most = maxf(most, _largest_difference(square[index], now[index]))
        most_pixel = maxf(most_pixel, _largest_difference(pixel_laid[index], now[index]))
        moved = maxf(moved, _largest_difference(_noise_of(READ[index]), now[index]))
    assert_true(moved > 0.05, "the blur changed the noise at %s, %s at most" % [label, moved])
    assert_true(most < HALF_STEP, "and laid the written square's picture at %s, %s apart at most" % [label, most])
    assert_true(most_pixel < HALF_STEP, "and the pixel function's, %s apart at most" % most_pixel)


## The texels of every chunk of READ, held or not, after *filter*, or the written square's
## kernel at *radius* when there is no filter, is applied to the noise, read
## before the run is undone. An empty list when the apply failed.
func _applied(filter: SaFilter, radius: int) -> Array[Image]:
    var out: Array[Image] = []
    var title := filter.title() if filter != null else "Old Box Blur"
    var ctx := SaFilterContext.new(_doc, _layer, &"sara-base-modules", title)
    if filter != null:
        filter.run(ctx)
    else:
        ctx.neighbourhood_pass("old_blur", "blur", {"radius": radius}, radius)
    if not SaFilterApply.apply(ctx, title):
        assert_true(false, "%s applied" % title)
        return out
    for grid: Vector2i in READ:
        # A chunk the run never wrote, the ring past a selection, is read as the
        # transparent picture it holds.
        var field := _layer.get_field(grid)
        out.append(_noise_of(Vector2i(-1, -1)) if field == null else SaExportScript.get_texture_image_float(field))
    assert_true(_doc.undo(), "%s undoes" % title)
    return out


## Noise in colour and alpha, the same every run, over the PAINTED chunks.
func _paint_noise() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    for grid: Vector2i in PAINTED:
        var chunk := _layer.get_or_create_chunk(grid)
        rd.texture_update(chunk.field(SaFieldSpec.ALBEDO).rid, 0, _noise_of(grid).get_data())


## The noise of chunk *grid*, transparent outside PAINTED. Values above one are
## among it, since nothing clamps.
func _noise_of(grid: Vector2i) -> Image:
    var image := Image.create(SaChunk.SIZE, SaChunk.SIZE, false, Image.FORMAT_RGBAF)
    image.fill(Color(0.0, 0.0, 0.0, 0.0))
    if grid not in PAINTED:
        return image
    var random := RandomNumberGenerator.new()
    random.seed = 737 + grid.x * 31 + grid.y * 977
    for y in SaChunk.SIZE:
        for x in SaChunk.SIZE:
            image.set_pixel(x, y, Color(random.randf() * 1.5, random.randf(), random.randf(), random.randf()))
    return image


## The largest difference of any channel of any texel between *a* and *b*.
static func _largest_difference(a: Image, b: Image) -> float:
    var most := 0.0
    for y in a.get_height():
        for x in a.get_width():
            var p := a.get_pixel(x, y)
            var q := b.get_pixel(x, y)
            most = maxf(most, maxf(maxf(absf(p.r - q.r), absf(p.g - q.g)), maxf(absf(p.b - q.b), absf(p.a - q.a))))
    return most
