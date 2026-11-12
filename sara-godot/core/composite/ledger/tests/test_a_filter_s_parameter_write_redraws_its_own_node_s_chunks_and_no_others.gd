## A filter's parameter write redraws its own node's chunks and no others.
##
## the document: three chunks wide, the filtered layer holding chunk (0,0) and
## a layer under it (2,0), over the background that allocates the whole grid.
## A write marked every allocated chunk and rebuilt every cache, because
## `SaFilterOps._changed` did both for a parameter as for an attach. Now the
## fold's ledger knows which nodes each cache baked, the write marks the
## node's chunks and their halos, and folds again only a cache that baked the
## node, over those positions.
##
## A cache chunk cleared to a colour no fold writes, [const SENTINEL], says
## whether a fold touched it: a rebuild folds every chunk of every cache, so a
## chunk still holding it was neither rebuilt nor folded again.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const TimeFilter = preload("res://tests/fixtures/modules/time-fixture/time_filter.gd")
const BoxBlurFilter = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")

## the fixture, a point pass whose picture is its time, under its module's id.
const TIME_OWNER: StringName = &"time-fixture"
const TIME: StringName = &"time-fixture.time_fixture"
## The box blur, whose halo is its radius.
const BLUR_DIR := "res://modules/sara-base-modules/base"
const BLUR_OWNER: StringName = &"sara-base-modules"
const BLUR: StringName = &"sara-base-modules.box_blur"
const RADIUS := 6.0
const WIDER := 24.0

const SENTINEL := Color(7.0, -3.0, 0.5, 2.0)
const UNDER := Color(0.1, 0.6, 0.3, 1.0)
const OVER := Color(0.9, 0.2, 0.05, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
## The filtered layer, holding (0,0), and the layer under it, holding (2,0).
var _over: SaLayer = null
var _under: SaLayer = null
var _grid: Array[Vector2i] = []


func after_each() -> void:
    if _easel != null:
        _easel.free()
    _easel = null
    _doc = null
    _over = null
    _under = null


## the three-chunk document with *key* attached to the filtered layer at
## *values*, composited whole. With *folded* a layer is added above it and
## made active, so the filtered layer folds into the bottom cache with the two
## under it. Without, the filtered layer is active and the bottom cache holds
## the background and the layer under it. Answers the record.
func _bench(key: StringName, values: Dictionary, folded: bool) -> SaAttachedFilter:
    var size := Vector2i(SaLayer.CHUNK_SIZE * 3, SaLayer.CHUNK_SIZE)
    _grid = SaLayer.grid_positions(size)
    _easel = Bench.easel(size)
    _doc = _easel.document
    var filters := _easel.compositor.filter_chain.registry
    filters.register(TimeFilter.new(), TIME_OWNER)
    ModuleLoader.module_dirs[BLUR_OWNER] = BLUR_DIR
    filters.register(BoxBlurFilter.new(), BLUR_OWNER)
    _under = _doc.active_layer
    _over = SaLayerOps.new(_doc).add()
    _under.get_or_create_chunk(_grid[2]).clear(UNDER)
    _over.get_or_create_chunk(_grid[0]).clear(OVER)
    var record := SaFilterOps.new(_doc).attach(_over, key, values)
    if folded:
        SaLayerOps.new(_doc).add()
    Bench.composite(_easel)
    return record


## Every chunk the bottom cache holds, cleared to [const SENTINEL].
func _mark_the_cache() -> void:
    for grid_pos: Vector2i in _doc.fold.bottom_cache.chunks:
        (_doc.fold.bottom_cache.chunks[grid_pos] as SaChunk).clear(SENTINEL)


## The bottom cache's chunks still holding [const SENTINEL], sorted.
func _untouched() -> Array[Vector2i]:
    var found: Array[Vector2i] = []
    for grid_pos: Vector2i in _grid:
        var chunk: SaChunk = _doc.fold.bottom_cache.chunks.get(grid_pos, null)
        if chunk != null and _worst_against(chunk.albedo(), SENTINEL) <= 1e-6:
            found.append(grid_pos)
    return found


## The sorted grid positions of a dirty set.
static func _sorted(dirty: Dictionary[Vector2i, Rect2i]) -> Array[Vector2i]:
    var keys: Array[Vector2i] = []
    keys.assign(dirty.keys())
    keys.sort()
    return keys


## The worst per-channel distance of any texel of *texture* from *colour*,
## over a few texels across it, which a clear makes all alike.
static func _worst_against(texture: SaTexture, colour: Color) -> float:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var worst := 0.0
    for at: Vector2i in [Vector2i(0, 0), Vector2i(128, 128), Vector2i(255, 3), Vector2i(3, 255)]:
        var texel := SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)
        worst = maxf(worst, _distance(texel, colour))
    return worst


