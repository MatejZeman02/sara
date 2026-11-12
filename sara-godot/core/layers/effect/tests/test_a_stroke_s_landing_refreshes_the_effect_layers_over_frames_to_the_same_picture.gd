## The frames after a stroke on a large painting stay under 50 ms.
##
## An effect layer waits out a live stroke and refreshed every region it
## dirtied in the frame the stroke landed, 74 ms over 28 chunks on a large
## painting's mirrors. The landing's refresh now stops once the pace's time is
## spent and goes on in the next frame, the backlog bringing that frame. This
## suite lands a stroke over a canvas of 32 chunks with a pace that stops after
## every piece of work, reads that the frame it lands in only starts the
## refresh, the next finds what it reached and the one after writes a chunk,
## that a change in the middle finishes the rest at once, and that once the
## backlog is empty the effect's cache and the picture are those of a refresh
## in one frame.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(2048, 1024)
const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const LATER := Color(0.875, 0.125, 0.375, 1.0)
const TOLERANCE := 1.0e-4
const AT := Vector2i(9, 9)

var _types: SaLayerTypeRegistry


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    SaProblems.pending_refusals = PackedStringArray()


## An easel whose Paint layer covers every chunk, read by an effect Mirror that
## inverts it, composited once.
func _painting() -> SaEasel:
    var easel := Bench.easel(SIZE)
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var paint := doc.get_node("Layer 1") as SaLayer
    paint.name = "Paint"
    for grid_pos in SaLayer.grid_positions(doc.canvas_size):
        paint.get_or_create_chunk(grid_pos).clear(PAINT)
    doc.set_active_layer(paint)
    var effect := SaLayerOps.new(doc).add(SaEffectLayer.TYPE_ID, _types)
    effect.name = "Mirror"
    assert_not_null(SaFilterOps.new(doc).attach(effect, Bench.INVERT), "The invert attaches to Mirror")
    if effect.source != paint:
        SaEffectLayer.read(doc, effect, paint)
    doc.set_active_layer(paint)
    Bench.composite(easel)
    return easel


## Paints every chunk of Paint in LATER and invalidates it at Paint, the way a
## stroke's commit lands, after a frame in which the stroke was live when
## *live* holds.
func _land(easel: SaEasel, live: bool) -> void:
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var regions: Dictionary[Vector2i, Rect2i] = {}
    for grid_pos in SaLayer.grid_positions(doc.canvas_size):
        regions[grid_pos] = SaDocument.WHOLE_CHUNK
    if live:
        doc.stroke_transaction.before_chunks[Vector2i(0, 0)] = null
        doc.invalidate_chunk_regions({Vector2i(0, 0): SaDocument.WHOLE_CHUNK}, paint)
        easel.process_pending_composite(true)
        doc.stroke_transaction.before_chunks.clear()
    for grid_pos: Vector2i in regions:
        paint.get_or_create_chunk(grid_pos).clear(LATER)
    doc.invalidate_chunk_regions(regions, paint)
    doc.update_caches()


static func _near(a: Color, b: Color) -> bool:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))) <= TOLERANCE


static func _cache_at(easel: SaEasel, grid_pos: Vector2i) -> Color:
    var mirror := easel.document.get_node("Mirror") as SaLayer
    return Bench.texel(mirror.get_field(grid_pos), AT)


static func _shown_at(easel: SaEasel, grid_pos: Vector2i) -> Color:
    return Bench.texel(easel.output, grid_pos * SaLayer.CHUNK_SIZE + AT)


## The pace of *easel*'s effect layers, set to stop every frame after its
## first chunk, so a canvas of 32 chunks lands over many frames.
static func _slow(easel: SaEasel) -> void:
    easel.compositor.effect._pace.frame_usec = 0


## Composites *easel* frame by frame until nothing is held, at most *most*
## frames, and answers how many it took.
static func _frames(easel: SaEasel, most: int = 200) -> int:
    var frames := 0
    while not easel.backlog.is_empty() and frames < most:
        easel.process_pending_composite(true)
        frames += 1
    return frames


