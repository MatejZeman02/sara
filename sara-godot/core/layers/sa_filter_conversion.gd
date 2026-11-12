## The two ways between an attached filter and an adjustment layer, each one
## history step: a record turned into an adjustment layer above what it hangs
## on, and an adjustment layer turned back into records on the node it sits at
## the top of, so either form becomes the other.
##
## Built by whoever runs one and dropped at once, the way `SaFilterOps` is, and
## the layers docker is what calls it, since `core` never names `ui`. The
## Filter dialog's Layer way comes through `add_holding` for the same reason.
##
## **Where the two forms are one picture.** A record on the root runs over the
## whole composite after the top layer, and a record on an isolated group over
## the group's composite before its mask. An adjustment layer at the top of the
## document, or of that group, at Normal and full opacity, shown, unclipped and
## with no mask of its own that hides anything, reads the same composite. Only a node's first record
## converts, since a node's records run bottom first and the layer runs before
## all of them, and the way back puts the layer's records in front of the
## node's own for the same reason. Everywhere else the two differ, and the
## conversion refuses with a sentence naming why rather than change the picture:
## a record on a paint layer filters that layer alone, a record that is not the
## first runs after others, a pass-through group isolated only by the record
## would pass through once it left, and a masked, clipped, faded, hidden or
## differently blended adjustment layer mixes in a way no record does.
##
## The records move themselves, masks and values and all, and are never copied,
## so undo puts back the very records the step took. The layer is kept alive
## while it is out of the document by the same `SaLayerOps.LayerKeeper` a
## deleted layer is.
class_name SaFilterConversion
extends RefCounted

## The history rows, which the Undo History docker shows.
const TO_LAYER := "Convert to Adjustment Layer"
const TO_RECORD := "Convert to Attached Filter"
const ADD_LAYER := "Add Adjustment Layer"

var _document: SaDocument = null


func _init(document: SaDocument) -> void:
    _document = document


## Why *record* on *node*, null for the root, cannot become an adjustment
## layer, or an empty string when it can. The docker dims its row on this and
## shows the sentence as the row's hint.
func layer_refusal(node: SaLayer, record: SaAttachedFilter) -> String:
    var list := _filters_of(node)
    if record == null or not _holds(node) or not list.has(record):
        return tr("The filter is no longer on its layer.")
    if node != null and not node.is_group:
        return (
            tr("'%s' is not a group: its filter works on that layer alone, and an adjustment layer works on all under it.")
            % node.name
        )
    if list.find(record) != 0:
        return (
            tr("Only the first filter on %s runs straight after its layers, so only it can become the layer at their top.")
            % _named(node)
        )
    if node != null and record.enabled and not _isolated_without(node, record):
        return (
            tr("'%s' blends on its own only because of this filter, so taking the filter off would change how its layers blend.")
            % node.name
        )
    if _reads_whole(node, record):
        return tr("An adjustment layer runs no filter that reads the whole layer yet, and this one does.")
    return ""


## Why the adjustment layer *layer* cannot become filters attached to the node
## it sits at the top of, or an empty string when it can.
func record_refusal(layer: SaLayer) -> String:
    if layer == null or not _holds(layer) or not layer.is_adjustment():
        return tr("Only an adjustment layer can become an attached filter.")
    if layer.filters.is_empty():
        return tr("'%s' holds no filter to attach.") % layer.name
    if not hides_nothing(layer.mask):
        return tr("'%s' has a mask of its own, and a filter attached in its place would reach everywhere.") % layer.name
    if layer.clip_to_below:
        return tr("'%s' is clipped to the layer below, and an attached filter cannot be.") % layer.name
    if layer.opacity < 1.0:
        return (
            tr("'%s' has %s opacity, but an attached filter works at full strength.")
            % [layer.name, "%d%%" % roundi(layer.opacity * 100.0)]
        )
    if layer.blend_mode != SaLayer.BLEND_MODE.NORMAL:
        return tr("'%s' blends in a mode other than Normal, and an attached filter replaces what it works on.") % layer.name
    if not layer.visible:
        return tr("'%s' is hidden, and an attached filter would show.") % layer.name
    if layer.affects_all and SaLayerStack.parent_of(layer) != null:
        return tr("'%s' affects the whole picture, and a filter attached to its group would reach the group alone.") % layer.name
    if not _at_the_top(layer):
        return (
            tr("'%s' is not at the top of the document or of its group, so an attached filter would reach more than it does.")
            % layer.name
        )
    var group := SaLayerStack.parent_of(layer)
    if group != null and not SaLayerStack.isolates(group) and SaFilterChain.has_enabled(layer.filters):
        return tr("'%s' blends its layers one by one, and a filter attached to it would make it blend on its own.") % group.name
    return ""


