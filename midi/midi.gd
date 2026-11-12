## MIDI controllers: Sara opens the inputs while the painter's Listen is on,
## hears every message a controller sends, and tells its listeners a control
## change or a note.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## This class listens, and hands each message first to the learning Map to MIDI
## starts and then to the bindings, which are private to the folder. The two
## signals below are told every message, whatever the bindings did with it.
##
## **Heard on the root window's own input, before anything else is.** Godot
## hands a MIDI message to every window the way it hands a key, and the root's
## `window_input` signal fires before its viewport passes the event on. Two
## places later in the path drop it: `Main._unhandled_input` gives every event
## to the shortcut router, which returns at once for anything that is not key
## like, and a focused embedded window, Preferences for one, takes every event
## that is not the mouse's so the root's own `_input` never sees it. A painter
## turning a knob with the MIDI page open is the case that has to work.
##
## **A message arrives on the driver's thread, so the project buffers input.**
## The ALSA driver calls `Input.parse_input_event` from a thread of its own.
## Sara turns input accumulation off to keep every pen sample, and with it off
## and `input_devices/buffering/agile_event_flushing` false Godot dispatches
## the event at once on that thread, where a window refuses it as not the main
## thread's and the message is lost. With the setting true events are queued
## and flushed on the main thread before each step, on every platform.
##
## **A fader that sends pitch bend is a control too.** A mixer's faders send a
## bend on their channel, 14 bits in `InputEventMIDI.pitch`, and it is bound and
## driven like a knob but kept at that resolution, so a fader moves a value in
## sixteen thousand steps rather than a hundred and twenty-eight.
##
## **Velocity and aftertouch are read and ignored**, because nothing a note
## drives is moved by how hard a key was struck. The one reading
## of velocity is the protocol's own: a note on at velocity 0 is how many
## keyboards say a key was let go, and Godot hands it on as received, so it is
## told as the note off it means.
##
## A facade with an instance per caller and one for the app: [method
## apply_stored] keeps the app's in [member app], following the module's Listen
## preference, and a suite builds its own over ports of its own.
##
## **It comes in through the door a module uses.** `module.gd` calls [method
## register], which hands the context an input source, [Source], the
## Preferences page and Map to MIDI. The registry applies the source when
## Listen moves, the door's `midi` step feeds it a message and the dump writes
## its block, each by the id `midi`, and a binding moves what it drives through
## `SaContext.drive`. The skeleton names nothing in this folder.
extends RefCounted

## The facade by path, since a module's script has no global name.
const Midi := preload("midi.gd")

## The Preferences page, private to this folder and reached by path.
const MidiPage := preload("midi_page.gd")

## What each control drives, the learning that binds one, and the two values
## the profile keeps, private to this folder.
const Bindings := preload("midi_bindings.gd")
const Learning := preload("midi_learning.gd")
const Preferences := preload("midi_preferences.gd")

## The command Map to MIDI is, under Interface on the Shortcuts page.
const MAP_COMMAND := &"ui_map_to_midi"

## The id the input source registers under, which the door's `midi` step asks
## for and the dump writes its block under.
const SOURCE_ID := &"midi"

## The module the registrations are held for, so they list and unload as a
## module's do, and the page sorts after the skeleton's pages of Painting.
const MODULE_ID := &"midi"

## The Preferences page's id and title, which the scenarios open it by.
const PAGE_ID := &"midi"
const PAGE_TITLE := "MIDI"

## A knob, a fader or a wheel moved: *controller* is its number and *value*
## where it stands, 0 to 127. *device* is the input's index in [member devices]
## and *channel* is 0 to 15, as the message carries them.
signal control_changed(device: int, channel: int, controller: int, value: int)

## A fader that sends pitch bend moved: *value* is where it stands at its full
## 14 bits, 0 to 16383.
signal bend_changed(device: int, channel: int, value: int)

## A key or a pad struck, *on*, or let go.
signal note_changed(device: int, channel: int, note: int, on: bool)

## The inputs were opened or closed, so [member devices] and [member
## refusals] say something new.
signal devices_changed

## The facade the running app hears through, made by [method apply_stored].
static var app: Midi = null

## The app's Listen and bindings, in the profile under `module.midi`, written by
## [method register] alone. Kept in this object until then, so a facade a suite
## makes never reaches the painter's profile.
static var preferences: Preferences = Preferences.new()

