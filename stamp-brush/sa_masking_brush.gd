## The masking brush: a second tip, its own size and its own spacing, carried by
## the one settings resource, and its own curve options.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Sara's own, read from what a mask is rather than from a port.** Krita runs a
## whole second engine per dab. A mask is a shape multiplying the coverage the
## first shape laid down, and a shape here is `SaBrushTip`, so this is a tip, a
## size and a spacing beside it.
##
## **A `Resource`, so the preset store carries it and nothing else has to know.**
## The store copies by script variable name, so this block travels in the `.tres`
## the way `tip` does, and a preset written before it existed loads with the mask
## off. It rides a buffer of its own to the kernel, because binding 4 holds the
## pattern sampler. The kernel, the editor page and the Krita import all read the
## one shape here.
##
## **The mask has its own dynamics**, since a mask at one fixed size reads as a
## stamp. `size_option` scales the size and `strength_option` is the mask's
## opacity, read by [method evaluated_size] and [method evaluated_strength].
## Flow, rotation, scatter and mirror carry too, read by the painted tip's own
## evaluator `SaDynamics` ([method dab_for] hands it this block), so no second
## copy of the arithmetic can drift. Flow is not a number in the kernel: Krita
## multiplies the mask preset's opacity and flow into each dab's alpha, so here
## the flow folds into [method evaluated_strength] as a second factor.
class_name SaMaskingBrush
extends Resource

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## The floor the mask's diameter is held above, which is `state_brush.gd`'s for
## the painted tip. A dab of no size is a dispatch over an empty rectangle, and
## a *mask* of no size would be worse than that: it is a coverage of nothing
## multiplying a dab that was going to paint.
const SMALLEST_DIAMETER: float = 0.1

## The strength a mask with no option reaches: the whole mask, which is what
## switching one on means.
const FULL_STRENGTH: float = 1.0

## How the mask's coverage meets the dab's, the five of
## Krita's masking composites Sara has arithmetic for. The number is what the
## buffer carries at `SaStampBindings.MASK_OP`, and `masking_tip.gmacs` names the same
## five against the same numbers.
##
## **Multiply is nought**, so every block saved before the field existed loads
## as the mask it always was, and a buffer written with the slot at nought is
## the kernel's old line exactly.
enum Op { MULTIPLY, SUBTRACT, DARKEN, BURN, OVERLAY }

## Krita's composite op ids against the ops above, which are the strings
## `MaskingBrush/MaskingCompositeOp` holds in a preset.
const OP_IDS: Dictionary = {
    "multiply": Op.MULTIPLY,
    "subtract": Op.SUBTRACT,
    "darken": Op.DARKEN,
    "burn": Op.BURN,
    "overlay": Op.OVERLAY,
}

## Off, so every preset a painter already has paints exactly as it did.
@export var enabled: bool = false

## The second shape. Its own `SaBrushTip`, with its own generator, ratio, angle,
## fades and softness curve, because the whole point of a masking brush is a
## shape that is not the one being painted with.
##
## **Its fades are stored and the painted tip's are not.** The bar's Hardness row
## writes the painted tip's two fades on every dab, so a tip carried between
## brushes brings no hardness with it. Nothing writes over these, so a mask that
## was drawn soft stays soft while the painter drags the Hardness row.
@export var tip: Resource = SaBrushTipScript.new()

## The mask's diameter as a multiple of the dab's, one being a mask exactly the
## size of the dab it masks.
##
## **A multiplier rather than a size in pixels**, which is the one decision in
## this file. Krita's masking brush carries an absolute size, and an absolute
## size here would come apart the moment the painter dragged the size row: a
## fifty pixel mask over a two hundred pixel dab is a dot, and over a ten pixel
## dab it is nothing at all. Sara's own size is a fraction of the canvas already
## ([member SaStampBrushSettings.radius]), so a second absolute number would be
## the only length in the brush that answers to nothing. A multiplier keeps the
## mask on the dab at every size, and a painter who wants the mask to stand
## still has the Masking Brush page's row to set it with.
@export var size: float = 1.0

## Fraction of the mask's own diameter between two of its dabs, the way
## `SaBrushTip.spacing` is for the painted tip.
##
## Stored here rather than taken from the painted tip because a mask laid down
## at the dab's own spacing is a mask that never varies along the stroke, which
## is a texture nobody asked for. Nothing reads it yet: the kernel lays the
## mask over the dab it is masking, and the stroke-long mask that this number
## is really for is not built.
@export var spacing: float = 0.1

## How the mask's size follows the sensors, as a fraction of the size row
## above.
##
## A `SaCurveOption` like the painted tip's `size_option`, so a size-like value
## whose ceiling is one: the option makes the mask smaller than the row says and
## never larger, and a painter who wants larger raises the row. Off for a new
## brush and for every preset written before the option existed, which is the
## whole mask at the size the row set.
@export var size_option: SaCurveOption = _fresh_option()

