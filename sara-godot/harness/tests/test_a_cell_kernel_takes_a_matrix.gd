## A notebook cell's matrix: a `float weights[49]` on a params
## line, or on a `uniform` line of the short form, is answered as a matrix the
## notebook draws as a grid, opens on a one in the middle, and runs from the
## storage buffer the dialect moved it into, because 196 bytes do not fit the
## push constant.
##
## Built like the kernel inputs suite: the driver with no run, handed the document, and each
## pixel read back the way an export does, the one readback a test may make.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const KernelDriver := preload("res://harness/sa_kernel_driver.gd")
const SaExportScript = preload("res://core/export/sa_export.gd")

## A 7 by 7 convolution over the source, the edge read as its nearest texel.
const SEVEN := """kernel convolve

image src: readonly
image dst

params:
    vec2 extent
    float gain
    float weights[49]

def convolve():
    if pixel.x >= int(extent.x) or pixel.y >= int(extent.y):
        return
    vec4 sum = vec4(0.0)
    for row in range(0, 7):
        for column in range(0, 7):
            ivec2 at = clamp(pixel + ivec2(column - 3, row - 3), ivec2(0), ivec2(extent) - 1)
            sum += image_load(src, at) * weights[row * 7 + column]
    image_store(dst, pixel, sum * gain)
"""

## The same with a 3 by 3, which stays in the push constant.
const THREE := """kernel convolve_small

image src: readonly
image dst

params:
    vec2 extent
    float weights[9]

def convolve_small():
    if pixel.x >= int(extent.x) or pixel.y >= int(extent.y):
        return
    image_store(dst, pixel, image_load(src, pixel) * weights[4])
"""

## The short form with the same two matrices on `uniform` lines, the 3 by 3
## written as its rows and the 7 by 7 with no default.
const SHORT := """uniform float near[9] = {
    0.0, 0.0, 0.0,
    0.0, 0.5, 0.0,
    0.0, 0.0, 0.0}
uniform float wide[49]

def pixel(ivec2 at) -> vec4:
    vec4 sum = vec4(0.0)
    for row in range(0, 3):
        for column in range(0, 3):
            sum += src(at + ivec2(column - 1, row - 1)) * near[row * 3 + column]
    for row in range(0, 7):
        for column in range(0, 7):
            sum += src(at + ivec2(column - 3, row - 3)) * wide[row * 7 + column]
    return vec4(sum.rgb, src(at).a)
"""

const PAINT := Color(0.2, 0.4, 0.6, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _driver: KernelDriver = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(1024, 1024))
    _doc = _easel.document
    _driver = KernelDriver.new(null)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _driver = null


## The params the notebook builds its widgets from: each matrix with its length
## and a one in the middle, the moved one among them, and the scalar beside it.
func test_a_matrix_is_answered_with_its_length_and_a_one_in_the_middle() -> void:
    var verdict := _driver.run_on(_doc, {"source": SEVEN, "name": "convolve", "run": false})
    assert_true(bool(verdict["ok"]), "the kernel compiled: %s" % [verdict])
    var by_name := {}
    for param: Dictionary in verdict.get("params", []):
        by_name[param["name"]] = param
    assert_eq(by_name.keys(), ["gain", "weights"], "the scalar, then the matrix that moved")
    var weights: Dictionary = by_name.get("weights", {})
    assert_eq(int(weights.get("length", 0)), 49, "a matrix says its length")
    assert_eq(str(weights.get("type", "")), "float", "and its type")
    var opening: Array = weights.get("default", [])
    assert_eq(opening.size(), 49, "it opens on forty-nine numbers")
    assert_eq(opening.find(1.0), 24, "a one in the middle")
    assert_eq(opening.count(1.0), 1, "and nought everywhere else")
    assert_false(by_name["gain"].has("length"), "a scalar has no length")

    var small := _driver.run_on(_doc, {"source": THREE, "name": "convolve_small", "run": false})
    var nine: Dictionary = small["params"][0]
    assert_eq([nine["name"], int(nine["length"])], ["weights", 9], "a 3 by 3 that stays in the block says its length too")


