## Layer > Convert to Ordinary Layer writes the transformed picture into
## the layer once. The bake writes what the cache shows into the layer's own
## chunks and takes the transform off, as one history step whose undo gives
## both back. Merge Down and Flatten take a transformed layer as it is drawn,
## the upper one read through its cache and a lower or bottom one baked on the
## way, and a mask moves with the paint it covers.
##
## The painting: two chunks across and two down, the grey background
## hidden, and one layer named Paint holding an opaque square in its first
## chunk. The map turns it a quarter clockwise about the canvas's middle and
## moves it down by a chunk, which takes the texel at (x, y) to
## (511 - y, x + 256), so the square lands whole in the chunk at (1, 1) with
## every texel on a texel, and the bake can be read for exact bytes.
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
## The chunk LANDED is in, and LANDED inside it.
const LANDED_CHUNK := Vector2i(1, 1)
const LANDED_LOCAL := Rect2i(160, 32, 64, 64)
## A second square, on a layer with no map, in the chunk at (1, 0).
const DOT := Rect2i(300, 40, 40, 40)
const DOT_CHUNK := Vector2i(1, 0)
const DOT_LOCAL := Rect2i(44, 40, 40, 40)
const DOT_PAINT := Color(0.9, 0.2, 0.1, 1.0)
const TOLERANCE := 1.0e-4


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
    _paint(paint, Vector2i.ZERO, SQUARE, PAINT)
    Bench.composite(easel)
    return easel


## Paints *rect* of *layer*'s chunk at *grid_pos* in *colour*, uploaded whole,
## since the brush is not what this suite is about.
static func _paint(layer: SaLayer, grid_pos: Vector2i, rect: Rect2i, colour: Color) -> void:
    var texture := layer.get_or_create_chunk(grid_pos).albedo()
    var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAF)
    image.fill_rect(rect, colour)
    if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
        image.convert(Image.FORMAT_RGBAH)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    layer.mark_unresolved(grid_pos)


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


## Composites what the document says changed, as a frame of the app does after
## an undo, the way the sibling suite does.
static func _redraw(easel: SaEasel) -> void:
    easel.document.update_caches()
    easel.process_pending_composite()


## Reads *colour* in *texture* at the corners and the middle of *rect*, and
## nothing just outside it.
func _holds(texture: SaTexture, rect: Rect2i, colour: Color, what: String) -> void:
    for at: Vector2i in [rect.position, rect.end - Vector2i.ONE, rect.get_center()]:
        var read := Bench.texel(texture, at)
        assert_true(_near(read, colour), "%s: %s at %s, %s" % [what, colour, at, read])
    var outside := Bench.texel(texture, rect.position - Vector2i.ONE)
    assert_true(outside.a <= TOLERANCE, "%s: nothing just outside, %s" % [what, outside])


## Composites what the document says changed and then the whole canvas, which
## is what a frame after each step would have drawn. A full composite alone
## walks the chunks the layers draw and drops the changed set, so the chunk a
## map took the paint away from kept the square it showed before the map when
## another step came between the map and the composite.
static func _settle(easel: SaEasel) -> void:
    _redraw(easel)
    Bench.composite(easel)


## Reads *easel*'s canvas against *canvas*, the bytes it held before, texel by
## texel and premultiplied, since a texel nothing covers reads as nothing
## whatever colour it holds, and names the worst texel when one moved.
func _reads_as(easel: SaEasel, canvas: PackedByteArray, what: String) -> void:
    var now := _bytes(easel.output)
    var worst := 0.0
    var where := Vector2i(-1, -1)
    var pair := []
    for y in range(SIZE.y):
        for x in range(SIZE.x):
            var p := SaFieldSpec.decode_texel(canvas, easel.output.format, y * SIZE.x + x)
            var q := SaFieldSpec.decode_texel(now, easel.output.format, y * SIZE.x + x)
            var off := maxf(maxf(absf(p.r * p.a - q.r * q.a), absf(p.g * p.a - q.g * q.a)), absf(p.a - q.a))
            off = maxf(off, absf(p.b * p.a - q.b * q.a))
            if off > worst:
                worst = off
                where = Vector2i(x, y)
                pair = [p, q]
    assert_true(worst <= TOLERANCE, "%s, worst %s at %s, %s" % [what, worst, where, pair])


