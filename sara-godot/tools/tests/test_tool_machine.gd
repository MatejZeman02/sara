## GPU integration tests for ToolMachine.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const StatePanScript = preload("res://modules/sara-base-modules/base/tools/state_pan.gd")
const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")
const StateZoomScript = preload("res://modules/sara-base-modules/base/tools/state_zoom.gd")


func test_tool_registration_and_switching() -> void:
    var surface := Fixtures.make_surface()
    var tm := ToolMachine.new()
    tm.name = "ToolMachine"
    tm._ready()
    tm.surface = surface

    var brush := StateBrushScript.new()
    var pan := StatePanScript.new()

    tm.register_tool(&"brush", brush)
    tm.register_tool(&"pan", pan)

    assert_eq(tm.registered_tools.size(), 2, "Should have 2 registered tools")
    assert_eq(tm.active_tool_name, &"brush", "First registered tool should be active")
    assert_eq(tm.active_tool, brush, "Active tool instance should match brush")

    tm.set_active_tool(&"pan")
    assert_eq(tm.active_tool_name, &"pan", "Active tool should switch to pan")
    assert_eq(tm.active_tool, pan, "Active tool instance should match pan")

    Fixtures.teardown(surface, tm)


func test_alt_key_eyedropper_switching() -> void:
    var surface := Fixtures.make_surface()
    var tm := Fixtures.make_bound_machine(surface)

    tm.set_active_tool(&"brush")
    assert_eq(tm.active_tool_name, &"brush", "Should start with brush")

    var alt_press := InputEventKey.new()
    alt_press.keycode = KEY_ALT
    alt_press.physical_keycode = KEY_ALT
    alt_press.pressed = true
    Input.parse_input_event(alt_press)
    tm.handle_input(alt_press)
    assert_eq(tm.active_tool_name, &"eyedropper", "Should switch to eyedropper while holding ALT")

    var alt_release := InputEventKey.new()
    alt_release.keycode = KEY_ALT
    alt_release.physical_keycode = KEY_ALT
    alt_release.pressed = false
    Input.parse_input_event(alt_release)
    tm.handle_input(alt_release)
    assert_eq(tm.active_tool_name, &"brush", "Should return to brush when releasing ALT")

    Fixtures.teardown(surface, tm)


## Tests the quick-tool (hold-to-activate, release-to-restore) behaviour and
## Ctrl+Space → Space modifier-stacking, handing `_update_held_keys` the key
## events a keyboard sends, so the test is independent of headless Input
## singleton quirks and the machine writes its own keys.
func test_quick_tool_hold_and_release() -> void:
    var surface := Fixtures.make_surface()
    var tm := Fixtures.make_bound_machine(surface)

    tm.set_active_tool(&"brush")
    assert_eq(tm.active_tool_name, &"brush", "Should start with brush as permanent tool")

    # --- Space (tool_pan_quick) held → pan. Released → brush ---------------
    _key(tm, KEY_SPACE, true)
    tm._evaluate_tool()
    assert_eq(tm.active_tool_name, &"pan", "Holding Space should quick-switch to pan")
    assert_eq(tm.default_tool_name, &"brush", "Permanent tool should still be brush while Space held")

    _key(tm, KEY_SPACE, false)
    tm._evaluate_tool()
    assert_eq(tm.active_tool_name, &"brush", "Releasing Space should restore brush (permanent tool)")

    # --- Ctrl+Space (tool_zoom_quick) held → zoom --------------------------
    _key(tm, KEY_CTRL, true)
    _key(tm, KEY_SPACE, true)
    tm._evaluate_tool()
    assert_eq(tm.active_tool_name, &"zoom", "Ctrl+Space should quick-switch to zoom (higher priority than pan)")

    # --- Modifier stacking: release Ctrl while Space still held → pan ------
    _key(tm, KEY_CTRL, false)
    tm._evaluate_tool()
    assert_eq(tm.active_tool_name, &"pan", "Releasing Ctrl (Space still held) should downgrade to pan quick-tool")

    # Release Space → restore permanent tool (brush)
    _key(tm, KEY_SPACE, false)
    tm._evaluate_tool()
    assert_eq(tm.active_tool_name, &"brush", "Releasing Space should restore brush (permanent tool)")

    # --- Permanent tool switch is independent of quick-tool ----------------
    tm.set_active_tool(&"pan")
    assert_eq(tm.active_tool_name, &"pan", "set_active_tool(pan) should make pan the permanent tool")

    # Quick Space held while permanent tool is pan → still pan (pan is permanent)
    _key(tm, KEY_SPACE, true)
    tm._evaluate_tool()
    assert_eq(tm.active_tool_name, &"pan", "Holding Space when pan is already permanent should stay on pan")

    _key(tm, KEY_SPACE, false)
    tm._evaluate_tool()
    assert_eq(tm.active_tool_name, &"pan", "Releasing Space when pan is permanent should stay on pan")

    # --- Alt (tool_eyedropper_quick) held → eyedropper --------------------
    tm.set_active_tool(&"brush")
    _key(tm, KEY_ALT, true)
    tm._evaluate_tool()
    assert_eq(tm.active_tool_name, &"eyedropper", "Holding Alt should quick-switch to eyedropper")

    _key(tm, KEY_ALT, false)
    tm._evaluate_tool()
    assert_eq(tm.active_tool_name, &"brush", "Releasing Alt should restore brush")

    Fixtures.teardown(surface, tm)


