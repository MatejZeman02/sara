## The drag of a layer's mask from its row onto another layer's row.
##
## A press on a row's mask picture arms the list's drag as this one, and from
## then on the list asks here what a row would do with the mask and hands the
## release over. Dropped on a row that takes it, the mask moves there and the
## layer it came from shows whole, and with Ctrl or Alt held at the release it
## is copied and both keep it, as Krita's Ctrl and Photoshop's Alt do. Either
## is one step, `SaMaskOps.transfer`.
##
## A layer that has a mask already refuses one, and the release says why on the
## notice line rather than asking whether to replace it: a replaced mask is
## coverage the painter made, and a question in the middle of a drag is one
## more window to close, where deleting the old mask first is one menu row.
## The row says so before the release as well, by the refused mark.
##
## Its own file beside the list, as `layer_pick.gd` is, because the list stands
## at its limit and because what a mask drop means is a question about masks
## the row drag never asks.
class_name SaLayerMaskDrag
extends RefCounted

## The layer whose mask is being carried, or null when the drag under way, if
## any, carries rows.
var source: SaLayer = null


## Arms the drag with *from*'s mask, or with nothing when *from* has none.
func arm(from: SaLayer) -> void:
    source = from if from != null and from.mask != null else null


## Ends the drag, dropped or not.
func let_go() -> void:
    source = null


## Whether the drag under way carries a mask.
func armed() -> bool:
    return source != null and is_instance_valid(source)


## The mark a row of *target* wears while the mask is over it: inside when it
## takes the mask, refused when it does not, and none on a filter's row, which
## *target* is null for.
func mode_over(target: SaLayer) -> SaLayerList.Drop:
    if target == null:
        return SaLayerList.Drop.NONE
    return SaLayerList.Drop.INTO if takes(source, target) else SaLayerList.Drop.REFUSED


## Whether *target* takes the mask *from* carries: a layer other than *from*,
## with no mask, that can carry one, stored at the density *from* is.
static func takes(from: SaLayer, target: SaLayer) -> bool:
    if from == null or target == null or from == target or from.mask == null or target.mask != null:
        return false
    return SaMaskOps.can(SaMaskOps.ADD, target) and target.resolution_scale == from.resolution_scale


## Why *target* takes no mask from *from*, in the painter's words, or "" when
## there is nothing to say: it takes it, or it is the layer the mask came from,
## where a drop back means no change.
static func refusal(from: SaLayer, target: SaLayer) -> String:
    if from == null or target == null or from == target or takes(from, target):
        return ""
    var named := str(target.name)
    if target.mask != null:
        return TranslationServer.translate("'%s' has a mask already. Delete it first to give it this one.") % named
    if not SaMaskOps.can(SaMaskOps.ADD, target):
        return TranslationServer.translate("'%s' takes no mask.") % named
    return TranslationServer.translate("'%s' is stored at another resolution, so the mask cannot go onto it.") % named


## Releases the mask over *target* in *document*: moved, or copied when *copy*,
## and answers whether it landed. A row that refuses it says why on the notice
## line.
func drop(document: SaDocument, target: SaLayer, copy: bool) -> bool:
    var from := source if armed() else null
    let_go()
    if document == null or from == null or target == null:
        return false
    if not takes(from, target):
        var why := refusal(from, target)
        if not why.is_empty():
            SaMessage.notice(why)
        return false
    return SaMaskOps.new(document).transfer(from, target, copy)
