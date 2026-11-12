## Opening a file over the live document handed the layers
## docker a freed layer, one `SCRIPT ERROR` per layer loaded.
##
## The load freed every layer and left the document's active layer pointing at
## one of them, and each `child_exiting_tree` and `child_entered_tree` on the way
## made the docker read it. What this holds is that no signal the docker answers
## ever finds a freed layer there, on a load and on File > New alike. The run
## itself is the other half: `run_tests.sh` fails on any `SCRIPT ERROR`, and the
## docker below listens to every signal of the rebuild.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the chunks the save writes and the load reads.
const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")

static var scratch_path: String = SaDataRoot.path("test_a_load_hands_the_docker_no_freed_layer.sad")

## Every moment the docker could have read a freed active layer, by the signal.
var _freed_reads: Array[String] = []

## The document has to be in the tree, since a node outside it announces no
## `child_entered_tree` and `child_exiting_tree`, which are the two signals the
## defect travelled by. Parented to an autoload rather than to the root, for the
## reason `test_canvas_view.gd` gives.
var _host: Node = null


func before_each() -> void:
    _host = Node.new()
    _host.name = "D2LoadTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


func _docker_on_a_document() -> LayersDocker:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    var docker: LayersDocker = LayersDockerScript.new()
    docker.name = "LayersDocker"
    canvas.add_child(docker)
    docker.target_canvas = canvas
    docker._ready()
    _host.add_child(canvas)
    assert_true(canvas.document.is_inside_tree(), "the document is in the tree, so its tree signals fire")
    return docker


## Three layers over the default ones, the first active, so the first layer the load frees is the
## one every later signal would have read.
func _document_of_several_layers(docker: LayersDocker) -> SaDocument:
    var doc := docker.target_canvas.document
    for i in 3:
        docker.actions.add_layer()
    doc.active_layer = _layers(doc)[0]
    return doc


func _layers(doc: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in doc.get_children():
        if child is SaLayer and child != doc.stroke_layer:
            found.append(child)
    return found


## The same three signals the docker listens to, each checking what it would
## read. A freed object is still a TYPE_OBJECT, which is what tells it from null.
func _watch(doc: SaDocument) -> void:
    _freed_reads.clear()
    doc.child_entered_tree.connect(func(_node: Node) -> void: _check(doc, "child_entered_tree"))
    doc.child_exiting_tree.connect(func(_node: Node) -> void: _check(doc, "child_exiting_tree"))
    doc.active_layer_changed.connect(func(_layer: SaLayer) -> void: _check(doc, "active_layer_changed"))


func _check(doc: SaDocument, heard: String) -> void:
    var active: Variant = doc.active_layer
    if typeof(active) == TYPE_OBJECT and not is_instance_valid(active):
        _freed_reads.append(heard)


func test_a_load_over_a_live_document_never_shows_the_docker_a_freed_layer() -> void:
    var docker := _docker_on_a_document()
    var doc := _document_of_several_layers(docker)
    var saved := _layers(doc).size()
    assert_eq(SaExport.save_sad(doc, scratch_path), OK, "the layers save")
    _watch(doc)
    assert_eq(SaExport.load_sad(doc, scratch_path, docker.target_canvas.compositor), OK, "and load back over themselves")
    assert_eq(_freed_reads, [] as Array[String], "no signal of the rebuild found a freed active layer")
    var loaded := _layers(doc)
    assert_true(saved >= 4, "at least four layers went into the file")
    assert_eq(loaded.size(), saved, "and every one of them is back")
    assert_true(doc.active_layer == loaded[0], "and the first of them is active, as `_finish_load` sets it")
    assert_true(docker._rows_match_document(), "the docker's rows are the loaded stack")
    DirAccess.remove_absolute(scratch_path)


## A mask target belongs to a layer the load frees, so it goes with it rather
## than leaving the brush painting into a mask no layer carries.
func test_a_load_lets_go_of_the_mask_target() -> void:
    var docker := _docker_on_a_document()
    var doc := _document_of_several_layers(docker)
    assert_eq(SaExport.save_sad(doc, scratch_path), OK, "the layers save")
    doc.mask_target = SaMask.new()
    assert_eq(SaExport.load_sad(doc, scratch_path, docker.target_canvas.compositor), OK, "and load back over themselves")
    assert_null(doc.mask_target, "no mask target survives the layers it belonged to")
    DirAccess.remove_absolute(scratch_path)


## File > New throws the layers away through `reset_to_default`, which freed
## them before letting go of the active one and so had the same gap.
func test_a_new_document_never_shows_the_docker_a_freed_layer() -> void:
    var docker := _docker_on_a_document()
    var doc := _document_of_several_layers(docker)
    _watch(doc)
    doc.reset_to_default(Vector2i(128, 128))
    assert_eq(_freed_reads, [] as Array[String], "no signal of the reset found a freed active layer")
    assert_true(is_instance_valid(doc.active_layer), "and the fresh document has a live active layer")
