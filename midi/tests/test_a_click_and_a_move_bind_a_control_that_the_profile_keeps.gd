## A chord, a click and a move of the control bind a fader, a
## knob or a pad, and the profile keeps what each control drives.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The learning is driven as Map to MIDI drives it, a click picking what to
## drive and a message from the suite's own ports naming the control, on a
## facade whose bindings are the module's preferences in a settings object of
## the suite's own, written to a scratch profile the way the painter's is. So no suite
## opens the machine's MIDI inputs or touches the painter's settings.
##
## The drive itself, a fader setting the brush's size and a note choosing a
## preset or opening a filter, needs the running app's bar and canvas, and is
## the unit's two scenarios.
extends "res://tests/test_framework.gd"

const Midi := preload("res://modules/sara-base-modules/midi/midi.gd")

const NAMES := ["Probe Mixer", "Probe Piano"]

## The settings autoload's script, a fresh object of which reads the scratch
## profile.
const SETTINGS := "res://core/settings/sa_settings.gd"

static var scratch_path: String = SaDataRoot.path("test_m3_midi_bindings.cfg")

var _made: Array[Node] = []


## Inputs that open by saying so, with two names.
class ProbePorts:
    extends Midi.Ports

    var opened: int = 0
    var closed: int = 0

    func open() -> PackedStringArray:
        opened += 1
        return PackedStringArray()

    func close() -> void:
        closed += 1

    func names() -> PackedStringArray:
        return PackedStringArray(NAMES) if opened > closed else PackedStringArray()


func before_each() -> void:
    _clear()


func after_each() -> void:
    for node: Node in _made:
        if is_instance_valid(node):
            node.free()
    _made.clear()
    _clear()


func _clear() -> void:
    var path := ProjectSettings.globalize_path(scratch_path)
    for suffix: String in ["", ".bak", ".tmp", ".broken"]:
        DirAccess.remove_absolute(path + suffix)


## The module's preferences in a load of the scratch file, by a settings object
## of the autoload's class, every change written back to it as the context
## writes the painter's.
func _loaded() -> Midi.Preferences:
    var settings: Node = load(SETTINGS).new()
    settings.settings_path = ProjectSettings.globalize_path(scratch_path)
    settings.load_settings()
    _made.append(settings)
    return Midi.Preferences.new(
        func(key: StringName, default: Variant, formerly: Array) -> Variant:
            return settings.module_preference(Midi.MODULE_ID, key, default, formerly),
        func(key: StringName, value: Variant) -> void: settings.set_module_preference(Midi.MODULE_ID, key, value)
    )


## A facade listening over the suite's ports, its bindings kept in *kept*.
func _facade(kept: Midi.Preferences, root: Window = null) -> Midi:
    var midi := Midi.new(ProbePorts.new(), root, Midi.Bindings.new(kept, SaAppDrive.new(Callable())))
    midi.listen(true)
    return midi


## A slider that names the brush's size, as the options bar's does.
func _size_slider() -> FactorSlider:
    var slider := FactorSlider.new()
    slider.prefix = "Size:"
    slider.value_name = &"tool/brush/radius"
    _made.append(slider)
    return slider


## A brush preset's cell with its picture button, as the chooser builds one.
func _preset_cell(preset: String) -> Button:
    var box := VBoxContainer.new()
    box.name = "Cell_" + preset
    box.set_meta(SaBrushPresetsChooser.PRESET_META, preset)
    var icon := Button.new()
    icon.name = "Icon"
    box.add_child(icon)
    _made.append(box)
    return icon


## A filter's row, as the Filters docker builds one.
func _filter_row(key: StringName, title: String) -> Button:
    var row := Button.new()
    row.name = "BrowserRow"
    row.text = title
    row.set_meta(SaFilterBrowser.FILTER_META, key)
    _made.append(row)
    return row


static func _control(device: int, channel: int, controller: int, value: int) -> InputEventMIDI:
    var event := InputEventMIDI.new()
    event.message = MIDI_MESSAGE_CONTROL_CHANGE
    event.device = device
    event.channel = channel
    event.controller_number = controller
    event.controller_value = value
    return event


static func _note(device: int, channel: int, pitch: int, on: bool = true) -> InputEventMIDI:
    var event := InputEventMIDI.new()
    event.message = MIDI_MESSAGE_NOTE_ON if on else MIDI_MESSAGE_NOTE_OFF
    event.device = device
    event.channel = channel
    event.pitch = pitch
    event.velocity = 100 if on else 0
    return event


