## A window's maximise button does what Ctrl+Space does.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The same word on the title strip and on the keyboard gives one window: the
## whole of Sara's at `SaDockerMaximise.MAXIMISED_SCALE`.
##
## Each case puts a window through the chord first, through a real
## `ShortcutRouter` and a real key event with the window holding the keyboard,
## and keeps the rectangle and the scale it gave. Then it presses the window's
## own button and reads the same rectangle and the same scale, the host
## `SaDockerMaximise.host_rect` names, and a second press back at the rectangle
## the window left. Every window is embedded, because a Window added to the tree
## without it maps a real OS window and the run blocks until the watchdog.
@tool
extends "res://tests/test_framework.gd"

## Preferences and the Brush Editor need a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")


## A docker with a drag bar and the ready every shipped docker runs, which is
## where the bar's buttons are built.
class StubDocker:
    extends DockerWindow

    func _init() -> void:
        _init_docker("ProbeDocker", "Probe Docker", Vector2i(260, 220))
        var column := SaMake.column(_control_node, "VBoxContainer")
        column.set_anchors_preset(Control.PRESET_FULL_RECT)
        drag_handle = DockerUtils.make_drag_bar("Probe Docker")
        column.add_child(drag_handle)

    func _ready() -> void:
        _setup_docker_ready()


var _host: Node = null
var _router: ShortcutRouter = null
var _kept_embedding: bool = true
## What the profile held for the docker switch, null for nothing, put back after
## each test so the run leaves the painter's preference as it found it.
var _kept_switch: Variant = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var section := SaSettingsFile.module_section(SaDockerMaximise.MODULE_ID)
    var held := SaSettings.config.has_section_key(section, String(SaDockerMaximise.SWITCH_KEY))
    _kept_switch = SaSettings.module_preference(SaDockerMaximise.MODULE_ID, SaDockerMaximise.SWITCH_KEY) if held else null
    _host = Node.new()
    _host.name = "U781Host"
    EventBus.add_child(_host)
    _router = ShortcutRouter.new()
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return null
    _router.bind_commands(Fixtures.make_registries().commands)
    _host.add_child(_router)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    _router = null
    SaSettings.set_module_preference(SaDockerMaximise.MODULE_ID, SaDockerMaximise.SWITCH_KEY, _kept_switch)
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding


func _ctrl_space() -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = KEY_SPACE
    event.physical_keycode = KEY_SPACE
    event.ctrl_pressed = true
    event.pressed = true
    return event


## The chord's rectangle and scale for *window*, read with the window filled and
## then put back, so the button is pressed on the window as the painter left it.
func _what_the_chord_gives(window: Window, what: String) -> Array:
    var left := Rect2i(window.position, window.size)
    window.grab_focus()
    var tree := Engine.get_main_loop() as SceneTree
    assert_eq(SaDockerMaximise.focused_window(tree), window, "%s holds the keyboard" % what)
    assert_true(_router.handle(_ctrl_space()), "Ctrl+Space is taken over %s" % what)
    assert_true(SaDockerMaximise.is_maximised(window), "and fills Sara's window with %s" % what)
    var filled := Rect2i(window.position, window.size)
    var scale := window.content_scale_factor
    assert_true(_router.handle(_ctrl_space()), "the chord again over %s" % what)
    assert_eq(Rect2i(window.position, window.size), left, "puts %s back" % what)
    return [left, filled, scale]


## The whole of the unit for one window: the button gives the chord's rectangle
## and scale, which is Sara's window, and a second press gives the old one back.
func _the_button_does_what_the_chord_does(window: Window, button: Button, what: String) -> void:
    assert_not_null(button, "%s has a maximise button" % what)
    if button == null:
        return
    assert_true(button.visible, "and shows it")
    var chord := _what_the_chord_gives(window, what)
    var left: Rect2i = chord[0]
    var filled: Rect2i = chord[1]

    button.pressed.emit()
    assert_true(SaDockerMaximise.is_maximised(window), "the button maximises %s" % what)
    assert_eq(Rect2i(window.position, window.size), filled, "to the rectangle the chord gave %s" % what)
    assert_eq(filled, SaDockerMaximise.host_rect(window), "which is the whole of Sara's window")
    assert_almost_eq(window.content_scale_factor, float(chord[2]), 0.0001, "at the scale the chord gave it")
    assert_eq(button.tooltip_text.begins_with("Restore"), true, "and the button then offers the way back")

    button.pressed.emit()
    assert_false(SaDockerMaximise.is_maximised(window), "a second press puts %s back" % what)
    assert_eq(Rect2i(window.position, window.size), left, "at the rectangle %s left" % what)
    assert_eq(button.tooltip_text.begins_with("Maximize"), true, "and the button offers the maximise again")


func test_preferences_button_does_what_the_chord_does() -> void:
    var window := SaSettingsWindow.new()
    _host.add_child(window)
    window.show()
    _the_button_does_what_the_chord_does(window, window.frame.maximize_button, "Preferences")
    window.hide()


## The chord or the button on Preferences rolled up to its title strip gives the
## page back first, or the strip would be the rectangle a restore came back to.
func test_a_rolled_up_preferences_maximises_with_its_page() -> void:
    var window := SaSettingsWindow.new()
    _host.add_child(window)
    window.show()
    var left := Rect2i(window.position, window.size)
    window.frame.toggle_collapsed()
    window.frame.maximize_button.pressed.emit()
    assert_eq(window.frame.mode, SaSettingsFrame.Mode.NORMAL, "the roll-up ends")
    assert_true(window.content.visible, "with the page shown")
    assert_eq(Rect2i(window.position, window.size), SaDockerMaximise.host_rect(window), "and the window filled")
    window.frame.maximize_button.pressed.emit()
    assert_eq(Rect2i(window.position, window.size), left, "a second press gives the window the person had")
    window.hide()


func test_a_floating_dockers_button_does_what_the_chord_does() -> void:
    SaSettings.set_module_preference(SaDockerMaximise.MODULE_ID, SaDockerMaximise.SWITCH_KEY, true)
    var docker := StubDocker.new()
    _host.add_child(docker)
    docker.position = Vector2i(140, 120)
    docker.show()
    _the_button_does_what_the_chord_does(docker, docker.maximise_button, "a floating docker")


func test_the_brush_editors_button_does_what_the_chord_does() -> void:
    SaSettings.set_module_preference(SaDockerMaximise.MODULE_ID, SaDockerMaximise.SWITCH_KEY, false)
    var window := SaBrushEditorWindow.new()
    _host.add_child(window)
    window.show()
    _the_button_does_what_the_chord_does(window, window.maximise_button, "the Brush Editor")
    window.hide()


## A dialog that answers a question keeps its close alone and still takes the
## chord, which is how it was before the button.
func test_a_question_shows_no_maximise_and_still_takes_the_chord() -> void:
    var window := SaRadiusDialog.new()
    _host.add_child(window)
    window.show()
    assert_false(window.maximise_button.visible, "Radius shows no maximise")
    _what_the_chord_gives(window, "Radius")
    window.hide()
