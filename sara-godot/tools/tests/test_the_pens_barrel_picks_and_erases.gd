## A stroke made with a pen button held, bound to a tool while held, is that
## tool's stroke: the eyedropper picks and the eraser erases.
##
## Under Windows Ink, binding the right button to each left the
## tool swapped in and doing nothing, because Windows reports the barrel held
## with the tip down as the second button and sends no left press. The events
## below are the shape that path hands Godot: a right press whose mask is the
## right button's, motions carrying the pen's pressure under the same mask, and
## a right release. The middle button gets the same, which is how a third barrel
## flag would arrive. The Wayland shape is held as well, where the barrel is
## pressed in the air and the tip is a left press of its own, so the fix cannot
## have bought Windows' stroke by erasing along a hovering pen.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")

## What the merged composite is cleared to for the eyedropper to find.
const UNDER_THE_PEN := Color(0.1, 0.6, 0.3, 1.0)
## The paint the eraser is given to take off.
const PAINT := Color(0.8, 0.2, 0.1, 1.0)
## The two buttons the ask names, with the ids their rows are stored under.
const BUTTONS: Array[Dictionary] = [
    {"id": "right", "index": MOUSE_BUTTON_RIGHT, "mask": MOUSE_BUTTON_MASK_RIGHT},
    {"id": "middle", "index": MOUSE_BUTTON_MIDDLE, "mask": MOUSE_BUTTON_MASK_MIDDLE},
]
## What an erased texel's alpha is under, at the stroke's pressure.
const ERASED := 0.9
## The row the strokes run along, and a point well off it.
const ROW_Y := 64.0
const OFF_THE_ROW := Vector2(64, 16)

var _stored: Dictionary = {}
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _picked: Array[Color] = []
var _host: Node = null


func before_each() -> void:
    _stored = SaSettings.pen_buttons.duplicate()
    _surface = Fixtures.make_surface(Vector2i(128, 128))
    # The built-in blend modes, as `main.gd` wires them. Wash is the brush's
    # default, so an eraser gathers in the stroke buffer and lands
    # under Erase at the commit, and a compositor without the registry would
    # resolve that mode to Normal and leave the paint standing.
    _surface.easel.compositor.set_registry(Fixtures.make_registries(_surface).blend_modes)
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _picked.clear()
    EventBus.color_picked.connect(_on_picked)


func after_each() -> void:
    EventBus.color_picked.disconnect(_on_picked)
    SaCursorPolicy.forget_pointer_device()
    SaSettings.pen_buttons = _stored
    Fixtures.teardown(_surface, _machine)
    if _host != null:
        var canvas := _host.get_child(0) as Node
        var machine: ToolMachine = canvas.get("tool_machine")
        machine.registered_tools.clear()
        machine.active_tool = null
        machine.registry = null
        _host.free()
        _host = null


func _on_picked(color: Color) -> void:
    _picked.append(color)


func test_the_barrel_bound_to_the_eyedropper_picks_the_colour_under_it() -> void:
    for button: Dictionary in BUTTONS:
        _bind(button["id"], SaSettingsPenButtons.EYEDROPPER)
        _picked.clear()
        var rd := GlobalShaderCompiler.get_rd()
        rd.texture_clear(_surface.easel.output.rid, UNDER_THE_PEN, 0, 1, 0, 1)
        var want := _surface.get_document().color_space.to_display(UNDER_THE_PEN)
        var tools := _barrel_stroke(button, [Vector2(40, ROW_Y), Vector2(48, ROW_Y), Vector2(56, ROW_Y)])
        var where := "the %s button" % button["id"]
        assert_eq(tools[0], &"eyedropper", "%s swaps the eyedropper in" % where)
        assert_true(_picked.size() > 0, "%s picks with the tip down" % where)
        if _picked.is_empty():
            continue
        var got: Color = _picked[_picked.size() - 1]
        assert_almost_eq(got.r, want.r, 0.01, "%s picks the red under the pen" % where)
        assert_almost_eq(got.g, want.g, 0.01, "%s picks the green under the pen" % where)
        assert_almost_eq(got.b, want.b, 0.01, "%s picks the blue under the pen" % where)
        assert_eq(tools[1], &"brush", "and the brush comes back on the release")


func test_the_barrel_bound_to_the_eraser_takes_paint_off() -> void:
    for button: Dictionary in BUTTONS:
        _bind(button["id"], SaSettingsPenButtons.ERASER)
        _paint_the_layer()
        var where := "the %s button" % button["id"]
        var steps := _steps()
        var tools := _barrel_stroke(button, _row(24, 104))
        assert_eq(tools[0], &"eraser", "%s swaps the eraser in" % where)
        assert_true(_alpha_at(Vector2(64, ROW_Y)) < ERASED, "%s erases along the stroke" % where)
        assert_almost_eq(_alpha_at(OFF_THE_ROW), 1.0, 0.001, "and leaves the paint off it alone")
        assert_eq(tools[1], &"brush", "and the brush comes back on the release")
        assert_eq(_steps(), steps + 1, "%s closes its stroke as one undo step" % where)


