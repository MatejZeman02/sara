## A fader that sends pitch bend is a control. Mixers send a fader's position as
## a pitch bend on its channel, 14 bits, so Map to MIDI binds it as it binds a
## knob, the profile keeps it, the page and the dump name it, and moving it
## drives the value at that resolution rather than cut to seven bits.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Built as the knob suite builds it: the base modules registered through the
## door, the bindings over a settings object of the suite's own, and the end of
## the frame reached by hand.
extends "res://tests/test_framework.gd"

const Midi := preload("res://modules/sara-base-modules/midi/midi.gd")

## The machine builds every tool, which needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")

const OPACITY := SaAppDrive.LAYER_OPACITY

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _values: SaAppDrive = null
var _midi: Midi = null


## Inputs that open by saying so, with one name.
class ProbePorts:
    extends Midi.Ports

    func open() -> PackedStringArray:
        return PackedStringArray()

    func close() -> void:
        pass

    func names() -> PackedStringArray:
        return PackedStringArray(["Probe Mixer"])


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
    var machine := _machine
    _values = SaAppDrive.new(func() -> ToolMachine: return machine)
    _midi = Midi.new(ProbePorts.new(), null, Midi.Bindings.new(Midi.Preferences.new(), _values))
    _midi.listen(true)


func after_each() -> void:
    _midi = null
    _values = null
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    for module: SaModule in _modules:
        module.unregister(_registries.context)
        _registries.context.for_module(module.get_id()).remove_all_registrations()
    _modules.clear()
    _registries = null


## What a fader sends: a pitch bend on a channel, its position in `pitch`.
static func _bend(channel: int, position: int) -> InputEventMIDI:
    var event := InputEventMIDI.new()
    event.message = MIDI_MESSAGE_PITCH_BEND
    event.device = 0
    event.channel = channel
    event.pitch = position
    return event


func _opacity() -> float:
    return _surface.get_document().active_layer.opacity


## Learning binds a fader that sends pitch bend, under a key of its own that
## says bend and the channel, and the page's words name it.
func test_learning_binds_a_fader_that_sends_pitch_bend() -> void:
    _midi.learning.start()
    assert_true(_midi.learning.picked.is_empty(), "nothing is picked yet")
    var slider := FactorSlider.new()
    slider.prefix = "Opacity:"
    slider.value_name = OPACITY
    assert_true(_midi.learning.pick(slider), "a slider that names its value is a dial")
    slider.free()
    _midi.hear(_bend(0, 8192))
    assert_eq(_midi.learning.step, Midi.Learning.Step.OFF, "the first bend binds and leaves learning")
    var listed := _midi.bindings.listed()
    assert_eq(listed.size(), 1, "one binding")
    assert_eq(String(listed[0]["control"]), "bend/0/0", "kept under the bend and its channel")
    assert_eq(String(listed[0]["target"]), String(OPACITY), "driving what the slider named")
    assert_eq(Midi.Bindings.control_text("bend/0/0"), "Pitch bend, channel 1", "and read as a painter reads it")
    assert_true(_midi.learning.said.contains("Pitch bend, channel 1 of Probe Mixer now drives"), _midi.learning.said)
    assert_eq(String(_midi.last_heard.get("kind", "")), "bend", "the dump's last message says bend")
    assert_eq(int(_midi.last_heard.get("value", -1)), 8192, "and its full 14-bit position")


## A bend is refused for a preset, as a control change is, and learning waits.
func test_a_bend_cannot_choose_a_preset() -> void:
    _midi.learning.start()
    var cell := Button.new()
    cell.set_meta(SaBrushPresetsChooser.PRESET_META, "Wet Ink")
    _midi.learning.pick(cell)
    cell.free()
    _midi.hear(_bend(0, 100))
    assert_eq(_midi.learning.step, Midi.Learning.Step.CONTROL, "a fader cannot choose a preset")
    assert_true(_midi.bindings.listed().is_empty(), "and nothing was bound")


