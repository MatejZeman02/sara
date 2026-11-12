## A left press of a painting tool that begins no stroke, said in the log with
## what took it, so a first dab lost after a preset pick names itself the next
## time.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Why it exists.** A first press on the canvas after a brush preset was
## picked once laid nothing, and a second that painted, and nothing in
## the log said which stop of the machine's route the first had met. So each
## stop that can keep a painting tool's press from beginning its stroke says so
## here, and so does the tool itself when it hears the press and refuses it on
## `EventBus.paint_refused`, a hidden or a locked layer. A press that begins a
## stroke is said already, by the `Sara stroke:` line its stroke ends with, and
## this says nothing for it.
##
## **One instance a press.** [method hear] listens on `paint_refused` while the
## tool is handed the press and [method done] lets go, so a refusal said at any
## other moment is never pinned on a press.
class_name SaUnpaintedPress
extends RefCounted

## What every line begins with, the word a reader of the log searches for.
const PREFIX := "Sara press: began no stroke, "

## The last line said, which a suite reads because a print is not something a
## test can hear.
static var last_line: String = ""

## The tool the press was handed to.
var _tool_name: StringName = &""

## The reason the tool gave while it was handed the press, empty for none.
var _refusal: String = ""


func _init(tool_name: StringName) -> void:
    _tool_name = tool_name


## Whether *event* is a left press while *machine* holds a painting tool, the one
## press this line is about. A press of a selection, a fill or the view's tools
## begins no stroke by design.
static func watched(event: InputEvent, machine: ToolMachine) -> bool:
    var button := event as InputEventMouseButton
    if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
        return false
    var descriptor := machine.get_descriptor(machine.active_tool_name)
    return descriptor != null and descriptor.is_painting


## Says that the press began no stroke, because *why*.
static func print_why(why: String) -> void:
    last_line = PREFIX + why
    print(last_line)


## Says why a press began no stroke, when *about* says it is the press this
## line is about, the answer of [method watched].
static func print_why_if(about: bool, why: String) -> void:
    if about:
        print_why(why)


## Listens for the tool's refusal while it is handed the press.
func hear() -> void:
    EventBus.paint_refused.connect(_on_refused)


## Lets go of the refusal, and says it when the tool gave one.
func done() -> void:
    if EventBus.paint_refused.is_connected(_on_refused):
        EventBus.paint_refused.disconnect(_on_refused)
    if not _refusal.is_empty():
        print_why("the %s tool refused it: %s" % [_tool_name, _refusal])


func _on_refused(reason: String) -> void:
    _refusal = reason