## How much of the mask the dab keeps, following the sensors.
##
## The mask's opacity: a strength of one is the whole mask and nought is no mask
## at all, which is what the buffer's strength slot means. Off for a new brush,
## and off answers the whole mask, so nothing existing changes.
@export var strength_option: SaCurveOption = _fresh_option()

## How much of the mask a dab keeps, as a second factor on the strength.
##
## Krita multiplies a dab's flow into the alpha its opacity sets, dab by dab,
## and Sara's mask is one dab per painted dab, so a flow here is a strength
## there and [method evaluated_strength] multiplies the two. Off for a new
## brush, and off answers one, so nothing existing changes.
@export var flow_option: SaCurveOption = _fresh_option()

## How the mask turns with the sensors, on top of its own tip's resting angle.
##
## Read the way the painted tip's rotation is, by `SaDynamics`, so a drawing
## angle sensor turns the mask along the stroke and a constant turns nothing.
## Still not the dab's rotation: the mask turns by its own option only, which
## is the one decision `sa_mask_coverage` in `masking_tip.gmacs` records.
@export var rotation_option: SaCurveOption = _fresh_option()

## How far the mask wanders from the dab's centre, in the mask's own diameters,
## which is why its ceiling is five like the painted tip's.
##
## The mask moves inside the painted dab's box and never out of it: a mask can
## only take coverage away, so the dirty rectangle stays the painted tip's own.
@export var scatter_option: SaCurveOption = _fresh_option(5.0)

## Which way the scatter may move the mask, as `scatter_axis_x` and
## `scatter_axis_y` are for the painted tip. `SaDynamics` reads them by name.
@export var scatter_axis_x: bool = true
@export var scatter_axis_y: bool = true

## When the mask is turned over, per dab, on top of its tip's own two mirror
## booleans, which is the painted tip's mirror path with the mask's tip on it.
@export var mirror_option: SaCurveOption = _fresh_option()

## Which axes the mirror option may turn over, X alone by default for the reason
## `SaStampBrushSettings.mirror_axis_x` gives.
@export var mirror_axis_x: bool = true
@export var mirror_axis_y: bool = false

## How the mask's coverage meets the dab's, one of [enum Op].
##
## Krita's masking brush is painted into a device of its own and then
## composited onto the dab's alpha, the mask as the source and the dab as the
## destination, and which composite is the preset's to say. Multiply keeps the
## dab where the mask is and nowhere else, subtract cuts the mask out of it,
## darken keeps the lower of the two, burn eats the dab from its thin edges
## inwards as the mask thins, and overlay lifts a dab above half and lowers one
## under it. The formulas are in `sa_mask_applied` in `masking_tip.gmacs`.
##
## Strength stays what it was for every op: nought is the dab untouched and
## one is the composite whole, so the mask's opacity option fades between the
## dab and the op's answer rather than being folded into the mask first, which
## for subtract would be a different cut and for multiply is the same number.
@export var op: Op = Op.MULTIPLY


## Whether there is a mask to read at all.
func active() -> bool:
    return enabled and tip != null


## The mask's diameter in document pixels over a dab of *dab_diameter*, after
## the size option has read the sensors.
##
## *info* is null wherever a caller has no stroke, which is every suite that
## asks for a shape without one: the option then answers its neutral value and
## the diameter is the row's size exactly as it was.
func diameter_for(dab_diameter: float, info: SaStrokeInfo = null) -> float:
    return maxf(SMALLEST_DIAMETER, maxf(0.0, dab_diameter) * maxf(0.0, evaluated_size(info)))


## The second tip carrying this block's size and spacing, ready to be measured.
##
## The one door the kernel's binder needs, and it is here rather than there for
## the reason `state_brush.gd` copies the painter's radius onto the painted tip:
## the tip is what the geometry reads, so the two numbers that live beside it
## are copied onto it in one place rather than remembered at every call site.
func shaped_tip(dab_diameter: float, info: SaStrokeInfo = null) -> Resource:
    if tip == null:
        tip = SaBrushTipScript.new()
    tip.diameter = diameter_for(dab_diameter, info)
    tip.spacing = spacing
    return tip


## The mask's size as a multiple of the dab's, after the size option has read
## the sensors. One is the size the row set, and the option can only make the
## mask smaller, the way the painted tip's size option works.
func evaluated_size(info: SaStrokeInfo = null) -> float:
    var factor := 1.0
    if info != null and size_option != null and size_option.enabled:
        factor = size_option.size_like(info)
    return maxf(0.0, size) * factor


