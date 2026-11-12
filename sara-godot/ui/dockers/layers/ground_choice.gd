## The Ground row of the Layer menu and of the Layers docker's add arrow: one
## row that opens a list of every ground, and a pick from it that swaps the
## ground the document has, or lays one when it has none.
##
## One row that swaps rather than a row per ground that adds a layer, so a
## document never stands on two grounds by two presses.
##
## **The list is `SaGeneratedLayer.grounds`**, every registered type that
## stores nothing and answers a height, so a module's ground joins it with no
## line here, as it joins the Ground choice of `SaGroundDialog`.
##
## **The ground a pick swaps is `SaGroundRows.ground_of`'s**, the one the
## Ground button and its dialog stand for: the active layer when it is a
## ground, and otherwise the uppermost. A document that holds a second ground
## by another route, a file or the door, keeps it, because this row only ever
## swaps one and the painter put the other there on purpose.
class_name SaGroundChoice
extends RefCounted

## The row's id in both menus.
const ROW := &"layer_ground"
## What the row reads and says on hover.
const WORDS := "Ground"
const SENTENCE := "Lay a ground under the painting, or swap the one it stands on for another."
## The child list's node name under the menu it opens beside.
const LIST_NAME := "GroundList"

var _document: SaDocument
var _registry: SaLayerTypeRegistry


## *document* is what a pick acts on and *registry* where the grounds are found.
func _init(document: SaDocument, registry: SaLayerTypeRegistry) -> void:
    _document = document
    _registry = registry


## Every ground a pick can lay, in the registry's order.
func kinds() -> Array[SaLayerTypeDescriptor]:
    return SaGeneratedLayer.grounds(_registry)


## Whether *id* names one of the grounds.
func is_ground(id: StringName) -> bool:
    return kinds().any(func(descriptor: SaLayerTypeDescriptor) -> bool: return descriptor.id == id)


## The ground a pick would swap, or null when the document has none.
func standing() -> SaLayer:
    return SaGroundRows.ground_of(_document, _registry)


## Swaps the standing ground for one of *id*'s kind, its colours kept where the
## new kind has a colour of the same name, or lays one when none stands. Each
## is one history step. Picking the kind that stands changes nothing. Answers
## whether *id* is a ground at all.
func pick(id: StringName) -> bool:
    if _document == null or not is_ground(id):
        return false
    var ground := standing()
    if ground == null:
        SaLayerOps.new(_document).add(id, _registry)
    else:
        SaGeneratedLayer.swap(_document, ground, _registry.get_descriptor(id), _registry, true)
    return true


## Adds the Ground row to *popup*, dimmed without a document, and nothing when
## no ground is registered.
func draw_row(popup: SaChoicePopup, key: StringName = ROW) -> void:
    if kinds().is_empty():
        return
    popup.add_branch_row(key, tr(WORDS), "", _document == null)
    popup.label_button(key).tooltip_text = tr(SENTENCE)


## Fills the list of grounds, the standing one marked, opens it beside
## *popup*'s row *key* and answers it. A row's id is its kind's, and a press
## reaches *on_chosen* with it. The list is made once per menu and kept under
## it, which is what `SaChoicePopup.open_child` asks of a child.
func open_beside(popup: SaChoicePopup, on_chosen: Callable, key: StringName = ROW) -> SaChoicePopup:
    var list := popup.get_node_or_null(LIST_NAME) as SaChoicePopup
    if list == null:
        list = SaChoicePopup.new()
        list.name = LIST_NAME
        list.one_of = true
        popup.add_child(list)
    list.clear()
    for descriptor: SaLayerTypeDescriptor in kinds():
        list.add_row(descriptor.id, tr(SaGeneratedLayer.kind_name(descriptor)), false, false, descriptor.icon_name)
        list.label_button(descriptor.id).tooltip_text = tr(descriptor.hint)
    var ground := standing()
    list.set_current(ground.layer_type if ground != null else &"")
    if not list.chosen.is_connected(on_chosen):
        list.chosen.connect(on_chosen)
    popup.open_child(list, key)
    return list
