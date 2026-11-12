## The layers docker's ground rows offer each ground's presets and edges.
##
## The paper and the canvas each state presets and the edges past the page
## their sheet can have. The rows list them for the ground shown, mark the
## preset the layer holds or say Custom once a slider moved it off one, and a
## pick is the one history step it names. What the presets and edges draw is
## held by the ground's own suite beside its kernels,
## `test_the_paper_and_canvas_grounds_look_like_a_real_sheet_and_a_real_canvas.gd`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _registries = null


## A ground of *kind* under the active layer, which stays active.
func _add_ground(kind: StringName) -> SaLayer:
    var paint := _doc.active_layer
    var ground := SaLayerOps.new(_doc).add(kind, _registries.layer_types)
    _doc.set_active_layer(paint)
    return ground


func test_the_rows_offer_the_presets_and_the_edges() -> void:
    var rows := SaGroundRows.new()
    var paper := _add_ground(&"paper")
    rows.show_layer(_doc, paper, _registries.layer_types)
    assert_true(rows.preset_choice.get_parent().visible, "A paper shows its presets")
    assert_eq(rows.preset_choice.choice_values().size(), 4, "all four")
    assert_eq(rows.preset_choice.selected_value(), 0, "with a new paper on Cartridge")
    assert_eq(rows.edge_choice.choice_values(), [0, 1, 2, 3], "and the edges None, Cut, Deckle and Torn")
    for key: String in ["fibre", "felt", "felt_size", "laid"]:
        assert_true(rows.part_sliders[key].get_parent().visible, "and its %s row" % key)
    for key: String in ["slub", "fuzz", "crimp", "priming"]:
        assert_false(rows.part_sliders[key].get_parent().visible, "but no %s row" % key)

    rows.preset_choice.choice_picked.emit(3)
    assert_almost_eq(SaTyped.float_at(paper.generator_params, "felt", 0.0), 1.0, 0.0001, "A pick of Rough lays its felt")
    rows.show_layer(_doc, paper, _registries.layer_types)
    assert_eq(rows.preset_choice.selected_value(), 3, "and the row marks Rough")
    rows.part_sliders["felt"].value_changed.emit(0.5)
    rows.show_layer(_doc, paper, _registries.layer_types)
    assert_null(rows.preset_choice.selected_value(), "A slider moved off it reads as Custom")
    assert_eq(rows.preset_choice.text, tr("Custom"), "in words")

    rows.edge_choice.choice_picked.emit(2)
    assert_almost_eq(SaTyped.float_at(paper.generator_params, "edge", 0.0), 2.0, 0.0001, "A pick of Deckle sets the edge")
    _doc.undo()
    assert_almost_eq(SaTyped.float_at(paper.generator_params, "edge", 0.0), 0.0, 0.0001, "as one step")

    var canvas := _add_ground(&"canvas")
    rows.show_layer(_doc, canvas, _registries.layer_types)
    assert_eq(rows.preset_choice.choice_values().size(), 4, "A canvas shows its four presets")
    assert_eq(rows.edge_choice.choice_values(), [0, 1, 4], "and the edges None, Cut and Wrapped")
    for key: String in ["slub", "fuzz", "crimp", "priming"]:
        assert_true(rows.part_sliders[key].get_parent().visible, "and its %s row" % key)
    assert_null(rows.preset_choice.selected_value(), "and a canvas made before its presets reads as Custom")
    rows.free()