## The one layer a flatten leaves.
static func _only_layer(doc: SaDocument) -> SaLayer:
    var layers := doc.get_children().filter(func(c: Node) -> bool: return c is SaLayer)
    return layers[0] if layers.size() == 1 else null


func test_the_bake_writes_what_the_cache_shows_into_the_layer_and_takes_the_map_off() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    assert_false(SaLiveTransform.can_bake(paint), "A layer with no map has nothing to bake")
    assert_false(SaLiveTransform.bake(doc, paint), "and the bake does nothing")
    var painted := _bytes(paint.get_field(Vector2i.ZERO))
    SaLiveTransform.put(doc, paint, _turned())
    Bench.composite(easel)
    assert_true(SaLiveTransform.can_bake(paint), "A layer with a map can be baked")
    var shown := _bytes(SaLiveTransform.paint_of(paint).get_field(LANDED_CHUNK))
    var canvas := _bytes(easel.output)
    var steps := doc.history.step_count()
    assert_true(SaLiveTransform.bake(doc, paint), "The bake runs")
    assert_eq(doc.history.step_count(), steps + 1, "as one history step")
    assert_null(paint.live_transform, "and the layer has no map left")
    assert_false(SaLiveTransform.can_bake(paint), "so there is nothing more to bake")
    assert_eq(paint.chunks.keys(), [LANDED_CHUNK], "The layer holds a chunk only where the paint was drawn")
    assert_eq(_bytes(paint.get_field(LANDED_CHUNK)), shown, "holding the bytes the cache showed")
    _holds(paint.get_field(LANDED_CHUNK), LANDED_LOCAL, PAINT, "The layer's own chunk")
    _redraw(easel)
    Bench.composite(easel)
    _reads_as(easel, canvas, "The canvas reads as it did through the map")
    assert_true(doc.undo(), "The bake undoes")
    _redraw(easel)
    var back := SaLiveTransform.of(paint)
    assert_not_null(back, "Undone, the map is on again")
    if back != null:
        assert_true(back.matrix.is_equal_approx(_turned()), "the same map, %s" % back.matrix)
    assert_eq(paint.chunks.keys(), [Vector2i.ZERO], "the layer holds the chunk it was painted in")
    assert_eq(_bytes(paint.get_field(Vector2i.ZERO)), painted, "with the bytes painted")
    Bench.composite(easel)
    _reads_as(easel, canvas, "and the canvas reads as it did")
    assert_true(doc.redo(), "Redone")
    _redraw(easel)
    assert_null(paint.live_transform, "the map is off again")
    assert_eq(paint.chunks.keys(), [LANDED_CHUNK], "and the baked chunk is back")
    assert_eq(_bytes(paint.get_field(LANDED_CHUNK)), shown, "with the bytes the cache showed")
    easel.free()


func test_a_locked_layer_is_refused_with_a_sentence() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    SaLiveTransform.put(doc, paint, _turned())
    paint.is_locked = true
    var steps := doc.history.step_count()
    assert_false(SaLiveTransform.bake(doc, paint), "A locked layer is not baked")
    assert_true("\n".join(SaProblems.pending_refusals).contains("locked"), "and the corner says why")
    assert_not_null(paint.live_transform, "The map stays on")
    assert_eq(paint.chunks.keys(), [Vector2i.ZERO], "the paint stays where it was painted")
    assert_eq(doc.history.step_count(), steps, "and no step is taken")
    easel.free()


