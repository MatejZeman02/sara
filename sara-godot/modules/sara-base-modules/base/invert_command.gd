## Invert on Ctrl+I, the base module's command: the mask while a mask is the
## paint target, and the picked layers' colours otherwise.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A module's command, not the skeleton's.** The pixels are inverted by this
## module's Invert filter, and the skeleton must not name a module's filter, so
## the one chord that reaches both a mask and a filter is registered here,
## through `SaContext.register_command` like any module's.
##
## **Each outcome is the step its own menu row makes.** The mask goes through
## `SaMaskOps`'s invert, recorded as Invert Mask, and the pixels through the
## filter's one-shot, `SaFilterOps.one_shot`, recorded as Invert, which is what
## Filter > Invert's Apply writes, inside the selection when there is one.
##
## **An adjustment or an effect layer holds no pixels.** With no mask as the
## target, Ctrl+I inverts such a layer's own mask, which decides where its work
## shows, as the fill and clear keys reach it, and refuses in the corner when
## the layer has none.
##
## **The two rows it runs show its chord.** The descriptor's `shows_on` names
## Invert Mask and Filter > Invert, so their rows read Ctrl+I while neither
## holds a chord of its own, and the skeleton names nothing of this module's.
extends RefCounted

const InvertFilter = preload("res://modules/sara-base-modules/base/usual/invert_filter.gd")

## The command's id, its action and the row the Keyboard Shortcuts page lists.
const COMMAND := &"layer_invert"
## The module the filter is registered under, which its key is made from.
const MODULE := &"sara-base-modules"
## The corner's line for an adjustment or an effect layer with no mask, the
## layer's name in it.
const NOTHING_TO_INVERT := "'%s' holds no pixels to invert and has no mask. Add a mask to invert where its work shows."


## Registers the command under Ctrl+I. The handler is bound to a context
## holding the easel provider alone and to the filter registry, as the stamp
## brush's eraser toggle is, because binding *ctx* closes a ring, registry to
## descriptor to Callable to ctx and back, and a module's context is dropped
## once its module has registered.
static func register(ctx: SaContext) -> void:
    var surfaces := SaContext.new(ctx.easel_provider, ctx.surface_provider)
    var command := SaCommandDescriptor.create(COMMAND, "Invert the mask or the layer", _run_in.bind(surfaces, ctx.filters))
    command.label = "Invert"
    var chord := InputEventKey.new()
    chord.keycode = KEY_I
    chord.ctrl_pressed = true
    command.default_events = [chord]
    command.category = &"layer"
    command.sentence = "Invert the mask when a mask is the paint target, and the picked layers' colours otherwise."
    command.shows_on = [SaMaskOps.INVERT]
    var filter := _filter(ctx.filters)
    if filter != null:
        command.shows_on.append(SaFilterRegistry.command_for(filter_key(), filter))
    ctx.register_command(command)


## The Invert filter's key in the filter registry.
static func filter_key() -> StringName:
    return SaFilterRegistry.key_for(MODULE, InvertFilter.new())


## The command's handler, on the primary document *surfaces* reaches.
static func _run_in(surfaces: SaContext, filters: SaFilterRegistry) -> bool:
    var easel := surfaces.get_easel()
    return run(easel.document if easel != null else null, filters)


## Inverts what Ctrl+I reaches in *document*, the filter read from *filters*,
## and answers whether anything changed.
static func run(document: SaDocument, filters: SaFilterRegistry) -> bool:
    if document == null or document.active_layer == null:
        return false
    var target := SaMaskOps.owner_of(document, document.mask_target)
    if target != null:
        return SaMaskOps.new(document).run(SaMaskOps.INVERT, target)
    var layer := document.active_layer
    if layer.is_adjustment() or layer.is_effect():
        if SaMaskOps.can(SaMaskOps.INVERT, layer):
            return SaMaskOps.new(document).run(SaMaskOps.INVERT, layer)
        EventBus.paint_refused.emit(TranslationServer.translate(NOTHING_TO_INVERT) % layer.name)
        return false
    return _invert_pixels(document, _filter(filters))


## The Invert filter baked into every picked layer that takes paint, a group
## once for the layers under it, as one step named as the filter's row is.
## When none takes it the active layer's reason goes to the corner.
static func _invert_pixels(document: SaDocument, filter: SaFilter) -> bool:
    if filter == null:
        return false
    var takers: Array[SaLayer] = []
    for layer: SaLayer in SaLayerStack.roots(document, document.picked.acted_on(document)):
        if is_instance_valid(layer) and SaFilterApply.way_refusal(layer, &"bake").is_empty():
            takers.append(layer)
    if takers.is_empty():
        var why := SaFilterApply.way_refusal(document.active_layer, &"bake")
        if not why.is_empty():
            EventBus.paint_refused.emit(why)
        return false
    var wrote: Array[bool] = [false]
    var work := func() -> void:
        for layer: SaLayer in takers:
            var context := SaFilterContext.new(document, layer, MODULE, filter.title(), true)
            if SaFilterApply.call_run(filter, context) and SaFilterOps.one_shot(context, filter):
                wrote[0] = true
    if document.history != null:
        document.history.as_one(filter.title(), work)
    else:
        work.call()
    return wrote[0]


## The registry's Invert filter, or null when the registry holds none.
static func _filter(filters: SaFilterRegistry) -> SaFilter:
    return filters.get_filter(filter_key()) if filters != null else null
