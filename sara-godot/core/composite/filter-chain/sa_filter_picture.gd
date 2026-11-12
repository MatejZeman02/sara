## Whether a document's attached filters already form the picture the screen
## shows, which is the question the view asks before it transforms the picture
## again.
##
## The view's own highlight rolloff and a filter that forms a picture are two
## display transforms of one picture, and the second over the first is a
## different picture: a colour that has already been brought under white gives
## up more chroma on the way to white a second time. So the canvas and the View
## menu ask this, and both stand aside while it answers true.
##
## Asked of `forms_the_picture` on the filter and never of the Tonemap by name,
## so a third-party filter that forms a picture steps the view aside the same
## way. `forms_the_picture` is the door's one word for it, beside `finishes`,
## which the layer list asks for the same kind of reason.
##
## Two places a forming filter covers the picture. A record on the picture
## itself, which is the Picture way. Or the topmost visible layer, when that
## layer is a filter layer: every layer under it is then that filter's backdrop
## and its output is what covers the picture. A filter layer with a visible
## layer above it covers only what is under it, and the view is left alone,
## because the layers above still need the rolloff.
##
## A class of its own because it owns the walk over those two lists, a
## question apart from running the chain. The chain answers for it in one
## line, and the registry arrives as an argument
## so a caller with no chain can ask it too.
class_name SaFilterPicture
extends RefCounted


## Whether a filter of *document* forms the picture, read through *registry*.
##
## A null registry answers false, which is the host with no filters at all, the
## same answer [method SaFilterChain.finishes] gives for the same reason.
static func covers(registry: SaFilterRegistry, document: SaDocument) -> bool:
    if document == null:
        return false
    for record: SaAttachedFilter in document.root_filters:
        if of(record, registry):
            return true
    var top: SaLayer = null
    for layer: SaLayer in SaLayerStack.members(document, null):
        if layer != null and layer.visible:
            top = layer
    if top == null or not top.is_adjustment():
        return false
    for record: SaAttachedFilter in top.filters:
        if of(record, registry):
            return true
    return false


## Whether *record* is an enabled filter that forms the picture, false for a
## record no installed module answers.
##
## The sibling of [method SaFilterChain.finishes] and asked the same way, so the
## registry is the one place a key becomes a filter.
static func of(record: SaAttachedFilter, registry: SaFilterRegistry) -> bool:
    var filter := registry.get_filter(record.key) if registry != null and record != null else null
    return filter != null and record.enabled and filter.forms_the_picture()
