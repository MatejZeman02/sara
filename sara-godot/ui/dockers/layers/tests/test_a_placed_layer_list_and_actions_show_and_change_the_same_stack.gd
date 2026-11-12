## Layers' Layer List and Actions placed in another docker show
## and change the same stack.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A placed element can be "a whole list" as readily as a slider, and
## it is a second view of the same state as at home.
## So each view here is built through the door, `SaSettings.build_element_view`,
## the way a composed docker builds one, with the Layers docker closed, and
## nothing in the suite hands a view a canvas, a keeper or a list. What it shows
## and what it acts on come from the docker's own keeper and strip.
##
## A docker is a `Window` and adding one to the tree in a headless test hangs,
## so nothing here enters the tree, as in the second layer list suite beside this one, and the
## docker's keeper is told to listen, which the docker's `_ready` does in the
## app.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const CATEGORY: String = SaDockerIds.LAYERS

var _registries: SaRegistries
var _easel: SaEasel
var _canvas: SaCanvas
var _doc: SaDocument
var _docker: LayersDocker
## The docker's own list.
var _home: SaLayerList
## Every view the door built, freed after each test.
var _views: Array[Control] = []
## The two layers made here, the bottom one active, and the Background the default
## document holds under them.
var _bottom: SaLayer
var _top: SaLayer
var _background: SaLayer


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(Vector2i(128, 128))
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document
    _bottom = _doc.active_layer
    _bottom.name = "Bottom"
    _background = _layers()[0]
    _top = SaLayerOps.new(_doc).add()
    _top.name = "Top"
    _doc.set_active_layer(_bottom)
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.target_canvas = _canvas
    _docker.bind_registries(_registries.blend_modes, _registries.layer_types)
    _docker.list_keeper.listen()
    _docker.hide()
    _home = _docker.item_list as SaLayerList


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
    _home = null
    _doc = null


func test_layer_list_and_actions_are_placeable_under_their_titles() -> void:
    assert_true(SaSettings.is_placeable(CATEGORY, "Layer List"), "Layer List has a view the Layers docker registered")
    assert_true(SaSettings.is_placeable(CATEGORY, "Actions"), "and so has Actions")
    var offered: Array = []
    for home: Dictionary in SaSettings.placeable_elements():
        if home["id"] == CATEGORY:
            assert_eq(home["title"], "Layers", "the two are listed under the Layers docker's title")
            for element: Dictionary in home["elements"]:
                offered.append("%s as %s" % [element["id"], element["title"]])
    assert_true(offered.has("Layer List as Layer List"), "Layer List under the title its Elements… page shows")
    assert_true(offered.has("Actions as Actions"), "and Actions under its own")


## The first case, its first half: a layer added through the
## document is read as a row of the view, with the docker closed.
func test_the_list_view_shows_a_layer_added_through_the_document() -> void:
    assert_false(_docker.visible, "the Layers docker is closed")
    var view := _list_view()
    assert_not_null(view, "the door builds a view of Layer List")
    assert_false(view.list == _home, "a list of its own, not the docker's")
    var stack: Array[SaLayer] = [_top, _bottom, _background]
    assert_eq(_rows(view.list), stack, "it shows the document's stack, the top first, filled by its own keeper")
    assert_eq(_lit(view.list), [_bottom], "and lights the active layer")

    var added := SaLayerOps.new(_doc).add()
    added.name = "Added"
    assert_true(_rows(view.list).has(added), "a layer added through the document has a row in the view")
    assert_eq(_rows(view.list), _rows(_home), "the rows the closed docker's list draws, in its order")
    assert_eq(_lit(view.list), [added], "the added layer is active, and lit in the view")
    assert_true(view.custom_minimum_size.y > 0.0, "the view stands as tall as its rows, where a scroll alone stands at none")


## Its second half: a row pressed in the view, read active in the document and
## in the docker's list.
func test_a_press_on_a_row_of_the_view_makes_its_layer_active() -> void:
    var view := _list_view()
    _press(view.list, _top)
    assert_eq(_doc.active_layer, _top, "a press on the view's row makes its layer active")
    assert_eq(_lit(_home), [_top], "and the closed docker's list lights it alone")
    _press(_home, _bottom)
    assert_eq(_lit(view.list), [_bottom], "a press in the docker's list is lit in the view")


## The second case: the view's add button adds a layer above the
## active one, read in both lists.
func test_the_actions_view_adds_a_layer_above_the_active_one_in_both_lists() -> void:
    var view := _list_view()
    var strip := _strip_view()
    assert_not_null(strip, "the door builds a view of Actions")
    assert_false(strip == _docker.actions, "a strip of its own, not the docker's")
    assert_eq(strip.layer_types, _registries.layer_types, "offering the kinds the docker's strip offers")
    assert_eq(strip.list, _home, "and reading the pick of the docker's own list, which the view's shares")

    strip.add_btn.pressed.emit()
    var added := _doc.active_layer
    assert_false(added == _bottom, "the add button made a new layer active")
    assert_eq(_layers().find(added), _layers().find(_bottom) + 1, "the new layer stands right above the one that was active")
    var drawn: Array[SaLayer] = [_top, added, _bottom, _background]
    assert_eq(_rows(view.list), drawn, "the placed list draws it above that layer")
    assert_eq(_rows(_home), drawn, "and so does the closed docker's")
    assert_eq(_lit(view.list), [added], "lit in the placed list")
    assert_eq(_lit(_home), [added], "and in the docker's")

    _doc.undo_redo.undo()
    var before: Array[SaLayer] = [_top, _bottom, _background]
    assert_eq(_rows(view.list), before, "an undo takes it out of the placed list")
    assert_eq(_rows(_home), before, "and out of the docker's")


