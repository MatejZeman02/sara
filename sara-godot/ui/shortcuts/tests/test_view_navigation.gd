## Moving around the picture: the one zoom helper, and the gestures that reach it
## whatever tool is active.
##
## The arithmetic is on SaView and runs against the fake view, no tree needed.
## The gestures go through ToolMachine, which needs a surface with an easel, so
## the suite as a whole wants a GPU.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")


func _fake_view() -> SaTestFixtures.FakeView:
    var view := SaTestFixtures.FakeView.new()
    view.viewport_size = Vector2(1000, 800)
    return view


# ---------------------------------------------------------------------------
# The helper
# ---------------------------------------------------------------------------


## Whatever was under the pointer stays under it. Pinning the screen centre
## would slide a corner away when zooming at it.
func test_zooming_at_a_point_keeps_that_document_point_under_it() -> void:
    var view := _fake_view()
    view.zoom = 2.0
    view.pan = Vector2(100, 50)
    var anchor := Vector2(700, 450)
    var before := (anchor - view.pan) / view.zoom

    view.zoom_at(3.0, anchor)

    assert_almost_eq(view.zoom, 3.0, 1e-6, "The zoom is what was asked for")
    var after := (anchor - view.pan) / view.zoom
    assert_almost_eq(after.x, before.x, 1e-4, "and the document point under the anchor has not moved in x")
    assert_almost_eq(after.y, before.y, 1e-4, "nor in y")


func test_zooming_by_a_factor_compounds_and_undoes() -> void:
    var view := _fake_view()
    var anchor := Vector2(300, 200)
    var before := (anchor - view.pan) / view.zoom

    view.zoom_by(SaView.ZOOM_STEP, anchor)
    view.zoom_by(SaView.ZOOM_STEP, anchor)
    assert_almost_eq(view.zoom, SaView.ZOOM_STEP * SaView.ZOOM_STEP, 1e-6, "Two notches in is the step squared")

    view.zoom_by(1.0 / SaView.ZOOM_STEP, anchor)
    view.zoom_by(1.0 / SaView.ZOOM_STEP, anchor)
    assert_almost_eq(view.zoom, 1.0, 1e-6, "and two out is back where it started")
    var after := (anchor - view.pan) / view.zoom
    assert_almost_eq(after.x, before.x, 1e-4, "with the anchored point still under the pointer")
    assert_almost_eq(after.y, before.y, 1e-4, "on both axes")


func test_the_zoom_is_clamped_to_the_shared_range() -> void:
    var view := _fake_view()
    view.zoom_at(1000.0, Vector2.ZERO)
    assert_almost_eq(view.zoom, SaView.ZOOM_MAX, 1e-6, "Nothing zooms past the maximum")
    view.zoom_at(0.0, Vector2.ZERO)
    assert_almost_eq(view.zoom, SaView.ZOOM_MIN, 1e-6, "or below the minimum, which is also never zero")


func test_fit_puts_the_whole_document_in_the_view_centred() -> void:
    var view := _fake_view()
    view.zoom = 7.0
    view.pan = Vector2(-500, -500)

    view.fit(Vector2i(200, 100))

    # The short side decides: 800 / 100 is tighter than 1000 / 200.
    assert_almost_eq(view.zoom, 5.0, 1e-6, "Fitted to the tighter axis")
    assert_almost_eq(view.pan.x, 0.0, 1e-6, "flush on the tight axis")
    assert_almost_eq(view.pan.y, 150.0, 1e-6, "and centred on the loose one")


func test_centre_keeps_the_zoom_and_moves_the_document_to_the_middle() -> void:
    var view := _fake_view()
    view.zoom = 2.0
    view.pan = Vector2(-900, -900)

    view.center(Vector2i(200, 100))

    assert_almost_eq(view.zoom, 2.0, 1e-6, "The zoom is the user's")
    assert_almost_eq(view.pan.x, 300.0, 1e-6, "and the document sits in the middle across")
    assert_almost_eq(view.pan.y, 300.0, 1e-6, "and down")


# ---------------------------------------------------------------------------
# The gestures, through the machine, with a tool listening
# ---------------------------------------------------------------------------


