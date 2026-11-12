## Layer > Edit Smart Layer Contents: the command that opens the active smart
## layer alone and untransformed over a solid grey, to paint into, and closes
## it again so the transform shows over the source as edited.
##
## A solid grey rather than the transparent checker Photoshop shows a Smart
## Object over, because the checker hides some parts of the paint, and the grey
## is a backdrop of the view that never reaches the layer.
##
## **A toggle in the style of Isolate Active Layer**, because the view is
## `SaLocalView`'s, kept out of the document, out of a merge and out of an
## export as isolation is, and framed the same way. The grey is the canvas's
## `SaContentsBackdrop`, and the sign at the foot of the room says what is open
## and how to close it, `SaIsolateActiveLayer`. Opening it ends isolation, and
## Isolate Active Layer pressed while it is open closes it.
class_name SaEditSmartLayerContents
extends RefCounted

const COMMAND := &"layer_edit_contents"
## The command's name in the menu, in the corner and in the sign.
const NAME := "Edit Smart Layer Contents"


## Registers the command against *ctx*. It acts on the main canvas, whose view
## it frames, as Isolate Active Layer does.
static func register_command(ctx: SaContext) -> void:
    var reach := SaIsolateActiveLayer.reach_of(ctx)
    var command := SaCommandDescriptor.create(COMMAND, "Edit the smart layer's contents", func() -> bool: return toggle(reach))
    command.label = NAME
    command.category = &"layer"
    command.sentence = (
        "Show the active smart layer alone, as it was painted, over a grey that is never part of the picture,"
        + " and paint into it with any tool. Again closes it and draws the transform over what you painted."
    )
    command.checked = func() -> bool: return SaLocalView.contents_of(SaIsolateActiveLayer.document_of(reach)) != null
    command.enabled = func() -> bool: return _can_open(SaIsolateActiveLayer.document_of(reach))
    ctx.register_command(command)


## Opens the contents of the active layer of the main canvas's document, or
## closes them, and answers whether it did either. A layer that is not smart
## says why in the corner.
static func toggle(ctx: SaContext) -> bool:
    var surface := SaIsolateActiveLayer.surface_of(ctx)
    if surface == null or surface.view == null or surface.get_document() == null:
        return false
    var document := surface.get_document()
    if SaLocalView.contents_of(document) != null:
        SaLocalView.end(document, surface.view)
        SaMessage.notice(TranslationServer.translate("The smart layer's contents are closed"))
        return true
    return open(document, surface.view, surface.view.get_free_rect())


## Opens the contents of *document*'s active layer, framed in *area* of *view*,
## and answers whether it did. Isolation gives way first. An ordinary layer is
## refused with a sentence in the corner.
static func open(document: SaDocument, view: SaView, area: Rect2) -> bool:
    var layer := document.active_layer if document != null else null
    if layer == null or not SaLiveTransform.can_bake(layer):
        var plain := "'%s' is not a smart layer, so it has no contents to open. Layer > Make Smart Layer makes it one."
        SaProblems.refuse(NAME, TranslationServer.translate(plain) % (String(layer.name) if layer != null else ""))
        return false
    if SaLocalView.is_on(document):
        SaLocalView.end(document, view)
    return SaLocalView.begin(document, view, area, layer)


## Whether a press would open or close something: contents open, or a smart
## active layer to open.
static func _can_open(document: SaDocument) -> bool:
    if document == null:
        return false
    return SaLocalView.contents_of(document) != null or SaLiveTransform.can_bake(document.active_layer)