## What the app's bindings drive, the context's drive [method register] was
## handed. Written there alone, and a drive that moves nothing until then.
static var _drive: SaControlDrive = null

## Whether the inputs are open and a message is told. Written by [method
## listen] alone.
var listening: bool = false

## The names of the inputs open now, in the order a message's device numbers
## them. Empty while not listening.
var devices: PackedStringArray = PackedStringArray()

## What stopped an input opening, a sentence each, from the last time the
## inputs were opened. Godot opens what it can and only prints the rest, so
## these are the lines it printed.
var refusals: PackedStringArray = PackedStringArray()

## How many messages were told since the facade was made, and the last of them
## as the dump writes it, so a scenario can read that a message arrived.
var heard: int = 0
var last_heard: Dictionary = {}

## What each control drives, read at every message.
var bindings: Bindings = null

## Map to MIDI's learning, which takes the next click and the next message.
var learning: Learning = null

var _ports: Ports = null
var _root: Window = null


## *ports* opens and names the inputs, the engine's when none is given. *root*
## is the window whose input is heard, none for a facade a suite hands messages
## to itself. *held* keeps the bindings, over the painter's settings when none
## is given.
func _init(ports: Ports = null, root: Window = null, held: Bindings = null) -> void:
    _ports = ports if ports != null else Ports.new()
    _root = root
    bindings = held if held != null else Bindings.new()
    learning = Learning.new(bindings, root)


## Registers MIDI through *ctx*: the input source the settings, the door and the
## dump reach it by, Preferences > MIDI under Painting, and Map to MIDI. The
## one call the app makes, with a context scoped to [constant MODULE_ID].
static func register(ctx: SaContext) -> void:
    _drive = ctx.drive
    preferences = Preferences.new(ctx.preference, ctx.set_preference)
    preferences.adopt()
    ctx.register_settings_page(PAGE_ID, PAGE_TITLE, func(_window: Node) -> Control: return preferences_page(), &"painting")
    register_command(ctx)
    ctx.register_input_source(Source.new())


## Lets the app's facade go as the module unloads: its inputs closed, and its
## preferences this object's own again, so nothing a facade made later writes
## reaches the profile through a context that is gone.
static func unregister() -> void:
    if app != null:
        app.listen(false)
    app = null
    _drive = null
    preferences = Preferences.new()


## Makes the app's facade on first use and has it follow the painter's Listen.
## [Source] calls it at start and whenever the preference moves. Never
## in the editor, where the setting is a file being edited rather than a
## painter asking for anything.
static func apply_stored() -> void:
    if Engine.is_editor_hint():
        return
    if app == null:
        var tree := Engine.get_main_loop() as SceneTree
        app = Midi.new(null, tree.root if tree != null else null, Bindings.new(preferences, _drive))
    app.listen(preferences.listen)


## Opens the inputs and starts telling, or closes them and stops. Asked for
## what it already is, it does nothing, so a setting written twice opens once.
func listen(on: bool) -> void:
    if on == listening:
        return
    listening = on
    if on:
        _open()
        if _root != null and not _root.window_input.is_connected(hear):
            _root.window_input.connect(hear)
    else:
        if _root != null and _root.window_input.is_connected(hear):
            _root.window_input.disconnect(hear)
        _close()


## Closes the inputs and opens them again, which is the only way Godot sees a
## controller plugged in after they were opened. Nothing while not listening.
func rescan() -> void:
    if not listening:
        return
    _close()
    _open()


## One event from the window, or from a suite. A MIDI message is told while
## listening, and anything else, or anything while not, is let pass.
func hear(event: InputEvent) -> void:
    var midi := event as InputEventMIDI
    if midi == null or not listening:
        return
    match midi.message:
        MIDI_MESSAGE_CONTROL_CHANGE:
            _told(
                {
                    "kind": "control",
                    "device": midi.device,
                    "channel": midi.channel,
                    "controller": midi.controller_number,
                    "value": midi.controller_value
                }
            )
            var device := device_name(midi.device)
            if not learning.heard_control(device, midi.channel, midi.controller_number):
                bindings.drive_control(device, midi.channel, midi.controller_number, midi.controller_value)
            control_changed.emit(midi.device, midi.channel, midi.controller_number, midi.controller_value)
        MIDI_MESSAGE_PITCH_BEND:
            _told({"kind": Bindings.BEND, "device": midi.device, "channel": midi.channel, "value": midi.pitch})
            var device := device_name(midi.device)
            if not learning.heard_bend(device, midi.channel):
                bindings.drive_bend(device, midi.channel, midi.pitch)
            bend_changed.emit(midi.device, midi.channel, midi.pitch)
        MIDI_MESSAGE_NOTE_ON, MIDI_MESSAGE_NOTE_OFF:
            var on := midi.message == MIDI_MESSAGE_NOTE_ON and midi.velocity > 0
            _told({"kind": "note", "device": midi.device, "channel": midi.channel, "note": midi.pitch, "on": on})
            var device := device_name(midi.device)
            if not learning.heard_note(device, midi.channel, midi.pitch, on) and on:
                bindings.drive_note(device, midi.channel, midi.pitch)
            note_changed.emit(midi.device, midi.channel, midi.pitch, on)


