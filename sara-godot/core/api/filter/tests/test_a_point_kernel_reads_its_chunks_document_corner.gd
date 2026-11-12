## A point kernel reads its chunk's document corner.
##
## Effect placement asks the point pass to write the chunk's
## document corner, as the neighbourhood pass does, so a pattern can be computed
## in document pixels. The fixture kernel writes `global_id` plus the region's
## origin plus that corner into red and green, so one texel place in two
## chunks reads apart by the chunk's side when the corner arrives, and alike
## when it does not.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## The fixture's folder, which is the owner the shader index files its kernel
## under.
const OWNER: StringName = &"point-fixture"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")


## The corner kernel as a filter, so the chain can attach it and run it the
## way it runs any record.
class CornerFilter:
    extends SaFilter

    func title() -> String:
        return "Point Fixture Corner"

    func run(ctx: SaFilterContext) -> void:
        ctx.point_pass("corner", "corner", PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))


var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document
    _doc.active_layer.fill(Color(0.5, 0.5, 0.5, 1.0))
    _easel.request_full_composite()
    _easel.process_pending_composite()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


func _layer_texel(grid: Vector2i, local: Vector2i) -> Color:
    var texture := _doc.active_layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * texture.size.x + local.x)


func _record() -> SaFilterContext:
    var ctx := SaFilterContext.new(_doc, _doc.active_layer, OWNER, "Corner", true)
    ctx.point_pass("corner", "corner", PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))
    return ctx


func test_the_pass_finds_the_slot_the_kernel_named() -> void:
    var recorded := _record().point
    assert_not_null(recorded, "The run recorded a pass")
    assert_eq(recorded.corner_slot, 2, "at the two floats after the origin, where the block put `chunk`")
    var push := recorded.push_for(Vector2i(3, 4), Vector2i(256, 512))
    assert_eq(push[0], 3.0, "The origin is written as before")
    assert_eq(push[2], 256.0, "and the corner beside it")
    assert_eq(push[3], 512.0, "x then y")


func test_a_kernel_that_names_no_corner_is_handed_none() -> void:
    var ctx := SaFilterContext.new(_doc, _doc.active_layer, OWNER, "Invert", true)
    var push := PackedFloat32Array([0.0, 0.0, 7.0, 9.0])
    ctx.point_pass("invert", "invert", push)
    assert_eq(ctx.point.corner_slot, -1, "The invert declares no `chunk`")
    var written := ctx.point.push_for(Vector2i(1, 2), Vector2i(256, 256))
    assert_eq(written[2], 7.0, "so its own floats are left as the filter wrote them")
    assert_eq(written[3], 9.0, "both of them")


func test_apply_hands_each_chunk_its_corner() -> void:
    var ctx := _record()
    assert_true(SaFilterApply.apply(ctx, "Corner"), "Apply writes")
    var side := SaChunk.SIZE
    var first := _layer_texel(Vector2i(0, 0), Vector2i(10, 20))
    var across := _layer_texel(Vector2i(1, 0), Vector2i(10, 20))
    var down := _layer_texel(Vector2i(0, 1), Vector2i(10, 20))
    assert_almost_eq(first.r, 10.0, 1e-3, "The first chunk's texel is at its document place: %s" % first)
    assert_almost_eq(across.r - first.r, float(side), 1e-3, "The next chunk across is a chunk's side on: %s" % across)
    assert_almost_eq(across.g, first.g, 1e-3, "at the same height")
    assert_almost_eq(down.g - first.g, float(side), 1e-3, "and the chunk below a side down: %s" % down)


func test_an_attached_record_hands_each_chunk_its_corner() -> void:
    var bench := Bench.easel(Vector2i(512, 512))
    var registry := bench.compositor.filter_chain.registry
    var filter := CornerFilter.new()
    assert_true(registry.register(filter, OWNER), "The corner registers beside the invert")
    var doc := bench.document
    doc.active_layer.fill(Color(0.5, 0.5, 0.5, 1.0))
    var key := SaFilterRegistry.key_for(OWNER, filter)
    var record := SaFilterOps.new(doc).attach(doc.active_layer, key, {})
    assert_not_null(record, "The corner attaches")
    Bench.composite(bench)
    var first := Bench.texel(bench.output, Vector2i(10, 20))
    var across := Bench.texel(bench.output, Vector2i(SaChunk.SIZE + 10, 20))
    var down := Bench.texel(bench.output, Vector2i(10, SaChunk.SIZE + 20))
    bench.free()
    assert_almost_eq(first.r, 10.0, 1e-2, "The chain's first chunk is at its document place: %s" % first)
    assert_almost_eq(across.r - first.r, float(SaChunk.SIZE), 1e-2, "the next across a side on: %s" % across)
    assert_almost_eq(down.g - first.g, float(SaChunk.SIZE), 1e-2, "and the one below a side down: %s" % down)
