## The capture harness's `layer` step names the layer it acts on.
##
## Every key of the step acted on the active layer, and `activate` ran after
## `add`, `blend`, `clip`, `fill`, `group` and `isolated`, so
## `{"activate": "X", "blend": "multiply"}` set the blend of the layer that was
## active before. An unknown `activate` only appended a line and the rest ran,
## so `{"activate": "Typo", "delete": true}` deleted the painter's selected
## layer. `of` names the layer, and the selection stays where it was.
extends "res://tests/test_framework.gd"

## The step is real history steps over a real stack, and `update_caches` at the
## end of it composites, so this needs a RenderingDevice.
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


## A document with a layer called Below and another called Above on top of it,
## Above the one selected. Easel, document, Below, Above.
func _stack() -> Array:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    easel.compositor.set_registry(_registries.blend_modes)
    var doc := easel.document
    SaCaptureLayers.run(doc, {"add": "Below"})
    SaCaptureLayers.run(doc, {"add": "Above"})
    return [easel, doc, doc.get_node("Below"), doc.get_node("Above")]


## The JSON a layer step answers with, `SaCapture: layer {...}`.
func _said(line: String) -> Dictionary:
    var said: Variant = JSON.parse_string(line.trim_prefix("SaCapture: layer "))
    assert_true(said is Dictionary, "The step answers JSON: %s" % line)
    return said if said is Dictionary else {}


func test_of_sets_the_blend_of_the_named_layer_and_leaves_the_selection() -> void:
    var made := _stack()
    var easel: SaEasel = made[0]
    var doc: SaDocument = made[1]
    var below: SaLayer = made[2]
    var above: SaLayer = made[3]
    assert_eq(doc.active_layer, above, "Above is the selected layer to begin with")

    var said := _said(SaCaptureLayers.run(doc, {"of": "Below", "blend": "multiply"}))
    assert_eq(below.blend_mode, &"multiply", "Below blends multiply")
    assert_false(above.blend_mode == &"multiply", "and the selected layer does not")
    assert_eq(doc.active_layer, above, "The selection stayed where it was")
    assert_eq(said["layer"], "Below", "The answer names the layer it acted on")
    assert_eq(said["active"], "Above", "and the layer that is selected")
    assert_eq(said["done"], ["Below blends multiply"], "and what it did")
    easel.free()


func test_of_takes_an_index_from_the_bottom_of_the_stack() -> void:
    var made := _stack()
    var easel: SaEasel = made[0]
    var doc: SaDocument = made[1]
    var above: SaLayer = made[3]
    var bottom: SaLayer = SaLayerOps.new(doc).layers()[0]

    var said := _said(SaCaptureLayers.run(doc, {"of": 0, "opacity": 0.25}))
    assert_almost_eq(bottom.opacity, 0.25, 0.0001, "The lowest layer took the opacity")
    assert_almost_eq(above.opacity, 1.0, 0.0001, "and the selected one did not")
    assert_eq(said["index"], 0, "The answer says where the layer is counted from the bottom")
    assert_eq(doc.active_layer, above, "The selection stayed")
    easel.free()


func test_an_unknown_layer_deletes_nothing_and_answers_the_refusal() -> void:
    var made := _stack()
    var easel: SaEasel = made[0]
    var doc: SaDocument = made[1]
    var above: SaLayer = made[3]
    var before := SaLayerOps.new(doc).layers().size()

    var said := _said(SaCaptureLayers.run(doc, {"of": "Typo", "delete": true}))
    var error := String(said.get("error", ""))
    assert_true(error.contains("there is no layer named 'Typo'"), "The step says which layer it did not find: %s" % said)
    assert_eq(SaLayerOps.new(doc).layers().size(), before, "and the stack is as it was")
    assert_eq(doc.active_layer, above, "and the painter's layer is still selected")
    easel.free()


func test_an_index_past_the_stack_refuses_the_whole_step() -> void:
    var made := _stack()
    var easel: SaEasel = made[0]
    var doc: SaDocument = made[1]
    var below: SaLayer = made[2]

    var said := _said(SaCaptureLayers.run(doc, {"of": 99, "blend": "multiply", "opacity": 0.5}))
    assert_true(said.has("error"), "A layer that is not there refuses: %s" % said)
    assert_false(below.blend_mode == &"multiply", "so no key before the refusal ran")
    easel.free()


func test_of_beside_add_is_refused_before_anything_runs() -> void:
    var made := _stack()
    var easel: SaEasel = made[0]
    var doc: SaDocument = made[1]
    var before := SaLayerOps.new(doc).layers().size()

    var said := _said(SaCaptureLayers.run(doc, {"of": "Below", "add": "Third", "blend": "multiply"}))
    assert_true(String(said.get("error", "")).contains("`add`"), "A layer made in the same step has no `of` to take: %s" % said)
    assert_eq(SaLayerOps.new(doc).layers().size(), before, "and no layer was added")
    easel.free()


func test_of_beside_an_unknown_activate_is_refused_before_anything_runs() -> void:
    var made := _stack()
    var easel: SaEasel = made[0]
    var doc: SaDocument = made[1]
    var below: SaLayer = made[2]

    var said := _said(SaCaptureLayers.run(doc, {"of": "Below", "blend": "multiply", "activate": "Typo"}))
    assert_true(String(said.get("error", "")).contains("Typo"), "The layer `activate` could not find is named: %s" % said)
    assert_false(below.blend_mode == &"multiply", "and the blend before it did not run")
    easel.free()


