## The frame after an add, a drop or a delete of a layer takes under fifty
## milliseconds.
##
## A change of the stack owed the fold whole and marked every allocated chunk,
## so the composite that drew it folded every cache and drew the whole
## picture, 84.8 ms after a delete on a stack of thirty layers. Now the
## debt reads what the change moved, marks the chunks of that layer alone, and
## folds each cache over them, so a layer that holds a few chunks costs a fold
## and a composite of a few chunks.
##
## Two easels are built alike on a stack, a 2160 by 720 document of thirty
## painted layers over the default two, the top four in a group, with two
## layers more that hold paint in a few chunks only, Spot and Dot, among them.
## The one under test owes its folds. Its twin folds at once with a full
## `update_caches` and composites every chunk, which is the true picture. Each
## act runs on both, and the canvas under test is read against the twin's at
## the frame after the act and at every frame until nothing is owed, the
## caches against the twin's once it is paid, and every chunk the act and
## those frames marked against the chunks the changed layer holds.
extends "res://tests/test_framework.gd"

## The pictures and the caches are compute dispatches, read back here.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const BusyBound = preload("res://tests/fixtures/busy_bound.gd")

const DOC_SIZE := Vector2i(2160, 720)
const PAINT_LAYERS := 30
const MEMBERS := 4

## The ceiling the row sets on the frame after an act, in milliseconds on a
## quiet machine, moved by `BusyBound` when the machine is busy.
const LIMIT_MS := 50.0

## More frames than any fold here takes.
const MOST_FRAMES := 64

## Where Spot and Dot hold paint, a few of the document's 27 chunks.
const SPOT_CHUNKS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2)]
const DOT_CHUNKS: Array[Vector2i] = [Vector2i(6, 0)]

var _easel: SaEasel
var _twin: SaEasel
var _marked: Dictionary[Vector2i, bool] = {}

## Every act of a test timed against the line, each moved for its own moment.
var _bound: BusyBound


static func _built(owing: bool) -> SaEasel:
    var easel := SaEasel.create_default(DOC_SIZE)
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := easel.document
    doc.active_layer.name = "Background"
    doc.fold.debt.quiet_msec = 0 if owing else 60000
    doc.update_caches()
    var members: Array[SaLayer] = []
    for i: int in PAINT_LAYERS:
        var layer := SaLayerOps.new(doc).add()
        layer.name = "Paint %d" % i
        doc.fill_layer(Color(float(i) / PAINT_LAYERS, 0.4, 0.2, 1.0), layer)
        if i >= PAINT_LAYERS - MEMBERS:
            members.append(layer)
        if i == 15:
            _spotted(doc, "Spot", SPOT_CHUNKS, Color(0.1, 0.8, 0.9, 0.7))
            _spotted(doc, "Dot", DOT_CHUNKS, Color(0.9, 0.9, 0.1, 1.0))
    SaLayerOps.new(doc).group_layers(members).name = "Pictures"
    doc.set_active_layer(_named(doc, "Paint 3"))
    doc.update_caches()
    easel.request_full_composite()
    _drawn(easel)
    return easel


# A layer above the active one that holds paint at *chunks* alone.
static func _spotted(doc: SaDocument, layer_name: String, chunks: Array[Vector2i], color: Color) -> void:
    var layer := SaLayerOps.new(doc).add()
    layer.name = layer_name
    for grid_pos in chunks:
        layer.get_or_create_chunk(grid_pos).clear(color)


func before_each() -> void:
    _bound = BusyBound.new(LIMIT_MS)
    _easel = _built(true)
    EventBus.add_child(_easel)
    _twin = _built(false)
    _marked = {}
    _easel.document.chunks_invalidated.connect(_note)


func after_each() -> void:
    _easel.free()
    _twin.free()


func _note(grid_positions: Array) -> void:
    for grid_pos: Vector2i in grid_positions:
        _marked[grid_pos] = true


## The canvas of *easel* as the next frame leaves it: what is dirty
## composited, nothing asked of the whole canvas.
static func _drawn(easel: SaEasel) -> PackedByteArray:
    easel.process_pending_composite()
    easel.flush()
    return GlobalShaderCompiler.get_rd().texture_get_data(easel.output.rid, 0)


## The twin's canvas after a full `update_caches` and a composite of every
## chunk.
func _truth() -> PackedByteArray:
    _twin.document.update_caches()
    _twin.request_full_composite()
    return _drawn(_twin)


