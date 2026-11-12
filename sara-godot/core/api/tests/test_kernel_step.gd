## The `kernel` step: a cell's source compiled and run once over a
## layer, its errors answered by the line they are on, and its params by type.
##
## The driver is built with no run and handed the document, so the suite drives
## exactly what the step drives without a window. Every pixel assertion reads the
## chunk back the way an export does, the one readback hard rule 1 permits a test.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const KernelDriver := preload("res://harness/sa_kernel_driver.gd")
const SaExportScript = preload("res://core/export/sa_export.gd")

## Ten lines that invert a layer, as a cell would send them. The amount is a
## param so the run proves a value reaches the block.
const INVERT := """kernel invert

image src: readonly
image dst

params:
    float amount

def invert():
    vec4 c = image_load(src, pixel)
    image_store(dst, pixel, vec4(mix(c.rgb, vec3(1.0) - c.rgb, amount), c.a))
"""

## The same kernel with an undeclared name on its fourth line.
const BROKEN := """kernel broken

def broken():
    vec4 c = no_such_thing
"""

## Three params of three types, for the answer a cell's sliders read.
const THREE := """kernel three

image src: readonly
image dst

params:
    float strength
    int steps
    vec2 centre

def three():
    image_store(dst, pixel, image_load(src, pixel) * strength)
"""

const PAINT := Color(0.2, 0.4, 0.6, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _driver: KernelDriver = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(1024, 1024))
    _doc = _easel.document
    _layer = _doc.active_layer
    _driver = KernelDriver.new(null)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null
    _driver = null


func _texel(layer: SaLayer, grid_pos: Vector2i, x: int, y: int) -> Color:
    var image := SaExportScript.get_texture_image_float(layer.chunks[grid_pos].field(SaFieldSpec.ALBEDO))
    return image.get_pixel(x, y)


func _near(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < 1e-4 and absf(a.g - b.g) < 1e-4 and absf(a.b - b.b) < 1e-4 and absf(a.a - b.a) < 1e-4


func test_the_invert_writes_the_painted_chunks_and_allocates_nothing_else() -> void:
    # Two chunks on a diagonal, so the bounds hold two positions with no paint,
    # and a run that wrote its whole rectangle would allocate them.
    _layer.get_or_create_chunk(Vector2i(1, 1)).clear(PAINT)
    _layer.get_or_create_chunk(Vector2i(2, 2)).clear(PAINT)

    var verdict := _driver.run_on(_doc, {"source": INVERT, "name": "invert", "params": {"amount": 1.0}})

    assert_true(bool(verdict["ok"]), "the kernel ran: %s" % [verdict])
    var into := KernelDriver.layer_of(_doc, String(verdict["into"]))
    assert_not_null(into, "and wrote a new layer named after it")
    assert_true(into != _layer, "rather than the layer it read")
    var held: Array = into.chunks.keys()
    held.sort()
    assert_eq(held, [Vector2i(1, 1), Vector2i(2, 2)], "only the painted chunks were allocated")
    var inverted := Color(0.8, 0.6, 0.4, 1.0)
    assert_true(_near(_texel(into, Vector2i(1, 1), 0, 0), inverted), "the first chunk is inverted")
    assert_true(_near(_texel(into, Vector2i(2, 2), 255, 255), inverted), "and so is the far corner of the second")
    assert_true(_near(_texel(_layer, Vector2i(1, 1), 0, 0), PAINT), "and the layer it read is untouched")
    assert_eq(verdict["chunks"], 2, "the verdict counts the chunks written")


func test_a_run_into_the_layer_it_reads_is_one_undo_step() -> void:
    _layer.get_or_create_chunk(Vector2i(0, 0)).clear(PAINT)

    # By its index from the bottom, which the easel's background makes 1.
    var index := SaLayerOps.new(_doc).layers().find(_layer)
    var verdict := _driver.run_on(_doc, {"source": INVERT, "name": "invert", "into": index, "params": {"amount": 1.0}})

    assert_true(bool(verdict["ok"]), "the kernel ran: %s" % [verdict])
    assert_true(_near(_texel(_layer, Vector2i(0, 0), 7, 9), Color(0.8, 0.6, 0.4, 1.0)), "the layer is inverted in place")
    _doc.undo()
    assert_true(_near(_texel(_layer, Vector2i(0, 0), 7, 9), PAINT), "and one undo puts it back")


func test_a_rect_bounds_the_run() -> void:
    _layer.get_or_create_chunk(Vector2i(0, 0)).clear(PAINT)

    var verdict := _driver.run_on(
        _doc, {"source": INVERT, "name": "invert", "into": String(_layer.name), "rect": [0, 0, 16, 16], "params": {"amount": 1.0}}
    )

    assert_eq(verdict["rect"], [0, 0, 16, 16], "the verdict says the rectangle it ran over")
    assert_true(_near(_texel(_layer, Vector2i(0, 0), 15, 15), Color(0.8, 0.6, 0.4, 1.0)), "inside it is inverted")
    assert_true(_near(_texel(_layer, Vector2i(0, 0), 16, 16), PAINT), "and outside it is not")


func test_an_error_answers_the_line_it_is_on() -> void:
    # Provoked on purpose, so the transcript carries the assertion and not the
    # compiler's alarm.
    SaProblems.announce = false
    var verdict := _driver.run_on(_doc, {"source": BROKEN, "name": "broken"})
    SaProblems.announce = true

    assert_false(bool(verdict["ok"]), "the kernel did not compile")
    assert_eq(verdict["line"], 4, "and the verdict names line 4 of the source as sent: %s" % [verdict])
    assert_true(String(verdict["error"]).contains("broken.gmacs:4"), "in the compiler's own words: %s" % [verdict["error"]])


func test_the_same_source_twice_compiles_once() -> void:
    _layer.get_or_create_chunk(Vector2i(0, 0)).clear(PAINT)
    var spec := {"source": INVERT, "name": "invert", "into": String(_layer.name), "params": {"amount": 1.0}}

    var first := _driver.run_on(_doc, spec)
    var second := _driver.run_on(_doc, spec)

    assert_true(bool(first["compiled"]), "the first send compiled")
    assert_false(bool(second["compiled"]), "the second found it compiled")
    assert_eq(_driver.compiles, 1, "and the driver counts one compile")
    assert_true(_near(_texel(_layer, Vector2i(0, 0), 3, 3), PAINT), "while both runs happened, inverting twice")


func test_three_params_come_back_with_their_types() -> void:
    var verdict := _driver.run_on(_doc, {"source": THREE, "name": "three", "run": false})

    assert_true(bool(verdict["ok"]), "the kernel compiled: %s" % [verdict])
    assert_eq(
        verdict["params"],
        [
            {"name": "strength", "type": "float", "default": 0.0},
            {"name": "steps", "type": "int", "default": 0},
            {"name": "centre", "type": "vec2", "default": [0.0, 0.0]},
        ],
        "each param with its type and its zero"
    )
    assert_false(verdict.has("into"), "and a compile-only request touched no layer")
    assert_eq(SaLayerOps.new(_doc).layers().size(), 2, "nor added one to the background and the paint layer")
