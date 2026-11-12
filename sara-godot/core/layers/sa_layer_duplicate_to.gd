## Layer > Duplicate To's copy: a layer or a group, with everything inside it,
## carried from the document it is in into another open document, as one undo
## step in that other document.
##
## **Every property a duplicate carries.** Each copy is made by
## `SaLayerDuplicate.copy`, so a layer carried across keeps its texels at full
## precision, its mask, blend, opacity, visibility, locks, filters and an
## effect layer's settings, exactly as Duplicate Layer keeps them inside one
## document. The texels are copied as they are, so a target in another colour
## space holds the source's numbers and not a conversion of them.
##
## **Names stay what they were.** A copy keeps its source's name where the
## target has no layer of that name, and takes the first free `name 2` and on
## where it has, so a group carried into a copy of its own file lands under the
## names a script and a reload read.
##
## **Where it lands.** On top of the stack, or on top of the group *under*
## names in the target. With *replace*, the target's node of the source's name
## at that place is taken out with everything inside it and the copy stands
## where it stood, which is how one season's groups painted in one copy of a
## file are carried into the other.
##
## **An effect layer's input is reconnected by name.** One that reads a member
## of the copied block reads that member's copy. One that reads a layer outside
## the block reads the target's layer of the same name, and where the target has
## none, or has one the effect cannot read, it reads nothing and the answer's
## `missing` says which, rather than the input being dropped in silence.
##
## **One step.** The copies and the node they replace are kept by
## `SaLayerOps.LayerKeeper`s in one presence step, as `SaRasterizeLayer` swaps a
## layer, so one Ctrl+Z in the target takes the copies out and puts back what
## they replaced. The source document records nothing.
class_name SaLayerDuplicateTo
extends RefCounted

## The history step's name in the target.
const ACTION_NAME := "Duplicate To"

var _from: SaDocument
var _to: SaDocument


func _init(from: SaDocument, to: SaDocument) -> void:
    _from = from
    _to = to


## Copies *source* and everything inside it into the target, on top of the
## stack or of the group *under*, in place of the node of the same name there
## when *replace* is true. Answers `copied`, the copies' names top first,
## `replaced`, the name of the node taken out or empty, and `missing`, one
## sentence for each effect layer whose input the target lacks, or `error` and
## nothing done.
func write(source: SaLayer, under: SaLayer = null, replace: bool = false) -> Dictionary:
    var why := _refusal(source, under)
    if not why.is_empty():
        return {"error": why}
    var ops := SaLayerOps.new(_to)
    var old := _named_at(String(source.name), under) if replace else null
    if old != null and (old == under or (under != null and SaLayerStack.is_inside(under, old))):
        return {
            "error": TranslationServer.translate("'%s' holds the group '%s' the copy was to go under.") % [old.name, under.name]
        }
    var gone := _take_out(ops, old)
    var at := _landing(old, gone, under)
    var block := _block(source)
    var copy_of: Dictionary[SaLayer, SaLayer] = {}
    var made: Array = []
    for original in block:
        var copy := SaLayerDuplicate.new(_to).copy(original, _free_name(String(original.name)))
        copy_of[original] = copy
        var keeper := SaLayerOps.LayerKeeper.new(copy, at)
        ops.put_back(keeper)
        made.push_front(keeper)
        at += 1
    var missing: Array[String] = []
    for original in block:
        var copy: SaLayer = copy_of[original]
        var parent := SaLayerStack.parent_of(original)
        copy.group = under if original == source else copy_of.get(parent, null)
        if original.source != null:
            _reconnect(original, copy, copy_of, missing)
    _to.set_active_layer(copy_of[source])
    _to.modified = true
    ops.refresh()
    var bytes := 0
    for keeper: SaLayerOps.LayerKeeper in gone:
        bytes += keeper.bytes()
    ops.commit_presence(ACTION_NAME, made + gone, bytes)
    var names: Array[String] = []
    for keeper: SaLayerOps.LayerKeeper in made:
        names.append(String(keeper.layer.name))
    return {"copied": names, "replaced": String(old.name) if old != null else "", "missing": missing}


## Why the copy cannot be made, or empty when it can.
func _refusal(source: SaLayer, under: SaLayer) -> String:
    if _from == null or _to == null:
        return TranslationServer.translate("There is no document to copy into.")
    if _from == _to:
        return TranslationServer.translate("The layer is already in that document. Duplicate Layer copies it there.")
    if source == null or source.get_parent() != _from:
        return TranslationServer.translate("There is no layer to copy.")
    if under != null and (under.get_parent() != _to or not under.is_group):
        return TranslationServer.translate("'%s' is no group of the document the copy goes into.") % under.name
    return ""


## The target's node called *wanted* whose parent is *under*, or null.
func _named_at(wanted: String, under: SaLayer) -> SaLayer:
    var found := _layer_named(wanted)
    return found if found != null and SaLayerStack.parent_of(found) == under else null


## *old* and everything inside it taken out of the target, top first, which is
## the order a presence step takes a block out and puts it back in.
func _take_out(ops: SaLayerOps, old: SaLayer) -> Array:
    var gone: Array = []
    if old == null:
        return gone
    var block := ops.subtree(old)
    block.sort_custom(func(a: SaLayer, b: SaLayer) -> bool: return a.get_index() > b.get_index())
    for layer in block:
        var keeper := SaLayerOps.LayerKeeper.new(layer, layer.get_index())
        ops.take_out(keeper)
        gone.append(keeper)
    return gone


## Where the bottom of the copied block goes: where the replaced block's bottom
## stood, under the group *under*'s own node, which sits above its members, or
## on top of the stack.
func _landing(old: SaLayer, gone: Array, under: SaLayer) -> int:
    if old != null:
        var lowest: SaLayerOps.LayerKeeper = gone[-1]
        return lowest.index
    if under != null:
        return under.get_index()
    return _to.get_child_count()


## *source* and every layer inside it, bottom first, the order their copies go
## in so a group's copy lands on top of its own members.
func _block(source: SaLayer) -> Array[SaLayer]:
    var block: Array[SaLayer] = []
    for child in _from.get_children():
        var layer := child as SaLayer
        if layer != null and (layer == source or (source.is_group and SaLayerStack.is_inside(layer, source))):
            block.append(layer)
    return block


## Points *copy*, an effect layer, at the copy of what *original* reads, or at
## the target's layer of that name, and notes in *missing* an input the target
## cannot give it.
func _reconnect(original: SaLayer, copy: SaLayer, copy_of: Dictionary[SaLayer, SaLayer], missing: Array[String]) -> void:
    if copy_of.has(original.source):
        copy.source = copy_of[original.source]
        return
    copy.source = null
    var wanted := String(original.source.name)
    var found := _layer_named(wanted)
    if found == null:
        missing.append(
            TranslationServer.translate("'%s' reads '%s', which this document has no layer called.") % [copy.name, wanted]
        )
    elif not SaEffectLayer.refusal(copy, found).is_empty():
        missing.append(SaEffectLayer.refusal(copy, found))
    else:
        copy.source = found


## *base* when no layer of the target has it, else the first of `base 2`,
## `base 3` and on that none has.
func _free_name(base: String) -> String:
    var candidate := base
    var number := 2
    while _layer_named(candidate) != null:
        candidate = "%s %d" % [base, number]
        number += 1
    return candidate


## The target's layer called *wanted*, or null. Read off the children rather
## than as a node path, which a name holding a dot would read as a property.
func _layer_named(wanted: String) -> SaLayer:
    for child in _to.get_children():
        if child is SaLayer and String(child.name) == wanted:
            return child
    return null
