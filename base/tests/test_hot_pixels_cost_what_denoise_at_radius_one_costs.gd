## Hot Pixels costs what Denoise at radius 1 costs, through
## Apply and through the canvas's preview, at the start of its slider and at
## its default.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Both filters read the nine texels round each one and run on the same
## neighbourhood pass, so they should cost the same. A kernel that kept the eight
## neighbours in an array filled at a count known only at run time and bubble
## sorted it would put them in the GPU's local memory, and over a 4000 by 3000
## picture cost 1.2 to 1.5 times Denoise's GPU time at the default threshold and
## 1.7 to 2.1 times at 0, where nearly every texel of a photograph stands apart
## and is sorted. Hot Pixels reads within a tenth of Denoise at both.
##
## **The clock is the GPU's.** At this size the wall time of either filter on a
## desktop card is the CPU issuing about seventeen hundred dispatches, the same
## for both, so it cannot tell them apart. A pair of timestamps around the run,
## [KernelDriver.DispatchClock], times what the card did between them. Each
## figure is a ratio read from pairs, Hot Pixels and Denoise back to back,
## because the card's clock moves between runs and the two of one pair share
## it, as [method _paired] says.
##
## Sara has no Median filter, so the reference is Denoise at radius 1 and Mean,
## the other radius-one pass of the Noise family.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const HotPixelsFilter = preload("res://modules/sara-base-modules/base/usual/hot_pixels_filter.gd")
const DenoiseFilter = preload("res://modules/sara-base-modules/base/usual/denoise_filter.gd")
const KernelDriver := preload("res://harness/sa_kernel_driver.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const MODULE_DIR := "res://modules/sara-base-modules"

## The size of a photograph.
const SIZE := Vector2i(4000, 3000)
## How much more than Denoise Hot Pixels may take.
const ALLOWED := 1.25
## Pairs per figure, even so that either filter goes first in half of them. A
## pair now and then reads half or one and a half times what the rest read, when
## the clock moves inside it, and six to a half keep two such from moving a
## median.
const RUNS := 12
## The slider's start, where every texel unlike all its neighbours is taken out
## and so nearly every texel of the picture is sorted, the dearest place on it,
## and its default. Every place above the picture's grain does the default's
## work, the end of the slider included.
const THRESHOLDS: Array[int] = [0, 20]

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _dir_was_set: bool = false
var _clock := KernelDriver.DispatchClock.new()


func before_each() -> void:
    _dir_was_set = ModuleLoader.module_dirs.has(OWNER)
    if not _dir_was_set:
        ModuleLoader.module_dirs[OWNER] = MODULE_DIR
    _easel = Bench.easel(SIZE)
    _doc = _easel.document
    _layer = _doc.active_layer
    _photograph()


func after_each() -> void:
    _easel.compositor.point_preview.clear(_doc)
    _easel.free()
    _easel = null
    _doc = null
    _layer = null
    if not _dir_was_set:
        ModuleLoader.module_dirs.erase(OWNER)


## Every chunk of the canvas holds one tile of a photograph's grain, a few
## hundredths either way of a warm grey, with a bright texel in every
## thousand or so.
func _photograph() -> void:
    var side := _layer.get_or_create_chunk(Vector2i.ZERO).pixel_size()
    var width: int = SaFieldSpec.BYTES_PER_TEXEL.get(_layer.get_field(Vector2i.ZERO).format, 0)
    var tile := Image.create_empty(side, side, false, Image.FORMAT_RGBAF)
    var rng := RandomNumberGenerator.new()
    rng.seed = 24
    for y in side:
        for x in side:
            var grey := 0.4 + 0.05 * rng.randf()
            tile.set_pixel(x, y, Color(grey, grey * 0.9, grey * 0.8, 1.0))
    for i in 64:
        tile.set_pixel(rng.randi_range(0, side - 1), rng.randi_range(0, side - 1), Color(4.0, 4.0, 4.0, 1.0))
    if width == 8:
        tile.convert(Image.FORMAT_RGBAH)
    var bytes := tile.get_data()
    for gy in ceili(float(SIZE.y) / side):
        for gx in ceili(float(SIZE.x) / side):
            var grid := Vector2i(gx, gy)
            GlobalShaderCompiler.get_rd().texture_update(_layer.get_or_create_chunk(grid).albedo().rid, 0, bytes)
            _layer.mark_unresolved(grid)
    Bench.composite(_easel)


func _hot_pixels(threshold: int) -> SaFilter:
    var filter := HotPixelsFilter.new()
    filter.set_parameters({"threshold": threshold})
    return filter


func _denoise() -> SaFilter:
    var filter := DenoiseFilter.new()
    filter.set_parameters({"kind": "mean", "radius": 1, "threshold": 10})
    return filter


## The GPU's milliseconds for *filter* applied to the layer and undone again,
## so every run filters the same picture, or -1 when the card answered no time.
func _apply(filter: SaFilter) -> float:
    _settled()
    _clock.begin()
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, filter.title())
    SaFilterApply.call_run(filter, ctx)
    SaFilterApply.apply(ctx, filter.title())
    _clock.end()
    var answer := _clock.answer()
    _doc.undo_redo.undo()
    return -1.0 if answer["gpu_ms"] == null else float(answer["gpu_ms"])


