## A tool's own chord puts the tool in the hand, and a detour's chord pressed
## again goes back to the tool before it.
##
## **A detour's chord is a toggle**, as a filter's is. A tool whose
## descriptor sets [member SaToolDescriptor.is_detour] is one a painter
## steps into from painting and out of again, so its chord pressed while it is
## already the permanent tool takes the hand back through
## [method ToolMachine.return_to_previous_tool], the way the Transform's Enter
## does. A tool that is no detour is where the painter goes back to, and its
## chord pressed again keeps it, so B pressed to be sure of the Brush stays on
## the Brush.
##
## Going back is a switch like any other, so the tool left is `reset`, which
## puts a Transform's lift or a Crop's rectangle back as Escape does rather
## than writing it, because only Enter commits. The chord is the
## descriptor's InputMap action, where a rebind is written, so a rebound chord
## toggles the same way.
##
## Kept out of the router, in a folder of its own beside it.
class_name SaToolKeys
extends RefCounted


## Answers the action of the tool whose chord *event* is, after putting that
## tool in *machine*'s hand, or the tool before it when that tool is a detour
## already there. `&""` when *event* is no registered tool's chord. A press
## only, never its repeat, so a held key does not flick between the two.
static func answer(machine: ToolMachine, event: InputEvent) -> StringName:
    if machine == null or machine.registry == null:
        return &""
    # A registered tool names its own action on its descriptor, so a module's
    # tool gets its key through the same door as a built-in and needs no row in
    # any table of the router's.
    var registry: SaToolRegistry = machine.registry
    for descriptor: SaToolDescriptor in registry.list_descriptors():
        var action := String(descriptor.activate_action)
        if action.is_empty() or not SaShortcutKeys.pressed(event, [action], false, true):
            continue
        if not machine.registered_tools.has(descriptor.id):
            continue
        if descriptor.is_detour and machine.default_tool_name == descriptor.id:
            machine.return_to_previous_tool()
        else:
            # B picks the Brush under the engine it last painted with.
            machine.set_active_tool(registry.picked(descriptor.id))
        return descriptor.activate_action
    return &""