## Moving a bound fader drives the value across its whole range at full
## resolution: neighbouring 14-bit positions that one 7-bit step covers give
## different values, and the ends reach the ends.
func test_a_fader_moves_the_value_at_fourteen_bits() -> void:
    _midi.bindings.bind("Probe Mixer", "bend/0/0", {"kind": "dial", "target": String(OPACITY), "label": "Layer opacity"})
    var values: Array[float] = []
    for position: int in [0, 8192, 8193, 16383]:
        _midi.hear(_bend(0, position))
        _midi.bindings.flush()
        values.append(_opacity())
    assert_almost_eq(values[0], 0.0, 1e-6, "the bottom of the fader is the bottom of the range")
    assert_almost_eq(values[1], 8192.0 / 16256.0, 1e-4, "the middle is where 14 bits put it")
    assert_true(values[2] > values[1], "one 14-bit step moves the value, which a 7-bit read would drop")
    assert_true(values[2] - values[1] < 1.0 / 127.0, "by less than a 7-bit step")
    assert_almost_eq(values[3], 1.0, 1e-6, "the top of the fader is the top of the range")
    assert_eq(String(_midi.bindings.last_driven.get("control", "")), "bend/0/0", "the dump says which control moved it")


## A mixer whose faders are seven bits in fourteen-bit clothing sends its MSB
## with the least byte 0 (raw `e0 00 7f` at the top), and its fader still
## reaches both ends of the value, where it stopped at 177 of 180 degrees.
func test_a_seven_bit_fader_sending_bend_reaches_both_ends_of_the_value() -> void:
    _midi.bindings.bind("Probe Mixer", "bend/0/0", {"kind": "dial", "target": String(OPACITY), "label": "Layer opacity"})
    var values: Array[float] = []
    for position: int in [0, 64 << 7, 127 << 7]:
        _midi.hear(_bend(0, position))
        _midi.bindings.flush()
        values.append(_opacity())
    assert_almost_eq(values[0], 0.0, 1e-6, "e0 00 00 is the minimum")
    assert_almost_eq(values[1], 0.5, 0.01, "a centred bend is the middle")
    assert_almost_eq(values[2], 1.0, 1e-6, "e0 00 7f is the maximum")
    _midi.hear(_bend(0, 16383))
    _midi.bindings.flush()
    assert_almost_eq(_opacity(), 1.0, 1e-6, "a true 14-bit fader's last steps saturate at the maximum")


## A fader on another channel and a control change on the same number drive
## nothing the bend's binding drives.
func test_only_the_bound_channel_moves_the_value() -> void:
    _midi.bindings.bind("Probe Mixer", "bend/1/0", {"kind": "dial", "target": String(OPACITY), "label": "Layer opacity"})
    var before := _opacity()
    _midi.hear(_bend(0, 16383))
    _midi.bindings.flush()
    assert_almost_eq(_opacity(), before, 1e-9, "a bend on channel 1 drives what is bound to channel 2 not at all")
    _midi.hear(_bend(1, 0))
    _midi.bindings.flush()
    assert_almost_eq(_opacity(), 0.0, 1e-6, "the bound channel does")


## The door's midi step plays a fader.
func test_the_doors_midi_step_plays_a_bend() -> void:
    _midi.bindings.bind("device 0", "bend/2/0", {"kind": "dial", "target": String(OPACITY), "label": "Layer opacity"})
    var answer := Midi.simulate({"bend": 12000, "channel": 2})
    assert_true(answer.contains("SaCapture: midi"), answer)
    assert_false(answer.contains("takes a control"), "a bend is a spec the step takes: " + answer)
    var refused := Midi.simulate({"nothing": 1})
    assert_true(refused.contains("a control, a bend or a note"), refused)


## A binding saved before bends existed still loads and still drives.
func test_a_saved_control_change_binding_still_drives() -> void:
    _midi.bindings.preferences.bindings = {
        "Probe Mixer": {"control/0/7": {"kind": "dial", "target": String(OPACITY), "label": "Layer opacity"}}
    }
    _midi.hear(_control(0, 7, 127))
    _midi.bindings.flush()
    assert_almost_eq(_opacity(), 1.0, 1e-6, "a control change binding is as it was")
    assert_eq(Midi.Bindings.control_text("control/0/7"), "Control 7, channel 1", "and reads as it did")


static func _control(channel: int, controller: int, value: int) -> InputEventMIDI:
    var event := InputEventMIDI.new()
    event.message = MIDI_MESSAGE_CONTROL_CHANGE
    event.channel = channel
    event.controller_number = controller
    event.controller_value = value
    return event
