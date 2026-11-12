## A Wrap Offset previewed on the canvas shows the paint it
## moves onto ground the layer holds no chunk at, as Apply then writes it, and
## Cancel takes it off again.
##
## A painter met it at -1608 by 1558 on a 1920 by 1080 layer: the dialog's
## thumbnail and Apply showed the wrapped strokes whole, and the canvas stopped
## them at chunk edges. `SaPointPreview.drawn` handed a missing chunk back as
## null and the walk visited only the positions the layer held, so a wrap's
## paint moved past them was drawn nowhere until Apply allocated the chunks.
##
## The painting: four chunks across and two down, the grey background hidden,
## Layer 1 holding one chunk at (0, 0), opaque red. A wrap by half the canvas,
## (512, 256), lands it on (2, 1), which the layer does not hold. The preview is
## set, redrawn and cleared the way `SaFilterDialogWindow` does it: the run's
## pass handed to the compositor, every position the pass shown before and the
## one shown now land on marked dirty, and the next composite. Where the pass
## lands is asked of `SaNeighbourhoodPass.lands_on`, the helper Apply allocates
## by.
##
## The note guessed the kaleidoscope, which writes the whole canvas, showed the
## same gaps. It did, and a case paints the chunk below and right of the centre
## and reads the fold round the centre on three chunks the layer does not hold.
## A blur's spill past the layer's edge, into the ring Apply allocates round its
## chunks, was left out the same way, and the last case reads it there.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Kaleidoscope = preload("res://modules/sara-base-modules/kaleidoscope/kaleidoscope.gd")
const BoxBlurFilter = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const SIZE := Vector2i(1024, 512)
const HALF := Vector2i(512, 256)
const RED := Color(1.0, 0.0, 0.0, 1.0)
const TOLERANCE := 1.0e-3
## The chunk the layer holds, and the one the wrap carries it onto.
const HELD := Vector2i(0, 0)
const LANDED := Vector2i(2, 1)
## Texels of the landed chunk, its corner, inside it and its last texel, and
## one of the held chunk, which the wrap reads from the empty middle of the
## canvas.
const WRAPPED: Array[Vector2i] = [Vector2i(512, 256), Vector2i(600, 300), Vector2i(767, 511)]
const EMPTIED := Vector2i(100, 100)
const SIX_MIRRORS := {"mirrors": 6, "angle": 0.0, "centre_x": 50.0, "centre_y": 50.0}
## Texels within a chunk's side of the centre, (512, 256), on chunks the layer
## does not hold. A kaleidoscope keeps a texel's distance from the centre, and
## every texel reads the wedge below and right of it, which lies in (2, 1).
const FOLDED: Array[Vector2i] = [Vector2i(300, 260), Vector2i(700, 100), Vector2i(400, 60)]
const BLUR_OWNER: StringName = &"sara-base-modules"
## A box blur of radius 4 over the red chunk reaches four texels into (1, 0),
## which the layer does not hold, where it reads four columns of red in nine.
const PAST := Vector2i(256, 128)
const PAST_ALPHA := 4.0 / 9.0

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _filter: SaWrapOffsetFilter = null


func before_each() -> void:
    _easel = Bench.easel(SIZE)
    _doc = _easel.document
    _filter = SaWrapOffsetFilter.new()
    _easel.compositor.filter_chain.registry.register(_filter, OWNER)
    (_doc.get_node("Background") as SaLayer).visible = false
    _layer = _doc.get_node("Layer 1") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    _layer.get_or_create_chunk(HELD).clear(RED)
    _doc.set_active_layer(_layer)
    Bench.composite(_easel)


func after_each() -> void:
    _filter = null
    _layer = null
    _doc = null
    _easel.free()
    _easel = null


## The wrap by half the canvas run as the dialog runs it on the active layer,
## and its pass shown on the canvas, as a ticked Preview box shows it. Answers
## the run, which Apply writes.
func _preview() -> SaFilterContext:
    _filter.set_parameters({"offset_x": HALF.x, "offset_y": HALF.y})
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, _filter.title(), true)
    assert_true(SaFilterApply.call_run(_filter, ctx), "The wrap runs clean")
    assert_true(ctx.point is SaNeighbourhoodPass, "and records a pass the compositor previews")
    var before := _held()
    _easel.compositor.point_preview.set_pass(_doc, ctx.point)
    _redraw(before, _lands(ctx))
    return ctx


