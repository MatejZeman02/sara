## The wrap offset shifts the canvas round on itself, modulo its size, in
## both forms from one run.
##
## One texel is painted at (10, 10) on a canvas one chunk square. A wrap of
## (-20, 0) carries it off the left edge and back in at the right, a wrap by the
## canvas's own width is the modulo's check that nothing moves, and two wraps by
## half the canvas put the picture back where it was.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const RED := Color(1.0, 0.0, 0.0, 1.0)
const CLEAR := Color(0.0, 0.0, 0.0, 0.0)
const DOT := Vector2i(10, 10)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _filter: SaWrapOffsetFilter = null
var _key: StringName = &""


func before_each() -> void:
    _easel = Bench.easel(Vector2i(SaChunk.SIZE, SaChunk.SIZE))
    _doc = _easel.document
    _filter = SaWrapOffsetFilter.new()
    _easel.compositor.filter_chain.registry.register(_filter, OWNER)
    _key = SaFilterRegistry.key_for(OWNER, _filter)
    _layer = _doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    _paint_dot(_layer.get_or_create_chunk(Vector2i.ZERO).field(SaFieldSpec.ALBEDO))


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null
    _filter = null


## *texture* transparent everywhere and red at [const DOT].
func _paint_dot(texture: SaTexture) -> void:
    texture.clear(CLEAR)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var texel := SaFieldSpec.BYTES_PER_TEXEL.get(texture.format, 16) as int
    var one := SaTexture.new(Vector2i.ONE, texture.format)
    one.clear(RED)
    var red := GlobalShaderCompiler.get_rd().texture_get_data(one.rid, 0)
    var at := (DOT.y * texture.size.x + DOT.x) * texel
    for i in texel:
        bytes[at + i] = red[i]
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)


## The one-shot wrap by *offset* over the layer, as the dialog's Apply runs it.
func _wrap(offset: Vector2i) -> bool:
    _filter.set_parameters({"offset_x": offset.x, "offset_y": offset.y})
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, _filter.title(), false)
    if not SaFilterApply.call_run(_filter, ctx):
        return false
    return SaFilterApply.apply(ctx, _filter.title())


func _layer_texel(at: Vector2i) -> Color:
    return Bench.texel(_layer.get_field(Vector2i.ZERO), at)


func test_the_run_records_a_pass_that_reads_the_whole_node() -> void:
    _filter.set_parameters({"offset_x": 3, "offset_y": -4})
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, _filter.title(), false)
    assert_true(SaFilterApply.call_run(_filter, ctx), "The run records a pass")
    assert_true(ctx.point is SaNeighbourhoodPass, "a neighbourhood pass")
    if ctx.point is SaNeighbourhoodPass:
        assert_true((ctx.point as SaNeighbourhoodPass).whole(), "that reads the whole node, since a wrap reads anywhere")


func test_a_texel_pushed_off_the_left_edge_comes_back_at_the_right() -> void:
    assert_eq(_layer_texel(DOT), RED, "The dot is painted before the wrap")
    assert_true(_wrap(Vector2i(-20, 0)), "The wrap applies")
    assert_eq(_layer_texel(Vector2i(SaChunk.SIZE - 10, 10)), RED, "The dot twenty pixels left of (10, 10) is at (246, 10)")
    assert_eq(_layer_texel(DOT), CLEAR, "and (10, 10) is transparent")


func test_a_wrap_by_the_canvas_width_changes_nothing() -> void:
    var tex := _layer.get_field(Vector2i.ZERO)
    var before := GlobalShaderCompiler.get_rd().texture_get_data(tex.rid, 0)
    assert_true(_wrap(Vector2i(SaChunk.SIZE, 0)), "The wrap applies")
    var after := GlobalShaderCompiler.get_rd().texture_get_data(_layer.get_field(Vector2i.ZERO).rid, 0)
    assert_true(before == after, "A wrap by the canvas's own width is the layer byte for byte")


