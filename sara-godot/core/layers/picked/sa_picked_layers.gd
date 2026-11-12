## The layers the painter picked in the Layers docker, held on the document so
## the Layer menu's commands act on the set the docker's buttons act on.
##
## A command that read the active layer alone, while the buttons read the
## picked rows, would have Ctrl+E merge the active layer into a layer the
## painter never picked. `core` never names `ui`, so the docker hands its pick
## here whenever the pick moves, and the commands ask.
##
## **A set is trusted only while it holds the active layer**, the rule the
## docker's own list keeps after a rebuild: an operation that made a new layer
## active, a duplicate or a group, replaced the set, and the set is then the
## active layer alone. A layer that left the document since is dropped, so a
## stale pick can never reach a layer the stack no longer has.
class_name SaPickedLayers
extends RefCounted

var _picked: Array[SaLayer] = []


## The docker's rows were picked anew, as *layers*, which the next command
## reads. Not a setter of a member another class reads: what a command acts on
## is `acted_on`, which checks the pick against the document first.
func pick(layers: Array[SaLayer]) -> void:
    _picked = layers.duplicate()


## The layers a Layer menu command acts on in *document*, the one holding this
## pick, in the docker's order, top of the stack first: the picked set while it
## holds the active layer and is still in the document, and the active layer
## alone otherwise. Empty with no active layer. The document is an argument
## rather than a member, so the pick it holds holds nothing back.
func acted_on(document: SaDocument) -> Array[SaLayer]:
    var out: Array[SaLayer] = []
    var active := document.active_layer if document != null else null
    if active == null:
        return out
    for layer in _picked:
        if is_instance_valid(layer) and document.is_ancestor_of(layer) and not out.has(layer):
            out.append(layer)
    if not out.has(active):
        out = [active]
    return out
