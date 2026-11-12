## The rows of the one right-click menu every selection tool shares, and the
## test for which tools those are.
##
## The menu of a lasso or a marquee is one menu, with Transform Selection in
## it as Photoshop has it, rather than one put together from each tool's own
## options. It is the same rows in the same order whichever selection tool is in hand: the
## selection mode the next shape lands in, the Feather that shape is drawn
## with, and then what can be done to the selection that stands, Transform
## Selection, Feather..., Invert, Deselect, and Layer via Copy and Cut. A row
## the tool in hand has nothing behind, the mode on Select Subject, is dimmed
## rather than left out, so the rows never move under the hand, and a command
## is dimmed while there is no selection for it to act on.
##
## What only one tool has, the wand's Contiguous or a lasso's Anti-aliasing,
## stays on the bar and the Tool Options docker, so the menu reads the same
## everywhere.
##
## **A selection tool** is one of the `select` category that reads Shift and
## Alt on its own press, which is how every tool that makes a selection takes
## Add and Subtract. The Patch shares the category, since it acts on the
## selection the others made, and reads neither key, so its menu stays its own.
## A module's tool that declares the same two is a selection tool here with no
## line of this file naming it.
class_name SelectionMenuRows
extends RefCounted

## The option every selection tool's mode is declared under.
const MODE_KEY: StringName = &"selection_mode"

## The option every selection tool's Feather is declared under, which the
## menu's Feather row reads and writes.
const FEATHER_KEY: StringName = &"feather"

## The four modes in the order the bar lists them, each with its words, so a
## tool that declares no mode still shows the four rows, dimmed.
const MODES: Array = [
    [SaSelection.Mode.REPLACE, "Replace"],
    [SaSelection.Mode.ADD, "Add"],
    [SaSelection.Mode.SUBTRACT, "Subtract"],
    [SaSelection.Mode.INTERSECT, "Intersect"],
]

## The commands under the mode, in menu order. A command no module registered
## is left out, so a build without the transform has a menu without its row.
const COMMANDS: Array[StringName] = [
    &"select_transform",
    &"select_feather",
    &"select_invert",
    &"select_none",
    &"layer_via_copy",
    &"layer_via_cut",
    &"layer_via_seamless_cut",
]


## Whether *descriptor*, which may be null, is a selection tool, the test the
## heading of this file gives.
static func makes_a_selection(descriptor: SaToolDescriptor) -> bool:
    return (
        descriptor != null
        and descriptor.category == &"select"
        and SaToolDescriptor.reads_key(descriptor, KEY_SHIFT)
        and SaToolDescriptor.reads_key(descriptor, KEY_ALT)
    )


## The spec *descriptor* declares under *key*, or null.
static func spec_of(descriptor: SaToolDescriptor, key: StringName) -> SaOptionSpec:
    if descriptor == null:
        return null
    for spec: SaOptionSpec in descriptor.options:
        if spec.key == key:
            return spec
    return null


## The commands of [constant COMMANDS] that *registry* holds, in menu order.
static func commands_in(registry: SaCommandRegistry) -> Array[SaCommandDescriptor]:
    var out: Array[SaCommandDescriptor] = []
    if registry == null:
        return out
    for command_id: StringName in COMMANDS:
        var descriptor := registry.get_descriptor(command_id)
        if descriptor != null:
            out.append(descriptor)
    return out