func test_two_half_wraps_read_the_original_back() -> void:
    var half := Vector2i.ONE * (SaChunk.SIZE >> 1)
    assert_true(_wrap(half), "The first half wrap applies")
    assert_eq(_layer_texel(DOT + half), RED, "Half the canvas on, the dot is at (138, 138)")
    assert_true(_wrap(half), "The second half wrap applies")
    assert_eq(_layer_texel(DOT), RED, "and a second half wrap puts it back at (10, 10)")
    assert_eq(_layer_texel(DOT + half), CLEAR, "with (138, 138) empty again")


func test_a_negative_offset_past_the_canvas_wraps_by_its_remainder() -> void:
    assert_true(_wrap(Vector2i(0, -SaChunk.SIZE - 20)), "The wrap applies")
    assert_eq(_layer_texel(Vector2i(10, SaChunk.SIZE - 10)), RED, "Up by a canvas and twenty is up by twenty")


func test_attached_the_canvas_shows_the_wrap() -> void:
    _filter.set_parameters({"offset_x": -20, "offset_y": 0})
    SaFilterOps.new(_doc).attach(_layer, _key, _filter.parameters())
    Bench.composite(_easel)
    assert_eq(Bench.texel(_easel.output, Vector2i(SaChunk.SIZE - 10, 10)), RED, "Attached, the canvas shows the dot at (246, 10)")
    assert_eq(_layer_texel(DOT), RED, "and the layer still holds it at (10, 10), since nothing is baked")


func test_the_parameters_come_back_as_they_went_in() -> void:
    _filter.set_parameters({"offset_x": 128, "offset_y": -64})
    assert_eq(_filter.parameters(), {"offset_x": 128.0, "offset_y": -64.0}, "Both offsets survive the record")


## Three chunks across and two down, so the width is not a power of two. GLSL's
## `%` on a negative operand came back as an unsigned remainder on the NVIDIA
## driver, which is a power of two's remainder, and this wrap landed a chunk to
## the left of where it belonged while every test on one chunk passed.
func test_a_wrap_across_chunks_on_a_canvas_three_chunks_wide() -> void:
    var wide := Bench.easel(Vector2i(3 * SaChunk.SIZE, 2 * SaChunk.SIZE))
    var filter := SaWrapOffsetFilter.new()
    var layer := wide.document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in layer.chunks.keys():
        layer.chunks.erase(grid_pos)
    for y in 2:
        for x in 3:
            layer.get_or_create_chunk(Vector2i(x, y)).clear(CLEAR)
    layer.get_or_create_chunk(Vector2i.ZERO).clear(RED)
    filter.set_parameters({"offset_x": 384, "offset_y": 128})
    var ctx := SaFilterContext.new(wide.document, layer, OWNER, filter.title(), false)
    assert_true(SaFilterApply.call_run(filter, ctx), "The run records a pass")
    assert_true(SaFilterApply.apply(ctx, filter.title()), "The wrap applies")
    # The red chunk, 0 to 255 square, moves to 384 to 639 across and 128 to 383 down.
    var at := {Vector2i(383, 200): CLEAR, Vector2i(384, 200): RED, Vector2i(639, 383): RED, Vector2i(640, 200): CLEAR}
    at[Vector2i(500, 127)] = CLEAR
    at[Vector2i(100, 200)] = CLEAR
    for point: Vector2i in at:
        var grid_pos := Vector2i((Vector2(point) / float(SaChunk.SIZE)).floor())
        var texel := Bench.texel(layer.get_field(grid_pos), point - grid_pos * SaChunk.SIZE)
        assert_eq(texel, at[point], "The document pixel %s after a wrap of (384, 128)" % point)
    layer = null
    wide.free()


