## The pen's arrow follows the pointer over every popup window, the colour
## picker of a gradient stop included.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The stop's colour popup is a window of its own with no
## cursor overlay, so the dialog's overlay stopped hearing the pen as it crossed
## into it and nothing drew the arrow there. `CursorOverlay.WindowWatch` is what
## Main holds to attach one to every window that comes in and takes the
## pointer. Each case holds a watch of its own and calls its `settle`, the call
## the frame's end makes, because a suite cannot reach a frame's end. The
## running app is the scenario of the same name.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

## The Gradient Map dialog runs its filter on open.
const REQUIRES_GPU := true

var _host: Node = null
var _watch: CursorOverlay.WindowWatch = null
var _easel: SaEasel = null
var _canvas: SaCanvas = null
var _dialog: SaFilterDialogWindow = null
var _registry: SaFilterRegistry = null
var _kept_embedding: bool = true
var _kept_mode: String = "auto"
var _kept_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    # A window of its own would map a real OS window and block the run.
    tree.root.gui_embed_subwindows = true
    _kept_mode = SaSettings.software_cursor
    SaSettings.software_cursor = "always"
    _kept_mouse_mode = Input.get_mouse_mode()
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "U172Host"
    EventBus.add_child(_host)
    _watch = CursorOverlay.WindowWatch.new()
    _host.add_child(_watch)


func after_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    SaPointerDevice.suite_pointer = null
    SaPatternCapture._close()
    if _dialog != null and is_instance_valid(_dialog):
        _dialog.free()
    _dialog = null
    Teardown.free_nodes([_canvas, _easel])
    _canvas = null
    _easel = null
    _registry = null
    if _host != null:
        _host.free()
        _host = null
    _watch = null
    SaSettings.software_cursor = _kept_mode
    Input.set_mouse_mode(_kept_mouse_mode)
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding


## The Gradient Map dialog open on a painted layer, the way Filter > Gradient
## Map opens it.
func _gradient_map_dialog() -> SaFilterDialogWindow:
    _easel = Bench.easel(Vector2i(256, 256))
    _easel.document.fill_layer(Color(0.4, 0.4, 0.4, 1.0), _easel.document.active_layer)
    Bench.composite(_easel)
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _registry = SaFilterRegistry.new()
    var filter := SaGradientMapFilter.new()
    _registry.register(filter, &"sara-base-modules")
    _dialog = SaFilterDialogWindow.new()
    _dialog.target_canvas = _canvas
    _dialog.watch(_registry)
    _host.add_child(_dialog)
    _dialog.open_filter(SaFilterRegistry.key_for(&"sara-base-modules", filter))
    return _dialog


func _ramp_control(dialog: Window) -> SaColorRampControl:
    for node in dialog.find_children("*", "", true, false):
        if node is SaColorRampControl:
            return node
    return null


## The stop's colour popup, opened by the swatch's own door.
func _stop_popup() -> PopupPanel:
    var control := _ramp_control(_gradient_map_dialog())
    assert_not_null(control, "The Gradient Map dialog holds the ramp's control")
    if control == null:
        return null
    assert_true(control.open_swatch(), "The swatch opens the stop's colour popup")
    _watch.settle()
    return control._popup


func _pen_at(window: Window, at: Vector2) -> void:
    var motion := InputEventMouseMotion.new()
    motion.tilt = Vector2(0.2, -0.1)
    motion.position = at
    SaCursorPolicy.note_pointer_device(motion, window)


## Plain motions enough to call the pointer a mouse again, with the suite's
## system pointer put at the same place on the desktop.
func _mouse_at(window: Window, at: Vector2) -> void:
    SaPointerDevice.suite_pointer = SaPointerDevice.desktop_transform(window) * at
    for i in SaCursorPolicy.MOUSE_MOTION_STREAK + 1:
        var motion := InputEventMouseMotion.new()
        motion.position = at
        SaCursorPolicy.note_pointer_device(motion, window)


func _inside(window: Window) -> Vector2:
    return window.get_visible_rect().size * 0.5


func _overlay_of(window: Window) -> CursorOverlay:
    return window.get_node_or_null("CursorOverlay") as CursorOverlay if window != null else null


func test_the_stop_s_popup_carries_an_overlay_of_its_own() -> void:
    var popup := _stop_popup()
    assert_true(popup != null and popup.visible, "The popup is up")
    assert_eq(String(popup.name), "StopColorPopup", "and it is the stop's colour popup")
    assert_true(popup.is_embedded(), "embedded in the root beside the dialog")
    assert_true(SaCursorPolicy.has_overlay(popup), "and it carries a cursor overlay, which it had none of before")