func test_a_mask_moves_with_the_paint_it_covers() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    assert_true(SaMaskOps.new(doc).add(paint), "Paint gets a mask")
    var mask := SaMaskOps.mask_of(paint)
    var rest := mask.rest
    # Zero over the left half of the square, which the map takes to its top half.
    var field := mask.get_or_create(Vector2i.ZERO)
    var hidden := Image.create_empty(field.size.x, field.size.y, false, Image.FORMAT_RF)
    hidden.fill(Color(1, 0, 0, 0))
    hidden.fill_rect(Rect2i(0, 0, 64, field.size.y), Color(0, 0, 0, 0))
    var data := hidden.get_data() if field.format == RenderingDevice.DATA_FORMAT_R32_SFLOAT else PackedByteArray()
    if data.is_empty():
        hidden.convert(Image.FORMAT_RH)
        data = hidden.get_data()
    GlobalShaderCompiler.get_rd().texture_update(field.rid, 0, data)
    paint.mark_unresolved(Vector2i.ZERO)
    SaLiveTransform.put(doc, paint, _turned())
    Bench.composite(easel)
    var top := Rect2i(LANDED.position, Vector2i(LANDED.size.x, 32))
    var bottom := Rect2i(LANDED.position + Vector2i(0, 32), Vector2i(LANDED.size.x, 32))
    assert_true(Bench.texel(easel.output, top.get_center()).a <= TOLERANCE, "Through the map the mask hides the top half")
    assert_true(_near(Bench.texel(easel.output, bottom.get_center()), PAINT), "and shows the bottom half")
    assert_true(SaLiveTransform.bake(doc, paint), "The masked layer bakes")
    _redraw(easel)
    Bench.composite(easel)
    assert_true(Bench.texel(easel.output, top.get_center()).a <= TOLERANCE, "Baked, the mask still hides the top half")
    assert_true(_near(Bench.texel(easel.output, bottom.get_center()), PAINT), "and shows the bottom half")
    var moved := SaMaskOps.mask_of(paint)
    assert_not_null(moved, "The layer keeps its mask")
    if moved != null:
        assert_almost_eq(moved.rest, rest, TOLERANCE, "reading what it read where it holds nothing")
        var at := LANDED_LOCAL.position + Vector2i(8, 8)
        assert_true(Bench.texel(moved.coverage(LANDED_CHUNK), at).r <= TOLERANCE, "and zero where the hidden half went")
        at = LANDED_LOCAL.position + Vector2i(8, 40)
        assert_true(Bench.texel(moved.coverage(LANDED_CHUNK), at).r >= 1.0 - TOLERANCE, "and one where the shown half went")
    var shown := Bench.texel(paint.get_field(LANDED_CHUNK), LANDED_LOCAL.position + Vector2i(8, 40))
    assert_true(_near(shown, PAINT), "The paint under the shown half moved too, %s" % shown)
    assert_true(doc.undo(), "Undone")
    _redraw(easel)
    assert_not_null(paint.live_transform, "the map is on again")
    assert_eq(paint.chunks.keys(), [Vector2i.ZERO], "over the chunk the paint and the mask were in")
    easel.free()


func test_merge_down_takes_a_transformed_upper_layer_as_it_is_drawn() -> void:
    var easel := Bench.easel(SIZE)
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var below := doc.get_node("Layer 1") as SaLayer
    below.name = "Below"
    doc.set_active_layer(below)
    var upper := SaLayerOps.new(doc).add()
    upper.name = "Paint"
    _paint(upper, Vector2i.ZERO, SQUARE, PAINT)
    SaLiveTransform.put(doc, upper, _turned())
    Bench.composite(easel)
    var canvas := _bytes(easel.output)
    var steps := doc.history.step_count()
    assert_true(SaLayerOps.new(doc).merge_down(upper), "The transformed layer merges down")
    assert_eq(doc.history.step_count(), steps + 1, "as one step")
    assert_true(below.chunks.has(LANDED_CHUNK), "The layer below holds the chunk the map drew the paint in")
    assert_false(below.chunks.has(Vector2i.ZERO), "and none where the paint was painted")
    _holds(below.get_field(LANDED_CHUNK), LANDED_LOCAL, PAINT, "The layer below")
    _redraw(easel)
    Bench.composite(easel)
    _reads_as(easel, canvas, "The canvas reads as it did")
    assert_true(doc.undo(), "The merge undoes")
    _redraw(easel)
    var back := doc.get_node_or_null("Paint") as SaLayer
    assert_not_null(back, "The upper layer is back")
    if back != null:
        assert_not_null(back.live_transform, "with its map")
        assert_eq(back.chunks.keys(), [Vector2i.ZERO], "and its own chunk")
    assert_true(below.chunks.is_empty(), "and the layer below is empty again")
    easel.free()