func test_of_deletes_a_layer_that_is_not_selected_and_the_selection_stays() -> void:
    var made := _stack()
    var easel: SaEasel = made[0]
    var doc: SaDocument = made[1]
    var below: SaLayer = made[2]
    var above: SaLayer = made[3]
    var before := SaLayerOps.new(doc).layers().size()

    var said := _said(SaCaptureLayers.run(doc, {"of": "Below", "delete": true}))
    assert_eq(said["done"], ["deleted Below"], "The step says what it took out")
    assert_eq(SaLayerOps.new(doc).layers().size(), before - 1, "and the stack is one shorter")
    assert_eq(SaLayerOps.new(doc).layers().find(below), -1, "without Below in it")
    assert_eq(doc.active_layer, above, "The selection stayed")
    assert_eq(said["index"], -1, "and the answer says the layer left the stack")
    easel.free()


func test_a_key_after_the_layer_has_gone_is_left_alone_and_says_so() -> void:
    var made := _stack()
    var easel: SaEasel = made[0]
    var doc: SaDocument = made[1]
    var before := SaLayerOps.new(doc).layers().size()

    var said := _said(SaCaptureLayers.run(doc, {"of": "Below", "delete": true, "merge_down": true}))
    assert_eq(
        said["done"],
        ["deleted Below", "merge_down left alone, Below has left the stack"],
        "The merge did not fall on whichever layer took its place"
    )
    assert_eq(SaLayerOps.new(doc).layers().size(), before - 1, "so only the one layer went")
    easel.free()


func test_of_groups_the_named_layer_and_the_keys_after_it_act_on_the_group() -> void:
    var made := _stack()
    var easel: SaEasel = made[0]
    var doc: SaDocument = made[1]
    var below: SaLayer = made[2]
    var above: SaLayer = made[3]

    var said := _said(SaCaptureLayers.run(doc, {"of": "Below", "group": true, "isolated": true}))
    var group := SaLayerStack.parent_of(below)
    assert_not_null(group, "Below sits in a group now")
    assert_true(SaLayerStack.isolates(group), "and the isolated key reached the group the step made")
    assert_eq(doc.active_layer, above, "while the selection stayed on Above")
    assert_eq(said["layer"], "Below", "The answer still names the layer that was asked for")
    easel.free()


func test_activate_beside_of_moves_the_selection_and_nothing_else_does() -> void:
    var made := _stack()
    var easel: SaEasel = made[0]
    var doc: SaDocument = made[1]
    var below: SaLayer = made[2]

    var said := _said(SaCaptureLayers.run(doc, {"of": "Below", "blend": "multiply", "activate": "Below"}))
    assert_eq(below.blend_mode, &"multiply", "The blend landed on Below")
    assert_eq(doc.active_layer, below, "and `activate` made it the selected layer, as it asks")
    assert_eq(said["active"], "Below", "which the answer says")
    easel.free()


func test_a_step_without_of_still_acts_on_the_layer_it_made() -> void:
    var made := _stack()
    var easel: SaEasel = made[0]
    var doc: SaDocument = made[1]
    var above: SaLayer = made[3]

    var said := _said(SaCaptureLayers.run(doc, {"add": "Third", "blend": "multiply"}))
    var third: SaLayer = doc.get_node("Third")
    assert_eq(third.blend_mode, &"multiply", "The blend landed on the new layer, as it always did")
    assert_false(above.blend_mode == &"multiply", "and not on the one before it")
    assert_eq(said["done"], ["added Third", "Third blends multiply"], "and the answer lists both keys")
    assert_eq(said["layer"], "Third", "naming the layer the step acted on")
    assert_eq(doc.active_layer, third, "which is selected, because `add` selects it")
    easel.free()


## An `activate` naming no layer is refused, with `of` or
## without, and nothing else in the step runs: answered among what was done, it
## read as success, and a client that guessed a renamed layer's name painted on
## whichever layer was active.
func test_a_step_without_of_and_with_a_missing_activate_is_refused_and_changes_nothing() -> void:
    var made := _stack()
    var easel: SaEasel = made[0]
    var doc: SaDocument = made[1]
    var below: SaLayer = made[2]
    var above: SaLayer = made[3]
    var before := [above.blend_mode, above.opacity, above.visible, below.blend_mode, below.opacity, below.visible]
    var count := doc.get_child_count()

    var said := _said(SaCaptureLayers.run(doc, {"activate": "Typo", "blend": "screen", "opacity": 0.5}))
    assert_eq(
        String(said.get("error", "")),
        "there is no layer called Typo to activate, so nothing was done",
        "The missing layer is a refusal: %s" % said
    )
    assert_false(said.has("done"), "and nothing is listed as done")
    var after := [above.blend_mode, above.opacity, above.visible, below.blend_mode, below.opacity, below.visible]
    assert_eq(after, before, "No layer's blend, opacity or visibility moved")
    assert_eq(doc.active_layer, above, "the selection stayed where it was")
    assert_eq(doc.get_child_count(), count, "and no layer came or went")
    assert_true(
        _said(SaCaptureLayers.run(doc, {"add": "New", "activate": "New"})).has("done"),
        "A layer the same step adds is one it may activate"
    )
    easel.free()