## Wayland's shape: the barrel pressed in the air, a hover at no pressure with
## it held, and then the tip, a left press of its own under the same mask. The
## hover erases nothing, and the tip's stroke is the eraser's as it always was.
func test_a_barrel_held_in_the_air_erases_nothing_until_the_tip_touches() -> void:
    _bind("right", SaSettingsPenButtons.ERASER)
    _paint_the_layer()
    var right := MOUSE_BUTTON_MASK_RIGHT
    _machine.handle_input(_button(MOUSE_BUTTON_RIGHT, true, Vector2(24, ROW_Y), right))
    for at: Vector2 in _row(24, 104):
        _machine.handle_input(_motion(at, 0.0, right))
    assert_eq(_machine.active_tool_name, &"eraser", "The barrel in the air swaps the eraser in")
    assert_almost_eq(_alpha_at(Vector2(64, ROW_Y)), 1.0, 0.001, "and a hover with it held erases nothing")

    var steps := _steps()
    var both := MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT
    _machine.handle_input(_motion(Vector2(104, ROW_Y), 0.6, both))
    _machine.handle_input(_button(MOUSE_BUTTON_LEFT, true, Vector2(104, ROW_Y), both))
    for i: int in range(20):
        _machine.handle_input(_motion(Vector2(104 - i * 4, ROW_Y), 0.6, both))
    _machine.handle_input(_button(MOUSE_BUTTON_LEFT, false, Vector2(28, ROW_Y), right))
    assert_true(_alpha_at(Vector2(64, ROW_Y)) < ERASED, "The tip's own stroke erases")
    assert_eq(_steps(), steps + 1, "as one undo step")
    _machine.handle_input(_button(MOUSE_BUTTON_RIGHT, false, Vector2(28, ROW_Y), 0))
    assert_eq(_machine.active_tool_name, &"brush", "and the release of the barrel hands the brush back")
    assert_eq(_steps(), steps + 1, "with no second step, since the barrel made no stroke of its own")


## A focus loss swallows the barrel's release. The stroke it was making is
## closed rather than left open with no undo step, and the brush comes back.
func test_a_focus_loss_mid_stroke_closes_the_stroke() -> void:
    _bind("right", SaSettingsPenButtons.ERASER)
    _paint_the_layer()
    var right := MOUSE_BUTTON_MASK_RIGHT
    _machine.handle_input(_button(MOUSE_BUTTON_RIGHT, true, Vector2(24, ROW_Y), right))
    for at: Vector2 in _row(24, 104):
        _machine.handle_input(_motion(at, 0.6, right))
    assert_true(_machine.active_tool.get("is_drawing"), "The barrel's stroke is under way")
    var steps := _steps()
    _machine.clear_held_keys()
    assert_eq(_steps(), steps + 1, "A focus loss closes it as an undo step")
    assert_eq(_machine.active_tool_name, &"brush", "and hands the brush back")
    assert_true(_alpha_at(Vector2(64, ROW_Y)) < ERASED, "keeping what it erased")


## A left press while the barrel's stroke is open is the tip of the same
## touch. The stroke goes on through it and the left release
## closes it, one touch one undo step, never two presses in a row.
func test_a_left_press_under_an_open_barrel_stroke_joins_it() -> void:
    _bind("right", SaSettingsPenButtons.ERASER)
    _paint_the_layer()
    var right := MOUSE_BUTTON_MASK_RIGHT
    _machine.handle_input(_button(MOUSE_BUTTON_RIGHT, true, Vector2(24, ROW_Y), right))
    _machine.handle_input(_motion(Vector2(24, ROW_Y), 0.6, right))
    _machine.handle_input(_motion(Vector2(28, ROW_Y), 0.6, right))
    var eraser := _machine.active_tool
    assert_true(eraser.get("is_drawing"), "The barrel's touch opened the eraser's stroke")
    var steps := _steps()
    var both := MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT
    _machine.handle_input(_button(MOUSE_BUTTON_LEFT, true, Vector2(28, ROW_Y), both))
    assert_eq(_steps(), steps, "The left press closed nothing")
    assert_true(eraser.get("is_drawing"), "and the stroke goes on")
    _machine.handle_input(_motion(Vector2(40, ROW_Y), 0.6, both))
    _machine.handle_input(_button(MOUSE_BUTTON_LEFT, false, Vector2(40, ROW_Y), right))
    assert_eq(_steps(), steps + 1, "until the left release closes it")
    _machine.handle_input(_button(MOUSE_BUTTON_RIGHT, false, Vector2(40, ROW_Y), 0))
    assert_eq(_steps(), steps + 1, "and the barrel's release has nothing left to close")


