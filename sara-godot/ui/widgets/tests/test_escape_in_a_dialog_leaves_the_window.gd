## Escape during a slider's drag in a dialog puts the value back and leaves the
## window open.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A dialog hears Escape first: the window emits `window_input`, which the
## router watches, before it pushes the key into its own tree, and the router
## closed the window as its × does. A painter who dragged a filter's slider and
## pressed Escape to put the value back would have lost the dialog. The router
## asks the sliders first now, so the first Escape is the drag's and the second
## is the window's, as it is for a number typed into a slider's field. The
## plain half is `test_a_right_press_or_escape_during_a_drag_puts_the_value_back.gd`.
extends "res://tests/test_framework.gd"

## Opens real windows, and only a run with a RenderingDevice has one.
const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

var _host: Node = null
var _router: ShortcutRouter = null
var _was_embedding: bool = false


## A host in the tree with a router watching every window that joins it, and
## embedding forced the way the other dialog suites force it, so `add_child`
## maps no real OS window.
func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "EscapeInADialogHost"
    EventBus.add_child(_host)
    _router = ShortcutRouter.new()
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return null
    _host.add_child(_router)
    _router.watch_windows(tree)


func after_each() -> void:
    _host.free()
    _host = null
    _router = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding


static func _escape() -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_ESCAPE
    key.physical_keycode = KEY_ESCAPE
    key.pressed = true
    return key


## A key the way the engine hands it to *window*: `window_input` first, which
## is where the router hears it, and then the window's own tree.
static func _press(window: Window, event: InputEvent) -> void:
    window.window_input.emit(event)
    window.push_input(event)


func test_the_first_escape_puts_a_dragged_value_back_and_the_second_closes() -> void:
    var easel := Bench.easel(Vector2i(128, 128))
    var canvas := SaCanvas.new()
    canvas.easel = easel
    var registry := SaFilterRegistry.new()
    registry.register(Bench.threshold(), &"sara-base-modules")
    var window := SaFilterDialogWindow.new()
    window.target_canvas = canvas
    window.watch(registry)
    _host.add_child(window)
    window.open_filter(&"sara-base-modules.threshold")
    var slider := window.dialog.row(&"level").custom_control as FactorSlider
    slider.size = Vector2(200.0, 18.0)
    var was := slider.value

    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = Vector2(slider.size.x * (0.2 if slider.ratio_of_value(was, slider.drag_max()) > 0.5 else 0.8), 9.0)
    slider._gui_input(press)
    assert_true(absf(slider.value - was) > 0.01, "The press moved the slider off %s" % was)

    _press(window, _escape())
    assert_almost_eq(slider.value, was, 1e-6, "The first Escape puts the value back")
    assert_true(window.visible, "and the window stays open")

    _press(window, _escape())
    assert_false(window.visible, "The second Escape closes it")

    window.free()
    canvas.free()
    easel.free()
