## A layer made smart keeps its untransformed source, and its
## transform can be reset. Make Smart Layer marks a painted layer, a chain of
## transforms ending at one map draws what one transform of an untouched copy
## to that map draws, the layer's own chunks are what was painted throughout,
## Reset Transform draws the source where it was painted and leaves the layer
## smart, Convert to Ordinary Layer writes the picture in once, and a smart
## layer saves and opens with its marker, its map and its source.
##
## The painting: two chunks across and two down, the grey background
## hidden, and one layer named Paint holding an opaque square in its first
## chunk, with a softer square beside it so a resample has edges to blur.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const LayersReport = preload("res://harness/report/sa_layers_report.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 512)
const SQUARE := Rect2i(32, 32, 64, 64)
const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const SOFT := Rect2i(120, 40, 30, 50)
const SOFT_PAINT := Color(0.9, 0.3, 0.1, 0.5)
const MIDDLE := Vector2(256.0, 256.0)
## The last map of the chain, which the untouched copy is drawn through once.
const LAST_MOVE := Vector2(140.0, 120.0)
const LAST_TURN := 30.0
const LAST_SCALE := Vector2(1.3, 1.3)
## How far apart the chained layer's picture and the copy's may read. The two
## are resampled from the same chunks through the same map, so they read
## alike to the byte, and the bound only takes a float's last place.
const SAME := 1.0e-6


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
    var texture := paint.get_or_create_chunk(Vector2i.ZERO).albedo()
    var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAF)
    image.fill_rect(SQUARE, PAINT)
    image.fill_rect(SOFT, SOFT_PAINT)
    if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
        image.convert(Image.FORMAT_RGBAH)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    paint.mark_unresolved(Vector2i.ZERO)
    Bench.composite(easel)
    return easel


static func _last() -> Basis:
    return SaLiveTransform.composed(LAST_MOVE, LAST_TURN, LAST_SCALE, MIDDLE)


## Every field of every chunk *layer* holds, as bytes by position.
static func _chunks(layer: SaLayer) -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in layer.chunks:
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(layer.get_field(grid_pos).rid, 0)
    return out


## The picture *layer* draws: its cache's chunks, or its own for a layer with
## no transform.
static func _drawn(layer: SaLayer) -> Dictionary:
    return _chunks(SaLiveTransform.paint_of(layer))


## The largest difference of one channel between *one* and *other*, two
## pictures as [method _drawn] gives them, reading a chunk one of them lacks as
## nothing, in the format of *texture*.
static func _apart(one: Dictionary, other: Dictionary, format: int) -> float:
    var worst := 0.0
    var positions := one.keys()
    for at: Vector2i in other:
        if not positions.has(at):
            positions.append(at)
    for at: Vector2i in positions:
        var a: PackedByteArray = one.get(at, PackedByteArray())
        var b: PackedByteArray = other.get(at, PackedByteArray())
        var count := SaLayer.CHUNK_SIZE * SaLayer.CHUNK_SIZE
        for i in count:
            var p := SaFieldSpec.decode_texel(a, format, i) if not a.is_empty() else Color(0, 0, 0, 0)
            var q := SaFieldSpec.decode_texel(b, format, i) if not b.is_empty() else Color(0, 0, 0, 0)
            worst = maxf(worst, maxf(maxf(absf(p.r - q.r), absf(p.g - q.g)), maxf(absf(p.b - q.b), absf(p.a - q.a))))
    return worst


static func _report(doc: SaDocument, name: String) -> Dictionary:
    for entry: Dictionary in LayersReport.stack(doc):
        if entry["name"] == name:
            return entry
    return {}


## First promise: a chain of transforms ending at one map draws what
## one transform of an untouched copy to that map draws, and the layer's own
## chunks are what they were before the first.
func test_a_chain_of_transforms_draws_what_one_transform_draws() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var painted := _chunks(paint)
    var format := paint.get_field(Vector2i.ZERO).format
    assert_false(SaSmartLayer.is_smart(paint), "A painted layer is ordinary")
    var steps := doc.history.step_count()
    assert_true(SaSmartLayer.make(doc, paint), "Make Smart Layer runs")
    assert_eq(doc.history.step_count(), steps + 1, "as one history step")
    assert_true(SaSmartLayer.is_marked(paint), "and the layer carries the marker")
    assert_true(SaLiveTransform.of(paint).matrix.is_equal_approx(Basis.IDENTITY), "under the identity")
    assert_true(_report(doc, "Paint").get("smart", false), "The layers report names it smart")
    assert_false(_report(doc, "Paint").get("transformed", true), "and not transformed")
    for i in 12:
        var map := SaLiveTransform.composed(
            Vector2(10.0 * i, -7.0 * i), 17.0 * i, Vector2(0.6 + 0.07 * i, 0.6 + 0.07 * i), MIDDLE
        )
        assert_true(SaLiveTransform.put(doc, paint, map), "Transform %d of the chain is put" % i)
    assert_true(SaLiveTransform.put(doc, paint, _last()), "and the last")
    assert_true(SaSmartLayer.is_marked(paint), "The layer is still marked smart")
    Bench.composite(easel)
    var chained := _drawn(paint)
    assert_eq(_chunks(paint), painted, "The layer's own chunks are what was painted, byte for byte")

    var copy := _painting()
    var untouched := copy.document.get_node("Paint") as SaLayer
    assert_true(SaLiveTransform.put(copy.document, untouched, _last()), "The untouched copy takes the last map once")
    Bench.composite(copy)
    var once := _drawn(untouched)
    assert_eq(chained.keys().size(), once.keys().size(), "Both draw the same chunks")
    var apart := _apart(chained, once, format)
    assert_true(apart <= SAME, "and the same picture, %s apart at most" % apart)
    copy.free()
    easel.free()