## The preview taken back off, as Cancel takes it.
func _cancel(ctx: SaFilterContext) -> void:
    var before := _lands(ctx)
    _easel.compositor.point_preview.clear(_doc)
    _redraw(before, _held())


## The preview taken off after the run is written into the layer, as Apply
## does it.
func _apply(ctx: SaFilterContext) -> void:
    assert_true(SaFilterApply.apply(ctx, _filter.title()), "Apply writes the wrap into the layer")
    var before := _lands(ctx)
    _easel.compositor.point_preview.clear(_doc)
    _redraw(before, _held())


## Where *ctx*'s pass lands over the layer as it stands, the layer's chunks with it.
func _lands(ctx: SaFilterContext) -> Dictionary[Vector2i, bool]:
    return (ctx.point as SaNeighbourhoodPass).lands_on(_layer.chunks.keys(), _doc.canvas_size)


func _held() -> Dictionary[Vector2i, bool]:
    return SaTyped.positions(_layer.chunks)


## *before* and *after* marked dirty and composited, the dialog's redraw.
func _redraw(before: Dictionary[Vector2i, bool], after: Dictionary[Vector2i, bool]) -> void:
    _doc.invalidate_chunks(after.merged(before).keys())
    _easel.request_composite()
    _easel.process_pending_composite()


## The canvas at every texel of [const WRAPPED].
func _look() -> Array[Color]:
    var out: Array[Color] = []
    for at: Vector2i in WRAPPED:
        out.append(Bench.texel(_easel.output, at))
    return out


func test_the_wrap_lands_on_a_chunk_the_layer_does_not_hold() -> void:
    var ctx := _preview()
    assert_true(_lands(ctx).has(LANDED), "The wrap lands on (2, 1), %s" % [_lands(ctx).keys()])
    assert_null(_layer.get_field(LANDED), "which the layer holds no chunk at while it is previewed")
    for shown: Color in _look():
        assert_almost_eq(shown.a, 1.0, TOLERANCE, "The canvas shows the wrapped paint there, %s" % shown)
        assert_almost_eq(shown.r, 1.0, TOLERANCE, "in red, %s" % shown)
    var emptied := Bench.texel(_easel.output, EMPTIED)
    assert_almost_eq(emptied.a, 0.0, TOLERANCE, "and the held chunk shows the empty middle moved onto it, %s" % emptied)
    _cancel(ctx)


func test_apply_writes_what_the_preview_showed_on_empty_ground() -> void:
    var ctx := _preview()
    var previewed := _look()
    var emptied := Bench.texel(_easel.output, EMPTIED)
    _apply(ctx)
    assert_not_null(_layer.get_field(LANDED), "Apply allocates the chunk the wrap lands on")
    var applied := _look()
    for i in WRAPPED.size():
        assert_true(
            applied[i].is_equal_approx(previewed[i]),
            "At %s the canvas shows after Apply what the preview showed, %s against %s" % [WRAPPED[i], applied[i], previewed[i]]
        )
        var written := Bench.texel(_layer.get_field(LANDED), WRAPPED[i] - LANDED * SaChunk.SIZE)
        assert_true(written.is_equal_approx(previewed[i]), "and the layer holds it, %s against %s" % [written, previewed[i]])
    var kept := Bench.texel(_easel.output, EMPTIED)
    assert_true(
        kept.is_equal_approx(emptied), "The held chunk shows what the preview showed too, %s against %s" % [kept, emptied]
    )


func test_cancel_takes_the_wrapped_paint_off_the_empty_ground() -> void:
    var ctx := _preview()
    _cancel(ctx)
    assert_null(_layer.get_field(LANDED), "Cancel allocates nothing")
    for shown: Color in _look():
        assert_almost_eq(shown.a, 0.0, TOLERANCE, "After Cancel the landed chunk shows nothing again, %s" % shown)
    var held := Bench.texel(_easel.output, EMPTIED)
    assert_true(held.is_equal_approx(RED), "and the held chunk its own red, %s" % held)


