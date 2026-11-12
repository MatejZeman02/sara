## The paper's brightness, contrast and cutoff: six settings rows folded into
## the pattern texture by one dispatch.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Baked where the scale is already baked**, because the push constant block is
## full. A pattern is rebuilt when a row moves and not when a dab lands, so the
## numbers folded into the texels once cost nothing per dab.
##
## **The contrast pivots about the neutral point.** The gain is `1 + contrast`,
## as in `adjust.gmacs`'s `brightness_contrast`, but the pivot is the tile's own
## mean (`pattern_mean` writes it into one texel on the card, so no readback)
## until a painter switches `texture_neutral_from_pattern` off and names one. A
## pivot fixed at a half would send a paper centred near 0.8, like Paper Grain,
## mostly to one.
##
## **A neutral setting bakes nothing.** `is_neutral` is asked before the
## dispatch, so a brush that never touches the rows pays no pass and no texture.
##
## **The cutoff is three more rows in the same pass**, the reason the class keeps
## the name "tone". A cutoff turns a continuous grain into a sparse one, which is
## the difference between a paper and grains placed about.
class_name SaPatternTone
extends RefCounted

## What happens to a pattern texel outside the cutoff band.
##
## Krita's `Texture/Pattern/CutoffPolicy` by the same numbers, whose combo reads
## "Cut Off Disabled", "Cut Off Brush" and "Cut Off Pattern". [constant OFF] is
## the band ignored, [constant DAB] takes the texel to nothing so the dab paints
## nothing there, and [constant PAPER] takes it to full so the dab paints as if
## there were no paper at all. The two are not each other's inverse: one makes
## the grain sparse and the other makes it patchy, and a painter reaching for
## "small grains placed at random" wants the first.
enum Policy { OFF, DAB, PAPER }

## The shader and the kernel in it, which are the same word.
const KERNEL: String = "pattern_tone"

## The `vec4` the kernel reads: brightness, contrast, the neutral point, spare.
const TONE_FIELD: String = "tone"

## The second `vec4`: the band's left bound, its right bound, the policy as a
## float, spare.
const CUTOFF_FIELD: String = "cutoff"

## The kernel that averages the tile into the one texel the tone pivots about.
const MEAN_KERNEL: String = "pattern_mean"

## The three images the shader declares, the last being that one texel.
const PATTERN_IMAGE: String = "sa_pattern"
const TONED_IMAGE: String = "sa_toned"
const MEAN_IMAGE: String = "sa_mean"

## The settings key that turns the contrast about the pattern's own mean.
const FROM_PATTERN_KEY: String = "texture_neutral_from_pattern"

## The stamp brush's settings version whose step is [method migrate_neutral].
const FROM_PATTERN_VERSION: int = 5

## The bands the three rows offer.
##
## Brightness and contrast are symmetric about nought because nought is the
## pattern as its author drew it, and a painter reaching for either wants to be
## able to go back by reading the number rather than by remembering it. The
## contrast's ceiling of one is the spread doubled and its floor of minus one is
## the grain flattened to the neutral point itself, which is the two ends the
## gain `1 + contrast` has to offer. The neutral point is a pattern value, so
## its band is a pattern value's band.
const MIN_BRIGHTNESS: float = -1.0
const MAX_BRIGHTNESS: float = 1.0
const MIN_CONTRAST: float = -1.0
const MAX_CONTRAST: float = 1.0
const MIN_NEUTRAL: float = 0.0
const MAX_NEUTRAL: float = 1.0

## The cutoff band's own band, which is a pattern value's, the way the neutral
## point's is. Krita writes the two bounds as bytes and the import divides.
const MIN_CUTOFF: float = 0.0
const MAX_CUTOFF: float = 1.0

## What Krita writes a cutoff bound as, so the import has one number to divide
## by rather than a magic 255 in the middle of a clamp.
const KRITA_CUTOFF_FULL: float = 255.0

## The Neutral Point row on a new brush, the pivot `adjust.gmacs` uses without a
## row. It turns nothing until the pattern's own mean is switched off.
const DEFAULT_NEUTRAL: float = 0.5

## Why the last bake answered nothing. Empty while it worked.
var error: String = ""

## The compute over `pattern_tone.gmacs`, made on the first bake.
##
## Held here rather than in a static for the reason `SaDabPattern`'s header
## gives: a static compute outlives the rendering device at exit and frees its
## pipelines into a device that is already gone. This object dies with the
## `SaDabPattern` that holds it, which dies with the brush.
var _compute: SaCompute = null