## Second promise: Reset Transform draws the source where it was
## painted, the layer stays smart, and one undo gives the map back.
func test_reset_draws_the_source_where_it_was_painted_and_stays_smart() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var painted := _chunks(paint)
    var format := paint.get_field(Vector2i.ZERO).format
    assert_false(SaSmartLayer.reset(doc, paint), "An ordinary layer has no transform to reset")
    assert_true("\n".join(SaProblems.pending_refusals).contains("not a smart layer"), "and the corner says why")
    SaSmartLayer.make(doc, paint)
    SaLiveTransform.put(doc, paint, _last())
    var steps := doc.history.step_count()
    assert_true(SaSmartLayer.reset(doc, paint), "Reset Transform runs")
    assert_eq(doc.history.step_count(), steps + 1, "as one history step")
    assert_false(SaSmartLayer.reset(doc, paint), "and a second reset has nothing to do")
    Bench.composite(easel)
    var live := SaLiveTransform.of(paint)
    assert_not_null(live, "The layer keeps its transform")
    if live != null:
        assert_true(live.smart, "marked smart")
        assert_true(live.matrix.is_equal_approx(Basis.IDENTITY), "at the identity")
    assert_true(_report(doc, "Paint").get("smart", false), "The layers report names it smart")
    assert_false(_report(doc, "Paint").get("transformed", true), "and not transformed")
    var apart := _apart(_drawn(paint), painted, format)
    assert_true(apart <= SAME, "It draws the source where it was painted, %s apart at most" % apart)
    assert_eq(_chunks(paint), painted, "over the chunks as painted")
    assert_true(doc.undo(), "One undo")
    Bench.composite(easel)
    assert_true(SaLiveTransform.of(paint).matrix.is_equal_approx(_last()), "gives the map back")
    assert_true(_report(doc, "Paint").get("transformed", false), "and the report names it transformed again")
    easel.free()


## A drag of the map back onto the paint, a `put` of no map, leaves a layer
## made smart at the identity, where a layer some step put a map on with no
## marker loses its transform, as it always has.
func test_a_map_of_nought_keeps_a_smart_layer_smart() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    SaSmartLayer.make(doc, paint)
    SaLiveTransform.put(doc, paint, _last())
    assert_true(SaLiveTransform.put(doc, paint, null), "No map is put")
    assert_true(SaSmartLayer.is_marked(paint), "and the layer stays smart")
    assert_true(SaLiveTransform.of(paint).matrix.is_equal_approx(Basis.IDENTITY), "at the identity")
    assert_false(SaLiveTransform.put(doc, paint, null), "A second one changes nothing")
    var other := doc.get_node("Background") as SaLayer
    SaLiveTransform.put(doc, other, _last())
    assert_false(SaSmartLayer.is_marked(other), "A map put with no marker")
    SaLiveTransform.put(doc, other, null)
    assert_null(SaLiveTransform.of(other), "comes off with a map of nought")
    easel.free()


## Third promise: Convert to Ordinary Layer writes the picture the
## layer drew into its chunks, the layer is ordinary, and one undo restores the
## smart layer with its map and its source. Make Smart Layer on a group, a
## locked layer and an adjustment layer says why and changes nothing.
func test_convert_writes_the_picture_in_and_undo_restores_the_smart_layer() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var painted := _chunks(paint)
    SaSmartLayer.make(doc, paint)
    SaLiveTransform.put(doc, paint, _last())
    Bench.composite(easel)
    var shown := _drawn(paint)
    var steps := doc.history.step_count()
    assert_true(SaLiveTransform.bake(doc, paint), "Convert to Ordinary Layer runs")
    assert_eq(doc.history.step_count(), steps + 1, "as one history step")
    assert_eq(doc.undo_redo.get_current_action_name(), SaLiveTransform.BAKE, "under its name")
    assert_null(SaLiveTransform.of(paint), "The layer has no transform left")
    assert_false(SaSmartLayer.is_smart(paint), "so it is ordinary")
    assert_false(_report(doc, "Paint").get("smart", true), "and the report says so")
    assert_eq(_chunks(paint), shown, "Its chunks hold the picture it drew, byte for byte")
    assert_true(doc.undo(), "One undo")
    Bench.composite(easel)
    var back := SaLiveTransform.of(paint)
    assert_not_null(back, "restores the transform")
    if back != null:
        assert_true(back.smart, "marked smart")
        assert_true(back.matrix.is_equal_approx(_last()), "under its map")
    assert_eq(_chunks(paint), painted, "over the source as painted")
    easel.free()


