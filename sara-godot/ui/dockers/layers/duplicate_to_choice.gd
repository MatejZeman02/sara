## The Duplicate To row of the Layer menu and of the menu a right click opens
## on the Layers docker: one row that opens a list of the other open documents,
## and a pick from it that copies the active layer or group into that one,
## `SaLayerDuplicateTo`'s copy, on top of its stack and as one undo step there.
##
## Photoshop's Duplicate Layer offers a destination document, and Krita's drag
## to another view does the same, so a painter who splits a picture across two
## files carries a group painted in one back into the other. The document in
## front stays in front, so the painter sees what was copied and not what it
## was copied into.
##
## An effect layer whose input the other document has no layer for is copied
## reading nothing, and the corner says which, rather than the input being
## dropped in silence.
class_name SaDuplicateToChoice
extends RefCounted

## The row's id in both menus.
const ROW := &"layer_duplicate_to"
## What the row reads and says on hover.
const WORDS := "Duplicate To"
const SENTENCE := "Copy the layer or group into another open document, on top of its layers."
## The child list's node name under the menu it opens beside.
const LIST_NAME := "DuplicateToList"
## What the corner says once the copy is made.
const DONE := "Copied '%s' into %s."

var _document: SaDocument
var _held: SaDocuments


## *document* is the one the active layer is copied from, and *host* any node
## of the tree whose scene holds the open documents, the running scene when
## null, which is what the menu rows ask with no node of their own.
func _init(document: SaDocument, host: Node = null) -> void:
    _document = document
    var scene: Node = host
    if host == null or host.is_inside_tree():
        var tree := host.get_tree() if host != null else Engine.get_main_loop() as SceneTree
        scene = tree.current_scene if tree != null else null
    var held: Object = scene.get("documents") if scene != null else null
    _held = held as SaDocuments if held is SaDocuments else null


## The open documents a copy can go into, every one but the source.
func targets() -> Array[SaSurface]:
    var out: Array[SaSurface] = []
    if _held == null:
        return out
    for surface in _held.surfaces:
        if surface.get_document() != null and surface.get_document() != _document:
            out.append(surface)
    return out


## Whether the row can act: a layer to copy and another document to copy it to.
func live() -> bool:
    return _document != null and _document.active_layer != null and not targets().is_empty()


## Fills the list with the other documents by name, opens it beside *popup*'s
## row *key* and answers it. A row's id is its surface's, so two copies of one
## file are two rows, and a press copies there.
func open_beside(popup: SaChoicePopup, key: StringName = ROW) -> SaChoicePopup:
    var list := popup.get_node_or_null(LIST_NAME) as SaChoicePopup
    if list == null:
        list = SaChoicePopup.new()
        list.name = LIST_NAME
        popup.add_child(list)
    list.clear()
    for surface in targets():
        list.add_row(surface.id, SaDocumentFiles.display_name(surface.get_document()), false, false)
    if not list.chosen.is_connected(pick):
        list.chosen.connect(pick)
    popup.open_child(list, key)
    return list


## Copies the active layer or group into the open document whose surface is
## *id*, and says in the corner what was copied and what the copy cannot read.
## Answers the copy's answer, empty when *id* names no other document.
func pick(id: StringName) -> Dictionary:
    for surface in targets():
        if surface.id != id:
            continue
        var into := surface.get_document()
        var layer := _document.active_layer
        var answer := SaLayerDuplicateTo.new(_document, into).write(layer)
        if answer.has("error"):
            EventBus.corner_notice.emit(tr(String(answer["error"])))
            return answer
        var lines: Array[String] = [tr(DONE) % [layer.name, SaDocumentFiles.display_name(into)]]
        for missing: String in answer["missing"]:
            lines.append(missing)
        EventBus.corner_notice.emit(" ".join(lines))
        return answer
    return {}