## The same wrap on the same canvas, with only the chunk at (0, 0) allocated.
## The red chunk lands on four positions the layer never held, and the one-shot
## allocates them and writes it there.
func test_d18_a_one_shot_wrap_writes_where_the_one_held_chunk_lands() -> void:
    var wide := Bench.easel(Vector2i(3 * SaChunk.SIZE, 2 * SaChunk.SIZE))
    var filter := SaWrapOffsetFilter.new()
    var layer := _only_origin(wide)
    filter.set_parameters({"offset_x": 384, "offset_y": 128})
    var ctx := SaFilterContext.new(wide.document, layer, OWNER, filter.title(), false)
    assert_true(SaFilterApply.call_run(filter, ctx), "The run records a pass")
    assert_true(SaFilterApply.apply(ctx, filter.title()), "The wrap applies")
    for point: Vector2i in _moved():
        var grid_pos := Vector2i((Vector2(point) / float(SaChunk.SIZE)).floor())
        var texture := layer.get_field(grid_pos)
        assert_not_null(texture, "The one-shot allocated %s, where the red chunk lands" % grid_pos)
        if texture != null:
            assert_eq(Bench.texel(texture, point - grid_pos * SaChunk.SIZE), _moved()[point], "The document pixel %s" % point)
    assert_false(layer.chunks.has(Vector2i(0, 1)), "and (0, 1), where nothing lands, is still not allocated")
    assert_eq(Bench.texel(layer.get_field(Vector2i.ZERO), Vector2i(100, 100)), CLEAR, "and (0, 0) was carried away")
    wide.document.undo()
    assert_eq(layer.chunks.keys(), [Vector2i.ZERO], "Undo takes the landed chunks away again")
    layer = null
    wide.free()


## And attached, over the same one chunk: the canvas shows the red chunk at
## (384, 128) though the layer holds nothing there, and nothing is baked.
func test_d18_an_attached_wrap_draws_where_the_one_held_chunk_lands() -> void:
    var wide := Bench.easel(Vector2i(3 * SaChunk.SIZE, 2 * SaChunk.SIZE))
    var filter := SaWrapOffsetFilter.new()
    wide.compositor.filter_chain.registry.register(filter, OWNER)
    var key := SaFilterRegistry.key_for(OWNER, filter)
    var layer := _only_origin(wide)
    filter.set_parameters({"offset_x": 384, "offset_y": 128})
    SaFilterOps.new(wide.document).attach(layer, key, filter.parameters())
    Bench.composite(wide)
    for point: Vector2i in _moved():
        assert_eq(Bench.texel(wide.output, point), _moved()[point], "Attached, the canvas at %s" % point)
    assert_eq(layer.chunks.keys(), [Vector2i.ZERO], "and the layer still holds the one chunk")
    # A paint on the held chunk alone makes where it lands stale, so the red
    # goes from the middle when the chunk is cleared and only it is invalidated.
    layer.get_or_create_chunk(Vector2i.ZERO).clear(CLEAR)
    wide.document.invalidate_chunks([Vector2i.ZERO])
    wide.process_pending_composite()
    assert_eq(Bench.texel(wide.output, Vector2i(500, 200)), CLEAR, "A paint on (0, 0) redraws where it lands")
    layer = null
    wide.free()


## The Background of *made* holding one red chunk at (0, 0) and nothing else.
func _only_origin(made: SaEasel) -> SaLayer:
    var layer := made.document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in layer.chunks.keys():
        layer.chunks.erase(grid_pos)
    layer.get_or_create_chunk(Vector2i.ZERO).clear(RED)
    return layer


## Where a wrap of (384, 128) puts the red chunk at 0 to 255 square: 384 to 639
## across and 128 to 383 down, over four chunks, and nothing beside it.
func _moved() -> Dictionary:
    return {
        Vector2i(384, 128): RED,
        Vector2i(511, 255): RED,
        Vector2i(512, 256): RED,
        Vector2i(639, 383): RED,
        Vector2i(383, 200): CLEAR,
        Vector2i(640, 200): CLEAR,
        Vector2i(500, 127): CLEAR,
    }