## Turns *record*, the first on *node* or on the root for null, into an
## adjustment layer at the top of that node holding it, as one step, and
## answers the layer. *types* is the registry the adjustment layer's kind is
## registered in, and *title* names the layer. Refused with the sentence of
## `layer_refusal`, and then nothing moves.
func to_layer(node: SaLayer, record: SaAttachedFilter, types: SaLayerTypeRegistry, title: String = "") -> SaLayer:
    var refusal := layer_refusal(node, record)
    if refusal.is_empty() and types == null:
        refusal = tr("No module registers the adjustment layer.")
    if not refusal.is_empty():
        # The sentence was translated where `layer_refusal` wrote it, and the
        # title is a line the corner shows as well.
        SaProblems.refuse(tr(TO_LAYER), refusal)
        return null
    var layer := _made(types, title, node)
    if layer == null:
        SaProblems.refuse(TO_LAYER, tr("No module registers the adjustment layer."))
        return null
    var index := node.get_index() if node != null else _document.get_child_count()
    var keeper := SaLayerOps.LayerKeeper.new(layer, index)
    var records: Array[SaAttachedFilter] = [record]
    _to_layer(keeper, node, records)
    _document.history.commit_pair(TO_LAYER, _to_layer.bind(keeper, node, records), _to_node.bind(keeper, node, records))
    return layer


## Turns the adjustment layer *layer* back into its records, put in front of
## the records of the node it sits at the top of, as one step. Answers whether
## it did. Refused with the sentence of `record_refusal`, and then nothing
## moves.
func to_record(layer: SaLayer) -> bool:
    var refusal := record_refusal(layer)
    if not refusal.is_empty():
        # Translated where `record_refusal` wrote it, as above.
        SaProblems.refuse(tr(TO_RECORD), refusal)
        return false
    var node := SaLayerStack.parent_of(layer)
    var keeper := SaLayerOps.LayerKeeper.new(layer, layer.get_index())
    var records: Array[SaAttachedFilter] = []
    records.assign(layer.filters)
    _to_node(keeper, node, records)
    _document.history.commit_pair(TO_RECORD, _to_node.bind(keeper, node, records), _to_layer.bind(keeper, node, records))
    return true


## An adjustment layer above the active layer, in its group, holding one record
## of the filter under *key* with *values*, masked by the selection when one is
## active, and with a mask of its own that hides nothing, as one step: the Filter dialog's Layer way. Answers the layer, or null
## with a refusal for a filter reading the whole layer or a kind no registry knows.
## With *affects_all*, the dialog's Affect all, the layer carries the property
## of that name and adjusts the whole picture from the same place, which
## `SaBackdropLayer` says. It was put at the top of the stack in no group, which a
## move into a group undid.
func add_holding(
    key: StringName, values: Dictionary, types: SaLayerTypeRegistry, title: String = "", affects_all: bool = false
) -> SaLayer:
    var active := _document.active_layer
    if key == &"" or active == null:
        return null
    var record := SaAttachedFilter.new(key, values)
    if _reads_whole(active, record):
        SaProblems.refuse(ADD_LAYER, tr("An adjustment layer runs no filter that reads the whole layer yet, and this one does."))
        return null
    var layer := _made(types, title, SaLayerStack.parent_of(active))
    if layer == null:
        SaProblems.refuse(ADD_LAYER, tr("No module registers the adjustment layer."))
        return null
    SaMaskOps.new(_document).mask_from_selection(record)
    give_bare_mask(layer)
    layer.affects_all = affects_all
    var keeper := SaLayerOps.LayerKeeper.new(layer, active.get_index() + 1)
    var records: Array[SaAttachedFilter] = [record]
    # The record is on no node, so the step neither takes it from one nor
    # gives it back.
    _to_layer(keeper, null, records, false)
    var undo := _to_node.bind(keeper, null, records, false)
    _document.history.commit_pair(ADD_LAYER, _to_layer.bind(keeper, null, records, false), undo, 0, record.byte_size())
    return layer


## Gives *layer*, a new adjustment or effect layer, the mask Layer > Add Mask
## gives, one hiding nothing, with no step of its own: the caller's Add step
## keeps the layer and so the mask, and one undo takes both.
static func give_bare_mask(layer: SaLayer) -> SaMask:
    var mask := layer.add_mask(1.0)
    mask.rest = 1.0
    return mask


## Whether *mask* hides nothing: none, one switched off, or one holding no
## chunk at a rest of one. It stays on the layer the way back to records keeps.
static func hides_nothing(mask: SaMask) -> bool:
    if mask == null or not mask.enabled:
        return true
    return mask.is_own() and mask.rest >= 1.0 and mask.grid_positions().is_empty()