func test_merge_down_into_a_transformed_layer_bakes_it_on_the_way() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var painted := _bytes(paint.get_field(Vector2i.ZERO))
    SaLiveTransform.put(doc, paint, _turned())
    var upper := SaLayerOps.new(doc).add()
    _paint(upper, DOT_CHUNK, DOT_LOCAL, DOT_PAINT)
    _settle(easel)
    var canvas := _bytes(easel.output)
    assert_true(SaLayerOps.new(doc).merge_down(upper), "A layer merges down into a transformed one")
    assert_null(paint.live_transform, "whose map is baked and taken off")
    _holds(paint.get_field(LANDED_CHUNK), LANDED_LOCAL, PAINT, "Its square, where the map drew it")
    _holds(paint.get_field(DOT_CHUNK), DOT_LOCAL, DOT_PAINT, "The upper layer's square, where it was")
    assert_false(paint.chunks.has(Vector2i.ZERO), "and nothing where the square was painted")
    _redraw(easel)
    Bench.composite(easel)
    _reads_as(easel, canvas, "The canvas reads as it did")
    assert_true(doc.undo(), "The merge undoes")
    _redraw(easel)
    assert_not_null(paint.live_transform, "the map is on again")
    assert_eq(paint.chunks.keys(), [Vector2i.ZERO], "over the chunk it was painted in")
    assert_eq(_bytes(paint.get_field(Vector2i.ZERO)), painted, "with the bytes painted")
    Bench.composite(easel)
    _reads_as(easel, canvas, "and the canvas reads as it did")
    easel.free()


func test_flatten_takes_every_transformed_layer_as_it_is_drawn() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    doc.move_child(paint, 0)
    var upper := SaLayerOps.new(doc).add()
    _paint(upper, Vector2i.ZERO, SQUARE, DOT_PAINT)
    # The upper square turns about the canvas's middle and stays in its row, so
    # it lands at (416, 32), clear of Paint's.
    var level := SaLiveTransform.composed(Vector2.ZERO, 90.0, Vector2.ONE, MIDDLE)
    SaLiveTransform.put(doc, paint, _turned())
    SaLiveTransform.put(doc, upper, level)
    _settle(easel)
    var canvas := _bytes(easel.output)
    assert_true(SaLayerOps.new(doc).flatten(), "A stack with two transformed layers flattens")
    var flat := _only_layer(doc)
    assert_not_null(flat, "into one layer")
    if flat != null:
        assert_null(flat.live_transform, "with no map left on it")
        _holds(flat.get_field(LANDED_CHUNK), LANDED_LOCAL, PAINT, "The bottom layer's square, where its map drew it")
        _holds(flat.get_field(DOT_CHUNK), Rect2i(160, 32, 64, 64), DOT_PAINT, "The upper one's, where its map drew it")
        assert_false(flat.chunks.has(Vector2i.ZERO), "and nothing where either was painted")
    _redraw(easel)
    Bench.composite(easel)
    _reads_as(easel, canvas, "The canvas reads as it did")
    assert_true(doc.undo(), "The flatten undoes")
    _redraw(easel)
    assert_not_null(paint.live_transform, "Paint has its map again")
    assert_eq(paint.chunks.keys(), [Vector2i.ZERO], "over the chunk it was painted in")
    assert_not_null(upper.live_transform, "and so has the upper layer")
    Bench.composite(easel)
    _reads_as(easel, canvas, "and the canvas reads as it did")
    easel.free()