## The name of input *device*, or a plain "device N" for a number no input has,
## which a message handed in by a door step can carry.
func device_name(device: int) -> String:
    if device >= 0 and device < devices.size():
        return devices[device]
    return "device %d" % device


## The sentences the MIDI page shows under its device list: one per input that
## would not open, and one saying why the list is empty when it is, so the
## page never shows an empty list and nothing else.
func sentences() -> PackedStringArray:
    var out := PackedStringArray()
    if not listening:
        out.append(tr("Turn Listen on and Sara looks for controllers."))
        return out
    out.append_array(refusals)
    if devices.is_empty() and refusals.is_empty():
        out.append(tr("No MIDI controller is connected. Plug one in and press Rescan."))
    return out


## The Preferences > MIDI page over *midi*, the app's facade when none is given.
static func preferences_page(midi: Midi = null) -> Control:
    if midi == null:
        apply_stored()
        midi = app
    return MidiPage.new(midi)


## Registers Map to MIDI, on Ctrl+Alt+M by default and rebound as any command
## is. [method register] calls it.
static func register_command(ctx: SaContext) -> void:
    var command := SaCommandDescriptor.create(MAP_COMMAND, "Map to MIDI", map_to_midi)
    command.category = &"view"
    var chord := InputEventKey.new()
    chord.keycode = KEY_M
    chord.ctrl_pressed = true
    chord.alt_pressed = true
    command.default_events = [chord]
    command.sentence = (
        "Waits for a click on a slider, a brush preset or a filter's row, then for a knob, a fader or a key"
        + " on a MIDI controller, and binds the two. Escape leaves."
    )
    ctx.register_command(command)


## Map to MIDI's handler: Listen is turned on if it is off, since a binding is
## made by a message, and the learning starts, or leaves when it is on.
static func map_to_midi() -> bool:
    var turned_on := not preferences.listen
    if turned_on:
        preferences.listen = true
    apply_stored()
    if app == null:
        return false
    app.learning.toggle(turned_on)
    return true


## What the dump's `midi` block says of the app's facade.
static func capture_state() -> Dictionary:
    if app == null:
        return {"present": false}
    return {
        "present": true,
        "listening": app.listening,
        "devices": Array(app.devices),
        "sentences": Array(app.sentences()),
        "heard": app.heard,
        "last_heard": app.last_heard.duplicate(),
        "learning": Learning.Step.keys()[app.learning.step].to_lower(),
        "picked": app.learning.picked.duplicate(),
        "said": app.learning.said,
        "bindings": app.bindings.listed(),
        "last_driven": app.bindings.last_driven.duplicate(),
        "page_lines": MidiPage.shown_lines(app._root),
    }


## Hands the app a MIDI message as a controller would, through the engine's own
## input, and answers the door's line: whether the app heard it, the count it
## has told and the last message, which stays where it was when Listen is off.
## [Source]'s answer to the `midi` step, see [method SaInputSource.simulate].
##
## `{"control": 7, "value": 64}` is a control change, a knob or a fader,
## `{"bend": 8192}` a pitch bend, a fader's 0 to 16383, and `{"note": 60}` a
## note on, with `"on": false` for the note off. `channel` and `device` default
## to 0, the first of each. The event is flushed at once rather than left for
## the next frame, so the line can say whether it was heard.
static func simulate(spec: Dictionary) -> String:
    var event := InputEventMIDI.new()
    event.device = int(spec.get("device", 0))
    event.channel = int(spec.get("channel", 0))
    if spec.has("control"):
        event.message = MIDI_MESSAGE_CONTROL_CHANGE
        event.controller_number = int(spec["control"])
        event.controller_value = int(spec.get("value", 0))
    elif spec.has("bend"):
        event.message = MIDI_MESSAGE_PITCH_BEND
        event.pitch = int(spec["bend"])
    elif spec.has("note"):
        var on := bool(spec.get("on", true))
        event.message = MIDI_MESSAGE_NOTE_ON if on else MIDI_MESSAGE_NOTE_OFF
        event.pitch = int(spec["note"])
        event.velocity = int(spec.get("velocity", 100 if on else 0))
    else:
        return "SaCapture: midi takes a control, a bend or a note, not %s" % JSON.stringify(spec)
    var before := app.heard if app != null else 0
    Input.parse_input_event(event)
    Input.flush_buffered_events()
    var state := capture_state()
    return (
        "SaCapture: midi %s  heard=%s listening=%s told=%d last=%s"
        % [
            JSON.stringify(spec),
            int(state.get("heard", 0)) > before,
            state.get("listening", false),
            int(state.get("heard", 0)),
            JSON.stringify(state.get("last_heard", {})),
        ]
    )


