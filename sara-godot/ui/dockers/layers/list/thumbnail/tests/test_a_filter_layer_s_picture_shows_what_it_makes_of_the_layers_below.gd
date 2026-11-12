## A filter layer's preview shows the output of all the transformed layers it
## is applied to.
##
## An adjustment layer holds no chunk, so its row drew the checker alone. Its
## picture is now its records run over the backdrop it reads, drawn on the card
## at a reduced size by `SaBackdropThumbnail` and read back here, as the
## suites beside this one read theirs.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const OWNER: StringName = &"sara-base-modules"
## Two chunks across and one down, so the picture is 32 texels by 16.
const SIZE := Vector2i(2 * SaChunk.SIZE, SaChunk.SIZE)
## A curve that lifts black to a half, so the black half reads a mid grey and
## not either grey of the checker.
const LIFT := {"curves": {"master": [[0.0, 0.5], [1.0, 1.0]]}}
## A texel in the middle of the picture's left half, over the first chunk, and
## one in its right half, over the second.
const LEFT := Vector2i(8, 8)
const RIGHT := Vector2i(24, 8)

var _types: SaLayerTypeRegistry
var _easel: SaEasel = null


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    _easel = Bench.easel(SIZE)
    _easel.compositor.filter_chain.registry.register(SaCurvesFilter.new(), OWNER)
    var doc := _easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var paint := doc.get_node("Layer 1") as SaLayer
    doc.set_active_layer(paint)
    _paint(Color(0.0, 0.0, 0.0, 1.0), Color(1.0, 1.0, 1.0, 1.0))


func after_each() -> void:
    _easel.free()
    _easel = null


## The layer below painted *left* over its first chunk and *right* over its
## second, and the two chunks announced as a stroke announces what it moved.
func _paint(left: Color, right: Color) -> void:
    var paint := _easel.document.get_node("Layer 1") as SaLayer
    paint.get_or_create_chunk(Vector2i(0, 0)).clear(left)
    paint.get_or_create_chunk(Vector2i(1, 0)).clear(right)
    var whole := Rect2i(0, 0, SaChunk.SIZE, SaChunk.SIZE)
    _easel.document.invalidate_chunk_regions({Vector2i(0, 0): whole, Vector2i(1, 0): whole}, paint)


func _adjustment(title: String, key: StringName, values: Dictionary = {}) -> SaLayer:
    var layer := SaLayerOps.new(_easel.document).add(SaBackdropLayer.TYPE_ID, _types)
    layer.name = title
    assert_not_null(SaFilterOps.new(_easel.document).attach(layer, key, values), "%s attaches" % title)
    return layer


func _thumbnail(layer: SaLayer) -> SaLayerThumbnail:
    var thumb := SaLayerThumbnail.new()
    thumb.bind_layer(layer, _easel.document)
    thumb.refresh()
    return thumb


## The picture's texel at *at*, half floats, display values.
static func _texel(thumb: SaLayerThumbnail, at: Vector2i) -> Color:
    var texture := thumb._texture
    if texture == null:
        return Color(-1, -1, -1, -1)
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var i := (at.y * texture.size.x + at.x) * 8
    return Color(data.decode_half(i), data.decode_half(i + 2), data.decode_half(i + 4), data.decode_half(i + 6))


static func _grey(texel: Color, value: float) -> bool:
    return absf(texel.r - value) < 0.05 and absf(texel.g - value) < 0.05 and absf(texel.b - value) < 0.05 and texel.a > 0.95


func test_an_invert_layers_picture_is_the_paint_below_inverted() -> void:
    var thumb := _thumbnail(_adjustment("Invert", Bench.INVERT))
    assert_not_null(thumb._texture, "The Invert row has a picture drawn on the card")
    assert_false(thumb._bare, "and not the checker alone")
    var left := _texel(thumb, LEFT)
    var right := _texel(thumb, RIGHT)
    assert_true(_grey(left, 1.0), "White where the paint below is black: %s" % left)
    assert_true(_grey(right, 0.0), "Black where the paint below is white: %s" % right)
    thumb.free()


