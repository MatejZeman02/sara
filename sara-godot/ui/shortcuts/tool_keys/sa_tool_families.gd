## Shift with a tool's key steps through that tool's family, the tools that
## share its button in the toolbox.
##
## **The family is the toolbox's group**, read live through [SaToolBoxGroups],
## so a painter who drags a tool into another button moves it into that key's
## family as well, and the order of the cycle is the order of the flyout. The
## cycle wraps after the last member, a tool the painter hid from the toolbox
## is skipped, and a press while no member is in hand picks the first of them,
## which is the button's own first tool. A tool that is alone in its group is
## just picked, so Shift with its key is never dead.
##
## **One command per key**, registered through the same door a module's
## command uses, so each shows on the Keyboard Shortcuts page and can be
## rebound. The row names the tool the bare key picks and answers for that
## tool's family, so rebinding the tool's own key does not move it.
##
## **Which keys have one.** Every bare tool key of Sara's own map whose Shift
## chord is free or was a docker toggle's. Q is left out because Shift+Q is
## Quick Favourites, which is a command and not a docker. Under the Photoshop
## profile Shift with a letter steps a group natively, so its table names the
## same chords. Krita keeps Shift+W for its wrap and Shift+I for the colour
## picker, so its table leaves those two cycles unbound.
class_name SaToolFamilies
extends RefCounted

## One row per command: its id, the tool the bare key picks, the key and the
## title and sentence the row reads as. Whole sentences per row, so a language
## that declines a group's name translates each as one message.
const ROWS: Array = [
    [
        &"tool_family_brush",
        &"brush",
        KEY_B,
        "Step through the Brush group",
        "Put the next tool of the Brush's group in hand, and the Brush itself when it is alone. Wraps after the last."
    ],
    [
        &"tool_family_crop",
        &"crop",
        KEY_C,
        "Step through the Crop group",
        "Put the next tool of the Crop's group in hand, and the Crop itself when it is alone. Wraps after the last."
    ],
    [
        &"tool_family_gradient",
        &"gradient",
        KEY_G,
        "Step through the Fill and Gradient tools",
        "Put the next tool of the Fill and Gradient group in hand, the Fill first when neither is. Wraps after the last."
    ],
    [
        &"tool_family_eyedropper",
        &"eyedropper",
        KEY_I,
        "Step through the Eyedropper group",
        "Put the next tool of the Eyedropper's group in hand, and the Eyedropper itself when it is alone. Wraps after the last."
    ],
    [
        &"tool_family_eraser",
        &"eraser",
        KEY_E,
        "Step through the Eraser group",
        "Put the next tool of the Eraser's group in hand, and the Eraser itself when it is alone. Wraps after the last."
    ],
    [
        &"tool_family_marquee",
        &"marquee",
        KEY_M,
        "Step through the selection tools",
        "Put the next tool of the selection group in hand, the rectangle first when none is. Wraps after the last."
    ],
    [
        &"tool_family_patch",
        &"patch",
        KEY_J,
        "Step through the Patch group",
        "Put the next tool of the Patch's group in hand, and the Patch itself when it is alone. Wraps after the last."
    ],
    [
        &"tool_family_lasso",
        &"lasso",
        KEY_L,
        "Step through the lassos",
        "Put the next lasso in hand, the freehand one first when none is. Wraps after the last."
    ],
    [
        &"tool_family_wand",
        &"wand",
        KEY_W,
        "Step through the Magic Wand group",
        "Put the next tool of the Magic Wand's group in hand, and the wand itself when it is alone. Wraps after the last."
    ],
]


## Registers every row against whatever module *ctx* belongs to.
## *tool_machine_provider* answers the main canvas's tool machine, and a host
## with none, which a suite that only wants the rows builds, gets commands that
## decline.
static func register_all(ctx: SaContext, tool_machine_provider: Callable) -> void:
    for row: Array in ROWS:
        var command := SaCommandDescriptor.create(row[0], row[3], _cycle.bind(tool_machine_provider, row[1]))
        command.default_events = [SaAppCommands.chord(row[2], false, true)]
        command.category = &"tool"
        command.sentence = row[4]
        ctx.register_command(command)


## The tool to put in hand: the member after *active* in *members*, wrapping,
## or the first member when *active* is not one of them, and empty when there
## are none. Pure, so the order is testable with no machine.
static func next_member(members: Array, active: StringName) -> StringName:
    if members.is_empty():
        return &""
    var at := members.find(active)
    if at < 0:
        return StringName(members[0])
    return StringName(members[(at + 1) % members.size()])


## The tools of *tool_id*'s toolbox group that a press can reach, in the
## toolbox's order: registered on *machine* and not hidden from the toolbox.
static func family_of(machine: ToolMachine, tool_id: StringName) -> Array[StringName]:
    var out: Array[StringName] = []
    if machine == null or machine.registry == null:
        return out
    var descriptors: Array = machine.registry.list_tools()
    var by_id: Dictionary = {}
    for descriptor: SaToolDescriptor in descriptors:
        by_id[String(descriptor.id)] = descriptor
    for group: Array in SaToolBoxGroups.stored(descriptors):
        if not group.has(String(tool_id)):
            continue
        for member: String in group:
            var descriptor: SaToolDescriptor = by_id[member]
            var shown := SaSettings.get_element_visible(SaDockerIds.TOOLBOX, SaToolBoxGrid.layout_entry_for(descriptor))
            if shown and machine.registered_tools.has(descriptor.id):
                out.append(descriptor.id)
        return out
    return out


static func _cycle(tool_machine_provider: Callable, tool_id: StringName) -> bool:
    var machine := tool_machine_provider.call() as ToolMachine if tool_machine_provider.is_valid() else null
    if machine == null or machine.registry == null:
        return false
    var members := family_of(machine, tool_id)
    if members.is_empty():
        return false
    var next := next_member(members, machine.registry.tool_of(machine.default_tool_name))
    # The engine the painter last painted with, as the bare key picks it.
    machine.set_active_tool(machine.registry.picked(next))
    return true
