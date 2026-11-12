## A detour tool's shortcut pressed again goes back to the tool before it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Ctrl+T is a toggle, and so are the other tools where it fits. Those are the Transform, the
## Crop, the Eyedropper, Pan, Zoom and the four selection tools, and not the
## Brush, the Fill or the Gradient, which are where a painter goes back to. A
## pending Transform or Crop is dropped on the way back as Escape drops it,
## because only Enter commits.
##
## Every chord goes in through `handle_viewport_input`, the door
## `Main._unhandled_input` hands the main window's keys to, and is the one the
## shortcut table holds for the tool's action, so a profile or a rebind moves
## the press with it. The machine is the bound one the base module's suites
## use, holding both modules of `sara-base-modules` with their real
## descriptors. The running app is
## `scenarios/a-detour-tool-s-shortcut-pressed-again-goes-back-to-the-tool-before-it.json`.
extends "res://tests/test_framework.gd"

## Chunks are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateCropScript = preload("res://modules/sara-base-modules/base/tools/state_crop.gd")

const PAINT := Color(0.5, 0.4, 0.3, 1.0)
## Inside the selection the Transform lifts, and inside the first chunk.
const PROBE := Vector2i(60, 60)
const SELECTED := Rect2i(40, 40, 100, 100)

## The tools whose chord pressed again goes back, by the row's ruling.
const DETOURS: Array[StringName] = [
    &"transform", &"crop", &"eyedropper", &"pan", &"zoom", &"marquee", &"ellipse_select", &"lasso", &"wand"
]
## The tools a painter goes back to, whose chord pressed again keeps them.
const HOMES: Array[StringName] = [&"brush", &"bucket_fill", &"gradient"]

## A chord no shipped action holds, for the Transform rebound and for Zoom,
## which ships with none on Sara's own map.
const SPARE_CHORD := "Ctrl+Alt+K"

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _router: ShortcutRouter = null
## Action -> the chords it had before a case rebound it.
var _shipped: Dictionary = {}


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(1024, 1024))
    _machine = Fixtures.make_bound_machine(_surface)
    _router = ShortcutRouter.new()
    _router.canvas_provider = func() -> SaCanvas: return null
    var machine := _machine
    _router.tool_machine_provider = func() -> ToolMachine: return machine
    _machine.set_active_tool(&"brush")


func after_each() -> void:
    for action: StringName in _shipped:
        SaShortcutStore.set_chords(action, _shipped[action])
    _shipped = {}
    _router.free()
    _router = null
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


## Gives *action* *chord* for this case, keeping what it had for `after_each`.
func _rebind(action: StringName, chord: String) -> void:
    if not _shipped.has(action):
        _shipped[action] = SaShortcutStore.chords_for(action)
    SaShortcutStore.set_chords(action, [chord])


## A press of the first key the table holds for *action*, as a keyboard sends it.
static func _chord_of(action: StringName) -> InputEventKey:
    for event: InputEvent in InputMap.action_get_events(action):
        if event is InputEventKey:
            var key := event.duplicate() as InputEventKey
            key.pressed = true
            return key
    return null


static func _press_of(chord: String) -> InputEventKey:
    var key := SaShortcutStore.parse_chord(chord)
    key.pressed = true
    return key


## A key over the canvas, as `Main._unhandled_input` hands it on.
func _press(event: InputEvent) -> void:
    _router.handle_viewport_input(event, null)


## The hand lifted off *event*'s key and then off its modifiers, as a keyboard
## sends it. The machine counts a modifier held until its own key is let go,
## and Ctrl or ALT left held is the quick Eyedropper in the hand.
func _let_go(event: InputEventKey) -> void:
    var up := event.duplicate() as InputEventKey
    up.pressed = false
    up.echo = false
    up.ctrl_pressed = false
    up.alt_pressed = false
    up.shift_pressed = false
    up.meta_pressed = false
    _press(up)
    for held: Array in [[event.ctrl_pressed, KEY_CTRL], [event.alt_pressed, KEY_ALT], [event.shift_pressed, KEY_SHIFT]]:
        if held[0]:
            var modifier := InputEventKey.new()
            modifier.keycode = held[1]
            modifier.physical_keycode = held[1]
            _press(modifier)


## A press and its release.
func _tap(event: InputEventKey) -> void:
    _press(event)
    _let_go(event)


func _press_chord_of(tool_id: StringName) -> void:
    var descriptor := _machine.get_descriptor(tool_id)
    var key := _chord_of(descriptor.activate_action)
    assert_not_null(key, "%s has a chord to press" % tool_id)
    if key != null:
        _tap(key)


func _layer() -> SaLayer:
    return _surface.get_document().active_layer


func _steps() -> int:
    return _surface.get_document().history.step_count()


