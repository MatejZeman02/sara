## The layer list's driving moves out of the docker into a class
## beside the list.
##
## The layer list is a widget the Layers docker fills and answers, and nothing
## else should need to drive one. So a second
## `SaLayerList` is handed an `SaLayerListKeeper` on the docker's canvas and
## nothing else, and each list is read for what was done in the other. No call
## to the docker drives the second list once it is built.
##
## A docker is a `Window` and adding one to the tree in a headless test hangs,
## so nothing here enters the tree, as in `test_layer_multiselect.gd`, and the
## docker's keeper is told to listen, which the docker's `_ready` does in the
## app.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _easel: SaEasel
var _canvas: SaCanvas
var _doc: SaDocument
var _docker: LayersDocker
## The docker's own list, and the second one with its keeper.
var _home: SaLayerList
var _list: SaLayerList
var _keeper: SaLayerListKeeper
## The three layers made here, bottom first, the bottom one active, and the
## ground the default document holds under them, which no test moves.
var _bottom: SaLayer
var _middle: SaLayer
var _top: SaLayer
var _ground: SaLayer


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(128, 128))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _easel.document
    var ops := SaLayerOps.new(_doc)
    _bottom = _doc.active_layer
    _bottom.name = "Bottom"
    _ground = _layers()[0]
    _middle = ops.add()
    _middle.name = "Middle"
    _top = ops.add()
    _top.name = "Top"
    _doc.set_active_layer(_bottom)
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.target_canvas = _canvas
    _docker.list_keeper.listen()
    _home = _docker.item_list as SaLayerList
    _list = SaLayerList.new()
    _keeper = SaLayerListKeeper.new(_list, _canvas)
    _keeper.listen()


func after_each() -> void:
    _keeper = null
    _list.free()
    _docker.free()
    _canvas.free()
    _easel.free()
    _list = null
    _home = null
    _docker = null
    _doc = null


func test_the_second_list_shows_the_dockers_layers() -> void:
    var stack: Array[SaLayer] = [_top, _middle, _bottom, _ground]
    assert_true(_ground != _bottom, "the default document has its ground under the active layer")
    assert_eq(_rows(_home), stack, "the docker's list shows the stack, the top first")
    assert_eq(_rows(_list), stack, "and so does the second list, filled by its keeper alone")
    assert_eq(_lit(_home), [_bottom], "the docker's list lights the active layer")
    assert_eq(_lit(_list), [_bottom], "and so does the second")


## The first half of the case: a row pressed in the second list, read active in
## the docker's.
func test_a_press_in_the_second_list_makes_its_layer_active_in_the_dockers() -> void:
    _press(_list, _middle)
    assert_eq(_doc.active_layer, _middle, "a press on the second list's row makes its layer active")
    assert_eq(_home.layer_at(_home.picked.selected_idx), _middle, "the docker's list has it as its active row")
    assert_eq(_lit(_home), [_middle], "lit alone, as a plain press leaves it")
    assert_eq(_lit(_list), [_middle], "and the second list the same")


## The second half of the case: a row dragged in the second list, read in the
## document's order and in both lists.
func test_a_drag_in_the_second_list_reorders_the_document_and_both_lists() -> void:
    _list.begin_drag(_row(_list, _bottom))
    _list.drag_over(_row(_list, _top), SaLayerList.Drop.ABOVE)
    _list.drop()
    var order: Array[SaLayer] = [_ground, _middle, _top, _bottom]
    assert_eq(_layers(), order, "the bottom layer dropped above the top is the top of the document")
    var drawn: Array[SaLayer] = [_bottom, _top, _middle, _ground]
    assert_eq(_rows(_list), drawn, "the second list draws the new order")
    assert_eq(_rows(_home), drawn, "and the docker's list draws it too")

    _doc.undo_redo.undo()
    var before: Array[SaLayer] = [_top, _middle, _bottom, _ground]
    assert_eq(_rows(_home), before, "an undo puts the docker's list back")
    assert_eq(_rows(_list), before, "and the second list with it")


