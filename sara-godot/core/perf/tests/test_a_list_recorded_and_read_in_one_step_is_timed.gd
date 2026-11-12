## A list recorded and read inside one step has its GPU time and
## the time the CPU waited for it.
##
## The wand floods in rounds of lists, each round read back before the next is
## recorded, all inside one step and no drawn frame between. Every read flushes
## the device into its next frame slot, and nothing folded the
## captures a slot handed back before the next read replaced them, so the
## window read every wand kernel `untimed` and a split needed
## a probe of its own. This suite is the wand's shape with the paint
## fixture: five lists, each read, then the window's own draws.
extends "res://tests/test_framework.gd"

## Needs the main RenderingDevice, real lists and real reads.
const REQUIRES_GPU := true
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

## Lists recorded and read in the one step, as many as the wand's reads a click.
const ROUNDS := 5

const KEY := PaintKernel.NAME + "/paint"

## What the paint kernel binds, held for the length of one test.
var _canvas: SaTexture = null
var _mask: SaTexture = null


func before_each() -> void:
    SaGpuTiming.enabled = false
    SaGpuTiming.reset()


func after_each() -> void:
    _canvas = null
    _mask = null
    SaGpuTiming.enabled = false
    SaGpuTiming.reset()


## Every list of the step is timed once the device has handed back its last
## slot, none lost to the read after it, and the reads' wait is filed under the
## list each followed.
func test_every_list_read_in_the_step_is_timed_and_its_wait_kept() -> void:
    var comp := _paint()
    var buffer := SaCompute.Buffer.new(PackedInt32Array([0, 0, 0, 0]).to_byte_array())
    SaGpuTiming.enabled = true
    RenderingServer.force_draw(false)
    SaGpuTiming.reset()
    for i: int in ROUNDS:
        comp.dispatch_kernel("paint", 8, 8, 1)
        buffer.read()
    var inside: Dictionary = (SaGpuTiming.block()["kernels"] as Dictionary).get(KEY, {})
    assert_true(int(inside.get("pairs", 0)) >= 1, "Pairs resolved inside the step, from the reads alone, with no frame drawn")
    _draw_and_collect()

    var block := SaGpuTiming.block()
    var entry: Dictionary = (block["kernels"] as Dictionary).get(KEY, {})
    assert_eq(int(entry.get("pairs", 0)), ROUNDS, "Every list recorded and read in the step resolved to one pair")
    assert_true(int(entry.get("gpu_ticks", 0)) > 0, "with a positive time on the card")
    assert_eq(int(entry.get("skipped", 0)), 0, "and none was skipped")
    var reads: Dictionary = (block["reads"] as Dictionary).get(KEY, {})
    assert_eq(int(reads.get("reads", 0)), ROUNDS, "Each read is filed under the list it followed")
    assert_true(int(reads.get("wait_usec", 0)) > 0, "with the time the CPU waited in it")
    assert_true(int(reads.get("wait_usec_max", 0)) <= int(reads.get("wait_usec", 0)), "and its longest no more than the sum")


## Flag off is the painter's path, and the wand's too: a read keeps nothing.
func test_a_read_with_the_flag_off_keeps_nothing() -> void:
    var comp := _paint()
    var buffer := SaCompute.Buffer.new(PackedInt32Array([0, 0, 0, 0]).to_byte_array())
    comp.dispatch_kernel("paint", 8, 8, 1)
    buffer.read()
    var block := SaGpuTiming.block()
    assert_eq((block["reads"] as Dictionary).size(), 0, "No read was kept with the flag off")
    assert_eq((block["kernels"] as Dictionary).size(), 0, "and no pair either")


## The window carries the reads, summed in `gpu_time` and by list in `reads`,
## which is the line `sara_perf.py` prints as a window's reads and wait.
func test_the_window_sums_the_reads_and_their_wait() -> void:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    var comp := _paint()
    var buffer := SaCompute.Buffer.new(PackedInt32Array([0, 0, 0, 0]).to_byte_array())
    SaPerfWindow.forget()
    SaMeasure.capture(easel.document, {"perf": "begin"})
    for i: int in ROUNDS:
        comp.dispatch_kernel("paint", 8, 8, 1)
        buffer.read()
    SaMeasure.capture(easel.document, {"perf": "end"})
    var block := SaPerfWindow.last_block
    SaPerfWindow.forget()
    easel.free()

    var gpu_time: Dictionary = block["gpu_time"]
    assert_eq(int(gpu_time.get("reads", 0)), ROUNDS, "The window counts the step's reads")
    assert_true(int(gpu_time.get("read_wait_usec", 0)) > 0, "and the time they waited")
    assert_eq(int((block["reads"] as Dictionary).get(KEY, {}).get("reads", 0)), ROUNDS, "and keeps them by list")
    var entry: Dictionary = (block["kernels"] as Dictionary).get(KEY, {})
    assert_eq(int(entry.get("pairs", 0)), ROUNDS, "Every list of the step has its GPU time in the window")


func _paint() -> SaCompute:
    var comp := PaintKernel.compute()
    _canvas = SaTexture.new(Vector2i(64, 64))
    comp.set_texture(0, _canvas.rid)
    _mask = SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    _mask.clear(Color(1.0, 1.0, 1.0, 1.0))
    comp.set_texture(SaSelection.BINDING, _mask.rid)
    var params := PackedFloat32Array()
    params.resize(16)
    comp.set_push_constant_float_array(params)
    return comp


## As many forced draws as the device keeps frames, which hands back the slots
## the last reads left, without a present.
func _draw_and_collect() -> void:
    for i: int in RenderingServer.get_rendering_device().get_frame_delay():
        RenderingServer.force_draw(false)
        SaGpuTiming.collect()
