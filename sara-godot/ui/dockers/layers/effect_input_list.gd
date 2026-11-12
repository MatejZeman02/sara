## The list beside the More menu's Input row of an effect layer: every node of
## the document the layer can read, a layer or a group, and None, with the one
## it reads ticked. A choice points the layer at it through
## `SaEffectLayer.read`, one history step. A node the layer would read itself
## through, or one that holds no paint of its own, is listed dimmed with the
## sentence that says why, so the list shows the whole tree in its order.
@tool
class_name SaEffectInputList
extends SaChoicePopup

## The row that reads nothing.
const NONE_ROW := &"effect_input_none"

var _document: SaDocument = null
var _effect: SaLayer = null
## Row id to the node it reads.
var _nodes: Dictionary[StringName, SaLayer] = {}


func _init() -> void:
    super(false)
    name = "EffectInputList"
    chosen.connect(_on_chosen)


## The rows for *effect* in *document*, the tree top first as the docker shows
## it.
func fill(document: SaDocument, effect: SaLayer) -> void:
    clear()
    _document = document
    _effect = effect
    _nodes = {}
    if document == null or effect == null:
        return
    add_row(NONE_ROW, tr("None"), true, effect.source == null)
    var children := document.get_children()
    children.reverse()
    for child in children:
        var node := child as SaLayer
        if node == null or node == effect:
            continue
        var id := StringName("effect_input_%d" % node.get_instance_id())
        _nodes[id] = node
        var refused := SaEffectLayer.refusal(effect, node)
        var label := "  ".repeat(SaLayerStack.depth(node)) + str(node.name)
        add_row(id, label, true, SaEffectLayer.input_of(effect) == node, "", "", not refused.is_empty(), refused)


## The node a row reads, null for None and for an id not in the list.
func node_of(id: StringName) -> SaLayer:
    return _nodes.get(id, null)


func _on_chosen(id: StringName) -> void:
    if _document == null or _effect == null:
        return
    if id == NONE_ROW or _nodes.has(id):
        SaEffectLayer.read(_document, _effect, node_of(id))