func _machine(surface: SaSurface) -> Array:
    var tm := ToolMachine.new()
    tm.name = "ToolMachine"
    tm._ready()
    tm.surface = surface
    var tool := SaTestFixtures.FakeTool.new()
    tm.register_tool(&"fake", tool)
    return [tm, tool]


func _wheel(index: int, at: Vector2, pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = index as MouseButton
    event.pressed = pressed
    event.position = at
    event.global_position = at
    return event


## A wheel notch zooms about the pointer and never reaches the active tool, so
## painting with the wheel in reach does not lay a dab per notch.
func test_a_wheel_notch_zooms_about_the_pointer_and_stays_away_from_the_tool() -> void:
    var surface := Fixtures.make_surface()
    var view := surface.view as SaTestFixtures.FakeView
    var pair := _machine(surface)
    var tm: ToolMachine = pair[0]
    var tool: SaTestFixtures.FakeTool = pair[1]
    var at := Vector2(600, 400)
    var before := (at - view.pan) / view.zoom

    tm.handle_input(_wheel(MOUSE_BUTTON_WHEEL_UP, at, true))
    tm.handle_input(_wheel(MOUSE_BUTTON_WHEEL_UP, at, false))

    assert_almost_eq(view.zoom, SaView.ZOOM_STEP, 1e-6, "One notch in is one step")
    var after := (at - view.pan) / view.zoom
    assert_almost_eq(after.x, before.x, 1e-4, "about the pointer")
    assert_true(tool.events.is_empty(), "and neither the press nor the release reached the tool")

    tm.handle_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN, at, true))
    tm.handle_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN, at, false))
    assert_almost_eq(view.zoom, 1.0, 1e-6, "A notch out undoes it")

    Fixtures.teardown(surface, tm)


## A smooth wheel reports fractions of a notch in `factor`.
func test_a_smooth_wheel_zooms_by_the_fraction_it_reports() -> void:
    var surface := Fixtures.make_surface()
    var view := surface.view as SaTestFixtures.FakeView
    var tm: ToolMachine = _machine(surface)[0]

    var half := _wheel(MOUSE_BUTTON_WHEEL_UP, Vector2(10, 10), true)
    half.factor = 0.5
    tm.handle_input(half)

    assert_almost_eq(view.zoom, pow(SaView.ZOOM_STEP, 0.5), 1e-6, "Half a notch is the square root of a step")

    Fixtures.teardown(surface, tm)


func test_a_pinch_zooms_by_its_factor_about_its_position() -> void:
    var surface := Fixtures.make_surface()
    var view := surface.view as SaTestFixtures.FakeView
    var pair := _machine(surface)
    var tm: ToolMachine = pair[0]
    var tool: SaTestFixtures.FakeTool = pair[1]

    var pinch := InputEventMagnifyGesture.new()
    pinch.factor = 2.0
    pinch.position = Vector2(500, 400)
    tm.handle_input(pinch)

    assert_almost_eq(view.zoom, 2.0, 1e-6, "The pinch's factor is the zoom's")
    assert_almost_eq(view.pan.x, -500.0, 1e-4, "about the pinch's centre")
    assert_true(tool.events.is_empty(), "and the tool never saw it")

    Fixtures.teardown(surface, tm)


## The middle button pans whatever tool is active, and the tool sees none of it.
func test_a_middle_drag_pans_whatever_the_tool_is() -> void:
    var surface := Fixtures.make_surface()
    var view := surface.view as SaTestFixtures.FakeView
    var pair := _machine(surface)
    var tm: ToolMachine = pair[0]
    var tool: SaTestFixtures.FakeTool = pair[1]

    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_MIDDLE
    press.pressed = true
    tm.handle_input(press)

    var motion := InputEventMouseMotion.new()
    motion.relative = Vector2(40, -15)
    tm.handle_input(motion)
    tm.handle_input(motion)

    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_MIDDLE
    release.pressed = false
    tm.handle_input(release)

    assert_almost_eq(view.pan.x, 80.0, 1e-6, "Two motions of forty pan by eighty")
    assert_almost_eq(view.pan.y, -30.0, 1e-6, "on both axes")
    assert_true(tool.events.is_empty(), "and the tool saw neither the button nor the drag")

    # Once released, motion is the tool's again.
    tm.handle_input(motion)
    assert_eq(tool.events.size(), 1, "After the release the motion reaches the tool")
    assert_almost_eq(view.pan.x, 80.0, 1e-6, "and the view no longer follows it")

    Fixtures.teardown(surface, tm)


