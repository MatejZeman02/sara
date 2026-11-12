## The kaleidoscope previewed on a photograph keeps up while a
## control drags. A painter added it to a photograph on a Pixel 6a and wrote
## "Not realtime".
##
## The canvas preview of a drag draws a draft, the fold read once for a square
## of 2^halvings texels on a side, and the release draws the exact pass. This
## suite reads both off the canvas. The draft is constant over every aligned
## square of four, where the exact pass is not. The release matches what Apply
## writes within 0.002 a channel. A redraw of the preview marks nothing
## painted, so the gather the layer keeps copies nothing again, and the draft's
## size follows the zoom.
##
## The painting: four chunks across and two down, each opaque in a colour of
## its own. The centre stands at two fifths of the canvas, (409.6, 204.8), so the
## wedge repeated crosses the chunk edges at x 512 and y 256 within the square
## read, and every fold of it shows those edges.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Kaleidoscope = preload("res://modules/sara-base-modules/kaleidoscope/kaleidoscope.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"kaleidoscope"
const SIZE := Vector2i(1024, 512)
const SIX_MIRRORS := {"mirrors": 6, "angle": 10.0, "centre_x": 40.0, "centre_y": 40.0}
## The square of the canvas read, round the centre, where every wedge meets,
## its corner on a multiple of four as the draft's squares are.
const LOOKED := Rect2i(Vector2i(280, 76), Vector2i(256, 256))
## Two halvings, a square of four texels on a side.
const HALVINGS := 2
const TOLERANCE := 0.002

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _filter: Kaleidoscope = null


func before_each() -> void:
    _easel = Bench.easel(SIZE)
    _doc = _easel.document
    _filter = Kaleidoscope.new()
    # The kernels' owner is the folder under modules, sara-base-modules, which
    # a filter registered by hand has to tell the loader.
    ModuleLoader.module_dirs[OWNER] = "res://modules/sara-base-modules/kaleidoscope"
    _easel.compositor.filter_chain.registry.register(_filter, OWNER)
    (_doc.get_node("Background") as SaLayer).visible = false
    _layer = _doc.get_node("Layer 1") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    for y in 2:
        for x in 4:
            var hue := float(y * 4 + x) / 8.0
            _layer.get_or_create_chunk(Vector2i(x, y)).clear(Color.from_hsv(hue, 0.8, 0.9))
    _doc.set_active_layer(_layer)
    Bench.composite(_easel)


func after_each() -> void:
    _filter = null
    _layer = null
    _doc = null
    _easel.free()
    _easel = null


## The kaleidoscope run as the dialog runs it, and its pass shown on the canvas
## at *halvings*, redrawn the way the dialog redraws it.
func _preview(halvings: int) -> SaFilterContext:
    _filter.set_parameters(SIX_MIRRORS)
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, _filter.title(), true)
    assert_true(SaFilterApply.call_run(_filter, ctx), "The kaleidoscope runs clean")
    _show(ctx, halvings)
    return ctx


func _show(ctx: SaFilterContext, halvings: int) -> void:
    _easel.compositor.point_preview.set_pass(_doc, ctx.point, halvings)
    var reached := _easel.compositor.point_preview.reached(_doc).merged(SaTyped.positions(_layer.chunks)).keys()
    _doc.invalidate_chunks(reached, null, false)
    _easel.request_composite()
    _easel.process_pending_composite()


## The canvas over [const LOOKED], row by row.
func _look() -> Array[Color]:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(_easel.output.rid, 0)
    var out: Array[Color] = []
    for y in range(LOOKED.position.y, LOOKED.end.y):
        for x in range(LOOKED.position.x, LOOKED.end.x):
            out.append(SaFieldSpec.decode_texel(bytes, _easel.output.format, y * SIZE.x + x))
    return out


## How many aligned squares of four in *seen* hold more than one colour.
static func _uneven_squares(seen: Array[Color]) -> int:
    var side := 1 << HALVINGS
    var count := 0
    for by in range(0, LOOKED.size.y, side):
        for bx in range(0, LOOKED.size.x, side):
            var first := seen[by * LOOKED.size.x + bx]
            var uneven := false
            for dy in side:
                for dx in side:
                    var other := seen[(by + dy) * LOOKED.size.x + bx + dx]
                    if absf(other.r - first.r) + absf(other.g - first.g) + absf(other.b - first.b) > TOLERANCE:
                        uneven = true
            if uneven:
                count += 1
    return count


## The largest difference of one channel between *a* and *b*.
static func _largest(a: Array[Color], b: Array[Color]) -> float:
    var most := 0.0
    for i in a.size():
        var apart := maxf(absf(a[i].r - b[i].r), absf(a[i].g - b[i].g))
        most = maxf(most, maxf(apart, maxf(absf(a[i].b - b[i].b), absf(a[i].a - b[i].a))))
    return most


func test_the_preview_of_a_drag_is_drawn_from_the_reduced_pass() -> void:
    var ctx := _preview(0)
    var exact := _look()
    assert_true(_uneven_squares(exact) > 0, "The exact pass shows the folded edge inside squares of four")
    _show(ctx, HALVINGS)
    assert_eq(_easel.compositor.point_preview.halvings(_doc), HALVINGS, "The preview holds the draft's halvings")
    var drafted := _look()
    assert_eq(_uneven_squares(drafted), 0, "and the draft draws every square of four in one colour")
    assert_true(_largest(drafted, exact) > TOLERANCE, "so it differs from the exact pass along the edge")
    _easel.compositor.point_preview.clear(_doc)


func test_the_release_matches_what_apply_writes() -> void:
    var ctx := _preview(HALVINGS)
    _show(ctx, 0)
    assert_eq(_easel.compositor.point_preview.halvings(_doc), 0, "The release drops the draft")
    var released := _look()
    assert_true(SaFilterApply.apply(ctx, _filter.title()), "Apply writes the full pass into the layer")
    _easel.compositor.point_preview.clear(_doc)
    _doc.invalidate_chunks(SaTyped.positions(_layer.chunks).keys())
    _easel.request_composite()
    _easel.process_pending_composite()
    var applied := _look()
    var most := _largest(released, applied)
    assert_true(most < TOLERANCE, "The picture after release is the full pass, the largest difference %f" % most)


func test_a_redraw_of_the_preview_marks_nothing_painted() -> void:
    var ctx := _preview(0)
    _show(ctx, HALVINGS)
    assert_eq(_doc.painted.size(), 0, "A drag's redraw leaves the gather the layer keeps nothing to copy again")


func test_the_draft_follows_the_zoom() -> void:
    assert_eq(SaCanvasDraft.at_scale(1.0), 0, "A texel a pixel or larger is drawn exact")
    assert_eq(SaCanvasDraft.at_scale(0.25), 2, "Four texels to a pixel is halved twice")
    assert_eq(SaCanvasDraft.at_scale(0.27), 2, "The photograph fitted to a phone's window takes the nearest square, four")
    assert_eq(SaCanvasDraft.at_scale(0.01), SaCanvasDraft.MOST_HALVINGS, "and no zoom is halved past the most")