## Two bindings saved, the settings loaded afresh, and
## both read back by device, control and what they drive.
func test_two_bindings_come_back_from_a_profile_loaded_afresh() -> void:
    var midi := _facade(_loaded())
    midi.learning.start()
    assert_eq(midi.learning.step, Midi.Learning.Step.CLICK, "the chord waits for a click")
    assert_true(midi.learning.pick(_size_slider()), "the size slider is a dial")
    assert_eq(midi.learning.step, Midi.Learning.Step.CONTROL, "and then a control is waited for")
    assert_true(midi.learning.said.contains("Size (brush)"), "the corner names what it will turn: %s" % midi.learning.said)
    midi.hear(_control(0, 0, 7, 64))
    assert_eq(midi.learning.step, Midi.Learning.Step.OFF, "the first control change binds and leaves learning")
    assert_true(
        midi.learning.said.contains("Control 7, channel 1 of Probe Mixer now drives Size (brush)"),
        "and says what it bound: %s" % midi.learning.said
    )

    midi.learning.start()
    assert_true(midi.learning.pick(_preset_cell("Wet Ink")), "a click on a cell's picture is that preset")
    midi.hear(_note(1, 9, 36, false))
    assert_eq(midi.learning.step, Midi.Learning.Step.CONTROL, "a key let go binds nothing")
    midi.hear(_note(1, 9, 36))
    assert_eq(midi.learning.step, Midi.Learning.Step.OFF, "a note on does")

    var again := Midi.Bindings.new(_loaded(), SaAppDrive.new(Callable()))
    assert_eq(
        again.listed(),
        [
            {
                "device": "Probe Mixer",
                "control": "control/0/7",
                "kind": "dial",
                "target": "tool/brush/radius",
                "label": "Size (brush)"
            },
            {"device": "Probe Piano", "control": "note/9/36", "kind": "preset", "target": "Wet Ink", "label": "Wet Ink"},
        ],
        "both read back from the profile, each under the device it was on"
    )
    assert_eq(String(again.find("Probe Piano", "note/9/36").get("target", "")), "Wet Ink", "and found by its control")


## A click on a plain label is refused in the corner and
## the learning goes on waiting for a click.
func test_a_click_on_a_plain_label_is_refused_and_the_learning_still_waits() -> void:
    var midi := _facade(_loaded())
    midi.learning.start()
    var label := Label.new()
    label.text = "Opacity"
    _made.append(label)
    assert_false(midi.learning.pick(label), "a label drives nothing")
    assert_eq(midi.learning.step, Midi.Learning.Step.CLICK, "and the learning still waits for a click")
    assert_true(midi.learning.said.contains("cannot be mapped"), "which the corner says: %s" % midi.learning.said)
    midi.hear(_control(0, 0, 7, 64))
    assert_eq(midi.learning.step, Midi.Learning.Step.CLICK, "a control moved before a click binds nothing")
    assert_eq(_listed(midi), [], "and nothing is bound")
    assert_true(midi.learning.pick(_filter_row(&"sara-base-modules.threshold", "Threshold")), "a filter's row is picked")
    assert_eq(
        midi.learning.picked,
        {"kind": "filter", "target": "sara-base-modules.threshold", "label": "Threshold"},
        "by its key, under the title its row shows"
    )


## A note on a dial and a control change on a preset or a filter are refused
## in the corner, and the learning goes on waiting for the right kind.
func test_a_message_of_the_wrong_kind_is_refused_and_waited_past() -> void:
    var midi := _facade(_loaded())
    midi.learning.start()
    midi.learning.pick(_size_slider())
    midi.hear(_note(0, 0, 60))
    assert_eq(midi.learning.step, Midi.Learning.Step.CONTROL, "a note cannot turn a dial, and a control is still waited for")
    assert_true(midi.learning.said.contains("A key or pad cannot turn"), "which the corner says: %s" % midi.learning.said)
    midi.learning.stop()

    midi.learning.start()
    midi.learning.pick(_preset_cell("Wet Ink"))
    midi.hear(_control(0, 0, 7, 64))
    assert_eq(midi.learning.step, Midi.Learning.Step.CONTROL, "a fader cannot choose a preset")
    assert_true(midi.learning.said.contains("A knob or fader cannot choose"), "which the corner says: %s" % midi.learning.said)
    midi.learning.stop()

    midi.learning.start()
    midi.learning.pick(_filter_row(&"sara-base-modules.threshold", "Threshold"))
    midi.hear(_control(0, 0, 7, 64))
    assert_eq(midi.learning.step, Midi.Learning.Step.CONTROL, "nor run a filter")
    assert_eq(_listed(midi), [], "and nothing was bound by any of them")


