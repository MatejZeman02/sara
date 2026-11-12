## The perf form of the `measure` step: a window over the five
## ledgers that snapshots what is shared, clears only what is its own, and leaves
## one block behind for the dump and the door.
extends "res://tests/test_framework.gd"

## `end` draws two frames and the window's dispatch is a real composite.
const REQUIRES_GPU := true

const SOURCE := "res://core/perf/sa_perf_window.gd"

const WINDOW_KEYS: Array[String] = [
    "window", "device", "counters", "kernels", "gpu_time", "composite", "commit", "stroke", "frames", "copies", "vram", "startup"
]

## The easel whose document the step is handed, which is what the table hands it
## off the run.
var _easel: SaEasel


func before_each() -> void:
    SaPerfWindow.forget()
    _easel = SaEasel.create_default(Vector2i(64, 64))


func after_each() -> void:
    SaPerfWindow.forget()
    _easel.free()
    _easel = null


func _block_of(line: String) -> Dictionary:
    var prefix := "SaCapture: measure perf "
    assert_true(line.begins_with(prefix), "every answer starts with the run log's prefix: %s" % line.left(60))
    var parsed: Variant = JSON.parse_string(line.trim_prefix(prefix))
    return parsed if parsed is Dictionary else {}


func _composite_once() -> void:
    _easel.request_full_composite()
    _easel.process_pending_composite()


func test_a_window_folds_every_key_and_the_kernels_sum_to_the_counters() -> void:
    _composite_once()
    var shared_before: int = SaCompute.counters()["dispatches"]
    SaMeasure.capture(_easel.document, {"perf": "begin"})
    assert_true(SaGpuTiming.enabled, "the GPU timing flag is on inside a window")
    assert_true(int(SaCompute.counters()["dispatches"]) >= shared_before, "begin resets no shared counter")
    assert_eq(SaCompute.kernel_counters().is_empty(), false, "nor the per-kernel tally")

    _composite_once()
    var block := _block_of(SaMeasure.capture(_easel.document, {"perf": "end"}))
    assert_false(SaGpuTiming.enabled, "and off again once it has closed")

    for key: String in WINDOW_KEYS:
        assert_true(block.has(key), "the block carries %s" % key)
    assert_eq(block["window"]["open"], false, "a folded block is a closed window")
    assert_eq(int(block["window"]["forced_draws"]), 2, "end drew the device's frame delay before it folded")

    var dispatches := int(block["counters"]["dispatches"])
    assert_true(dispatches > 0, "the composite between begin and end was counted")
    var summed := 0
    for key: String in block["kernels"]:
        summed += int(block["kernels"][key]["dispatches"])
    assert_eq(summed, dispatches, "the kernels' dispatches sum to the window's")
    assert_eq(int(block["composite"]["count"]), 1, "one composite of the runner's easel")

    assert_eq(int(block["vram"]["sara_textures"]), SaTexture.allocated_bytes, "vram.sara_textures is the dump's vram_bytes")
    assert_true(block["vram"].has("sara_buffers") and block["vram"].has("history_bytes"), "with the two figures kept")
    # Through JSON and back, because a parsed 3 is 3.0 and the dump's is still 3.
    var kept: Variant = JSON.parse_string(JSON.stringify(SaPerfWindow.last_block))
    assert_eq(JSON.stringify(kept), JSON.stringify(block), "the dump's block is the printed one")


func test_a_second_begin_is_refused_and_the_first_window_stands() -> void:
    SaMeasure.capture(_easel.document, {"perf": "begin"})
    _composite_once()
    var refused := SaMeasure.capture(_easel.document, {"perf": "begin"})
    assert_true(refused.contains("refused"), "a begin inside a window is refused: %s" % refused)
    var block := _block_of(SaMeasure.capture(_easel.document, {"perf": "end"}))
    assert_true(int(block["counters"]["dispatches"]) > 0, "and the first window kept what it had counted")
    assert_true(SaMeasure.capture(_easel.document, {"perf": "end"}).contains("refused"), "an end with no window is refused too")
    assert_true(SaMeasure.capture(_easel.document, {"perf": "sideways"}).contains("refused"), "and so is a form nobody wrote")


func test_a_read_before_any_window_answers_the_boot_and_the_memory() -> void:
    assert_true(SaPerfWindow.last_block.is_empty(), "nothing measured, nothing in the dump")
    var block := _block_of(SaMeasure.capture(_easel.document, {"perf": "read"}))
    assert_true(block.has("startup") and block.has("vram") and block.has("device"), "the resting block")
    assert_false(block.has("counters"), "and no window's figures, because there was no window")
    assert_false(SaPerfWindow.last_block.is_empty(), "the read is kept for the dump")


func test_the_rect_form_still_answers() -> void:
    var line := SaMeasure.capture(_easel.document, {"rect": [0, 0, 8, 8]})
    assert_true(line.begins_with("SaCapture: measure {"), "a rectangle is still a rectangle: %s" % line.left(40))
    assert_true(line.contains('"of"'), "with what it looked at")


func test_the_file_reads_nothing_back_and_resets_nothing_shared() -> void:
    var source := FileAccess.get_file_as_string(SOURCE)
    assert_false(source.is_empty(), "the source is readable")
    for banned: String in ["texture_get_data", "buffer_get_data", "sync(", "reset_counters"]:
        assert_false(source.contains(banned), "sa_perf_window.gd holds no %s" % banned)
