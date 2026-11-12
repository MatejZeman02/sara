## The `kernel` step's `inputs`: one kernel reads two layers, or
## two corners of one, which is what an array's expression over two operands is.
##
## Built like the kernel read suite: the driver with no run, handed the document, and each
## pixel read back the way an export does, the one readback a test may make.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const KernelDriver := preload("res://harness/sa_kernel_driver.gd")
const SaExportScript = preload("res://core/export/sa_export.gd")

## The sum of two images, as the array writes `a + b`.
const ADD := """kernel add_two

image src: readonly
image src1: readonly
image dst

params:
    vec2 extent

def add_two():
    if pixel.x >= int(extent.x) or pixel.y >= int(extent.y):
        return
    image_store(dst, pixel, image_load(src, pixel) + image_load(src1, pixel))
"""

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


func _layer(name: String) -> SaLayer:
    var layer := SaLayerOps.new(_doc).add(&"", null)
    layer.name = name
    return layer


func _texel(layer: SaLayer, grid_pos: Vector2i, x: int, y: int) -> Color:
    var image := SaExportScript.get_texture_image_float(layer.chunks[grid_pos].field(SaFieldSpec.ALBEDO))
    return image.get_pixel(x, y)


func _near(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < 1e-3 and absf(a.g - b.g) < 1e-3 and absf(a.b - b.b) < 1e-3 and absf(a.a - b.a) < 1e-3


func test_two_layers_are_read_by_one_kernel() -> void:
    var first := _layer("First")
    first.get_or_create_chunk(Vector2i(0, 0)).clear(Color(0.1, 0.2, 0.3, 0.5))
    var second := _layer("Second")
    second.get_or_create_chunk(Vector2i(1, 0)).clear(Color(0.4, 0.4, 0.4, 0.5))
    var out := _layer("Out")

    var spec := {
        "source": ADD,
        "name": "add_two",
        "layer": "First",
        "rect": [0, 0, 256, 256],
        "into": "Out",
        "inputs": {"src1": {"layer": "Second", "at": [256, 0]}}
    }
    var verdict := _driver.run_on(_doc, spec)

    assert_true(bool(verdict["ok"]), "the kernel ran: %s" % [verdict])
    assert_true(_near(_texel(out, Vector2i(0, 0), 5, 7), Color(0.5, 0.6, 0.7, 1.0)), "each texel is the two summed")
    assert_eq(out.chunks.size(), 1, "and only the chunk under the rectangle is written")


func test_an_input_where_the_layer_holds_nothing_reads_zero() -> void:
    var first := _layer("First")
    first.get_or_create_chunk(Vector2i(0, 0)).clear(Color(0.1, 0.2, 0.3, 1.0))
    _layer("Empty")

    var spec := {
        "source": ADD, "name": "add_two", "layer": "First", "rect": [0, 0, 64, 64], "into": "First", "inputs": {"src1": "Empty"}
    }
    var verdict := _driver.run_on(_doc, spec)

    assert_true(bool(verdict["ok"]), "the kernel ran: %s" % [verdict])
    assert_true(_near(_texel(first, Vector2i(0, 0), 3, 3), Color(0.1, 0.2, 0.3, 1.0)), "the sum with nothing is itself")


func test_an_unknown_input_is_refused_before_anything_is_written() -> void:
    _layer("First").get_or_create_chunk(Vector2i(0, 0)).clear(Color(0.1, 0.2, 0.3, 1.0))
    var before := SaLayerOps.new(_doc).layers().size()

    var verdict := _driver.run_on(
        _doc, {"source": ADD, "name": "add_two", "layer": "First", "inputs": {"src1": {"layer": "Nowhere"}}}
    )

    assert_false(bool(verdict["ok"]), "an input with no layer is refused")
    assert_true(String(verdict["error"]).contains("Nowhere"), "naming the layer: %s" % [verdict])
    assert_eq(SaLayerOps.new(_doc).layers().size(), before, "and no layer was added for the result")


func test_an_image_no_input_binds_is_refused_and_the_target_kept() -> void:
    _layer("First").get_or_create_chunk(Vector2i(0, 0)).clear(Color(0.1, 0.2, 0.3, 1.0))
    var out := _layer("Out")
    out.get_or_create_chunk(Vector2i(0, 0)).clear(Color(0.6, 0.5, 0.4, 1.0))
    var before := SaLayerOps.new(_doc).layers().size()

    var spec := {"source": ADD, "name": "add_two", "layer": "First", "rect": [0, 0, 64, 64], "into": "Out"}
    var verdict := _driver.run_on(_doc, spec)

    assert_false(bool(verdict["ok"]), "a kernel with an image left unbound is refused")
    assert_true(String(verdict.get("error", "")).contains("src1"), "naming the image: %s" % [verdict])
    assert_eq(SaLayerOps.new(_doc).layers().size(), before, "no layer was added")
    assert_true(_near(_texel(out, Vector2i(0, 0), 3, 3), Color(0.6, 0.5, 0.4, 1.0)), "and the target is as it was")


func test_an_unbound_image_adds_no_result_layer() -> void:
    _layer("First").get_or_create_chunk(Vector2i(0, 0)).clear(Color(0.1, 0.2, 0.3, 1.0))
    var before := SaLayerOps.new(_doc).layers().size()

    var verdict := _driver.run_on(_doc, {"source": ADD, "name": "add_two", "layer": "First", "rect": [0, 0, 64, 64]})

    assert_false(bool(verdict["ok"]), "refused with no layer named to write")
    assert_eq(SaLayerOps.new(_doc).layers().size(), before, "and no layer was added for the result")
