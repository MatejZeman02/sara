## An open of the seasons file holds no frame over a tenth of
## a second outside the effect layers.
##
## Five frames of the open passed 0.1 s: the call that read the header, let go
## of the old stack and read the blobs, the landing's first walk that built
## every filter's passes, the fill's last step with its record, the Layers
## docker's rows let go and built, and a step that hashed the chunks it read
## while the card still walked the whole canvas. The pieces here are the ones
## that spread them: the layers the open takes out and frees a share a frame,
## the filters the chain leaves to the fill, and the open that answers once,
## a frame after its record is kept. The rows the Layers list frees a share a
## frame have their suite beside the list. The running app's reading is the
## two takes of `open_trace.py` in the unit's proof folder.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save reads chunks back and an open writes them.
const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const SIZE := Vector2i(64, 64)
const PAINTED := 4

var _easels: Array[SaEasel] = []
var _paths: Array[String] = []


func after_each() -> void:
    for easel in _easels:
        easel.free()
    _easels.clear()
    for path in _paths:
        DirAccess.remove_absolute(path)
    _paths.clear()


func _easel() -> SaEasel:
    var made := Bench.easel(SIZE)
    _easels.append(made)
    return made


static func _layers(document: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in document.get_children():
        if child is SaLayer and child != document.stroke_layer:
            found.append(child)
    return found


func test_the_layers_an_open_takes_out_leave_the_document_and_wait_to_be_freed() -> void:
    var document := _easel().document
    for i in PAINTED:
        SaLayerOps.new(document).add(&"").name = "Painted %d" % i
    var had := _layers(document)
    assert_true(had.size() >= PAINTED, "The document holds its layers: %d" % had.size())
    var out := SaSadLettingGo.taken_out(document)
    assert_eq(_layers(document), [] as Array[SaLayer], "The document holds none of them once they are taken out")
    assert_eq(out.size(), had.size(), "and every one is answered for the open to free")
    var outside := out.all(func(layer: SaLayer) -> bool: return is_instance_valid(layer) and layer.get_parent() == null)
    assert_true(outside, "each still there and in no tree")
    for layer in out:
        layer.free()


func test_the_filters_held_back_are_built_one_call_each_and_an_empty_hold_lets_them_go() -> void:
    var document := _easel().document
    var chain := document.compositor.filter_chain
    var first := SaLayerOps.new(document).add(&"")
    var second := SaLayerOps.new(document).add(&"")
    chain.hold_back([first, second] as Array[SaLayer])
    assert_eq(chain._held_back.size(), 2, "Both layers' passes are held back")
    chain.build(first)
    assert_false(chain._held_back.has(first.get_instance_id()), "A build lets the first go")
    assert_true(chain._held_back.has(second.get_instance_id()), "and keeps the second held")
    chain.hold_back([] as Array[SaLayer])
    assert_true(chain._held_back.is_empty(), "An empty hold lets every one go")


func test_an_open_over_frames_answers_once_and_leaves_nothing_busy() -> void:
    var source := _easel().document
    for i in PAINTED:
        SaLayerOps.new(source).add(&"").name = "Painted %d" % i
    var path := ProjectSettings.globalize_path(SaDataRoot.path("test_u725.sad"))
    _paths.append(path)
    assert_eq(SaExport.save_sad(source, path), OK, "The file is written")
    var target := _easel().document
    var answers: Array[Error] = []
    SaExport.open_sad(target, path, answers.append)
    for _i in 60:
        if not answers.is_empty():
            break
        await (Engine.get_main_loop() as SceneTree).process_frame
    assert_eq(answers, [OK] as Array[Error], "The answer comes once, and it is OK")
    assert_false(SaSadFile.filling(target), "Nothing is filling once it answered")
    await (Engine.get_main_loop() as SceneTree).process_frame
    await (Engine.get_main_loop() as SceneTree).process_frame
    assert_false(SaSadFile.opening(), "and two frames after it no open is busy")