func test_a_kaleidoscope_previewed_shows_its_fold_on_empty_ground_too() -> void:
    _layer.chunks.erase(HELD)
    _layer.get_or_create_chunk(LANDED).clear(RED)
    var filter := Kaleidoscope.new()
    # The kernels' owner is the folder under modules, sara-base-modules, which
    # a filter registered by hand has to tell the loader.
    ModuleLoader.module_dirs[&"kaleidoscope"] = "res://modules/sara-base-modules/kaleidoscope"
    _easel.compositor.filter_chain.registry.register(filter, &"kaleidoscope")
    filter.set_parameters(SIX_MIRRORS)
    var ctx := SaFilterContext.new(_doc, _layer, &"kaleidoscope", filter.title(), true)
    assert_true(SaFilterApply.call_run(filter, ctx), "The kaleidoscope runs clean")
    var before := _held()
    _easel.compositor.point_preview.set_pass(_doc, ctx.point)
    _redraw(before, _lands(ctx))
    var previewed: Array[Color] = []
    for at: Vector2i in FOLDED:
        assert_null(_layer.get_field(_chunk_of(at)), "The layer holds no chunk under %s" % at)
        var shown := Bench.texel(_easel.output, at)
        assert_almost_eq(shown.a, 1.0, TOLERANCE, "The fold shows at %s while it is previewed, %s" % [at, shown])
        previewed.append(shown)
    assert_true(SaFilterApply.apply(ctx, filter.title()), "Apply writes the fold into the layer")
    before = _lands(ctx)
    _easel.compositor.point_preview.clear(_doc)
    _redraw(before, _held())
    for i in FOLDED.size():
        var applied := Bench.texel(_easel.output, FOLDED[i])
        assert_true(
            applied.is_equal_approx(previewed[i]),
            "At %s Apply shows what the preview showed, %s against %s" % [FOLDED[i], applied, previewed[i]]
        )


func test_a_blur_previewed_shows_what_it_spills_past_the_layer_s_chunks() -> void:
    ModuleLoader.module_dirs[BLUR_OWNER] = "res://modules/sara-base-modules/base"
    var filter := BoxBlurFilter.new()
    _easel.compositor.filter_chain.registry.register(filter, BLUR_OWNER)
    filter.write_parameter(&"radius", 4)
    var ctx := SaFilterContext.new(_doc, _layer, BLUR_OWNER, filter.title(), true)
    assert_true(SaFilterApply.call_run(filter, ctx), "The blur runs clean")
    var before := _held()
    _easel.compositor.point_preview.set_pass(_doc, ctx.point)
    var lands := _reach(ctx)
    _redraw(before, lands)
    assert_true(lands.has(_chunk_of(PAST)), "Apply writes the chunk beside the red one, %s" % [lands.keys()])
    assert_null(_layer.get_field(_chunk_of(PAST)), "which the layer holds none of while the blur is previewed")
    var previewed := Bench.texel(_easel.output, PAST)
    assert_almost_eq(previewed.a, PAST_ALPHA, TOLERANCE, "The spill shows past the edge in the preview, %s" % previewed)
    assert_true(SaFilterApply.apply(ctx, filter.title()), "Apply writes the blur into the layer")
    _easel.compositor.point_preview.clear(_doc)
    _redraw(lands, _held())
    var applied := Bench.texel(_easel.output, PAST)
    assert_true(
        applied.is_equal_approx(previewed), "and Apply shows what the preview showed, %s against %s" % [applied, previewed]
    )


## Where *ctx*'s pass writes over the layer as Apply walks it, the layer's chunks with it.
func _reach(ctx: SaFilterContext) -> Dictionary[Vector2i, bool]:
    var out := _held()
    for grid_pos: Vector2i in SaFilterApply.neighbourhood_reach(_doc, _layer, ctx.point as SaNeighbourhoodPass):
        out[grid_pos] = true
    return out


## The grid position of the chunk the document pixel *at* lies in.
static func _chunk_of(at: Vector2i) -> Vector2i:
    return Vector2i((Vector2(at) / SaChunk.SIZE).floor())
