## After every stroke on a large test document two or
## three frames of 60 to 99 ms followed, each naming `layer rows` and a long
## `draw`. The stroke's commit announces `document_changed`, and every
## adjustment row whose backdrop takes the walk drew its whole plate again from
## it, a position a frame for 17 frames a row, and the frames of the walk drew
## nothing, so the frame its picture showed in sent all their lists to the card
## at once. Now a stroke redraws its own layer's picture, once, and an
## adjustment's walk of the positions the stroke moved waits for the idle clock
## to say the painter has stopped. The frames of a walk are drawn as they go.
##
## The clock is the app's own, the autoload `SaIdle` the wait asks, turned to
## the suite's document and driven by `tick`, as in
## `ui/settings/tests/test_layer_thumbnails_can_refresh_only_once_the_painter_has_stopped.gd`,
## whose frames this suite keeps for the same reason: the pictures share a
## frame's budget keyed by the engine's frame count.
extends "res://tests/test_framework.gd"

## The pictures are compute passes over the chunks and the plate.
const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## One frame of the suite, in seconds, past the quarter second a redraw waits.
const FRAME: float = 0.5
## Two chunks across and one down, so the picture is 32 texels by 16.
const SIZE := Vector2i(2 * SaChunk.SIZE, SaChunk.SIZE)
## A texel of the picture over the first chunk.
const LEFT := Vector2i(8, 8)


## A layer's picture that counts how often it is drawn.
class CountingThumbnail:
    extends SaLayerThumbnail

    var redraws: int = 0

    func refresh() -> void:
        redraws += 1
        super()


var _types: SaLayerTypeRegistry
var _easel: SaEasel = null
var _paint: SaLayer = null
var _paint_thumb: CountingThumbnail = null
var _adjust_thumb: CountingThumbnail = null
var _kept_document: SaDocument = null
var _kept_seconds: float = 5.0
var _kept_process_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT


## Black paint under two Inverts. The lower one lifted by Affect all sends the
## upper one's backdrop down the walk, which is the path a large test document's
## adjustments in groups take.
func before_each() -> void:
    _kept_process_mode = SaIdle.process_mode
    SaIdle.process_mode = Node.PROCESS_MODE_DISABLED
    _kept_document = SaIdle.document
    _kept_seconds = SaIdle.idle_seconds
    _types = Fixtures.make_registries().layer_types
    _easel = Bench.easel(SIZE)
    var doc := _easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    _paint = doc.get_node("Layer 1") as SaLayer
    doc.set_active_layer(_paint)
    _paint.get_or_create_chunk(Vector2i(0, 0)).clear(Color(0.0, 0.0, 0.0, 1.0))
    _paint.get_or_create_chunk(Vector2i(1, 0)).clear(Color(0.0, 0.0, 0.0, 1.0))
    var whole := Rect2i(0, 0, SaChunk.SIZE, SaChunk.SIZE)
    doc.invalidate_chunk_regions({Vector2i(0, 0): whole, Vector2i(1, 0): whole}, _paint)
    var below := _adjustment("Invert 1")
    assert_true(SaBackdropLayer.affect_all(doc, below, true), "Affect all goes on")
    var top := _adjustment("Invert 2")
    doc.set_active_layer(_paint)
    assert_true(SaBackdropThumbnail.Quick.layers_below(doc, top).is_empty(), "The upper Invert's backdrop takes the walk")
    SaIdle.follow_settings = false
    SaIdle.follow_main = false
    SaIdle.idle_seconds = 5.0
    SaIdle.attach(doc)
    _paint_thumb = CountingThumbnail.new()
    _paint_thumb.bind_layer(_paint, doc)
    _adjust_thumb = CountingThumbnail.new()
    _adjust_thumb.bind_layer(top, doc)


func after_each() -> void:
    SaIdle.attach(_kept_document if is_instance_valid(_kept_document) else null)
    SaIdle.idle_seconds = _kept_seconds
    SaIdle.follow_settings = true
    SaIdle.follow_main = true
    SaIdle.process_mode = _kept_process_mode
    _paint_thumb.free()
    _adjust_thumb.free()
    _easel.free()


