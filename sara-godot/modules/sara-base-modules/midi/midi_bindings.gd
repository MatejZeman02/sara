## What each MIDI control drives, kept per device in the painter's settings,
## and what a bound control does when it moves.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Private to this module, held by the facade, which hands it every message the
## learning did not take. Nothing is bound until the painter binds it, because
## what a controller's knobs should drive is each painter's own.
##
## **Kept per device, by the name the device gives.** The table is the
## module's `bindings` preference, device name to control to what it drives, so a
## piano and a mixer each keep their own, and an input's number, which moves
## when a controller is plugged in first or second, never keys anything. A
## control is `control/<channel>/<number>` or `note/<channel>/<number>`, the
## channel as the message carries it, 0 to 15. A fader that sends pitch bend
## rather than a control change is `bend/<channel>/0`, since a bend has no
## number of its own, and it is read at its full 14 bits.
##
## **Four kinds of target, each kept by a name that outlives its widget.** A
## dial is the value a slider names, a preset is the preset's stored name, a
## filter is its registry key, whose command a note runs, and a button is the
## name it was made under, pressed by a note or by a control change that
## passes halfway upward, so a pedal or a knob serves as a key. Each is moved,
## chosen or run through the context's [SaControlDrive], so nothing here names
## a window of the app.
## The table is read afresh at every message, so a binding made, removed or
## loaded at start is the one the next message finds.
##
## **A dial is moved the way a hand expects.** An absolute knob
## is picked up rather than jumped to: once the value moved another way, by the
## keyboard, the pen or a slider, the control changes nothing until it passes
## where the dial stands. A binding marked relative steps the dial instead, one
## per cent of its range for each detent, the endless encoders this class reads
## being 1 up, 127 down and 64 the middle. Only the last message of a control in
## a frame is applied, and a turn of a value that is an undo step is one step
## closed when the control rests for half a second. While it turns, the corner
## names the value moved and where it stands.
extends RefCounted

const Preferences := preload("midi_preferences.gd")

## The table moved, by a binding made or removed here or by the profile being
## loaded, so the page lists it again.
signal changed

## A slider's value, set across its range by a control change.
const DIAL := SaControlDrive.DIAL

## A brush preset, chosen by a note on.
const PRESET := SaControlDrive.PRESET

## A filter, whose command a note on runs, which opens its dialog.
const FILTER := SaControlDrive.FILTER

## A button, which a note on or a control change past halfway presses.
const BUTTON := SaControlDrive.BUTTON

## The kinds of control, the first word of a control's key.
const CONTROL := "control"
const NOTE := "note"
const BEND := "bend"

## The highest a control change goes, which is the top of a dial's range.
const TOP := 127.0

## Where a pitch bend reaches the top of a dial's range: 127 in the most
## significant byte and 0 in the least, 0x7F << 7. A mixer whose faders are
## seven bits wide in fourteen-bit clothing sends exactly that at its top, with
## the least byte always 0, so reading against the true 16383 left such a fader
## 127 steps short, about 177 of the Rotation slider's 180 degrees. A genuinely
## fourteen-bit fader keeps every step below this and only its last 127 steps
## saturate, a distance no hand can feel, which is simpler and surer than
## remembering per binding whether a non-zero least byte was ever heard.
const BEND_TOP := 16256.0

## The middle a relative control rests at, and how its messages read: 1 is one
## step up, 127 one step down, 64 and 0 nothing. The endless encoders on a mixer
## send this shape.
const RELATIVE_MIDDLE := 64

## How far one relative step moves the dial, a hundredth of the way across its
## range, so a detent is the same proportion of a pixel as of a whole picture.
const RELATIVE_STEP := 0.01

## How long a control rests before the turn of a value that is an undo step is
## closed, in milliseconds. Shorter than the 800 ms Godot folds within, so a
## turn taken up after half a second opens a step of its own.
const REST_MS := 500

## How near a control's last position must be to a dial's for the two to read as
## one, in control units. A slider's rounding is not read as a move of it.
const PICKUP_EPSILON := 1.0

## What the last bound message did, as the dump writes it, so a scenario can
## read that a note chose a preset or a fader moved the size. Written here alone.
var last_driven: Dictionary = {}

## The preferences the table is kept in, the app's or a suite's own, the
## page's Listen row writing the same object. Written by the constructor alone.
var preferences: Preferences = null

## What a binding drives: the values a dial reads and sets by name, the presets
## a note chooses and the filters it runs. Written by the constructor alone.
var drive: SaControlDrive = null

