## Sara listens to a MIDI controller when the painter turns it
## on.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The facade is handed a control change and a note on and each is read told to
## a listener with its device, channel and number, and nothing is told while
## Listen is off. Then the path a controller's message takes: through the
## engine's input to the root window, which is where the facade hears it before
## the shortcut router drops it. Then the page: its device list names the
## controllers or says in a sentence why there are none.
##
## The ports are the suite's own, so no suite opens the machine's MIDI inputs
## or touches the painter's Listen. The test machine has no controller, and
## how a real one feels is untried.
extends "res://tests/test_framework.gd"

const Midi := preload("res://modules/sara-base-modules/midi/midi.gd")

const NAMES := ["Probe Mixer", "Probe Piano"]


## Inputs that open by saying so, with the names and refusals a case gives.
class ProbePorts:
    extends Midi.Ports

    var names_given := PackedStringArray()
    var refusals_given := PackedStringArray()
    var opened: int = 0
    var closed: int = 0

    func open() -> PackedStringArray:
        opened += 1
        return refusals_given

    func close() -> void:
        closed += 1

    func names() -> PackedStringArray:
        return names_given if opened > closed else PackedStringArray()


## What a facade told, in order, one line each.
class Told:
    extends RefCounted

    var lines: Array = []

    func control(device: int, channel: int, controller: int, value: int) -> void:
        lines.append(["control", device, channel, controller, value])

    func note(device: int, channel: int, note_number: int, on: bool) -> void:
        lines.append(["note", device, channel, note_number, on])


static func _control(device: int, channel: int, controller: int, value: int) -> InputEventMIDI:
    var event := InputEventMIDI.new()
    event.message = MIDI_MESSAGE_CONTROL_CHANGE
    event.device = device
    event.channel = channel
    event.controller_number = controller
    event.controller_value = value
    return event


static func _note(
    device: int, channel: int, pitch: int, velocity: int, message: MIDIMessage = MIDI_MESSAGE_NOTE_ON
) -> InputEventMIDI:
    var event := InputEventMIDI.new()
    event.message = message
    event.device = device
    event.channel = channel
    event.pitch = pitch
    event.velocity = velocity
    return event


func _facade(root: Window = null) -> Array:
    var ports := ProbePorts.new()
    ports.names_given = PackedStringArray(NAMES)
    var midi := Midi.new(ports, root)
    var told := Told.new()
    midi.control_changed.connect(told.control)
    midi.note_changed.connect(told.note)
    return [midi, ports, told]


func test_a_control_change_and_a_note_on_are_told_with_their_device_channel_and_number() -> void:
    var made := _facade()
    var midi := made[0] as Midi
    var told := made[2] as Told
    midi.listen(true)
    midi.hear(_control(1, 3, 7, 64))
    midi.hear(_note(0, 9, 60, 100))
    assert_eq(
        told.lines, [["control", 1, 3, 7, 64], ["note", 0, 9, 60, true]], "the fader on the mixer, then the key on the piano"
    )
    assert_eq(midi.heard, 2, "two messages heard")
    assert_eq(String(midi.last_heard.get("device_name", "")), "Probe Mixer", "the note came from the first input")
    assert_eq(midi.device_name(1), "Probe Piano", "and the second input is named by its device number")


func test_nothing_is_told_with_listen_off() -> void:
    var made := _facade()
    var midi := made[0] as Midi
    var told := made[2] as Told
    midi.hear(_control(0, 0, 7, 64))
    midi.hear(_note(0, 0, 60, 100))
    assert_eq(told.lines, [], "off as it starts, a message is heard by nobody")
    midi.listen(true)
    midi.listen(false)
    midi.hear(_control(0, 0, 7, 127))
    assert_eq(told.lines, [], "and off again after Listen was on")
    assert_eq(midi.heard, 0, "nothing counted")


## Velocity is ignored, except where the protocol says a
## note on at nothing is a key let go.
func test_a_note_off_and_a_silent_note_on_are_both_told_as_off() -> void:
    var made := _facade()
    var midi := made[0] as Midi
    var told := made[2] as Told
    midi.listen(true)
    midi.hear(_note(0, 0, 60, 64, MIDI_MESSAGE_NOTE_OFF))
    midi.hear(_note(0, 0, 61, 0))
    midi.hear(_note(0, 0, 62, 1))
    assert_eq(
        told.lines,
        [["note", 0, 0, 60, false], ["note", 0, 0, 61, false], ["note", 0, 0, 62, true]],
        "off, off, and the softest on"
    )


