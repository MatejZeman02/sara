## The `kernel` step gathers its source past the rectangle it
## writes, so a blur run over a rectangle reads the paint around it rather than
## transparent black, and a tap past the canvas reads the canvas's edge texel.
##
## Built like the other kernel suites: the driver with no run, handed the document, and each
## pixel read back the way an export does, the one readback a test may make.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const KernelDriver := preload("res://harness/sa_kernel_driver.gd")
const SaExportScript = preload("res://core/export/sa_export.gd")

## A box blur as a lesson writes it, reading its neighbours at `pixel`.
const BOX := """kernel box

image src: readonly
image dst

params:
    int radius

def box():
    vec4 sum = vec4(0.0)
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            sum += image_load(src, pixel + ivec2(dx, dy))
    int n = 2 * radius + 1
    image_store(dst, pixel, sum / float(n * n))
"""

## Writes each pixel with the texel five to the right and five below it, so at
## the canvas's last column and row every read lies past the canvas.
const SHIFT := """kernel shift

image src: readonly
image dst

def shift():
    image_store(dst, pixel, image_load(src, pixel + ivec2(5, 5)))
"""

const FLAT := Color(0.2, 0.4, 0.6, 1.0)

## Not a multiple of the chunk's size, so the canvas ends inside a chunk.
const CANVAS := Vector2i(1000, 1000)

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


## A layer called *name* filled with FLAT over every chunk the canvas reaches.
func _flat(name: String) -> SaLayer:
    var layer := SaLayerOps.new(_doc).add(&"", null)
    layer.name = name
    @warning_ignore("integer_division")
    var last := (CANVAS - Vector2i.ONE) / SaChunk.SIZE
    for y in range(last.y + 1):
        for x in range(last.x + 1):
            layer.get_or_create_chunk(Vector2i(x, y)).clear(FLAT)
    return layer


## The texel of *layer* at the document pixel *at*.
func _texel(layer: SaLayer, at: Vector2i) -> Color:
    @warning_ignore("integer_division")
    var chunk: SaChunk = layer.chunks[at / SaChunk.SIZE]
    var image := SaExportScript.get_texture_image_float(chunk.field(SaFieldSpec.ALBEDO))
    var local := at % SaChunk.SIZE
    return image.get_pixel(local.x, local.y)


func _near(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < 1e-4 and absf(a.g - b.g) < 1e-4 and absf(a.b - b.b) < 1e-4 and absf(a.a - b.a) < 1e-4


func _blur(rect: Array, extra: Dictionary = {}) -> Dictionary:
    var spec := {"source": BOX, "name": "box", "layer": "Flat", "into": "Flat", "rect": rect, "params": {"radius": 3}}
    spec.merge(extra, true)
    return _driver.run_on(_doc, spec)


func test_a_blur_inside_a_flat_layer_keeps_its_edges_the_flat_colour() -> void:
    var layer := _flat("Flat")

    var verdict := _blur([300, 200, 100, 80])

    assert_true(bool(verdict["ok"]), "the kernel ran: %s" % [verdict])
    assert_eq(verdict["rect"], [300, 200, 100, 80], "over the rectangle it was asked for")
    assert_eq(int(verdict["halo"]), KernelDriver.DEFAULT_HALO, "with the default halo")
    for at: Vector2i in [Vector2i(300, 200), Vector2i(399, 200), Vector2i(300, 279), Vector2i(399, 279), Vector2i(350, 200)]:
        assert_true(_near(_texel(layer, at), FLAT), "the edge texel %s stays the flat colour: %s" % [at, _texel(layer, at)])


func test_a_halo_of_zero_reads_the_rectangle_alone() -> void:
    var layer := _flat("Flat")

    var verdict := _blur([300, 200, 100, 80], {"halo": 0})

    assert_true(bool(verdict["ok"]), "the kernel ran: %s" % [verdict])
    var corner := _texel(layer, Vector2i(300, 200))
    assert_true(corner.a < 0.9, "the corner reads transparent past the rectangle and comes out lighter: %s" % [corner])
    assert_true(_near(_texel(layer, Vector2i(350, 240)), FLAT), "while the middle stays flat")


func test_a_tap_past_the_canvas_reads_its_edge_texel() -> void:
    var layer := _flat("Flat")

    var verdict := _blur([0, 0, 40, 40])
    assert_true(bool(verdict["ok"]), "the blur at the canvas's corner ran: %s" % [verdict])
    assert_true(
        _near(_texel(layer, Vector2i(0, 0)), FLAT), "the canvas's corner stays flat: %s" % [_texel(layer, Vector2i(0, 0))]
    )

    verdict = _driver.run_on(
        _doc, {"source": SHIFT, "name": "shift", "layer": "Flat", "into": "Flat", "rect": [960, 960, 40, 40]}
    )
    assert_true(bool(verdict["ok"]), "the shift ran: %s" % [verdict])
    var last := CANVAS - Vector2i.ONE
    assert_true(
        _near(_texel(layer, last), FLAT), "the last texel read five past the canvas as the edge: %s" % [_texel(layer, last)]
    )


func test_the_write_stays_the_rectangle() -> void:
    var layer := _flat("Flat")
    var out := SaLayerOps.new(_doc).add(&"", null)
    out.name = "Out"

    var verdict := _driver.run_on(
        _doc, {"source": SHIFT, "name": "shift", "layer": "Flat", "into": "Out", "rect": [100, 100, 20, 20]}
    )

    assert_true(bool(verdict["ok"]), "the kernel ran: %s" % [verdict])
    assert_eq(int(verdict["chunks"]), 1, "one chunk written")
    assert_true(_near(_texel(out, Vector2i(119, 119)), FLAT), "inside the rectangle the result")
    assert_true(_near(_texel(out, Vector2i(120, 120)), Color(0, 0, 0, 0)), "and past it nothing, halo or not")
    assert_true(_near(_texel(layer, Vector2i(120, 120)), FLAT), "the read layer untouched")
