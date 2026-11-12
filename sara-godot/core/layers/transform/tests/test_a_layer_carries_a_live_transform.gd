## A layer carries a live transform the compositor draws it
## through. The layer keeps its own chunks as they were painted, the canvas
## shows the paint where the map takes it, and the map is saved with the layer
## and undone as one step. A brush paints through a move, a turn or a scale
## now, whose suite beside this one hears a perspective refused.
##
## The painting: two chunks across and two down, the grey background hidden,
## and one layer named Paint holding an opaque square in its first chunk. The
## map turns it a quarter clockwise about the canvas's middle and moves it down
## by a chunk, which takes the texel at (x, y) to (511 - y, x + 256), so the
## square lands whole in the chunk at (1, 1) with every texel on a texel.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 512)
const SQUARE := Rect2i(32, 32, 64, 64)
const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const MIDDLE := Vector2(256.0, 256.0)
const MOVE := Vector2(0.0, 256.0)
## Where the square's texels land: x from 511 - 95 and y from 32 + 256.
const LANDED := Rect2i(416, 288, 64, 64)
const TOLERANCE := 1.0e-4
## A file saved before this row, version 4.
const OLD_FILE := "res://tests/data/plain_v4.sad"


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()


## The painting of the header, with Paint active.
func _painting() -> SaEasel:
    var easel := Bench.easel(SIZE)
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var paint := doc.get_node("Layer 1") as SaLayer
    paint.name = "Paint"
    doc.set_active_layer(paint)
    _paint_square(paint)
    Bench.composite(easel)
    return easel


## Paints SQUARE in PAINT on *layer*'s chunk at the origin, uploaded whole,
## since the brush is not what this suite is about.
static func _paint_square(layer: SaLayer) -> void:
    var texture := layer.get_or_create_chunk(Vector2i.ZERO).albedo()
    var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAF)
    image.fill_rect(SQUARE, PAINT)
    if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
        image.convert(Image.FORMAT_RGBAH)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    layer.mark_unresolved(Vector2i.ZERO)


## The map of the header.
static func _turned() -> Basis:
    return SaLiveTransform.composed(MOVE, 90.0, Vector2.ONE, MIDDLE)


static func _bytes(texture: SaTexture) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


static func _near(a: Color, b: Color) -> bool:
    return (
        absf(a.r - b.r) <= TOLERANCE
        and absf(a.g - b.g) <= TOLERANCE
        and absf(a.b - b.b) <= TOLERANCE
        and absf(a.a - b.a) <= TOLERANCE
    )


## Reads the square where *easel* shows it at *square* and nothing at *empty*,
## its corners and its middle both.
func _shows(easel: SaEasel, square: Rect2i, empty: Rect2i, what: String) -> void:
    for at: Vector2i in [square.position, square.end - Vector2i.ONE, square.get_center()]:
        var shown := Bench.texel(easel.output, at)
        assert_true(_near(shown, PAINT), "%s: the square's colour at %s, %s" % [what, at, shown])
    for at: Vector2i in [empty.position, empty.end - Vector2i.ONE, empty.get_center()]:
        var shown := Bench.texel(easel.output, at)
        assert_true(shown.a <= TOLERANCE, "%s: nothing at %s, %s" % [what, at, shown])
    var outside := Bench.texel(easel.output, square.position - Vector2i.ONE)
    assert_true(outside.a <= TOLERANCE, "%s: nothing just outside the square, %s" % [what, outside])


## Composites what the document says changed, as a frame of the app does after
## an undo. A full composite walks the chunks the layers hold, and the place a
## map took the paint to is not one of them once the map is gone.
static func _redraw(easel: SaEasel) -> void:
    easel.document.update_caches()
    easel.process_pending_composite()


func test_the_canvas_shows_the_square_turned_and_moved_and_the_layer_keeps_its_chunks() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var painted := _bytes(paint.get_field(Vector2i.ZERO))
    _shows(easel, SQUARE, LANDED, "Before the map")
    assert_true(SaLiveTransform.put(doc, paint, _turned()), "The map is put on the layer")
    Bench.composite(easel)
    _shows(easel, LANDED, SQUARE, "Through the map, the layer active")
    assert_eq(paint.chunks.keys(), [Vector2i.ZERO], "The layer holds the one chunk it was painted in")
    assert_eq(_bytes(paint.get_field(Vector2i.ZERO)), painted, "and its bytes are the bytes painted")
    var cache := SaLiveTransform.paint_of(paint)
    assert_eq(cache.chunks.keys(), [Vector2i(1, 1)], "The cache holds a chunk only where the moved paint lands")
    SaLayerOps.new(doc).add()
    Bench.composite(easel)
    _shows(easel, LANDED, SQUARE, "Through the map, another layer active")
    easel.free()


func test_a_change_of_the_paint_redraws_where_the_map_takes_it() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    SaLiveTransform.put(doc, paint, _turned())
    SaLayerOps.new(doc).add()
    Bench.composite(easel)
    paint.get_field(Vector2i.ZERO).clear(Color(0.0, 0.0, 0.0, 0.0))
    paint.mark_unresolved(Vector2i.ZERO)
    doc.invalidate_chunks([Vector2i.ZERO])
    easel.process_pending_composite()
    var gone := Bench.texel(easel.output, LANDED.get_center())
    assert_true(gone.a <= TOLERANCE, "Paint taken off the layer leaves the place it showed, %s" % gone)
    easel.free()


