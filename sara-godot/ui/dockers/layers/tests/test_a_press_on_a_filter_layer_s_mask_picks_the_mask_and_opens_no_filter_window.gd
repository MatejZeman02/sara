## A press on a filter layer's mask picks the mask and opens no filter window.
##
## Clicking the mask pinned to a filter layer does not open the filter window,
## because the painter clicked on it to edit the mask, not the filter.
##
## No single press opens the window, the
## layer's own filter being a double click on its picture. The presses
## are delivered to the row the way a hand's are, with its pictures laid out as
## the box would, and the window is the filter editor under a host as the
## attached filters suite holds one. The running app's half is the scenario of the same name.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const OWNER := &"sara-base-modules"
const CURVES_VALUES := {"curves": {"master": [[0.0, 0.0], [0.375, 0.75], [1.0, 1.0]]}}
## Where the layer's picture and the mask's are laid along the row.
const PICTURE_X := 30.0
const MASK_X := 70.0
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
    _host.name = "MaskPressHost"
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


## A Curves adjustment layer with a mask, listed.
func _curves_with_mask() -> SaLayer:
    var layer := SaFilterConversion.new(_doc).add_holding(_curves, CURVES_VALUES, _registries.layer_types, "Curves")
    assert_true(layer != null and layer.is_adjustment(), "A Curves adjustment layer is added")
    assert_true(layer.mask != null, "and given a mask, which every new filter layer carries")
    _docker.sync_layer_list()
    return layer


## The row *layer* is drawn on, or -1.
func _row_of(layer: SaLayer) -> int:
    for i: int in _docker.item_list.row_count():
        if _docker.item_list.layer_at(i) == layer:
            return i
    return -1


## Presses *layer*'s row at *x* along it, its pictures laid out as the box
## would lay them, which a list never shown has not done.
func _press(layer: SaLayer, x: float) -> void:
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
    press.position = Vector2(x + 4.0, 11.0)
    press.global_position = press.position
    row.gui_input.emit(press)


func test_a_press_on_the_mask_picks_it_and_opens_no_window() -> void:
    var layer := _curves_with_mask()
    assert_false(_window.visible, "No window is open before the press")
    _press(layer, MASK_X)
    assert_false(_window.visible, "A press on the Curves layer's mask opens no filter window")
    assert_eq(_doc.mask_target, layer.mask, "and the mask is what the brush paints")
    assert_eq(_doc.active_layer, layer, "on the layer it is pinned to")
    _press(layer, PICTURE_X)
    assert_false(_window.visible, "A press on the same row's picture opens no window either,")
    assert_eq(_doc.mask_target, null, "and the brush leaves the mask")


func test_a_press_on_the_name_opens_no_window_with_the_mask_picked() -> void:
    var layer := _curves_with_mask()
    _press(layer, MASK_X)
    assert_false(_window.visible, "The mask is picked and no window opens")
    _press(layer, 200.0)
    assert_false(_window.visible, "A press on the row's name opens no window,")
    assert_eq(_doc.active_layer, layer, "and the layer stays the active one")