static func _distance(a: Color, b: Color) -> float:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


## What *texture* holds, read back once.
static func _read(texture: SaTexture) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


## The worst per-channel distance between two read-backs of *format*, every
## texel of them, nought when the bytes are alike.
static func _worst(a: PackedByteArray, b: PackedByteArray, format: int, texels: int) -> float:
    if a == b:
        return 0.0
    var worst := 0.0
    for i in texels:
        worst = maxf(worst, _distance(SaFieldSpec.decode_texel(a, format, i), SaFieldSpec.decode_texel(b, format, i)))
    return worst


func test_a_write_marks_the_filtered_layers_chunk_alone_and_rebuilds_no_cache() -> void:
    var record := _bench(TIME, {}, false)
    assert_eq(_doc.active_layer, _over, "The filtered layer is the active one, as in the measure")
    assert_eq(_doc.fold.bottom_cache.chunks.size(), 3, "and the bottom cache holds the background and the layer under it")
    _mark_the_cache()
    _doc.consume_dirty_chunks()
    var stack := _doc.fold.bottom_stack
    SaFilterOps.new(_doc).set_parameters(record, {String(SaFilter.Store.TIME): 0.5})
    var dirty := _doc.consume_dirty_chunks()
    assert_almost_eq(SaTyped.real(record.parameters.get(String(SaFilter.Store.TIME))), 0.5, 1e-6, "The write moved the time")
    assert_eq(_sorted(dirty), [_grid[0]] as Array[Vector2i], "and marked (0,0) alone: %s" % [_sorted(dirty)])
    assert_eq(_untouched(), _grid, "with no chunk of the bottom cache folded again")
    assert_true(is_same(stack, _doc.fold.bottom_stack), "and the walk not rebuilt")


func test_the_write_shows_on_the_canvas_where_it_marked() -> void:
    var record := _bench(TIME, {}, false)
    var before := _read(_easel.output)
    SaFilterOps.new(_doc).set_parameters(record, {String(SaFilter.Store.TIME): 0.5})
    _easel.process_pending_composite()
    var after := _read(_easel.output)
    var width := _easel.output.size.x
    var format := _easel.output.format
    var inside := SaFieldSpec.decode_texel(after, format, 30 * width + 20)
    assert_almost_eq(inside.r, 0.5, 1e-4, "The filtered layer's chunk shows the new time")
    var far := Vector2i(2 * SaLayer.CHUNK_SIZE + 20, 30)
    assert_eq(
        SaFieldSpec.decode_texel(after, format, far.y * width + far.x),
        SaFieldSpec.decode_texel(before, format, far.y * width + far.x),
        "and the chunk of the layer under it is as it was"
    )