## The pick is shared: a Ctrl press in either list picks the same set in both.
func test_a_ctrl_press_in_either_list_picks_the_same_set_in_both() -> void:
    _press(_list, _top)
    _press(_list, _middle, true)
    assert_eq(_lit(_list), [_top, _middle], "a Ctrl press in the second list adds its row to the set")
    assert_eq(_lit(_home), [_top, _middle], "and the docker's list picks the same two")
    assert_eq(_doc.active_layer, _middle, "the row pressed last is active")

    _press(_home, _bottom, true)
    var all: Array[SaLayer] = [_top, _middle, _bottom]
    assert_eq(_lit(_home), all, "a Ctrl press in the docker's list adds its row")
    assert_eq(_lit(_list), all, "and the second list follows it")

    _press(_home, _top)
    assert_eq(_lit(_list), [_top], "a plain press in either takes both back to one row")


## The folds are shared: a group shut in the second list is shut in the
## docker's, and opened there it opens in both.
func test_a_group_folded_in_the_second_list_is_folded_in_the_dockers() -> void:
    var group := SaLayerOps.new(_doc).group_layers([_middle])
    assert_true(_rows(_list).has(_middle), "the group's member has a row in the second list")
    _list.group_toggled.emit(_row(_list, group))
    assert_false(_rows(_list).has(_middle), "the fold mark shuts the group in the second list")
    assert_false(_rows(_home).has(_middle), "and in the docker's")
    assert_true(_docker._closed_groups.has(group), "the docker's set of shut groups holds it")
    assert_eq(_rows(_home), _rows(_list), "the two lists draw the same rows")

    _home.group_toggled.emit(_row(_home, group))
    assert_true(_rows(_home).has(_middle), "the mark in the docker's list opens it")
    assert_true(_rows(_list).has(_middle), "and the second list opens with it")


## A list handed a keeper once the docker's list has a pick and a fold takes
## both, so it opens the way the other lists look.
func test_a_list_built_later_takes_the_pick_and_the_folds() -> void:
    var group := SaLayerOps.new(_doc).group_layers([_middle])
    _home.group_toggled.emit(_row(_home, group))
    _press(_home, _top)
    _press(_home, _bottom, true)
    var late := SaLayerList.new()
    var keeper := SaLayerListKeeper.new(late, _canvas)
    keeper.listen()
    assert_eq(_rows(late), _rows(_home), "the late list draws the rows the docker's does, the group shut")
    assert_eq(_lit(late), [_top, _bottom], "and picks the same two")
    keeper = null
    late.free()


## A keeper let go of lets go of its list, and the lists still kept go on.
func test_a_keeper_let_go_of_leaves_its_list_as_it_was() -> void:
    var late := SaLayerList.new()
    _fill_and_let_go(late)
    assert_eq(_rows(late), _rows(_home), "the keeper filled the list before it went")
    _press(_home, _top)
    assert_eq(_lit(_list), [_top], "the second list, still kept, follows a press in the docker's")
    assert_eq(_lit(late), [_bottom], "and the list whose keeper is gone stays on the row it had")
    late.free()


## A keeper with no canvas shows nothing and acts on nothing.
func test_a_keeper_with_no_canvas_shows_nothing() -> void:
    var bare := SaLayerList.new()
    var keeper := SaLayerListKeeper.new(bare)
    keeper.listen()
    assert_eq(bare.row_count(), 0, "no canvas, no rows")
    assert_eq(keeper.active_layer(), null, "and no active layer")
    keeper.target_canvas = _canvas
    assert_eq(_rows(bare), _rows(_home), "handed the canvas, it shows the stack")
    keeper = null
    bare.free()


## Hands *list* a keeper on the canvas and lets go of it on the return, which
## wait for the end of the suite.
## wait for the end of the suite.
func _fill_and_let_go(list: SaLayerList) -> void:
    var keeper := SaLayerListKeeper.new(list, _canvas)
    keeper.listen()


## A left press on *layer*'s row of *list*, with Ctrl when *ctrl*, and its
## release, the way the pointer gives them.
func _press(list: SaLayerList, layer: SaLayer, ctrl: bool = false) -> void:
    var down := _button(true, ctrl)
    list._on_row_gui_input(down, _row(list, layer))
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
