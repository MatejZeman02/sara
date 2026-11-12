## Driving a stamp brush's settings from a scenario's `pen_settings`.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The one door onto a curve option that is not the brush editor. `curve_option`
## edits whatever control is on screen and complains when none is, so proving
## that a ticked sensor now works *without* a visit to the editor had no step to
## make the tick with. `SaCaptureLayers.brush` hands this whatever a scenario
## wrote under `pen_settings`, asked for by method name so the skeleton names no
## module script.
##
## ```json
## {"brush": {"pen_settings": {"rotation": {"enabled": true, "sensors": ["tilt_direction"]}}}}
## ```
##
## `sensors` is a list of the keys `SaSensor.KEYS` holds, each switched on, and
## switching one on switches the option's curve on with it. An entry may also be
## a dictionary naming the key under `id` and setting the sensor's own fields
## beside it, which is [method _tick_sensors]'s half of this. Everything else is
## set by name on the option, so `strength`, `use_curve`, `use_same_curve` and
## `combine` are all reachable. An unknown option or sensor name is skipped
## rather than raising, because a scenario naming one is a scenario to fix and
## not a run to lose.
##
## Its own class because [SaStampBrushSettings] stands at its line bound, and
## this walks a capture's JSON where the settings hold what a brush is.
class_name SaBrushPenSettings
extends RefCounted


## Sets fields on the options by name, and switches sensors on, from the
## dictionary a scenario wrote under `pen_settings`.
##
## **Pressure ticked on Size or Opacity with no curve of its own draws the curve
## the bar's switch draws**, `SaStampBrushSettings.pressure_curve` of the
## switch's gamma, pressure to the power 4.8 for Size and 1.2 for Opacity. The
## harness's pen reads every door stroke through a table fitted to the Size
## switch's curve, so on the straight line a fresh option has, Fill at radius 40
## lays 29 px at a pressure of 0.01 where the switch lays 1. *straight* keeps a
## bare tick on the straight line, which is the line the shipped recipes are
## written and recorded on, so `SaShippedPresets.build` passes it. Every other
## option has no switch and keeps the straight line.
static func apply(settings: SaStampBrushSettings, spec: Dictionary, straight: bool = false) -> void:
    var by_name: Dictionary = settings.options()
    for key: String in spec:
        # `masking` reaches the mask's own two options, which are on the masking
        # block rather than in `options()`, so they get their own half of this
        # door.
        if key == "masking":
            _apply_mask_pen_settings(settings, spec[key])
            continue
        var option: SaCurveOption = by_name.get(key, null)
        if option == null or not spec[key] is Dictionary:
            continue
        var asked: Dictionary = spec[key]
        var bare := option.sensors.is_empty() and not asked.has("common_curve")
        for field: String in asked:
            if field == "sensors":
                _tick_sensors(option, asked[field], SaDynamics.is_offset(StringName(key + "_option")))
            elif field in option:
                option.set(field, asked[field])
        if bare and not straight and _ticks_a_bare_pressure(asked.get("sensors", [])):
            var curve := _switch_curve(settings, option)
            if not curve.is_empty():
                option.common_curve = curve


## Whether *keys*, a `sensors` list as [method _tick_sensors] reads it, ticks
## pressure without a curve beside it.
static func _ticks_a_bare_pressure(keys: Variant) -> bool:
    if not keys is Array:
        return false
    for key: Variant in keys as Array:
        var asked: Dictionary = key if key is Dictionary else {}
        var name := String(asked.get("id", "")) if key is Dictionary else String(key)
        if SaSensor.id_of(name) == SaSensor.Id.PRESSURE:
            return not asked.has("curve")
    return false


## The curve the bar's switch for *option* draws when it goes on, or none for an
## option the bar has no switch for.
static func _switch_curve(settings: SaStampBrushSettings, option: SaCurveOption) -> PackedVector2Array:
    var gamma: GammaFloat = null
    if option == settings.size_option:
        gamma = settings.size_pressure_gamma
    elif option == settings.opacity_option:
        gamma = settings.opacity_pressure_gamma
    else:
        return PackedVector2Array()
    return SaStampBrushSettings.pressure_curve(gamma.gamma() if gamma != null else 1.0)


## The mask's own two options, reached by the same shape the painted tip's are:
## `{"masking": {"size": {"enabled": true, "sensors": ["pressure"]}}}`. The
## names are `size` and `strength`, with `opacity` as the strength's painter
## name, which is what `SaMaskingBrush.option_for` answers.
static func _apply_mask_pen_settings(settings: SaStampBrushSettings, spec: Dictionary) -> void:
    var masking: SaMaskingBrush = settings.masking
    if masking == null or not spec is Dictionary:
        return
    for key: String in spec:
        var option: SaCurveOption = masking.option_for(key)
        if option == null or not spec[key] is Dictionary:
            continue
        var asked: Dictionary = spec[key]
        for field: String in asked:
            if field == "sensors":
                _tick_sensors(option, asked[field])
            elif field in option:
                option.set(field, asked[field])


## Every sensor *keys* names, switched on, on *option*.
##
## An entry is a key, or a dictionary carrying one under `id` and the sensor's
## own fields beside it. A bare key is every sensor whose being on is the whole
## of what a scenario asks, and the dictionary is for the ones that carry a
## setting of their own: the drawing angle's `fan_corners` and `fan_step` are
## the pair the fan needs, and no other door onto them exists outside the brush
## editor. Unknown fields are skipped for the reason an unknown sensor is.
##
## The lift-up is ticked through the door's binding, as the editor's tick is,
## because on the identity curve it reads backwards. *offset* says which of
## its two curves the option needs.
static func _tick_sensors(option: SaCurveOption, keys: Variant, offset: bool = false) -> void:
    if not keys is Array:
        return
    for key: Variant in keys as Array:
        var asked: Dictionary = key if key is Dictionary else {}
        var name := String(asked.get("id", "")) if key is Dictionary else String(key)
        var id := SaSensor.id_of(name)
        if id < 0:
            continue
        if id == SaSensor.Id.LIFT_UP:
            option.bind_lift_up(offset)
            continue
        var sensor := SaSensor.create(id as SaSensor.Id, true)
        for field: String in asked:
            if field != "id" and field in sensor:
                sensor.set(field, asked[field])
        option.set_sensor(sensor)
