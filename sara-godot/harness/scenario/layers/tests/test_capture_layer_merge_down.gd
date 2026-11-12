## The capture harness's `layer` step tells a refused merge from a merge with
## nothing below it.
##
## `SaLayerOps.merge_down` answers false for a group or a
## generated layer with a layer below it as well as for the bottom layer, and
## the step printed "nothing below to merge into" for both. The walk of that
## row's scenario printed it four times over a stack with a layer below each
## time, beside a corner line naming the real reason.
extends "res://tests/test_framework.gd"

## The merge is a real history step over real chunks, and `update_caches` at
## the end of the step composites, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _registries: SaRegistries = null
var _announced: bool = true


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _announced = SaProblems.announce
    SaProblems.announce = false


func after_each() -> void:
    SaProblems.announce = _announced
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


## A group merges down into a paint layer, so the
## refusal is met with a group under the group.
func test_a_group_over_a_group_is_refused_with_the_reason() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    SaCaptureLayers.run(doc, {"add": "Lower", "fill": [0.1, 0.3, 0.7, 1.0], "group": true})
    var lower := doc.active_layer
    SaCaptureLayers.run(doc, {"add": "Member", "fill": [0.8, 0.2, 0.1, 0.5], "group": true})
    var group := doc.active_layer
    assert_true(group.is_group, "the step left the new group active")
    assert_eq(SaGroupMerge.lower_of(doc, group), lower, "over the first group")
    var before := SaLayerOps.new(doc).layers().size()
    assert_true(SaLayerOps.new(doc).layers().find(group) > 0, "with a layer below it")

    var line: String = _done(SaCaptureLayers.run(doc, {"merge_down": true}))[0]
    assert_true(line.begins_with("refused, "), "The step says the merge was refused: %s" % line)
    assert_true(line.contains("is a group"), "and quotes the corner line's reason: %s" % line)
    assert_false(line.contains("nothing below"), "rather than claiming there was nothing below")
    assert_eq(SaLayerOps.new(doc).layers().size(), before, "and the stack is as it was")
    easel.free()


func test_the_bottom_layer_has_nothing_below() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    var bottom: SaLayer = SaLayerOps.new(doc).layers()[0]
    doc.set_active_layer(bottom)

    var line := SaCaptureLayers.run(doc, {"merge_down": true})
    assert_eq(_done(line), ["nothing below to merge into"], "The bottom layer has no layer below")
    easel.free()


func test_a_plain_merge_still_says_merged() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    SaCaptureLayers.run(doc, {"add": "Ground", "fill": [0.1, 0.3, 0.7, 1.0]})
    SaCaptureLayers.run(doc, {"add": "Plain", "fill": [0.5, 0.1, 0.8, 0.5]})

    var line: String = _done(SaCaptureLayers.run(doc, {"merge_down": true}))[0]
    assert_eq(line, "merged Plain down", "A merge that takes names the layer")
    easel.free()
