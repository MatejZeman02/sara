## The Hue Saturation Lightness dialog previews over the part
## of the canvas the view shows, and every dispatch of its preview covers at
## most `SaFilterContext.SUBMIT_TEXELS`, with the same texels as one dispatch.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A weak Windows laptop lost Sara in this dialog to a fault in
## Intel's Vulkan driver, after the main thread had stood 7.9 s in it. The
## suite holds the three things the fix builds or finds: the canvas preview
## reaches the chunks the window shows and holds the rest, no dispatch of the
## preview or the thumbnail is larger than the bound, and the dialog opens on a
## reduced picture of the layer rather than a copy of it at its own size.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const HueFilter = preload("res://modules/sara-base-modules/base/filters/hue_saturation_lightness_filter.gd")
const PointAdjust = preload("res://modules/sara-base-modules/base/filters/sa_point_adjust.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const MODULE_DIR := "res://modules/sara-base-modules"
## Eight chunks on a side, painted whole, so the layer is larger than the view.
const SIZE := Vector2i(2048, 2048)
const PAINT := Color(0.7, 0.3, 0.2, 1.0)
## The view shows the top left quarter of the canvas.
const SHOWN := Rect2(0.0, 0.0, 1024.0, 1024.0)
## The kernel's key in `SaCompute`'s tally.
const KERNEL := "sara-base-modules/adjust/hue_saturation_lightness"

var _easel: SaEasel = null
var _doc: SaDocument = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
var _host: Node = null
var _registry: SaFilterRegistry = null
var _key: StringName = &""
var _was_embedding: bool = false
var _dir_was_set: bool = false
var _was_on_canvas: bool = true


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _was_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true
    _dir_was_set = ModuleLoader.module_dirs.has(OWNER)
    if not _dir_was_set:
        ModuleLoader.module_dirs[OWNER] = MODULE_DIR
    _was_on_canvas = SaSettings.filter_preview_on_canvas
    SaSettings.filter_preview_on_canvas = true

    _host = Node.new()
    _host.name = "U108TestHost"
    EventBus.add_child(_host)

    _easel = Bench.easel(SIZE)
    _doc = _easel.document
    _doc.fill_layer(PAINT, _doc.active_layer)
    Bench.composite(_easel)
    _easel.shown_rect = func() -> Rect2: return SHOWN

    _canvas = SaCanvas.new()
    _canvas.easel = _easel

    var filter := HueFilter.new()
    _key = SaFilterRegistry.key_for(OWNER, filter)
    _registry = SaFilterRegistry.new()
    _registry.register(filter, OWNER)

    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.watch(_registry)
    _host.add_child(_window)


func after_each() -> void:
    Teardown.free_nodes([_window, _canvas, _easel])
    _window = null
    _canvas = null
    _easel = null
    _doc = null
    _registry = null
    if _host != null:
        _host.free()
        _host = null
    SaSettings.filter_preview_on_canvas = _was_on_canvas
    if not _dir_was_set:
        ModuleLoader.module_dirs.erase(OWNER)
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _was_embedding


## The bound and the cut, read off the constants: a chunk's worth of texels, and
## a region larger than that cut into pieces that cover it once.
func test_a_region_is_cut_into_pieces_no_larger_than_the_bound_that_cover_it_once() -> void:
    assert_eq(SaFilterContext.SUBMIT_TEXELS, 65536, "the bound is 256 by 256 texels")
    assert_eq(SaFilterContext.SUBMIT_SIDE * SaFilterContext.SUBMIT_SIDE, SaFilterContext.SUBMIT_TEXELS, "a piece's side squared")
    var region := Rect2i(37, 11, 700, 300)
    var pieces := SaFilterContext.submits(region)
    var area := 0
    for piece: Rect2i in pieces:
        assert_true(piece.get_area() <= SaFilterContext.SUBMIT_TEXELS, "%s is inside the bound" % [piece])
        assert_true(region.encloses(piece), "and inside the region")
        if piece.end.x < region.end.x:
            assert_eq(piece.size.x % SaCompute.WORKGROUP_SIZE, 0, "a piece inside the region ends on a group's edge")
        area += piece.get_area()
    assert_eq(area, region.get_area(), "the pieces cover every texel once")
    assert_eq(pieces.size(), 6, "three across and two down")
    assert_true(SaFilterContext.submits(Rect2i(0, 0, 0, 5)).is_empty(), "and an empty region is no piece")


## The dialog opens on a picture of the layer reduced to the thumbnail's size,
## rather than copying the layer whole at its own size first.
func test_the_dialog_opens_on_a_reduced_picture_of_the_layer() -> void:
    _window.open_filter(_key)
    var thumbnail := _window.dialog.preview_control
    assert_not_null(thumbnail, "Hue/Saturation/Lightness declares a picture")
    var shown: Dictionary = thumbnail.describe()
    var measured: Array = shown.get("texture_size", [0, 0])
    var side := maxi(int(measured[0]), int(measured[1]))
    assert_true(side > 0, "the picture holds a texture")
    assert_true(side <= SaFilterPreview.REDUCED_SIDE, "no larger than the thumbnail's side, %d" % side)


## A slider frame over a layer painted across the whole canvas, with the view on
## a quarter of it, runs the kernel over the chunks the window reaches and holds
## the rest, and every dispatch of it, the thumbnail's among them, went through
## the cut and covers at most the bound.
func test_a_slider_frame_runs_over_the_visible_chunks_in_pieces_inside_the_bound() -> void:
    _window.open_filter(_key)
    _easel.process_pending_composite()
    SaCompute.reset_counters()
    SaFilterContext.count_submits_from_zero()

    var row := _window.dialog.row(&"hue")
    assert_not_null(row, "the dialog has its Hue slider")
    _window.compressor.reset()
    row.drive(40.0)
    _window.dialog.flush_rerun()
    if _window.compressor.pending:
        _window.compressor.timeout.emit()
    _easel.process_pending_composite()

    var tally: Dictionary = SaCompute.kernel_counters().get(KERNEL, {})
    var dispatched := int(tally.get("dispatches", 0))
    assert_true(dispatched > 0, "the frame ran the filter")
    assert_eq(dispatched, SaFilterContext.submitted, "every dispatch of the kernel went through the cut")
    assert_true(
        SaFilterContext.largest_submit <= SaFilterContext.SUBMIT_TEXELS,
        "and the largest covered %d texels, inside the bound" % SaFilterContext.largest_submit
    )

    var window := SHOWN.grow(SaLayer.CHUNK_SIZE)
    var reached := 0
    for grid_pos: Vector2i in _doc.active_layer.chunks:
        var cell := Rect2(Vector2(grid_pos * SaLayer.CHUNK_SIZE), Vector2(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE))
        if window.intersects(cell):
            reached += 1
    var thumbnail_pieces := SaFilterContext.submits(Rect2i(Vector2i.ZERO, SaFilterPreview.Reducer.size_for(SIZE))).size()
    assert_eq(dispatched - thumbnail_pieces, reached, "the canvas preview ran over the %d chunks the window reaches" % reached)
    var held := _doc.active_layer.chunks.size()
    assert_true(reached < held, "which are fewer than the layer's %d" % held)
    assert_false(_easel.backlog.is_empty(), "and the rest are held until the view moves over them")


## A chunk of a layer at twice the document's resolution, 512 texels on a side,
## previewed through the compositor's own path, goes out as four dispatches
## and reads the same texels as one dispatch over all of it.
func test_a_split_run_equals_a_single_run_texel_for_texel() -> void:
    var side := 512
    var pattern := Image.create_empty(side, side, false, Image.FORMAT_RGBAF)
    for y in side:
        for x in side:
            pattern.set_pixel(x, y, Color(float(x) / side, float(y) / side, float((x * 7 + y * 3) % 61) / 61.0, 1.0))
    var rd := GlobalShaderCompiler.get_rd()
    var source := SaTexture.new(Vector2i(side, side))
    rd.texture_update(source.rid, 0, pattern.get_data())
    var single := SaTexture.new(Vector2i(side, side))
    rd.texture_update(single.rid, 0, pattern.get_data())

    var values := {"hue": 40.0, "saturation": 1.3, "lightness": 0.1}
    var recorded: SaPointPass = PointAdjust.new().record(PointAdjust.HUE_SATURATION_LIGHTNESS, values, _doc.color_space)
    assert_not_null(recorded, "the filter's pass is recorded")
    var mask := SaTexture.new(Vector2i(side, side), SaSelection.FORMAT)
    mask.clear(Color(1.0, 1.0, 1.0, 1.0))

    var whole := SaCompute.new(PointAdjust.SHADER)
    whole.use_storage_format(single.format)
    whole.set_texture(0, single.rid)
    whole.set_texture(SaSelection.BINDING, mask.rid)
    recorded.bind(whole)
    whole.set_push_constant_float_array(recorded.push_for(Vector2i.ZERO))
    whole.dispatch_kernel(recorded.kernel, SaCompute.groups_for(side), SaCompute.groups_for(side), 1)

    SaFilterContext.count_submits_from_zero()
    var preview := SaPointPreview.new()
    var split := preview.chunk(
        SaCompute.new(PointAdjust.SHADER), source, mask, Rect2i(0, 0, SaChunk.SIZE, SaChunk.SIZE), recorded, Vector2i.ZERO
    )
    assert_eq(SaFilterContext.submitted, 4, "the chunk went out as four dispatches")
    assert_eq(SaFilterContext.largest_submit, SaFilterContext.SUBMIT_TEXELS, "each a quarter of it")

    var one := rd.texture_get_data(single.rid, 0)
    var four := rd.texture_get_data(split.rid, 0)
    assert_eq(four.size(), one.size(), "the two pictures are one size")
    assert_true(four == one, "and the split run's texels are the single run's, byte for byte")
    var changed := SaFieldSpec.decode_texel(one, single.format, 300 * side + 300)
    var kept := pattern.get_pixel(300, 300)
    assert_true(not changed.is_equal_approx(kept), "a run that changed the picture, so the comparison means something")
