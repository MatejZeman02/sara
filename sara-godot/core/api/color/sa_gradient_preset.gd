## One saved gradient: a name on disk and the ramp's stops.
##
## A ramp is an `SaColorRamp`, which is a `RefCounted` and cannot be written to a
## `.tres`, so this is the thin `Resource` that carries one to and from
## `SaPresetStore`. That store and not a second one, because it sits in the
## skeleton rather than in the brush module so anything with a settings resource
## can use it.
##
## The stops travel as `SaColorRamp.to_array()` gives them, four floats per
## colour rather than a hex string, because Sara is float throughout (hard
## rule 5) and a ramp written as `#33cc4d80` comes back a different colour.
@tool
class_name SaGradientPreset
extends Resource

## `[{"position": float, "color": [r, g, b, a]}, ...]`, exactly
## `SaColorRamp.to_array()`.
##
## `@export` so `SaPresetStore.copy_settings` finds it: that walks the script's
## property list and an unexported `var` is not in it, which is the whole of why
## a preset saved without this annotation came back empty.
@export var stops: Array = []


## The preset holding *ramp*'s stops.
static func from_ramp(ramp: SaColorRamp) -> SaGradientPreset:
    var preset := SaGradientPreset.new()
    if ramp != null:
        preset.stops = ramp.to_array()
    return preset


## The ramp this preset describes, or *fallback* when the file held nothing a
## ramp can be built from. Never null, because a control with no ramp draws
## nothing and reads as a broken docker rather than as a failed load.
func to_ramp(fallback: SaColorRamp = null) -> SaColorRamp:
    return SaColorRamp.from_array(stops, fallback)
