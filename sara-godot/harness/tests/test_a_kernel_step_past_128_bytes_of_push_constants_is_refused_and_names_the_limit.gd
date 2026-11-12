## A `kernel` step whose params block, at the size Sara computes for it, is past
## the 128 bytes a dispatch takes answers `ok: false` with an error naming both
## numbers, before any layer or history step. The engine would otherwise drop
## the dispatch with a line in its log and the step would read back the layer
## it never wrote as if it had run.
##
## The two kernels are the realistic media research's `scatter` cut down: a
## run of floats and the `origin` the step fills from the rectangle. 34 floats
## and the vec2 make 144 bytes, 29 floats and the vec2 exactly 128.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const KernelDriver := preload("res://harness/sa_kernel_driver.gd")
const SaExportScript = preload("res://core/export/sa_export.gd")

const PAINT := Color(0.8, 0.4, 0.2, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _paint: SaLayer = null
var _driver: KernelDriver = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document
    _paint = _doc.active_layer
    _paint.get_or_create_chunk(Vector2i(0, 0)).clear(PAINT)
    _driver = KernelDriver.new(null)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _paint = null
    _driver = null


## A kernel named *kernel_name* of *floats* float params and a vec2 `origin`,
## which writes the colour it reads with its red set to the first float.
static func _source(kernel_name: String, floats: int) -> String:
    var lines := PackedStringArray(["kernel " + kernel_name, "", "image src: readonly", "image dst", "", "params:"])
    for i in floats:
        lines.append("    float f%d" % i)
    lines.append("    vec2 origin")
    lines.append_array(["", "def %s():" % kernel_name, "    vec4 c = image_load(src, pixel)"])
    lines.append("    image_store(dst, pixel, vec4(f0, c.g, c.b, c.a))")
    return "\n".join(lines) + "\n"


func _spec(kernel_name: String, floats: int) -> Dictionary:
    return {
        "source": _source(kernel_name, floats),
        "name": kernel_name,
        "layer": String(_paint.name),
        "rect": [0, 0, 64, 64],
        "params": {"f0": 0.25},
    }


func test_a_block_of_144_bytes_is_refused_and_names_144_and_128() -> void:
    var spec := _spec("spray", 34)
    var verdict := _driver.run_on(_doc, spec)
    var shader: String = (_driver._compiled.values()[0] as KernelDriver.CellKernel).compute.shader_name
    assert_eq(GlobalShaderCompiler.push_constant_bytes(shader), 144, "the block Sara computes is 144 bytes")
    assert_false(bool(verdict["ok"]), "a block past the limit is refused: %s" % [verdict])
    var error := String(verdict.get("error", ""))
    assert_true(error.contains("144") and error.contains("128"), "the error names the size and the limit: %s" % error)
    assert_true(error.contains("spray"), "the error names the kernel: %s" % error)


func test_the_refused_step_adds_no_layer_and_no_history_step() -> void:
    var layers := _doc.get_children().size()
    var steps := _doc.history.step_count()
    var verdict := _driver.run_on(_doc, _spec("spray", 34))
    assert_false(bool(verdict["ok"]), "refused: %s" % [verdict])
    assert_eq(_doc.get_children().size(), layers, "the refusal added no layer")
    assert_eq(_doc.history.step_count(), steps, "the refusal recorded no history step")
    assert_null(KernelDriver.layer_of(_doc, "spray"), "no layer called spray")


func test_a_block_of_exactly_128_bytes_runs_and_writes_its_layer() -> void:
    var verdict := _driver.run_on(_doc, _spec("spray", 29))
    var shader: String = (_driver._compiled.values()[0] as KernelDriver.CellKernel).compute.shader_name
    assert_eq(GlobalShaderCompiler.push_constant_bytes(shader), 128, "the block Sara computes is 128 bytes")
    assert_true(bool(verdict["ok"]), "a block at the limit runs: %s" % [verdict])
    var into := KernelDriver.layer_of(_doc, String(verdict.get("into", "")))
    assert_not_null(into, "the kernel wrote a layer")
    if into == null:
        return
    var image := SaExportScript.get_texture_image_float(into.chunks[Vector2i.ZERO].field(SaFieldSpec.ALBEDO))
    var texel := image.get_pixel(7, 9)
    assert_almost_eq(texel.r, 0.25, 2e-3, "red is the param the block carried")
    assert_almost_eq(texel.g, PAINT.g, 2e-3, "green is the layer's")
