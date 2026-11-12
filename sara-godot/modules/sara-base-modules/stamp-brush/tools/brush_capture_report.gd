## What the stamp brush answers a capture with: its dynamics vocabulary, what the
## migration makes of the shipped presets, the diameters a pressure ramp asks
## for, the last dabs it evaluated and the walk of the last stroke.
##
## **Why this lives in the module.** Every one of those five blocks is arithmetic
## over the brush's own resource, its own sensors and its own dab params, so
## written in `sara-godot/ui/` they would make the skeleton reach into the module twice
## over: by naming `SaStampBrushSettings`, `SaSensor`,
## `SaCurveOption`, `SaStrokeInfo` and `SaDynamics`, and by preloading
## `res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd` outright.
## The skeleton has to boot with `modules/` empty, and a `preload` of a path that
## is not there is a parse error rather than a missing block.
##
## So the direction is reversed. The tool answers
## [method ToolState.capture_report] and the state report merges what it says,
## which is the public door applied to a dump: a third-party tool adds a block
## to the capture the same way this one does, and the skeleton names nothing.
##
## Built with the tool state it reports about, the way every report class is
## built with its subject. A null tool state is allowed and is what the three
## blocks that need no live stroke are answered from.
extends RefCounted

class_name SaBrushCaptureReport

## Where the migrated curve is read, which is what the migration is
## graded on.
const GRADE_POINTS: int = 11

## The resource an older build wrote. Loaded by path, which is legal here and was
## not in the skeleton: this file and that one are in the same module, so the path
## is there exactly when this file is.
const OldSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")

## The shipped recipes, which this file reads its own module's way. The same
## script the module registers under the `shipped_presets` role, so what a dump
## says about where they came from is the file a caller gets from the
## registries.
const SaShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")

## The tool this reports about, or null when only the stroke-free blocks are
## wanted.
var _tool: ToolState = null

## The name the machine registered it under. A tool does not carry its own name,
## the machine's dictionary is where it lives, so it arrives with the request.
var _name: String = ""

## Whether that tool is the one the machine is on. The blocks about the last
## stroke are empty when it is not, because a dump taken with the crop tool up
## has no brush stroke to describe.
var _active: bool = false


func _init(tool_state: ToolState = null, tool_name: String = "", active: bool = false) -> void:
    _tool = tool_state
    _name = tool_name
    _active = active


## Every block the brush contributes, by the key the state dump writes it under.
func blocks() -> Dictionary:
    return {
        "brush_dynamics": dynamics(),
        "brush_migration": migration(),
        "brush_size_ramp": size_ramp(),
        "brush_dabs": dabs(),
        "stroke_walk": stroke_walk(),
        "brush_texture": texture(),
        "brush_masking": masking(),
        "brush_smudge": smudge(),
    }


## What the dynamics layer answers in a running app.
##
## Every sensor asked for its reading of one hand-built sample, so a constant that
## survived the suite and not the app would show here as a number out of place
## rather than as a crash. `sample` is the same sample in every dump, which is
## what makes two dumps comparable at all. The Texture page's state as the dab
## pipeline reads it: the name, the scale, the offset, the invert, whether a
## texture is bound and what the option is set to, so a shot of a grainy stroke
## has a number beside it.
func texture() -> Dictionary:
    var pattern: SaDabPattern = _tool.get("dab_pattern") if "dab_pattern" in _tool else null
    var settings: Resource = _tool.get("settings") if "settings" in _tool else null
    var out: Dictionary = pattern.report(settings) if pattern != null else {}
    var option: SaCurveOption = settings.get("texture_option") if settings != null and "texture_option" in settings else null
    out["enabled"] = option != null and option.enabled
    out["strength"] = option.strength if option != null else 0.0
    return out


## The masking brush's block as the live settings hold it: the second tip's
## generator and shape, the size and the spacing, and whether the mask is on
## at all.
##
## The block answers for itself rather than being unpacked here, for the reason
## `texture()` above reaches into `SaDabPattern`: what a dump says about a thing
## is that thing's own arithmetic, and a report written here would be a second
## place to keep in step with a field.
func masking() -> Dictionary:
    var settings: Resource = _tool.get("settings") if _tool != null and "settings" in _tool else null
    var block: Variant = settings.get("masking") if settings != null and "masking" in settings else null
    if block == null or not block.has_method("report"):
        return {}
    return block.call("report")


