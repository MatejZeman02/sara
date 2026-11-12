## A single click on a filter layer picks it and opens nothing.
## A single click on the filter layer only selects the layer and does not open
## the filter settings right away.
##
## A press on a Curves adjustment layer's picture or name makes the layer the
## active one and leaves the filter editor shut. A double click on its picture
## opens the editor on the layer's own Curves, as a double click on a ground's
## picture opens its settings, and a double click on its name begins a rename.
## The presses are delivered to the row the way a hand's are, with its pictures
## laid out as the box would, and the window is the filter editor under a host as
## the mask press suite holds one. The running app's half is the scenario of the same
## name.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const OWNER := &"sara-base-modules"
const CURVES_VALUES := {"curves": {"master": [[0.0, 0.0], [0.375, 0.75], [1.0, 1.0]]}}
## Where the layer's picture and the mask's are laid along the row.
const PICTURE_X := 30.0
const MASK_X := 70.0
## Where the name is, clear of the pictures and the row's buttons.
const NAME_X := 200.0
const PICTURE_SIZE := Vector2(32.0, 22.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _registries: SaRegistries = null
var _registry: SaFilterRegistry = null
var _curves: StringName = &""
var _canvas: SaCanvas = null
var _docker: LayersDocker = null
var _window: SaFilterEditWindow = null
var _host: Node = null
var _was_embedding := false


## Embedding is forced as the attached filters suite forces it, or `add_child` maps a real
## OS window and the run blocks until the watchdog.
func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _easel = Bench.easel(Vector2i(256, 256))
    _doc = _easel.document
    _registries = Fixtures.make_registries()
    _registry = _easel.compositor.filter_chain.registry
    _registry.register(SaCurvesFilter.new(), OWNER)
    _curves = SaFilterRegistry.key_for(OWNER, SaCurvesFilter.new())
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.filter_registry = _registry
    _docker.target_canvas = _canvas
    _window = SaFilterEditWindow.new()
    _window.watch(_registry)
    _host = Node.new()
    _host.name = "SingleClickHost"
    EventBus.add_child(_host)
    _host.add_child(_window)
    _host.add_child(_docker)


func after_each() -> void:
    _host.free()
    _host = null
    _window = null
    _docker = null
    _canvas.free()
    _easel.free()
    _canvas = null
    _easel = null
    _doc = null
    _registries = null
    _registry = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding


## A Curves adjustment layer, listed, and the background made the active layer
## so a press on the Curves row has a pick to change.
func _curves_layer() -> SaLayer:
    var layer := SaFilterConversion.new(_doc).add_holding(_curves, CURVES_VALUES, _registries.layer_types, "Curves")
    assert_true(layer != null and layer.is_adjustment(), "A Curves adjustment layer is added")
    _docker.sync_layer_list()
    for i: int in _docker.item_list.row_count():
        var other: SaLayer = _docker.item_list.layer_at(i)
        if other != null and other != layer:
            _doc.set_active_layer(other)
            break
    _docker.sync_layer_list()
    assert_true(_doc.active_layer != layer, "Another layer is the active one before the press")
    return layer


## The row *layer* is drawn on, or -1.
func _row_of(layer: SaLayer) -> int:
    for i: int in _docker.item_list.row_count():
        if _docker.item_list.layer_at(i) == layer:
            return i
    return -1


## Presses *layer*'s row at *x* along it, its pictures laid out as the box
## would lay them, which a list never shown has not done. A *double* press is
## the second of a pair, and the plain one comes first as a hand's does.
func _press(layer: SaLayer, x: float, double: bool = false) -> void:
    if double:
        _press(layer, x)
    var row: SaRowFrame = _docker.item_list.rows[_row_of(layer)]
    row.hbox.position = Vector2.ZERO
    row.thumb.position = Vector2(PICTURE_X, 0.0)
    row.thumb.size = PICTURE_SIZE
    if row.mask_thumb != null:
        row.mask_thumb.position = Vector2(MASK_X, 0.0)
        row.mask_thumb.size = PICTURE_SIZE
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.double_click = double
    press.position = Vector2(x + 4.0, 11.0)
    press.global_position = press.position
    row.gui_input.emit(press)


func test_a_press_on_the_picture_picks_the_layer_and_opens_nothing() -> void:
    var layer := _curves_layer()
    _press(layer, PICTURE_X)
    assert_eq(_doc.active_layer, layer, "A press on the Curves layer's picture makes it the active layer")
    assert_false(_window.visible, "and opens no filter window")
    assert_eq(_docker.item_list.renaming_row(), -1, "nor a rename")


func test_a_press_on_the_name_picks_the_layer_and_opens_nothing() -> void:
    var layer := _curves_layer()
    _press(layer, NAME_X)
    assert_eq(_doc.active_layer, layer, "A press on the Curves layer's name makes it the active layer")
    assert_false(_window.visible, "and opens no filter window")


func test_a_double_click_on_the_picture_opens_the_layers_own_filter() -> void:
    var layer := _curves_layer()
    _press(layer, PICTURE_X, true)
    assert_true(_window.visible, "A double click on the Curves layer's picture opens the filter editor")
    assert_eq(_window.record, layer.filters[0], "on the layer's own Curves")
    assert_eq(_doc.active_layer, layer, "with the layer the active one")
    assert_eq(_docker.item_list.renaming_row(), -1, "and no rename begun")


func test_a_double_click_on_the_name_renames_and_opens_nothing() -> void:
    var layer := _curves_layer()
    _press(layer, NAME_X, true)
    assert_eq(_docker.item_list.renaming_row(), _row_of(layer), "A double click on the Curves layer's name begins its rename")
    assert_false(_window.visible, "and opens no filter window")
