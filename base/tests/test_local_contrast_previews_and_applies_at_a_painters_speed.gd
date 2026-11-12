## Local Contrast previews and applies at a speed a painter
## can work with.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const LocalContrastFilter = preload("res://modules/sara-base-modules/base/filters/local_contrast/local_contrast_filter.gd")
const KernelDriver := preload("res://harness/sa_kernel_driver.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const MODULE_DIR := "res://modules/sara-base-modules"
const PHOTOGRAPH := "res://scenarios/references/a-photograph.jpg"
const SIZE := Vector2i(1920, 1080)
const RUNS := 7

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


func _photograph() -> void:
    var whole := Image.load_from_file(ProjectSettings.globalize_path(PHOTOGRAPH))
    whole.convert(Image.FORMAT_RGBAF)
    var side := _layer.get_or_create_chunk(Vector2i.ZERO).pixel_size()
    var width: int = SaFieldSpec.BYTES_PER_TEXEL.get(_layer.get_field(Vector2i.ZERO).format, 0)
    var top := int((whole.get_height() - SIZE.y) / 2.0)
    for gy in ceili(float(SIZE.y) / side):
        for gx in ceili(float(SIZE.x) / side):
            var grid := Vector2i(gx, gy)
            var tile := Image.create_empty(side, side, false, Image.FORMAT_RGBAF)
            var from := Rect2i(gx * side, top + gy * side, side, side).intersection(Rect2i(0, top, SIZE.x, SIZE.y))
            tile.blit_rect(whole, from, Vector2i.ZERO)
            if width == 8:
                tile.convert(Image.FORMAT_RGBAH)
            GlobalShaderCompiler.get_rd().texture_update(_layer.get_or_create_chunk(grid).albedo().rid, 0, tile.get_data())
            _layer.mark_unresolved(grid)
    Bench.composite(_easel)


func _settled() -> void:
    GlobalShaderCompiler.get_rd().texture_get_data(_layer.get_field(Vector2i.ZERO).rid, 0)


func _preview(filter: SaFilter) -> Array[float]:
    _settled()
    var started := Time.get_ticks_usec()
    _clock.begin()
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, filter.title(), true)
    SaFilterApply.call_run(filter, ctx)
    _easel.compositor.point_preview.set_pass(_doc, ctx.point)
    _doc.invalidate_chunks(_layer.chunks.keys())
    _easel.request_composite()
    _easel.process_pending_composite()
    _clock.end()
    var issued := Time.get_ticks_usec()
    var answer := _clock.answer()
    var done := Time.get_ticks_usec()
    var gpu := -1.0 if answer["gpu_ms"] == null else float(answer["gpu_ms"])
    return [(issued - started) / 1000.0, (done - started) / 1000.0, gpu]


func _apply(filter: SaFilter) -> Array[float]:
    _settled()
    var started := Time.get_ticks_usec()
    _clock.begin()
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, filter.title())
    SaFilterApply.call_run(filter, ctx)
    SaFilterApply.apply(ctx, filter.title())
    _clock.end()
    var issued := Time.get_ticks_usec()
    var answer := _clock.answer()
    var done := Time.get_ticks_usec()
    _doc.undo_redo.undo()
    var gpu := -1.0 if answer["gpu_ms"] == null else float(answer["gpu_ms"])
    return [(issued - started) / 1000.0, (done - started) / 1000.0, gpu]


## A measurement harness rather than a bar it must clear: the run is timed on
## the machine it runs on, and a wall-clock ceiling here would flake under
## parallel test slots the way the Hot Pixels suite's own numbers could. What it asserts is that each run
## happened and that the device
## timed its dispatches, so a null timestamp cannot be read as a fast run.
func test_times() -> void:
    var filter := LocalContrastFilter.new()
    for form: String in ["preview", "apply"]:
        var timed: Callable = _preview if form == "preview" else _apply
        timed.call(filter)
        for run in RUNS:
            var t: Array[float] = timed.call(filter)
            print("%s issued %.1f ms, done %.1f ms, gpu %.1f ms" % [form, t[0], t[1], t[2]])
            assert_true(t[1] > 0.0, "the %s run was timed, %.1f ms" % [form, t[1]])
            assert_true(t[2] > 0.0, "and the device timed its dispatch, %.1f ms" % t[2])