## The smudge stage's block as the live settings hold it, and the reservoir's
## own account of the stroke under way when there is one: the switch, the three
## curve options' strengths, the brush's reach as a multiple of the dab, which
## of the stage's two rates it paints at, and the reach the last pickup
## actually sampled.
##
## **Why it is here at all.** A reach the canvas cannot be asked about: the
## shot beside the dump shows the paint coming from further out, and this is the
## number that says how much further without a reader measuring a picture. The
## reservoir answers for itself the way the mask does above, and it is absent
## between strokes, because a stroke drops its carry with the VRAM it holds.
func smudge() -> Dictionary:
    var settings: Resource = _tool.get("settings") if _tool != null and "settings" in _tool else null
    if settings == null or not "smudge_pickup_option" in settings:
        return {}
    var out: Dictionary = {"radius": settings.get("smudge_radius"), "mode": settings.get("smudge_mode")}
    var option: SaCurveOption = settings.get("smudge_pickup_option")
    out["enabled"] = option != null and option.enabled
    for key: String in ["pickup", "color_rate", "length"]:
        var named := "smudge_%s_option" % key
        var curve: SaCurveOption = settings.get(named) if named in settings else null
        out[key] = curve.strength if curve != null else 0.0
    var reservoir: Variant = _tool.get("_smudge") if "_smudge" in _tool else null
    if reservoir != null and reservoir.has_method("report"):
        out["reservoir"] = reservoir.call("report")
    return out


func dynamics() -> Dictionary:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 1)
    info.feed(Vector2(30.0, 0.0), 0.5, Vector2(15.0, -30.0), 90.0, 10.0)
    info.next_dab()
    var readings: Dictionary = {}
    for i in range(SaSensor.KEYS.size()):
        var sensor := SaSensor.create(i as SaSensor.Id, true)
        readings[SaSensor.key_of(i as SaSensor.Id)] = snappedf(sensor.value(info), 0.000001)
    return {
        "sensors": SaSensor.KEYS.size(),
        "deferred": SaSensor.DEFERRED.size(),
        "sample": info.report(),
        "readings": readings,
        "options": _curve_options(info),
    }


## Three curve options at the same sample, so a regression in either reducer shows
## in a state dump and not only in a test.
##
## Built here rather than from a scenario step. A step would let a scenario vary
## them, and what the reducers need watching for is a sign or a bound that moved,
## which a **fixed** trio catches better: the three numbers are the same in every
## dump of every run, so a reader comparing two runs is comparing the reducers and
## nothing else.
##
## The trio touches all three buckets. `plain` is one scaling sensor, `pair` is two
## of them under the mode least like multiply, and `angle` puts the one absolute
## rotation sensor in, which is the bucket that overwrites rather than combines.
func _curve_options(info: SaStrokeInfo) -> Dictionary:
    var plain := SaCurveOption.create_default()

    var pair := SaCurveOption.new()
    pair.set_sensor(SaSensor.create(SaSensor.Id.PRESSURE, true))
    pair.set_sensor(SaSensor.create(SaSensor.Id.TILT_X, true))
    pair.combine = SaCurveOption.Combine.MAXIMUM

    var angle := SaCurveOption.new()
    angle.set_sensor(SaSensor.create(SaSensor.Id.DRAWING_ANGLE, true))

    for option: SaCurveOption in [plain, pair, angle]:
        option.begin_stroke()
    return {"plain": plain.report(info), "pair": pair.report(info), "angle": angle.report(info)}


## What the migration makes of each of the three presets Sara ships.
##
## The recipes are built from `SaShippedPresets.ENTRIES` on the old script, which
## is exactly what `install_shipped` does, rather than read out of
## `user://brush_presets`. A painter's own directory is not the same on two
## machines, and the presets already on disk name a script path that moved when
## the module split, so reading them would photograph the
## `preset-script-path` scenario rather than the migration. What is
## deterministic here is the arithmetic, and the arithmetic is the claim: the
## migrated curve answers what the old exponent answered.
func migration() -> Dictionary:
    var presets: Dictionary = {}
    for entry: Dictionary in SaShippedPresetsScript.entries():
        var old_preset := OldSettingsScript.new()
        for path: String in entry["settings"]:
            old_preset.set_indexed(NodePath(path), entry["settings"][path])
        presets[String(entry["name"])] = _migrated(old_preset)

    # One preset the shipped three cannot show, because all three leave size by
    # pressure off: the steep curve, which is the one its three control points have
    # the most trouble carrying.
    var steep := OldSettingsScript.new()
    steep.size_by_pressure = true
    presets["_size_by_pressure"] = _migrated(steep)

    return {
        "format_version": SaStampBrushSettings.FORMAT_VERSION,
        # How many points the Size switch's curve is drawn with, at its gamma of 2.
        "curve_points": SaStampBrushSettings.pressure_curve(2.0).size(),
        "tool_gamma": SaStampBrushSettings.TOOL_PRESSURE_GAMMA,
        "presets": presets,
        # Where the recipes came from, so a dump proves the table left `core/`
        # rather than only that eight presets exist. The role's script, which is
        # the file the preset group is handed by the registries. The cast is what
        # makes `resource_path` readable: a `const` preload is typed as the class
        # it loads, which has no such member to the checker.
        "source": {"role": SaShippedPresetsScript.ROLE, "script": (SaShippedPresetsScript as Script).resource_path},
    }