## The brightness *settings* asks for, clamped to the band, and nought for a
## settings resource written before the key existed.
static func brightness_of(settings: Resource) -> float:
    return _read(settings, "texture_brightness", 0.0, MIN_BRIGHTNESS, MAX_BRIGHTNESS)


## The contrast *settings* asks for, as the widening about the neutral point.
static func contrast_of(settings: Resource) -> float:
    return _read(settings, "texture_contrast", 0.0, MIN_CONTRAST, MAX_CONTRAST)


## The value the contrast pivots about while [method from_pattern_of] is false.
static func neutral_of(settings: Resource) -> float:
    return _read(settings, "texture_neutral", DEFAULT_NEUTRAL, MIN_NEUTRAL, MAX_NEUTRAL)


## Whether the contrast turns about the pattern's own mean rather than the
## Neutral Point row, which a new brush does and a resource without the key does.
static func from_pattern_of(settings: Resource) -> bool:
    return settings == null or not FROM_PATTERN_KEY in settings or bool(settings.get(FROM_PATTERN_KEY))


## The version 5 step of the stamp brush's `migrate()`.
##
## A file written before the switch turned its contrast about the Neutral Point
## row, so one whose contrast is not nought switches the pattern's mean off and
## paints what it painted. One at nought keeps the switch on, because a pivot
## with nothing turning about it moves no texel: it paints what it painted too,
## and grows its tooth the way a new brush does. A fresh resource is migrated at
## construction with its contrast at nought, which is what leaves a new brush on
## the pattern's own mean.
static func migrate_neutral(settings: Resource, version: int) -> void:
    if settings == null or not FROM_PATTERN_KEY in settings or version >= FROM_PATTERN_VERSION:
        return
    if not is_zero_approx(contrast_of(settings)):
        settings.set(FROM_PATTERN_KEY, false)


## A neutral point a file names, clamped to the row's band and taken as the
## pivot, so an imported `.kpp` turns about the number its author wrote rather
## than about the pattern's own mean.
static func take_neutral(settings: Resource, value: float) -> void:
    if settings == null or not FROM_PATTERN_KEY in settings:
        return
    settings.set("texture_neutral", clampf(value, MIN_NEUTRAL, MAX_NEUTRAL))
    settings.set(FROM_PATTERN_KEY, false)


## The cutoff band's left bound as a pattern value.
static func cutoff_left_of(settings: Resource) -> float:
    return _read(settings, "texture_cutoff_left", MIN_CUTOFF, MIN_CUTOFF, MAX_CUTOFF)


## The cutoff band's right bound as a pattern value.
static func cutoff_right_of(settings: Resource) -> float:
    return _read(settings, "texture_cutoff_right", MAX_CUTOFF, MIN_CUTOFF, MAX_CUTOFF)


## What happens outside the band: one of [enum Policy], as the int a settings
## row stores and an `ENUM` spec's choice id is.
##
## Clamped rather than trusted for the reason every other reader here is: a
## `.kpp` is a file somebody else wrote, and a preset from a Krita that grew a
## fourth policy would otherwise reach the kernel as a number it has no branch
## for.
static func cutoff_policy_of(settings: Resource) -> int:
    if settings == null or not "texture_cutoff_policy" in settings:
        return Policy.OFF
    return clampi(int(settings.get("texture_cutoff_policy")), Policy.OFF, Policy.PAPER)


## Whether the cutoff moves any texel at all, which is a policy that is not
## [constant Policy.OFF] over a band that is not the whole range.
##
## A band of the whole range is the shipped default and is what a painter who
## picked a policy and then dragged both bounds back out has, so it reads as
## the cutoff being off rather than as a pass that copies every texel.
static func cuts(settings: Resource) -> bool:
    if cutoff_policy_of(settings) == Policy.OFF:
        return false
    return cutoff_left_of(settings) > MIN_CUTOFF or cutoff_right_of(settings) < MAX_CUTOFF


## Whether *settings* leaves the pattern exactly as its author drew it, which is
## the case a bake is skipped in. The neutral point alone changes nothing: it is
## a pivot, and a pivot with nothing turning about it moves no texel.
static func is_neutral(settings: Resource) -> bool:
    if cuts(settings):
        return false
    return is_zero_approx(brightness_of(settings)) and is_zero_approx(contrast_of(settings))


