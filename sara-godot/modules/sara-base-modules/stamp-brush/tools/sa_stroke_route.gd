## How one stroke reaches the canvas: straight into the active layer, or through
## the stroke buffer and one composite at the end.
##
## Three questions decide it, and the answers are read once at the press because
## the buffer holds one stroke's coverage and the commit applies one rule to it.
## Is the brush erasing, is the active layer alpha locked, and is the painting
## mode wash rather than build-up.
##
## **Build-up paints straight in, wash goes through the buffer.** Build-up means
## a stroke that crossing itself deposits twice, which is what painting straight
## into the layer already does, so the direct path is kept for it: it is one
## dispatch per dab and no composite at the end. Wash means the whole stroke
## reaches the opacity it was set to and stops, which needs the coverage in one
## place before any of it lands, so the buffer is the only way to get it. The
## mode decides the route for an eraser and on an alpha-locked layer too, and
## not for an ordinary brush alone: an eraser at half opacity sent straight in
## would erase more where its stroke crossed itself, whatever the mode said.
##
## **A blur paints straight in, in either mode**. A blurring dab moves
## the texel towards the paint it blurred, which needs the layer's texel under
## it. In the buffer it found nothing and laid the blur's alpha there, and the
## commit laid that over the layer, so every stroke added the blur's coverage
## to what was there and a thin wisp went opaque in a few strokes.
##
## The class holds no document and no settings. It is the answers, so a suite
## can build one by hand and a dab can read it without asking anything again.
class_name SaStrokeRoute
extends RefCounted

## By path rather than by class name, for the reason `state_brush.gd` gives
## beside its own copy: a module's script has to resolve before the editor has
## rescanned the class cache.
const SaLayerScript = preload("res://core/api/document/sa_layer.gd")
const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## Painting straight into the active layer rather than into the stroke buffer.
var direct: bool = false

## The brush is erasing, whether by the eraser tool, the toggle or the flipped
## end of a pen.
var erasing: bool = false

## The active layer is alpha locked.
var alpha_locked: bool = false

## Wash rather than build-up.
var washing: bool = false

## A blurring smudge, which moves the layer's own paint and lays none.
var blurring: bool = false


## The route a stroke with these answers takes.
##
## An eraser on an alpha-locked layer is the one pair that stays direct in wash
## as well: alpha lock forbids moving alpha and an erase moves nothing else, so
## the stroke has to paint nothing, and the dab kernel is where that is already
## written. Gathering the coverage first would only buy a buffer to throw away.
## The brush refuses such a press with a line before it gets here, so the pair
## is reached only by a stroke driven past `handle_input`.
##
## A blur, *smudge_mode* the settings' own, goes straight in unless it erases.
static func decide(is_erasing: bool, is_alpha_locked: bool, is_washing: bool, smudge_mode: int = 0) -> SaStrokeRoute:
    var route := SaStrokeRoute.new()
    route.erasing = is_erasing
    route.alpha_locked = is_alpha_locked
    route.washing = is_washing
    route.blurring = smudge_mode == SettingsScript.SmudgeMode.BLURRING and not is_erasing
    var locked_erase: bool = is_erasing and is_alpha_locked
    route.direct = route.blurring or ((is_erasing or is_alpha_locked) and (locked_erase or not is_washing))
    return route


## What the stroke buffer composites as at the commit, and an empty name for a
## stroke that paints straight in or has no rule of its own.
##
## Erase carves with the stroke's coverage once, and alpha lock tints what is
## already there and keeps its alpha. The two never arrive together here,
## because [method decide] sends that pair down the direct path.
func buffer_mode() -> StringName:
    if direct:
        return &""
    if alpha_locked:
        return SaLayerScript.BLEND_MODE.ALPHA_LOCK
    if erasing:
        return SaLayerScript.BLEND_MODE.ERASE
    return &""


## The `paint_mode` the dab kernel gets.
##
## A dab that lands in the buffer lays coverage and nothing else: the composite
## at the end is what says whether that coverage paints, carves or tints, so the
## kernel never erases into a buffer. A dab that lands straight in the layer
## carries the whole meaning of the stroke and erases there.
func dab_mode() -> int:
    if not direct:
        return SaDabGeometry.PaintMode.ALPHA_DARKEN if washing else SaDabGeometry.PaintMode.OVER
    return SaDabGeometry.PaintMode.ERASE if erasing else SaDabGeometry.PaintMode.OVER


## Whether the dab kernel applies alpha lock itself.
##
## Only on the direct path. In the buffer the destination alpha is the buffer's
## own and starts at nothing, so a dab that read it there would refuse to paint
## anywhere and the stroke would be blank. The lock is applied once, at the
## commit, against the alpha it is actually about.
func dab_alpha_lock() -> bool:
    return alpha_locked and direct
