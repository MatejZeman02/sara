## A filter's shortcut closes its own dialog as Escape does.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A filter's shortcut serves as a toggle: a painter who presses Ctrl+B,
## slides some changes and dislikes them can close the dialog with Escape or
## with Ctrl+B again. Colour Balance is on Ctrl+B,
## registered through the door the base module registers it through, so its
## command is the one a painter's chord runs and a rebind lands on.
##
## A key into the dialog goes in the way the engine hands it on, the window's
## `window_input`, which the router watches, and then `push_input` into its
## own tree, the shape `test_escape_closes_a_dialog.gd` sends Escape in. A key
## over the canvas is the main window's, which `Main._unhandled_input` hands
## to `handle_viewport_input` with the root as its viewport, and the press
## that opens the dialog again is one of those, since a shut dialog holds no
## keyboard. The dialog counts as on screen once its deferred cascade has
## run, which a suite has no frame for, so it is asked for by hand. The
## running app is
## `scenarios/a-filter-s-shortcut-closes-its-own-dialog-as-escape-does.json`.
extends "res://tests/test_framework.gd"

## Opens real windows and runs a preview, which need a RenderingDevice.
const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const OWNER := &"sara-base-modules"
const COMMAND := &"filter_color_balance"
## Hue/Saturation/Lightness's command, another filter's chord.
const OTHER_COMMAND := &"filter_hue_saturation_lightness"
## The midtones' cyan to red slider, moved so the preview differs from the
## layer.
const SLIDER := &"midtones_cr"
const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const PROBE := Vector2i(100, 100)

var _host: Node = null
var _router: ShortcutRouter = null
var _registries: SaRegistries = null
var _easel: SaEasel = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
var _was_embedding: bool = true
var _shipped: Array[String] = []


## A host with a router watching every window, wired as `main.gd` wires one,
## and the filter dialog under it watching registries that hold Colour
## Balance and Hue/Saturation/Lightness as the base module registers them.
##
## Embedding is forced as `test_escape_closes_a_dialog.gd` forces it, or
## `add_child` maps a real OS window and the run blocks until the watchdog.
func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "U24TestHost"
    EventBus.add_child(_host)

    _registries = SaRegistries.new()
    _registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    var ctx := _registries.context.for_module(OWNER)
    ctx.register_filter_section(&"color", "Colour", 200)
    ctx.register_filter(SaColorBalanceFilter.new())
    ctx.register_filter(SaHueSaturationLightnessFilter.new())
    _shipped = SaShortcutStore.chords_for(COMMAND)

    _easel = Bench.easel(Vector2i(256, 256))
    _easel.document.fill_layer(PAINT, _easel.document.active_layer)
    Bench.composite(_easel)
    _easel.compositor.filter_chain.registry = _registries.filters
    _canvas = SaCanvas.new()
    _canvas.easel = _easel

    _router = ShortcutRouter.new()
    _router.name = "U24Router"
    _router.canvas_provider = func() -> SaCanvas: return _canvas
    _router.tool_machine_provider = func() -> ToolMachine: return null
    _router.commands = _registries.commands
    _host.add_child(_router)
    _router.watch_windows(tree)

    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.watch(_registries.filters)
    _host.add_child(_window)


func after_each() -> void:
    SaShortcutStore.set_chords(COMMAND, _shipped)
    if _window != null and _window.visible:
        _window.cancel_filter()
    _host.free()
    _host = null
    _router = null
    _window = null
    _canvas.free()
    _canvas = null
    _easel.free()
    _easel = null
    _registries = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding


## A press of *keycode* with Ctrl and, when asked, ALT, with both keycode
## fields set as a keyboard sends them.
static func _chord(keycode: Key, alt: bool = false) -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = keycode
    key.physical_keycode = keycode
    key.ctrl_pressed = true
    key.alt_pressed = alt
    key.pressed = true
    return key


## A key the way the engine hands it to *window*: `window_input` first, which
## is where the router hears it, and then the window's own tree.
static func _press_into(window: Window, event: InputEvent) -> void:
    window.window_input.emit(event)
    window.push_input(event)


## A key over the canvas, as `Main._unhandled_input` hands it on.
func _press_over_the_canvas(event: InputEvent) -> void:
    _router.handle_viewport_input(event, (Engine.get_main_loop() as SceneTree).root)


func _layer_texel() -> Color:
    return Bench.texel(_easel.document.active_layer.get_field(Vector2i.ZERO), PROBE)


