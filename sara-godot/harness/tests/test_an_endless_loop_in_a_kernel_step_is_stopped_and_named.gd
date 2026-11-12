## A `kernel` step whose loop never ends is stopped by the loop
## guard before the driver gives the GPU up, answers an error naming the kernel,
## and the next step runs and answers. Lesson 00's cell 29 did this with a
## `while true:` over the canvas and took Sara down with the painter's work.
##
## Built like the other kernel step suites: the driver with no run, handed a
## document at File > New's size. Every endless kernel runs over a rectangle of
## one workgroup first, so a guard that failed would cost one workgroup's hang
## and not the whole canvas's. The text half is `sa_loop_guard.gd`'s own suite
## in `core/custom-shader/dialect/tests/`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const KernelDriver := preload("res://harness/sa_kernel_driver.gd")
const LoopGuard := preload("res://core/custom-shader/dialect/sa_loop_guard.gd")
const SaExportScript = preload("res://core/export/sa_export.gd")

## File > New's size, `new_document_dialog.gd`'s DEFAULT_SIZE.
const NEW_DOCUMENT := Vector2i(1920, 1080)

## Windows' default timeout for a GPU that stops answering, the shortest any
## driver Sara runs on keeps. The laptop's Linux driver waited about thirty.
const DRIVER_TIMEOUT_MS: float = 2000.0

## The cell that hung the laptop, in the dialect a student writes.
const ENDLESS := """kernel endless

image src: readonly
image dst

def endless():
    float v = 0.0
    while true:
        v += 1.0
    image_store(dst, pixel, vec4(v))
"""

## A kernel that ends, its loop well inside the budget, so the guard leaves its
## answer as it was: the sum of the first hundred whole numbers.
const COUNTED := """kernel counted

image src: readonly
image dst

def counted():
    float v = 0.0
    for i in range(0, 100):
        v += float(i)
    image_store(dst, pixel, vec4(v / 4950.0, 0.0, 0.0, 1.0))
"""

## No loop at all, so the kernel is compiled as it always was.
const FLAT := """kernel flat

image src: readonly
image dst

def flat():
    image_store(dst, pixel, vec4(0.25, 0.5, 0.75, 1.0))
"""

## The short form, whose body is an include of the wrapper the step writes.
const PIXEL_ENDLESS := """def pixel(ivec2 at) -> vec4:
    float v = 0.0
    while true:
        v += 1.0
    return vec4(v)
"""

var _easel: SaEasel = null
var _doc: SaDocument = null
var _driver: KernelDriver = null


func before_each() -> void:
    _easel = SaEasel.create_default(NEW_DOCUMENT)
    _doc = _easel.document
    _driver = KernelDriver.new(null)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _driver = null


## The texel at *at* of the layer *name*, inside its first chunk.
func _texel(name: String, at: Vector2i) -> Color:
    var layer := KernelDriver.layer_of(_doc, name)
    var chunk: SaChunk = layer.chunks.get(Vector2i.ZERO, null)
    if chunk == null:
        return Color(0.0, 0.0, 0.0, 0.0)
    return SaExportScript.get_texture_image_float(chunk.field(SaFieldSpec.ALBEDO)).get_pixel(at.x, at.y)


## Asserts *verdict* is the guard's stop, named for *kernel_name*.
func _assert_stopped(verdict: Dictionary, kernel_name: String, where: String) -> void:
    assert_false(bool(verdict["ok"]), "the endless kernel %s fails: %s" % [where, verdict])
    assert_true(bool(verdict.get("stopped", false)), "because the guard stopped it %s" % where)
    var said := String(verdict.get("error", ""))
    var named := said.begins_with("kernel %s ran past its loop budget" % kernel_name)
    assert_true(named, "and says which kernel and why: %s" % said)


