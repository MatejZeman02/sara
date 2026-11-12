## The refusals each layer kind adds to a merge, a flatten and a filter, in
## one table the kinds register into, so a new kind is one row here rather
## than one more `is_` test in each of the three operations that asked.
##
## `SaLayerOps` and `SaFilterOps` ask this class, where they and `SaMergeFold`
## walked `is_group`, `is_generated`, `is_adjustment` and `is_effect` in turn.
## A row names a kind and the sentence it refuses each act with, and a kind
## that does not refuse an act has no sentence for it. The sentences are kept
## untranslated, a template for `tr` with one `%s` and the layer's name, and
## go through the lookup only when a refusal is said.
##
## What paint refuses stays `SaLayer.refuses_paint`, the one call a tool's
## guard makes through `SaContext`, because a tool sees the door only.
class_name SaLayerRefusals
extends RefCounted

## The acts a kind can refuse. `MERGE` is either side of a merge, `MERGE_ONTO`
## the lower side alone, `STORE` a layer holding no paint, which a filter's
## flatten passes over and Flatten draws past into a new paint layer,
## `WRITE_FILTER` a flatten of a filter attached to the kind itself, and
## `READ_WHOLE` a filter attached to it that reads the whole node, which
## `SaFilterOps` asks only once the pass it builds is such a gather. `STORE`
## is said by a filter dialog's dimmed Bake and the guard of every bake in
## `SaFilterApply`, and Flatten asks it through `stores_paint` alone, since
## it stopped refusing a bottom layer of these kinds. `PAINT` is a brush, an
## eraser, a smudge or a fill, said through `SaContext.paint_refusal_line`
## with the gesture in place of the name, by the kinds whose sentence says
## more than the line every refusal of paint ends on. `RESHAPE` is a scale, a
## turn, a skew or a part of a layer the Transform tool would otherwise move
## whole, said by a drawn layer whose recipe takes a move and nothing more.
enum Act { MERGE, MERGE_ONTO, STORE, WRITE_FILTER, READ_WHOLE, PAINT, RESHAPE }

const STORES_NOTHING: String = "'%s' stores no paint."
const HOLDS_NOTHING: String = "'%s' holds no paint to write into. Merge Down applies it to the layer below."
## What a merge says of a locked layer it would write into or take out, the
## sentence the transform and Rasterize already say of a lock.
const LOCKED: String = "'%s' is locked. Unlock it in the Layers docker first."

## One row per kind, in the order a merge asks them: the kind, and what it
## refuses each act with. A generated layer refuses a merge on either side,
## and a group, an adjustment layer and an effect layer only the side a merge
## would write into.
var _kinds: Array[Dictionary] = [
    {
        &"kind": &"group",
        Act.MERGE_ONTO: "'%s' is a group. A group merges down into the paint layer under it, but nothing merges onto a group.",
        Act.STORE: STORES_NOTHING,
    },
    {
        &"kind": &"generated",
        Act.MERGE: "'%s' is a generated layer, and it stores no paint to merge.",
        Act.STORE: STORES_NOTHING,
    },
    {
        &"kind": &"adjustment",
        Act.MERGE_ONTO: "'%s' is an adjustment layer and holds no paint to merge onto.",
        Act.STORE: STORES_NOTHING,
        Act.WRITE_FILTER: HOLDS_NOTHING,
        Act.READ_WHOLE: "'%s' is an adjustment layer, and this filter reads the whole layer, which it does not offer yet.",
    },
    {
        &"kind": &"effect",
        Act.MERGE_ONTO: "'%s' is an effect layer, so nothing can be merged onto it.",
        Act.STORE: STORES_NOTHING,
        Act.WRITE_FILTER: HOLDS_NOTHING,
    },
    {
        &"kind": &"drawn",
        Act.MERGE_ONTO:
        "'%s' is drawn from its shapes, so nothing can be merged onto it. Rasterize Layer turns it into paint first.",
        Act.STORE: STORES_NOTHING,
        Act.WRITE_FILTER:
        (
            "'%s' is drawn from its shapes, and its next edit would draw over the filter."
            + " Rasterize Layer turns it into paint first."
        ),
        Act.PAINT:
        (
            "This layer is drawn from its shapes, and its next edit would draw over the %s."
            + " Add a paint layer above it to paint on, or turn it into paint with Layer > Rasterize Layer."
        ),
        # Only text takes a move into its recipe, so only text is ever told this.
        Act.RESHAPE:
        (
            "'%s' is text, kept sharp by drawing its letters, so the Transform tool moves the whole of it and nothing more."
            + " To scale, turn or skew it, or to move a part of it, turn it into paint first with Layer > Rasterize Layer."
        ),
    },
]

var _document: SaDocument


func _init(document: SaDocument) -> void:
    _document = document