# ---------------------------------------------------------------------------
# The chords
# ---------------------------------------------------------------------------


func _chord(keycode: int, shift: bool) -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = keycode as Key
    key.physical_keycode = keycode as Key
    key.ctrl_pressed = true
    key.shift_pressed = shift
    key.pressed = true
    return key


## Ctrl with plus, minus and zero zoom the canvas, and the UI scale moves
## to Ctrl+Shift. The bare chords do not scale the UI.
func test_ctrl_plus_zooms_the_canvas_and_leaves_the_ui_scale_alone() -> void:
    var surface := Fixtures.make_surface()
    var view := surface.view as SaTestFixtures.FakeView
    var tm: ToolMachine = _machine(surface)[0]
    var router := ShortcutRouter.new()
    router.tool_machine_provider = func() -> ToolMachine: return tm
    # The zoom, rotate and interface chords are registered commands,
    # so a router with no registry answers none of them.
    router.bind_commands(SaCommandRegistry.new())
    var ui_scale_before := SaSettings.ui_scale

    assert_true(router.handle(_chord(KEY_EQUAL, false)), "Ctrl+= is taken")
    assert_almost_eq(view.zoom, SaView.ZOOM_STEP, 1e-6, "as one step in")
    assert_true(router.handle(_chord(KEY_MINUS, false)), "Ctrl+- is taken")
    assert_almost_eq(view.zoom, 1.0, 1e-6, "as one step out")
    assert_true(router.handle(_chord(KEY_0, false)), "Ctrl+0 is taken")
    view.set_zoom(4.0)
    router.handle(_chord(KEY_0, false))
    assert_almost_eq(
        view.zoom_per_cent(surface.get_canvas_size()),
        float(SaView.RESET_SIZE),
        1e-4,
        "and is Reset Zoom, Krita's binding, the whole picture at the Size the Display page names"
    )
    assert_almost_eq(SaSettings.ui_scale, ui_scale_before, 1e-6, "None of that touched the UI scale")

    # Krita's chord zooms about the middle of the view, since a key has no
    # pointer. A fake view's free rectangle is the whole of it, so the two
    # middles are one here.
    view.zoom = 1.0
    view.pan = Vector2.ZERO
    var middle := view.viewport_size * 0.5
    var before := (middle - view.pan) / view.zoom
    router.handle(_chord(KEY_EQUAL, false))
    var after := (middle - view.pan) / view.zoom
    assert_almost_eq(after.x, before.x, 1e-4, "The middle of the view stays put")

    router.free()
    Fixtures.teardown(surface, tm)


func test_ctrl_shift_plus_scales_the_ui_and_leaves_the_canvas_alone() -> void:
    var surface := Fixtures.make_surface()
    var view := surface.view as SaTestFixtures.FakeView
    var tm: ToolMachine = _machine(surface)[0]
    var router := ShortcutRouter.new()
    router.tool_machine_provider = func() -> ToolMachine: return tm
    # The zoom, rotate and interface chords are registered commands,
    # so a router with no registry answers none of them.
    router.bind_commands(SaCommandRegistry.new())
    var ui_scale_before := SaSettings.ui_scale

    assert_true(router.handle(_chord(KEY_EQUAL, true)), "Ctrl+Shift+= is taken")
    assert_almost_eq(view.zoom, 1.0, 1e-6, "and the canvas did not move")
    assert_almost_eq(SaSettings.ui_scale, ui_scale_before + SaShortcutCommands.UI_SCALE_STEP, 1e-6, "the UI did")

    SaSettings.ui_scale = ui_scale_before
    router.free()
    Fixtures.teardown(surface, tm)


## The zoom tool zooms about where it was pressed, through the same helper.
func test_the_zoom_tool_zooms_about_the_press() -> void:
    var surface := Fixtures.make_surface()
    var view := surface.view as SaTestFixtures.FakeView
    var zoom_tool: ToolState = load("res://modules/sara-base-modules/base/tools/state_zoom.gd").new()
    zoom_tool.surface = surface
    var at := Vector2(800, 600)
    var before := (at - view.pan) / view.zoom

    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = at
    press.global_position = at
    zoom_tool.handle_input(press)

    var drag := InputEventMouseMotion.new()
    drag.position = at - Vector2(0, 200)
    drag.global_position = drag.position
    zoom_tool.handle_input(drag)

    assert_true(view.zoom > 1.0, "Dragging up zooms in")
    var after := (at - view.pan) / view.zoom
    assert_almost_eq(after.x, before.x, 1e-3, "about the point that was pressed")
    assert_almost_eq(after.y, before.y, 1e-3, "on both axes")

    surface.easel.free()