## The cursor overlay reads the ring radius off the canvas rather than being
## pushed at directly, so that each window's overlay can ask which canvas the
## pointer is over. A painting tool must publish a radius. Anything else must
## clear it, because a non-negative radius is what permits hiding the OS cursor.
## Whether a tool gets a ring is now a property of its descriptor, not a hardcoded
## `name == "brush" or name == "eraser"` in two places.
func test_only_painting_tools_publish_a_cursor_ring() -> void:
    var surface := Fixtures.make_surface()
    var registry := SaToolRegistry.new()

    var brush := Fixtures.make_tool_descriptor(&"brush", StateBrushScript)
    brush.is_painting = true
    brush.wants_brush_cursor = true
    registry.register(brush)

    var pan := Fixtures.make_tool_descriptor(&"pan", StatePanScript)
    registry.register(pan)

    var tm := ToolMachine.new()
    tm.name = "ToolMachine"
    tm._ready()
    tm.bind(surface, registry)

    tm.set_active_tool(&"brush")
    assert_true(surface.cursor_ring_radius >= 0.0, "The brush should publish a ring radius")

    tm.set_active_tool(&"pan")
    assert_true(surface.cursor_ring_radius < 0.0, "Pan should clear the ring so the OS cursor is used")

    tm.set_active_tool(&"brush")
    assert_true(surface.cursor_ring_radius >= 0.0, "Switching back to the brush should restore the ring")

    Fixtures.teardown(surface, tm)


## The brush radius is a plain field on the settings object, which the options bar
## slider writes directly. Nothing announced the change, so the ring kept the size
## it had at the last tool switch and only caught up when some unrelated event
## happened to republish it, to the user, the circle resized on alt-tab.
func test_the_ring_follows_the_brush_size_without_being_told() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")

    var before: float = surface.cursor_ring_radius
    assert_true(before > 0.0, "The brush should publish a ring radius to begin with")

    var brush := machine.get_tool(&"brush")
    brush.settings.radius *= 2.0
    # No signal, no refresh_cursor() call: exactly what the slider does.
    machine._process(0.0)
    assert_true(surface.cursor_ring_radius > before * 1.5, "Growing the brush must grow the ring, unprompted")

    brush.settings.radius /= 2.0
    machine._process(0.0)
    assert_true(is_equal_approx(surface.cursor_ring_radius, before), "Shrinking it back must restore the original ring")

    Fixtures.teardown(surface, machine)


## A canvas with no ring must never claim one, whatever the pointer position.
func test_ring_lookup_ignores_canvases_that_want_no_ring() -> void:
    var canvas := SaCanvas.new()
    canvas.cursor_ring_radius = -1.0
    assert_true(
        SaCursorPolicy.cursor_ring_radius_at(null, Vector2.ZERO) < 0.0, "A canvas outside any window must not report a ring"
    )
    canvas.free()


