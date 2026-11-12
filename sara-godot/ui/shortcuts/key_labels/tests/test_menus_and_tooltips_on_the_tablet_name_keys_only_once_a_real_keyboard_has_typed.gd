## Android's configuration can report a keyboard a tablet does not have, so on
## Android the menus and tooltips name keys only once a key from a physical
## keyboard has reached Sara, and a volume key or a pen's button is no keyboard.
##
## The platform is taken as Android through `os_name_override` alone, and the
## headless display server answers `has_hardware_keyboard()` with true, which
## is the configuration the tablet gives. The Edit menu and the erase toggle's
## tooltip are read as the suite for a tablet with no keyboard reads them.
extends "res://tests/test_framework.gd"

const STAMP_MODULE := "res://modules/sara-base-modules/stamp-brush/module.gd"


func before_each() -> void:
    SaKeyLabels.keyboard_typed = false


func after_each() -> void:
    SaKeyLabels.os_name_override = ""
    SaKeyLabels.keyboard_override = -1
    SaKeyLabels.keyboard_typed = false
    var root := (Engine.get_main_loop() as SceneTree).root
    if root.window_input.is_connected(SaKeyLabels.hear):
        root.window_input.disconnect(SaKeyLabels.hear)


func test_the_configuration_reports_a_keyboard_here() -> void:
    assert_true(DisplayServer.has_hardware_keyboard(), "the suite's configuration reports a keyboard, as the tablet's does")


func test_a_tablet_names_no_key_until_a_letter_is_typed() -> void:
    SaKeyLabels.os_name_override = "Android"
    assert_false(SaKeyLabels.shown(), "a keyboard the configuration reports is not taken on its word")
    _assert_hidden("before any key")
    _type(KEY_A)
    assert_true(SaKeyLabels.shown(), "a typed letter is a keyboard")
    _assert_shown("after a typed letter")


func test_a_volume_key_or_a_pen_button_proves_no_keyboard() -> void:
    SaKeyLabels.os_name_override = "Android"
    for code: Key in [KEY_VOLUMEUP, KEY_VOLUMEDOWN, KEY_UNKNOWN, KEY_BACK]:
        _type(code)
    _assert_hidden("after the volume keys, a pen's button and the back key")


func test_a_letter_let_go_or_repeated_is_not_a_press() -> void:
    SaKeyLabels.os_name_override = "Android"
    var up := InputEventKey.new()
    up.keycode = KEY_A
    SaKeyLabels.hear(up)
    assert_false(SaKeyLabels.shown(), "a release alone proves nothing")


func test_the_root_window_s_keys_reach_the_labels() -> void:
    SaKeyLabels.os_name_override = "Android"
    var tree := Engine.get_main_loop() as SceneTree
    SaKeyLabels.listen(tree)
    SaKeyLabels.listen(tree)
    assert_eq(
        (
            tree
            . root
            . window_input
            . get_connections()
            . filter(func(c: Dictionary) -> bool: return c["callable"] == Callable(SaKeyLabels.hear))
            . size()
        ),
        1,
        "listened to once however often asked"
    )
    tree.root.window_input.emit(_press(KEY_Z, true))
    assert_true(SaKeyLabels.shown(), "Ctrl+Z on the root window is a keyboard")

    tree.root.window_input.disconnect(SaKeyLabels.hear)


func test_asking_on_a_tablet_starts_the_listening() -> void:
    SaKeyLabels.os_name_override = "Android"
    var tree := Engine.get_main_loop() as SceneTree
    if tree.root.window_input.is_connected(SaKeyLabels.hear):
        tree.root.window_input.disconnect(SaKeyLabels.hear)
    assert_false(SaKeyLabels.shown(), "and no key has typed yet")
    assert_true(tree.root.window_input.is_connected(SaKeyLabels.hear), "the first question on a tablet listens to the root")
    tree.root.window_input.disconnect(SaKeyLabels.hear)


func test_the_no_keyboard_override_holds_after_a_key() -> void:
    SaKeyLabels.os_name_override = "Android"
    SaKeyLabels.keyboard_override = 0
    _type(KEY_A)
    assert_false(SaKeyLabels.shown(), "the suite's override still wins")


func test_the_desktop_names_its_keys_before_any_key() -> void:
    SaKeyLabels.os_name_override = "Linux"
    assert_true(SaKeyLabels.shown(), "a desktop names its keys with no key typed")
    _assert_shown("on the desktop")


func _type(code: Key) -> void:
    SaKeyLabels.hear(_press(code, false))


func _press(code: Key, ctrl: bool) -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = code
    key.physical_keycode = code
    key.ctrl_pressed = ctrl
    key.pressed = true
    return key


func _assert_hidden(when: String) -> void:
    var bar := _bound_bar()
    var hints := _hints(bar.menus["Edit"])
    assert_true(hints.size() > 5, "the Edit menu has its rows, %d of them" % hints.size())
    for row: String in hints:
        assert_eq(hints[row], "", "row %s draws no key %s" % [row, when])
    bar.free()
    var label := _shown_tooltip(_erase_tooltip())
    assert_eq(label.text, "Erase with the brush", "the tooltip names no key %s" % when)
    label.free()


func _assert_shown(when: String) -> void:
    var bar := _bound_bar()
    var hints := _hints(bar.menus["Edit"])
    assert_eq(hints.get(String(SaMenu.key(SaEditMenu.ID_UNDO)), ""), "Ctrl+Z", "Undo draws its chord %s" % when)
    bar.free()
    var label := _shown_tooltip(_erase_tooltip())
    assert_eq(label.text, "Erase with the brush (E)", "the tooltip names its key %s" % when)
    label.free()


func _erase_tooltip() -> String:
    var stamp: Script = load(STAMP_MODULE)
    for spec: SaOptionSpec in stamp.brush_options():
        if spec.key == &"eraser_toggled":
            return spec.tooltip
    return ""


## A label built as the engine builds a tooltip's, entering the tree.
func _shown_tooltip(text: String) -> Label:
    SaTooltip.install(Engine.get_main_loop() as SceneTree)
    var label := Label.new()
    label.theme_type_variation = &"TooltipLabel"
    label.text = text
    EventBus.add_child(label)
    return label


func _bound_bar() -> TopMenuBar:
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(SaTestFixtures.make_menu_registries().commands)
    return bar


func _hints(popup: SaChoicePopup) -> Dictionary:
    var out := {}
    for entry: Dictionary in popup.row_report():
        out[String(entry.get("id", ""))] = String(entry.get("hint", ""))
    return out