func test_it_saves_and_opens_with_its_map_and_an_older_file_has_none() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var map := SaLiveTransform.composed(MOVE, 30.0, Vector2(1.25, 0.75), MIDDLE)
    SaLiveTransform.put(doc, paint, map)
    Bench.composite(easel)
    assert_eq(SaSadFile.version_for(doc), SaSadFile.SAD_VERSION_LIVE_TRANSFORM, "A document with a live transform takes 9")
    var path := ProjectSettings.globalize_path(SaDataRoot.path("g1_live_transform.sad"))
    assert_eq(SaExport.save_sad(doc, path), OK, "It saves")
    var loaded := Bench.easel(SIZE)
    assert_eq(SaExport.load_sad(loaded.document, path, loaded.compositor), OK, "It opens")
    DirAccess.remove_absolute(path)
    var reopened := SaLiveTransform.of(loaded.document.get_node("Paint") as SaLayer)
    assert_not_null(reopened, "with the layer's live transform")
    if reopened != null:
        assert_true(reopened.matrix.is_equal_approx(map), "holding the map, %s against %s" % [reopened.matrix, map])
    Bench.composite(loaded)
    var worst := 0.0
    var before := _bytes(easel.output)
    var after := _bytes(loaded.output)
    for y in range(0, SIZE.y, 5):
        for x in range(0, SIZE.x, 5):
            var p := SaFieldSpec.decode_texel(before, easel.output.format, y * SIZE.x + x)
            var q := SaFieldSpec.decode_texel(after, loaded.output.format, y * SIZE.x + x)
            worst = maxf(worst, maxf(absf(p.a - q.a), absf(p.r * p.a - q.r * q.a)))
    assert_true(worst <= TOLERANCE, "and the composite reads as it did, worst %s" % worst)
    var older := SaDocument.new()
    assert_eq(
        SaExport.load_sad(older, ProjectSettings.globalize_path(OLD_FILE), SaCompositor.new()),
        OK,
        "A file from before the key opens"
    )
    var layers := older.get_children().filter(func(c: Node) -> bool: return c is SaLayer)
    assert_false(layers.is_empty(), "with its layers")
    for layer: SaLayer in layers:
        assert_null(layer.live_transform, "and %s has no live transform" % layer.name)
    older.free()
    easel.free()
    loaded.free()


func test_undo_puts_the_square_back_where_it_was_painted() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    SaLiveTransform.put(doc, paint, _turned())
    Bench.composite(easel)
    _shows(easel, LANDED, SQUARE, "Through the map")
    assert_true(doc.undo(), "The map is one step")
    _redraw(easel)
    assert_null(paint.live_transform, "Undone, the layer has no map")
    _shows(easel, SQUARE, LANDED, "Undone")
    assert_true(doc.redo(), "and redone")
    _redraw(easel)
    _shows(easel, LANDED, SQUARE, "Redone")
    easel.free()


func test_what_cannot_be_drawn_through_a_map_is_refused_with_a_sentence() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    assert_false(
        SaLiveTransform.put(doc, paint, Basis(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, 1))), "A map that folds flat is refused"
    )
    assert_true(
        "\n".join(SaProblems.pending_refusals).contains("flat"), "with a sentence: %s" % "\n".join(SaProblems.pending_refusals)
    )
    # w is 1 - x / 100, nought a fifth of the way across.
    var horizon := Basis(Vector3(1, 0, -0.01), Vector3(0, 1, 0), Vector3(0, 0, 1))
    assert_false(SaLiveTransform.put(doc, paint, horizon), "A perspective whose horizon crosses the canvas is refused")
    assert_true("\n".join(SaProblems.pending_refusals).contains("horizon"), "and says so")
    paint.is_locked = true
    assert_false(SaLiveTransform.put(doc, paint, _turned()), "A locked layer is refused")
    assert_true("\n".join(SaProblems.pending_refusals).contains("locked"), "and says so")
    assert_null(paint.live_transform, "and none of them put a map on")
    easel.free()


func test_four_corners_make_a_map_that_takes_the_canvas_corners_there() -> void:
    var canvas := Rect2(Vector2.ZERO, Vector2(SIZE))
    var corners := PackedVector2Array([Vector2(40, 10), Vector2(470, 60), Vector2(500, 480), Vector2(20, 400)])
    var map: Variant = SaLiveTransform.cornered(canvas, corners)
    assert_true(map is Basis, "Four corners make a map")
    var live := SaLiveTransform.new(map)
    var at := [canvas.position, Vector2(canvas.end.x, 0.0), canvas.end, Vector2(0.0, canvas.end.y)]
    for i in range(4):
        var landed := live.map_point(at[i])
        assert_true(landed.distance_to(corners[i]) < 1.0e-2, "Corner %d lands at %s, %s" % [i, corners[i], landed])
    var turned := SaLiveTransform.new(_turned())
    assert_eq(turned.map_point(Vector2(32.5, 32.5)), Vector2(479.5, 288.5), "A quarter turn is exact")
    assert_null(
        SaLiveTransform.cornered(canvas, PackedVector2Array([Vector2.ZERO, Vector2(1, 1), Vector2(2, 2), Vector2(3, 3)])),
        "Corners on a line make none"
    )
