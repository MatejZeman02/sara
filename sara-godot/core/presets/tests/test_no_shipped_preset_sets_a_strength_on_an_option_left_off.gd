## No shipped preset sets a strength on an option it leaves off.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Oil Smudge shipped `smudge_dilution_option:strength` 0.5 and
## `smudge_length_option:strength` 0.75 without either option's `enabled`, so
## both boxes were unticked and neither number did anything, since an option
## that is off answers its neutral one whatever its strength says. Blender
## shipped the same two the same way. The dilution is Colour Rate, which starts ticked, so the scan's own test unticks it.
##
## Every shelf of shipped presets a module registers is read through the roles
## the presets bar reads, so a shelf a module adds later is read too, and each
## recipe is built through its own shelf's `build` onto the settings of the
## engine the shelf is for, the resource the install writes. A curve option is
## any stored property of the built settings holding an `SaCurveOption`. One
## that is off is a finding when the recipe names its strength, by a property
## path or under `pen_settings`, or when its strength stands anywhere but where
## a fresh resource of the engine puts it.
##
## In `tests/` rather than the stamp's own suites, because the shelves are found
## through `ModuleLoader`, which a module cannot name past the door.
extends "res://tests/test_framework.gd"

## The shelf the stamp registers under the bare role, and the engine its
## recipes are written for. Every other shelf names its engine after the role's
## `shipped_presets_`, which is how the presets bar asks for it.
const STAMP_ROLE: StringName = &"shipped_presets"
const STAMP_ENGINE: StringName = &"stamp"

## A strength set on an option left off that a shelf means, keyed
## `<preset>: <option>` and saying why. None is meant: an option that is off
## reads its neutral one, so its strength is a number a painter sees in the
## brush editor that paints nothing. The ones allowed are a painter's own,
## which the shipped files hold them as, so that a
## fresh install and a painter's store read equal field by field.
const ALLOWED: Dictionary = {
    "Airbrush: size_option": REFERENCE_FILE,
    "Airbrush: smudge_color_rate_option": REFERENCE_FILE,
    "Spatter: smudge_color_rate_option": REFERENCE_FILE,
    "Streaks: smudge_color_rate_option": REFERENCE_FILE,
    "Dry Strokes: smudge_color_rate_option": REFERENCE_FILE,
    "Torn Gouache: smudge_color_rate_option": REFERENCE_FILE,
    "Broken Chalk: smudge_color_rate_option": REFERENCE_FILE,
}

## Why each of a painter's presets is allowed its strength on an option it
## leaves off.
const REFERENCE_FILE: String = "the reference file holds it, and the stock preset matches it field for field"

## The two Oil Smudge shipped with off until this row, which the scan has to
## find in its recipe as it stood.
const OIL_SMUDGE_AS_IT_STOOD: Array[String] = [
    "Oil Smudge: smudge_color_rate_option",
    "Oil Smudge: smudge_length_option",
]

var _registries: SaRegistries = null


func before_each() -> void:
    _registries = SaRegistries.new()
    _registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    ModuleLoader.verbose = false
    ModuleLoader.load_and_register_modules(_registries.context)
    ModuleLoader.verbose = true


func after_each() -> void:
    ModuleLoader.unload_all()
    _registries = null


## The row's second clause: no shipped preset with a strength set on a disabled
## option, or each one allowed with its reason.
func test_no_shipped_preset_sets_a_strength_on_an_option_it_leaves_off() -> void:
    var found: Array[String] = []
    var read := _read_every_shelf(found)
    assert_true(read.has("Oil Smudge") and read.has("Blender"), "The stamp's two smudges are among the presets read")
    assert_true(read.size() >= 40, "Every shelf's presets are read, %d of them" % read.size())
    var unexplained: Array[String] = []
    for line: String in found:
        if not ALLOWED.has(line.get_slice(" at ", 0)):
            unexplained.append(line)
    assert_eq(unexplained, [] as Array[String], "No shipped preset sets a strength on an option it leaves off")
    for key: String in ALLOWED:
        var still := found.any(func(line: String) -> bool: return line.begins_with(key + " at "))
        assert_true(still, "%s is allowed because %s, and the scan still finds it" % [key, ALLOWED[key]])


## The scan is not blind: Oil Smudge as it shipped before this row, its two
## options off again, is named for both options and for nothing else. The
## colour rate is unticked by its key rather than by taking the key out, as a
## fresh brush's is ticked.
func test_the_scan_names_oil_smudge_as_it_stood() -> void:
    var recipes := _registries.roles.script_for(STAMP_ROLE)
    var settings_script := _settings_scripts()[STAMP_ENGINE] as Script
    var entry := _entry(recipes, "Oil Smudge").duplicate(true)
    var settings: Dictionary = entry["settings"]
    settings["smudge_color_rate_option:enabled"] = false
    settings.erase("smudge_length_option:enabled")
    var found := _findings(recipes, settings_script, entry)
    var named: Array[String] = []
    for line: String in found:
        named.append(line.get_slice(" at ", 0))
    assert_eq(named, OIL_SMUDGE_AS_IT_STOOD, "Both options are named, %s" % [found])