func test_the_landing_s_frame_only_starts_the_refresh_and_the_frames_after_it_write_a_share_each() -> void:
    var easel := _painting()
    _slow(easel)
    var positions := SaLayer.grid_positions(easel.document.canvas_size)
    var before := _shown_at(easel, Vector2i(0, 0))
    _land(easel, true)
    easel.process_pending_composite(true)
    assert_eq(_caught(easel), [] as Array[Vector2i], "The frame the stroke lands in writes no effect chunk")
    var shown := _shown_at(easel, Vector2i(0, 0))
    assert_true(_near(shown, before), "Nor walks the commit's regions, %s against %s" % [shown, before])
    assert_false(easel.backlog.is_empty(), "A region waits in the backlog to bring the next frame")
    easel.process_pending_composite(true)
    assert_eq(_caught(easel), [] as Array[Vector2i], "The next frame finds what the change reached, and stops there")
    easel.process_pending_composite(true)
    var caught := _caught(easel)
    assert_eq(caught.size(), 1, "The frame after it writes the one chunk it pays for, %s" % [caught])
    assert_false(easel.backlog.is_empty(), "And the rest waits for the frames after it")
    assert_true(positions.size() > 1, "The canvas holds more chunks than one")
    easel.free()


## The grid positions whose effect cache holds LATER.
static func _caught(easel: SaEasel) -> Array[Vector2i]:
    var caught: Array[Vector2i] = []
    for grid_pos in SaLayer.grid_positions(easel.document.canvas_size):
        if _near(_cache_at(easel, grid_pos), LATER):
            caught.append(grid_pos)
    return caught


func test_the_picture_after_the_last_frame_is_a_single_refresh_s() -> void:
    var paced := _painting()
    _slow(paced)
    var whole := _painting()
    var before := _shown_at(whole, Vector2i(3, 2))
    _land(paced, true)
    _land(whole, false)
    whole.process_pending_composite()
    paced.process_pending_composite(true)
    var frames := _frames(paced)
    assert_true(paced.backlog.is_empty(), "The backlog empties, in %d frames after the first" % frames)
    assert_true(frames >= 31, "The landing of 32 chunks took a frame a chunk, %d after the first" % frames)
    assert_eq(_wrong(paced, whole), [] as Array[String], "Every chunk's cache and picture are a single refresh's")
    var after := _shown_at(whole, Vector2i(3, 2))
    assert_false(_near(after, before), "The landing changed the picture, %s from %s" % [after, before])
    paced.free()
    whole.free()


func test_a_change_while_the_landing_goes_on_is_refreshed_with_it_over_frames() -> void:
    var paced := _painting()
    _slow(paced)
    var whole := _painting()
    _land(paced, true)
    _land(whole, false)
    paced.process_pending_composite(true)
    paced.process_pending_composite(true)
    for easel: SaEasel in [paced, whole]:
        var doc := easel.document
        var paint := doc.get_node("Paint") as SaLayer
        paint.get_or_create_chunk(Vector2i(7, 3)).clear(PAINT)
        doc.invalidate_chunk_regions({Vector2i(7, 3): SaDocument.WHOLE_CHUNK}, paint)
        doc.update_caches()
    whole.process_pending_composite()
    paced.process_pending_composite(true)
    var stale: Array[Vector2i] = []
    for grid_pos in SaLayer.grid_positions(paced.document.canvas_size):
        var want := PAINT if grid_pos == Vector2i(7, 3) else LATER
        if not _near(_cache_at(paced, grid_pos), want):
            stale.append(grid_pos)
    assert_false(stale.is_empty(), "The frame of the change leaves the rest of the landing and the change to the frames after it")
    _frames(paced)
    assert_eq(_wrong(paced, whole, Vector2i(7, 3)), [] as Array[String], "The picture is a single refresh's")
    paced.free()
    whole.free()


## Every chunk of *paced* whose cache is not LATER, but at *odd* PAINT, or
## whose picture differs from *whole*'s.
func _wrong(paced: SaEasel, whole: SaEasel, odd: Vector2i = Vector2i(-1, -1)) -> Array[String]:
    var wrong: Array[String] = []
    for grid_pos in SaLayer.grid_positions(paced.document.canvas_size):
        var cache := _cache_at(paced, grid_pos)
        var shown := _shown_at(paced, grid_pos)
        var expected := _shown_at(whole, grid_pos)
        var want := PAINT if grid_pos == odd else LATER
        if not _near(cache, want) or not _near(shown, expected):
            wrong.append("%s cache %s shown %s against %s" % [grid_pos, cache, shown, expected])
    return wrong