func _adjustment(title: String) -> SaLayer:
    var layer := SaLayerOps.new(_easel.document).add(SaBackdropLayer.TYPE_ID, _types)
    layer.name = title
    assert_not_null(SaFilterOps.new(_easel.document).attach(layer, Bench.INVERT), "%s attaches" % title)
    return layer


## *seconds* of the app, a frame at a time: the clock first, then the pictures.
func _run(seconds: float) -> void:
    var left := seconds
    while left > 0.001:
        await _next_frame()
        SaIdle.tick(FRAME)
        _paint_thumb._process(FRAME)
        _adjust_thumb._process(FRAME)
        left -= FRAME


## Waits until the pictures' share of a frame is whole again, two engine frames,
## because the frame after one that spent the whole share rests.
func _next_frame() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var start := Engine.get_process_frames()
    for i in 4:
        if Engine.get_process_frames() >= start + 2:
            return
        await tree.process_frame


## What a stroke's commit does to the document in one frame: the paint moves
## under its chunks' positions, which are announced, and then the change.
## The list marks the painted row and the adjustment rows at the commit. The
## frames before it composited what was dirty, so the positions are announced
## afresh, as they are in the app, and the composite's own change is heard in a
## frame of its own.
func _stroke(color: Color) -> void:
    _easel.process_pending_composite()
    await _next_frame()
    var whole := Rect2i(0, 0, SaChunk.SIZE, SaChunk.SIZE)
    _paint.get_or_create_chunk(Vector2i(0, 0)).clear(color)
    _easel.document.invalidate_chunk_regions({Vector2i(0, 0): whole}, _paint)
    _easel.document.document_changed.emit()
    _paint_thumb.mark_dirty()
    _adjust_thumb.mark_dirty()


static func _texel(thumb: SaLayerThumbnail, at: Vector2i) -> Color:
    var texture := thumb._texture
    if texture == null:
        return Color(-1, -1, -1, -1)
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var i := (at.y * texture.size.x + at.x) * 8
    return Color(data.decode_half(i), data.decode_half(i + 2), data.decode_half(i + 4), data.decode_half(i + 6))


func test_one_stroke_redraws_its_own_layers_picture_once_and_no_adjustments() -> void:
    await _run(2.0)
    var painted := _paint_thumb.redraws
    var adjusted := _adjust_thumb.redraws
    assert_eq(painted, 1, "The painted layer's picture is drawn once when bound")
    assert_false(_adjust_thumb._adjustment.pending(), "and the adjustment's walk has drawn its whole plate")
    var before := _texel(_adjust_thumb, LEFT)
    assert_true(before.a > 0.95, "The adjustment's picture shows the black paint as it makes it: %s" % before)
    await _stroke(Color(1.0, 1.0, 1.0, 1.0))
    assert_false(_adjust_thumb._adjustment._whole, "The commit's change, heard in the frame the paint moved, is no whole plate")
    await _run(3.0)
    assert_eq(_paint_thumb.redraws, painted + 1, "One stroke, one redraw of its own layer's picture")
    assert_eq(_adjust_thumb.redraws, adjusted, "and none of the adjustment's while the painter has not stopped")
    assert_eq(_texel(_adjust_thumb, LEFT), before, "which still shows the paint before the stroke")
    SaIdle.tick(5.0)
    await _run(2.0)
    assert_true(_adjust_thumb.redraws > adjusted, "The painter stopped, and the adjustment's picture is drawn")
    assert_false(_adjust_thumb._adjustment.pending(), "its walk done")
    var shown := _texel(_adjust_thumb, LEFT)
    assert_true(absf(shown.r - before.r) > 0.9 and shown.a > 0.95, "and it shows the stroke's white as it makes it: %s" % shown)
    assert_eq(_paint_thumb.redraws, painted + 1, "while the painted layer's picture was drawn no more")


func test_a_change_with_no_paint_moved_draws_the_adjustments_whole_plate_without_waiting() -> void:
    await _run(2.0)
    var adjusted := _adjust_thumb.redraws
    _easel.document.document_changed.emit()
    _adjust_thumb.mark_dirty()
    assert_true(_adjust_thumb._adjustment._whole, "A change heard in a frame no paint moved in is the whole plate")
    await _run(2.0)
    assert_true(_adjust_thumb.redraws > adjusted, "and it is drawn although the painter has not stopped")
