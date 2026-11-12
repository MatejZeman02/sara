## A `kernel` step answers `gpu_ms`, the GPU time of its
## dispatch alone, timed by a pair of timestamps around the kernel's compute
## list and read inside the step, and a device that answers no timestamps says
## so rather than answering 0.
##
## Built like the kernel read suite: the driver with no run, handed the document. The
## round trip a suite can see is the wall time of the step itself, which is
## less than the one Python sees and still has to be more than the dispatch.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const KernelDriver := preload("res://harness/sa_kernel_driver.gd")


## A clock on a device whose frame comes back with no timestamps in it.
class NoStamps:
    extends KernelDriver.DispatchClock

    func _collected(_rd: RenderingDevice) -> Dictionary:
        return {}


## A box blur, whose cost grows with the square of `radius`.
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

const CANVAS := Vector2i(1024, 1024)

var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _easel = SaEasel.create_default(CANVAS)
    _doc = _easel.document
    var layer := SaLayerOps.new(_doc).add(&"", null)
    layer.name = "Paint"
    for y in range(4):
        for x in range(4):
            layer.get_or_create_chunk(Vector2i(x, y)).clear(Color(0.2, 0.4, 0.6, 1.0))


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


## Runs the blur at *radius* over the whole canvas into `Out` through *driver*,
## and answers the verdict with the step's own wall time beside it.
func _blur(driver: KernelDriver, radius: int) -> Dictionary:
    var spec := {"source": BOX, "name": "box", "layer": "Paint", "rect": [0, 0, CANVAS.x, CANVAS.y], "params": {"radius": radius}}
    var began := Time.get_ticks_usec()
    var verdict := driver.run_on(_doc, spec)
    verdict["wall_ms"] = float(Time.get_ticks_usec() - began) / 1000.0
    return verdict


func test_a_run_answers_a_positive_gpu_time_below_its_round_trip() -> void:
    var driver := KernelDriver.new(null)
    _blur(driver, 1)

    var verdict := _blur(driver, 1)

    assert_true(bool(verdict["ok"]), "the kernel ran: %s" % [verdict])
    assert_true(verdict.has("gpu_ms"), "the answer carries the GPU time: %s" % [verdict])
    assert_true(verdict["gpu_ms"] != null, "the device here answers timestamps: %s" % [verdict.get("gpu_unknown")])
    var gpu_ms := float(verdict["gpu_ms"])
    assert_true(gpu_ms > 0.0, "the dispatch took some time: %s ms" % gpu_ms)
    assert_true(
        gpu_ms < float(verdict["wall_ms"]), "and less than the step around it, %s ms against %s ms" % [gpu_ms, verdict["wall_ms"]]
    )
    assert_false(verdict.has("gpu_unknown"), "with no reason beside a time it has")


## The pair is around the kernel and not the gather or the write, which are
## the same copies whatever the radius: a blur of radius 12 reads 625 texels a
## pixel where radius 0 reads one.
func test_the_time_is_the_kernels_own() -> void:
    var driver := KernelDriver.new(null)
    _blur(driver, 0)

    var light := _blur(driver, 0)
    var heavy := _blur(driver, 12)

    assert_true(light["gpu_ms"] != null and heavy["gpu_ms"] != null, "both were timed: %s, %s" % [light, heavy])
    assert_true(
        float(heavy["gpu_ms"]) > 4.0 * float(light["gpu_ms"]),
        "a kernel 625 times the reads takes longer, %s ms against %s ms" % [heavy["gpu_ms"], light["gpu_ms"]]
    )


func test_a_device_with_no_timestamps_says_so_rather_than_answering_zero() -> void:
    var driver := KernelDriver.new(null, NoStamps.new())

    var verdict := _blur(driver, 1)

    assert_true(bool(verdict["ok"]), "the kernel still ran and wrote: %s" % [verdict])
    assert_eq(int(verdict["chunks"]), 16, "every chunk of the canvas")
    assert_true(verdict.has("gpu_ms") and verdict["gpu_ms"] == null, "the GPU time is null, never 0: %s" % [verdict])
    assert_eq(
        String(verdict.get("gpu_unknown", "")), "the device answered no timestamps for the dispatch", "and the answer says why"
    )


func test_a_compile_alone_answers_no_gpu_time() -> void:
    var driver := KernelDriver.new(null)

    var verdict := driver.run_on(_doc, {"source": BOX, "name": "box", "run": false})

    assert_true(bool(verdict["ok"]), "the kernel compiled: %s" % [verdict])
    assert_false(verdict.has("gpu_ms"), "nothing was dispatched, so nothing was timed")
