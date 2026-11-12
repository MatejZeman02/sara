## A live transform moves a relief layer's height with its
## colour. The height resamples through the map and the read the colour takes,
## its values kept and never multiplied by the scale, a flip leaving its sign,
## in the cache the view lights and in the bake, and the undo of a bake gives
## every byte of it back.
##
## The painting is two chunks across and two down, the grey background hidden,
## and one layer named Paint holding an opaque square of colour and a plateau
## of height under it, PLATEAU millimetres, written whole rather than by a
## brush, since the brush is not what this suite is about. The square crosses
## the seam between the chunks at (0, 0) and (1, 0), so a read that stopped at
## a chunk's edge shows as a step there.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 512)
## The square in document pixels, across the seam at x 256.
const SQUARE := Rect2i(200, 40, 112, 96)
const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const PLATEAU := 2.0
const MIDDLE := Vector2(256.0, 256.0)
## A move by whole pixels, which takes every texel onto a texel.
const MOVE := Vector2i(-40, 200)
## What a half float holds of PLATEAU, and of nought.
const EXACT := 1.0e-3


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
    paint.add_field(SaFieldSpec.height())
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        var cell := Rect2i(grid_pos * SaLayer.CHUNK_SIZE, Vector2i(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE))
        var local := Rect2i(SQUARE.intersection(cell).position - cell.position, SQUARE.intersection(cell).size)
        _write(paint.get_or_create_chunk(grid_pos).albedo(), local, PAINT, Image.FORMAT_RGBAF)
        _write(paint.get_or_create_field(grid_pos, SaFieldSpec.HEIGHT), local, Color(PLATEAU, 0, 0, 0), Image.FORMAT_RF)
        paint.mark_unresolved(grid_pos)
    Bench.composite(easel)
    return easel


## Writes *rect* of *texture* as *value* and the rest as nought, through an
## image of *format* converted to the texture's own.
static func _write(texture: SaTexture, rect: Rect2i, value: Color, format: Image.Format) -> void:
    var image := Image.create_empty(texture.size.x, texture.size.y, false, format)
    image.fill_rect(rect, value)
    if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
        image.convert(Image.FORMAT_RGBAH)
    elif texture.format == SaFieldSpec.HEIGHT_FORMAT:
        image.convert(Image.FORMAT_RH)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


## The height *layer* holds at the document position *at*, nought where it
## holds none.
static func _height(layer: SaLayer, at: Vector2i) -> float:
    var side := SaLayer.CHUNK_SIZE
    var grid_pos := Vector2i(floori(float(at.x) / side), floori(float(at.y) / side))
    var texture := layer.get_field(grid_pos, SaFieldSpec.HEIGHT)
    return Bench.texel(texture, at - grid_pos * side).r if texture != null else 0.0


## The highest height *layer* holds, read over every chunk of it.
static func _peak(layer: SaLayer) -> float:
    var highest := 0.0
    for chunk: SaChunk in layer.chunks.values():
        var texture := chunk.field(SaFieldSpec.HEIGHT)
        if texture == null:
            continue
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        for i in range(texture.size.x * texture.size.y):
            highest = maxf(highest, bytes.decode_half(i * 2))
    return highest


