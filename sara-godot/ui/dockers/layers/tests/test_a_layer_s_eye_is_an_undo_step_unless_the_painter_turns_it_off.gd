## A layer's eye is an undo step unless the painter turns it off.
##
## Hiding a layer is registered to undo. Preferences' `visibility_in_history` is on by default, so a press on
## an eye, a sweep across eyes and a group's eye are each one "Layer
## Visibility" step on a fresh settings folder. A profile an older build wrote
## holds the old default of off whether or not the painter touched it, because
## every load writes every key back, so the version-27 step of
## `SaSettingsMigrations` turns it on once, and an off saved since stays off.
## The running app's half is
## `scenarios/a-layer-s-eye-is-an-undo-step-unless-the-painter-turns-it-off.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

## The version a profile written the day before the step names.
const BEFORE_THE_STEP: int = 26

var _easel: SaEasel
var _doc: SaDocument
var _canvas: SaCanvas
var _layers: LayersDocker
var _a: SaLayer
var _b: SaLayer
var _c: SaLayer
## Whether the eye was an undo step when the test began.
var _eye_was: bool


## The setting as a fresh settings folder holds it, which is what every test
## here starts from.
func before_each() -> void:
    _eye_was = SaSettings.visibility_in_history
    var fresh := SaSettingsValues.new()
    SaSettings.visibility_in_history = fresh.visibility_in_history
    fresh.free()
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


func after_each() -> void:
    SaSettings.visibility_in_history = _eye_was
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


func test_a_fresh_settings_folder_keeps_the_eye_in_the_history() -> void:
    var fresh := SaSettingsValues.new()
    assert_true(fresh.visibility_in_history, "the setting is on by default")
    fresh.free()


func test_a_click_on_an_eye_is_one_step_and_an_undo_shows_the_layer_again() -> void:
    var steps := _doc.history.step_count()
    _list()._on_eye_pressed(_row_of(_b))
    assert_false(_b.visible, "the click hid the layer")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Layer Visibility", "named Layer Visibility")
    assert_true(_doc.undo(), "the step is undone")
    assert_true(_b.visible, "and the layer is shown again")


func test_a_sweep_across_three_eyes_is_one_step_and_one_undo_shows_all_three() -> void:
    var steps := _doc.history.step_count()
    _list()._arm_eye(_row_of(_c), Vector2.ZERO)
    for layer: SaLayer in [_c, _b, _a]:
        _list()._apply_eye(_row_of(layer))
    _list()._finish_eye()
    assert_false(_a.visible or _b.visible or _c.visible, "the sweep hid all three")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Layer Visibility", "named Layer Visibility")
    assert_true(_doc.undo(), "the step is undone")
    assert_true(_a.visible and _b.visible and _c.visible, "and one undo shows all three")


func test_a_group_s_eye_is_a_step_too() -> void:
    var group := SaLayerOps.new(_doc).group_layers([_a, _b])
    _layers.sync_layer_list()
    var steps := _doc.history.step_count()
    _list()._on_eye_pressed(_row_of(group))
    assert_false(group.visible, "the click hid the group")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_true(_doc.undo(), "the step is undone")
    assert_true(group.visible, "and the group is shown again")


func test_a_painter_who_turned_it_off_adds_no_step() -> void:
    SaSettings.visibility_in_history = false
    var steps := _doc.history.step_count()
    _list()._on_eye_pressed(_row_of(_b))
    assert_false(_b.visible, "the click hid the layer")
    assert_eq(_doc.history.step_count(), steps, "and the history is left alone")


func test_an_older_profile_holding_off_reads_on_once() -> void:
    var old := ConfigFile.new()
    old.set_value("files", "visibility_in_history", false)
    old.set_value("meta", "version", BEFORE_THE_STEP)
    SaSettingsMigrations.apply(old, BEFORE_THE_STEP)
    assert_true(old.get_value("files", "visibility_in_history"), "the old default reads the new one")
    assert_eq(old.get_value("meta", "version"), SaSettingsMigrations.SETTINGS_VERSION, "and is stamped with this build")


func test_an_off_saved_by_this_build_stays_off() -> void:
    var chosen := ConfigFile.new()
    chosen.set_value("files", "visibility_in_history", false)
    chosen.set_value("meta", "version", SaSettingsMigrations.SETTINGS_VERSION)
    SaSettingsMigrations.apply(chosen, SaSettingsMigrations.SETTINGS_VERSION)
    assert_false(chosen.get_value("files", "visibility_in_history"), "a painter's off is kept")