## The last position a control stood at, per device and control, so a dial moved
## another way is picked up as the control passes it rather than jumped to.
var _positions: Dictionary = {}

## When each control last moved, per device and control, for the rest that
## closes a turn.
var _turned: Dictionary = {}

## The last message of each control waiting for the end of the frame, so a fader
## sending hundreds a second has only its last read.
var _pending: Dictionary = {}

## Whether the frame's flush is already queued.
var _flush_queued: bool = false

## The controls a bound button last saw held, past halfway, so a pedal that
## sends 127 until it is let go presses once.
var _held: Dictionary = {}


## *kept* holds the table and *control_drive* is what a binding drives,
## preferences of this object's own and a drive that moves nothing when none is
## given.
func _init(kept: Preferences = null, control_drive: SaControlDrive = null) -> void:
    preferences = kept if kept != null else Preferences.new()
    drive = control_drive if control_drive != null else SaControlDrive.new()
    preferences.changed.connect(_on_preference)


## The key of a control: *kind* is [constant CONTROL], [constant NOTE] or
## [constant BEND], whose *number* is 0.
static func control_key(kind: String, channel: int, number: int) -> String:
    return "%s/%d/%d" % [kind, channel, number]


## What *device*'s *control* drives, `{kind, target, label}`, or an empty
## dictionary when nothing is bound to it.
func find(device: String, control: String) -> Dictionary:
    var controls: Variant = preferences.bindings.get(device, {})
    if not controls is Dictionary:
        return {}
    var binding: Variant = (controls as Dictionary).get(control, {})
    return (binding as Dictionary).duplicate() if _is_binding(binding) else {}


## Binds *device*'s *control* to *target*, `{kind, target, label}`, and answers
## what it drove before, empty when it drove nothing. The table is assigned
## whole, because the setting announces itself in its setter and the file is
## written from that.
func bind(device: String, control: String, target: Dictionary) -> Dictionary:
    var before := find(device, control)
    var table: Dictionary = preferences.bindings.duplicate(true)
    var controls: Variant = table.get(device, {})
    var mine: Dictionary = (controls as Dictionary) if controls is Dictionary else {}
    mine[control] = {"kind": String(target["kind"]), "target": String(target["target"]), "label": String(target["label"])}
    table[device] = mine
    preferences.bindings = table
    return before


## Unbinds *device*'s *control*, and a device left with none leaves the table.
## False when it was not bound.
func remove(device: String, control: String) -> bool:
    if find(device, control).is_empty():
        return false
    var table: Dictionary = preferences.bindings.duplicate(true)
    var mine: Dictionary = table[device]
    mine.erase(control)
    if mine.is_empty():
        table.erase(device)
    preferences.bindings = table
    return true


## Marks *device*'s *control* relative or absolute, so its messages step the dial
## up or down rather than set it across its range. False when nothing is bound to
## it. The mark is kept only while it is true, so an absolute binding reads as it
## always did.
func set_relative(device: String, control: String, on: bool) -> bool:
    if find(device, control).is_empty():
        return false
    var table: Dictionary = preferences.bindings.duplicate(true)
    var mine: Dictionary = table[device]
    var binding: Dictionary = mine[control]
    if on:
        binding["relative"] = true
    else:
        binding.erase("relative")
    mine[control] = binding
    table[device] = mine
    preferences.bindings = table
    return true


## Every binding, `{device, control, kind, target, label}`, devices and then
## controls in the order a sort puts their names, so the page and the dump read
## the same list in the same order every time.
func listed() -> Array:
    var out: Array = []
    var table: Dictionary = preferences.bindings
    var devices: Array = table.keys()
    devices.sort()
    for device: Variant in devices:
        var controls: Variant = table[device]
        if not controls is Dictionary:
            continue
        var keys: Array = (controls as Dictionary).keys()
        keys.sort()
        for control: Variant in keys:
            var binding: Variant = controls[control]
            if not _is_binding(binding):
                continue
            var entry: Dictionary = (binding as Dictionary).duplicate()
            entry["device"] = String(device)
            entry["control"] = String(control)
            out.append(entry)
    return out


## A control change on *device*: a dial bound to it is set or stepped, true when
## a binding took the message.
##
## **Only the last message of a control in a frame is applied.** A fader sends
## hundreds a second, so each message is kept as the pending one for its control
## and a single flush at the frame's end applies the last, a relative control
## summing its steps so none of them is lost.
func drive_control(device: String, channel: int, controller: int, value: int) -> bool:
    var control := control_key(CONTROL, channel, controller)
    if String(find(device, control).get("kind", "")) == BUTTON:
        return _press_on_edge(device, control, value >= RELATIVE_MIDDLE)
    return _queue(device, control, value, TOP)