func test_aftertouch_and_a_key_are_told_nothing() -> void:
    var made := _facade()
    var midi := made[0] as Midi
    var told := made[2] as Told
    midi.listen(true)
    for message: MIDIMessage in [MIDI_MESSAGE_AFTERTOUCH, MIDI_MESSAGE_CHANNEL_PRESSURE]:
        var event := _note(0, 0, 60, 100, message)
        event.pressure = 90
        midi.hear(event)
    var key := InputEventKey.new()
    key.keycode = KEY_M
    key.pressed = true
    midi.hear(key)
    assert_eq(told.lines, [], "only a control change, a pitch bend and a note reach a listener")


func test_listen_opens_the_inputs_once_and_rescan_opens_them_again() -> void:
    var made := _facade()
    var midi := made[0] as Midi
    var ports := made[1] as ProbePorts
    midi.rescan()
    assert_eq(ports.opened, 0, "Rescan while off opens nothing")
    midi.listen(true)
    midi.listen(true)
    assert_eq(ports.opened, 1, "Listen asked twice opens once")
    assert_eq(midi.devices, PackedStringArray(NAMES), "and names the inputs")
    midi.rescan()
    assert_eq([ports.closed, ports.opened], [1, 2], "Rescan closes and opens again")
    midi.listen(false)
    assert_eq(ports.closed, 2, "Listen off closes them")
    assert_eq(midi.devices, PackedStringArray(), "and names none")


## The page never shows an empty list with nothing to say why.
func test_the_device_list_names_the_inputs_or_says_why_there_are_none() -> void:
    var made := _facade()
    var midi := made[0] as Midi
    var ports := made[1] as ProbePorts
    var page := Midi.preferences_page(midi)
    var label := page.find_child("Devices", true, false) as Label
    assert_not_null(label, "the page has a device list")
    if label == null:
        page.free()
        return
    assert_true(label.text.contains("Turn Listen on"), "off, it says how to look: %s" % label.text)
    for key: StringName in [&"listen", &"devices", &"rescan"]:
        assert_not_null((page as SaSettingsPage).page.row(key), "a %s row" % key)

    midi.listen(true)
    assert_eq(label.text, "\n".join(NAMES), "on, the two inputs by name and nothing else")

    midi.listen(false)
    ports.names_given = PackedStringArray()
    ports.refusals_given = PackedStringArray(["A device would not open: Probe Synth is held by another program"])
    midi.listen(true)
    assert_true(label.text.contains("Probe Synth"), "a refusal is said in its sentence: %s" % label.text)

    ports.refusals_given = PackedStringArray()
    midi.rescan()
    assert_true(label.text.contains("No MIDI controller is connected"), "and none at all is said too: %s" % label.text)
    page.free()


## Godot opens what it can and only prints an error for an input it could not,
## so the facade's ports hear the errors printed while they open. Here an error
## of the shape Godot's Windows driver prints for a device another program
## holds, printed through the same engine call.
func test_an_error_printed_while_the_inputs_open_becomes_the_pages_sentence() -> void:
    var caught := SaErrorCatcher.listening()
    push_error('Can\'t open MIDI device "Probe Synth", is it being used by another application?')
    caught.stop()
    var said := Midi.Ports.sentences(caught)
    assert_eq(said.size(), 1, "one device, one sentence: %s" % [said])
    assert_true(said.size() == 1 and said[0].contains("Probe Synth"), "naming the device as Godot printed it")
    assert_true(said.size() == 1 and said[0].begins_with("A device would not open"), "and saying what it means")


## The path a controller's message takes, through the engine's input to the
## root window. Its `window_input` is heard before the window's viewport hands
## the event on, which is where the shortcut router would drop it.
func test_a_message_through_the_engine_reaches_a_facade_on_the_root_window() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var made := _facade(tree.root)
    var midi := made[0] as Midi
    var told := made[2] as Told
    midi.listen(true)
    Input.parse_input_event(_control(0, 2, 74, 100))
    Input.flush_buffered_events()
    midi.listen(false)
    Input.parse_input_event(_control(0, 2, 74, 0))
    Input.flush_buffered_events()
    assert_eq(told.lines, [["control", 0, 2, 74, 100]], "heard while listening, and not after")
    assert_false(tree.root.window_input.is_connected(midi.hear), "and off, it is no longer on the window's input")


## Listen is the module's own preference, under `module.midi`.
func test_listen_is_a_preference_off_by_default() -> void:
    assert_eq(Midi.Preferences.LISTEN, &"listen", "kept under the module's own key")
    assert_false(Midi.Preferences.new().listen, "and off until the painter turns it on")