static func _texel(layer: SaLayer, at: Vector2i) -> Color:
    var texture := layer.get_field(Vector2i.ZERO)
    if texture == null:
        return Color(0.0, 0.0, 0.0, 0.0)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


## A press at *from* and a motion to *to*, in document pixels, the hand still
## down, so what the drag started stays in the air.
func _drag(from: Vector2, to: Vector2) -> void:
    var view := _surface.view as Fixtures.FakeView
    view.mouse_position = from
    _machine.active_tool.handle_input(_button(true))
    view.mouse_position = to
    _machine.active_tool.handle_input(InputEventMouseMotion.new())


## The detour set, read off the descriptors the base module registers.
func test_the_detours_are_the_ones_the_row_names() -> void:
    for tool_id: StringName in DETOURS:
        assert_true(_machine.get_descriptor(tool_id).is_detour, "%s is a detour" % tool_id)
    for tool_id: StringName in HOMES:
        assert_false(_machine.get_descriptor(tool_id).is_detour, "%s is where a painter goes back to" % tool_id)


## Ctrl+T from the Brush, a selection lifted and moved, and Ctrl+T again: the
## Brush is back, the hole the lift cut is filled again, and no step was
## written.
func test_ctrl_t_again_puts_a_lifted_selection_back_and_hands_the_brush_back() -> void:
    var layer := _layer()
    layer.get_or_create_chunk(Vector2i.ZERO).clear(PAINT)
    _surface.get_document().selection.select_rect(SELECTED)
    var before := _texel(layer, PROBE)
    var steps := _steps()
    var brush := _machine.default_tool_name

    _press_chord_of(&"transform")
    assert_eq(_machine.active_tool_name, &"transform", "Ctrl+T picks the Transform")
    _drag(Vector2(PROBE), Vector2(PROBE) + Vector2(300.0, 0.0))
    assert_true(_machine.active_tool.is_moving(), "the drag lifted the selection")
    assert_true(_texel(layer, PROBE).a < 0.01, "and cut a hole in the layer where it was")

    _press_chord_of(&"transform")
    assert_eq(_machine.default_tool_name, brush, "Ctrl+T again goes back to the Brush")
    assert_eq(_machine.active_tool_name, brush, "which is the tool in the hand")
    assert_false(_machine.get_tool(&"transform").is_moving(), "nothing is in the air")
    assert_eq(_texel(layer, PROBE), before, "the layer's texel is as it was before the lift")
    assert_eq(_steps(), steps, "and no step was written")


## Ctrl+T with nothing selected moves the layer's live transform, and Ctrl+T
## again draws the map the session opened on.
func test_ctrl_t_again_puts_a_live_move_back() -> void:
    var layer := _layer()
    layer.get_or_create_chunk(Vector2i.ZERO).clear(PAINT)
    var before := _texel(layer, PROBE)
    var map_before: Variant = layer.live_transform
    var steps := _steps()
    var brush := _machine.default_tool_name

    _press_chord_of(&"transform")
    _drag(Vector2(100.0, 100.0), Vector2(400.0, 100.0))
    assert_true(_machine.active_tool.holds_session(), "the drag moved the layer's map")

    _press_chord_of(&"transform")
    assert_eq(_machine.default_tool_name, brush, "Ctrl+T again goes back to the Brush")
    assert_eq(layer.live_transform, map_before, "the layer is drawn by the map it had")
    assert_eq(_texel(layer, PROBE), before, "its texels never moved")
    assert_eq(_steps(), steps, "and no step was written")


## C from the Brush, a crop dragged and shown on the layer, and C again: the
## Brush is back, the rectangle gone and the layer shown as it was.
func test_c_again_drops_a_pending_crop_and_hands_the_brush_back() -> void:
    var layer := _layer()
    layer.get_or_create_chunk(Vector2i.ZERO).clear(PAINT)
    # The crop is the skeleton's live transform, reached through the role
    # registry a bare machine does not hand the tool.
    var crop := _machine.get_tool(&"crop") as StateCropScript
    crop.roles = Fixtures.make_registries().roles
    crop.mode = StateCropScript.Mode.LAYER  # Canvas is the default.
    var before := _texel(layer, PROBE)
    var map_before: Variant = layer.live_transform
    var steps := _steps()
    var brush := _machine.default_tool_name

    _press_chord_of(&"crop")
    assert_eq(_machine.active_tool_name, &"crop", "C picks the Crop")
    _drag(Vector2(20.0, 20.0), Vector2(120.0, 90.0))
    crop.handle_input(_button(false))
    assert_eq(crop.pending_rect(), Rect2i(20, 20, 100, 70), "the drag left a rectangle")
    assert_true(crop.holds_session(), "and the layer shows the crop")

    _press_chord_of(&"crop")
    assert_eq(_machine.default_tool_name, brush, "C again goes back to the Brush")
    var canvas := Rect2i(Vector2i.ZERO, crop.surface.get_document().canvas_size)
    assert_eq(crop.pending_rect(), canvas, "the rectangle is gone, the box back on the canvas")
    assert_false(crop.holds_session(), "no session is open")
    assert_eq(layer.live_transform, map_before, "the layer is shown as it was")
    assert_eq(_texel(layer, PROBE), before, "its texels never moved")
    assert_eq(_steps(), steps, "and no step was written")


