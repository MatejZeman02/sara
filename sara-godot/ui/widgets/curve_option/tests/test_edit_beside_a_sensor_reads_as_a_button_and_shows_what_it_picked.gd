## Edit beside a sensor is a framed button, and a press on it lights that
## sensor's row and names it above the curve.
##
## In the brush editor's sensor list the Edit text did not read as a button.
## Edit was flat, so it read as text,
## and nothing marked the picked row, so with a shared curve a press changed
## nothing a painter could see. Each press here is a real left button event
## handed to the root window, the way the display server hands one, so the
## press reaches Edit through the GUI's own hit test rather than a signal
## emitted by hand.
extends "res://tests/test_framework.gd"

var _host: Control = null
var _control: SaCurveOptionControl = null
var _option: SaCurveOption = null


func before_each() -> void:
    _option = SaCurveOption.create_default()
    _option.set_sensor(SaSensor.create(SaSensor.Id.TILT_X, true))
    _option.set_sensor(SaSensor.create(SaSensor.Id.TILT_Y, true))
    _control = SaCurveOptionControl.new()
    _control.bind_option(_option, "Size")
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    _host = Control.new()
    _host.name = "SensorListHost"
    _host.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _host.position = Vector2(20.0, 20.0)
    EventBus.add_child(_host)
    _host.add_child(_control)
    _control.size = Vector2(SaUI.px(420), SaUI.px(600))
    _lay_out()


func after_each() -> void:
    if _host != null:
        _host.free()
    _host = null
    _control = null


func test_edit_is_framed_at_rest_on_every_row() -> void:
    for row: Dictionary in _control.option_report()["sensors"]:
        assert_true(bool(row["edit_framed"]), "%s's Edit is drawn as a button" % row["key"])
    var edit := _list().edit_for("tilt_x")
    assert_false(edit.flat, "and is not flat")
    assert_true(edit.has_theme_stylebox("normal"), "so it takes the theme's own button frame")


func test_a_press_on_tilt_x_lights_its_row_and_names_it_with_its_own_curve() -> void:
    _control.set_use_same_curve(false)
    _press_edit("tilt_x")
    _assert_picked("tilt_x", "Tilt X")
    assert_false("shared" in String(_control.option_report()["heading"]), "and says nothing of a shared curve")


func test_a_press_on_tilt_x_lights_its_row_and_names_it_with_the_shared_curve() -> void:
    _control.set_use_same_curve(true)
    var curve_before: Array = _control.option_report()["shown_curve"]
    _press_edit("tilt_x")
    _assert_picked("tilt_x", "Tilt X")
    var report := _control.option_report()
    assert_true(
        String(report["heading"]).contains("shared by every ticked sensor"), "and says the curve is every ticked sensor's"
    )
    assert_eq(report["shown_curve"], curve_before, "while the shared curve itself stays as it was")


func test_a_second_press_moves_the_light_and_turning_sharing_off_keeps_it() -> void:
    _control.set_use_same_curve(true)
    _press_edit("tilt_y")
    _press_edit("tilt_x")
    _assert_picked("tilt_x", "Tilt X")
    _control.set_use_same_curve(false)
    _assert_picked("tilt_x", "Tilt X")
    assert_eq(String(_control.option_report()["heading"]), "Tilt X", "and the heading drops the shared sentence")


# --- Helpers --------------------------------------------------------------------


func _list() -> SaSensorList:
    return _control.find_child("SensorList", true, false) as SaSensorList


func _lay_out() -> void:
    _control.notification(Container.NOTIFICATION_SORT_CHILDREN)
    for container: Node in _control.find_children("*", "Container", true, false):
        (container as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)


## Presses and lets go of the left button over *key*'s Edit, in the root's
## own space, after scrolling the row into the list's view.
func _press_edit(key: String) -> void:
    var list := _list()
    var edit := list.edit_for(key)
    list.ensure_visible(key)
    list.scroll_vertical = int(edit.get_parent_control().position.y)
    _lay_out()
    var at := edit.get_global_rect().get_center()
    assert_true(list.get_global_rect().has_point(at), "%s's Edit is inside the list's view" % key)
    _send(at, true)
    _send(at, false)


func _send(at: Vector2, pressed: bool) -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    event.position = root.get_final_transform() * at
    event.global_position = event.position
    root.push_input(event)


func _assert_picked(key: String, title: String) -> void:
    var report := _control.option_report()
    assert_eq(String(report["selected"]), key, "%s is the picked sensor" % title)
    for row: Dictionary in report["sensors"]:
        if row["key"] == key:
            assert_true(bool(row["lit"]), "%s's row is lit" % title)
        else:
            assert_false(bool(row["lit"]), "%s's row is not lit" % row["label"])
    assert_true(String(report["heading"]).begins_with(title), "and the panel names %s above the curve" % title)