## A button bound to a tool no registry holds leaves the pen doing nothing, and
## a touch under it opens no stroke of the tool that stayed.
func test_a_touch_under_a_button_whose_tool_is_missing_paints_nothing() -> void:
    _bind("right", SaSettingsPenButtons.ERASER)
    _machine.registered_tools.erase(&"eraser")
    var right := MOUSE_BUTTON_MASK_RIGHT
    _machine.handle_input(_button(MOUSE_BUTTON_RIGHT, true, Vector2(24, ROW_Y), right))
    for at: Vector2 in _row(24, 104):
        _machine.handle_input(_motion(at, 0.6, right))
    assert_eq(_machine.active_tool_name, &"brush", "The brush stays")
    assert_false(_machine.active_tool.get("is_drawing"), "and opens no stroke under the barrel")
    _machine.handle_input(_button(MOUSE_BUTTON_RIGHT, false, Vector2(104, ROW_Y), 0))


## The barrel's release reaches the machine wherever it lands. The canvas takes
## a right press at the window only where the point is its own, and the release
## was held to the same test, so a stroke that ended over a docker left
## the eraser swapped in and its stroke open.
func test_a_release_off_the_canvas_still_reaches_the_machine() -> void:
    _bind("right", SaSettingsPenButtons.EYEDROPPER)
    var canvas := _canvas_in_the_tree()
    var machine: ToolMachine = canvas.get("tool_machine")
    var control: Control = canvas.get("control_node")
    machine.handle_input(_button(MOUSE_BUTTON_RIGHT, true, Vector2(10, 10), MOUSE_BUTTON_MASK_RIGHT))
    assert_eq(machine.active_tool_name, &"eyedropper", "The press on the canvas swaps the eyedropper in")
    var outside := control.get_global_rect().position - Vector2(400, 400)
    var to_window := canvas.get_window().get_final_transform()
    canvas.call("_on_window_input", _button(MOUSE_BUTTON_RIGHT, false, to_window * outside, 0))
    assert_false(machine.active_tool_name == &"eyedropper", "and the release off the canvas hands it back")


# --- Helpers --------------------------------------------------------------------


## Presses *button*, puts the tip down at the first point and moves through the
## rest with the button held, then releases it at the last. Answers the tool
## active with the button down and the one after the release.
func _barrel_stroke(button: Dictionary, points: Array[Vector2]) -> Array[StringName]:
    var index: MouseButton = button["index"]
    var mask: int = button["mask"]
    _machine.handle_input(_motion(points[0], 0.0, 0))
    _machine.handle_input(_button(index, true, points[0], mask))
    var held := _machine.active_tool_name
    for at: Vector2 in points:
        _machine.handle_input(_motion(at, 0.6, mask))
    _machine.handle_input(_button(index, false, points[points.size() - 1], 0))
    return [held, _machine.active_tool_name]


func _bind(button_id: String, action: String) -> void:
    var table := SaSettings.pen_buttons.duplicate()
    table[button_id] = action
    SaSettings.pen_buttons = table


## The active layer filled with opaque paint, the way a fill leaves it, and
## the eraser wide enough that the row's middle is well inside its stroke.
func _paint_the_layer() -> void:
    _surface.get_document().fill_layer(PAINT)
    assert_almost_eq(_alpha_at(Vector2(64, ROW_Y)), 1.0, 0.001, "The layer starts painted")
    var eraser := _machine.get_tool(&"eraser")
    var settings: Resource = eraser.get("settings")
    settings.set("radius", 0.08)


## The undo steps the document keeps, which a closed stroke adds one to.
func _steps() -> int:
    var history := _surface.get_document().history
    assert_not_null(history, "The fixture's document keeps a history")
    return history.step_count() if history != null else -1


## The alpha the active layer holds at *at*, read the way the eyedropper reads
## a layer.
func _alpha_at(at: Vector2) -> float:
    var reader := StateEyedropperScript.new()
    reader.surface = _surface
    reader.sample_from = StateEyedropperScript.SampleFrom.LAYER
    return reader.pick_color_at_pos(at).a


func _row(from_x: int, to_x: int) -> Array[Vector2]:
    var out: Array[Vector2] = []
    for x: int in range(from_x, to_x + 1, 4):
        out.append(Vector2(x, ROW_Y))
    return out


## A motion at *at*, where the fake view puts the pointer too, since a tool
## reads its position from the view rather than from the event.
func _motion(at: Vector2, pressure: float, mask: int) -> InputEventMouseMotion:
    (_surface.view as Fixtures.FakeView).mouse_position = at
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    event.pressure = pressure
    event.tilt = Vector2(0.2, 0.1)
    event.button_mask = mask
    # What the cursor overlay does with every motion in a window, so the pen's
    # middle press is told from a wheel press.
    SaCursorPolicy.note_pointer_device(event)
    return event


func _button(index: MouseButton, pressed: bool, at: Vector2, mask: int) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = index
    event.pressed = pressed
    event.position = at
    event.global_position = at
    event.button_mask = mask
    return event


## A main canvas in the tree with the built-in tools, the way the tally suite
## builds one to drive its window route.
func _canvas_in_the_tree() -> Node:
    _host = Node.new()
    _host.name = "BarrelHost"
    EventBus.add_child(_host)
    var canvas: Node = MainCanvasScript.new()
    _host.add_child(canvas)
    canvas.call("bind_tools", Fixtures.make_tool_registry())
    return canvas