## The sentence *layer*'s kind refuses *act* with, untranslated, or an empty
## string when its kind does not refuse it. A null layer is the root, which
## refuses nothing here.
func sentence(act: Act, layer: SaLayer) -> String:
    if layer == null:
        return ""
    for row in _kinds:
        var kind: StringName = row[&"kind"]
        if row.has(act) and _is(layer, kind):
            return str(row[act])
    return ""


## The sentence a tool that paints says on *layer*, translated, with
## *gesture* in it, or an empty string when its kind has none of its own.
## Static, because a tool's guard holds no document.
static func paint_sentence(layer: SaLayer, gesture: String) -> String:
    var found := SaLayerRefusals.new(null).sentence(Act.PAINT, layer)
    return TranslationServer.translate(found) % gesture if not found.is_empty() else ""


## What the Transform tool says on *layer* when it would do more than move
## it whole, translated, with the layer's name in it, or an empty string when
## its kind has no such sentence.
static func reshape_sentence(layer: SaLayer) -> String:
    var found := SaLayerRefusals.new(null).sentence(Act.RESHAPE, layer)
    return TranslationServer.translate(found) % layer.name if not found.is_empty() else ""


## Whether *layer* stores paint a flatten could write into.
func stores_paint(layer: SaLayer) -> bool:
    return sentence(Act.STORE, layer).is_empty()


## Refuses *act* on *layer* with a corner line under *title*, and answers
## whether it did.
func refuses(title: String, act: Act, layer: SaLayer) -> bool:
    var found := sentence(act, layer)
    if found.is_empty():
        return false
    SaProblems.refuse(title, tr(found) % layer.name)
    return true


## Whether *upper* can merge onto *lower*, quietly, which is what dims Merge
## Down: a menu asks it on every open.
func can_take(upper: SaLayer, lower: SaLayer) -> bool:
    return merge(upper, lower).is_empty()


## Refuses the merge of *upper* onto *lower* with a corner line under
## *action*, and answers whether it did.
func refuses_merge(action: String, upper: SaLayer, lower: SaLayer) -> bool:
    var found := merge(upper, lower)
    if found.is_empty():
        return false
    SaProblems.refuse(action, tr(str(found[0])) % found[1])
    return true


## The first thing that stops *upper* merging onto *lower*, as a template for
## `tr` with one `%s` and the name that goes in it, or nothing when the merge
## can go ahead. A group merges down drawn as the canvas draws it, its
## members going with it, `SaGroupMerge`, but merging onto one would write
## chunks the compositor never draws, because a group's paint is its members'.
## A generated layer stores nothing to give or to take, so it refuses either
## side, as Krita does. An adjustment layer merges
## down into the paint under it, and nothing merges onto one, which holds no
## paint to write into. A hidden lower layer refuses too, because the merged
## paint would disappear from the canvas. A layer whose albedo is computed
## from other fields cannot take a merge either, because the next resolve
## would overwrite it, and a double resolution one is baked first. A locked
## layer refuses either side, the lower one because its paint would change
## and an upper one or a locked member of an upper group because it would go,
## as every other writer of a layer's paint refuses a lock. Flatten passes no
## *upper*, because it draws the whole tree into *lower*, a new paint layer
## when the bottom one stores nothing, and it flattens over locks as Krita
## and Photoshop do.
func merge(upper: SaLayer, lower: SaLayer) -> Array:
    if upper != null:
        var pair: Array[SaLayer] = [upper, lower]
        for layer in pair:
            var either := sentence(Act.MERGE, layer)
            if not either.is_empty():
                return [either, layer.name]
        var onto := sentence(Act.MERGE_ONTO, lower)
        if not onto.is_empty():
            return [onto, lower.name]
        if not lower.visible:
            return ["'%s' is hidden. Show it first.", lower.name]
        var locked := _locked_in(upper, lower)
        if locked != null:
            return [LOCKED, locked.name]
    if lower.has_derived:
        return ["'%s' takes its colour from its simulation, so nothing can be merged onto it.", lower.name]
    if lower.resolution_scale != 1.0:
        return ["'%s' is at double resolution. Resample it to the document's resolution first.", lower.name]
    if _document.compositor == null:
        return ["'%s' cannot be merged while its document is not open.", lower.name]
    return []


## The first locked layer a merge of *upper* onto *lower* would change or take
## out, *lower* first, or null. The lock is read as set, because `is_locked`
## answers true for every group and a group merges down as its members drawn.
func _locked_in(upper: SaLayer, lower: SaLayer) -> SaLayer:
    if lower._locked:
        return lower
    for layer in SaLayerGroups.new(_document).subtree(upper):
        if layer._locked:
            return layer
    return null


## Whether *layer* is of *kind*, the one place a row's kind is read.
static func _is(layer: SaLayer, kind: StringName) -> bool:
    match kind:
        &"group":
            return layer.is_group
        &"generated":
            return layer.is_generated()
        &"adjustment":
            return layer.is_adjustment()
        &"effect":
            return layer.is_effect()
        &"drawn":
            return layer.is_drawn()
    return false