## The strip acts on the pick: two rows picked in the placed list are taken
## off by the placed strip's minus, one step.
func test_the_actions_view_acts_on_the_rows_picked_in_any_list() -> void:
    var view := _list_view()
    var strip := _strip_view()
    var middle := SaLayerOps.new(_doc).add()
    _press(view.list, _top)
    _press(view.list, middle, true)
    assert_eq(_lit(_home), [_top, middle], "a Ctrl press in the placed list picks two rows in the docker's too")
    strip.del_btn.pressed.emit()
    var left: Array[SaLayer] = [_bottom, _background]
    assert_eq(_rows(view.list), left, "the placed minus took both picked layers off")
    assert_eq(_rows(_home), left, "and the docker's list lost the same two")
    _doc.undo_redo.undo()
    assert_eq(_rows(view.list).size(), 4, "one undo brings both back")


## The strip's buttons follow the active layer as the docker's do: Ground is
## live on the ground and dimmed elsewhere.
func test_the_actions_view_lights_ground_on_the_ground() -> void:
    var strip := _strip_view()
    assert_true(strip.ground_btn.disabled, "Ground is dimmed on a paint layer")
    var ground := SaLayerOps.new(_doc).add(&"canvas", _registries.layer_types)
    _doc.set_active_layer(ground)
    assert_false(strip.ground_btn.disabled, "and live once the ground is made active, with no press in any list")
    assert_false(_docker.actions.ground_btn.disabled, "as the closed docker's Ground is")


## Rename and Ground on a placed strip are the docker's to answer, so there is
## one rename window and one ground panel, the panel under the strip pressed.
func test_rename_and_ground_on_the_actions_view_reach_the_docker() -> void:
    var strip := _strip_view()
    var heard: Array = []
    _docker.actions.rename_requested.connect(func() -> void: heard.append("rename"))
    _docker.actions.ground_pressed.connect(func(pressed: SaLayerActions) -> void: heard.append(pressed))
    strip.press_item(SaLayerActions.Item.RENAME)
    strip.ground_btn.pressed.emit()
    assert_eq(heard, ["rename", strip], "the docker hears the rename, and Ground with the placed strip to open under")


## A view built before the docker has a canvas takes it when the docker does,
## which is the boot's order when a composed docker is in the layout.
func test_views_built_before_the_canvas_take_it_when_the_docker_does() -> void:
    _docker.free()
    _docker = LayersDocker.new()
    _docker.list_keeper.listen()
    var view := _list_view()
    var strip := _strip_view()
    assert_eq(view.list.row_count(), 0, "with no canvas the view shows nothing")
    _docker.target_canvas = _canvas
    assert_eq(_rows(view.list), [_top, _bottom, _background], "handed the canvas, the docker's keeper hands it on")
    assert_eq(strip.target_canvas, _canvas, "to the placed strip too")
    _docker.bind_registries(_registries.blend_modes, _registries.layer_types)
    _doc.document_changed.emit()
    assert_eq(strip.layer_types, _registries.layer_types, "and the kinds bound after reach it on the next change")


## The door holds the docker weakly: a view built once it is gone shows nothing
## and acts on nothing.
func test_a_view_built_after_the_docker_is_gone_acts_on_nothing() -> void:
    _docker.free()
    _docker = null
    var view := _list_view()
    var strip := _strip_view()
    assert_not_null(view, "the door still builds a list")
    assert_eq(view.list.row_count(), 0, "which shows nothing")
    strip.add_btn.pressed.emit()
    assert_eq(_layers().size(), 3, "and a strip whose plus adds nothing")


func _list_view() -> SaLayerListViews.ListView:
    var built := SaSettings.build_element_view(CATEGORY, "Layer List")
    if built != null:
        _views.append(built)
    return built as SaLayerListViews.ListView


func _strip_view() -> SaLayerListViews.ActionsView:
    var built := SaSettings.build_element_view(CATEGORY, "Actions")
    if built != null:
        _views.append(built)
    return built as SaLayerListViews.ActionsView


## A left press on *layer*'s row of *list*, with Ctrl when *ctrl*, and its
## release, the way the pointer gives them.
func _press(list: SaLayerList, layer: SaLayer, ctrl: bool = false) -> void:
    list._on_row_gui_input(_button(true, ctrl), _row(list, layer))
    list._input(_button(false, ctrl))


func _button(pressed: bool, ctrl: bool) -> InputEventMouseButton:
    var ev := InputEventMouseButton.new()
    ev.button_index = MOUSE_BUTTON_LEFT
    ev.pressed = pressed
    ev.ctrl_pressed = ctrl
    ev.position = Vector2(10, 10)
    ev.global_position = Vector2(10, 10)
    return ev


func _row(list: SaLayerList, layer: SaLayer) -> int:
    for i: int in list.row_count():
        if list.layer_at(i) == layer:
            return i
    return -1


## The layers *list* draws, the top first.
func _rows(list: SaLayerList) -> Array[SaLayer]:
    var out: Array[SaLayer] = []
    for i: int in list.row_count():
        out.append(list.layer_at(i))
    return out


## The layers *list* has picked, the top first.
func _lit(list: SaLayerList) -> Array[SaLayer]:
    var out: Array[SaLayer] = []
    for i: int in list.picked.selected_indices():
        out.append(list.layer_at(i))
    return out


## The document's layers, the bottom first.
func _layers() -> Array[SaLayer]:
    var out: Array[SaLayer] = []
    for child in _doc.get_children():
        if child is SaLayer and child != _doc.stroke_layer:
            out.append(child)
    return out
