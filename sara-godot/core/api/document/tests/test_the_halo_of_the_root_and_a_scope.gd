## A neighbourhood filter on the document's root and on a group holding the
## active layer reads its neighbours' composite across a chunk seam.
## Both used to read their halo as transparent, the root because the
## canvas beside a dirty chunk holds last frame's filtered composite and a scope
## because it is composited one chunk at a time into a scratch, and both showed
## a darker band along the chunk grid.
##
## The box blur is attached three ways over the same picture, red and blue
## chunks side by side: to the plain layer, which is proved elsewhere, to the root and to
## a group whose member is active. The seam texel of the last two has to be the
## first's. Each is then redrawn over a sliver of one chunk at the seam, the way
## a dab redraws, and the row across the seam has to read as the whole redraw
## left it.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const BoxBlurFilter = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")

const REQUIRES_GPU := true

const MODULE_DIR := "res://modules/sara-base-modules/base"
const KEY: StringName = &"sara-base-modules.box_blur"
const RADIUS := 4
const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
const ROW := 128
## One pixel inside chunk (0, 0)'s right edge.
const SEAM := Vector2i(SaChunk.SIZE - 1, ROW)
## A sliver of chunk (0, 0) along its right edge, which the document's own
## growth spills into chunk (1, 0).
const SLIVER := Rect2i(SaChunk.SIZE - 6, ROW - 20, 6, 40)

enum Where { LAYER, ROOT, SCOPE }

var _easel: SaEasel = null


func after_each() -> void:
    if _easel != null:
        _easel.free()
    _easel = null


## An easel holding the red and blue chunks on one layer and the box blur
## attached *where*.
func _bench(where: Where, size := Vector2i(3 * SaChunk.SIZE, SaChunk.SIZE)) -> SaEasel:
    var made := Bench.easel(size)
    var doc := made.document
    ModuleLoader.module_dirs[&"sara-base-modules"] = MODULE_DIR
    var blur := BoxBlurFilter.new()
    made.compositor.filter_chain.registry.register(blur, &"sara-base-modules")
    var layer := doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in layer.chunks.keys():
        layer.chunks.erase(grid_pos)
    layer.get_or_create_chunk(Vector2i(0, 0)).clear(RED)
    layer.get_or_create_chunk(Vector2i(1, 0)).clear(BLUE)
    var ops := SaFilterOps.new(doc)
    match where:
        Where.LAYER:
            ops.attach(layer, KEY, {"radius": RADIUS})
        Where.ROOT:
            ops.attach(null, KEY, {"radius": RADIUS})
        Where.SCOPE:
            var group := SaLayerOps.new(doc).group_layers([layer])
            doc.set_active_layer(layer)
            ops.attach(group, KEY, {"radius": RADIUS})
    Bench.composite(made)
    return made


## The texels of [const ROW] from *first* to *last* of *texture*, read back once.
func _row(texture: SaTexture, first: int, last: int) -> Array[Color]:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out: Array[Color] = []
    for x in range(first, last):
        out.append(SaFieldSpec.decode_texel(bytes, texture.format, ROW * texture.size.x + x))
    return out


func _same(found: Color, expected: Color, what: String) -> void:
    assert_almost_eq(found.r, expected.r, 0.01, "%s, red: %s against %s" % [what, found, expected])
    assert_almost_eq(found.b, expected.b, 0.01, "%s, blue: %s against %s" % [what, found, expected])
    assert_almost_eq(found.a, expected.a, 0.01, "%s, alpha: %s against %s" % [what, found, expected])


func _plain_seam() -> Color:
    _easel = _bench(Where.LAYER)
    var seam := Bench.texel(_easel.output, SEAM)
    _easel.free()
    _easel = null
    return seam


func test_the_plain_layer_reads_across_the_seam() -> void:
    var seam := _plain_seam()
    assert_almost_eq(seam.b, 4.0 / 9.0, 0.01, "The reference reads four columns of blue, %s" % seam)
    assert_almost_eq(seam.a, 1.0, 0.01, "and is opaque, %s" % seam)


func test_the_root_reads_its_neighbours_composite() -> void:
    var expected := _plain_seam()
    _easel = _bench(Where.ROOT)
    assert_true(_easel.document.root_filters.size() == 1, "The blur hangs on the root")
    _same(Bench.texel(_easel.output, SEAM), expected, "The root's seam is the plain layer's")


func test_a_scope_reads_its_neighbours_composite() -> void:
    var expected := _plain_seam()
    _easel = _bench(Where.SCOPE)
    assert_eq(_easel.document.fold.active_scopes.size(), 1, "The group holding the active layer is a scope")
    _same(Bench.texel(_easel.output, SEAM), expected, "The scope's seam is the plain layer's")


func test_a_sliver_redrawn_on_the_root_leaves_the_row_as_it_was() -> void:
    _easel = _bench(Where.ROOT)
    _redraw_a_sliver("root")


func test_a_sliver_redrawn_in_a_scope_leaves_the_row_as_it_was() -> void:
    _easel = _bench(Where.SCOPE)
    _redraw_a_sliver("scope")


## Redraws [const SLIVER] alone and compares the row across the seam, far past
## where the growth reaches, with what the whole redraw left. A ring cleared
## and not put back reads transparent, and a ring put back unfiltered reads the
## flat colour at the seam.
func _redraw_a_sliver(what: String) -> void:
    var first := SaChunk.SIZE - 40
    var last := SaChunk.SIZE + 40
    var whole := _row(_easel.output, first, last)
    _easel.document.invalidate_chunk_regions({Vector2i(0, 0): SLIVER})
    _easel.process_pending_composite()
    var again := _row(_easel.output, first, last)
    var worst := 0.0
    var at := -1
    for i in whole.size():
        var gap := maxf(maxf(absf(whole[i].r - again[i].r), absf(whole[i].b - again[i].b)), absf(whole[i].a - again[i].a))
        if gap > worst:
            worst = gap
            at = first + i
    assert_true(worst < 0.01, "The %s's row after a sliver is the whole redraw's, worst %.3f at x %d" % [what, worst, at])


## A canvas that ends inside its last row of chunks, the way 1080 does. The
## root's halo past the canvas's edge has to read as transparent, which is what
## the plain layer's chunk holds there, and not as whatever the halo's own chunk
## was allocated with.
func test_the_roots_last_partial_row_reads_as_the_plain_layers() -> void:
    var size := Vector2i(3 * SaChunk.SIZE, SaChunk.SIZE + 56)
    _easel = _bench(Where.LAYER, size)
    var plain := _column(_easel.output, SEAM.x)
    _easel.free()
    _easel = _bench(Where.ROOT, size)
    var root := _column(_easel.output, SEAM.x)
    var worst := 0.0
    var at := -1
    for i in plain.size():
        var gap := maxf(maxf(absf(plain[i].r - root[i].r), absf(plain[i].b - root[i].b)), absf(plain[i].a - root[i].a))
        if gap > worst:
            worst = gap
            at = i
    assert_true(worst < 0.01, "The root's column is the plain layer's, worst %.3f at y %d" % [worst, at])


func _column(texture: SaTexture, x: int) -> Array[Color]:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out: Array[Color] = []
    for y in texture.size.y:
        out.append(SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x))
    return out