# ---------------------------------------------------------------------------
# Rotation, item 7
# ---------------------------------------------------------------------------


## The pivot stays at the origin and the pan absorbs the turn, so whatever was
## under the anchor is still under it, at any zoom and from any rotation.
func test_rotating_at_a_point_keeps_that_document_point_under_it() -> void:
    var view := _fake_view()
    view.zoom = 1.5
    view.pan = Vector2(120, 80)
    view.rotation = 0.3
    var anchor := Vector2(640, 420)
    var before := view.screen_to_document(anchor)

    view.rotate_at(1.1, anchor)

    assert_almost_eq(view.rotation, 1.1, 1e-6, "The rotation is what was asked for")
    var after := view.screen_to_document(anchor)
    assert_almost_eq(after.x, before.x, 1e-3, "and the document point under the anchor has not moved in x")
    assert_almost_eq(after.y, before.y, 1e-3, "nor in y")
    var back := view.document_to_screen(after)
    assert_almost_eq(back.x, anchor.x, 1e-3, "and the two conversions are inverses")


func test_zooming_under_a_rotation_still_pins_the_anchor() -> void:
    var view := _fake_view()
    view.rotation = -0.7
    view.pan = Vector2(300, 300)
    var anchor := Vector2(200, 700)
    var before := view.screen_to_document(anchor)

    view.zoom_at(2.5, anchor)

    var after := view.screen_to_document(anchor)
    assert_almost_eq(after.x, before.x, 1e-3, "Rotation does not break the anchored zoom in x")
    assert_almost_eq(after.y, before.y, 1e-3, "nor in y")


func test_a_rotation_near_a_right_angle_snaps_onto_it() -> void:
    assert_almost_eq(SaView.snap_rotation(PI / 2.0 + deg_to_rad(2.0)), PI / 2.0, 1e-9, "Two degrees off a quarter turn snaps")
    assert_almost_eq(SaView.snap_rotation(deg_to_rad(-3.0)), 0.0, 1e-9, "and so does three degrees off straight")
    assert_almost_eq(SaView.snap_rotation(deg_to_rad(30.0)), deg_to_rad(30.0), 1e-9, "Thirty degrees is left alone")
    assert_almost_eq(absf(SaView.snap_rotation(deg_to_rad(178.0))), PI, 1e-9, "and the half turn is a right angle too")


func test_centre_and_fit_account_for_the_rotation() -> void:
    var view := _fake_view()
    view.rotation = PI / 2.0
    view.zoom = 1.0

    view.center(Vector2i(200, 100))
    var middle := view.document_to_screen(Vector2(100, 50))
    assert_almost_eq(middle.x, 500.0, 1e-3, "The document's centre sits in the middle of the view")
    assert_almost_eq(middle.y, 400.0, 1e-3, "at a quarter turn")

    # Turned a quarter, a 1600 by 200 document is 200 wide and 1600 tall, so it
    # is the view's 800 height that limits it, not its 1000 width.
    view.fit(Vector2i(1600, 200))
    assert_almost_eq(view.zoom, 0.5, 1e-6, "Fit measures the rotated bounding box")


func test_reset_rotation_brings_the_view_straight_about_the_anchor() -> void:
    var view := _fake_view()
    view.rotation = 0.9
    view.pan = Vector2(50, 50)
    var anchor := Vector2(500, 400)
    var before := view.screen_to_document(anchor)

    view.rotate_at(0.0, anchor)

    assert_almost_eq(view.rotation, 0.0, 1e-9, "Straight again")
    var after := view.screen_to_document(anchor)
    assert_almost_eq(after.x, before.x, 1e-3, "with the anchor still over the same document point")