func _told(message: Dictionary) -> void:
    heard += 1
    message["device_name"] = device_name(int(message["device"]))
    last_heard = message


func _open() -> void:
    refusals = _ports.open()
    devices = _ports.names()
    devices_changed.emit()


func _close() -> void:
    _ports.close()
    devices = PackedStringArray()
    refusals = PackedStringArray()
    devices_changed.emit()


## MIDI as the registry knows it: applied at start and when Listen moves,
## released as it unloads, its block in the dump and its message from the door.
class Source:
    extends SaInputSource

    func _init() -> void:
        # The settings announce a module's key as its id, a slash and the key.
        super(SOURCE_ID, [StringName("%s/%s" % [MODULE_ID, Preferences.LISTEN])] as Array[StringName])

    func apply() -> void:
        Midi.apply_stored()

    func release() -> void:
        if Midi.app != null:
            Midi.app.listen(false)

    func capture_state() -> Dictionary:
        return Midi.capture_state()

    func simulate(spec: Dictionary) -> String:
        return Midi.simulate(spec)


## The engine's MIDI inputs, which a suite replaces with its own.
class Ports:
    extends RefCounted

    ## Opens every input it can and answers what stopped the rest, a sentence
    ## each.
    ##
    ## **On Linux Godot reads MIDI through ALSA's library, which only a sound
    ## driver loads.** Started with the Dummy driver, as `--headless` does,
    ## `OS.open_midi_inputs()` calls into a library that is not there and the
    ## engine dies with signal 11, printing nothing first. So it is asked only
    ## once the library is in the process, and otherwise the page says why.
    func open() -> PackedStringArray:
        var missing := _missing_library()
        if not missing.is_empty():
            return PackedStringArray([missing])
        var caught := SaErrorCatcher.listening()
        OS.open_midi_inputs()
        caught.stop()
        return sentences(caught)

    ## The page's sentence for each error *caught* while the inputs opened,
    ## which is how Godot says a device would not open: on Windows, a device a
    ## music program holds, and on Linux one ALSA refused.
    static func sentences(caught: SaErrorCatcher) -> PackedStringArray:
        var out := PackedStringArray()
        for line in caught.texts([SaErrorCatcher.ERROR]):
            out.append(TranslationServer.translate("A device would not open: %s") % line)
        return out

    func close() -> void:
        if _missing_library().is_empty():
            OS.close_midi_inputs()

    func names() -> PackedStringArray:
        return OS.get_connected_midi_inputs()

    ## A sentence when the library MIDI is read through is not loaded, empty
    ## when it is or when the system reads MIDI without it.
    static func _missing_library() -> String:
        if not OS.get_name() in ["Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"]:
            return ""
        if _library_mapped("libasound"):
            return ""
        return TranslationServer.translate(
            "Sara started without sound, which a controller is read through here. Start Sara with sound to use one."
        )

    ## Whether the process has *library* loaded. Read off `/proc/self/maps` a
    ## line at a time, because a file under `/proc` reports no length and
    ## `get_as_text()` answers it empty. Where there is no such file, a BSD,
    ## a driver other than Dummy is the sign that the sound library was loaded.
    static func _library_mapped(library: String) -> bool:
        var maps := FileAccess.open("/proc/self/maps", FileAccess.READ)
        if maps == null:
            return AudioServer.get_driver_name() != "Dummy"
        while not maps.eof_reached():
            if maps.get_line().contains(library):
                return true
        return false
