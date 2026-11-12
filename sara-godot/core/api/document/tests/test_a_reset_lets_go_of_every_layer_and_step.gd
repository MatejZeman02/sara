## A new document made over one of 305 layers took 24.8 s
## and grew the process from 1.82 to 5.71 GB.
##
## `reset_to_default` freed the layers one by one, and each free told every
## listener of the document's stack that the stack had changed. What this holds
## is that a reset lets go of every chunk the layers held and every step of
## the history with the layers it kept, and tells the stack's listeners once.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice, for the chunks the layers hold.
const REQUIRES_GPU := true

const SIZE := Vector2i(512, 512)
const LAYERS := 300
const STEPS := 50

## The document is in the tree, since a node outside it announces no change
## of its children. Parented to an autoload, as `test_a_load_hands_the_docker_no_freed_layer.gd` does.
var _host: Node = null


func before_each() -> void:
    _host = Node.new()
    _host.name = "ResetHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


## Three hundred small layers, each with one chunk painted, and fifty recorded
## deletes, each keeping its layer and its chunk in the history. After the
## reset no chunk and no layer of the old document is held by anything.
func test_a_reset_releases_every_chunk_and_every_step() -> void:
    var doc := _document()
    var ops := SaLayerOps.new(doc)
    var chunks: Array[WeakRef] = []
    var layers: Array[SaLayer] = []
    doc.history.quietly(
        func() -> void:
            for i in LAYERS:
                var layer := ops.add()
                chunks.append(weakref(layer.get_or_create_chunk(Vector2i(i % 2, 0))))
                layers.append(layer)
    )
    doc.undo_redo.clear_history()
    doc.history.reset()
    var kept: Array[SaLayer] = []
    for i in STEPS:
        var gone: SaLayer = layers[i * 2]
        assert_true(ops.remove(gone), "delete %d is taken" % i)
        kept.append(gone)
    assert_eq(doc.history.step_count(), STEPS, "the history holds the fifty deletes")
    assert_eq(_held(chunks), LAYERS, "and every chunk stands before the reset")

    var notices := [0]
    doc.child_order_changed.connect(func() -> void: notices[0] += 1)
    doc.reset_to_default(Vector2i(256, 256))

    assert_eq(_held(chunks), 0, "no chunk of the old layers is held")
    assert_eq(_standing(layers), 0, "no old layer is left, the fifty the history kept among them")
    assert_eq(_standing(kept), 0, "the deleted layers went with their steps")
    assert_eq(doc.history.step_count(), 0, "the new document starts with no step")
    assert_false(doc.undo_redo.has_undo(), "and nothing to undo")
    # One for the old stack going, and one for each layer the new document adds.
    var added := SaLayerOps.new(doc).layers().size()
    assert_eq(notices[0], 1 + added, "the stack's listeners heard of the old layers going once, not once a layer")
    doc.free()


func _document() -> SaDocument:
    var compositor := SaCompositor.new()
    compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := SaDocument.new()
    doc.setup_default_document(SIZE, compositor)
    _host.add_child(doc)
    return doc


## How many of *chunks* something still holds.
func _held(chunks: Array[WeakRef]) -> int:
    return chunks.filter(func(held: WeakRef) -> bool: return held.get_ref() != null).size()


## How many of *layers* are not freed. Untyped, since a freed object will not
## pass as a layer.
func _standing(layers: Array) -> int:
    return layers.filter(func(layer: Variant) -> bool: return is_instance_valid(layer)).size()
