## The `kernel` step runs over the whole canvas for
## `"rect": "canvas"`, and with no `rect` over a read layer that holds no paint,
## so the noise lesson's first cell, a texture made from `at` alone into a new
## layer over the empty layer `sara.init()` answers, is no longer refused. A
## read layer that holds paint keeps the chunks it holds, hard rule 3.
##
## Built like the kernel read suite: the driver with no run, handed the document, and each
## pixel read back the way an export does, the one readback a test may make.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const KernelDriver := preload("res://harness/sa_kernel_driver.gd")
const SaExportScript = preload("res://core/export/sa_export.gd")

## The ask's cell, a gradient from the document pixel and nothing it reads.
const GRADIENT := """def pixel(ivec2 at) -> vec4:
    return vec4(vec2(at) / 1000.0, 0.0, 1.0)
"""

## Not a multiple of the chunk's size, so the canvas ends inside a chunk.
const CANVAS := Vector2i(1000, 600)

const FLAT := Color(0.2, 0.4, 0.6, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _driver: KernelDriver = null


func before_each() -> void:
    _easel = SaEasel.create_default(CANVAS)
    _doc = _easel.document
    _driver = KernelDriver.new(null)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _driver = null


## A layer called *name* holding no chunk.
func _empty(name: String) -> SaLayer:
    var layer := SaLayerOps.new(_doc).add(&"", null)
    layer.name = name
    return layer


## A layer called *name* painted FLAT in the canvas's top left chunk alone.
func _corner(name: String) -> SaLayer:
    var layer := _empty(name)
    layer.get_or_create_chunk(Vector2i.ZERO).clear(FLAT)
    return layer


## Every chunk the canvas reaches.
func _canvas_chunks() -> int:
    @warning_ignore("integer_division")
    var grid := (CANVAS - Vector2i.ONE) / SaChunk.SIZE + Vector2i.ONE
    return grid.x * grid.y


## The texel of *layer* at the document pixel *at*, transparent where it holds no chunk.
func _texel(layer: SaLayer, at: Vector2i) -> Color:
    @warning_ignore("integer_division")
    var chunk: SaChunk = layer.chunks.get(at / SaChunk.SIZE, null)
    if chunk == null:
        return Color(0.0, 0.0, 0.0, 0.0)
    var image := SaExportScript.get_texture_image_float(chunk.field(SaFieldSpec.ALBEDO))
    var local := at % SaChunk.SIZE
    return image.get_pixel(local.x, local.y)


## What GRADIENT writes at *at*.
func _gradient(at: Vector2i) -> Color:
    return Color(at.x / 1000.0, at.y / 1000.0, 0.0, 1.0)


func _near(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < 2e-3 and absf(a.g - b.g) < 2e-3 and absf(a.b - b.b) < 2e-3 and absf(a.a - b.a) < 2e-3


func _cell(read: String, extra: Dictionary = {}) -> Dictionary:
    var spec := {"source": GRADIENT, "name": "pixels", "layer": read, "into": "Gradient"}
    spec.merge(extra, true)
    return _driver.run_on(_doc, spec)


func test_a_cell_with_no_rect_over_an_empty_layer_writes_the_whole_canvas() -> void:
    _empty("Empty")

    var verdict := _cell("Empty")

    assert_true(bool(verdict["ok"]), "the cell ran rather than being refused: %s" % [verdict])
    assert_eq(verdict["rect"], [0, 0, CANVAS.x, CANVAS.y], "over the canvas")
    assert_eq(int(verdict["chunks"]), _canvas_chunks(), "every chunk the canvas reaches written")
    var written := KernelDriver.layer_of(_doc, "Gradient")
    assert_eq(written.chunks.size(), _canvas_chunks(), "the new layer holds them all")
    var far := CANVAS - Vector2i.ONE
    for at: Vector2i in [far, Vector2i(0, far.y), Vector2i(far.x, 0), Vector2i(512, 300)]:
        assert_true(_near(_texel(written, at), _gradient(at)), "the gradient at %s: %s" % [at, _texel(written, at)])


func test_a_cell_with_no_rect_over_a_painted_corner_writes_that_corner_alone() -> void:
    _corner("Corner")

    var verdict := _cell("Corner")

    assert_true(bool(verdict["ok"]), "the cell ran: %s" % [verdict])
    assert_eq(verdict["rect"], [0, 0, SaChunk.SIZE, SaChunk.SIZE], "over the chunk the layer holds")
    assert_eq(int(verdict["chunks"]), 1, "one chunk written")
    var written := KernelDriver.layer_of(_doc, "Gradient")
    assert_eq(written.chunks.size(), 1, "and nothing allocated past it")
    var inside := Vector2i(SaChunk.SIZE - 1, SaChunk.SIZE - 1)
    assert_true(_near(_texel(written, inside), _gradient(inside)), "the gradient inside: %s" % [_texel(written, inside)])


func test_rect_canvas_over_a_painted_corner_writes_the_whole_canvas() -> void:
    _corner("Corner")

    var verdict := _cell("Corner", {"rect": "canvas"})

    assert_true(bool(verdict["ok"]), "the cell ran: %s" % [verdict])
    assert_eq(verdict["rect"], [0, 0, CANVAS.x, CANVAS.y], "over the canvas")
    assert_eq(int(verdict["chunks"]), _canvas_chunks(), "every chunk the canvas reaches written")
    var written := KernelDriver.layer_of(_doc, "Gradient")
    assert_eq(written.chunks.size(), _canvas_chunks(), "the layer holds them all")
    var far := CANVAS - Vector2i.ONE
    assert_true(_near(_texel(written, far), _gradient(far)), "the gradient at the far corner: %s" % [_texel(written, far)])


func test_a_rect_that_is_neither_numbers_nor_canvas_is_refused() -> void:
    _corner("Corner")

    var verdict := _cell("Corner", {"rect": "everywhere"})

    assert_false(bool(verdict["ok"]), "refused: %s" % [verdict])
    assert_true(String(verdict["error"]).contains("canvas"), "naming the word it takes: %s" % [verdict["error"]])
    assert_null(KernelDriver.layer_of(_doc, "Gradient"), "and no layer added")