## A bound button is pressed when its control passes halfway upward and again
## only after it came back down. True when a button is bound to the control.
func _press_on_edge(device: String, control: String, high: bool) -> bool:
    var key := _key(device, control)
    var was := bool(_held.get(key, false))
    _held[key] = high
    if high and not was:
        _press(device, control)
    return true


## Presses the button bound to *control* and writes what it did.
func _press(device: String, control: String) -> void:
    var binding := find(device, control)
    var done := drive.press_button(String(binding.get("target", "")))
    last_driven = {"control": control, "target": String(binding.get("target", "")), "kind": BUTTON, "moved": done}


## A pitch bend on *device*, a fader's 14-bit position, 0 to 16383, driving the
## dial bound to it as a control change does, but across its whole resolution
## rather than cut to seven bits first. True when a binding took the message.
## A bend is always absolute, since a fader has a position and no detents.
func drive_bend(device: String, channel: int, value: int) -> bool:
    return _queue(device, control_key(BEND, channel, 0), value, BEND_TOP)


## Keeps *value*, a message of a control whose range is 0 to *top*, as the
## control's pending one. True when a dial is bound to the control.
func _queue(device: String, control: String, value: int, top: float) -> bool:
    var binding := find(device, control)
    if String(binding.get("kind", "")) != DIAL:
        return false
    var key := _key(device, control)
    var relative := bool(binding.get("relative", false)) and top == TOP
    var entry: Dictionary = _pending.get(key, {"device": device, "control": control, "steps": 0, "value": 0})
    entry["target"] = String(binding["target"])
    entry["label"] = String(binding.get("label", ""))
    entry["relative"] = relative
    entry["top"] = top
    if relative:
        entry["steps"] = int(entry["steps"]) + relative_steps(value)
    else:
        entry["value"] = value
    _pending[key] = entry
    if not _flush_queued:
        _flush_queued = true
        _flush.call_deferred()
    return true


## Applies what each control sent since the last flush, as the end of its frame.
## The deferred call drives it in the running app and a suite reaches the frame's
## end by hand, since a suite runs inside one frame.
func flush() -> void:
    _flush()


## Applies each control's last message of the frame, once the frame ends.
func _flush() -> void:
    _flush_queued = false
    if _pending.is_empty():
        return
    var batch := _pending
    _pending = {}
    var now := Time.get_ticks_msec()
    for key: String in batch:
        _apply(key, batch[key], now)


## Drives one control's pending message, as the last of its frame, and writes
## what it did to [member last_driven] and the corner.
func _apply(key: String, entry: Dictionary, now: int) -> void:
    var value_name := StringName(entry["target"])
    var rested := now - int(_turned.get(key, -REST_MS - 1)) > REST_MS
    _turned[key] = now
    var merge := UndoRedo.MERGE_DISABLE if rested else UndoRedo.MERGE_ENDS
    var moved := (
        _step(value_name, int(entry["steps"]), merge)
        if bool(entry["relative"])
        else _pick_up(key, value_name, int(entry["value"]), float(entry["top"]), merge)
    )
    var driven := {
        "control": String(entry["control"]),
        "target": String(value_name),
        "relative": bool(entry["relative"]),
        "moved": moved,
    }
    if moved:
        var value := drive.read(value_name)
        var ends := drive.range_of(value_name)
        driven["value"] = value
        driven["range"] = [ends.x, ends.y]
        driven["said"] = _say(String(entry["label"]), value)
    last_driven = driven


## A relative message's steps added to the dial, held to its range. True when
## there was a dial to step.
func _step(value_name: StringName, steps: int, merge: UndoRedo.MergeMode) -> bool:
    if steps == 0:
        return false
    var ratio := drive.read_ratio(value_name)
    if is_nan(ratio):
        return false
    return drive.write_ratio(value_name, clampf(ratio + float(steps) * RELATIVE_STEP, 0.0, 1.0), merge)


## An absolute control change: the dial is set to *value* once the control has
## picked it up. The dial's position is wherever the control last left it, so a
## dial moved by the keyboard, the pen or its slider is not jumped to: the
## control changes nothing until it passes where the dial stands, then moves it
## from there. *top* is the control's highest value, and the slack that reads as
## one position scales with it. True when the dial was set.
func _pick_up(key: String, value_name: StringName, value: int, top: float, merge: UndoRedo.MergeMode) -> bool:
    var ratio := drive.read_ratio(value_name)
    if is_nan(ratio):
        return false
    var at := ratio * top
    var last: Variant = _positions.get(key)
    var took := last == null or _passed(float(last), float(value), at, PICKUP_EPSILON * top / TOP)
    _positions[key] = value
    if not took:
        return false
    return drive.write_ratio(value_name, clampf(float(value) / top, 0.0, 1.0), merge)


