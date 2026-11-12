## GPU time per kernel and per category, from timestamp pairs behind a flag.
##
## The counters say how often a kernel ran and the
## easel says what issuing a composite cost the CPU. This proves the third
## figure, what the card spent, arrives without a stall, stays inside the
## engine's pool of 256 captures a frame, and costs nothing while the flag is
## off.
extends "res://tests/test_framework.gd"

## Needs the main RenderingDevice, real lists and drawn frames.
const REQUIRES_GPU := true
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

## The files the pairs live in, which may never wait for the card.
const TIMED_FILES: Array[String] = [
    "res://core/perf/sa_gpu_timing.gd",
    "res://core/custom-shader/sa_dispatch_list.gd",
    "res://core/composite/sa_easel.gd",
    "res://core/api/document/sa_document.gd",
]

## The selection mask the paint kernel binds, held for the length of one test.
var _mask: SaTexture = null


func before_each() -> void:
    SaGpuTiming.enabled = false
    SaGpuTiming.reset()


func after_each() -> void:
    _mask = null
    SaGpuTiming.enabled = false
    SaGpuTiming.reset()


## Flag on, one dispatch, a few drawn frames: the kernel's key carries a pair
## with a positive GPU delta, read two frames late and never waited for.
func test_one_dispatch_resolves_to_a_pair_under_its_key() -> void:
    var comp := _paint()
    var canvas := SaTexture.new(Vector2i(64, 64))
    _bind(comp, canvas)
    SaGpuTiming.enabled = true
    comp.dispatch_kernel("paint", 8, 8, 1)
    _draw_and_collect()

    var block := SaGpuTiming.block()
    assert_eq(str(block["device"]), "main", "The suite runs on the main device, the one whose captures resolve")
    var kernels: Dictionary = block["kernels"]
    assert_true(kernels.has(PaintKernel.NAME + "/paint"), "The pair is filed under the tally's own key")
    if kernels.has(PaintKernel.NAME + "/paint"):
        var entry: Dictionary = kernels[PaintKernel.NAME + "/paint"]
        assert_true(int(entry["pairs"]) >= 1, "At least one pair resolved")
        assert_true(int(entry["gpu_ticks"]) > 0, "and the card spent a positive time between its two stamps")
    assert_true(int(block["readable_after_min"]) >= 0, "and the block says how many drawn frames late the entry was read")
    assert_eq(int(block["ticks_per_usec"]) in [0, 1, 1000], true, "The divisor is one of the two units, or unknown on one pair")
    assert_eq(int(block["skipped"]), 0, "One list is nowhere near the pool")


## Flag off is the painter's path: nothing is captured and nothing is kept.
func test_flag_off_captures_nothing() -> void:
    var comp := _paint()
    var canvas := SaTexture.new(Vector2i(64, 64))
    _bind(comp, canvas)
    comp.dispatch_kernel("paint", 8, 8, 1)
    SaGpuTiming.category_begin("composite")
    SaGpuTiming.category_end("composite", {"dirty_chunks": 1})
    SaGpuTiming.enabled = true
    _draw_and_collect()

    var block := SaGpuTiming.block()
    assert_eq((block["kernels"] as Dictionary).size(), 0, "No kernel entry was made with the flag off")
    assert_eq((block["categories"] as Dictionary).size(), 0, "and no category entry either")
    assert_eq(int(block["frames_collected"]), 0, "so no later frame holds a capture of ours")


## 300 lists in one frame is more than the pool of 256. The pairs that do not
## fit are counted and never reach the engine, and the category pair around
## them still resolves, because it draws on its own reserve.
func test_an_overfull_frame_skips_pairs_and_keeps_its_category() -> void:
    var comp := _paint()
    var canvas := SaTexture.new(Vector2i(64, 64))
    _bind(comp, canvas)
    SaGpuTiming.enabled = true
    # The frame's budget may be part spent by whatever the runner did since the
    # last draw, so start from a fresh drawn frame.
    RenderingServer.force_draw(false)
    SaGpuTiming.reset()
    SaGpuTiming.category_begin("composite")
    for i: int in 300:
        comp.dispatch_kernel("paint", 1, 1, 1)
    SaGpuTiming.category_end("composite", {"dirty_chunks": 300})
    _draw_and_collect()

    var block := SaGpuTiming.block()
    var entry: Dictionary = (block["kernels"] as Dictionary).get(PaintKernel.NAME + "/paint", {})
    assert_true(int(entry.get("skipped", 0)) > 0, "Pairs past the ceiling are counted as skipped")
    var accounted := int(entry.get("skipped", 0)) + int(entry.get("pairs", 0))
    assert_eq(accounted, 300, "and every list is either timed or counted, none lost")
    var category: Dictionary = (block["categories"] as Dictionary).get("composite", {})
    assert_eq(int(category.get("pairs", 0)), 1, "The category pair still resolved, out of its reserve")
    assert_true(int(category.get("gpu_ticks", 0)) > 0, "with a positive time of its own")
    assert_eq(int((category.get("load", {}) as Dictionary).get("dirty_chunks", 0)), 300, "and the load it was handed")