func test_a_curves_layers_picture_is_unlike_the_checker_alone() -> void:
    var thumb := _thumbnail(_adjustment("Curves", SaFilterRegistry.key_for(OWNER, SaCurvesFilter.new()), LIFT))
    assert_not_null(thumb._texture, "The Curves row has a picture drawn on the card")
    var left := _texel(thumb, LEFT)
    for checker: float in [SaLayerThumbnail.CHECKER_LIGHT, SaLayerThumbnail.CHECKER_DARK]:
        assert_false(_grey(left, checker), "The lifted black is not a grey of the checker, %s: %s" % [checker, left])
    assert_true(left.a > 0.95 and left.r > 0.3 and left.r < 0.95, "It is the curve's mid grey over black: %s" % left)
    assert_true(_grey(_texel(thumb, RIGHT), 1.0), "and white stays white under it")
    thumb.free()


## Painting the layer below dirties every row, and the picture follows on the
## next redraw the interval lets through.
func test_the_picture_follows_the_paint_below_within_one_refresh() -> void:
    var thumb := _thumbnail(_adjustment("Invert", Bench.INVERT))
    assert_true(_grey(_texel(thumb, LEFT), 1.0), "Before, the left half reads white")
    # The easel takes the dirty set every frame, and a position still in it
    # signals nothing when painted again.
    _easel.document.consume_dirty_chunks()
    _paint(Color(1.0, 1.0, 1.0, 1.0), Color(0.0, 0.0, 0.0, 1.0))
    thumb.mark_dirty()
    # A frame of its own, two on, whose share for pictures the cases before
    # spent none of, since the frame after one that spent it all rests.
    for _frame in 2:
        await (Engine.get_main_loop() as SceneTree).process_frame
    thumb._process(SaLayerThumbnail.REFRESH_SECONDS)
    var left := _texel(thumb, LEFT)
    var right := _texel(thumb, RIGHT)
    assert_true(_grey(left, 0.0), "After one refresh the left half reads black: %s" % left)
    assert_true(_grey(right, 1.0), "and the right half white: %s" % right)
    thumb.free()


## A group below is not plain, so the picture takes the walk of a flatten,
## and reads the same as the quick way does.
func test_a_group_below_takes_the_walk_and_reads_the_same() -> void:
    SaLayerOps.new(_easel.document).group_layers([_easel.document.get_node("Layer 1")])
    var layer := _adjustment("Invert", Bench.INVERT)
    assert_true(SaBackdropThumbnail.Quick.layers_below(_easel.document, layer).is_empty(), "A group below is not the quick way")
    var thumb := _thumbnail(layer)
    var left := _texel(thumb, LEFT)
    var right := _texel(thumb, RIGHT)
    assert_true(_grey(left, 1.0), "Through the walk the black half reads white: %s" % left)
    assert_true(_grey(right, 0.0), "and the white half black: %s" % right)
    thumb.free()


## A ground is brought down the quick way too, generated once: the document's
## grey ground under a Curves layer that lifts black to half reads lifted.
func test_the_ground_below_is_brought_down_the_quick_way() -> void:
    (_easel.document.get_node("Layer 1") as SaLayer).visible = false
    (_easel.document.get_node("Background") as SaLayer).visible = true
    var layer := _adjustment("Curves", SaFilterRegistry.key_for(OWNER, SaCurvesFilter.new()), LIFT)
    assert_eq(SaBackdropThumbnail.Quick.layers_below(_easel.document, layer).size(), 1, "The ground is the quick way")
    var thumb := _thumbnail(layer)
    var left := _texel(thumb, LEFT)
    assert_true(left.r > 0.6 and left.r < 0.9 and left.a > 0.95, "The grey ground reads lifted: %s" % left)
    thumb.free()


## Nothing below the layer is the checker alone, which costs no texture.
func test_an_adjustment_over_nothing_is_the_checker_alone() -> void:
    (_easel.document.get_node("Layer 1") as SaLayer).visible = false
    var thumb := _thumbnail(_adjustment("Invert", Bench.INVERT))
    var left := _texel(thumb, LEFT)
    assert_true(
        _grey(left, SaLayerThumbnail.CHECKER_LIGHT) or _grey(left, SaLayerThumbnail.CHECKER_DARK),
        "Over nothing the picture is the checker: %s" % left
    )
    thumb.free()