## The mask's strength after its own opacity and flow options. One is the
## whole mask, which is what every mask was before the options existed, so a
## block whose options are off answers exactly what it answered.
func evaluated_strength(info: SaStrokeInfo = null) -> float:
    if info == null:
        return FULL_STRENGTH
    var strength := FULL_STRENGTH
    if strength_option != null and strength_option.enabled:
        strength = strength_option.size_like(info)
    if flow_option != null and flow_option.enabled:
        strength *= flow_option.size_like(info)
    return strength


## The mask's own dab for one sample, of which the kernel reads the rotation,
## the scatter and the mirror.
##
## The painted tip's evaluator reads this block as it reads the settings, so
## every option under the settings' names is read exactly as the painted tip's
## is and every other one answers its neutral value. *info* null, which is
## every caller with no stroke, is the neutral dab itself: no turn, no offset
## and the tip's own mirror.
func dab_for(dab_diameter: float, info: SaStrokeInfo = null) -> SaDabParams:
    if info == null:
        return SaDabParams.new()
    return SaDynamics.new(self).evaluate(info, maxf(0.0, dab_diameter) * maxf(0.0, size))


## The option the name refers to, for the importer and for a scenario's
## `pen_settings`. `size` and `strength` are the stored field names, and
## `opacity` is the strength's painter name, which is what Krita calls it.
func option_for(name: String) -> SaCurveOption:
    match name:
        "size":
            return size_option
        "strength", "opacity":
            return strength_option
        "flow":
            return flow_option
        "rotation":
            return rotation_option
        "scatter":
            return scatter_option
        "mirror":
            return mirror_option
        _:
            return null


## Krita's id for [member op], which is what a dump and a scenario name it by.
func op_id() -> String:
    return String(OP_IDS.find_key(op))


## The op Krita's *id* names, or -1 for one Sara has no arithmetic for, which
## the importer then leaves at multiply and tags.
static func op_of(id: String) -> int:
    return int(OP_IDS.get(id.strip_edges(), -1))


## What a state dump says about the block.
##
## The shape's own numbers rather than a texel of it, which would be a read back
## from the card, and the same answer `SaBrushTipMask.report` gives: what a mask
## looks like is read off the scenario's shot, and what a dump can say is which
## shape was set. The options and the size ramp are reported too, so a dump can
## say the mask's size follows the sensors without reading a texel back either.
func report() -> Dictionary:
    var block: Dictionary = {"enabled": enabled, "active": active(), "size": size, "spacing": spacing, "op": op_id()}
    block["size_option"] = _option_report(size_option)
    block["strength_option"] = _option_report(strength_option)
    for name: String in ["flow", "rotation", "scatter", "mirror"]:
        block[name + "_option"] = _option_report(option_for(name))
    block["scatter_axes"] = [scatter_axis_x, scatter_axis_y]
    block["mirror_axes"] = [mirror_axis_x, mirror_axis_y]
    block["size_ramp"] = _size_ramp()
    if tip == null:
        block["tip"] = {}
        return block
    var fade: Vector2 = tip.effective_fade()
    block["tip"] = {
        "generator": int(tip.generator),
        "shape": int(tip.shape),
        "diameter": tip.diameter,
        "ratio": tip.ratio,
        "angle": snappedf(tip.angle, 0.000001),
        "softness": tip.softness,
        "fade": [snappedf(fade.x, 0.000001), snappedf(fade.y, 0.000001)],
        "image_path": tip.image_path,
    }
    return block


## One option's state, as the enabled flag, the strength and the sensors it is
## listening to, which is what a dump wants rather than the option's whole shape.
func _option_report(option: SaCurveOption) -> Dictionary:
    if option == null:
        return {}
    var names: Array[String] = []
    for sensor: SaSensor in option.active_sensors():
        names.append(SaSensor.key_of(sensor.id))
    return {"enabled": option.enabled, "strength": option.strength, "active": names}


## The effective size multiplier at five pressures, so a dump can say the size
## slot follows the sensors without a texel. A flat ramp is the honest answer
## for an option that is off or a mask whose size is not modulated.
func _size_ramp() -> Array[float]:
    var ramp: Array[float] = []
    for i in range(5):
        var pressure := 0.2 + 0.2 * float(i)
        var info := SaStrokeInfo.new()
        info.begin(Vector2.ZERO, 1)
        info.pressure = pressure
        ramp.append(snappedf(evaluated_size(info), 0.000001))
    return ramp


## An option that is off, reads no sensor and answers its whole strength, which
## is the neutral state of every one of the mask's options. *maximum* is the
## ceiling, one for all but the scatter.
static func _fresh_option(maximum: float = 1.0) -> SaCurveOption:
    var option := SaCurveOption.new()
    option.enabled = false
    option.use_curve = true
    option.strength = 1.0
    option.strength_min = 0.0
    option.strength_max = maximum
    return option
