## One of the four axes a colour space is made of: the curve between a stored
## value and the light it stands for.
##
## Why this is a value rather than an enum
## ---------------------------------------
## `SaColorSpace.Transfer` had two members and every consumer branched on them by
## hand: the descriptor's GLSL generator, the info docker, the browser's curve
## plot, and a `float transfer` in two push constants that kernels compared
## against 0.5. Adding a third curve meant editing all of them, which is the
## definition of an axis that does not compose.
##
## The observation that makes it compose is that the curves Sara cares about are
## one shape with different numbers. Every one of them is a straight line near
## zero and a power curve above it:
##
##     encode( x ) = x < t/s  ?  s*x  :  a * x^(1/g) - b
##     decode( y ) = y < t    ?  y/s  :  ( (y + b) / a )^g
##
## sRGB is s=12.92, t=0.04045, a=1.055, g=2.4. Rec. 709 is the same shape with
## different constants. A pure gamma curve is the same shape with the straight
## segment switched off by t=0. And **linear is the same shape too**, at s=1, t=0,
## a=1, g=1, where both branches reduce to the identity.
##
## So the kernels need not know which curve they were given: one shape and four
## numbers, rather than a boolean that could only ever mean two things.
##
## Four and not five, because b is not free. A display transfer is normalised so
## that full scale encodes to full scale, `a * 1^(1/g) - b = 1`, which fixes
## `b = a - 1`. sRGB's 1.055 and 0.055 are that pair, and so are Rec. 709's 1.099
## and 0.099. Deriving it rather than storing it is what makes a whole curve fit
## in the composite kernel's push constant, which is full at the 128 bytes Vulkan
## guarantees, and it turns an invariant that held by coincidence across four
## tables into one that cannot be got wrong.
##
## Mirrored through the origin
## ---------------------------
## `pow` is undefined for a negative base, and Sara's canvas carries negatives on
## purpose, so every curve here is applied to the magnitude and given the sign
## back. Clamping instead would silently discard out-of-gamut colour, which is the
## whole thing the no-clamp guarantee exists to prevent.
@tool
class_name SaTransferFunction
extends RefCounted

## Stable ids. These reach `.sad`, so they are the serialisation contract.
const ID_LINEAR: StringName = &"linear"
const ID_SRGB: StringName = &"srgb"
const ID_REC709: StringName = &"rec709"
const ID_GAMMA22: StringName = &"gamma22"
const ID_GAMMA30: StringName = &"gamma30"

## Any pure power curve, which is what a gamma slider builds. Unlike the ids
## above it does not name one curve, so a file that records it has to record the
## numbers too. See [method SaColorSpace.to_header].
const ID_GAMMA: StringName = &"gamma"

## The range a chooser should offer for [method gamma], and the floor that keeps
## `1.0 / exponent` finite. Below 1 the encode is a power rather than a root,
## which is unusual and legal, and the point of offering a slider is not to decide
## for the person using it.
const MIN_GAMMA: float = 0.1
const MAX_GAMMA: float = 6.0

## How many floats [method to_params] writes.
const PARAM_FLOATS: int = 4

var id: StringName = ID_SRGB

var display_name: String = "sRGB"

## Slope of the straight segment near zero.
var slope: float = 12.92

## Where the straight segment ends, measured in **encoded** values. The matching
## threshold in linear values is this over [member slope], which is what makes one
## number enough for both directions.
var threshold: float = 0.04045

## Scale of the power segment. Its offset is `gain - 1`, see [method offset].
var gain: float = 1.055

## Exponent taking encoded values to linear ones. Decode raises to this, encode
## raises to its reciprocal.
var exponent: float = 2.4


static func create(
    function_id: StringName, name: String, curve_slope: float, curve_threshold: float, a: float, g: float
) -> SaTransferFunction:
    var curve := SaTransferFunction.new()
    curve.id = function_id
    curve.display_name = name
    curve.slope = curve_slope
    curve.threshold = curve_threshold
    curve.gain = a
    curve.exponent = g
    return curve


## The power segment's offset, fixed by the normalisation `encode(1) == 1`.
func offset() -> float:
    return gain - 1.0


## No curve at all. Written as the same four numbers rather than as a special
## case, because a special case here is a branch in every kernel that reads one.
static func linear() -> SaTransferFunction:
    return create(ID_LINEAR, "Linear", 1.0, 0.0, 1.0, 1.0)


## IEC 61966-2-1. What Sara has always painted in.
static func srgb() -> SaTransferFunction:
    return create(ID_SRGB, "sRGB", 12.92, 0.04045, 1.055, 2.4)


## ITU-R BT.709, the broadcast curve. A shallower toe and a lower power than
## sRGB, so the two are close but not interchangeable.
static func rec709() -> SaTransferFunction:
    return create(ID_REC709, "Rec. 709", 4.5, 0.081, 1.099, 1.0 / 0.45)


## A pure power curve with no straight segment, which is what older software
## usually means by "gamma 2.2".
static func gamma22() -> SaTransferFunction:
    return create(ID_GAMMA22, "Gamma 2.2", 1.0, 0.0, 1.0, 2.2)


