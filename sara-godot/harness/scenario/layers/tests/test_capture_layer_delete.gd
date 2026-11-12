## The capture harness's `layer` step names the operation its delete performed,
## rather than the answer `SaLayerOps.remove` gave.
##
## `SaLayerOps.remove` answers answer true for the only layer a document
## has, because deleting that one now clears it rather than being refused. The
## step read the answer as a deletion, so `{"layer": {"delete": true}}` on a
## one-layer document printed `deleted Layer 1` for a step that deleted nothing
## and emptied the layer instead. A dump is what a reader of a scenario trusts
## about what a step did, so a line naming the wrong operation is worth a test
## of its own.
extends "res://tests/test_framework.gd"

## The delete is a real history step over real chunks, and `update_caches` at
## the end of the step composites, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _registries: SaRegistries = null


func before_each() -> void:
    _registries = Fixtures.make_registries()


func after_each() -> void:
    _registries = null


func _document() -> Array:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    easel.compositor.set_registry(_registries.blend_modes)
    return [easel, easel.document]


## The `done` lines of the JSON a layer step answers with, `SaCapture: layer {...}`.
func _done(line: String) -> Array:
    var said: Variant = JSON.parse_string(line.trim_prefix("SaCapture: layer "))
    assert_true(said is Dictionary and said.has("done"), "The step answers JSON with its done lines: %s" % line)
    return said["done"] if said is Dictionary and said.has("done") else []


func test_a_delete_that_drops_the_count_says_deleted() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    var stack := SaLayerOps.new(doc).layers()
    assert_true(stack.size() > 1, "A fresh document has more than one layer to delete from")
    var doomed: SaLayer = stack[stack.size() - 1]
    doc.set_active_layer(doomed)

    var line := SaCaptureLayers.run(doc, {"delete": true})
    assert_eq(_done(line), ["deleted %s" % doomed.name], "The step names the layer it took out")
    assert_eq(SaLayerOps.new(doc).layers().size(), stack.size() - 1, "and the stack is one shorter")
    easel.free()


func test_a_delete_of_the_only_layer_says_cleared() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    var removals := SaLayerOps.new(doc).layers().size()
    while SaLayerOps.new(doc).layers().size() > 1 and removals > 0:
        var stack := SaLayerOps.new(doc).layers()
        assert_true(SaLayerOps.new(doc).remove(stack[stack.size() - 1]), "down to the last layer")
        removals -= 1
    assert_eq(SaLayerOps.new(doc).layers().size(), 1, "and the last layer is all that stands")
    var last: SaLayer = SaLayerOps.new(doc).layers()[0]
    doc.set_active_layer(last)
    assert_false(last.chunks.is_empty(), "which holds the paper it was filled with")

    var line := SaCaptureLayers.run(doc, {"delete": true})
    assert_eq(_done(line), ["cleared %s" % last.name], "The step says it emptied the layer")
    assert_eq(SaLayerOps.new(doc).layers().size(), 1, "because the row stayed")
    assert_true(last.chunks.is_empty(), "with every chunk released")
    easel.free()


func test_a_locked_last_layer_is_still_kept() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    var removals := SaLayerOps.new(doc).layers().size()
    while SaLayerOps.new(doc).layers().size() > 1 and removals > 0:
        var stack := SaLayerOps.new(doc).layers()
        assert_true(SaLayerOps.new(doc).remove(stack[stack.size() - 1]), "down to the last layer")
        removals -= 1
    assert_eq(SaLayerOps.new(doc).layers().size(), 1, "and the last layer is all that stands")
    var last: SaLayer = SaLayerOps.new(doc).layers()[0]
    doc.set_active_layer(last)

    var line := SaCaptureLayers.run(doc, {"lock": true, "delete": true})
    assert_eq(
        _done(line),
        ["%s locked true" % last.name, "kept the last layer"],
        "A locked last layer is the one case the delete still refuses, and the refusal line stays"
    )
    assert_false(last.chunks.is_empty(), "so the paint is untouched")
    easel.free()