## Shift plus a horizontal drag resizes the brush. The press that starts it must
## never reach the tool, or every resize would leave a dab behind on the canvas.
func test_shift_drag_resizes_the_brush_without_painting() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")

    var brush := machine.get_tool(&"brush")
    var before: float = brush.settings.radius

    machine.handle_input(_press(Vector2(100.0, 100.0), true))
    assert_false(brush.is_drawing, "The press that starts a resize must not start a stroke")

    machine.handle_input(_motion(Vector2(125.0, 100.0)))
    # A 256 pixel canvas at zoom 1: 25 pixels of drag is 25/256 of the smaller side.
    assert_almost_eq(
        brush.settings.radius, before + 25.0 / 256.0, 0.0001, "The radius should grow by the distance the pointer travelled"
    )

    machine.handle_input(_release(Vector2(125.0, 100.0)))
    var resized: float = brush.settings.radius
    machine.handle_input(_motion(Vector2(200.0, 100.0)))
    assert_almost_eq(brush.settings.radius, resized, 0.0001, "Motion after the button came up must not keep resizing")

    Fixtures.teardown(surface, machine)


## The ring is drawn in screen pixels and the radius is stored in document ones,
## so the zoom has to come out of the drag: at 2x, the same hand movement is half
## the brush. Past the maximum the drag stops mattering rather than wrapping.
func test_shift_drag_follows_the_zoom_and_stops_at_the_maximum() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    surface.view.zoom = 2.0

    var brush := machine.get_tool(&"brush")
    var before: float = brush.settings.radius

    machine.handle_input(_press(Vector2(100.0, 100.0), true))
    machine.handle_input(_motion(Vector2(150.0, 100.0)))
    assert_almost_eq(
        brush.settings.radius, before + 50.0 / (256.0 * 2.0), 0.0001, "Zoom must divide the drag, so the ring tracks the hand"
    )

    machine.handle_input(_motion(Vector2(100000.0, 100.0)))
    assert_almost_eq(brush.settings.radius, ToolMachine.BRUSH_RADIUS_MAX, 0.0001, "A long drag must stop at the maximum radius")

    machine.handle_input(_release(Vector2(100000.0, 100.0)))
    Fixtures.teardown(surface, machine)


## Only the shifted press is the gesture. An ordinary one still paints.
func test_a_press_without_shift_still_reaches_the_tool() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")

    var brush := machine.get_tool(&"brush")
    machine.handle_input(_press(Vector2(100.0, 100.0), false))
    assert_true(brush.is_drawing, "A press with no shift held must reach the brush")

    machine.handle_input(_release(Vector2(100.0, 100.0)))
    assert_false(brush.is_drawing, "Releasing must end the stroke")

    Fixtures.teardown(surface, machine)


## Every InputEventMouseMotion handle_input forwards to the active tool is
## counted, one for one, whatever tool is active and whether or not a stroke
## is under way: the machine's own delivery is what the count answers,
## not any one tool's reading of it. `scenarios/every-motion-event.json`
## is the same proof against the real input pipeline, where a scenario's
## `move` and a `stroke`'s own points are spaced one per frame by the
## runner's own step loop and only `motion_burst` pushes several inside one.
func test_every_motion_event_is_counted_once() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    assert_eq(machine.motion_samples_seen, 0, "nothing counted before anything moves")

    for at: Vector2 in [Vector2(100.0, 100.0), Vector2(110.0, 104.0), Vector2(120.0, 110.0)]:
        machine.handle_input(_motion(at))
    assert_eq(machine.motion_samples_seen, 3, "one per event, none folded into another")

    machine.reset_motion_samples()
    assert_eq(machine.motion_samples_seen, 0, "and reset_motion_samples zeroes it again")

    Fixtures.teardown(surface, machine)