## A pure cube root, which is the curve Oklab's own lightness is built on.
##
## Its use is an Oklab document: the coordinate axis decides what the chunks hold,
## and the transfer axis decides what the document's RGB *view* is, which is what
## the eleven RGB-defined blend modes are arithmetic on. Choosing this makes that
## view cube-root encoded, so those modes work on the same kind of scale the
## storage does instead of on a 2.4-power one.
##
## `exponent` is the gamma, so encode is the cube root and decode is the cube.
static func gamma30() -> SaTransferFunction:
    return create(ID_GAMMA30, "Gamma 3.0 (cube root)", 1.0, 0.0, 1.0, 3.0)


## A pure power curve of any exponent, with no straight segment.
##
## `gamma22()` and `gamma30()` are two points on this, kept as named curves
## because a name round-trips through a `.sad` header on its own and an arbitrary
## exponent does not.
static func gamma(g: float) -> SaTransferFunction:
    var safe := clampf(g, MIN_GAMMA, MAX_GAMMA)
    return create(ID_GAMMA, "Gamma %.2f" % safe, 1.0, 0.0, 1.0, safe)


## A curve from the four numbers a header recorded, however it is named.
##
## This is what lets a document declare a curve no build has a name for, which is
## the whole reason the four-parameter form exists: an id alone would let a
## curve chosen on a slider be painted with and never saved.
##
## Null for four numbers no curve can be made of, which the header's reader
## answers with the curve the id names or sRGB, saying so. A slope of nought
## under a threshold, an exponent of nought, or a gain whose offset leaves the
## power's base below zero turned every texel of the document into an infinity
## or a NaN, and nothing downstream clamps one.
static func from_params(function_id: StringName, values: Array) -> SaTransferFunction:
    if values.size() < PARAM_FLOATS:
        return null
    for value: Variant in values.slice(0, PARAM_FLOATS):
        if not (value is float or value is int) or not is_finite(SaTyped.real(value)):
            return null
    var s := SaTyped.real(values[0])
    var t := SaTyped.real(values[1])
    var a := SaTyped.real(values[2])
    var g := SaTyped.real(values[3])
    if g <= 0.0 or a <= 0.0 or t < 0.0 or (t > 0.0 and s <= 0.0) or t + a - 1.0 < 0.0:
        return null
    var known := from_id(function_id)
    var label: String = known.display_name if known != null else "Custom"
    if function_id == ID_GAMMA:
        label = "Gamma %.2f" % g
    return create(function_id, label, s, t, a, g)


## Every curve a document may declare, in the order a chooser should offer them.
static func presets() -> Array[SaTransferFunction]:
    var all: Array[SaTransferFunction] = [srgb(), linear(), rec709(), gamma22(), gamma30()]
    return all


## The curve *function_id* names, or null when nothing does.
##
## Null rather than a silent fall back to sRGB. A file naming a curve this build
## does not have is a real situation, and what to do about it is not the same
## decision in a loader as in a chooser.
static func from_id(function_id: StringName) -> SaTransferFunction:
    for curve in presets():
        if curve.id == function_id:
            return curve
    return null


## Where the straight segment ends, in linear values.
func linear_threshold() -> float:
    return threshold / slope if not is_zero_approx(slope) else 0.0


## True when this curve is the identity, so a caller can skip work rather than
## compute it. Asked of the values, not of the id: a custom curve that happens to
## be flat is still flat.
##
## It is a correctness guard as much as an optimisation. `pow(x, 1.0)` is not
## exactly `x` on a GPU, so a linear document put through the general form would
## come back perturbed in its last bits. Every kernel that reads a curve takes
## this branch first, and the branch is uniform across a dispatch because it comes
## from a push constant.
func is_identity() -> bool:
    return is_equal_approx(gain, 1.0) and is_equal_approx(exponent, 1.0) and is_equal_approx(slope, 1.0)


## Stored value to light-linear value, sign preserved.
func decode(value: float) -> float:
    if is_identity():
        return value
    var m := absf(value)
    var out := m / slope if m < threshold else pow((m + offset()) / gain, exponent)
    return signf(value) * out


## Light-linear value to stored value, sign preserved.
func encode(value: float) -> float:
    if is_identity():
        return value
    var m := absf(value)
    var out := slope * m if m < linear_threshold() else gain * pow(m, 1.0 / exponent) - offset()
    return signf(value) * out


## The four numbers a kernel needs, in the order `transfer_curve.gmacs` reads
## them. Never an id: a kernel that switched on which curve it was given would put
## every curve's cost on every document.
func to_params() -> PackedFloat32Array:
    var packed := PackedFloat32Array([slope, threshold, gain, exponent])
    assert(packed.size() == PARAM_FLOATS, "Transfer params are the wrong size")
    return packed


func matches(other: SaTransferFunction) -> bool:
    if other == null:
        return false
    return (
        is_equal_approx(slope, other.slope)
        and is_equal_approx(threshold, other.threshold)
        and is_equal_approx(gain, other.gain)
        and is_equal_approx(exponent, other.exponent)
    )
