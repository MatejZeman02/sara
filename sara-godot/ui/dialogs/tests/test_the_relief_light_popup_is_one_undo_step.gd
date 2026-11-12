## View > Relief Light... moves the open document's own light
## from a small window, and the move is one undo step.
##
## The light is the document's, `SaReliefLight`, and the saving half is
## `core/sad-file/tests/test_the_relief_s_light_and_strength_are_saved_with_the_document.gd`.
## The window stands in a real root with embedding forced, the way the Local Server
## suite puts its dialog there, and `MainDialogs` hears the request. The row's
## press emits it deferred, as the exposure row does, and a test that awaits
## drops every assertion after the await, so the suite emits what the
## frame would carry itself. The running app's proof is
## `scenarios/the-relief-s-light-and-strength-are-saved-with-the-document.json`.
@tool
extends "res://tests/test_framework.gd"

## Real windows go in the tree, and the document's easel needs a RenderingDevice.
const REQUIRES_GPU := true

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _bar: TopMenuBar = null
var _menu: SaViewMenu = null
var _popup: SaChoicePopup = null
var _canvas: SaCanvas = null
var _host: Node = null
var _dialogs: MainDialogs = null
var _was_embedding: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _surface = SaTestFixtures.make_surface()
    _registries = SaTestFixtures.make_registries(_surface)
    _bar = TopMenuBar.new()
    _bar._ready()
    _menu = _bar.menu("View")
    _menu.view_transforms = _registries.view_transforms
    _popup = _bar.menus["View"]
    _canvas = SaCanvas.new()
    _canvas.easel = _surface.easel
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    _host = Node.new()
    _host.name = "U41Host"
    EventBus.add_child(_host)
    _dialogs = MainDialogs.new(_registries, func() -> SaCanvas: return _canvas)
    _host.add_child(_dialogs)
    _dialogs.connect_event_bus()


func after_each() -> void:
    _host.free()
    _host = null
    _dialogs = null
    _canvas.free()
    _canvas = null
    _bar.free()
    _bar = null
    _menu = null
    _popup = null
    _surface.easel.free()
    _surface = null
    _registries = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding


func _row(label: String) -> StringName:
    for list: SaChoicePopup in SaMenu.lists_of(_popup):
        for id: StringName in list.row_ids():
            var button := list.label_button(id)
            if button != null and button.text == label:
                return id
    return &""


## The window, as View > Relief Light... opens it: the row pressed, and the
## request its deferred emit carries at the end of the frame.
func _open() -> SaReliefLightDialog:
    _menu.on_id_pressed(SaViewMenu.ID_RELIEF_LIGHT)
    EventBus.relief_light_requested.emit()
    return _dialogs.find_child("ReliefLightDialog", true, false) as SaReliefLightDialog


## What a hand's drag or typed number does to a slider: the value and its signal.
static func _move(slider: FactorSlider, value: float) -> void:
    slider.value = value
    slider.value_changed.emit(value)


func _steps() -> int:
    return _surface.easel.document.undo_redo.get_history_count()


func test_the_view_menu_has_the_row() -> void:
    var row := _row("Relief Light...")
    assert_false(row.is_empty(), "The View menu has a Relief Light... row")
    if row.is_empty():
        return
    var list := SaMenu.list_holding(_popup, row)
    assert_false(list.is_disabled(row), "and it is live")
    assert_true(list.label_button(row).tooltip_text.contains("Saved with the document"), "and says the light is the document's")


## The case: the light changed from the View menu's popup, undone,
## reads as it was.
func test_a_move_in_the_popup_is_one_step_that_one_undo_takes_back() -> void:
    var doc := _surface.easel.document
    var light := doc.relief_light
    light.angle = 315.0
    light.strength = 2.0
    doc.mark_saved("")
    var steps := _steps()
    var dialog := _open()
    assert_not_null(dialog, "The row opens the Relief Light window")
    if dialog == null:
        return
    assert_true(dialog.visible, "and it is up")
    assert_almost_eq(dialog.angle_slider.value, 315.0, 1e-6, "showing the document's light")
    assert_almost_eq(dialog.strength_slider.value, 2.0, 1e-6, "and its strength")

    _move(dialog.angle_slider, 60.0)
    _move(dialog.angle_slider, 90.0)
    _move(dialog.strength_slider, 3.0)
    _move(dialog.strength_slider, 5.0)
    assert_almost_eq(light.angle, 90.0, 1e-6, "The sliders move the light as they travel")
    assert_almost_eq(light.strength, 5.0, 1e-6, "strength and all")
    assert_eq(_steps(), steps, "and nothing is recorded while the window is up")

    (dialog.find_child("CloseButton", true, false) as Button).pressed.emit()
    assert_false(dialog.visible, "Close puts the window away")
    assert_eq(_steps(), steps + 1, "and the four moves are one step")
    assert_eq(doc.undo_redo.get_current_action_name(), "Relief Light", "called Relief Light")
    assert_true(doc.modified, "which the document has not saved")

    assert_true(doc.undo(), "One undo")
    assert_almost_eq(light.angle, 315.0, 1e-6, "puts the light back where it stood")
    assert_almost_eq(light.strength, 2.0, 1e-6, "at the strength it had")
    assert_false(doc.modified, "and the document is as it was saved")
    assert_true(doc.redo(), "A redo")
    assert_almost_eq(light.angle, 90.0, 1e-6, "moves it again")
    assert_almost_eq(light.strength, 5.0, 1e-6, "strength and all")


func test_the_title_bar_close_records_too_and_an_unmoved_light_records_nothing() -> void:
    var doc := _surface.easel.document
    var steps := _steps()
    var dialog := _open()
    assert_not_null(dialog, "The row opens the window")
    if dialog == null:
        return
    dialog.close_requested.emit()
    assert_false(dialog.visible, "The × puts the window away")
    assert_eq(_steps(), steps, "and a light nobody moved is no step")

    dialog = _open()
    _move(dialog.angle_slider, 180.0)
    dialog.close_requested.emit()
    assert_eq(_steps(), steps + 1, "A moved one is a step, however the window closed")
    assert_true(doc.undo(), "and one undo")
    assert_almost_eq(doc.relief_light.angle, SaSettings.relief_light_angle, 1e-6, "takes it back")


## Opened again while it is up, the window records what it held before it
## starts over, so a move made before the second open is not lost to undo.
func test_a_second_open_keeps_the_first_move() -> void:
    var doc := _surface.easel.document
    var was := doc.relief_light.angle
    var steps := _steps()
    var dialog := _open()
    assert_not_null(dialog, "The row opens the window")
    if dialog == null:
        return
    _move(dialog.angle_slider, fposmod(was + 90.0, 360.0))
    dialog = _open()
    assert_eq(_steps(), steps + 1, "The first move is a step of its own")
    dialog.hide()
    assert_eq(_steps(), steps + 1, "and the second open, unmoved, adds none")
    assert_true(doc.undo(), "One undo")
    assert_almost_eq(doc.relief_light.angle, was, 1e-6, "puts it back")