func _press(at: Vector2, shift: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.position = at
    event.global_position = at
    event.shift_pressed = shift
    return event


func _release(at: Vector2) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = false
    event.position = at
    event.global_position = at
    return event


func _motion(at: Vector2) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    return event


## A tool that has done the job the painter came to it for hands the machine
## back to the tool before it, through the door the machine
## gave it at registration, so the tool never has to know which tool that was.
## With no tool before it, the brush.
func test_a_tool_hands_back_to_the_tool_before_it() -> void:
    var surface := Fixtures.make_surface()
    var tm := ToolMachine.new()
    tm.name = "ToolMachine"
    tm._ready()
    tm.surface = surface
    var brush := StateBrushScript.new()
    var pan := StatePanScript.new()
    var zoom := StateZoomScript.new()
    tm.register_tool(&"brush", brush)
    tm.register_tool(&"pan", pan)
    tm.register_tool(&"zoom", zoom)

    tm.set_active_tool(&"pan")
    tm.set_active_tool(&"zoom")
    assert_eq(tm.previous_tool_name, &"pan", "the machine remembers the permanent tool before the last switch")
    zoom.request_hand_back()
    assert_eq(tm.active_tool_name, &"pan", "and a hand-back goes there")
    assert_eq(tm.previous_tool_name, &"zoom", "the switch back is a switch too")

    tm.previous_tool_name = &""
    pan.request_hand_back()
    assert_eq(tm.active_tool_name, &"brush", "with nothing before it, the brush")

    Fixtures.teardown(surface, tm)
    assert_false(zoom.hand_back.is_valid(), "the door closes with the machine")


## A shift-drag moves one value, so it says so and nothing rebinds. It said `tool_changed`, and every surface rebound per motion
## event, the presets docker rebuilding its whole grid each time. It says so
## once a frame, so the motions of this test, which is one
## frame, are told when the frame's end tells them.
func test_a_size_drag_moves_values_and_changes_no_tool() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var counts := {"changed": 0, "moved": 0}
    var on_changed := func(_name: String) -> void: counts["changed"] += 1
    var on_moved := func() -> void: counts["moved"] += 1
    EventBus.tool_changed.connect(on_changed)
    EventBus.tool_options_moved.connect(on_moved)

    machine.handle_input(_press(Vector2(100.0, 100.0), true))
    machine.handle_input(_motion(Vector2(120.0, 100.0)))
    machine.handle_input(_motion(Vector2(140.0, 100.0)))
    machine.handle_input(_release(Vector2(140.0, 100.0)))
    assert_eq(counts["changed"], 0, "The drag changes no tool")
    assert_eq(counts["moved"], 0, "and says nothing before the frame ends")
    machine.tell_moved_size()
    assert_eq(counts["moved"], 1, "and then says the values moved, once for both motions")

    counts["moved"] = 0
    var brush_settings: Resource = machine.get_tool(&"brush").get("settings")
    SaShortcutKeys.nudge_brush_radius(machine, SaShortcutKeys.brush_size_step(brush_settings.radius, 1))
    assert_eq(counts["changed"], 0, "The bracket keys change no tool either")
    assert_eq(counts["moved"], 1, "and say the values moved once")

    EventBus.tool_changed.disconnect(on_changed)
    EventBus.tool_options_moved.disconnect(on_moved)
    Fixtures.teardown(surface, machine)


## A key event as a keyboard sends it, handed to the machine's own bookkeeping.
## A modifier's own press carries its flag, which is where `_update_held_keys`
## reads a modifier from.
func _key(tm: ToolMachine, keycode: Key, pressed: bool) -> void:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.pressed = pressed
    event.ctrl_pressed = pressed and keycode == KEY_CTRL
    event.shift_pressed = pressed and keycode == KEY_SHIFT
    event.alt_pressed = pressed and keycode == KEY_ALT
    tm._update_held_keys(event)


## Under the Krita profile a held Ctrl is the eyedropper, as Krita's own canvas
## has it, so a Ctrl click samples and leaves no history step, and the Ctrl
## chords still answer while it is held: Ctrl+Z undoes and Ctrl+Space is the
## quick zoom, which outranks it. Every key goes through the router the way the
## main window hands it one.
func test_under_krita_a_held_ctrl_samples_and_ctrl_z_still_undoes() -> void:
    var rig := _rig()
    var machine: ToolMachine = rig["machine"]
    var router: ShortcutRouter = rig["router"]
    var document: SaDocument = (rig["surface"] as SaSurface).get_document()
    SaShortcutStore.apply_profile("Krita")
    assert_eq(SaShortcutStore.chords_for(&"tool_eyedropper_quick"), ["Alt", "Ctrl"] as Array[String], "Krita holds Alt and Ctrl")
    document.fill_layer(Color(0.9, 0.5, 0.1, 1.0))
    # The eyedropper reads the picture the view shows, which a frame composites.
    var easel := (rig["surface"] as SaSurface).easel
    easel.request_full_composite()
    easel.process_pending_composite()
    var steps := document.history.step_count()
    var place := document.history.position()
    var picked: Array[Color] = []
    var on_pick := func(colour: Color) -> void: picked.append(colour)
    EventBus.color_picked.connect(on_pick)

    assert_eq(machine.active_tool_name, &"brush", "Nothing held is the brush")
    _send_key(router, KEY_CTRL, true)
    assert_eq(machine.active_tool_name, &"eyedropper", "A held Ctrl is the eyedropper")
    var press := _press(Vector2(10.0, 10.0), false)
    press.ctrl_pressed = true
    machine.handle_input(press)
    machine.handle_input(_release(Vector2(10.0, 10.0)))
    assert_eq(picked.size(), 1, "The Ctrl click samples")
    if not picked.is_empty():
        assert_almost_eq(picked[0].r, 0.9, 0.02, "the fill's colour: %s" % picked[0])
    assert_eq(document.history.step_count(), steps, "and leaves no history step")

    _send_key(router, KEY_SPACE, true, true)
    assert_eq(machine.active_tool_name, &"zoom", "Ctrl+Space is the quick zoom over it")
    _send_key(router, KEY_SPACE, false, true)
    assert_eq(machine.active_tool_name, &"eyedropper", "and Ctrl alone the eyedropper again")
    _send_key(router, KEY_Z, true, true)
    assert_true(document.history.position() != place, "Ctrl+Z undoes the fill with Ctrl held")
    assert_eq(machine.active_tool_name, &"eyedropper", "and the eyedropper stays in the hand")
    _send_key(router, KEY_Z, false, true)
    _send_key(router, KEY_CTRL, false)
    assert_eq(machine.active_tool_name, &"brush", "Letting Ctrl go is the brush again")

    EventBus.color_picked.disconnect(on_pick)
    _unrig(rig)


## Sara Default keeps Ctrl off the eyedropper, which is Alt's there, so a Ctrl
## click paints.
func test_under_sara_default_a_ctrl_click_paints() -> void:
    var rig := _rig()
    var machine: ToolMachine = rig["machine"]
    var router: ShortcutRouter = rig["router"]
    SaShortcutStore.apply_profile("Krita")
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    assert_eq(SaShortcutStore.chords_for(&"tool_eyedropper_quick"), ["Alt"] as Array[String], "Sara Default holds Alt alone")

    _send_key(router, KEY_CTRL, true)
    assert_eq(machine.active_tool_name, &"brush", "A held Ctrl leaves the brush in the hand")
    var press := _press(Vector2(100.0, 100.0), false)
    press.ctrl_pressed = true
    machine.handle_input(press)
    assert_true(machine.get_tool(&"brush").is_drawing, "and a Ctrl click paints")
    machine.handle_input(_release(Vector2(100.0, 100.0)))
    _send_key(router, KEY_CTRL, false)
    _send_key(router, KEY_ALT, true)
    assert_eq(machine.active_tool_name, &"eyedropper", "Alt is still the eyedropper after a trip to Krita")
    _send_key(router, KEY_ALT, false)

    _unrig(rig)


## A machine on the brush, the application's commands and a router over both,
## with the map saved after the commands made their actions, so `_unrig` puts it
## back and drops only the actions a profile wrote into being.
func _rig() -> Dictionary:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var registries := Fixtures.make_registries(surface)
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var canvas := SaCanvas.new()
    canvas.easel = surface.easel
    var router := ShortcutRouter.new()
    router.tool_machine_provider = func() -> ToolMachine: return machine
    router.canvas_provider = func() -> SaCanvas: return canvas
    router.bind_commands(registries.commands)
    var saved := {}
    for action: StringName in InputMap.get_actions():
        saved[action] = InputMap.action_get_events(action).duplicate()
    return {"surface": surface, "machine": machine, "router": router, "canvas": canvas, "saved": saved}


func _unrig(rig: Dictionary) -> void:
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    var saved: Dictionary = rig["saved"]
    for action: StringName in InputMap.get_actions():
        if not saved.has(action):
            InputMap.erase_action(action)
    for action: StringName in saved:
        InputMap.action_erase_events(action)
        for event: InputEvent in saved[action]:
            InputMap.action_add_event(action, event)
    (rig["router"] as ShortcutRouter).free()
    (rig["canvas"] as SaCanvas).free()
    Fixtures.teardown(rig["surface"], rig["machine"])


## A key as the keyboard sends it, through the router the main window hands it
## to, and told to `Input` as well, since a mouse event asks `Input` whether a
## modifier the machine holds is still down.
func _send_key(router: ShortcutRouter, keycode: Key, pressed: bool, ctrl: bool = false) -> void:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.pressed = pressed
    event.ctrl_pressed = ctrl or (pressed and keycode == KEY_CTRL)
    event.alt_pressed = pressed and keycode == KEY_ALT
    Input.parse_input_event(event)
    Input.flush_buffered_events()
    router.handle_viewport_input(event, null)