func test_a_pen_in_the_popup_has_its_arrow_drawn_there_and_none_in_the_dialog() -> void:
    var popup := _stop_popup()
    var at := _inside(popup)
    _pen_at(popup, at)
    var read := SaCursorPolicy.pointer_in_window(popup)
    assert_true(read.is_equal_approx(at), "The popup reads the pen where it is, %s" % read)
    assert_true(SaCursorPolicy.arrow_drawn_in(popup, read), "The popup's overlay draws the pen's arrow")
    assert_eq(SaCursorPolicy.drawn_at(popup, read), &"pointer", "at the pointer, as the drawn pointer")
    var overlay := _overlay_of(popup)
    assert_not_null(overlay, "The popup's overlay is a node in it")
    if overlay != null:
        assert_true(overlay.drawn_centre(read).is_equal_approx(read), "and it puts the arrow's tip on the pointer")
    var in_dialog := SaCursorPolicy.pointer_in_window(_dialog)
    assert_true(SaCursorPolicy.pointer_is_over_embedded_window(_dialog, in_dialog), "The dialog finds the popup over the pen")
    assert_false(SaCursorPolicy.arrow_drawn_in(_dialog, in_dialog), "and its overlay draws no arrow under the popup")
    SaCursorPolicy.sync_os_cursor_visibility()
    assert_eq(Input.get_mouse_mode(), Input.MOUSE_MODE_HIDDEN, "The system cursor is hidden for the arrow drawn in its place")


func test_a_mouse_in_the_popup_has_the_system_cursor() -> void:
    var popup := _stop_popup()
    var at := _inside(popup)
    _pen_at(popup, at)
    _mouse_at(popup, at)
    assert_false(SaCursorPolicy.pointer_is_tablet, "The popup heard the mouse, so the pen's word no longer stands")
    var read := SaCursorPolicy.pointer_in_window(popup)
    assert_eq(SaCursorPolicy.drawn_at(popup, read), &"system", "The popup shows the system cursor")
    SaCursorPolicy.sync_os_cursor_visibility()
    assert_eq(Input.get_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "which is visible")


func test_the_palette_s_chip_editor_carries_an_overlay() -> void:
    var panel := SaPalettePanel.new([Color.RED, Color.BLUE])
    _host.add_child(panel)
    _watch.settle()
    assert_true(SaCursorPolicy.has_overlay(panel._chip_editor), "The palette's chip editor carries a cursor overlay")


func test_a_floating_panel_s_frame_carries_an_overlay() -> void:
    # In a window embedded in the root, as a docker is, because a suite's root
    # is busy readying the runner and takes no child.
    var host := Window.new()
    host.name = "U172FloatingHost"
    host.size = Vector2i(400, 300)
    _host.add_child(host)
    var anchor := Button.new()
    anchor.text = "Anchor"
    host.add_child(anchor)
    var panel := SaFloatingPanel.new(Label.new(), "U172Floating")
    host.add_child(panel)
    panel.open_under(anchor)
    _watch.settle()
    assert_true(panel.in_frame(), "The panel opened in a frame, its window being embedded")
    assert_true(panel._frame != null and SaCursorPolicy.has_overlay(panel._frame), "and the frame carries a cursor overlay")


func test_the_pattern_capture_s_window_carries_an_overlay() -> void:
    SaPatternCapture._open(Engine.get_main_loop() as SceneTree, SaPatternChooser.DEFAULT_ICON, _host)
    _watch.settle()
    var window := SaPatternCapture._window
    assert_not_null(window, "The pattern capture opened its window")
    assert_true(window != null and SaCursorPolicy.has_overlay(window), "and it carries a cursor overlay")


## Built as `Viewport._gui_show_tooltip` builds the engine's tooltip, a popup
## the pointer passes through, since a suite cannot wait out the tooltip's
## delay.
func test_a_tooltip_carries_none() -> void:
    var tip := PopupPanel.new()
    tip.name = "U172Tooltip"
    tip.theme_type_variation = &"TooltipPanel"
    tip.transient = true
    tip.set_flag(Window.FLAG_NO_FOCUS, true)
    tip.set_flag(Window.FLAG_POPUP, false)
    tip.set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)
    var label := Label.new()
    label.text = "A tip"
    tip.add_child(label)
    _host.add_child(tip)
    _watch.settle()
    assert_false(CursorOverlay.takes_pointer(tip), "A tooltip takes no pointer")
    assert_false(SaCursorPolicy.has_overlay(tip), "so it is left without an overlay")


func test_the_watch_ends_with_its_holder() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var heard := tree.node_added.get_connections().size()
    _host.remove_child(_watch)
    assert_eq(tree.node_added.get_connections().size(), heard - 1, "The watch stops hearing the tree once it leaves it")
    _host.add_child(_watch)