## The adjustment layer the steps put in, of the kind *types* registers, named
## after *title*, and a member of *group*. Null when the registry knows no
## such kind.
func _made(types: SaLayerTypeRegistry, title: String, group: SaLayer) -> SaLayer:
    if types == null:
        return null
    var layer := SaLayer.new()
    layer.schema = SaFieldSpec.schema_for_space(_document.color_space)
    if not types.apply_to(layer, SaBackdropLayer.TYPE_ID, _document.color_space) or not layer.is_adjustment():
        layer.free()
        return null
    layer.name = layer_name_for(title if not title.is_empty() else tr("Adjustment Layer"))
    layer.group = group
    return layer


## The name a layer made for the filter titled *title* takes, numbered past
## every name the document's layers have. A layer's name is a `Node` name,
## and Godot makes each mark one cannot hold an underscore, so
## "Brightness/Contrast" would read "Brightness_Contrast" in the row, the
## window title and the refusals. Each such mark is a space here instead.
func layer_name_for(title: String) -> String:
    var words := title
    for mark: String in [".", ":", "@", "/", '"', "%"]:
        words = words.replace(mark, " ")
    return _free_name(" ".join(words.split(" ", false)))


## The layer in the document at its keeper's place, holding *records*, which
## leave *node*'s list unless *keep* is false, which is a record that came from
## no node at all.
func _to_layer(keeper: SaLayerOps.LayerKeeper, node: SaLayer, records: Array[SaAttachedFilter], keep: bool = true) -> void:
    var layer := keeper.layer
    if not is_instance_valid(layer) or (node != null and not is_instance_valid(node)):
        return
    if keep:
        for record in records:
            _filters_of(node).erase(record)
    layer.filters.clear()
    layer.filters.append_array(records)
    if layer.get_parent() != _document:
        _document.add_child(layer)
        _document.move_child(layer, clampi(keeper.index, 0, _document.get_child_count() - 1))
        layer.mark_all_unresolved()
    _document.set_active_layer(layer)
    _changed()


## The layer out of the document, and *records* at the front of *node*'s list
## in their order, unless *keep* is false, which is a record that came from
## no node going back to none.
func _to_node(keeper: SaLayerOps.LayerKeeper, node: SaLayer, records: Array[SaAttachedFilter], keep: bool = true) -> void:
    var layer := keeper.layer
    if not is_instance_valid(layer) or (node != null and not is_instance_valid(node)):
        return
    layer.filters.clear()
    if keep:
        var list := _filters_of(node)
        for at in records.size():
            if not list.has(records[at]):
                list.insert(mini(at, list.size()), records[at])
    if layer.get_parent() == _document:
        keeper.index = layer.get_index()
        var below := keeper.index - 1
        _document.invalidate_chunks(SaBackdropLayer.drawn_over(_document, layer))
        _document.remove_child(layer)
        if _document.active_layer == layer or _document.active_layer == null:
            var stack := SaLayerOps.new(_document).layers()
            if not stack.is_empty():
                _document.set_active_layer(stack[clampi(below, 0, stack.size() - 1)])
    _changed()


## Whether *node* would still isolate with *record* taken off it.
func _isolated_without(node: SaLayer, record: SaAttachedFilter) -> bool:
    if node.isolated or node.mask != null:
        return true
    for other in node.filters:
        if other != record and other.enabled:
            return true
    return false


## Whether *layer* is the top of the document or the top member of its group,
## the two places its backdrop is a whole node's composite.
func _at_the_top(layer: SaLayer) -> bool:
    var group := SaLayerStack.parent_of(layer)
    if group != null:
        return layer.get_index() == group.get_index() - 1
    return layer.get_index() == _document.get_child_count() - 1


## Whether *record* reads the whole node, asked of the pass the compositor's
## chain builds for it, the question `SaFilterOps` asks on an attach to an
## adjustment layer. Held as an Object and asked through `call`, because the
## chain is private to its package.
func _reads_whole(node: SaLayer, record: SaAttachedFilter) -> bool:
    var compositor := _document.compositor
    var chain: Object = compositor.filter_chain if compositor != null else null
    var built: Variant = chain.call("pass_for", _document, node, record) if chain != null else null
    var gather: SaNeighbourhoodPass = built if built is SaNeighbourhoodPass else null
    return gather != null and gather.whole()


func _filters_of(node: SaLayer) -> Array[SaAttachedFilter]:
    return _document.root_filters if node == null else node.filters


func _holds(node: SaLayer) -> bool:
    return node == null or (is_instance_valid(node) and node.get_parent() == _document)


## A node as a sentence names it.
func _named(node: SaLayer) -> String:
    return tr("the document") if node == null else "'%s'" % node.name


func _free_name(wanted: String) -> String:
    var candidate := wanted
    var count := 2
    while _document.has_node(NodePath(candidate)):
        candidate = "%s %d" % [wanted, count]
        count += 1
    return candidate


## What every step ends on, as `SaFilterOps` ends: the whole document redraws,
## because the records moved between nodes that composite every chunk.
func _changed() -> void:
    _document.modified = true
    _document.invalidate_all_allocated_chunks()
    _document.update_caches()
