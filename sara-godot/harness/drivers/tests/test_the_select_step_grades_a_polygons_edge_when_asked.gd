## The `select` step grades a polygon's and an ellipse's
## edge when it is given `"anti_alias": true`.
##
## A flat graphic illustration whose clouds and far island have no line round
## them has edges that are the selection's own. The step called
## `select_polygon` with no third argument, the mask came back wholly in or out
## at every pixel, and a probe's circle stepped a whole pixel at a time down its
## side. The mask has graded a lasso's edge for as long as the lasso has been
## anti-aliased, so the step now asks for it when told to, and keeps the hard edge every scenario before it was written for.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const CanvasDriver = preload("res://harness/drivers/sa_canvas_driver.gd")

var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


## A triangle whose long side falls one pixel in two, across a chunk seam, so
## every column the side crosses has a pixel only partly inside it.
static func _triangle() -> Array:
    return [[120.0, 20.0], [400.0, 20.0], [120.0, 160.0]]


## The pixel the long side crosses in column *x*: its centre lies a quarter of
## a pixel from the side, so graded it holds part of a pixel and hard it is
## wholly in or out.
static func _on_the_side(x: int) -> Vector2i:
    return Vector2i(x, floori(20.0 + (400.0 - (float(x) + 0.5)) * 0.5))


func test_a_polygon_asked_to_anti_alias_grades_its_edge() -> void:
    CanvasDriver.select_shapes(_doc.selection, {"polygon": _triangle(), "anti_alias": true}, SaSelection.Mode.REPLACE)
    var mask := _mask_of(_doc)
    var graded := 0
    for x in range(130, 390, 10):
        var cover := _at(mask, _on_the_side(x))
        if cover > 0.0 and cover < 1.0:
            graded += 1
    assert_eq(graded, 26, "Every column the side crosses holds part of a pixel")


func test_a_polygon_not_asked_keeps_the_hard_edge() -> void:
    CanvasDriver.select_shapes(_doc.selection, {"polygon": _triangle()}, SaSelection.Mode.REPLACE)
    var mask := _mask_of(_doc)
    for x in range(130, 390, 10):
        var cover := _at(mask, _on_the_side(x))
        assert_true(cover == 0.0 or cover == 1.0, "Column %d is wholly in or out, as every scenario wrote it for" % x)


func test_an_ellipse_asked_to_anti_alias_grades_its_edge() -> void:
    CanvasDriver.select_shapes(_doc.selection, {"ellipse": [100, 100, 300, 200], "anti_alias": true}, SaSelection.Mode.REPLACE)
    var graded := _partial(_mask_of(_doc), Rect2i(98, 98, 304, 204))
    assert_true(graded > 300, "Hundreds of pixels along the rim hold part of a pixel, %d of them" % graded)
    CanvasDriver.select_shapes(_doc.selection, {"ellipse": [100, 100, 300, 200]}, SaSelection.Mode.REPLACE)
    assert_eq(_partial(_mask_of(_doc), Rect2i(98, 98, 304, 204)), 0, "and not asked, none does")


func test_a_rectangle_is_hard_whatever_is_asked() -> void:
    CanvasDriver.select_shapes(_doc.selection, {"rect": [40, 40, 100, 100], "anti_alias": true}, SaSelection.Mode.REPLACE)
    var mask := _mask_of(_doc)
    assert_eq(_at(mask, Vector2i(40, 80)), 1.0, "The rectangle's first column is whole")
    assert_eq(_at(mask, Vector2i(39, 80)), 0.0, "and the one before it empty, its sides lying on whole pixels")


## Every chunk of the selection read back once, `{grid: [bytes, width]}`.
static func _mask_of(document: SaDocument) -> Dictionary:
    var out := {}
    for grid: Vector2i in document.selection.chunks:
        var texture: SaTexture = document.selection.chunks[grid].field(SaSelection.FIELD)
        out[grid] = [GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0), texture.size.x]
    return out


## The coverage at a document pixel, 0 where no chunk is.
static func _at(mask: Dictionary, pixel: Vector2i) -> float:
    var size := SaChunk.SIZE
    var grid := Vector2i(floori(float(pixel.x) / size), floori(float(pixel.y) / size))
    if not mask.has(grid):
        return 0.0
    var bytes: PackedByteArray = mask[grid][0]
    var width: int = mask[grid][1]
    var texel: int = SaFieldSpec.BYTES_PER_TEXEL[SaSelection.FORMAT]
    return bytes.decode_float(((pixel.y - grid.y * size) * width + pixel.x - grid.x * size) * texel)


## How many pixels of *box* hold part of a pixel, neither 0 nor 1.
static func _partial(mask: Dictionary, box: Rect2i) -> int:
    var count := 0
    for y in range(box.position.y, box.end.y):
        for x in range(box.position.x, box.end.x):
            var cover := _at(mask, Vector2i(x, y))
            if cover > 0.0 and cover < 1.0:
                count += 1
    return count