## Shift plus a middle drag turns the view about the press, by the angle the
## pointer swings around it, and the tool sees none of it.
func test_a_shift_middle_drag_rotates_about_the_press() -> void:
    var surface := Fixtures.make_surface()
    var view := surface.view as SaTestFixtures.FakeView
    var pair := _machine(surface)
    var tm: ToolMachine = pair[0]
    var tool: SaTestFixtures.FakeTool = pair[1]
    var pivot := Vector2(500, 500)
    var under_pivot := view.screen_to_document(pivot)

    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_MIDDLE
    press.pressed = true
    press.shift_pressed = true
    press.position = pivot
    tm.handle_input(press)

    # The lever is set by the first motion far enough from the pivot, then a
    # swing from three o'clock to six o'clock is a quarter turn clockwise.
    for at: Vector2 in [Vector2(600, 500), Vector2(571, 571), Vector2(500, 600)]:
        var motion := InputEventMouseMotion.new()
        motion.position = at
        tm.handle_input(motion)

    assert_almost_eq(view.rotation, PI / 2.0, 1e-6, "A quarter swing is a quarter turn, snapped exactly")
    var after := view.screen_to_document(pivot)
    assert_almost_eq(after.x, under_pivot.x, 1e-3, "about the press")
    assert_almost_eq(after.y, under_pivot.y, 1e-3, "on both axes")
    assert_true(tool.events.is_empty(), "and the tool saw nothing")

    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_MIDDLE
    release.pressed = false
    tm.handle_input(release)
    var after_motion := InputEventMouseMotion.new()
    after_motion.position = Vector2(500, 400)
    tm.handle_input(after_motion)
    assert_almost_eq(view.rotation, PI / 2.0, 1e-6, "Motion after the release turns nothing")

    Fixtures.teardown(surface, tm)


## A key going down or up, with Shift on the event while it is held, as a
## keyboard sends it.
func _held(keycode: Key, pressed: bool, shift: bool) -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = keycode
    key.physical_keycode = keycode
    key.pressed = pressed
    key.shift_pressed = shift
    return key


## A left button going down or up at *at*, as a pen's tip or a mouse sends it.
func _left(at: Vector2, pressed: bool, shift: bool) -> InputEventMouseButton:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = pressed
    button.shift_pressed = shift
    button.position = at
    button.global_position = at
    return button


## Shift and Space held with a pen drag turn the view, where Krita turns it, and
## do not pan. Space holds the pan tool,
## which asks for the turn, so a Shift left drag turns the view about the
## press by the swing the Shift middle drag above makes, through the same
## `SaViewDrag`, and the pan tool sees none of it.
func test_shift_space_and_a_drag_rotate_about_the_press() -> void:
    var surface := Fixtures.make_surface()
    var view := surface.view as SaTestFixtures.FakeView
    var tm := Fixtures.make_bound_machine(surface)
    tm.set_active_tool(&"brush")
    var pivot := Vector2(500, 500)
    var under_pivot := view.screen_to_document(pivot)

    tm.handle_input(_held(KEY_SHIFT, true, true))
    tm.handle_input(_held(KEY_SPACE, true, true))
    assert_eq(tm.active_tool_name, &"pan", "Shift and Space hold the pan tool")
    var pan_tool := tm.get_tool(&"pan")
    tm.handle_input(_left(pivot, true, true))
    for at: Vector2 in [Vector2(600, 500), Vector2(571, 571), Vector2(500, 600)]:
        var motion := InputEventMouseMotion.new()
        motion.position = at
        motion.relative = Vector2(-30, 30)
        tm.handle_input(motion)

    assert_almost_eq(view.rotation, PI / 2.0, 1e-6, "A quarter swing is a quarter turn, as the middle drag's is")
    var after := view.screen_to_document(pivot)
    assert_almost_eq(after.x, under_pivot.x, 1e-3, "about the press")
    assert_almost_eq(after.y, under_pivot.y, 1e-3, "on both axes")
    assert_false(bool(pan_tool.get("is_panning")), "and the pan tool never saw the press")

    tm.handle_input(_left(Vector2(500, 600), false, true))
    var after_motion := InputEventMouseMotion.new()
    after_motion.position = Vector2(500, 400)
    tm.handle_input(after_motion)
    assert_almost_eq(view.rotation, PI / 2.0, 1e-6, "Motion after the release turns nothing")

    # Without Shift the same drag is the pan it always was, and turns nothing.
    tm.handle_input(_held(KEY_SHIFT, false, false))
    assert_eq(tm.active_tool_name, &"pan", "Space alone still holds the pan tool")
    var pan_before := view.get_pan()
    tm.handle_input(_left(pivot, true, false))
    var drag := InputEventMouseMotion.new()
    drag.position = pivot + Vector2(40, 0)
    drag.relative = Vector2(40, 0)
    tm.handle_input(drag)
    tm.handle_input(_left(drag.position, false, false))
    assert_almost_eq(view.get_pan().x - pan_before.x, 40.0, 1e-6, "Space and a drag pans by the drag")
    assert_almost_eq(view.rotation, PI / 2.0, 1e-6, "and leaves the turn where it was")

    tm.handle_input(_held(KEY_SPACE, false, false))
    Fixtures.teardown(surface, tm)