## A fifth category pair in one frame is past the reserve of eight captures. It
## is counted, its load is still summed, and no half pair is left open.
func test_the_category_reserve_is_four_pairs_a_frame() -> void:
    SaGpuTiming.enabled = true
    RenderingServer.force_draw(false)
    SaGpuTiming.reset()
    for i: int in 5:
        SaGpuTiming.category_begin("commit")
        SaGpuTiming.category_end("commit", {"chunks": 2})
    _draw_and_collect()

    var category: Dictionary = (SaGpuTiming.block()["categories"] as Dictionary).get("commit", {})
    assert_eq(int(category.get("pairs", 0)), 4, "Four pairs fit the reserve")
    assert_eq(int(category.get("skipped", 0)), 1, "and the fifth is counted")
    var work: Dictionary = category.get("load", {})
    assert_eq(int(work.get("chunks", 0)), 10, "The load is CPU knowledge and is kept for all five")


## The block is a copy, so a reader cannot move the ledger.
func test_the_block_is_a_copy() -> void:
    SaGpuTiming.enabled = true
    SaGpuTiming.category_begin("commit")
    SaGpuTiming.category_end("commit", {"chunks": 1})
    var block := SaGpuTiming.block()
    (block["categories"] as Dictionary).clear()
    assert_eq((SaGpuTiming.block()["categories"] as Dictionary).size(), 1, "Clearing the copy leaves the ledger as it was")
    _draw_and_collect()


## Hard rule 1 and the no-stall promise, as a scan: the files the pairs live in
## never wait for the card and never read a texture back.
func test_the_timed_files_never_stall_or_read_back() -> void:
    for path: String in TIMED_FILES:
        var source := FileAccess.get_file_as_string(path)
        assert_true(source != "", "The scan reached %s" % path)
        for banned: String in [".sync(", ".submit(", "texture_get_data"]:
            assert_false(_code_of(source).contains(banned), "%s contains %s" % [path, banned])


## The engine refuses a capture while a list is open, so the pair brackets the
## list from outside and nothing else in these files captures at all.
func test_no_capture_sits_inside_an_open_list() -> void:
    var list := _code_of(FileAccess.get_file_as_string("res://core/custom-shader/sa_dispatch_list.gd"))
    assert_false(list.contains("capture_timestamp"), "The list captures through the ledger, never by itself")
    var pair_begin := list.find("list_pair_begin(")
    var list_begin := list.find("compute_list_begin(")
    var list_end := list.find("compute_list_end(")
    var pair_end := list.find("list_pair_end(")
    assert_true(pair_begin >= 0 and pair_begin < list_begin, "The pair opens before the list does")
    assert_true(list_end >= 0 and list_end < pair_end, "and closes after the list has")
    for path: String in ["res://core/composite/sa_easel.gd", "res://core/api/document/sa_document.gd"]:
        assert_false(_code_of(FileAccess.get_file_as_string(path)).contains("capture_timestamp"), "%s captures by itself" % path)


func _paint() -> SaCompute:
    return PaintKernel.compute()


## Binds what the paint kernel needs. The mask is kept on the suite, because the
## dispatches need it alive and the test has no other use for it.
func _bind(comp: SaCompute, canvas: SaTexture) -> void:
    comp.set_texture(0, canvas.rid)
    _mask = SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    _mask.clear(Color(1.0, 1.0, 1.0, 1.0))
    comp.set_texture(SaSelection.BINDING, _mask.rid)
    var params := PackedFloat32Array()
    params.resize(16)
    comp.set_push_constant_float_array(params)


## As many forced draws as the device keeps frames, which is what brings the
## ring back to the slot that captured, and no more. The draws do not present,
## because a present waits on the compositor and a silent one hung the run,
## and the device's frame moves all the same.
func _draw_and_collect() -> void:
    for i: int in RenderingServer.get_rendering_device().get_frame_delay():
        RenderingServer.force_draw(false)
        SaGpuTiming.collect()


## *source* without its comment lines, so a sentence about a stall is not one.
func _code_of(source: String) -> String:
    var kept := PackedStringArray()
    for line: String in source.split("\n"):
        if not line.strip_edges().begins_with("#"):
            kept.append(line)
    return "\n".join(kept)
