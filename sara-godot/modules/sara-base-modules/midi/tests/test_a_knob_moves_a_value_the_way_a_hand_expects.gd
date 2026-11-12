## A knob moves a value the way a hand expects. An absolute
## control is picked up rather than jumped to once the value moved another way,
## an endless encoder steps the dial up and down, only the last message of a
## control in a frame is applied, a turn of the layer's opacity is one undo step
## closed once the control rests, and the corner names the value moved.
##
## Built the way the app builds it: the base modules registered through the door,
## a machine bound to their registry, the resolver over that machine and the
## bindings over a settings node of the suite's own, so no suite opens the
## machine's MIDI inputs or touches the painter's profile. The drive is reached
## through [method Midi.Bindings.drive_control] and its frame's end is reached
## by hand, [method Midi.Bindings.flush], since a suite runs inside one frame.
extends "res://tests/test_framework.gd"

const Midi := preload("res://modules/sara-base-modules/midi/midi.gd")

## The machine builds every tool, which needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")

const SIZE := &"tool/brush/radius"
const OPACITY := SaAppDrive.LAYER_OPACITY

## Longer than the half second a control rests before its turn is closed.
const PAST_THE_REST_MS := 600

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _host: Node = null
var _values: SaAppDrive = null
var _bindings: Midi.Bindings = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    _modules.clear()
    for script: GDScript in [StampModuleScript, BaseModuleScript]:
        var module: SaModule = script.new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)
    _machine.set_active_tool(&"brush")
    _host = Node.new()
    _host.name = "MidiKnobHost"
    EventBus.add_child(_host)
    var machine := _machine
    _values = SaAppDrive.new(func() -> ToolMachine: return machine)
    _bindings = Midi.Bindings.new(Midi.Preferences.new(), _values)


func after_each() -> void:
    _bindings = null
    _values = null
    if _host != null:
        EventBus.remove_child(_host)
        _host.free()
        _host = null
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    for module: SaModule in _modules:
        module.unregister(_registries.context)
        _registries.context.for_module(module.get_id()).remove_all_registrations()
    _modules.clear()
    _registries = null


func _document() -> SaDocument:
    return _surface.get_document()


func _size() -> float:
    return float(_machine.get_tool(&"brush").get("settings").radius)


## Binds control 7 on channel 0 of the mixer to *target*.
func _bind_control(target: StringName, label: String) -> void:
    _bindings.bind("Knob", "control/0/7", {"kind": "dial", "target": String(target), "label": label})


## One control change, and the frame's end after it, as a fader resting between
## messages never quite does in a suite.
func _turn(value: int) -> void:
    _bindings.drive_control("Knob", 0, 7, value)
    _bindings.flush()


## The Done when: the control is picked up rather than jumped to. The brush's
## size is moved by the keyboard after the control has it, the control below the
## new size changes nothing, and the control past it takes the size up.
func test_an_absolute_control_is_picked_up_rather_than_jumped_to() -> void:
    _bind_control(SIZE, "Size (brush)")
    _turn(64)
    var synced := _size()
    SaShortcutKeys.nudge_brush_radius(_machine, synced * 0.25)
    var moved := _size()
    assert_true(moved > synced, "the size moved another way, as the keyboard moves it: %f -> %f" % [synced, moved])

    _turn(50)
    assert_almost_eq(_size(), moved, 1e-9, "a control below the new size changes nothing until it passes it")
    _turn(75)
    assert_true(_size() > moved, "a control past the new size takes it up from there")


## The Done when: a relative binding steps the dial. One up message steps it up,
## one down message steps it down, and the two cancel.
func test_a_relative_binding_steps_the_dial_up_and_down() -> void:
    _bind_control(OPACITY, "Layer opacity")
    assert_true(_bindings.set_relative("Knob", "control/0/7", true), "the binding is marked relative")
    var layer := _document().active_layer
    _values.write(OPACITY, 0.5)
    var before := layer.opacity

    _turn(1)
    assert_true(layer.opacity > before, "an up message steps the dial up")
    var up := layer.opacity
    _turn(127)
    assert_true(layer.opacity < up, "a down message steps the dial down")
    assert_almost_eq(layer.opacity, before, 1e-6, "one step up and one step down are where it started")

    assert_eq(Midi.Bindings.relative_steps(1), 1, "1 is one step up")
    assert_eq(Midi.Bindings.relative_steps(127), -1, "127 is one step down")
    assert_eq(Midi.Bindings.relative_steps(64), 0, "64 is the middle, a step nowhere")
    assert_eq(Midi.Bindings.relative_steps(65), -63, "65 steps down 63")


