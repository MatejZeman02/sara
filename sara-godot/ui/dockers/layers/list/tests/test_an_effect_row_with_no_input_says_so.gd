## The Layers docker's row of an effect layer whose input was
## deleted says it has no input, and the delete's undo takes the words away.
##
## The effect then draws nothing, so its picture is as empty as a fresh paint
## layer's and says nothing about why. The row carries "No input" beside the
## name, with what to do about it on hover. The rows are built through
## `SaLayerRowView` alone, because a docker is a `Window` and adding one in a
## headless run hangs, and refreshed by hand where the list's rebuild would.
## `scenarios/an-effect-layer-whose-input-is-deleted-goes-empty-without-an-error.json`
## photographs the row in the running app.
extends "res://tests/test_framework.gd"

## The row carries a thumbnail, which is a compute dispatch.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const RowView = preload("res://ui/dockers/layers/list/layer_row_view.gd")

const WORDS := "No input"


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


func _row(layer: SaLayer, document: SaDocument) -> SaLayerRowView:
    var item: SaLayerRowView = RowView.new(str(layer.name), 0, false, 0, layer)
    EventBus.add_child(item)
    item.refresh(document)
    return item


## What *item* says about its input, the words on show or nothing.
static func _says(item: SaLayerRowView) -> String:
    return String(item.report().get("input_mark", ""))


func test_the_row_says_no_input_once_its_input_is_deleted_and_not_after_the_undo() -> void:
    var easel := _easel()
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    var source := doc.active_layer
    source.name = "Photo"
    var effect := ops.add(SaEffectLayer.TYPE_ID, Fixtures.make_registries().layer_types)
    assert_true(SaEffectLayer.input_of(effect) == source, "The effect reads the layer it was made above")
    var item := _row(effect, doc)
    assert_eq(_says(item), "", "Reading a layer, its row says nothing about its input")

    assert_true(ops.remove(source), "The input is deleted")
    item.refresh(doc)
    assert_eq(_says(item), WORDS, "and the row says it has no input")
    assert_true(item.input_mark.is_visible_in_tree(), "on show beside the name")
    var tip := item.input_mark.tooltip_text
    assert_true(tip.contains("Input"), "and its hover names where to pick one: %s" % tip)

    assert_true(doc.undo(), "The delete is one step")
    item.refresh(doc)
    assert_eq(_says(item), "", "and its undo takes the words away")
    item.free()
    easel.free()


func test_an_effect_made_with_nothing_to_read_says_so_and_a_paint_layer_never_does() -> void:
    var easel := _easel()
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    var effect := ops.add(SaEffectLayer.TYPE_ID, Fixtures.make_registries().layer_types)
    assert_true(SaEffectLayer.read(doc, effect, null), "The effect is pointed at nothing, the Input list's None")
    var item := _row(effect, doc)
    assert_eq(_says(item), WORDS, "Its row says it has no input")
    var paint := _row(doc.get_node("Layer 1") as SaLayer, doc)
    assert_eq(_says(paint), "", "A paint layer reads no input and its row never says so")
    item.free()
    paint.free()
    easel.free()
