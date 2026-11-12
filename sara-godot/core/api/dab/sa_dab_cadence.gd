## How far apart the next dab goes, in travel and in time.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Two answers a stroke needs before it may ask the walk anything: how far the
## tip has to travel before the next dab is due, and how long it has to wait if
## the pen is standing still. They are one small class because they are asked
## together, once per dab, and because each folds the same two switches, the
## airbrush and the spacing option, into a number the walk can use without
## knowing either exists.
##
## [method dabs_for_frame] is the only caller of the interval that is not the
## walk itself, and it is here for that reason.
class_name SaDabCadence
extends RefCounted

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## What one frame of the airbrush may deposit, however far behind the clock
## is. This is the ceiling that keeps a stalled frame from paying its whole
## debt in one dispatch batch, and it is the only cap there is.
##
## **The accumulator does not cap the rate at one dab a frame.**
## [method dabs_for_frame] asks until the walk says no, up to this
## number, so a rate of 100 at sixty frames a second deposits its hundred and
## the whole of the Rate slider is honoured. The Rate row's tooltip says the
## same to a painter.
const MAX_DABS_PER_FRAME: int = 8


## The spacing one dab of *tip* asks for.
##
## Anisotropic always, rather than reading an isotropic switch the tip has no
## field for. A round tip's two spacings come out equal and
## `Spacing.is_isotropic()` picks the cheap walk anyway, so the switch would buy
## an option row and no behaviour. The day a painter wants a flat tip stepped by
## one number it is a field on the tip and a row beside Auto Spacing.
##
## A tip under [constant SaDabGeometry.PIXEL_MODE_DIAMETER] steps by one texel
## instead of by any of that, which is the small-dab pixel mode: this is the one
## place a real dab asks for a step, so it is where the size is tested.
##
## *extra_scale* is the spacing option's answer for this dab, so a sensor on
## Spacing multiplies the whole step rather than the tip's fraction of it.
## *distance_enabled* is false under Ignore Spacing, which turns the travel gate
## off entirely so time is the only clock left and a fast drag deposits the same
## count as a slow one. *pixel_grid* false keeps a brush that stays out of the
## mode on its own spacing at every size, Fill's thin line (`SaSmallDab`).
static func spacing_for(
    tip: Resource, extra_scale: float = 1.0, distance_enabled: bool = true, pixel_grid: bool = true
) -> SaStrokeDistance.Spacing:
    var brush_tip: SaBrushTipScript = tip
    var half := brush_tip.half_extent()
    return SaStrokeDistance.effective_spacing(
        half.x * 2.0,
        half.y * 2.0,
        brush_tip.spacing,
        extra_scale,
        false,
        brush_tip.angle,
        false,
        brush_tip.auto_spacing,
        brush_tip.auto_spacing_coeff,
        distance_enabled,
        pixel_grid and SaDabGeometry.is_pixel_mode(half.x * 2.0)
    )


## Milliseconds between airbrush dabs, or -1.0 when the airbrush is off.
##
## A rate in dabs per second is the reciprocal of an interval in seconds, and
## the walk counts in milliseconds, so the interval is `1000 / rate`. The rate
## curve option divides it rather than multiplying the rate, so a sensor on Rate
## can only slow the airbrush down, which is what
## `SaStampBrushSettings.rate_option`'s own comment says it is for.
##
## Read through `in` because the eraser, the scratchpad and a suite that builds
## one by hand may hand this a settings resource that predates the field.
static func interval_for(settings: Resource) -> float:
    if not "airbrush_enabled" in settings or not SaTyped.flag(settings.get("airbrush_enabled")):
        return -1.0
    return 1000.0 / maxf(0.001, SaTyped.real(settings.get("airbrush_rate")))


## Whether Ignore Spacing is on, which is the negation of *distance_enabled*.
static func ignores_spacing(settings: Resource) -> bool:
    if not "airbrush_ignore_spacing" in settings or not SaTyped.flag(settings.get("airbrush_enabled")):
        return false
    return SaTyped.flag(settings.get("airbrush_ignore_spacing"))


## How many dabs this frame's airbrush clock owes, and it advances that
## clock.
##
## The decision, without the dispatch, so a suite can advance the clock by hand
## and count what a held pen deposits over an interval it measured itself. A
## count read against a frame number rather than against a time is the failure
## this guards, and nothing outside the app could produce the count
## otherwise.
##
## Zero when the interval has not come round or the airbrush is off. Never more
## than [constant MAX_DABS_PER_FRAME]. The caller answers for the pen being
## down, which is the one thing here that is the tool's state rather than the
## clock's.
static func dabs_for_frame(walk: SaStrokeDistance, at: Vector2, interval: float, delta: float) -> int:
    if interval <= 0.0:
        return 0
    walk.timed_interval = interval
    var elapsed := delta * 1000.0
    # The frame's own time, added once, because the walk sees this frame as
    # several overlapping sub-segments and cannot add them up itself.
    walk.timed_elapsed += elapsed
    # The start time advances to each dab the way the segment start advances to
    # each position, or the second question of a frame sees the whole frame's
    # elapsed time again and the airbrush fires once a call rather than once an
    # interval.
    var consumed := 0.0
    var dabs := 0
    for _step in MAX_DABS_PER_FRAME:
        var t := walk.next_point_position(at, at, consumed, elapsed)
        if t < 0.0:
            break
        consumed = lerpf(consumed, elapsed, t)
        dabs += 1
    return dabs
