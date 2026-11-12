## File > New from Clipboard: a document the size of the picture on the
## clipboard, holding it as its one layer.
##
## Without it, a painter who copied a reference or a screenshot makes a
## document of a guessed size first and pastes into it. The clipboard is read in Paste's order, Sara's own when
## Copy left something there and the desktop has not been given a picture
## since, `SaClipboard.desktop_changed`, and the desktop's otherwise, through
## `SaDesktopPicture.read`, which is what Paste reads too.
##
## **Read before the question, built in its answer.** `read` looks at the
## clipboard and says so in the corner when it holds no picture, so the
## unsaved-changes question is never asked for a command that would make
## nothing. `make` then throws the open document away and builds the new one in
## its place, as New and Open do, because Sara holds one document.
##
## None of the steps the build commits is an edit a painter made, so they run
## quietly and the history is cleared after, the way an opened picture's are
## (`SaDocumentFiles.open_picture_into`). The document stays modified and
## nameless, so Save asks where and closing asks whether.
class_name SaNewFromClipboard
extends RefCounted

## What the corner says when neither clipboard holds a picture.
const NO_PICTURE := "The clipboard holds no picture. Copy in Sara, or put a picture on the desktop clipboard."

## What the layer made from Sara's own clipboard is called, the name Paste gives it.
const HELD_NAME := "Pasted Layer"

## The ground the document is built on: none, so the picture is its one layer.
const NO_GROUND: Dictionary = {SaDocumentBackground.KIND: SaDocumentBackground.TRANSPARENT}

## The picture on the desktop clipboard, `SaDesktopPicture.read` in everything
## but a suite: a headless run has no desktop clipboard, and a run on the
## machine of whoever runs the gate would take whatever they last copied.
## Answers an `SaDesktopPicture` or null.
## Test seam. A suite that replaces it puts `SaDesktopPicture.read` back.
static var desktop_picture: Callable = SaDesktopPicture.read

## The desktop's picture, or null when the document is made from Sara's own
## clipboard.
var _picture: SaDesktopPicture = null

## Sara's own clipboard, the one every open document shares, or null.
var _held: SaClipboard = null


func _init(picture: SaDesktopPicture, held: SaClipboard) -> void:
    _picture = picture
    _held = held


## What Sara's clipboard *held* and then the desktop's hold, or null after
## saying in the corner that there is no picture. The desktop is not asked when
## Sara's own clipboard holds something and the desktop still holds its mark,
## as Paste does not ask it. A desktop given a picture since is taken first,
## and one given only words leaves Sara's copy the one taken.
static func read(document: SaDocument, held: SaClipboard) -> SaNewFromClipboard:
    if document == null:
        return null
    var sara_first := held != null and not held.is_empty()
    if sara_first and not held.desktop_changed():
        return SaNewFromClipboard.new(null, held)
    var picture := desktop_picture.call() as SaDesktopPicture if desktop_picture.is_valid() else null
    if picture == null or picture.image == null or picture.image.is_empty():
        if sara_first:
            return SaNewFromClipboard.new(null, held)
        SaMessage.notice(TranslationServer.translate(NO_PICTURE))
        return null
    return SaNewFromClipboard.new(picture, held)


## What the document made from the clipboard needs of the card's memory: a
## canvas of the picture's size, covered.
func needs() -> int:
    var size := _picture.image.get_size() if _picture != null else _held.bounds.size
    return SaCardMemory.for_canvas(size, size.x * size.y)


## Makes *document* the clipboard's picture and answers its one layer, or null
## when nothing could be built.
func make(document: SaDocument) -> SaLayer:
    if document == null or (_picture == null and (_held == null or _held.is_empty())):
        return null
    var build := _from_desktop.bind(document) if _picture != null else _from_held.bind(document)
    if _picture != null:
        var named := SaImageImport.depth_for(_picture.image)
        var depth: int = named if named >= 0 else SaImportFitDialog.remembered_depth()
        var space := _picture.space.with_depth(depth as SaColorSpace.Depth)
        document.reset_to_default(_picture.image.get_size(), space, document.dpi, NO_GROUND)
    else:
        var copied := _held.space if _held.space != null else document.color_space
        document.reset_to_default(_held.bounds.size, copied, document.dpi, NO_GROUND)
    var layer := document.history.quietly(build) as SaLayer if document.history != null else build.call() as SaLayer
    if document.undo_redo != null:
        document.undo_redo.clear_history()
    if document.history != null:
        document.history.reset()
    if layer != null:
        document.modified = true
    return layer


## The desktop's picture put down at the origin, under its own name.
func _from_desktop(document: SaDocument) -> SaLayer:
    var layer := SaImageImport.place(document, _picture.image, _picture.layer_name, _picture.space, SaImageImport.Fit.ORIGIN)
    return _alone(document, layer)


## Sara's own clipboard put down on a canvas of the copy's size. Paste centres
## a copy on a canvas of another size, and centred on its own size is at
## the origin, so the region lands at the corner re-tiled on the GPU with no
## crop after it.
func _from_held(document: SaDocument) -> SaLayer:
    return _alone(document, _held.paste(document, HELD_NAME))


## *layer* as the document's only one, the empty paint layer a fresh document
## comes with taken off.
static func _alone(document: SaDocument, layer: SaLayer) -> SaLayer:
    if layer == null:
        return null
    var ops := SaLayerOps.new(document)
    for spare: SaLayer in ops.layers():
        if spare != layer:
            ops.remove(spare)
    # The layers docker rebuilds when the active layer is named again, which is
    # true anyway, as `SaDocumentFiles` gives for an opened picture.
    document.set_active_layer(layer)
    return layer
