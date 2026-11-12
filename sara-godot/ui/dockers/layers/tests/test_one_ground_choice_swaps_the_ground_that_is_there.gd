## Layer then Ground is one choice among every ground, and
## picking one swaps the ground that is there.
##
## Paper and Canvas were two rows of the Layer menu and of the docker's add
## arrow, each adding a layer even over a ground. What this suite holds is
## that both have one Ground row whose list is every ground the registry
## holds, a module's included, that a pick over a Paper swaps it for a Canvas
## in one history step with its colours kept, and that a pick with no ground
## lays one.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the document the menus are drawn for.
const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const FIXTURE_MODULE = preload("res://tests/fixtures/noise-ground/modules/noise-ground-fixture/module.gd")

## A tone no ground is born with, so a kept colour is told from a default.
const TONE := Color(0.31, 0.27, 0.22, 1.0)

var _bar: TopMenuBar = null
var _docker: LayersDocker = null
var _registries: SaRegistries = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
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
    var menu := _layer_menu()
    menu.document = _document()
    menu.layer_types = _registries.layer_types


func after_each() -> void:
    _bar.free()
    _docker.target_canvas.free()
    _registries = null


func _layer_menu() -> SaLayerMenu:
    return _bar.menu("Layer") as SaLayerMenu


func _document() -> SaDocument:
    return _docker.target_canvas.document


func _layers() -> Array[SaLayer]:
    return SaLayerOps.new(_document()).layers()


func _grounds() -> Array[SaLayer]:
    return _layers().filter(func(layer: SaLayer) -> bool: return SaGroundRows.is_ground(layer, _registries.layer_types))


## The Layer menu built afresh and its Ground list opened, as a press on the
## Ground row opens it.
func _ground_list() -> SaChoicePopup:
    var menu := _layer_menu()
    menu.populate()
    var key := SaMenu.key(SaLayerMenuRows.number_of(SaGroundChoice.ROW))
    var holder := SaMenu.list_holding(menu.popup, key)
    assert_true(holder != null and holder.is_branch(key), "The Layer menu's Ground row opens a list")
    return menu.show_grounds()


## A Paper laid the way the arrow laid one before, toned to [constant TONE],
## with a paint layer active above it.
func _lay_paper() -> SaLayer:
    var paint := _document().active_layer
    var paper := SaLayerOps.new(_document()).add(&"paper", _registries.layer_types)
    paper.generator_params[SaGeneratedLayer.PARAM_COLOR] = TONE
    _document().set_active_layer(paint)
    return paper


func test_the_menus_have_one_ground_row_and_no_row_per_ground() -> void:
    var menu := _layer_menu()
    menu.populate()
    var words := SaMenu.labels_of(menu.popup)
    assert_true(words.has("Ground"), "The Layer menu has a Ground row: %s" % [words])
    assert_false(words.has("Paper") or words.has("Canvas"), "and no Paper or Canvas row of its own")
    _docker.actions.fill_add_type_menu()
    var arrow: SaChoicePopup = _docker.actions._add_type_menu
    assert_true(arrow.is_branch(SaGroundChoice.ROW), "The arrow has the Ground row as well")
    assert_false(arrow.row_ids().has(&"paper") or arrow.row_ids().has(&"canvas"), "and no row per ground")


func test_canvas_picked_over_a_paper_swaps_it_in_one_step() -> void:
    var paper := _lay_paper()
    var count := _layers().size()
    var steps := _document().undo_redo.get_history_count()

    var list := _ground_list()
    assert_eq(list.current, &"paper", "The list marks the Paper that stands")
    assert_true(list.press_row(&"canvas"), "Canvas takes a press")
    assert_eq(_layers().size(), count, "The stack holds as many layers as before")
    assert_eq(_grounds().size(), 1, "and one ground")
    assert_eq(paper.layer_type, &"canvas", "the Paper now a Canvas")
    assert_true(paper.generator_params.has(SaGeneratedLayer.PARAM_THICKNESS), "with the canvas's threads")
    assert_eq(paper.generator_params[SaGeneratedLayer.PARAM_COLOR], TONE, "and the Paper's own colour kept")
    assert_eq(_document().undo_redo.get_history_count(), steps + 1, "One history step")

    _document().undo()
    assert_eq(paper.layer_type, &"paper", "which undoes to the Paper")
    assert_eq(_layers().size(), count, "with the stack as it was")


func test_paper_picked_with_no_ground_lays_one() -> void:
    assert_true(_grounds().is_empty(), "The document starts with no ground")
    var count := _layers().size()
    assert_true(_ground_list().press_row(&"paper"), "Paper takes a press")
    assert_eq(_layers().size(), count + 1, "One layer is added")
    assert_eq(_grounds().size(), 1, "and it is the one ground")
    assert_eq(_grounds()[0].layer_type, &"paper", "a Paper")


func test_the_arrow_and_the_old_number_swap_rather_than_add() -> void:
    var paper := _lay_paper()
    var count := _layers().size()
    assert_true(_docker.actions.open_grounds().press_row(&"canvas"), "The arrow's Ground list takes a press")
    assert_eq(paper.layer_type, &"canvas", "and swaps the ground")
    var addable := SaLayerMenuRows.addable(_registries.layer_types).filter(
        func(descriptor: SaLayerTypeDescriptor) -> bool: return descriptor.id != SaLayerTypeDescriptor.PLAIN
    )
    var at := addable.map(func(descriptor: SaLayerTypeDescriptor) -> StringName: return descriptor.id).find(&"paper")
    _layer_menu().on_id_pressed(SaLayerMenuRows.FIRST_KIND + at)
    assert_eq(paper.layer_type, &"paper", "Paper pressed by its old number swaps it back")
    assert_eq(_layers().size(), count, "and never adds a second ground")
    _layer_menu().on_id_pressed(SaLayerMenuRows.FIRST_KIND + at)
    assert_eq(_layers().size(), count, "Picking the ground that stands changes nothing")


func test_a_modules_ground_is_in_the_choice_beside_paper_and_canvas() -> void:
    FIXTURE_MODULE.new().register(_registries.context.for_module(FIXTURE_MODULE.ID))
    var ids := _ground_list().row_ids()
    assert_true(ids.has(&"paper") and ids.has(&"canvas"), "The list holds Paper and Canvas: %s" % [ids])
    assert_true(ids.has(FIXTURE_MODULE.TYPE), "and the module's Noise Ground beside them")
    var paper := _lay_paper()
    _ground_list().press_row(FIXTURE_MODULE.TYPE)
    assert_eq(paper.layer_type, FIXTURE_MODULE.TYPE, "which a pick swaps the Paper for")
    assert_eq(paper.generator_params[SaGeneratedLayer.PARAM_COLOR], TONE, "its colour kept")