## The key a texture cache is kept under, so a row moving rebuilds and a stroke
## of a hundred dabs does not.
static func key_of(settings: Resource) -> String:
    return (
        "%.4f|%.4f|%.4f|%d|%.4f|%.4f|%d"
        % [
            brightness_of(settings),
            contrast_of(settings),
            neutral_of(settings),
            int(from_pattern_of(settings)),
            cutoff_left_of(settings),
            cutoff_right_of(settings),
            cutoff_policy_of(settings),
        ]
    )


## What the dump reads.
func report(settings: Resource) -> Dictionary:
    return {
        "brightness": brightness_of(settings),
        "contrast": contrast_of(settings),
        "neutral": neutral_of(settings),
        "neutral_from_pattern": from_pattern_of(settings),
        "cutoff_left": cutoff_left_of(settings),
        "cutoff_right": cutoff_right_of(settings),
        "cutoff_policy": cutoff_policy_of(settings),
        "cutting": cuts(settings),
        "baked": not is_neutral(settings),
        "error": error,
    }


## *source* with the tone *settings* asks for folded in, as a second texture of
## the same size and format, or *source* itself when the tone is neutral.
##
## Null with [member error] set when the pass cannot run, which a caller reads
## as the pattern being unusable rather than as the tone being skipped: a
## silently untoned pattern is a wrong picture, and a wrong picture is the one
## thing this cannot answer.
func bake(source: SaTexture, settings: Resource) -> SaTexture:
    if source == null or not source.rid.is_valid():
        error = tr("there is no pattern texture to tone.")
        return null
    if is_neutral(settings):
        error = ""
        return source
    var compute := _tone_compute()
    if compute == null:
        error = tr("no rendering device, so %s could not run.") % KERNEL
        return null
    var toned := SaTexture.new(source.size, RenderingDevice.DATA_FORMAT_R32_SFLOAT)
    var mean := SaTexture.new(Vector2i.ONE, RenderingDevice.DATA_FORMAT_R32_SFLOAT)
    if toned.rd == null or not toned.rid.is_valid() or not mean.rid.is_valid():
        error = tr("no texture could be made to tone the pattern into.")
        return null
    var from_pattern := from_pattern_of(settings)
    var images := {PATTERN_IMAGE: source, TONED_IMAGE: toned, MEAN_IMAGE: mean}
    var params := {
        TONE_FIELD: Vector4(brightness_of(settings), contrast_of(settings), neutral_of(settings), 1.0 if from_pattern else 0.0),
        CUTOFF_FIELD: _cutoff_vector(settings),
    }
    # The mean only when the tone reads it. The texel stays bound either way,
    # because a uniform set has to cover every binding the shader declares, and
    # unwritten it is never read: the tone takes the row's number instead.
    if from_pattern:
        compute.run(MEAN_KERNEL, images, params, Rect2i(Vector2i.ZERO, Vector2i.ONE))
    compute.run(KERNEL, images, params, Rect2i(Vector2i.ZERO, source.size))
    error = ""
    return toned


## The band and the policy as the kernel's `vec4`, with the policy sent as
## [constant Policy.OFF] whenever [method cuts] says nothing is cut.
##
## Sending the off policy rather than the band is what makes a tone-only bake
## one branch in the kernel instead of two comparisons per texel, and it is also
## the only place the "a whole band is no cutoff" rule is written down for the
## GPU: the kernel itself has no notion of the range being whole.
static func _cutoff_vector(settings: Resource) -> Vector4:
    var policy: int = cutoff_policy_of(settings) if cuts(settings) else Policy.OFF
    return Vector4(cutoff_left_of(settings), cutoff_right_of(settings), float(policy), 0.0)


## The compute, made on the first bake and kept, because compiling the kernel
## once per settings change would be a compile per slider drag.
func _tone_compute() -> SaCompute:
    if _compute == null and GlobalShaderCompiler.get_rd() != null:
        _compute = SaCompute.new(KERNEL)
    return _compute


## One additive key off *settings*, clamped, and *fallback* when the resource
## does not carry it. The `in` guard is `SaDabPattern`'s: a preset written
## before the three rows existed loads with none of them and paints as it did.
static func _read(settings: Resource, key: String, fallback: float, low: float, high: float) -> float:
    if settings == null or not key in settings:
        return fallback
    return clampf(float(settings.get(key)), low, high)
