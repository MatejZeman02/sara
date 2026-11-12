## A solid colour ground is in the Ground list beside Paper and Canvas.
##
## A painter who deleted a document's Background found no way back but a
## paint layer filled by hand, because the Ground list kept only the types that
## answer a height. The flat colour that stores nothing was registered all
## along. What this suite holds is that it is in the list as Solid Colour, that
## a pick lays it under a document with no ground and swaps a Paper for it, and
## that its colour set from the ground's dialog lands in the composite. The
## running app's half is
## `scenarios/a-solid-colour-ground-is-in-the-ground-list-beside-paper-and-canvas.json`.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the document and its composite.
const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## A blue as the picker shows it, the colour the scenario sets as well.
const BLUE := Color(0.18, 0.32, 0.78, 1.0)

var _bar: TopMenuBar = null
var _docker: LayersDocker = null
var _registries: SaRegistries = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.easel.compositor.set_registry(_registries.blend_modes)
    canvas.add_child(canvas.easel)
    _docker = LayersDockerScript.new()
    _docker.name = "LayersDocker"
    canvas.add_child(_docker)
    _docker.target_canvas = canvas
    _docker._ready()
    _docker.bind_registries(_registries.blend_modes, _registries.layer_types)
    _bar = TopMenuBar.new()
    _bar._ready()
    _bar.bind_commands(_registries.commands)
    var menu := _bar.menu("Layer") as SaLayerMenu
    menu.document = _document()
    menu.layer_types = _registries.layer_types


func after_each() -> void:
    _bar.free()
    _docker.target_canvas.free()
    _registries = null


func _document() -> SaDocument:
    return _docker.target_canvas.document


func _grounds() -> Array[SaLayer]:
    return SaLayerOps.new(_document()).layers().filter(
        func(layer: SaLayer) -> bool: return SaGroundRows.is_ground(layer, _registries.layer_types)
    )


## The Layer menu's Ground list, opened as a press on its row opens it.
func _ground_list() -> SaChoicePopup:
    var menu := _bar.menu("Layer") as SaLayerMenu
    menu.populate()
    return menu.show_grounds()


## The fresh document with its stored Background deleted, as a painter leaves it.
func _without_background() -> void:
    var doc := _document()
    SaLayerOps.new(doc).remove(doc.get_node(SaDocumentBackground.LAYER_NAME) as SaLayer)
    assert_true(doc.get_node_or_null(SaDocumentBackground.LAYER_NAME) == null, "The Background is gone")


func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var at := (y * texture.size.x + x) * 16
    return Color(data.decode_float(at), data.decode_float(at + 4), data.decode_float(at + 8), data.decode_float(at + 12))


func test_solid_colour_is_among_the_grounds() -> void:
    var ids := _ground_list().row_ids()
    assert_true(ids.has(SaGeneratedLayer.SOLID), "The Ground list holds Solid Colour: %s" % [ids])
    assert_true(ids.has(&"paper") and ids.has(&"canvas"), "beside Paper and Canvas")
    var descriptor := _registries.layer_types.get_descriptor(SaGeneratedLayer.SOLID)
    assert_eq(SaGeneratedLayer.kind_name(descriptor), "Solid Colour", "under the name Solid Colour")
    assert_false(SaGeneratedLayer.answers_height(descriptor), "and it answers no height, so thick paint sits on it")
    assert_false(SaLayerMenuRows.addable(_registries.layer_types).has(descriptor), "It is no row of the add list of its own")


func test_a_pick_lays_it_under_a_document_with_no_ground() -> void:
    _without_background()
    assert_true(_grounds().is_empty(), "The document has no ground")
    var count := SaLayerOps.new(_document()).layers().size()
    assert_true(_ground_list().press_row(SaGeneratedLayer.SOLID), "Solid Colour takes a press")
    assert_eq(SaLayerOps.new(_document()).layers().size(), count + 1, "One layer is added")
    assert_eq(_grounds().size(), 1, "and it is the one ground")
    var solid := _grounds()[0]
    assert_eq(solid.layer_type, SaGeneratedLayer.SOLID, "a Solid Colour")
    assert_eq(str(solid.name), "Solid Colour", "named for its kind")
    assert_eq(solid.get_index(), 0, "at the bottom of the stack, under the painting")
    assert_eq(solid.chunks.size(), 0, "and it stores nothing")


func test_a_pick_swaps_a_paper_for_it_in_one_step() -> void:
    var paint := _document().active_layer
    var paper := SaLayerOps.new(_document()).add(&"paper", _registries.layer_types)
    _document().set_active_layer(paint)
    var steps := _document().undo_redo.get_history_count()
    assert_true(_ground_list().press_row(SaGeneratedLayer.SOLID), "Solid Colour takes a press over a Paper")
    assert_eq(_grounds().size(), 1, "The document still stands on one ground")
    assert_eq(paper.layer_type, SaGeneratedLayer.SOLID, "the Paper now a Solid Colour")
    assert_false(paper.generator_params.has(SaGeneratedLayer.PARAM_TOOTH), "with no tooth")
    assert_eq(_document().undo_redo.get_history_count(), steps + 1, "One history step")
    _document().undo()
    assert_eq(paper.layer_type, &"paper", "which undoes to the Paper")


func test_its_colour_set_from_the_dialog_lands_in_the_composite() -> void:
    _without_background()
    _ground_list().press_row(SaGeneratedLayer.SOLID)
    var solid := _grounds()[0]
    var dialog := SaGroundDialog.new()
    var rows := dialog.rows
    rows.show_layer(_document(), SaGroundRows.ground_of(_document(), _registries.layer_types), _registries.layer_types)
    assert_true(rows.visible, "The dialog's rows show for the Solid Colour")
    assert_true(rows.swatches["color"].get_parent().visible, "with its colour")
    assert_false(rows.swatches["second"].visible, "and no second colour, which it never reads")
    assert_false(rows.tooth_slider.get_parent().visible, "nor a tooth, which it has none of")

    rows.swatches["color"].color_changed.emit(BLUE)
    var stored := _document().color_space.from_display(BLUE)
    assert_eq(solid.generator_params[SaGeneratedLayer.PARAM_COLOR], stored, "The picked colour is its colour")
    var easel := _docker.target_canvas.easel
    _document().fold.debt.settle(_document())
    _document().update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()
    var shown := _texel(easel.output, 200, 200)
    assert_almost_eq(shown.r, stored.r, 0.02, "and the composite shows it where nothing is painted: %s" % [shown])
    assert_almost_eq(shown.g, stored.g, 0.02, "in green")
    assert_almost_eq(shown.b, stored.b, 0.02, "and in blue")
    dialog.free()
