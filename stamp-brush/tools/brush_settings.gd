## Resource containing configurable parameters for a brush.
##
## Stores radius, hardness, opacity, flow, spacing, colour and tablet pressure dynamics.
extends Resource

## The stamp engine's, the same id `SaStampBrushSettings` declares, because a
## preset written from these older settings loads onto that resource.
const PRESET_ENGINE: StringName = &"stamp"

@export var radius: float = 0.02314814815  # 2x radius is diameter (% proportional to the canvas lower dimension)
@export var hardness: GammaFloat = GammaFloat.new(0.0, 1.0)
@export var opacity: float = 1.0  # maximum opacity per stroke
@export var flow: GammaFloat = GammaFloat.new(1.0, 2.4)  # strength per dab/stamp
@export var spacing: float = 0.05  # % of the brush diameter

## The stabilizer in front of the interpolation: 0 off, 1 a weighted moving
## average, 2 a rope. `stabilizer_amount` is nought to one, how many
## samples or how long a rope. Both travel with a preset.
@export var stabilizer_mode: int = 0
@export var stabilizer_amount: float = 0.5
@export var size_by_pressure: bool = false
@export var size_pressure_gamma: GammaFloat = GammaFloat.new(0.0, 2.0)
@export var opacity_by_pressure: bool = true
@export var opacity_pressure_gamma: GammaFloat = GammaFloat.new(0.0, 0.5)
@export var color: Color = Color(1.0, 1.0, 1.0, 1.0)

# No exposure: the paint exposure is the foreground's own stops in
# `SaColors`, which the colour already carries, and a preset's old multiplier
# is read without it.

const SaLayerScript = preload("res://core/api/document/sa_layer.gd")
@export var blend_mode: StringName = SaLayerScript.BLEND_MODE.NORMAL

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## The shape of a dab, and everything about it that is not colour or
## pressure. A sub-resource, so a saved preset carries it whole.
##
## **`radius` above is still the size the painter drags** and this tip's
## `diameter` is written from it before each dab rather than kept in step by
## hand: the fraction of the canvas is what a preset means by a size, and the
## pixels are what the kernel needs.
@export var tip: Resource = SaBrushTipScript.new()

## Whether a pen may enter the pixel mode, as on `SaStampBrushSettings`, so a shipped recipe that turns it off, Fill's,
## can be carried by a template of this script as well.
@export var pixel_mode_when_small: bool = true
