## A filter's option set by its name moves the slider of the dialog that is
## open, and once the dialog is closed the name says it cannot be moved.
##
## Built as the closing suite of the filter window builds it: Threshold
## registered as the base module registers it, the window watching that
## registry and a canvas under it, so the dialog is the one a painter opens.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

## The easel and the preview pass need a RenderingDevice.
const REQUIRES_GPU := true

const LEVEL := &"filter/sara-base-modules.threshold/level"

var _easel: SaEasel = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
var _host: Node = null
var _registry: SaFilterRegistry = null
var _was_embedding: bool = false
var _values: SaAppDrive = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _was_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "MidiFilterHost"
    EventBus.add_child(_host)
    _easel = Bench.easel(Vector2i(256, 256))
    _easel.document.fill_layer(Color(0.25, 0.5, 0.75, 1.0), _easel.document.active_layer)
    Bench.composite(_easel)
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _registry = SaFilterRegistry.new()
    _registry.register(Bench.threshold(), &"sara-base-modules")
    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.watch(_registry)
    _host.add_child(_window)
    _values = SaAppDrive.new(Callable())


func after_each() -> void:
    _values = null
    Teardown.free_nodes([_window, _canvas, _easel])
    _window = null
    _canvas = null
    _easel = null
    _registry = null
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _was_embedding


func _level_slider() -> FactorSlider:
    var row := _window.dialog.row(&"level") if _window.dialog != null else null
    return row.custom_control as FactorSlider if row != null else null


## The ask: the dialog open, the option set by its name, the dialog's slider at
## the value, then the dialog closed and the option out of reach.
func test_the_option_moves_while_its_dialog_is_open_and_not_after() -> void:
    assert_false(_values.can_move(LEVEL), "With no dialog open the level cannot be moved")

    _window.open_filter(&"sara-base-modules.threshold")
    var slider := _level_slider()
    assert_not_null(slider, "Threshold's dialog has a level slider")
    assert_eq(slider.value_name, LEVEL, "The dialog's slider names the filter's level")
    assert_true(_values.can_move(LEVEL), "With the dialog open the level can be moved")

    assert_true(_values.write(LEVEL, 0.8), "The level is written by its name")
    assert_almost_eq(slider.value, 0.8, 1e-6, "The dialog's slider stands at the value set")
    assert_almost_eq(_values.read(LEVEL), 0.8, 1e-6, "The resolver reads it back by its name")
    var store := _window.dialog.row(&"level").target as SaFilter.Store
    assert_almost_eq(float(store.read(&"level")), 0.8, 1e-6, "The dialog's store holds it, as after a drag")

    assert_true(_values.write_ratio(LEVEL, 0.25), "The level is set a quarter of the way")
    assert_almost_eq(slider.value, lerpf(slider.drag_min(), slider.drag_max(), 0.25), 1e-6, "A quarter of the slider's drag")

    _window.close_button.pressed.emit()
    assert_false(_window.visible, "The window closed")
    assert_false(_values.can_move(LEVEL), "With the dialog closed the level cannot be moved now")
    assert_false(_values.write(LEVEL, 0.3), "and a write moves nothing")
    assert_true(is_nan(_values.read(LEVEL)), "and a read finds nothing")


## The next dialog of the same filter answers the same name, which is what a
## binding made on the first one keeps.
func test_the_name_finds_the_next_dialog_of_the_filter() -> void:
    _window.open_filter(&"sara-base-modules.threshold")
    _window.close_button.pressed.emit()
    _window.open_filter(&"sara-base-modules.threshold")
    var slider := _level_slider()
    assert_not_null(slider, "The dialog opened again")
    assert_true(_values.write(LEVEL, 0.6), "The name moves the new dialog")
    assert_almost_eq(slider.value, 0.6, 1e-6, "Its slider stands at the value set")


## A dialog built without the registry's key, as the Filters docker's panel
## and the edit window of an attached filter build theirs, names nothing, so
## the option is moved only through the filter's own dialog.
func test_a_dialog_built_without_the_filters_key_names_nothing() -> void:
    var filter := Bench.threshold()
    var dialog := SaDialog.for_filter(filter)
    var host := VBoxContainer.new()
    dialog.realize(host)
    var slider := dialog.row(&"level").custom_control as FactorSlider
    assert_not_null(slider, "The dialog has a level slider")
    assert_eq(slider.value_name, &"", "A slider of a dialog given no key answers empty")
    host.free()
