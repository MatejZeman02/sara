## The layer a `.sad` file was saved with active, and the header key that
## carries it.
##
## **Why a key.** The reader made the first layer it built active, which is the
## bottom of the stack, whatever the painter had selected when they saved. A
## layer added next went in above Background and under every other layer, so
## opening a file never put the painter back where they left off.
##
## **How it is kept.** The layer's name, the way a member names its group, since
## a name is unique among the document's layers. Additive to v4 like the keys
## beside it, so there is no version bump: a build without this line opens the
## file with its first layer active, and this build opens a file without the key
## the same way.
class_name SaSadActiveLayer
extends RefCounted

## The header key the name is written under.
const KEY := "active_layer"


## Writes the document's active layer into *header*, when there is one among
## the layers the file holds. A document with none, or whose active layer is
## not one of its own children, writes no key and so opens as a file written
## by a Sara that kept no active layer does.
static func write_header(document: SaDocument, header: Dictionary[String, Variant]) -> void:
    var active := document.active_layer
    if active == null or not is_instance_valid(active) or active.get_parent() != document:
        return
    header[KEY] = str(active.name)


## The layer *header* names among the document's layers, or *fallback* when the
## key is absent, is not a name, or names a layer the file does not hold.
static func read_header(document: SaDocument, header: Dictionary[String, Variant], fallback: SaLayer) -> SaLayer:
    var raw: Variant = header.get(KEY, null)
    if not (raw is String):
        return fallback
    for child in document.get_children():
        var layer := child as SaLayer
        if layer != null and str(layer.name) == raw:
            return layer
    push_warning("SaSadActiveLayer: the file names no layer '%s' as active" % raw)
    return fallback