## A strength the recipe leaves at the engine's own default on an option that
## is off is still a finding when the recipe names it, since the recipe says
## the number was meant.
func test_a_strength_written_at_its_default_is_still_named() -> void:
    var recipes := _registries.roles.script_for(STAMP_ROLE)
    var settings_script := _settings_scripts()[STAMP_ENGINE] as Script
    var fresh := settings_script.new() as Resource
    var entry := {
        "name": "Probe",
        "settings": {"smudge_length_option:strength": (fresh.get("smudge_length_option") as SaCurveOption).strength},
        "pen_settings": {"mix": {"strength": (fresh.get("mix_option") as SaCurveOption).strength}},
    }
    var found := _findings(recipes, settings_script, entry)
    assert_eq(found.size(), 2, "Both written strengths are named, %s" % [found])


# --- The scan -----------------------------------------------------------------


## Every recipe of every `shipped_presets` shelf, built onto its engine's
## settings, with each finding appended to *found*. Answers the names read.
func _read_every_shelf(found: Array[String]) -> Array[String]:
    var scripts := _settings_scripts()
    var read: Array[String] = []
    var shelves := 0
    for role: StringName in _registries.roles.list_roles():
        if not String(role).begins_with(String(STAMP_ROLE)):
            continue
        shelves += 1
        var engine := STAMP_ENGINE if role == STAMP_ROLE else StringName(String(role).trim_prefix("%s_" % STAMP_ROLE))
        assert_true(scripts.has(engine), "The %s shelf's engine, %s, has a tool whose settings it builds onto" % [role, engine])
        if not scripts.has(engine):
            continue
        var recipes := _registries.roles.script_for(role)
        for raw: Variant in recipes.call("entries"):
            var entry: Dictionary = raw
            read.append(String(entry.get("name", "?")))
            found.append_array(_findings(recipes, scripts[engine], entry))
    assert_true(
        shelves >= 4, "The stamp's, the noise brush's, the filter brush's and liquify's shelves are read, %d found" % shelves
    )
    return read


## What *entry* of *recipes* sets on an option it leaves off, built onto
## *settings_script*, one line `<preset>: <option> at <strength>` each.
func _findings(recipes: Script, settings_script: Script, entry: Dictionary) -> Array[String]:
    var preset_name := String(entry.get("name", "?"))
    var built := recipes.call("build", settings_script, entry) as Resource
    assert_not_null(built, "%s builds onto the settings of its engine" % preset_name)
    if built == null:
        return []
    var fresh := settings_script.new() as Resource
    var found: Array[String] = []
    for property: String in _curve_options(built):
        var option := built.get(property) as SaCurveOption
        if option.enabled:
            continue
        var stock := fresh.get(property) as SaCurveOption
        var moved := not is_equal_approx(option.strength, stock.strength)
        if moved or _names_strength(built, entry, property):
            found.append("%s: %s at %s" % [preset_name, property, option.strength])
    return found


## The stored properties of *settings* that hold a curve option.
func _curve_options(settings: Resource) -> Array[String]:
    var names: Array[String] = []
    for property: Dictionary in settings.get_property_list():
        if int(property["usage"]) & PROPERTY_USAGE_STORAGE == 0:
            continue
        if settings.get(property["name"]) is SaCurveOption:
            names.append(String(property["name"]))
    return names


## Whether *entry* writes the strength of *settings*'s option *property*, by the
## property path or under the name `options()` gives it in `pen_settings`.
func _names_strength(settings: Resource, entry: Dictionary, property: String) -> bool:
    var values: Dictionary = entry.get("settings", {})
    if values.has("%s:strength" % property):
        return true
    var pen: Dictionary = entry.get("pen_settings", {})
    if pen.is_empty() or not settings.has_method("options"):
        return false
    var options: Dictionary = settings.call("options")
    var option: Object = settings.get(property)
    for key: String in pen:
        if options.get(key, null) == option and (pen[key] as Dictionary).has("strength"):
            return true
    return false


## The settings script of every engine a registered tool paints with, keyed by
## the engine, read off the settings each tool shares.
func _settings_scripts() -> Dictionary:
    var scripts := {}
    for raw: Variant in _registries.tools.list_descriptors():
        var descriptor := raw as SaToolDescriptor
        if descriptor == null or descriptor.shared_settings == null:
            continue
        var script: Script = descriptor.shared_settings.get_script()
        var engine := descriptor.preset_engine
        if engine == &"":
            engine = StringName(script.get_script_constant_map().get("PRESET_ENGINE", ""))
        if engine != &"" and not scripts.has(engine):
            scripts[engine] = script
    return scripts


## The recipe *recipes* ships as *preset_name*.
func _entry(recipes: Script, preset_name: String) -> Dictionary:
    for raw: Variant in recipes.call("entries"):
        var entry: Dictionary = raw
        if String(entry.get("name", "")) == preset_name:
            return entry
    assert_true(false, "%s is a shipped recipe" % preset_name)
    return {}