## The steps a relative control's *value* means: 1 one step up, 127 one step
## down, 64 and 0 nothing, 63 up to 63 and 65 down to 63.
static func relative_steps(value: int) -> int:
    if value == RELATIVE_MIDDLE or value == 0:
        return 0
    return value if value < RELATIVE_MIDDLE else value - 128


## Whether a control that moved from *was* to *now* passed the dial standing at
## *at*, so it takes the dial up from where it is. Near counts as passed, so a
## slider's rounding is not a move of it, within *slack* of the control's units.
static func _passed(was: float, now: float, at: float, slack: float = PICKUP_EPSILON) -> bool:
    return at >= minf(was, now) - slack and at <= maxf(was, now) + slack


## A control's own key in this class's state, device and control apart.
static func _key(device: String, control: String) -> String:
    return device + "\n" + control


## Names the value in the corner while the control turns, and answers the line so
## the dump reads it. Silent where no notice is installed, as a suite's host.
func _say(label: String, value: float) -> String:
    var line := "%s: %s" % [label, String.num(value, 3)]
    SaMessage.notice(line)
    return line


## A note on from *device*: a preset bound to it is chosen, a filter bound to
## it has its command run and a button bound to it is pressed. True when a binding did either.
func drive_note(device: String, channel: int, note: int) -> bool:
    var binding := find(device, control_key(NOTE, channel, note))
    var kind := String(binding.get("kind", ""))
    var target := String(binding.get("target", ""))
    var done := false
    match kind:
        PRESET:
            done = _choose_preset(target)
        FILTER:
            done = _run_filter(StringName(target))
        BUTTON:
            done = drive.press_button(target)
        _:
            return false
    last_driven = {"control": control_key(NOTE, channel, note), "target": target, "kind": kind, "moved": done}
    return done


## A control's key as a painter reads it, "Control 7, channel 1" or "Pitch bend,
## channel 1", the channel counted from one as a controller's own display counts it.
static func control_text(control: String) -> String:
    var parts := control.split("/")
    if parts.size() != 3:
        return control
    var channel := int(parts[1]) + 1
    if parts[0] == BEND:
        var bent := String(TranslationServer.translate_plural("Pitch bend, channel %d", "Pitch bend, channel %d", channel))
        return bent % channel
    if parts[0] == NOTE:
        var note := int(parts[2])
        var said := String(TranslationServer.translate_plural("Note %d, channel %d", "Note %d, channel %d", note))
        return said % [note, channel]
    var controller := int(parts[2])
    var spoken := String(TranslationServer.translate_plural("Control %d, channel %d", "Control %d, channel %d", controller))
    return spoken % [controller, channel]


## What a binding drives, as a painter reads it.
static func target_text(binding: Dictionary) -> String:
    var label := String(binding.get("label", binding.get("target", "")))
    match String(binding.get("kind", "")):
        PRESET:
            return TranslationServer.translate("the preset %s") % label
        FILTER:
            return TranslationServer.translate("the filter %s") % label
        BUTTON:
            return TranslationServer.translate("the button %s") % label
    return label


## Chooses *preset* through the drive. A preset deleted since it was bound
## says so.
func _choose_preset(preset: String) -> bool:
    if drive.choose_preset(preset):
        return true
    SaMessage.notice(TranslationServer.translate('The preset "%s" a MIDI note chooses is gone.') % preset)
    return false


## Runs the command of the filter registered under *key* through the drive,
## which opens its dialog. A filter not loaded says so.
func _run_filter(key: StringName) -> bool:
    if drive.run_filter(key):
        return true
    SaMessage.notice(TranslationServer.translate('The filter "%s" a MIDI note opens is not loaded.') % key)
    return false


func _on_preference(key: StringName) -> void:
    if key == Preferences.BINDINGS:
        changed.emit()


## Whether *binding* is the shape [method bind] writes, so a hand-edited
## profile cannot hand the drive a target with no kind.
static func _is_binding(binding: Variant) -> bool:
    if not binding is Dictionary:
        return false
    var shape := binding as Dictionary
    return String(shape.get("kind", "")) in [DIAL, PRESET, FILTER, BUTTON] and not String(shape.get("target", "")).is_empty()