## A control bound before is bound again, and the corner names what it drove.
func test_a_control_bound_again_says_what_it_drove() -> void:
    var midi := _facade(_loaded())
    midi.learning.start()
    midi.learning.pick(_preset_cell("Wet Ink"))
    midi.hear(_note(1, 0, 40))
    midi.learning.start()
    midi.learning.pick(_filter_row(&"sara-base-modules.threshold", "Threshold"))
    midi.hear(_note(1, 0, 40))
    assert_true(
        midi.learning.said.contains("It drove the preset Wet Ink before."), "the corner names the old: %s" % midi.learning.said
    )
    var listed := _listed(midi)
    assert_eq(listed.size(), 1, "one binding, the new")
    assert_eq(String(listed[0]["target"]), "sara-base-modules.threshold", "which runs the filter")


## Escape leaves learning, and the chord pressed again does too.
func test_escape_and_the_chord_again_leave_learning() -> void:
    var midi := _facade(_loaded())
    midi.learning.toggle()
    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.pressed = true
    assert_true(midi.learning.handle(escape), "Escape is taken")
    assert_eq(midi.learning.step, Midi.Learning.Step.OFF, "and leaves")
    midi.learning.toggle()
    midi.learning.pick(_size_slider())
    midi.learning.toggle()
    assert_eq(midi.learning.step, Midi.Learning.Step.OFF, "the chord again leaves while a control is waited for")
    midi.hear(_control(0, 0, 7, 64))
    assert_eq(_listed(midi), [], "and the next message binds nothing")


## The click picks, it does not press: a press on a filter's row through the
## engine's input picks that filter and the row is never pressed. The row is in
## an embedded window of the suite's own, as the Filters docker's is in its
## docker, since the runner's root is busy building its children while a suite
## runs and takes no catcher.
func test_a_click_through_the_engine_picks_and_presses_nothing() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var was_embedding := tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var window := Window.new()
    window.name = "MidiLearningProbe"
    window.position = Vector2i(0, 0)
    window.size = Vector2i(320, 200)
    window.unfocusable = true
    var row := _filter_row(&"sara-base-modules.threshold", "Threshold")
    _made.erase(row)
    window.add_child(row)
    row.position = Vector2(40, 40)
    row.size = Vector2(160, 32)
    EventBus.add_child(window)
    var presses: Array = []
    row.pressed.connect(func() -> void: presses.append(true))
    var midi := _facade(_loaded(), window)
    midi.learning.start()
    assert_not_null(window.get_node_or_null(Midi.Learning.CATCHER_NAME), "the window has a catcher while learning")
    var at := Vector2(row.get_global_rect().get_center()) + Vector2(window.position)
    for down: bool in [true, false]:
        var click := InputEventMouseButton.new()
        click.button_index = MOUSE_BUTTON_LEFT
        click.pressed = down
        click.position = at
        click.global_position = at
        Input.parse_input_event(click)
    Input.flush_buffered_events()
    assert_eq(String(midi.learning.picked.get("target", "")), "sara-base-modules.threshold", "the press picked the row's filter")
    assert_eq(presses, [], "and the row was not pressed")
    midi.learning.stop()
    EventBus.remove_child(window)
    window.free()
    tree.root.gui_embed_subwindows = was_embedding


## Preferences > MIDI lists each binding with its Remove, and a Remove unbinds
## that one control.
func test_the_page_lists_the_bindings_each_with_a_remove() -> void:
    var midi := _facade(_loaded())
    var page := Midi.preferences_page(midi)
    _made.append(page)
    assert_not_null(page.find_child("NoBindings", true, false), "none yet, and a sentence says how to map one")
    midi.learning.start()
    midi.learning.pick(_size_slider())
    midi.hear(_control(0, 0, 7, 64))
    midi.learning.start()
    midi.learning.pick(_preset_cell("Wet Ink"))
    midi.hear(_note(1, 9, 36))
    var removes := page.find_children("RemoveBinding*", "Button", true, false)
    assert_eq(removes.size(), 2, "two lines, a Remove each")
    var lines: Array[String] = []
    for line: Node in page.find_children("Binding*", "HBoxContainer", true, false):
        lines.append(((line as HBoxContainer).get_child(0) as Label).text)
    assert_eq(
        lines,
        (
            [
                "Probe Mixer: Control 7, channel 1, Size (brush)",
                "Probe Piano: Note 36, channel 10, the preset Wet Ink",
            ]
            as Array[String]
        ),
        "each by its device, its control and what it drives"
    )
    (removes[0] as Button).pressed.emit()
    assert_eq(_listed(midi).size(), 1, "a Remove unbinds its control")
    assert_eq(page.find_children("RemoveBinding*", "Button", true, false).size(), 1, "and the page lists one")


func _listed(midi: Midi) -> Array:
    return midi.bindings.listed()
