## Showing a group of a large test document held the window for
## 74 s, because every adjustment layer's picture walked the whole stack below
## it at each chunk position in the one frame after the fold. These read the
## parts that pay it over frames: a walk with a deadline draws a position and
## stays pending, and what it draws over many calls is what one call draws, a
## row whose walk is still pending keeps its last picture, the deadline is one
## for the whole frame, and the members a tree walk reads once answer as the
## stack's own questions do.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## Four chunks across and two down.
const SIZE := Vector2i(4 * SaChunk.SIZE, 2 * SaChunk.SIZE)
## A deadline that passed long ago, as a `Time.get_ticks_usec`.
const PASSED := 1

var _types: SaLayerTypeRegistry
var _easel: SaEasel = null
var _paint: SaLayer = null


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    _easel = Bench.easel(SIZE)
    var doc := _easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    _paint = doc.get_node("Layer 1") as SaLayer
    doc.set_active_layer(_paint)
    var moved: Dictionary[Vector2i, Rect2i] = {}
    for x in 4:
        for y in 2:
            var grey := 0.25 * x
            _paint.get_or_create_chunk(Vector2i(x, y)).clear(Color(grey, grey, grey, 1.0))
            moved[Vector2i(x, y)] = Rect2i(0, 0, SaChunk.SIZE, SaChunk.SIZE)
    doc.invalidate_chunk_regions(moved, _paint)


func after_each() -> void:
    _easel.free()
    _easel = null
    _paint = null


## An Invert over the paint, with a record on the paint so the picture takes
## the walk rather than the quick way.
func _walked_invert() -> SaLayer:
    assert_not_null(SaFilterOps.new(_easel.document).attach(_paint, Bench.INVERT), "The paint takes a record")
    var layer := SaLayerOps.new(_easel.document).add(SaBackdropLayer.TYPE_ID, _types)
    layer.name = "Invert"
    assert_not_null(SaFilterOps.new(_easel.document).attach(layer, Bench.INVERT), "The Invert attaches")
    assert_true(SaBackdropThumbnail.Quick.layers_below(_easel.document, layer).is_empty(), "A record on the paint is the walk")
    return layer


static func _bytes(texture: SaTexture) -> PackedByteArray:
    if texture == null or not texture.rid.is_valid():
        return PackedByteArray()
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


## A deadline already passed draws one position a call, answers null with the
## walk pending until the last, and the plate it ends with is the one a call
## with no deadline draws.
func test_a_walk_past_its_deadline_draws_a_position_a_call_and_ends_on_the_same_plate() -> void:
    var top := _walked_invert()
    var positions := SaNodeInput.new(_easel.document, top).positions().size()
    assert_true(positions > 1, "The walk has %d positions to spread" % positions)
    var spread := SaBackdropThumbnail.new()
    var calls := 0
    var shown: SaTexture = null
    while calls <= positions:
        calls += 1
        shown = spread.drawn(_easel.document, top, PASSED)
        if not spread.pending():
            break
        assert_null(shown, "A pending walk answers null on call %d" % calls)
    assert_eq(calls, positions, "One position a call")
    var spread_bytes := _bytes(shown)
    var whole := SaBackdropThumbnail.new()
    var at_once := _bytes(whole.drawn(_easel.document, top))
    assert_false(whole.pending(), "A call with no deadline leaves nothing due")
    assert_false(at_once.is_empty(), "The plate drawn at once is read")
    assert_true(spread_bytes == at_once, "The plate drawn over %d calls is the plate drawn in one" % calls)


## A row whose walk a deadline stopped keeps the picture it had, and stays
## dirty and going on so the next frame takes the rest without the interval.
## A redraw with no deadline then finishes it.
func test_a_row_keeps_its_picture_while_its_walk_is_pending() -> void:
    var top := _walked_invert()
    var thumb := SaLayerThumbnail.new()
    thumb.bind_layer(top, _easel.document)
    thumb.refresh()
    var before := thumb._texture
    assert_not_null(before, "The picture is drawn")
    _easel.document.document_changed.emit()
    thumb._settle(PASSED)
    assert_true(thumb._texture == before, "The picture from before stays while the walk is pending")
    assert_true(thumb._continuing, "The row goes on with the walk next frame")
    assert_true(thumb._dirty, "and stays dirty for it")
    thumb.refresh()
    assert_false(thumb._adjustment.pending(), "A redraw with no deadline finishes the walk")
    assert_not_null(thumb._texture, "and draws the picture")
    thumb.free()