## Colour Balance opened through its command, the cascade that counts it on
## screen run, and its slider moved so the preview stands on the canvas.
func _open_and_slide() -> void:
    assert_true(_registries.commands.execute(COMMAND), "Colour Balance's command runs")
    assert_true(_window.visible, "and opens its dialog")
    assert_eq(_window.filter.title(), "Colour Balance", "on Colour Balance")
    _window.cascade_off_the_open_dialogs()
    _window.dialog.row(SLIDER).drive(60.0)
    _window.dialog.flush_rerun()
    assert_not_null(_easel.compositor.point_preview.for_document(_easel.document), "The preview is on the canvas")


## What Escape leaves, read after the chord closed the dialog: the window
## shut with its page down, the preview gone, no step and the layer as it was.
func _assert_closed_as_escape_closes(before: Color, steps: int, how: String) -> void:
    assert_false(_window.visible, "%s closes the dialog" % how)
    assert_null(_window.dialog, "%s takes its page down" % how)
    assert_null(_easel.compositor.point_preview.for_document(_easel.document), "%s takes the preview off the canvas" % how)
    assert_eq(_easel.document.history.step_count(), steps, "%s makes no step" % how)
    assert_true(_easel.document.active_layer.filters.is_empty(), "%s attaches nothing" % how)
    Bench.composite(_easel)
    var after := _layer_texel()
    assert_true(after.is_equal_approx(before), "%s leaves the layer as it was: %s against %s" % [how, after, before])


func test_ctrl_b_into_the_dialog_closes_it_and_ctrl_b_again_opens_it() -> void:
    var before := _layer_texel()
    var steps := _easel.document.history.step_count()
    _open_and_slide()

    _press_into(_window, _chord(KEY_B))
    _assert_closed_as_escape_closes(before, steps, "Ctrl+B into the dialog")

    _press_over_the_canvas(_chord(KEY_B))
    assert_true(_window.visible, "Ctrl+B pressed again opens the dialog")
    assert_eq(_window.filter.title(), "Colour Balance", "on Colour Balance")


func test_ctrl_b_over_the_canvas_closes_the_open_dialog() -> void:
    var before := _layer_texel()
    var steps := _easel.document.history.step_count()
    _open_and_slide()

    _press_over_the_canvas(_chord(KEY_B))
    _assert_closed_as_escape_closes(before, steps, "Ctrl+B over the canvas")


func test_ctrl_b_with_a_sliders_number_field_focused_closes_the_dialog() -> void:
    var before := _layer_texel()
    var steps := _easel.document.history.step_count()
    _open_and_slide()
    # The slider sits in a box of its own, so its name stands beside it.
    var found := _window.dialog.row(SLIDER).custom_control.find_children("*", "FactorSlider", true, false)
    var slider: FactorSlider = found[0] if not found.is_empty() else null
    assert_not_null(slider, "the midtones' cyan to red row holds a slider")
    if slider == null:
        return
    slider.start_editing()
    assert_true(slider._line_edit.has_focus(), "the slider's number field holds the keyboard")

    _press_into(_window, _chord(KEY_B))
    _assert_closed_as_escape_closes(before, steps, "Ctrl+B in the number field")


func test_the_chord_rebound_toggles_the_dialog_and_ctrl_b_no_longer_does() -> void:
    SaShortcutStore.set_chords(COMMAND, ["Ctrl+Alt+K"])
    assert_eq(_registries.commands.chord_text(COMMAND), "Ctrl+Alt+K", "Colour Balance is rebound")
    var before := _layer_texel()
    var steps := _easel.document.history.step_count()
    _open_and_slide()

    _press_into(_window, _chord(KEY_B))
    assert_true(_window.visible, "Ctrl+B is no longer Colour Balance's and leaves the dialog open")

    _press_into(_window, _chord(KEY_K, true))
    _assert_closed_as_escape_closes(before, steps, "The rebound Ctrl+Alt+K into the dialog")

    _press_over_the_canvas(_chord(KEY_K, true))
    assert_true(_window.visible, "Ctrl+Alt+K pressed again opens the dialog")


func test_another_filters_chord_into_the_dialog_leaves_it_open_as_before() -> void:
    assert_eq(_registries.commands.chord_text(OTHER_COMMAND), "Ctrl+U", "Hue/Saturation/Lightness is on Ctrl+U")
    _open_and_slide()

    _press_into(_window, _chord(KEY_U))
    assert_true(_window.visible, "Ctrl+U into Colour Balance's dialog leaves it open")
    assert_eq(_window.filter.title(), "Colour Balance", "on Colour Balance")


func test_another_filters_chord_over_the_canvas_opens_that_filter_as_before() -> void:
    _open_and_slide()

    _press_over_the_canvas(_chord(KEY_U))
    assert_true(_window.visible, "Ctrl+U over the canvas leaves the dialog up")
    assert_eq(_window.filter.title(), "Hue/Saturation/Lightness", "on Hue/Saturation/Lightness, as before")