## One old preset copied onto the new resource, migrated, and graded.
func _migrated(old_preset: Resource) -> Dictionary:
    var settings := SaStampBrushSettings.new()
    SaPresetStore.copy_settings(old_preset, settings)
    # The one step the switch to this resource has to do for itself. The old
    # script carries no `format_version`, so the copy leaves this object at
    # the version its own constructor stamped and the migration would have
    # nothing to do.
    settings.format_version = 1
    settings.migrate()

    return {
        "was":
        {
            "size_by_pressure": old_preset.size_by_pressure,
            "size_gamma": old_preset.size_pressure_gamma.gamma(),
            "opacity_by_pressure": old_preset.opacity_by_pressure,
            "opacity_gamma": old_preset.opacity_pressure_gamma.gamma(),
        },
        "size": _option_state(settings.size_option, old_preset.size_pressure_gamma.gamma()),
        "opacity": _option_state(settings.opacity_option, old_preset.opacity_pressure_gamma.gamma()),
    }


## One migrated option: what it is set to, and how far its curve is from the
## response the old exponent gave.
##
## The samples are read through a real `SaSensor`, not off the control points,
## because the control points are not what a dab reads. Between them and a dab are
## a monotone cubic, a 256-entry table and a linear read, and a dump that reported
## the control points would be reporting the input rather than the answer.
func _option_state(option: SaCurveOption, gamma: float) -> Dictionary:
    var exponent := gamma * SaStampBrushSettings.TOOL_PRESSURE_GAMMA
    var built := {"enabled": option.enabled, "use_curve": option.use_curve, "active": option.active_sensors().size()}
    if not option.use_curve:
        # An option the migration did not build carries the identity curve, and
        # grading that against the old exponent would report an error of half a
        # unit for an option that is simply off. The old boolean is the answer
        # here, not a number.
        built["built"] = false
        return built

    var sensor := SaSensor.create(SaSensor.Id.PRESSURE, true)
    sensor.curve = option.common_curve.duplicate()

    var samples: Array[float] = []
    var wanted: Array[float] = []
    var worst := 0.0
    for i in range(GRADE_POINTS):
        var pressure := float(i) / float(GRADE_POINTS - 1)
        var info := SaStrokeInfo.new()
        info.begin(Vector2.ZERO, 1)
        info.pressure = pressure
        var answered := sensor.parameter(info)
        var expected := pow(pressure, exponent)
        samples.append(snappedf(answered, 0.000001))
        wanted.append(snappedf(expected, 0.000001))
        worst = maxf(worst, absf(answered - expected))

    built["built"] = true
    built["exponent"] = exponent
    built["samples"] = samples
    built["old_response"] = wanted
    built["worst_error"] = snappedf(worst, 0.000001)
    return built


## What the evaluator makes of a ramp with size by pressure switched on.
##
## Here rather than in the scenario because no capture step can switch a boolean
## row of the tool options bar on: `ToolOptionsDocker.capture_option` writes a
## `FactorSlider` and "Size by Pressure" is a button, which is the gap
## `bar-option-step` was filed against. So the claim that pressure moves the
## diameter is made on a settings resource built here, in the running app, at five
## pressures, and the tool path that reads the same evaluator is proved by the
## suite instead.
func size_ramp() -> Dictionary:
    var settings := SaStampBrushSettings.new()
    settings.size_by_pressure = true
    var dynamics_layer := SaDynamics.new(settings)
    dynamics_layer.begin_stroke()

    var diameters: Array[float] = []
    for i in range(5):
        var pressure := 0.2 + 0.2 * float(i)
        var info := SaStrokeInfo.new()
        info.begin(Vector2.ZERO, 1)
        info.hovering = false
        info.pressure = pressure
        diameters.append(snappedf(dynamics_layer.evaluate(info, 50.0).size, 0.000001))

    return {
        "base_diameter": 50.0,
        "pressures": [0.2, 0.4, 0.6, 0.8, 1.0],
        "diameters": diameters,
        "enabled": settings.size_option.enabled,
    }