## The plate holds the document in one chunk across by a power of two, so a
## 4096 document is brought down sixteen times, and nothing is brought down that
## fits already.
func test_the_plate_brings_the_document_down_by_a_power_of_two() -> void:
    assert_eq(SaBackdropThumbnail.reduction(Vector2i(4096, 4096)), 16, "4096 by sixteen")
    assert_eq(SaBackdropThumbnail.reduction(Vector2i(1000, 700)), 4, "1000 by four")
    assert_eq(SaBackdropThumbnail.reduction(Vector2i(200, 100)), 1, "200 not at all")
    assert_eq(SaBackdropThumbnail.filled(Vector2i(1000, 700)), Rect2i(0, 0, 250, 175), "and fills 250 by 175")


## The measure the Done paragraph quotes: one refresh of an Invert row over a
## 4096 by 4096 document of five layers painted over the whole canvas, on the
## card, between two timestamps the device reads back frames later, so nothing
## waits on it. Twice: the whole plate drawn again, as after `document_changed`,
## and one chunk drawn again, as after a dab. Printed rather than held to a
## number, because the card running the suite is not always the one the budget
## was set on.
func test_one_refresh_over_a_large_document_is_timed_on_the_card() -> void:
    var easel := Bench.easel(Vector2i(4096, 4096))
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var ops := SaLayerOps.new(doc)
    var painted: Array[SaLayer] = [doc.get_node("Layer 1") as SaLayer]
    while painted.size() < 5:
        painted.append(ops.add())
    for i: int in painted.size():
        for grid_pos: Vector2i in SaLayer.grid_positions(doc.canvas_size):
            painted[i].get_or_create_chunk(grid_pos).clear(Color(0.2 * i, 0.5, 1.0 - 0.2 * i, 0.5))
    var layer := SaLayerOps.new(doc).add(SaBackdropLayer.TYPE_ID, _types)
    SaFilterOps.new(doc).attach(layer, Bench.INVERT)
    var thumb := SaLayerThumbnail.new()
    thumb.bind_layer(layer, doc)
    var whole := _timed(thumb, func() -> void: doc.document_changed.emit())
    var dab := Rect2i(0, 0, 64, 64)
    var one := _timed(
        thumb,
        func() -> void:
            doc.consume_dirty_chunks()
            doc.invalidate_chunk_regions({Vector2i(5, 5): dab}, painted[0])
    )
    print("Filter thumbnail: one refresh, 4096 by 4096 of five painted layers, whole plate: GPU ms %s, CPU ms %s" % whole)
    print("Filter thumbnail: one refresh, the same after one chunk moved: GPU ms %s, CPU ms %s" % one)
    assert_false(thumb._bare, "The picture over the five layers is drawn")
    thumb.free()
    easel.free()


## Ten refreshes of *thumb*, each after *before*, as `[gpu_ms, cpu_ms]`, two
## warming refreshes left out.
func _timed(thumb: SaLayerThumbnail, before: Callable) -> Array:
    var rd := RenderingServer.get_rendering_device()
    var runs := 12
    var cpu_ms: Array[float] = []
    var tag := "probe|%d|" % Time.get_ticks_usec()
    for i: int in runs:
        RenderingServer.force_draw(false)
        before.call()
        rd.capture_timestamp(tag + "%d|b" % i)
        var began := Time.get_ticks_usec()
        thumb.refresh()
        cpu_ms.append(snappedf((Time.get_ticks_usec() - began) / 1000.0, 0.01))
        rd.capture_timestamp(tag + "%d|e" % i)
    var stamps: Dictionary[String, int] = {}
    for i: int in rd.get_frame_delay() + 2:
        RenderingServer.force_draw(false)
        for at: int in rd.get_captured_timestamps_count():
            var name := rd.get_captured_timestamp_name(at)
            if name.begins_with(tag):
                stamps[name] = int(rd.get_captured_timestamp_gpu_time(at))
    var gpu_ms: Array[float] = []
    for i: int in range(2, runs):
        if stamps.has(tag + "%d|b" % i) and stamps.has(tag + "%d|e" % i):
            gpu_ms.append(snappedf((stamps[tag + "%d|e" % i] - stamps[tag + "%d|b" % i]) / 1.0e6, 0.001))
    return [gpu_ms, cpu_ms.slice(2)]
