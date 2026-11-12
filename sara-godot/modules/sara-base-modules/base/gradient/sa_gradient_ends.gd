## The gradient tool's rule for its two ends: a fresh gradient opens with the
## picked pair and the alphas the painter last gave its ends.
##
## The picker has no alpha a painter sets, so a picked colour is always opaque
## and the alphas can only come from the profile.
##
## Beside the tool rather than on `SaColorRamp`. The ramp is a type of the door
## that other tools and filters use, and a ramp built anywhere else, a test, a
## saved gradient, a later tool with two ends of its own, must not silently
## take the gradient's alphas. Keeping the rule here is what keeps `from_pair`
## pure.
##
## **The alphas are the module's own preferences**, read and written through
## `SaContext.preference`, which the module hands this at `register`. One
## object, built once by the module and handed to the tool as its descriptor's
## `shared_settings` and to the ramp control through its builder, which is why
## it is a `Resource`.
##
## Without a context, a test's or a control built outside the module, the ends
## open opaque and remember nothing.
class_name SaGradientEnds
extends Resource

## The two keys under the module's section, the names the skeleton's `[tools]`
## keys had, which the version-15 migration moves across unchanged.
const START_ALPHA_KEY := &"gradient_start_alpha"
const END_ALPHA_KEY := &"gradient_end_alpha"

## The library's two stock gradients, which are live rather than files: the
## picked pair, and the foreground fading to nothing. Each is the far end's
## alpha, and the near end of both is opaque.
##
## Here rather than in the library, because what a stock gradient is is a rule
## for the two ends and the alphas they remember, which is this file. The
## library only lists them.
const TO_BACKGROUND := &"foreground_to_background"
const TO_TRANSPARENT := &"foreground_to_transparent"
const STOCK := [
    {"id": TO_BACKGROUND, "label": "Foreground to Background", "far_alpha": 1.0},
    {"id": TO_TRANSPARENT, "label": "Foreground to Transparent", "far_alpha": 0.0},
]

## The module's context, held weakly. The tool registry holds the descriptor
## that holds this, and the context holds the registry, so a strong reference
## is a ring nothing but the module's unload would ever break.
var _context: WeakRef = null


func _init(context: SaContext = null) -> void:
    if context != null:
        _context = weakref(context)


## The alpha the near end opens with, opaque when nothing is remembered.
func start_alpha() -> float:
    return _alpha(START_ALPHA_KEY)


## The alpha the far end opens with, opaque when nothing is remembered.
func end_alpha() -> float:
    return _alpha(END_ALPHA_KEY)


## A remembered alpha, clamped here because the module is the one that decides
## what its preference may be, and a hand-edited profile is not a promise.
func _alpha(key: StringName) -> float:
    var context := _live_context()
    if context == null:
        return 1.0
    var stored: Variant = context.preference(key, 1.0)
    if not (stored is float or stored is int):
        return 1.0
    return clampf(float(stored), 0.0, 1.0)


func _live_context() -> SaContext:
    return _context.get_ref() as SaContext if _context != null else null


## The two-stop ramp the gradient tool opens with: the picked pair, carrying the
## endpoint alphas the painter last set.
func fresh_ramp(near: Color, far: Color) -> SaColorRamp:
    var ramp := SaColorRamp.from_pair(near, far)
    apply_remembered_alphas(ramp)
    return ramp


## Puts the remembered endpoint alphas on *ramp*'s first and last stops, without
## announcing a change: this runs while a ramp is still its default and an
## announcement would be read as the painter having edited it.
func apply_remembered_alphas(ramp: SaColorRamp) -> void:
    if ramp.stops.size() < SaColorRamp.MIN_STOPS:
        return
    var near: Color = ramp.stops[0]["color"]
    near.a = start_alpha()
    ramp.stops[0]["color"] = near
    var far: Color = ramp.stops[ramp.stops.size() - 1]["color"]
    far.a = end_alpha()
    ramp.stops[ramp.stops.size() - 1]["color"] = far


## Re-seeds an untouched two-stop *ramp* from the picked pair, keeping the
## alphas its ends already carry. What the gradient tool calls while its ramp is
## still following, so a painter who picks a colour and then drags gets that
## colour.
##
## The ramp's own alphas and not the remembered ones, which it opened with. The
## two differ when another surface's gradient was edited or a stock gradient
## was chosen there, and a ramp that says it follows the colours must not turn
## into a fade because of a slider on the scratchpad.
##
## One function rather than two writes in the tool, because the alpha rule and
## the colour rule are one operation: writing the pair and then the alphas in
## two places is how the second one ends up forgotten.
func reseed(ramp: SaColorRamp, near: Color, far: Color) -> void:
    if ramp.stops.size() != SaColorRamp.MIN_STOPS:
        return
    ramp.stops[0]["color"] = Color(near, Color(ramp.stops[0]["color"]).a)
    ramp.stops[1]["color"] = Color(far, Color(ramp.stops[1]["color"]).a)


## Whether *stock* names one of the stock gradients.
static func is_stock(stock: StringName) -> bool:
    return _stock_far_alpha(stock) >= 0.0


## The far alpha *stock* puts on the ramp, and -1 for a name that is no stock
## gradient.
static func _stock_far_alpha(stock: StringName) -> float:
    for entry: Dictionary in STOCK:
        if entry["id"] == stock:
            return float(entry["far_alpha"])
    return -1.0


## Puts *ramp* back on the stock gradient *stock* in place: two stops, *near* at
## the press end and opaque, *far* at the release end at the stock's alpha. The
## two alphas are remembered as well, so the next launch opens on the gradient
## chosen and a stale fade to nothing does not come back. False, with *ramp*
## untouched, for a name that is no stock gradient.
##
## Without announcing a change, for the reason `apply_remembered_alphas` gives:
## the tool reads an announcement as the painter editing the ramp, and this is
## the opposite.
func restock(ramp: SaColorRamp, stock: StringName, near: Color, far: Color) -> bool:
    var far_alpha := _stock_far_alpha(stock)
    if far_alpha < 0.0:
        return false
    ramp.stops.clear()
    ramp.stops.append({"position": 0.0, "color": Color(near, 1.0)})
    ramp.stops.append({"position": 1.0, "color": Color(far, far_alpha)})
    remember_endpoint_alpha(ramp, 0)
    remember_endpoint_alpha(ramp, 1)
    return true


## Writes stop *index*'s alpha to the profile when it is an endpoint, so a fresh
## launch's `fresh_ramp` opens with it. Does nothing for a middle stop:
## remembering one would mean adding a stop changed what the next launch opens
## with.
##
## Called by the ramp control rather than by `SaColorRamp.set_stop_alpha`, which
## stays pure for the reason `from_pair` does. The control is the single door a
## painter's alpha edit comes through, its slider and the capture step
## included, so a mirrored value is written from one setter and never from each
## caller.
func remember_endpoint_alpha(ramp: SaColorRamp, index: int) -> void:
    if index < 0 or index >= ramp.stops.size() or ramp.stops.size() < SaColorRamp.MIN_STOPS:
        return
    var context := _live_context()
    if context == null:
        return
    var alpha: float = clampf(Color(ramp.stops[index]["color"]).a, 0.0, 1.0)
    if index == 0:
        context.set_preference(START_ALPHA_KEY, alpha)
    elif index == ramp.stops.size() - 1:
        context.set_preference(END_ALPHA_KEY, alpha)