## The moved matrix reaches the kernel: at its default the layer is written as
## it was, and a one at the end of the middle row reads three to the right,
## which is past the paint at its edge.
func test_a_moved_matrix_reaches_the_kernel_row_by_row() -> void:
    var paint := SaLayerOps.new(_doc).add(&"", null)
    paint.name = "Paint"
    paint.get_or_create_chunk(Vector2i(0, 0)).clear(PAINT)
    var rect := [0, 0, 512, 256]

    var kept := _driver.run_on(
        _doc, {"source": SEVEN, "name": "convolve", "layer": "Paint", "into": "Kept", "rect": rect, "params": {"gain": 1.0}}
    )
    assert_true(bool(kept["ok"]), "the kernel ran at its default: %s" % [kept])
    assert_true(_texel("Kept", 253, 10).is_equal_approx(PAINT), "a one in the middle writes the paint as it was")
    assert_true(_texel("Kept", 256, 10).is_equal_approx(Color(0, 0, 0, 0)), "and nothing past it")

    var right := []
    right.resize(49)
    right.fill(0.0)
    right[3 * 7 + 6] = 1.0
    var shifted := _driver.run_on(
        _doc,
        {
            "source": SEVEN,
            "name": "convolve",
            "layer": "Paint",
            "into": "Shifted",
            "rect": rect,
            "params": {"gain": 1.0, "weights": right}
        }
    )
    assert_true(bool(shifted["ok"]), "the kernel ran with its matrix: %s" % [shifted])
    assert_true(_texel("Shifted", 252, 10).is_equal_approx(PAINT), "three to the left of the edge reads the paint")
    assert_true(_texel("Shifted", 253, 10).is_equal_approx(Color(0, 0, 0, 0)), "three from it reads past the edge")


## A matrix on a `uniform` line is answered the way one on a params line is,
## its written rows its opening, and the run adds a half of the picture to the
## whole of it through the 7 by 7's one in the middle.
func test_a_matrix_on_a_uniform_line_is_answered_and_runs_alike() -> void:
    var paint := SaLayerOps.new(_doc).add(&"", null)
    paint.name = "Paint"
    paint.get_or_create_chunk(Vector2i(0, 0)).clear(PAINT)
    var ran := _driver.run_on(_doc, {"source": SHORT, "name": "weighted", "layer": "Paint", "rect": [0, 0, 256, 256]})
    assert_true(bool(ran["ok"]), "the short form ran: %s" % [ran])
    var by_name := {}
    for param: Dictionary in ran.get("params", []):
        by_name[param["name"]] = param
    assert_eq(by_name.keys(), ["near", "wide"], "both matrices, the 3 by 3 kept and the 7 by 7 moved")
    assert_eq(int(by_name["near"]["length"]), 9, "the 3 by 3 says its length")
    assert_eq(by_name["near"]["default"], [0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 0.0], "and opens on its rows as written")
    assert_eq(int(by_name["wide"]["length"]), 49, "the 7 by 7 says its length")
    assert_eq((by_name["wide"]["default"] as Array).find(1.0), 24, "and opens on a one in the middle")
    var expected := Color(PAINT.r * 1.5, PAINT.g * 1.5, PAINT.b * 1.5, PAINT.a)
    var written := _texel("weighted", 100, 100)
    assert_true(written.is_equal_approx(expected), "a half and a whole of the paint: %s" % written)


## The texel at *x*, *y* of the layer called *name*, in its first chunk.
func _texel(name: String, x: int, y: int) -> Color:
    var layer := KernelDriver.layer_of(_doc, name)
    var chunk_pos := Vector2i(floori(float(x) / SaChunk.SIZE), floori(float(y) / SaChunk.SIZE))
    if layer == null or not layer.chunks.has(chunk_pos):
        return Color(0, 0, 0, 0)
    var image := SaExportScript.get_texture_image_float(layer.chunks[chunk_pos].field(SaFieldSpec.ALBEDO))
    return image.get_pixel(x % SaChunk.SIZE, y % SaChunk.SIZE)