## The Done when: a burst of a control's messages in one frame is one move, the
## last of them, not one move a message.
func test_only_the_last_message_of_a_control_in_a_frame_is_applied() -> void:
    _bind_control(SIZE, "Size (brush)")
    var writes: Array = []
    var counter := func() -> void: writes.append(1)
    EventBus.tool_options_moved.connect(counter)
    for value: int in [10, 30, 60, 90, 120]:
        _bindings.drive_control("Knob", 0, 7, value)
    _bindings.flush()
    EventBus.tool_options_moved.disconnect(counter)
    assert_eq(writes.size(), 1, "one write for the frame, not one a message")
    var high := _size()
    assert_almost_eq(high, float(_bindings.last_driven.get("value", 0.0)), 1e-6, "and it is the frame's last value")

    _turn(10)
    var low := _size()
    assert_true(high > low * 2.0, "the frame's last value was applied, not its first: %f then %f" % [high, low])


## The Done when: thirty values of a control on the opacity are one undo step,
## waited past the rest, and one undo puts the opacity back where the turn
## found it.
func test_a_turn_of_the_opacity_is_one_step_undone_once_after_the_rest() -> void:
    _bind_control(OPACITY, "Layer opacity")
    var layer := _document().active_layer
    _values.write(OPACITY, 0.5)
    var before := layer.opacity
    var steps := _document().undo_redo.get_history_count()

    var value := 0
    for frame: int in 6:
        for _message: int in 5:
            _bindings.drive_control("Knob", 0, 7, value)
            value += 1
        _bindings.flush()
    assert_eq(_document().undo_redo.get_history_count(), steps + 1, "the whole turn is one undo step")

    OS.delay_msec(PAST_THE_REST_MS)
    assert_true(_document().undo(), "the turn undoes")
    assert_almost_eq(layer.opacity, before, 1e-6, "and the opacity is where the turn found it")


## A turn taken up after the rest is closed is a step of its own, the Done
## when's half second made real.
func test_a_turn_after_the_rest_opens_a_step_of_its_own() -> void:
    _bind_control(OPACITY, "Layer opacity")
    var layer := _document().active_layer
    _values.write(OPACITY, 0.5)
    _turn(60)
    var steps := _document().undo_redo.get_history_count()
    var rested := layer.opacity

    OS.delay_msec(PAST_THE_REST_MS)
    _turn(90)
    assert_eq(_document().undo_redo.get_history_count(), steps + 1, "a turn after half a rest opens a step of its own")
    assert_true(_document().undo(), "which undoes alone")
    assert_almost_eq(layer.opacity, rested, 1e-6, "back to where the second turn found the opacity")


## The Done when: the corner names the value the control moves while it turns.
func test_the_corner_names_the_value_the_control_moves() -> void:
    _bind_control(SIZE, "Size (brush)")
    _turn(64)
    assert_true(bool(_bindings.last_driven.get("moved", false)), "the size moved")
    assert_eq(
        String(_bindings.last_driven.get("said", "")),
        "Size (brush): %s" % String.num(_size(), 3),
        "the corner names the value moved and where it stands"
    )


## Preferences > MIDI marks a binding relative, and the mark is kept in the
## profile and read back by the binding's drive.
func test_the_midi_page_marks_a_binding_relative() -> void:
    _bind_control(SIZE, "Size (brush)")
    var midi := Midi.new(null, null, _bindings)
    var page := Midi.preferences_page(midi)
    _host.add_child(page)
    var toggle := page.find_child("RelativeBinding", true, false) as CheckButton
    assert_not_null(toggle, "the binding's line has a Relative switch")
    assert_false(toggle.button_pressed, "off until it is marked")

    toggle.set_pressed_no_signal(true)
    toggle.toggled.emit(true)
    assert_eq(bool(_bindings.find("Knob", "control/0/7").get("relative", false)), true, "the switch marks the binding")
    var toggle_again := page.find_child("RelativeBinding", true, false) as CheckButton
    assert_true(toggle_again.button_pressed, "and the line drawn again shows it on")

    toggle_again.set_pressed_no_signal(false)
    toggle_again.toggled.emit(false)
    assert_false(bool(_bindings.find("Knob", "control/0/7").get("relative", false)), "and off takes the mark away")

    _host.remove_child(page)
    page.free()
