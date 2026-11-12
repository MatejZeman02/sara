## The Add Effect Layer browser previews a whole-picture filter
## whole.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The fault: Kaleidoscope in the browser was a piece of
## the photograph on the chequer while the layer it added was a whole
## kaleidoscope. A canvas of three by three chunks, centred at (384, 384), holds
## one chunk, the one below and right of the centre, painted white, and two
## mirrors at no rotation fold that quadrant into the other three. The tile has
## to cover the whole canvas the fold writes, reduced, with the fold's paint
## where Apply writes it and the layer untouched. The browser's own shot is the
## scenario's,
## `scenarios/the-add-effect-layer-browser-previews-a-whole-picture-filter-whole.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Kaleidoscope = preload("res://modules/sara-base-modules/kaleidoscope/kaleidoscope.gd")

const OWNER: StringName = &"kaleidoscope"
const WHITE := Color(1.0, 1.0, 1.0, 1.0)
const CANVAS := Vector2i(3 * SaChunk.SIZE, 3 * SaChunk.SIZE)
## The only chunk the layer holds.
const PAINTED := Vector2i(2, 2)
const TWO_MIRRORS := {"mirrors": 2, "angle": 0.0, "centre_x": 50.0, "centre_y": 50.0}

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _preview: SaFilterPreview = null


func before_each() -> void:
    _easel = Bench.easel(CANVAS)
    _doc = _easel.document
    _layer = _doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    _layer.get_or_create_chunk(PAINTED).clear(WHITE)
    _preview = SaFilterPreview.new()


func after_each() -> void:
    _preview.free()
    _preview = null
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


## The kaleidoscope run over the layer the way the browser runs it, previewing.
func _run() -> SaFilterContext:
    var filter := Kaleidoscope.new()
    filter.set_parameters(TWO_MIRRORS)
    # The kernels' owner is the folder under modules, sara-base-modules, which
    # a filter registered by hand has to tell the loader.
    ModuleLoader.module_dirs[OWNER] = "res://modules/sara-base-modules/kaleidoscope"
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, filter.title(), true)
    assert_true(SaFilterApply.call_run(filter, ctx), "The kaleidoscope's run is clean")
    return ctx


## The tile's texel over the document pixel *at*.
func _tile_at(at: Vector2i) -> Color:
    var shown := _preview.describe()["texture_size"] as Array
    var size := Vector2(float(shown[0]), float(shown[1]))
    var rect := _preview.rect
    var texel := Vector2i(((Vector2(at - rect.position) + Vector2(0.5, 0.5)) * size / Vector2(rect.size)).floor())
    return Bench.texel(_held(), texel)


func _held() -> SaTexture:
    return _preview._held


func test_the_tile_covers_the_canvas_the_fold_writes_and_shows_the_fold() -> void:
    var steps := _doc.history.step_count()
    var ctx := _run()
    assert_true(SaFilterBrowser.reads_whole(ctx), "The kaleidoscope records a pass that reads the whole layer")
    _preview.show_whole_pass(ctx)
    assert_eq(_preview.whole_runs, 1, "The tile took the whole layer's run")
    assert_eq(_preview.rect, Rect2i(Vector2i.ZERO, CANVAS), "over the whole canvas, though the layer holds one chunk")
    assert_eq(_held().size, Vector2i(SaFilterPreview.REDUCED_SIDE, SaFilterPreview.REDUCED_SIDE), "reduced to the tile's side")
    assert_almost_eq(_tile_at(Vector2i(668, 600)).a, 1.0, 1e-3, "The painted quadrant shows as it is")
    assert_almost_eq(_tile_at(Vector2i(100, 600)).a, 1.0, 1e-3, "its mirror image below and left of the centre")
    assert_almost_eq(_tile_at(Vector2i(100, 100)).a, 1.0, 1e-3, "and the quadrant diagonally across")
    assert_almost_eq(_tile_at(Vector2i(668, 100)).r, 1.0, 1e-3, "and above it, white in every channel")
    assert_almost_eq(_tile_at(Vector2i(400, 400)).a, 0.0, 1e-3, "and nothing where the fold holds no paint")
    assert_eq(_layer.chunks.keys(), [PAINTED], "The layer allocated nothing for the tile")
    assert_eq(_doc.history.step_count(), steps, "and recorded no step")


## Run a chunk at a time over that chunk alone, every fold that read past it
## would read nothing. That path answers no
## picture for such a pass, so no window can show the fragment.
func test_the_chunk_by_chunk_picture_is_not_offered_for_a_whole_layer_pass() -> void:
    var ctx := _run()
    assert_null(SaFilterBrowser.picture_of(ctx), "The browser's run over the run's rectangle answers no picture")
    assert_null(SaFilterBrowser.PassPicture.evaluate(ctx), "and neither does the dialog's gathered one")


## Under a selection the tile covers its bounds, and the kernel mixes by it as
## Apply's does, so a part of the bounds the selection leaves out shows the
## layer as it is and not the fold.
func test_under_a_selection_the_tile_is_the_fold_inside_it_and_the_layer_outside() -> void:
    _doc.selection.select_rect(Rect2i(0, 0, CANVAS.x, 300))
    _doc.selection.select_rect(Rect2i(600, 600, 168, 168), SaSelection.Mode.ADD)
    _preview.show_whole_pass(_run())
    assert_eq(_preview.rect, Rect2i(Vector2i.ZERO, CANVAS), "The tile covers the selection's bounds")
    assert_almost_eq(_tile_at(Vector2i(100, 100)).a, 1.0, 1e-3, "Inside the selection the fold shows")
    assert_almost_eq(_tile_at(Vector2i(700, 700)).a, 1.0, 1e-3, "and over the painted chunk")
    assert_almost_eq(_tile_at(Vector2i(100, 600)).a, 0.0, 1e-3, "Outside it the layer holds nothing, and the fold is not shown")
    _doc.selection.select_rect(Rect2i(0, 0, 384, 300))
    _preview.show_whole_pass(_run())
    assert_eq(_preview.rect, Rect2i(0, 0, 384, 300), "A smaller selection is a smaller tile")
    assert_eq(_held().size, Vector2i(384, 300), "at its own size while it fits the tile's side")


## An empty layer has nothing to fold, and a run that is not a whole layer's
## pass is not this picture, so both clear the tile rather than leave the last.
func test_an_empty_layer_and_another_run_clear_the_tile() -> void:
    _preview.show_whole_pass(_run())
    assert_not_null(_held(), "A tile is up")
    _layer.chunks.erase(PAINTED)
    _preview.show_whole_pass(_run())
    assert_null(_held(), "An empty layer clears it")
    _preview.show_whole_pass(null)
    assert_null(_held(), "and so does no run")
    assert_eq(_preview.whole_runs, 1, "and neither counts as the whole layer's run")