## The GPU's milliseconds for *filter* previewed on the canvas over every
## chunk, as the dialog shows it while a slider moves, or -1 as above.
func _preview(filter: SaFilter) -> float:
    _settled()
    _clock.begin()
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, filter.title(), true)
    SaFilterApply.call_run(filter, ctx)
    _easel.compositor.point_preview.set_pass(_doc, ctx.point)
    _doc.invalidate_chunks(_layer.chunks.keys())
    _easel.request_composite()
    _easel.process_pending_composite()
    _clock.end()
    var answer := _clock.answer()
    return -1.0 if answer["gpu_ms"] == null else float(answer["gpu_ms"])


## Waits for what the card was handed before, so a run's pair holds its own
## work and none queued ahead of it.
func _settled() -> void:
    GlobalShaderCompiler.get_rd().texture_get_data(_layer.get_field(Vector2i.ZERO).rid, 0)


## How many times Denoise's time Hot Pixels at *threshold* took through
## *timed*, read from *RUNS* pairs, each pair the two run back to back. The
## card's clock drops to a fraction of its top between bursts and climbs again
## under load, so two runs apart can stand at clocks several times apart while
## the two of one pair share theirs, all but the climb, which favours whichever
## runs second. So half the pairs run Hot Pixels first and half Denoise, and the
## ratio is the geometric mean of the two halves' medians, in which the climb
## cancels. Each filter runs once first, which compiles its kernel. Answers the
## ratio and the least time each took, or nothing when the card answered no
## time.
func _paired(timed: Callable, threshold: int) -> Array[float]:
    timed.call(_hot_pixels(threshold))
    timed.call(_denoise())
    var halves: Array[PackedFloat64Array] = [PackedFloat64Array(), PackedFloat64Array()]
    var least := [INF, INF]
    for run in RUNS:
        var first := run % 2
        var against: float = timed.call(_denoise()) if first == 1 else 0.0
        var taken: float = timed.call(_hot_pixels(threshold))
        if first == 0:
            against = timed.call(_denoise())
        if taken <= 0.0 or against <= 0.0:
            return []
        halves[first].append(taken / against)
        least = [minf(least[0], taken), minf(least[1], against)]
    return [sqrt(_median(halves[0]) * _median(halves[1])), least[0], least[1]]


static func _median(values: PackedFloat64Array) -> float:
    values.sort()
    @warning_ignore("integer_division")
    var half := values.size() / 2
    if values.size() % 2 == 1:
        return values[half]
    return 0.5 * (values[half - 1] + values[half])


func _compare(timed: Callable, form: String) -> void:
    for threshold in THRESHOLDS:
        var figures := _paired(timed, threshold)
        if figures.is_empty():
            skip("the card here answers no timestamps, so no GPU time could be read")
            return
        # The figures go to the log whether or not they pass, so a run is a
        # measurement as well as a verdict.
        print(
            (
                "%s of Hot Pixels at %d %% at least %.2f ms, Denoise at radius 1 at least %.2f ms, %.2f times"
                % [form, threshold, figures[1], figures[2], figures[0]]
            )
        )
        assert_true(
            figures[0] <= ALLOWED,
            (
                (
                    "%s of Hot Pixels at %d %% takes %.2f times Denoise's GPU time at radius 1, "
                    + "at least %.2f ms against %.2f ms, within a quarter"
                )
                % [form, threshold, figures[0], figures[1], figures[2]]
            )
        )


func test_apply_costs_what_denoise_at_radius_one_costs() -> void:
    _compare(_apply, "Apply")


func test_a_preview_costs_what_denoise_at_radius_one_costs() -> void:
    _compare(_preview, "A preview")