## Under the brush a Shift left drag is still the size, and turns nothing: the
## turn is the pan tool's to ask for, not every tool's.
func test_a_shift_drag_under_the_brush_sizes_it_and_turns_nothing() -> void:
    var surface := Fixtures.make_surface()
    var view := surface.view as SaTestFixtures.FakeView
    var tm := Fixtures.make_bound_machine(surface)
    tm.set_active_tool(&"brush")
    var settings: Resource = tm.get_tool(&"brush").get("settings")
    var radius_before: float = settings.radius

    tm.handle_input(_left(Vector2(500, 500), true, true))
    for at: Vector2 in [Vector2(600, 500), Vector2(571, 571), Vector2(650, 600)]:
        var motion := InputEventMouseMotion.new()
        motion.position = at
        motion.global_position = at
        tm.handle_input(motion)
    tm.handle_input(_left(Vector2(650, 600), false, true))
    tm.tell_moved_size()

    assert_almost_eq(view.rotation, 0.0, 1e-6, "The brush's Shift drag turns nothing")
    assert_true(settings.radius > radius_before, "and sizes the brush")
    Fixtures.teardown(surface, tm)


## The Gestures rows list both turns, so the Shift middle drag that turns the
## view is not a gesture a painter has to know without being told.
func test_the_gestures_rows_list_both_turns() -> void:
    var chords: Array = []
    for gesture: Array in SaShortcutRows.GESTURES:
        chords.append(gesture[0])
    assert_true(chords.has("Shift + middle drag"), "The Gestures rows list the Shift middle drag: %s" % str(chords))
    assert_true(chords.has("Shift + Space + drag"), "and the Shift and Space drag")


func test_ctrl_brackets_rotate_a_step_and_the_bare_brackets_do_not() -> void:
    var surface := Fixtures.make_surface()
    var view := surface.view as SaTestFixtures.FakeView
    var tm: ToolMachine = _machine(surface)[0]
    var router := ShortcutRouter.new()
    router.tool_machine_provider = func() -> ToolMachine: return tm
    # The zoom, rotate and interface chords are registered commands,
    # so a router with no registry answers none of them.
    router.bind_commands(SaCommandRegistry.new())

    assert_true(router.handle(_chord(KEY_BRACKETRIGHT, false)), "Ctrl+] is taken")
    assert_almost_eq(view.rotation, SaView.ROTATION_STEP, 1e-6, "as one step clockwise")
    assert_true(router.handle(_chord(KEY_BRACKETLEFT, false)), "Ctrl+[ is taken")
    assert_almost_eq(view.rotation, 0.0, 1e-6, "as one step back")

    # The physical keycode as well as the keycode, because project.godot binds
    # the two brush size actions physically and an event carrying only the
    # keycode matches neither, which made this half of the check vacuous.
    for keycode: Key in [KEY_BRACKETRIGHT, KEY_BRACKETLEFT]:
        var bare := InputEventKey.new()
        bare.keycode = keycode
        bare.physical_keycode = keycode
        bare.pressed = true
        assert_true(router.handle(bare), "The bare bracket is taken, by the brush")
        assert_almost_eq(view.rotation, 0.0, 1e-6, "and not by the view")

    router.free()
    Fixtures.teardown(surface, tm)


# ---------------------------------------------------------------------------
# The brush size brackets, in every shape a keyboard sends them
# ---------------------------------------------------------------------------


