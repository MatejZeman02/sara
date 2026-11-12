## A neighbourhood pass, every step of it, goes out in pieces
## of at most `SaFilterContext.SUBMIT_TEXELS` threads, and the texels it writes
## are the ones a single dispatch of each step writes, bit for bit.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The point passes were cut first, and the neighbourhood passes waited, since
## local contrast's pyramid counts the threads of a level from the region's
## corner on that level, so a piece handed its corner in the frame wrote some
## texels of a level twice. Each case runs one filter's recorded pass through
## a runner that cuts at the bound and through one that never cuts, on a chunk
## of a layer at twice the document's resolution, 512 texels on a side, so the
## last step alone is four pieces.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const LocalContrastFilter = preload("res://modules/sara-base-modules/base/filters/local_contrast/local_contrast_filter.gd")
const MirrorFilter = preload("res://modules/sara-base-modules/base/usual/mirror_filter.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const MODULE_DIR := "res://modules/sara-base-modules"
## Two chunks side by side, so the painted chunk has a neighbour to pad from.
const CANVAS := Vector2i(512, 256)
const GRIDS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
## A side no region of the suite reaches, which leaves a dispatch whole.
const UNCUT := 1 << 14

var _easel: SaEasel = null
var _layer: SaLayer = null
var _dir_was_set: bool = false


func before_each() -> void:
    _dir_was_set = ModuleLoader.module_dirs.has(OWNER)
    if not _dir_was_set:
        ModuleLoader.module_dirs[OWNER] = MODULE_DIR


func after_each() -> void:
    _layer = null
    if _easel != null:
        _easel.free()
        _easel = null
    if not _dir_was_set:
        ModuleLoader.module_dirs.erase(OWNER)


## A fresh easel whose active layer is at *scale*, its two chunks grain over a
## ramp, the same picture every run.
func _open(scale: float) -> void:
    _easel = Bench.easel(CANVAS)
    var doc := _easel.document
    _layer = SaLayerOps.new(doc).add(&"", null, scale)
    doc.active_layer = _layer
    var rng := RandomNumberGenerator.new()
    rng.seed = 108
    for grid_pos: Vector2i in GRIDS:
        var chunk := _layer.get_or_create_chunk(grid_pos)
        var texture := chunk.albedo()
        var side := chunk.pixel_size()
        var image := Image.create_empty(side, side, false, Image.FORMAT_RGBAF)
        for y in side:
            for x in side:
                var v := 0.2 + 0.6 * float(x) / float(side) + rng.randf_range(-0.1, 0.1)
                image.set_pixel(x, y, Color(v, v * 0.8 + 0.1 * sin(y * 0.2), 1.0 - v, 1.0))
        if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
            image.convert(Image.FORMAT_RGBAH)
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    doc.invalidate_chunks(_layer.chunks.keys())


## *filter*'s recorded pass over the whole first chunk through *runner*, into
## a texture of its own, as the bytes the GPU holds.
func _ran(filter: SaFilter, runner: SaNeighbourhoodPass.Runner) -> PackedByteArray:
    var ctx := SaFilterContext.new(_easel.document, _layer, OWNER, "neighbourhood")
    filter.run(ctx)
    var recorded := ctx.point as SaNeighbourhoodPass
    assert_not_null(recorded, "%s records a neighbourhood pass" % filter.get_class())
    if recorded == null:
        return PackedByteArray()
    var compute := ctx.kernel(recorded.shader)
    var center := _layer.get_field(GRIDS[0])
    var target := SaTexture.new(center.size, center.format)
    var mask := _easel.document.selection.texture_for(GRIDS[0])
    runner.reads_canvas_of(_easel.document)
    runner.run(recorded, compute, target, center, _layer.get_field, GRIDS[0], Rect2i(Vector2i.ZERO, center.size), mask)
    return GlobalShaderCompiler.get_rd().texture_get_data(target.rid, 0)


func test_local_contrasts_pyramid_goes_out_in_pieces_and_writes_what_one_dispatch_writes() -> void:
    _open(2.0)
    assert_eq(_layer.get_field(GRIDS[0]).size.x, 512, "The chunk is 512 texels on a side")
    var filter := LocalContrastFilter.new()
    filter.set_parameters({"detail": 180, "highlights": 60, "shadows": 60, "midtone_range": 0.5})
    var whole := _ran(filter, SaNeighbourhoodPass.Runner.new(UNCUT))
    SaFilterContext.count_submits_from_zero()
    var cut := _ran(filter, SaNeighbourhoodPass.Runner.new())
    var steps := 2 * LocalContrastFilter.LEVELS - 1
    assert_true(
        SaFilterContext.submitted > steps,
        "The %d steps went out as %d pieces, more than one a step" % [steps, SaFilterContext.submitted]
    )
    assert_true(
        SaFilterContext.largest_submit <= SaFilterContext.SUBMIT_TEXELS,
        "and the largest held %d threads, inside the bound" % SaFilterContext.largest_submit
    )
    assert_false(whole.is_empty(), "The single dispatches wrote the chunk")
    assert_true(cut == whole, "and the pieces wrote the same bytes, texel for texel")


func test_a_two_step_blur_goes_out_in_pieces_and_writes_what_one_dispatch_writes() -> void:
    _open(2.0)
    var filter := SaGaussianBlurFilter.new()
    filter.set_parameters({"radius": 12.0})
    var whole := _ran(filter, SaNeighbourhoodPass.Runner.new(UNCUT))
    SaFilterContext.count_submits_from_zero()
    var cut := _ran(filter, SaNeighbourhoodPass.Runner.new())
    assert_true(SaFilterContext.submitted >= 4, "The blur went out as %d pieces" % SaFilterContext.submitted)
    assert_true(
        SaFilterContext.largest_submit <= SaFilterContext.SUBMIT_TEXELS,
        "and the largest held %d threads, inside the bound" % SaFilterContext.largest_submit
    )
    assert_true(cut == whole, "The pieces wrote the bytes one dispatch writes")


func test_a_whole_node_pass_goes_out_in_pieces_and_writes_what_one_dispatch_writes() -> void:
    _open(1.0)
    var filter := MirrorFilter.new()
    var ctx := SaFilterContext.new(_easel.document, _layer, OWNER, "neighbourhood")
    filter.run(ctx)
    var recorded := ctx.point as SaNeighbourhoodPass
    assert_true(recorded != null and recorded.whole(), "The mirror records a pass over the whole node")
    if recorded == null:
        return
    var compute := ctx.kernel(recorded.shader)
    var mask := _easel.document.selection.texture_for(GRIDS[0])
    var format := _layer.get_field(GRIDS[0]).format
    var out: Array[PackedByteArray] = []
    for side: int in [UNCUT, SaFilterContext.SUBMIT_SIDE]:
        var runner := SaNeighbourhoodPass.Runner.new(side)
        var gathered := runner.gather(_layer.chunks.keys(), _layer.get_field, format)
        var target := SaTexture.new(CANVAS, format)
        SaFilterContext.count_submits_from_zero()
        runner.run_whole(recorded, compute, target, gathered, Vector2i.ZERO, Rect2i(Vector2i.ZERO, CANVAS), mask)
        out.append(GlobalShaderCompiler.get_rd().texture_get_data(target.rid, 0))
    assert_eq(SaFilterContext.submitted, 2, "The canvas of two chunks went out as two pieces")
    assert_true(out[1] == out[0], "and they wrote the bytes one dispatch writes")
