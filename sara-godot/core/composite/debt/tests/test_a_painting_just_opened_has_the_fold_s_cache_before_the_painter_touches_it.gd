## A painting just opened has the fold's cache before the painter touches it.
##
## read a forty-two layer painting a canvas of cache short thirty frames
## after its load, and filed this row on the reading that a load leaves the
## fold in debt. It does not: `SaSadFile.finish_load` rebuilds the caches
## before the load returns, and the canvas that was missing one is the run cache
## above the layer it picked, which a pick in the middle of the stack makes.
## This suite holds the load to that. Three painted layers are saved with the
## top one active and opened into a fresh document, and with no activation, no
## press and no frame the bottom cache stands folded, the walk reads it in
## place of the two layers under the active one, and nothing is owed.
extends "res://tests/test_framework.gd"

## The caches are compute dispatches, read back here.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const SIZE := Vector2i(512, 512)

## The three layers, bottom first, each a colour over the whole canvas.
const PAINT: Array[Color] = [Color(0.8, 0.1, 0.1, 1.0), Color(0.1, 0.7, 0.2, 0.5), Color(0.1, 0.2, 0.9, 0.5)]

static var scratch_sad: String = SaDataRoot.path("three-painted-layers.sad")

var _painted: SaSurface = null
var _opened: SaSurface = null


func before_each() -> void:
    _painted = Fixtures.make_surface(SIZE)
    var doc := _painted.easel.document
    var top: SaLayer = null
    for i: int in PAINT.size():
        top = SaLayerOps.new(doc).add()
        top.name = "Paint %d" % (i + 1)
        doc.fill_layer(PAINT[i], top)
    doc.set_active_layer(top)
    doc.update_caches()
    assert_eq(SaExport.save_sad(doc, scratch_sad, 0), OK, "the three layers save")
    _opened = Fixtures.make_surface(SIZE)


func after_each() -> void:
    Fixtures.teardown(_opened)
    Fixtures.teardown(_painted)
    if FileAccess.file_exists(scratch_sad):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_sad))


func _load() -> SaDocument:
    var doc := _opened.easel.document
    assert_eq(SaExport.load_sad(doc, scratch_sad, _opened.easel.compositor), OK, "the file opens")
    return doc


static func _texel(layer: SaLayer, grid_pos: Vector2i, at: Vector2i) -> Color:
    var picture := SaExport.get_texture_image_float(layer.chunks[grid_pos].albedo())
    return picture.get_pixel(at.x, at.y) if picture != null else Color(NAN, NAN, NAN, NAN)


func test_the_bottom_cache_stands_after_a_load_with_no_activation_and_no_press() -> void:
    var doc := _load()
    assert_eq(str(doc.active_layer.name), "Paint 3", "the layer saved active is active")
    var cache := doc.fold.bottom_cache
    assert_not_null(cache, "the bottom cache stands")
    var chunk_edge := 256
    if not cache.chunks.is_empty():
        chunk_edge = (cache.chunks.values()[0] as SaChunk).pixel_size()
    var across := ceili(float(SIZE.x) / chunk_edge) * ceili(float(SIZE.y) / chunk_edge)
    assert_eq(cache.chunks.size(), across, "and holds a chunk wherever the layers under the active one hold paint")
    assert_false(doc.fold.debt.is_owed(), "and nothing is owed to the fold")
    assert_false(doc.fold.is_unpaid(), "and no fold over frames is left to pay")


func test_the_walk_reads_the_cache_and_not_the_layers_under_the_active_one() -> void:
    var doc := _load()
    var cache := doc.fold.bottom_cache
    var read: Array[SaLayer] = []
    for step: Dictionary in doc.fold.bottom_stack:
        read.append(SaLayerStack.layer_of(step))
    assert_true(cache in read, "the walk below the active layer reads the bottom cache")
    for name: String in ["Paint 1", "Paint 2"]:
        var layer := doc.find_child(name, false, false) as SaLayer
        assert_false(layer in read, "%s is read through the cache and not walked" % name)


func test_the_cache_holds_what_a_fold_of_the_opened_stack_holds() -> void:
    var doc := _load()
    var cache := doc.fold.bottom_cache
    var grid_pos: Vector2i = cache.chunks.keys()[0]
    var at := Vector2i(17, 33)
    var opened := _texel(cache, grid_pos, at)
    assert_true(opened.a > 0.99, "the cache holds the paint folded, the bottom layer opaque")
    doc.update_caches()
    var folded := _texel(doc.fold.bottom_cache, grid_pos, at)
    for channel: int in 4:
        var same := is_equal_approx(opened[channel], folded[channel])
        assert_true(same, "channel %d is what a fold of the opened stack writes" % channel)
