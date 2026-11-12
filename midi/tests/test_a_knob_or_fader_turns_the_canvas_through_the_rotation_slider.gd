## Map to MIDI binds the canvas Rotation slider on the top bar, as it binds the
## brush's size. The slider names its value like every other dial, so a click on
## it is a dial, a control change turns the canvas to where the knob stands, and
## a fader that sends pitch bend does the same.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The bar's own slider, built by `SaTopBarRotation.attach` over a fake view, so
## the turn is read off the view the way the bar turns it.
extends "res://tests/test_framework.gd"

const Midi := preload("res://modules/sara-base-modules/midi/midi.gd")
const Fixtures = preload("res://tests/fixtures.gd")

var _host: HBoxContainer = null
var _pair: SaTopBarRotation = null
var _view: SaView = null
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
    _host = HBoxContainer.new()
    _host.name = "MidiRotationHost"
    EventBus.add_child(_host)
    _view = Fixtures.FakeView.new()
    _pair = SaTopBarRotation.new(_view)
    _pair.attach(_host)
    _pair.follow()
    _midi = Midi.new(ProbePorts.new(), null, Midi.Bindings.new(Midi.Preferences.new(), SaAppDrive.new(Callable())))
    _midi.listen(true)


func after_each() -> void:
    _midi = null
    _pair = null
    if _host != null:
        _host.free()
        _host = null


func _bind(message: InputEventMIDI) -> void:
    _midi.learning.start()
    assert_true(_midi.learning.pick(_pair.slider), "the rotation slider is a dial, not a refusal")
    _midi.hear(message)


func test_a_click_on_the_rotation_slider_picks_a_dial_called_rotate() -> void:
    _midi.learning.start()
    assert_true(_midi.learning.pick(_pair.slider), "it can be mapped")
    assert_eq(String(_midi.learning.picked["kind"]), "dial", "a dial")
    assert_eq(String(_midi.learning.picked["target"]), "view/rotation", "of the canvas view's angle")
    assert_eq(String(_midi.learning.picked["label"]), "Rotate", "under the word the slider shows")


func test_a_knob_turns_the_canvas() -> void:
    var knob := InputEventMIDI.new()
    knob.message = MIDI_MESSAGE_CONTROL_CHANGE
    knob.controller_number = 9
    knob.controller_value = 64
    _bind(knob)
    assert_eq(_midi.bindings.listed().size(), 1, "the knob is bound")
    knob.controller_value = 127
    _midi.hear(knob)
    _midi.bindings.flush()
    # 180 and -180 are one angle and the view wraps onto the second.
    assert_almost_eq(absf(rad_to_deg(_view.get_rotation())), 180.0, 0.01, "the top of the knob is a half turn")
    assert_almost_eq(absf(_pair.slider.value), 180.0, 0.01, "and the slider follows")


func test_a_fader_that_sends_pitch_bend_turns_the_canvas() -> void:
    var fader := InputEventMIDI.new()
    fader.message = MIDI_MESSAGE_PITCH_BEND
    fader.pitch = 8192
    _bind(fader)
    assert_eq(_midi.bindings.listed().size(), 1, "the fader is bound")
    fader.pitch = 12192  # three quarters of BEND_TOP, 16256
    _midi.hear(fader)
    _midi.bindings.flush()
    assert_almost_eq(rad_to_deg(_view.get_rotation()), 90.0, 1.0, "three quarters of the fader is 90 degrees")
