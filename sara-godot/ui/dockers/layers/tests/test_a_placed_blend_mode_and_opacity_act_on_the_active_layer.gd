## Layers' Blend Mode and Opacity placed in another docker act
## on the active layer.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The opacity slider always acts on the active layer
## and stays in sync with its home copy. So each view here is built through
## the door, `SaSettings.build_element_view`, the way a composed docker builds
## one, with the Layers docker closed, and nothing in the suite hands a view a
## canvas or a registry. What it shows comes from the docker's own row.
##
## A docker is a `Window` and adding one to the tree in a headless test hangs,
## so nothing here enters the tree, as in the second blend and opacity row suite beside this one, and
## `update_caches` stands for the deferred call that announces a step on a layer
## once the frame ends.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const CATEGORY: String = SaDockerIds.LAYERS

var _registries: SaRegistries
var _easel: SaEasel
var _canvas: SaCanvas
var _doc: SaDocument
var _docker: LayersDocker
## Every view the door built, freed after each test.
var _views: Array[Control] = []
## The background, at full opacity and Normal, and the layer above it, made
## active, at a quarter and Multiply.
var _bottom: SaLayer
var _top: SaLayer


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(Vector2i(256, 256))
    _easel.compositor.set_registry(_registries.blend_modes)
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
    _docker.bind_registries(_registries.blend_modes, _registries.layer_types)
    _docker.hide()


func after_each() -> void:
    for view: Control in _views:
        if is_instance_valid(view):
            view.free()
    _views.clear()
    if _docker != null:
        _docker.free()
    _canvas.free()
    _easel.free()
    _docker = null
    _doc = null


## A fresh view of *element* of the Layers docker, built through the door.
func _view(element: String) -> SaLayerBlendOpacityRow:
    var built := SaSettings.build_element_view(CATEGORY, element)
    if built != null:
        _views.append(built)
    return built as SaLayerBlendOpacityRow


func test_blend_mode_and_opacity_are_placeable_under_their_titles() -> void:
    assert_true(SaSettings.is_placeable(CATEGORY, "Blend Mode"), "Blend Mode has a view the Layers docker registered")
    assert_true(SaSettings.is_placeable(CATEGORY, "Opacity"), "and so has Opacity")
    assert_false(SaSettings.is_placeable(CATEGORY, "Drag Handle"), "while the docker's drag bar is not placeable")
    var offered: Array = []
    for home: Dictionary in SaSettings.placeable_elements():
        if home["id"] == CATEGORY:
            assert_eq(home["title"], "Layers", "the two are listed under the Layers docker's title")
            for element: Dictionary in home["elements"]:
                offered.append("%s as %s" % [element["id"], element["title"]])
    assert_true(offered.has("Blend Mode as Blend Mode"), "Blend Mode under the title its Elements… page shows")
    assert_true(offered.has("Opacity as Opacity"), "and Opacity under its own")


## The first half of the case, for Opacity: the view built with the docker
## closed, moved, and read on the layer and on the docker's slider, then on
## another layer made active.
func test_the_opacity_view_moves_the_active_layer_and_the_closed_dockers_slider_follows() -> void:
    assert_false(_docker.visible, "the Layers docker is closed")
    var view := _view("Opacity")
    assert_not_null(view, "the door builds a view of Opacity")
    assert_not_null(view.opacity_slider, "which is the slider")
    assert_null(view.blend_mode_opt, "and nothing else")
    assert_false(view == _docker.blend_row, "a row of its own, not the docker's")
    assert_almost_eq(view.opacity_slider.value, 0.25, 0.0001, "it opens on the active layer's opacity")

    view.opacity_slider.step_by_units(35.0)
    assert_almost_eq(_top.opacity, 0.6, 0.0001, "35 per cent up from a quarter is the active layer's opacity")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Layer Opacity", "as a step on the document")
    _doc.update_caches()
    assert_almost_eq(_docker.opacity_slider.value, 0.6, 0.0001, "and the closed docker's slider reads the new value")

    _doc.set_active_layer(_bottom)
    assert_almost_eq(view.opacity_slider.value, 1.0, 0.0001, "with the background active the view reads its full opacity")
    _doc.set_active_layer(_top)
    assert_almost_eq(view.opacity_slider.value, 0.6, 0.0001, "and back on the top layer its 60")

    _doc.undo()
    _doc.update_caches()
    assert_almost_eq(_top.opacity, 0.25, 0.0001, "an undo puts the layer back")
    assert_almost_eq(view.opacity_slider.value, 0.25, 0.0001, "and the view with it")