func test_make_smart_refuses_a_group_a_locked_layer_and_an_adjustment_layer() -> void:
    var easel := _painting()
    var doc := easel.document
    var group := SaLayer.new()
    group.name = "Folder"
    group.is_group = true
    var adjustment := SaLayer.new()
    adjustment.name = "Curves"
    adjustment.input = SaLayerTypeDescriptor.INPUT_BELOW
    doc.add_child(group)
    doc.add_child(adjustment)
    var locked := doc.get_node("Paint") as SaLayer
    locked.is_locked = true
    var steps := doc.history.step_count()
    for layer: SaLayer in [group, locked, adjustment]:
        SaProblems.pending_refusals = PackedStringArray()
        assert_false(SaSmartLayer.make(doc, layer), "Make Smart Layer refuses %s" % layer.name)
        var said := "\n".join(SaProblems.pending_refusals)
        assert_true(said.contains(String(layer.name)), "and the corner says why, %s" % said)
        assert_null(SaLiveTransform.of(layer), "leaving %s with no transform" % layer.name)
    assert_eq(doc.history.step_count(), steps, "and no step is taken")
    locked.is_locked = false
    SaSmartLayer.make(doc, locked)
    SaProblems.pending_refusals = PackedStringArray()
    assert_false(SaSmartLayer.make(doc, locked), "A smart layer is not made smart twice")
    assert_true("\n".join(SaProblems.pending_refusals).contains("already"), "and the corner says so")
    easel.free()


## Fourth promise: a smart layer with a map and one reset to no map
## save and open with the marker, the map and the source, and a file with no
## marker key reads as before.
func test_a_smart_layer_saves_and_opens_with_its_marker_map_and_source() -> void:
    for reset: bool in [false, true]:
        var easel := _painting()
        var doc := easel.document
        var paint := doc.get_node("Paint") as SaLayer
        var painted := _chunks(paint)
        SaSmartLayer.make(doc, paint)
        SaLiveTransform.put(doc, paint, _last())
        if reset:
            SaSmartLayer.reset(doc, paint)
        var map := SaLiveTransform.of(paint).matrix
        var path := ProjectSettings.globalize_path(SaDataRoot.path("smart_layer_%s.sad" % reset))
        assert_eq(SaExport.save_sad(doc, path), OK, "It saves, reset %s" % reset)
        easel.free()

        var opened_easel := Bench.easel(SIZE)
        var opened_doc := opened_easel.document
        assert_eq(SaExport.load_sad(opened_doc, path, opened_easel.compositor), OK, "It opens")
        DirAccess.remove_absolute(path)
        var opened := opened_doc.get_node("Paint") as SaLayer
        assert_not_null(opened, "with its layer")
        if opened != null:
            assert_true(SaSmartLayer.is_marked(opened), "marked smart, reset %s" % reset)
            var live := SaLiveTransform.of(opened)
            if live != null:
                assert_true(live.matrix.is_equal_approx(map), "under its map, %s" % live.matrix)
            assert_eq(_chunks(opened), painted, "over the source as painted, byte for byte")
        opened_easel.free()


func test_the_entry_reads_the_marker_and_an_entry_without_it_as_before() -> void:
    var easel := _painting()
    var paint := easel.document.get_node("Paint") as SaLayer
    var entry: Dictionary[String, Variant] = {}
    SaSmartLayer.write_header(paint, entry)
    assert_true(entry.is_empty(), "An ordinary layer writes no key")
    SaSmartLayer.read_header(paint, entry)
    assert_null(SaLiveTransform.of(paint), "and an entry with neither key reads ordinary")
    var floats := SaLiveTransform.new(_last()).floats()
    entry = {SaLiveTransform.KEY: floats}
    SaSmartLayer.read_header(paint, entry)
    assert_true(SaSmartLayer.is_marked(paint), "An entry with a map and no marker, saved before the marker existed, reads smart")
    paint.live_transform = null
    entry = {SaSmartLayer.KEY: true}
    SaSmartLayer.read_header(paint, entry)
    assert_true(SaSmartLayer.is_marked(paint), "An entry with the marker alone reads smart")
    assert_true(SaLiveTransform.of(paint).matrix.is_equal_approx(Basis.IDENTITY), "at the identity")
    var written: Dictionary[String, Variant] = {}
    SaSmartLayer.write_header(paint, written)
    assert_eq(written.get(SaSmartLayer.KEY, false), true, "and writes the marker back")
    paint.live_transform = null
    easel.free()
