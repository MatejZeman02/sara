## `SaFilterChain.spilled` answers the regions a fresh chain
## answers for the same document after every change to the tree a painter can
## make, whatever the chain asked of the tree before.
##
## A document of thirty painted layers on twelve chunks, every third carrying a
## filter of a halo, each a different reach so the widest is a layer of its
## own. The chain the easel composites with is asked once before a change, then
## the change is made through the operations the docker uses, and the chain is
## asked again beside a chain made fresh for the question. The changes are the
## ones the note names: a layer added, deleted, hidden, moved into a group,
## given a filter, a filter disabled and a mask removed.
##
## Both are asked with `whole`, the form whose answer is the tree's alone: the
## widest reach of every layer and where a whole-node record lands. Without it
## a chain that has composited answers only what the document's own growth
## could not know, which a fresh chain cannot know either, so the two forms are
## not the same question. A change that narrows the widest reach is answered
## once wider by the kept chain than by a fresh one, which is the spill the
## last composite drew being cleared, so that first answer is read as covering
## the fresh one and the answer after it as equal to it.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const WholeShiftFilter = preload("res://tests/fixtures/modules/whole-fixture/whole_shift_filter.gd")

const REQUIRES_GPU := true

## Four chunks by three, twelve.
const CANVAS := Vector2i(1024, 768)
const LAYERS := 30
const WHOLE_OWNER: StringName = &"whole-fixture"
const WHOLE_KEY: StringName = &"whole-fixture.whole_fixture_shift"

var _easel: SaEasel = null
var _document: SaDocument = null
## The layers in the order they were made, bottom first.
var _made: Array[SaLayer] = []


func before_each() -> void:
    _easel = Bench.easel(CANVAS)
    _easel.compositor.filter_chain.registry.register(WholeShiftFilter.new(), WHOLE_OWNER)
    _document = _easel.document
    _made = []
    var ops := SaLayerOps.new(_document)
    for i in LAYERS:
        var layer := ops.add()
        layer.get_or_create_chunk(_grid(i)).clear(Color(0.1 * (i % 10), 0.5, 0.2, 1.0))
        if i % 3 == 0:
            _attach(layer, 2 + i)
        _made.append(layer)
    Bench.composite(_easel)


func after_each() -> void:
    _made = []
    _document = null
    if _easel != null:
        _easel.free()
    _easel = null


## The grid position the *i*-th layer paints, round the twelve chunks.
func _grid(i: int) -> Vector2i:
    return Vector2i(i % 4, floori(i / 4.0) % 3)


## A filter of halo *reach* on *layer*, through the docker's operation.
func _attach(layer: SaLayer, reach: int) -> SaAttachedFilter:
    return SaFilterOps.new(_document).attach(layer, WHOLE_KEY, {"offset_x": 1.0, "offset_y": 0.0, "mode": 0, "reach": reach})


## A dirty set of two small regions, as a stroke leaves one.
func _dirty() -> Dictionary[Vector2i, Rect2i]:
    return {Vector2i(1, 1): Rect2i(100, 100, 20, 20), Vector2i(3, 0): Rect2i(0, 200, 10, 10)}


## What a chain made now, knowing nothing of the document, answers.
func _fresh() -> Dictionary[Vector2i, Rect2i]:
    var fresh := SaFilterChain.new()
    fresh.registry = _easel.compositor.filter_chain.registry
    return fresh.spilled(_document, _dirty(), true)


func _kept() -> Dictionary[Vector2i, Rect2i]:
    return _easel.compositor.filter_chain.spilled(_document, _dirty(), true)


## Whether every region of *inner* lies inside the region *outer* holds there.
static func _covers(outer: Dictionary[Vector2i, Rect2i], inner: Dictionary[Vector2i, Rect2i]) -> bool:
    for grid_pos: Vector2i in inner:
        if not outer.has(grid_pos) or not outer[grid_pos].encloses(inner[grid_pos]):
            return false
    return true


## Asks the kept chain before *change*, makes it, and reads the kept chain's
## answers beside a fresh one's, naming the change in each line.
func _reads_as_fresh(what: String, change: Callable) -> void:
    _kept()
    change.call()
    var first := _kept()
    var fresh := _fresh()
    assert_true(_covers(first, fresh), "After %s the kept chain's first answer covers a fresh chain's" % what)
    assert_eq(_kept(), fresh, "and its next answer is a fresh chain's, after %s" % what)


func test_the_answer_before_any_change_is_a_fresh_chains() -> void:
    _kept()
    assert_eq(_kept(), _fresh(), "A chain that composited answers as a fresh one")
    assert_true(
        _fresh().has(Vector2i(2, 0)),
        "and the widest halo, 29 pixels, grows the region on a chunk's left edge into the chunk beside it"
    )


func test_a_layer_added() -> void:
    _reads_as_fresh(
        "a layer was added",
        func() -> void:
            var layer := SaLayerOps.new(_document).add()
            layer.get_or_create_chunk(Vector2i(2, 2)).clear(Color.WHITE)
            _attach(layer, 300)
    )
    assert_true(_fresh().has(Vector2i(0, 0)), "and its halo of 300 pixels reaches the chunk diagonally beside the region")


func test_a_layer_deleted() -> void:
    # The widest, so the answer narrows.
    var widest := _made[27]
    _reads_as_fresh("the layer of the widest halo was deleted", func() -> void: SaLayerOps.new(_document).remove(widest))


func test_a_layer_hidden() -> void:
    var widest := _made[27]
    _reads_as_fresh(
        "the layer of the widest halo was hidden", func() -> void: SaLayerOps.new(_document).set_visible(widest, false)
    )


func test_a_layer_moved_into_a_group() -> void:
    var widest := _made[27]
    _reads_as_fresh(
        "the layer of the widest halo was moved into a group", func() -> void: SaLayerOps.new(_document).group_layers([widest])
    )


func test_a_layer_given_a_filter() -> void:
    var plain := _made[4]
    _reads_as_fresh("a plain layer was given a filter of a wider halo", func() -> void: _attach(plain, 200))


func test_a_filter_disabled() -> void:
    var widest := _made[27]
    _reads_as_fresh(
        "the widest filter was disabled", func() -> void: SaFilterOps.new(_document).set_enabled(widest.filters[0], false)
    )


func test_a_mask_removed() -> void:
    var widest := _made[27]
    SaMaskOps.new(_document).add(widest)
    _reads_as_fresh(
        "the mask of the layer of the widest halo was removed", func() -> void: SaMaskOps.new(_document).remove(widest)
    )