## The docker's own slider moved is read on the view, the other way round.
func test_the_dockers_slider_moves_the_view() -> void:
    var view := _view("Opacity")
    _docker.opacity_slider.step_by_units(-15.0)
    _doc.update_caches()
    assert_almost_eq(_top.opacity, 0.1, 0.0001, "the docker's slider moves the layer")
    assert_almost_eq(view.opacity_slider.value, 0.1, 0.0001, "and the placed view reads it")


## The same for Blend Mode: a mode picked in the view's list is the active
## layer's and the docker's dropdown names it, and another layer made active
## is read on the view.
func test_the_blend_mode_view_sets_the_active_layers_mode_and_the_closed_docker_follows() -> void:
    var view := _view("Blend Mode")
    assert_not_null(view, "the door builds a view of Blend Mode")
    assert_not_null(view.blend_mode_opt, "which is the dropdown")
    assert_null(view.opacity_slider, "and no slider")
    assert_eq(view.blend_mode_opt.current, SaLayer.BLEND_MODE.MULTIPLY, "it opens on the active layer's mode")
    assert_true(view.blend_mode_opt.mode_ids().has(SaLayer.BLEND_MODE.SCREEN), "with the docker's registry's modes in its list")

    view.blend_mode_opt.popup.chosen.emit(SaLayer.BLEND_MODE.SCREEN)
    assert_eq(_top.blend_mode, SaLayer.BLEND_MODE.SCREEN, "the active layer takes the mode picked in the view")
    _doc.update_caches()
    assert_eq(_docker.blend_mode_opt.current, SaLayer.BLEND_MODE.SCREEN, "and the closed docker's dropdown names it")

    _doc.set_active_layer(_bottom)
    assert_eq(view.blend_mode_opt.current, SaLayer.BLEND_MODE.NORMAL, "with the background active the view reads Normal")
    _doc.set_active_layer(_top)
    assert_eq(view.blend_mode_opt.current, SaLayer.BLEND_MODE.SCREEN, "and back on the top layer its Screen")


## How the app boots: a composed docker may build its views before main hands
## the Layers docker its canvas and registry. A view follows the docker's row
## and takes both when the docker does, with no line that hands them to it.
func test_a_view_built_before_the_docker_has_a_canvas_takes_the_one_it_is_handed() -> void:
    _docker.free()
    _docker = LayersDocker.new()
    _docker.hide()
    var opacity := _view("Opacity")
    var blend := _view("Blend Mode")
    opacity.opacity_slider.step_by_units(-10.0)
    assert_almost_eq(_top.opacity, 0.25, 0.0001, "a view of a docker with no canvas writes no layer")

    _docker.bind_registries(_registries.blend_modes, _registries.layer_types)
    _docker.target_canvas = _canvas
    assert_almost_eq(opacity.opacity_slider.value, 0.25, 0.0001, "handed the docker's canvas, the view reads the active layer")
    assert_eq(blend.blend_mode_opt.current, SaLayer.BLEND_MODE.MULTIPLY, "and the blend view its mode")
    opacity.opacity_slider.step_by_units(35.0)
    assert_almost_eq(_top.opacity, 0.6, 0.0001, "and moving the view now moves the layer")


## A view freed with the docker that held it leaves no connection on the home
## row, and a view built after the Layers docker is gone shows nothing and
## writes nothing.
func test_a_view_lets_go_of_its_home_and_one_without_a_home_writes_nothing() -> void:
    var before := _docker.blend_row.rebound.get_connections().size()
    var view := _view("Opacity")
    assert_eq(_docker.blend_row.rebound.get_connections().size(), before + 1, "a view listens to the docker's row")
    view.free()
    assert_eq(_docker.blend_row.rebound.get_connections().size(), before, "and lets go of it when freed")

    _docker.free()
    _docker = null
    var orphan := _view("Opacity")
    assert_not_null(orphan, "the door still builds a view once the docker is gone")
    orphan.opacity_slider.step_by_units(-10.0)
    assert_almost_eq(_top.opacity, 0.25, 0.0001, "and moving it writes no layer")