## The share is what the rows spent in the frame, so a frame that is long by
## time alone, a suite's or a slow machine's, leaves the rows the whole of it.
## The frame asked is one no engine frame reaches, so the rows of the suites
## after this one keep their own count.
func test_time_alone_spends_none_of_the_share() -> void:
    var frame := Engine.get_process_frames() + 100000
    var whole := SaLayerThumbnail.FRAME_BUDGET_USEC
    assert_eq(SaLayerThumbnail._share_left(frame), whole, "A frame no row spent in has the whole share")
    OS.delay_usec(whole + 2000)
    assert_eq(SaLayerThumbnail._share_left(frame), whole, "and still has it after the frame ran past it")


## The frame after one whose rows spent the whole share draws no row, and the
## frame after that rest has the whole share again. The frames asked are ones
## no engine frame reaches, so the suites after this one keep their count.
func test_the_frame_after_a_spent_share_rests() -> void:
    var frame := Engine.get_process_frames() + 200000
    var whole := SaLayerThumbnail.FRAME_BUDGET_USEC
    assert_eq(SaLayerThumbnail._share_left(frame), whole, "A fresh frame has the whole share")
    SaLayerThumbnail._spend(frame, whole)
    assert_eq(SaLayerThumbnail._share_left(frame + 1), 0, "The frame after a spent share rests")
    assert_eq(SaLayerThumbnail._share_left(frame + 2), whole, "and the one after the rest has it all again")


## A row that redraws in its process takes what the redraw cost off the share
## the rows after it in the same frame are left.
func test_a_row_s_redraw_spends_the_share() -> void:
    var top := _walked_invert()
    var thumb := SaLayerThumbnail.new()
    thumb.bind_layer(top, _easel.document)
    var frame := Engine.get_process_frames()
    var before := SaLayerThumbnail._share_left(frame)
    thumb.mark_dirty()
    thumb._process(SaLayerThumbnail.REFRESH_SECONDS)
    assert_false(thumb._dirty and not thumb._continuing, "The row redrew")
    assert_true(SaLayerThumbnail._share_left(frame) < before, "and its redraw came off the share")
    thumb.free()


## The members a tree walk reads once give every layer the clip base and the
## clipped run `SaLayerStack` gives it, in groups and at the top level.
func test_the_walks_members_answer_as_the_stack_does() -> void:
    var doc := _easel.document
    var ops := SaLayerOps.new(doc)
    var base := ops.add()
    var clipped := ops.add()
    clipped.clip_to_below = true
    var adjustment := ops.add(SaBackdropLayer.TYPE_ID, _types)
    var on_adjustment := ops.add()
    on_adjustment.clip_to_below = true
    var group := ops.group_layers([base, clipped])
    assert_not_null(group, "The base and its clip are grouped")
    var inner := ops.add()
    inner.clip_to_below = true
    var siblings := SaTreeRender.Siblings.new(doc)
    var layers := 0
    for child in doc.get_children():
        var layer := child as SaLayer
        if layer == null:
            continue
        layers += 1
        assert_eq(siblings.clip_base(layer), SaLayerStack.clip_base(doc, layer), "%s's clip base" % layer.name)
        assert_eq(siblings.clipped_run(layer), SaLayerStack.clipped_run(doc, layer), "%s's clipped run" % layer.name)
    assert_eq(siblings.of(group), SaLayerStack.members(doc, group), "The group's members")
    assert_eq(siblings.of(null), SaLayerStack.members(doc, null), "The top level's members")
    assert_true(layers >= 7, "Every layer was asked, %d" % layers)
    assert_not_null(adjustment, "The adjustment was made")
    assert_not_null(on_adjustment, "and the layer clipped to it")