## One bracket keypress, in the shape a given keyboard would send it.
##
## `shape` is `physical`, `keycode` or `label`, and the three are what
## `project.godot` binding by physical keycode alone could not tell apart. An
## event carrying only the character is what a layout that needs AltGr for a
## bracket produces.
func _bracket(keycode: int, shape: String, alt: bool = false, ctrl: bool = false) -> InputEventKey:
    var key := InputEventKey.new()
    if shape == "physical":
        key.physical_keycode = keycode as Key
    elif shape == "keycode":
        key.keycode = keycode as Key
    else:
        key.key_label = keycode as Key
        key.unicode = keycode
    key.alt_pressed = alt
    key.ctrl_pressed = ctrl
    key.pressed = true
    return key


## The bracket rule, held here so a later profile switch cannot drop it:
## a bracket is a bracket whichever field of the event carries it, and the
## modifier a layout needs to type one is not a chord.
##
## Without the rule every row below reaches nothing except the first.
## `scenarios/brush-size-brackets-2.json` is the same six rows on the running
## app, with the size in each dump.
func test_every_shape_of_a_bracket_steps_the_brush_size() -> void:
    var cases: Array = [
        ["physical", false, false, 1, "The physical position alone, which is what project.godot binds"],
        ["keycode", false, false, 1, "The keycode alone, which the binding could not match"],
        ["label", true, false, 1, "The character with AltGr held, which is a Czech layout's bracket"],
        ["label", true, true, 1, "and the same key when the compositor reports AltGr as Ctrl with ALT"],
        ["label", false, false, -1, "The left bracket as a character steps down"],
        ["physical", true, false, -1, "and with AltGr held it still steps down"],
    ]
    for case: Array in cases:
        var keycode: int = KEY_BRACKETRIGHT if int(case[3]) > 0 else KEY_BRACKETLEFT
        var event := _bracket(keycode, String(case[0]), bool(case[1]), bool(case[2]))
        assert_eq(SaShortcutKeys.brush_size_direction(event), int(case[3]), String(case[4]))


## What the widening does not reach, which is the other half of the rule.
##
## Ctrl alone has to stay the view rotation, because `_handle_brush` runs before
## the command registry and would otherwise take `Ctrl+]` from it. That is the
## one modifier combination the app already spends on these two keys.
func test_the_widening_stops_at_the_chords_that_mean_something_else() -> void:
    assert_eq(
        SaShortcutKeys.brush_size_direction(_bracket(KEY_BRACKETRIGHT, "physical", false, true)),
        0,
        "Ctrl and a bracket is the view rotation, not the brush"
    )
    var meta := _bracket(KEY_BRACKETRIGHT, "physical")
    meta.meta_pressed = true
    assert_eq(SaShortcutKeys.brush_size_direction(meta), 0, "and Super with anything belongs to the desktop")

    var released := _bracket(KEY_BRACKETRIGHT, "physical")
    released.pressed = false
    assert_eq(SaShortcutKeys.brush_size_direction(released), 0, "A keyup steps nothing")

    var other := _bracket(KEY_P, "physical")
    assert_eq(SaShortcutKeys.brush_size_direction(other), 0, "and a key that is not a bracket is not one")


## The half that is not matching at all: ALT is `tool_eyedropper_quick`,
## so by the time the router asks to resize, the eyedropper is the active tool
## and has no radius. The size the painter meant is the permanent tool's.
func test_altgr_resizes_the_permanent_tool_rather_than_the_quick_one() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var brush_settings: Resource = machine.get_tool(&"brush").get("settings")
    var before: float = brush_settings.radius

    machine.set_active_tool(&"brush")
    machine.active_tool = machine.get_tool(&"eyedropper")
    var step := SaShortcutKeys.brush_size_step(before, 1)
    SaShortcutKeys.nudge_brush_radius(machine, step)

    assert_almost_eq(
        brush_settings.radius,
        SaShortcutKeys.brush_size_step(before, 1) + before,
        1e-6,
        "The eyedropper has no radius, so the step lands on the tool the painter is holding"
    )

    machine.set_active_tool(&"transform")
    var held: float = brush_settings.radius
    SaShortcutKeys.nudge_brush_radius(machine, step)
    assert_almost_eq(brush_settings.radius, held, 1e-6, "but a permanent tool with no radius gets silence, not the brush's size")

    Fixtures.teardown(surface, machine)
