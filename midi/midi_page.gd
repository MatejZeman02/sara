## Preferences > MIDI: the Listen switch, the controllers Sara hears, a
## Rescan, which is the only way Godot sees one plugged in later, and what each
## control was mapped to, with a Remove for each.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Private to this module, built by the facade's `preferences_page`. The device
## list is a label the page rewrites whenever the facade opens or closes the
## inputs, rather than a page built again, because Listen is one of the rows and
## a page rebuilt from inside its own toggle's write frees the toggle under it.
## The bindings are a column of lines rebuilt the same way, whenever the table
## moves, and a Remove pressed frees only its own line's row.
extends SaSettingsPage

const Bindings := preload("midi_bindings.gd")
const Midi := preload("midi.gd")

## The name of each binding's Remove button, which a scenario presses by name.
const REMOVE_NAME := "RemoveBinding"

## The name of each binding's Relative switch, which marks an endless encoder.
const RELATIVE_NAME := "RelativeBinding"

## The facade the page shows and drives, set before `super()` builds the rows.
var _midi: Midi = null

## The device list's text, rewritten from the facade.
var _devices: Label = null

## The bindings, a line each, rebuilt from the facade's bindings.
var _bindings: VBoxContainer = null


func _init(midi: Midi) -> void:
    _midi = midi
    _devices = Label.new()
    _devices.name = "Devices"
    _devices.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _devices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _bindings = VBoxContainer.new()
    _bindings.name = "Bindings"
    _bindings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    super()
    _midi.devices_changed.connect(_show_devices)
    _midi.bindings.changed.connect(_show_bindings)
    _show_devices()
    _show_bindings()


func build(ui: SaPage) -> void:
    var rows := ui.section(tr("MIDI controllers"))
    var listen := rows.toggle("Listen", _midi.bindings.preferences, ^"listen").named(&"listen")
    listen.explain(tr("Opens every connected MIDI controller, so its knobs and keys reach Sara. Off, other programs keep them."))
    rows.custom("Devices", _devices).named(&"devices").explain(tr("The controllers Sara hears, by the names they give."))
    var rescan := rows.action("Look for controllers", _midi.rescan).button("Rescan").named(&"rescan")
    rescan.explain(tr("Looks again, for a controller plugged in since Listen was turned on."))
    listen.dims(rescan)
    var mapped := ui.section(tr("Mapped controls"))
    mapped.custom("Bindings", _bindings).named(&"bindings").explain(
        tr("What each knob, fader and key drives, under the controller it is on. Map to MIDI binds another.")
    )


## The names of the inputs open, one a line, then every sentence the facade
## has, so the list is never empty with nothing to say why.
func _show_devices() -> void:
    var lines := PackedStringArray()
    for device: String in _midi.devices:
        lines.append(device)
    lines.append_array(_midi.sentences())
    _devices.text = "\n".join(lines)


## A line a binding, the device, the control and what it drives, each with its
## Remove, or the sentence saying how one is made when there are none.
func _show_bindings() -> void:
    for line: Node in _bindings.get_children():
        _bindings.remove_child(line)
        line.queue_free()
    var listed := _midi.bindings.listed()
    if listed.is_empty():
        var none := Label.new()
        none.name = "NoBindings"
        none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        none.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        none.text = tr("Nothing is mapped. Press Map to MIDI, click a slider, a brush preset or a filter, then move a control.")
        _bindings.add_child(none)
        return
    for binding: Dictionary in listed:
        var line := HBoxContainer.new()
        line.name = "Binding"
        var said := Label.new()
        said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        said.text = (
            "%s: %s, %s"
            % [String(binding["device"]), Bindings.control_text(String(binding["control"])), Bindings.target_text(binding)]
        )
        line.add_child(said)
        var relative := SaMake.switch(line, RELATIVE_NAME, tr("Relative"), bool(binding.get("relative", false)))
        relative.tooltip_text = tr(
            "Marks this control an endless encoder, so it steps the value up or down rather than setting it."
        )
        relative.toggled.connect(
            func(on: bool) -> void: _midi.bindings.set_relative(String(binding["device"]), String(binding["control"]), on)
        )
        var remove := Button.new()
        remove.name = REMOVE_NAME
        remove.text = tr("Remove")
        remove.tooltip_text = tr("Unbind this control.")
        remove.pressed.connect(_midi.bindings.remove.bind(String(binding["device"]), String(binding["control"])))
        line.add_child(remove)
        _bindings.add_child(line, true)


## What every bindings list on screen shows, a line each with whether its
## Remove is drawn, so the dump reads what the page's shot shows.
static func shown_lines(root: Window) -> Array:
    var out: Array = []
    if root == null:
        return out
    for list: Node in root.find_children("Bindings", "VBoxContainer", true, false):
        if not (list as Control).is_visible_in_tree():
            continue
        for line: Node in list.get_children():
            var said := line.get_child(0) as Label if line.get_child_count() > 0 else line as Label
            var remove := line.get_node_or_null(REMOVE_NAME) as Button
            (
                out
                . append(
                    {
                        "text": said.text if said != null else "",
                        "remove": remove != null and remove.is_visible_in_tree(),
                    }
                )
            )
    return out