## Every chunk of every cache of *doc*'s fold, by the cache's name.
static func _caches(doc: SaDocument) -> Dictionary:
    var out := {}
    for cache in doc.fold.caches():
        if not is_instance_valid(cache):
            continue
        var chunks := {}
        for grid_pos: Vector2i in SaTyped.positions(cache.chunks):
            chunks[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(cache.chunks[grid_pos].albedo().rid, 0)
        out[str(cache.name)] = chunks
    return out


static func _named(doc: SaDocument, layer_name: String) -> SaLayer:
    return doc.find_child(layer_name, false, false) as SaLayer


## *act* run on both easels, its argument each one's document, and *changed*
## the name of the layer it adds, drops or deletes. The frame after it shows
## the true picture, and so does every frame until nothing is owed. Then the
## caches are the ones a full fold folds, and what the act and its frames
## marked lies inside the chunks *changed* holds. Answers the milliseconds of
## the frame after the act and the frames that paid.
func _step(what: String, act: Callable, changed: String) -> float:
    var doc := _easel.document
    # A layer an act adds is found after it, and one it deletes before it.
    var layer := _named(doc, changed)
    _marked = {}
    act.call(doc)
    act.call(_twin.document)
    if layer == null:
        layer = _named(doc, changed)
    var held: Dictionary[Vector2i, bool] = {}
    for grid_pos: Vector2i in SaTyped.positions(layer.chunks):
        held[grid_pos] = true
    var truth := _truth()
    # A lambda copies a local, so what the frames show comes back in here.
    var seen := {}
    var paid := func() -> void:
        seen[&"shown"] = _drawn(_easel)
        var every_true: bool = seen[&"shown"] == truth
        var count := 0
        while doc.fold.debt.is_owed() and count < MOST_FRAMES:
            doc.fold.debt.frame()
            every_true = every_true and _drawn(_easel) == truth
            count += 1
        seen[&"all_true"] = every_true
        seen[&"frames"] = count
    var took := _bound.time("The frame after %s and the frames that paid" % what, paid)
    var shown: PackedByteArray = seen[&"shown"]
    var all_true: bool = seen[&"all_true"]
    var frames: int = seen[&"frames"]
    var line := "probe after %s, the frame after it and %d frames more took %.1f ms and marked %d of the %d chunks %s holds"
    print(line % [what, frames, took, _marked.size(), held.size(), changed])
    assert_eq(shown, truth, "the frame after %s shows the true picture" % what)
    assert_true(all_true, "and so does every frame until nothing is owed")
    assert_false(doc.fold.debt.is_owed(), "Nothing is owed after %s once its frames have run" % what)
    assert_true(doc.fold.reads_as_built(doc), "the walk is built around %s" % doc.active_layer.name)
    assert_eq(_caches(doc), _caches(_twin.document), "and every cache is the one a full fold folds")
    var wider: Array[Vector2i] = []
    for grid_pos: Vector2i in _marked:
        if not held.has(grid_pos):
            wider.append(grid_pos)
    assert_eq(wider, [] as Array[Vector2i], "%s marked no chunk %s does not hold" % [what, changed])
    return took


func test_an_add_a_drop_and_deletes_draw_the_true_picture_over_the_changed_layers_chunks() -> void:
    _step("an add", _add, "Added")
    _step("a drop", _place.bind("Spot", 26), "Spot")
    _step("a delete of a painted layer", _remove.bind("Dot"), "Dot")
    _step("a delete of an empty layer", _remove.bind("Added"), "Added")
    assert_true(_bound.all_held, _bound.worst)


## A layer that holds paint across the canvas changes the picture across it,
## so its delete and its drop mark every chunk, and still draw the true one.
func test_a_layer_across_the_canvas_draws_the_true_picture_where_it_held_paint() -> void:
    _step("a delete of Paint 10", _remove.bind("Paint 10"), "Paint 10")
    _step("a drop of Paint 5", _place.bind("Paint 5", 20), "Paint 5")
    _step("a delete of the active layer", _remove_active, "Paint 3")


## An undo of each brings back the picture before it, drawn over the same
## chunks.
func test_the_undo_of_a_drop_and_a_delete_draws_the_true_picture() -> void:
    _step("a drop of Dot", _place.bind("Dot", 2), "Dot")
    _step("its undo", func(doc: SaDocument) -> void: doc.undo(), "Dot")
    _step("a delete of Spot", _remove.bind("Spot"), "Spot")
    _step("its undo", func(doc: SaDocument) -> void: doc.undo(), "Spot")


func _add(doc: SaDocument) -> void:
    SaLayerOps.new(doc).add().name = "Added"


func _place(doc: SaDocument, name: String, index: int) -> void:
    SaLayerOps.new(doc).place(_named(doc, name), null, index)


func _remove(doc: SaDocument, name: String) -> void:
    SaLayerOps.new(doc).remove(_named(doc, name))


func _remove_active(doc: SaDocument) -> void:
    SaLayerOps.new(doc).remove(doc.active_layer)
