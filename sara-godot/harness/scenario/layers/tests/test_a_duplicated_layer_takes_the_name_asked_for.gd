## The `layer` step's `duplicate` takes a name.
##
## `layer.duplicate()` in `sara.py` had no way to name the copy, because the rule that keeps a layer already
## called the name an `add` asks for and a copy must not be that. A copy is a
## new layer, so a name the stack holds refuses the whole step before anything
## runs, and the name is given inside the one "Duplicate Layer" step.
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


## A document with Ink above its first layer, and the first layer selected, so
## a copy made through `of` is seen to move the selection.
func _stack() -> Array:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    easel.compositor.set_registry(_registries.blend_modes)
    var doc := easel.document
    SaCaptureLayers.run(doc, {"add": "Ink"})
    doc.set_active_layer(SaLayerOps.new(doc).layers()[0])
    return [easel, doc]


func _said(line: String) -> Dictionary:
    var said: Variant = JSON.parse_string(line.trim_prefix("SaCapture: layer "))
    assert_true(said is Dictionary, "The step answers JSON: %s" % line)
    return said if said is Dictionary else {}


func _names(doc: SaDocument) -> Array[String]:
    var names: Array[String] = []
    for layer: SaLayer in SaLayerOps.new(doc).layers():
        names.append(String(layer.name))
    return names


func test_a_named_copy_sits_above_its_layer_selected_and_under_its_name() -> void:
    var made := _stack()
    var easel: SaEasel = made[0]
    var doc: SaDocument = made[1]
    var steps := doc.history.step_count()

    var said := _said(SaLayerStep.run(doc, {"of": "Ink", "duplicate": "Ink blurred"}))
    assert_false(said.has("error"), "The step is not refused: %s" % said)
    assert_eq(_names(doc).slice(-2), ["Ink", "Ink blurred"] as Array[String], "the copy is above Ink")
    assert_eq(String(doc.active_layer.name), "Ink blurred", "and selected")
    assert_eq(said.get("active"), "Ink blurred", "which the answer says")
    assert_true((said.get("done", []) as Array).has("duplicated as Ink blurred"), "the line the client reads")
    assert_eq(doc.history.step_count(), steps + 1, "one history step for the copy and its name")
    easel.free()


func test_one_undo_takes_the_named_copy_away_and_a_redo_brings_it_back_under_the_name() -> void:
    var made := _stack()
    var easel: SaEasel = made[0]
    var doc: SaDocument = made[1]
    var before := _names(doc)
    SaLayerStep.run(doc, {"of": "Ink", "duplicate": "Ink blurred"})

    assert_true(doc.undo(), "Undo takes a step back")
    assert_eq(_names(doc), before, "and the copy is gone with it")
    assert_true(doc.redo(), "Redo takes it forward")
    assert_eq(_names(doc).slice(-1), ["Ink blurred"] as Array[String], "the copy is back under its name")
    easel.free()


func test_a_name_the_stack_holds_refuses_and_leaves_the_stack_and_the_history() -> void:
    var made := _stack()
    var easel: SaEasel = made[0]
    var doc: SaDocument = made[1]
    SaLayerStep.run(doc, {"of": "Ink", "duplicate": "Ink blurred"})
    var names := _names(doc)
    var active := doc.active_layer
    var steps := doc.history.step_count()

    var said := _said(SaLayerStep.run(doc, {"of": "Ink", "duplicate": "Ink blurred"}))
    assert_true(String(said.get("error", "")).contains("already called 'Ink blurred'"), "a sentence names it: %s" % said)
    var holder := "layer %d " % names.find("Ink blurred")
    assert_true(String(said.get("error", "")).contains(holder), "and the place of the layer that holds it")
    assert_eq(_names(doc), names, "the stack is as it was")
    assert_eq(doc.active_layer, active, "and the selection")
    assert_eq(doc.history.step_count(), steps, "and the history")
    easel.free()


func test_the_refusal_comes_before_any_other_key_of_the_step() -> void:
    var made := _stack()
    var easel: SaEasel = made[0]
    var doc: SaDocument = made[1]
    var ink: SaLayer = doc.get_node("Ink")

    var said := _said(SaLayerStep.run(doc, {"of": "Ink", "opacity": 0.25, "duplicate": "Ink"}))
    assert_true(said.has("error"), "a copy may not take its own layer's name")
    assert_eq(ink.opacity, 1.0, "and the opacity before it in the step was never set")
    easel.free()


func test_an_empty_name_or_one_godot_would_change_is_refused() -> void:
    var made := _stack()
    var easel: SaEasel = made[0]
    var doc: SaDocument = made[1]
    var names := _names(doc)
    for asked: String in ["", "  ", "a.b", "a/b"]:
        var said := _said(SaLayerStep.run(doc, {"of": "Ink", "duplicate": asked}))
        assert_true(said.has("error"), "'%s' is refused" % asked)
    assert_eq(_names(doc), names, "and nothing was copied")
    easel.free()


func test_true_names_the_copy_as_the_menu_does() -> void:
    var made := _stack()
    var easel: SaEasel = made[0]
    var doc: SaDocument = made[1]

    var said := _said(SaLayerStep.run(doc, {"of": "Ink", "duplicate": true}))
    var made_name := String(doc.active_layer.name)
    assert_false(made_name == "Ink", "a copy of its own")
    assert_true((said.get("done", []) as Array).has("duplicated as %s" % made_name), "named as the menu names it")
    easel.free()