## Every byte of every height *layer* holds, by grid position.
static func _heights(layer: SaLayer) -> Dictionary:
    var found := {}
    for grid_pos: Vector2i in layer.chunks:
        var texture := (layer.chunks[grid_pos] as SaChunk).field(SaFieldSpec.HEIGHT)
        if texture != null:
            found[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return found


## The summed height the view lights at *at*, which is what a shot of the lit
## view shows.
static func _lit(easel: SaEasel, at: Vector2i) -> float:
    return Bench.texel(easel.relief.heights, at).r if easel.relief.heights != null else 0.0


## Bakes *map* on Paint and answers whether the bake ran, after checking the
## undo gives every byte of the height back and the redo puts the bake back.
func _bake_and_undo(easel: SaEasel, map: Basis, what: String) -> bool:
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var before := _heights(paint)
    assert_true(SaLiveTransform.put(doc, paint, map), "%s: the relief layer takes the map" % what)
    Bench.composite(easel)
    assert_true(SaLiveTransform.bake(doc, paint), "%s: the bake runs" % what)
    var baked := _heights(paint)
    assert_true(doc.undo(), "%s: the bake undoes" % what)
    assert_eq(_heights(paint), before, "%s: one undo of the bake gives back every byte of the height" % what)
    assert_true(doc.redo(), "%s: and redoes" % what)
    assert_eq(_heights(paint), baked, "%s: the redo gives the baked height back" % what)
    return true


func test_a_relief_layer_takes_a_live_transform_with_no_refusal() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var map := SaLiveTransform.composed(Vector2(MOVE), 0.0, Vector2.ONE, MIDDLE)
    assert_eq(SaLiveTransform.refusal(doc, paint, map), "", "A relief is no refusal")
    assert_true(SaLiveTransform.put(doc, paint, map), "The map is put")
    assert_true(SaProblems.pending_refusals.is_empty(), "and the corner says nothing: %s" % SaProblems.pending_refusals)
    paint.is_locked = true
    assert_false(SaLiveTransform.refusal(doc, paint, map).is_empty(), "A locked relief layer is refused as any is")
    easel.free()


func test_a_move_by_whole_pixels_carries_the_height_live_and_into_the_bake() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var old := SQUARE.position + Vector2i(4, 4)
    var new := old + MOVE
    assert_almost_eq(_lit(easel, old), PLATEAU, EXACT, "Before the move the view lights the plateau where it was painted")
    var map := SaLiveTransform.composed(Vector2(MOVE), 0.0, Vector2.ONE, MIDDLE)
    assert_true(SaLiveTransform.put(doc, paint, map), "The move is put")
    Bench.composite(easel)
    var cache := SaLiveTransform.paint_of(paint)
    assert_almost_eq(_height(cache, new), PLATEAU, EXACT, "The cache holds the height at the new place")
    assert_almost_eq(_lit(easel, new), PLATEAU, EXACT, "and the view lights it there")
    assert_almost_eq(_lit(easel, old), 0.0, EXACT, "and nothing at the old place")
    var seam := Vector2i(256, SQUARE.position.y + 10)
    assert_almost_eq(_lit(easel, seam + MOVE), PLATEAU, EXACT, "with no step where the seam of the source went")
    assert_almost_eq(_lit(easel, seam + MOVE - Vector2i.RIGHT), PLATEAU, EXACT, "on either side of it")
    assert_true(SaLiveTransform.bake(doc, paint), "The bake runs")
    assert_almost_eq(_height(paint, new), PLATEAU, EXACT, "The baked layer holds the height at the new place")
    assert_almost_eq(_height(paint, old), 0.0, EXACT, "and nought at the old place")
    assert_almost_eq(_height(paint, SQUARE.end - Vector2i.ONE + MOVE), PLATEAU, EXACT, "to the square's last texel")
    assert_almost_eq(_height(paint, SQUARE.end + MOVE), 0.0, EXACT, "and nothing past it")
    easel.free()


func test_a_scale_by_two_keeps_the_height_and_widens_the_plateau() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var map := SaLiveTransform.composed(Vector2.ZERO, 0.0, Vector2(2.0, 2.0), Vector2(256.0, 88.0))
    var middle := Vector2i(256, 88)
    if not _bake_and_undo(easel, map, "Scaled by two"):
        return
    var peak := _peak(paint)
    assert_true(absf(peak - PLATEAU) <= PLATEAU * 0.01, "The peak stays within one per cent, %s" % peak)
    assert_almost_eq(_height(paint, middle), PLATEAU, EXACT, "at the middle of the plateau")
    var wide := Vector2i(256 + 100, 88)
    assert_almost_eq(_height(paint, wide), PLATEAU, EXACT, "which reaches twice as far, %s" % wide)
    easel.free()


func test_a_turn_by_thirty_degrees_keeps_the_peak() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var map := SaLiveTransform.composed(Vector2(0.0, 120.0), 30.0, Vector2.ONE, MIDDLE)
    if not _bake_and_undo(easel, map, "Turned by thirty degrees"):
        return
    var peak := _peak(paint)
    assert_true(absf(peak - PLATEAU) <= PLATEAU * 0.01, "The peak stays within one per cent, %s" % peak)
    var centre := Vector2(SQUARE.get_center())
    var moved := map * Vector3(centre.x, centre.y, 1.0)
    var landed := Vector2i(roundi(moved.x / moved.z), roundi(moved.y / moved.z))
    assert_almost_eq(_height(paint, landed), PLATEAU, PLATEAU * 0.01, "at the turned plateau's middle %s" % landed)
    easel.free()


func test_a_flip_leaves_the_height_s_sign() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var map := SaLiveTransform.composed(Vector2.ZERO, 0.0, Vector2(-1.0, 1.0), Vector2(256.0, 88.0))
    assert_true(SaLiveTransform.put(doc, paint, map), "The flip is put")
    Bench.composite(easel)
    assert_true(SaLiveTransform.bake(doc, paint), "and baked")
    assert_almost_eq(_height(paint, Vector2i(256 + 30, 60)), PLATEAU, EXACT, "A ridge stays a ridge seen from the other side")
    assert_almost_eq(_height(paint, Vector2i(256 - 30, 60)), PLATEAU, EXACT, "on both sides of the flip")
    easel.free()


func test_the_cache_s_height_carries_the_layer_s_mask_and_the_view_does_not_mask_it_twice() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    assert_true(SaMaskOps.new(doc).add(paint), "Paint gets a mask")
    var mask := SaMaskOps.mask_of(paint)
    var field := mask.get_or_create(Vector2i.ZERO)
    _write(field, Rect2i(Vector2i.ZERO, field.size), Color(0.5, 0, 0, 0), Image.FORMAT_RF)
    paint.mark_unresolved(Vector2i.ZERO)
    var map := SaLiveTransform.composed(Vector2(MOVE), 0.0, Vector2.ONE, MIDDLE)
    assert_true(SaLiveTransform.put(doc, paint, map), "The move is put")
    Bench.composite(easel)
    var at := SQUARE.position + Vector2i(4, 4)
    assert_almost_eq(_lit(easel, at + MOVE), PLATEAU * 0.5, EXACT, "The view lights the height at the mask's half once")
    easel.free()