func test_a_write_on_a_folded_layer_folds_its_cache_again_over_its_chunk_and_halo_only() -> void:
    var record := _bench(BLUR, {"radius": RADIUS}, true)
    assert_true(_doc.active_layer != _over, "Another layer is active")
    assert_true(
        _doc.fold.ledger.bakes(_doc.fold.bottom_cache, {_over.get_instance_id(): true}),
        "so the bottom cache baked the filtered layer"
    )
    assert_eq(_doc.fold.bottom_cache.chunks.size(), 3, "over every chunk of the grid")
    _mark_the_cache()
    _doc.consume_dirty_chunks()
    var stack := _doc.fold.bottom_stack
    SaFilterOps.new(_doc).set_parameters(record, {"radius": WIDER})
    var dirty := _doc.consume_dirty_chunks()
    assert_eq(
        _sorted(dirty),
        [_grid[0], _grid[1]] as Array[Vector2i],
        "The write marked (0,0) and its halo, (1,0): %s" % [_sorted(dirty)]
    )
    assert_eq(_untouched(), [_grid[2]] as Array[Vector2i], "and folded the cache again there, leaving (2,0) as it was")
    assert_true(is_same(stack, _doc.fold.bottom_stack), "with the walk not rebuilt")
    var refolded: Array[PackedByteArray] = []
    for grid_pos: Vector2i in [_grid[0], _grid[1]]:
        refolded.append(_read((_doc.fold.bottom_cache.chunks[grid_pos] as SaChunk).albedo()))
    _doc.update_caches()
    var format: int = (_doc.fold.bottom_cache.chunks[_grid[0]] as SaChunk).albedo().format
    var texels := SaLayer.CHUNK_SIZE * SaLayer.CHUNK_SIZE
    for i in 2:
        var whole := _read((_doc.fold.bottom_cache.chunks[_grid[i]] as SaChunk).albedo())
        assert_true(
            _worst(refolded[i], whole, format, texels) <= 1e-6, "The cache at %s is what a full refold folds" % [_grid[i]]
        )


func test_the_composite_after_a_folded_write_is_a_full_refolds() -> void:
    var record := _bench(BLUR, {"radius": RADIUS}, true)
    var before := _read(_easel.output)
    SaFilterOps.new(_doc).set_parameters(record, {"radius": WIDER})
    _easel.process_pending_composite()
    var narrow := _read(_easel.output)
    var texels := _easel.output.size.x * _easel.output.size.y
    assert_true(_worst(before, narrow, _easel.output.format, texels) > 1e-3, "The wider blur changed the picture")
    Bench.composite(_easel)
    var full := _read(_easel.output)
    assert_true(
        _worst(narrow, full, _easel.output.format, texels) <= 1e-6, "and the narrow redraw is what a full refold composites"
    )


func test_a_point_filter_folded_refolds_its_own_chunk_alone() -> void:
    var record := _bench(TIME, {}, true)
    _mark_the_cache()
    _doc.consume_dirty_chunks()
    SaFilterOps.new(_doc).set_parameters(record, {String(SaFilter.Store.TIME): 0.25})
    assert_eq(_sorted(_doc.consume_dirty_chunks()), [_grid[0]] as Array[Vector2i], "A point filter's write marks its chunk alone")
    assert_eq(_untouched(), [_grid[1], _grid[2]] as Array[Vector2i], "and folds the cache again there alone")


func test_undo_of_the_write_takes_the_same_narrow_path() -> void:
    var record := _bench(TIME, {}, false)
    SaFilterOps.new(_doc).set_parameters(record, {String(SaFilter.Store.TIME): 0.5})
    _mark_the_cache()
    _doc.consume_dirty_chunks()
    _doc.undo()
    assert_almost_eq(
        SaTyped.real(record.parameters.get(String(SaFilter.Store.TIME)), 0.0), 0.0, 1e-6, "The undo put the time back"
    )
    assert_eq(_sorted(_doc.consume_dirty_chunks()), [_grid[0]] as Array[Vector2i], "and marked (0,0) alone")
    assert_eq(_untouched(), _grid, "with no cache folded again")


func test_a_write_on_the_root_marks_every_chunk_and_folds_nothing() -> void:
    _bench(TIME, {}, false)
    var record := SaFilterOps.new(_doc).attach(null, TIME, {})
    Bench.composite(_easel)
    _mark_the_cache()
    _doc.consume_dirty_chunks()
    SaFilterOps.new(_doc).set_parameters(record, {String(SaFilter.Store.TIME): 0.5})
    assert_eq(_sorted(_doc.consume_dirty_chunks()), _grid, "The root's write marks every chunk, since the root reads them all")
    assert_eq(_untouched(), _grid, "and folds no cache, since none holds the root's filters")
