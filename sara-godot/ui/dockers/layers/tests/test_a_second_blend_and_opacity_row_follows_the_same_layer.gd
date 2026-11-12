## The blend and opacity row is a class that follows the active
## layer itself.
##
## The opacity slider and the blend dropdown are a class of their own and
## not lines inside the Layers docker that only that docker can drive. So a second `SaLayerBlendOpacityRow` stands beside the
## docker's here, handed the same canvas and registry and nothing else, and
## each row is read for what the other did. No call to the docker drives
## either row after it is built.
##
## A docker is a `Window` and adding one to the tree in a headless test hangs,
## so nothing here enters the tree, as in `test_layer_multiselect.gd`. A test
## cannot await a frame either, so `update_caches` stands for the deferred
## call that announces a step on a layer once the frame ends.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _easel: SaEasel
var _canvas: SaCanvas
var _doc: SaDocument
var _docker: LayersDocker
## The second row, beside the docker's own in its column.
var _row: SaLayerBlendOpacityRow
## The background, at full opacity and Normal, and the layer above it, made
## active, at a quarter and Multiply.
var _bottom: SaLayer
var _top: SaLayer


func before_each() -> void:
    var registries := Fixtures.make_registries()
    _easel = SaEasel.create_default(Vector2i(256, 256))
    _easel.compositor.set_registry(registries.blend_modes)
    _doc = _easel.document
    var ops := SaLayerOps.new(_doc)
    _bottom = _doc.active_layer
    _top = ops.add()
    ops.set_opacity(_top, 0.25)
    ops.set_blend_mode(_top, SaLayer.BLEND_MODE.MULTIPLY)
    _doc.set_active_layer(_top)
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.target_canvas = _canvas
    _docker.bind_registries(registries.blend_modes, registries.layer_types)
    _row = SaLayerBlendOpacityRow.new()
    _docker.blend_row.add_sibling(_row)
    _row.target_canvas = _canvas
    _row.blend_registry = registries.blend_modes
    _row.refresh()


func after_each() -> void:
    _docker.free()
    _canvas.free()
    _easel.free()
    _docker = null
    _row = null
    _doc = null


func test_both_rows_open_on_the_active_layer() -> void:
    assert_true(_row.get_parent() == _docker.blend_row.get_parent(), "the second row stands in the docker's column")
    assert_false(_row == _docker.blend_row, "and is a row of its own")
    assert_almost_eq(_docker.opacity_slider.value, 0.25, 0.0001, "the docker's slider reads the active layer")
    assert_almost_eq(_row.opacity_slider.value, 0.25, 0.0001, "and so does the second row's")
    assert_eq(_docker.blend_mode_opt.current, SaLayer.BLEND_MODE.MULTIPLY, "the docker's dropdown reads its mode")
    assert_eq(_row.blend_mode_opt.current, SaLayer.BLEND_MODE.MULTIPLY, "and so does the second row's")


## The first half of the case: the second row's opacity moved, read on the
## layer and on the docker's slider.
func test_the_second_rows_opacity_moves_the_layer_and_the_docker_follows() -> void:
    _row.opacity_slider.step_by_units(35.0)
    assert_almost_eq(_top.opacity, 0.6, 0.0001, "35 per cent up from a quarter is the active layer's opacity")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Layer Opacity", "as a step on the document")
    _doc.update_caches()
    assert_almost_eq(_docker.opacity_slider.value, 0.6, 0.0001, "and the docker's slider reads the new value")
    assert_almost_eq(_row.opacity_slider.value, 0.6, 0.0001, "where the second row's stands")

    _doc.undo()
    _doc.update_caches()
    assert_almost_eq(_top.opacity, 0.25, 0.0001, "an undo puts the layer back")
    assert_almost_eq(_docker.opacity_slider.value, 0.25, 0.0001, "and the docker's slider with it")
    assert_almost_eq(_row.opacity_slider.value, 0.25, 0.0001, "and the second row's")


## The same for the dropdown: a mode picked in the second row's list, the row a
## press on it chooses, is the layer's, and the docker's dropdown names it.
func test_a_mode_picked_in_the_second_row_is_the_layers_and_the_docker_follows() -> void:
    _row.blend_mode_opt.popup.chosen.emit(SaLayer.BLEND_MODE.SCREEN)
    assert_eq(_top.blend_mode, SaLayer.BLEND_MODE.SCREEN, "the active layer takes the mode")
    _doc.update_caches()
    assert_eq(_docker.blend_mode_opt.current, SaLayer.BLEND_MODE.SCREEN, "and the docker's dropdown names it")


## The second half of the case: another layer made active, read on both rows
## at that layer's opacity and mode.
func test_another_active_layer_moves_both_rows_to_it() -> void:
    _row.opacity_slider.step_by_units(35.0)
    _doc.set_active_layer(_bottom)
    assert_almost_eq(_bottom.opacity, 1.0, 0.0001, "the background is still at full opacity")
    assert_almost_eq(_docker.opacity_slider.value, 1.0, 0.0001, "the docker's slider reads the background")
    assert_almost_eq(_row.opacity_slider.value, 1.0, 0.0001, "and so does the second row's")
    assert_eq(_docker.blend_mode_opt.current, SaLayer.BLEND_MODE.NORMAL, "the docker's dropdown reads Normal")
    assert_eq(_row.blend_mode_opt.current, SaLayer.BLEND_MODE.NORMAL, "and so does the second row's")

    _doc.set_active_layer(_top)
    assert_almost_eq(_docker.opacity_slider.value, 0.6, 0.0001, "back on the top layer the docker reads its 60")
    assert_almost_eq(_row.opacity_slider.value, 0.6, 0.0001, "and so does the second row")
    assert_eq(_row.blend_mode_opt.current, SaLayer.BLEND_MODE.MULTIPLY, "with its Multiply")


## A row handed no canvas shows nothing and moves nothing, and a row handed
## another canvas lets go of the first document.
func test_a_row_lets_go_of_the_document_it_leaves() -> void:
    _row.target_canvas = null
    _doc.set_active_layer(_bottom)
    assert_almost_eq(_row.opacity_slider.value, 0.25, 0.0001, "a row with no canvas stays where it stood")
    assert_almost_eq(_docker.opacity_slider.value, 1.0, 0.0001, "while the docker's follows")
    _row.opacity_slider.step_by_units(-10.0)
    assert_almost_eq(_bottom.opacity, 1.0, 0.0001, "and moving it writes no layer")
    assert_false(_doc.document_changed.is_connected(_row.sync_from_active_layer), "nor does it still hear the document")