func test_an_endless_loop_over_a_new_documents_canvas_is_stopped_and_the_next_step_runs() -> void:
    var small := _driver.run_on(_doc, {"source": ENDLESS, "name": "endless", "rect": [0, 0, 8, 8], "halo": 0})
    _assert_stopped(small, "endless", "over one workgroup")
    if bool(small["ok"]) or not bool(small.get("stopped", false)):
        return

    var canvas := _driver.run_on(_doc, {"source": ENDLESS, "name": "endless", "rect": "canvas"})
    _assert_stopped(canvas, "endless", "over the whole canvas")
    print("an endless loop over %s stopped after %s ms of GPU time" % [NEW_DOCUMENT, canvas.get("gpu_ms")])
    if canvas.get("gpu_ms") != null:
        assert_true(float(canvas["gpu_ms"]) < DRIVER_TIMEOUT_MS, "well under any driver's timeout: %s ms" % canvas["gpu_ms"])

    var next := _driver.run_on(_doc, {"source": FLAT, "name": "flat", "rect": [0, 0, 8, 8], "halo": 0})
    assert_true(bool(next["ok"]), "the next kernel step runs and answers: %s" % [next])
    assert_true(_texel("flat", Vector2i(3, 3)).is_equal_approx(Color(0.25, 0.5, 0.75, 1.0)), "and writes its colour")


func test_a_loop_inside_the_budget_answers_as_it_always_did() -> void:
    var verdict := _driver.run_on(_doc, {"source": COUNTED, "name": "counted", "rect": [0, 0, 8, 8], "halo": 0})

    assert_true(bool(verdict["ok"]), "a loop that ends is not stopped: %s" % [verdict])
    assert_false(verdict.has("stopped"), "and the verdict says nothing of a stop")
    assert_almost_eq(_texel("counted", Vector2i(3, 3)).r, 1.0, 1e-6, "every turn of it ran")


func test_a_kernel_with_no_loop_declares_no_guard() -> void:
    var flat := KernelDriver.CellKernel.new("flat", FLAT)
    var looped := KernelDriver.CellKernel.new("counted", COUNTED)

    assert_eq(flat.error, "", "the flat kernel compiles")
    assert_eq(flat.loops, 0, "with no loop to bound")
    var flat_layout := GlobalShaderCompiler.binding_layout(flat.shader_name)
    assert_eq(SaCompute.BindingSlots.slot_of(flat_layout, LoopGuard.INSTANCE, "buffer"), -1, "so it declares no guard")
    var looped_layout := GlobalShaderCompiler.binding_layout(looped.shader_name)
    var looped_slot := SaCompute.BindingSlots.slot_of(looped_layout, LoopGuard.INSTANCE, "buffer")
    assert_eq(looped_slot, 2, "and one loop is enough to declare it, after the kernel's two images")


func test_an_endless_loop_in_the_short_pixel_form_is_stopped_too() -> void:
    var verdict := _driver.run_on(_doc, {"source": PIXEL_ENDLESS, "name": "spin", "rect": [0, 0, 8, 8], "halo": 0})

    _assert_stopped(verdict, "spin", "in the short form")


func test_a_loop_the_guard_cannot_read_is_refused_at_its_line() -> void:
    var source := "#kernel hidden\n"
    source += "layout( SA_STORAGE_FORMAT, set = 0, binding = 0 ) uniform image2D dst;\n"
    source += "#define FOREVER while\n"
    source += "[numthreads( 8, 8, 1 )] void hidden() { FOREVER (true) {} }\n"
    var verdict := _driver.run_on(_doc, {"source": source, "name": "hidden", "rect": [0, 0, 8, 8], "halo": 0})

    assert_false(bool(verdict["ok"]), "a loop renamed out of the guard's sight is not run: %s" % [verdict])
    assert_eq(int(verdict.get("line", 0)), 3, "and the verdict names the line that hid it")
    assert_true(String(verdict["error"]).contains("hidden.gmacs:3"), "in the compiler's spelling: %s" % [verdict["error"]])
