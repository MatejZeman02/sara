## A layer's eye is kept out of the undo history unless Preferences asks for it.
##
## Five eye clicks would be five history rows, and Photoshop keeps them out
## unless asked. Off, the eye marks the document
## changed and commits no step, on, it is a step. On is the default,
## and its suite is
## `test_a_layer_s_eye_is_an_undo_step_unless_the_painter_turns_it_off.gd`.
## The running app's half, with the Undo History docker in the shot, is
## `scenarios/a-layer-s-eye-is-kept-out-of-the-undo-history-unless-preferences-asks-for-it.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

var _easel: SaEasel
var _doc: SaDocument
var _canvas: SaCanvas
var _layers: LayersDocker
var _a: SaLayer
var _b: SaLayer
var _c: SaLayer
var _was: bool


func before_each() -> void:
    _was = SaSettings.visibility_in_history
    SaSettings.visibility_in_history = false
    _easel = Bench.easel(Vector2i(128, 128))
    _doc = _easel.document
    _a = _doc.active_layer
    _b = SaLayerOps.new(_doc).add()
    _c = SaLayerOps.new(_doc).add()
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _layers = LayersDocker.new()
    _layers.target_canvas = _canvas
    _layers.list_keeper.listen()
    _layers.sync_layer_list()
    _doc.modified = false


func after_each() -> void:
    SaSettings.visibility_in_history = _was
    _layers.free()
    _canvas.free()
    _easel.free()
    _a = null
    _b = null
    _c = null


func _list() -> SaLayerList:
    return _layers.item_list


func _row_of(layer: SaLayer) -> int:
    for i in _list().rows.size():
        if _list().layer_at(i) == layer:
            return i
    return -1


func _pick(layer: SaLayer, ctrl: bool = false) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.ctrl_pressed = ctrl
    _list()._on_row_gui_input(event, _row_of(layer))


## Five toggles of one eye, each read in the layer's flag, and how many steps
## the history gained.
func _five_toggles(layer: SaLayer) -> int:
    var steps := _doc.history.step_count()
    var ops := SaLayerOps.new(_doc)
    for i in 5:
        ops.set_visible(layer, not layer.visible)
        assert_eq(layer.visible, i % 2 == 1, "toggle %d is in the layer's flag" % (i + 1))
    return _doc.history.step_count() - steps


func test_five_eye_toggles_with_the_setting_off_add_no_step() -> void:
    assert_eq(_five_toggles(_b), 0, "five toggles add no step")
    assert_true(_doc.modified, "and the document is marked changed")


func test_five_eye_toggles_with_the_setting_on_add_five_steps() -> void:
    SaSettings.visibility_in_history = true
    assert_eq(_five_toggles(_b), 5, "five toggles are five steps")
    assert_true(_doc.modified, "and the document is marked changed")


## The docker's eye on a picked set, the press that flips the whole set.
func test_the_eye_on_a_picked_set_with_the_setting_off_adds_no_step() -> void:
    _pick(_c)
    _pick(_a, true)
    var steps := _doc.history.step_count()
    _list()._on_eye_pressed(_row_of(_c))
    assert_false(_a.visible or _c.visible, "the eye hid both picked layers")
    assert_true(_b.visible, "and left the one not picked")
    assert_eq(_doc.history.step_count(), steps, "with no step")
    assert_true(_doc.modified, "and the document marked changed")


## The sweep, the eye dragged down the rows, writes through the same helper.
func test_an_eye_sweep_with_the_setting_off_adds_no_step() -> void:
    var steps := _doc.history.step_count()
    _list()._arm_eye(0, Vector2.ZERO)
    for i in _list().rows.size():
        _list()._apply_eye(i)
    _list()._finish_eye()
    assert_false(_a.visible or _b.visible or _c.visible, "the sweep hid every layer")
    assert_eq(_doc.history.step_count(), steps, "with no step")


## An undo walks past the eyes: a paint step undone leaves them as the
## painter set them after it.
func test_undoing_an_earlier_paint_step_leaves_the_eyes_alone() -> void:
    _doc.fill_layer(Color(0.8, 0.2, 0.1, 1.0), _b)
    var steps := _doc.history.step_count()
    _pick(_c)
    _pick(_a, true)
    _list()._on_eye_pressed(_row_of(_c))
    SaLayerOps.new(_doc).set_visible(_b, false)
    assert_eq(_doc.history.step_count(), steps, "the eyes added no step after the fill")

    assert_true(_doc.undo(), "the fill is undone")
    assert_false(_a.visible or _b.visible or _c.visible, "and every eye stays as the painter left it")
    assert_true(_doc.redo(), "the fill is redone")
    assert_false(_a.visible or _b.visible or _c.visible, "and the eyes still stand")
