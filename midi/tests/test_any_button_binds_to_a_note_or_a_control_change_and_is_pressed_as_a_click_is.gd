## Any button the widget maker made binds to a note or a control change, the
## profile keeps it, and the press is a click's.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The top bar's rotation reset button is the one a painter found refused. It
## is built by the bar's own class in a host the suite puts in the tree, since a
## binding finds its button again by the name it was made under.
extends "res://tests/test_framework.gd"

const Midi := preload("res://modules/sara-base-modules/midi/midi.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const DEVICE := "Probe Pads"

static var scratch_path: String = SaDataRoot.path("test_midi_button_bindings.cfg")

var _made: Array[Node] = []


class ProbePorts:
    extends Midi.Ports

    var opened: int = 0

    func open() -> PackedStringArray:
        opened += 1
        return PackedStringArray()

    func names() -> PackedStringArray:
        return PackedStringArray([DEVICE]) if opened > 0 else PackedStringArray()


func before_each() -> void:
    _clear()


func after_each() -> void:
    for node: Node in _made:
        if is_instance_valid(node):
            if node.get_parent() != null:
                node.get_parent().remove_child(node)
            node.free()
    _made.clear()
    _clear()


func _clear() -> void:
    var path := ProjectSettings.globalize_path(scratch_path)
    for suffix: String in ["", ".bak", ".tmp", ".broken"]:
        DirAccess.remove_absolute(path + suffix)


func _loaded() -> Midi.Preferences:
    var settings: Node = load("res://core/settings/sa_settings.gd").new()
    settings.settings_path = ProjectSettings.globalize_path(scratch_path)
    settings.load_settings()
    _made.append(settings)
    return Midi.Preferences.new(
        func(key: StringName, default: Variant, formerly: Array) -> Variant:
            return settings.module_preference(Midi.MODULE_ID, key, default, formerly),
        func(key: StringName, value: Variant) -> void: settings.set_module_preference(Midi.MODULE_ID, key, value)
    )


func _facade(kept: Midi.Preferences) -> Midi:
    var midi := Midi.new(ProbePorts.new(), null, Midi.Bindings.new(kept, SaAppDrive.new(Callable())))
    midi.listen(true)
    return midi


## The rotation pair on a view of the suite's, its host in the tree.
func _bar(view: SaView) -> SaTopBarRotation:
    var host := HBoxContainer.new()
    host.name = "MidiButtonProbeBar"
    var pair := SaTopBarRotation.new(view)
    pair.attach(host)
    EventBus.add_child(host)
    _made.append(host)
    pair.follow()
    return pair


static func _note(pitch: int, on: bool = true) -> InputEventMIDI:
    var event := InputEventMIDI.new()
    event.message = MIDI_MESSAGE_NOTE_ON if on else MIDI_MESSAGE_NOTE_OFF
    event.device = 0
    event.pitch = pitch
    event.velocity = 100 if on else 0
    return event


static func _control(controller: int, value: int) -> InputEventMIDI:
    var event := InputEventMIDI.new()
    event.message = MIDI_MESSAGE_CONTROL_CHANGE
    event.device = 0
    event.controller_number = controller
    event.controller_value = value
    return event


func test_the_rotation_reset_button_binds_to_a_note_and_the_note_resets_the_rotation() -> void:
    var view := Fixtures.FakeView.new()
    var pair := _bar(view)
    view.rotate_at(deg_to_rad(40.0), view.get_viewport_size() * 0.5)
    assert_almost_eq(pair.slider.value, 40.0, 0.01, "the canvas starts turned")
    var midi := _facade(_loaded())
    midi.learning.start()
    assert_true(midi.learning.pick(pair.reset_button), "the button is something to map")
    assert_eq(String(midi.learning.picked["kind"]), "button", "a button")
    assert_eq(String(midi.learning.picked["label"]), pair.reset_button.tooltip_text, "labelled by its tooltip, having no text")
    midi.hear(_note(36))
    assert_eq(midi.learning.step, Midi.Learning.Step.OFF, "a note binds it")
    midi.hear(_note(36, false))
    assert_almost_eq(pair.slider.value, 40.0, 0.01, "a key let go presses nothing")
    midi.hear(_note(36))
    assert_almost_eq(rad_to_deg(view.get_rotation()), 0.0, 0.01, "the note reset the rotation")
    assert_true(bool(midi.bindings.last_driven["moved"]), "and says it pressed")


func test_a_control_change_past_halfway_presses_once_until_it_comes_back_down() -> void:
    var pair := _bar(Fixtures.FakeView.new())
    var presses: Array = []
    pair.reset_button.pressed.connect(func() -> void: presses.append(true))
    var midi := _facade(_loaded())
    midi.learning.start()
    midi.learning.pick(pair.reset_button)
    midi.hear(_control(64, 127))
    assert_eq(midi.learning.step, Midi.Learning.Step.OFF, "a control change binds a button")
    midi.bindings.flush()
    assert_eq(presses.size(), 0, "the binding message itself pressed nothing")
    midi.hear(_control(64, 10))
    midi.hear(_control(64, 100))
    midi.hear(_control(64, 127))
    assert_eq(presses.size(), 1, "up past halfway presses and staying up does not press again")
    midi.hear(_control(64, 0))
    midi.hear(_control(64, 90))
    assert_eq(presses.size(), 2, "back down and up again presses again")


func test_a_binding_to_a_button_survives_a_profile_reload() -> void:
    var view := Fixtures.FakeView.new()
    var pair := _bar(view)
    var midi := _facade(_loaded())
    midi.learning.start()
    midi.learning.pick(pair.reset_button)
    midi.hear(_note(40))
    var again := _facade(_loaded())
    var found := again.bindings.find(DEVICE, "note/0/40")
    assert_eq(String(found.get("kind", "")), "button", "the profile holds a button binding")
    assert_eq(String(found.get("target", "")), "ResetRotationBtn", "by the name it was made under")
    view.rotate_at(deg_to_rad(25.0), view.get_viewport_size() * 0.5)
    again.hear(_note(40))
    assert_almost_eq(rad_to_deg(view.get_rotation()), 0.0, 0.01, "and the reloaded binding presses it")
    var page := Midi.preferences_page(again)
    _made.append(page)
    var line := page.find_child("Binding", true, false) as HBoxContainer
    assert_true(
        (line.get_child(0) as Label).text.contains("the button Reset rotation"),
        "the page lists it: %s" % (line.get_child(0) as Label).text
    )


func test_a_disabled_button_is_not_pressed() -> void:
    var view := Fixtures.FakeView.new()
    var pair := _bar(view)
    var midi := _facade(_loaded())
    midi.learning.start()
    midi.learning.pick(pair.reset_button)
    midi.hear(_note(41))
    view.rotate_at(deg_to_rad(25.0), view.get_viewport_size() * 0.5)
    pair.reset_button.disabled = true
    midi.hear(_note(41))
    assert_almost_eq(rad_to_deg(view.get_rotation()), 25.0, 0.01, "a disabled button does nothing")
    assert_false(bool(midi.bindings.last_driven["moved"]), "and says so")


func test_a_toggle_button_toggles_and_announces_the_press() -> void:
    var host := VBoxContainer.new()
    host.name = "MidiToggleProbe"
    var toggle := SaMake.switch(host, "ProbeToggleBtn", "Probe")
    EventBus.add_child(host)
    _made.append(host)
    var toggled: Array = []
    toggle.toggled.connect(func(on: bool) -> void: toggled.append(on))
    var midi := _facade(_loaded())
    midi.learning.start()
    assert_true(midi.learning.pick(toggle), "a toggle is a button")
    assert_eq(String(midi.learning.picked["label"]), "Probe", "labelled by its text")
    midi.hear(_note(42))
    assert_eq(toggled, [], "the first note only binds it")
    midi.hear(_note(42))
    midi.hear(_note(42))
    midi.hear(_note(42))
    assert_eq(toggled, [true, false, true], "each note flips it")


func test_two_buttons_of_one_name_are_told_apart_by_their_holder() -> void:
    var host := VBoxContainer.new()
    host.name = "MidiNamesakeProbe"
    var one := VBoxContainer.new()
    one.name = "ProbeHolderOne"
    var two := VBoxContainer.new()
    two.name = "ProbeHolderTwo"
    host.add_child(one)
    host.add_child(two)
    var first := SaMake.button(one, "Same", "Same")
    var second := SaMake.button(two, "Same", "Same")
    EventBus.add_child(host)
    _made.append(host)
    var presses: Array = []
    first.pressed.connect(func() -> void: presses.append(1))
    second.pressed.connect(func() -> void: presses.append(2))
    var midi := _facade(_loaded())
    midi.learning.start()
    assert_true(midi.learning.pick(second), "the second is picked")
    assert_eq(String(midi.learning.picked["target"]), "ProbeHolderTwo/Same", "by its holder and its name")
    midi.hear(_note(43))
    assert_eq(presses, [], "the first note only binds it")
    midi.hear(_note(43))
    midi.hear(_note(43))
    assert_eq(presses, [2, 2], "and only it is pressed")


func test_a_button_that_cannot_be_found_again_by_name_is_refused() -> void:
    var loose := Button.new()
    loose.text = "Plain"
    _made.append(loose)
    var midi := _facade(_loaded())
    midi.learning.start()
    assert_false(midi.learning.pick(loose), "a button the widget maker did not make has no name to find it by")
    assert_true(midi.learning.said.contains("cannot be mapped"), "the corner says so: %s" % midi.learning.said)
