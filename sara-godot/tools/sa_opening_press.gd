class_name SaOpeningPress
extends RefCounted
## A press of a tool that paints, refused while an open still fills the
## document in, before the tool sees it.
##
## A layer of a document still opening refuses paint, which a tool's own guard
## reads through `SaLayer.refuses_paint`. Not every tool asks it: a brush from
## a module may ask the layer's lock alone, and a stroke on a mask asks the
## mask's owner. So the machine asks [method take] for every event it is about
## to hand its tool, and the press of a painting tool on a document still
## filling stops here, with the open's progress in the corner, whatever the
## tool asks. A stroke there would paint over chunks the open is about to
## replace. The motions still reach the tool, which draws its cursor from them.


## Whether *event* is the left press of *machine*'s painting tool on a
## document an open still fills, which then says so in the corner and is
## handed no further.
static func take(event: InputEvent, machine: ToolMachine) -> bool:
    var button := event as InputEventMouseButton
    if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
        return false
    var document := machine.surface.get_document() if machine.surface != null else null
    if document == null or not SaSadFile.filling(document):
        return false
    var descriptor := machine.get_descriptor(machine.active_tool_name)
    if descriptor == null or not descriptor.is_painting:
        return false
    EventBus.paint_refused.emit(SaSadFile.opening_refusal(document, TranslationServer.translate("stroke")))
    return true