## The last few dabs the brush evaluated, and what it read them from.
##
## The dynamics half is arithmetic with no picture of its own. A stroke that came
## out the wrong weight is a wrong number somewhere in nine options, and a
## screenshot cannot say which, so the tool keeps its last five `SaDabParams` and
## this reports them.
func dabs() -> Dictionary:
    if not _reporting_a_stroke():
        return {}
    # The spread, with the stroke's last dab on the end when the decimation did
    # not happen to keep it. Five dabs along a stroke is what the unit's proof
    # line asks for, and four of them are no use without the fifth saying where
    # the stroke ended up.
    var out: Array = []
    for dab: SaDabParams in _tool.get("sampled_dabs"):
        out.append(dab.report())
    var final_dab: SaDabParams = _tool.get("last_dab")
    if final_dab != null and (out.is_empty() or out[-1] != final_dab.report()):
        out.append(final_dab.report())
    var info: SaStrokeInfo = _tool.get("stroke_info")
    var mask: SaBrushTipMask = _tool.get("tip_mask") if "tip_mask" in _tool else null
    return {
        "tool": _name,
        "dabs": out,
        "sample": info.report() if info != null else {},
        "options": _option_flags(_tool.get("settings")),
        "tip": mask.report(_tool.get("settings")) if mask != null else {},
    }


## Which of the nine options the live settings has switched on, and whether each is
## reading its sensors. Two booleans rather than the whole option, because what a
## dump of a stroke wants to say is which options were in play.
func _option_flags(settings: Resource) -> Dictionary:
    var flags: Dictionary = {}
    if settings == null or not settings.has_method("options"):
        return flags
    for key: String in settings.options():
        var option: SaCurveOption = settings.options()[key]
        if option == null:
            continue
        flags[key] = {"enabled": option.enabled, "use_curve": option.use_curve, "active": option.active_sensors().size()}
    return flags


## What the spacing accumulator did on the last stroke, empty when this tool is
## not the one on the machine.
##
## **The count is the point.** Two spacings five times apart both draw a solid bar
## at any size a painter uses, so a screenshot cannot tell them apart and the
## number of dabs behind the bar can. It is read after the stroke rather than
## during it, so it is the whole stroke's total.
func stroke_walk() -> Dictionary:
    if not _active or _tool == null:
        return {}
    var walk: Variant = _tool.get("stroke_distance")
    if walk == null:
        return {}
    var step: Vector2 = walk.get("spacing").get("distance")
    var at: Vector2 = walk.get("last_position")
    return {
        "tool": _name,
        "dabs": int(walk.get("dab_sequence")),
        "travel": snappedf(float(walk.get("total_distance")), 0.001),
        # The live counters are zero between strokes, because the tool resets on
        # the pen lift and a sensor wants them per stroke. These two are what a
        # dump taken after a stroke is actually asking for.
        "previous_dabs": int(walk.get("previous_dabs")),
        "previous_travel": snappedf(float(walk.get("previous_distance")), 0.001),
        # The milliseconds the airbrush clock ran, beside the dabs it fired,
        # because a rate cannot be read off a count alone and a capture's frame is
        # not a sixtieth of a second. Zero for a stroke with no airbrush on it,
        # which is the honest answer rather than a plausible one.
        "previous_timed_ms": snappedf(float(walk.get("previous_timed_elapsed")), 0.001),
        "spacing_x": snappedf(step.x, 0.001),
        "spacing_y": snappedf(step.y, 0.001),
        "last_x": snappedf(at.x, 0.001),
        "last_y": snappedf(at.y, 0.001),
    }


## Whether there is a live stroke to describe: this tool is on the machine and
## carries the two fields the dab blocks read.
func _reporting_a_stroke() -> bool:
    if not _active or _tool == null:
        return false
    return "sampled_dabs" in _tool and "stroke_info" in _tool