## Every detour's chord twice from the Brush leaves the Brush in the hand.
## Zoom ships with no chord on Sara's own map, and Ellipse Select has none
## since the Patch tool took its J, so each is lent the spare
## chord while it is pressed and gives it back after.
func test_each_detour_s_chord_twice_from_the_brush_goes_back_to_the_brush() -> void:
    assert_true(SaShortcutStore.holders(SPARE_CHORD).is_empty(), "%s is nobody's chord" % SPARE_CHORD)
    var brush := _machine.default_tool_name
    for tool_id: StringName in DETOURS:
        var action := _machine.get_descriptor(tool_id).activate_action
        var lent := SaShortcutStore.chords_for(action).is_empty()
        if lent:
            _rebind(action, SPARE_CHORD)
        _press_chord_of(tool_id)
        assert_eq(_machine.default_tool_name, tool_id, "%s's chord picks it" % tool_id)
        _press_chord_of(tool_id)
        assert_eq(_machine.default_tool_name, brush, "%s's chord again goes back to the Brush" % tool_id)
        if lent:
            SaShortcutStore.set_chords(action, [])


## B twice keeps the Brush, and the Fill's and the Gradient's chords twice
## keep them, because nothing is before a tool a painter goes back to.
func test_b_twice_keeps_the_brush_and_no_home_tool_toggles() -> void:
    var brush := _machine.default_tool_name
    _press_chord_of(&"brush")
    assert_eq(_machine.default_tool_name, brush, "B keeps the Brush")
    _press_chord_of(&"brush")
    assert_eq(_machine.default_tool_name, brush, "and B again still does")
    for tool_id: StringName in [&"gradient"]:
        _press_chord_of(tool_id)
        _press_chord_of(tool_id)
        assert_eq(_machine.default_tool_name, tool_id, "%s's chord twice keeps it" % tool_id)


## A held key repeats its press, and the repeat is nobody's toggle.
func test_a_held_chord_does_not_flick_back() -> void:
    var brush := _machine.default_tool_name
    var key := _chord_of(&"tool_transform")
    _press(key)
    var repeat := key.duplicate() as InputEventKey
    repeat.echo = true
    _press(repeat)
    _let_go(key)
    assert_eq(_machine.default_tool_name, &"transform", "the repeat of Ctrl+T leaves the Transform in the hand")
    _tap(key)
    assert_eq(_machine.default_tool_name, brush, "and a second press goes back")


## A detour picked from another detour goes back to that one, the tool before
## it, rather than to the Brush.
func test_a_detour_from_a_detour_goes_back_to_it() -> void:
    _press_chord_of(&"transform")
    _press_chord_of(&"marquee")
    assert_eq(_machine.default_tool_name, &"marquee", "M from the Transform picks the Marquee")
    _press_chord_of(&"marquee")
    assert_eq(_machine.default_tool_name, &"transform", "and M again goes back to the Transform")


## The Transform rebound: the old chord picks nothing, and the new one toggles
## as Ctrl+T did, a lift in the air put back as before.
func test_a_rebound_chord_toggles_the_same_way() -> void:
    var old_chord := _chord_of(&"tool_transform")
    assert_true(SaShortcutStore.holders(SPARE_CHORD).is_empty(), "%s is nobody's chord" % SPARE_CHORD)
    _rebind(&"tool_transform", SPARE_CHORD)
    var layer := _layer()
    layer.get_or_create_chunk(Vector2i.ZERO).clear(PAINT)
    _surface.get_document().selection.select_rect(SELECTED)
    var before := _texel(layer, PROBE)
    var steps := _steps()
    var brush := _machine.default_tool_name

    _tap(old_chord)
    assert_eq(_machine.default_tool_name, brush, "Ctrl+T rebound away picks nothing")
    _tap(_press_of(SPARE_CHORD))
    assert_eq(_machine.default_tool_name, &"transform", "%s picks the Transform" % SPARE_CHORD)
    _drag(Vector2(PROBE), Vector2(PROBE) + Vector2(300.0, 0.0))
    assert_true(_machine.active_tool.is_moving(), "the drag lifted the selection")
    _tap(_press_of(SPARE_CHORD))
    assert_eq(_machine.default_tool_name, brush, "and %s again goes back to the Brush" % SPARE_CHORD)
    assert_eq(_texel(layer, PROBE), before, "with the lift put back")
    assert_eq(_steps(), steps, "and no step written")
