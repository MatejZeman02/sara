## Reads a shipped preset's recipe onto a settings resource, for every engine
## that ships its presets as recipes: the stamp, the filter brush, liquify and
## the noise brush.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Why one reader.** The four engines each carried the same `missing_fields`
## and `build`, word for word where their recipes were alike and growing apart
## where one learnt a key, a property path or a pen's curve, that the others
## then lacked. A recipe is a dictionary and a
## settings resource is duck typed, so nothing here names an engine's class.
##
## A recipe may carry four keys. `settings` maps a property path of the kind
## `set_indexed` takes to its value, and a plain field name is such a path.
## `pen_settings` is handed to the resource's own `apply_pen_settings`, and its
## options and fields are checked against `options()`. `lift_up` and `pressure`
## name curve options found through `option_for` or `options()`, and what binds
## them is the engine's own, so its `build` passes a *finish* that does.
##
## Beside them a recipe may carry `description`, a sentence or three on what
## the preset lays and what it is for, which `SaPresetStore.install_shipped`
## writes into the preset's file under `SaPresetMeta.DESCRIPTION_META` and never
## onto the settings. A recipe written before the key had a name says `about`,
## read the same way. Written in British English as a literal, so the message
## template collects it and a cell's tooltip shows it in the painter's language.
##
## **A recipe the template cannot carry is not written**, so a preset naming a
## field the engine does not have is left out rather than shipped half made. The
## question is asked of the resource in hand and of nothing else. A Dry Marker
## written from a settings script with no curve options would be a plain round
## called Dry Marker, and the grid would say a thing about it that is not true.
## `set_indexed` says nothing when a path is missing, so without this the lie
## would also be silent.
##
## Sensor names are not checked here, because a sensor is the module's word.
## The stamp's suite holds them against `SaSensor.KEYS`.
class_name SaPresetRecipe
extends RefCounted


## What *entry* names that *template* does not have, one line per name, and
## empty when the template can carry the whole recipe.
static func missing_fields(template: Resource, entry: Dictionary) -> PackedStringArray:
    var missing := PackedStringArray()
    if template == null:
        missing.append("a settings resource")
        return missing
    var settings: Dictionary = entry.get("settings", {})
    for path: String in settings:
        if not _has_path(template, path):
            missing.append(path)
    for key: String in entry.get("lift_up", []):
        if option(template, key) == null:
            missing.append("lift_up." + key)
    for key: String in entry.get("pressure", {}):
        if option(template, key) == null:
            missing.append("pressure." + key)
    var pen: Dictionary = entry.get("pen_settings", {})
    missing.append_array(_missing_pen(template, pen))
    return missing


## A fresh resource of *script* at its own defaults with *entry* written onto
## it, or null when the script cannot carry the whole recipe. *finish*, when
## given, is called with the resource and the entry once the settings and the
## pen's are written, for what only the engine knows how to bind.
##
## The script's defaults rather than a copy of the template's values, so the
## shipped presets are never whatever brush happened to be loaded when the store
## was found missing.
static func build(script: Script, entry: Dictionary, finish := Callable()) -> Resource:
    if script == null:
        return null
    var made: Variant = (script as GDScript).new()
    if not made is Resource:
        return null
    var settings: Resource = made
    if not missing_fields(settings, entry).is_empty():
        return null
    var values: Dictionary = entry.get("settings", {})
    for path: String in values:
        settings.set_indexed(NodePath(path), values[path])
    if entry.has("pen_settings"):
        settings.call("apply_pen_settings", entry["pen_settings"], true)
    if finish.is_valid():
        finish.call(settings, entry)
    return settings


## The curve option *key* names on *settings*, through its `option_for` so a
## recipe may name Size's by `radius`, or by `options()` alone for a script
## that has no such method, or null when it has none by that name.
static func option(settings: Object, key: String) -> Object:
    if settings.has_method("option_for"):
        var found: Variant = settings.call("option_for", key)
        return found if found is Object else null
    var options: Dictionary = settings.call("options") if settings.has_method("options") else {}
    var named: Variant = options.get(key, null)
    return named if named is Object else null


## What *pen*, a recipe's `pen_settings`, names that *template* has no option or
## field for, or empty when it names nothing missing.
static func _missing_pen(template: Resource, pen: Dictionary) -> PackedStringArray:
    var missing := PackedStringArray()
    if pen.is_empty():
        return missing
    if not template.has_method("options") or not template.has_method("apply_pen_settings"):
        missing.append("pen_settings")
        return missing
    var options: Dictionary = template.call("options")
    for key: String in pen:
        var found: Object = options.get(key, null)
        if found == null:
            missing.append("pen_settings." + key)
            continue
        for field: String in pen[key]:
            if field != "sensors" and not (field in found):
                missing.append("pen_settings.%s.%s" % [key, field])
    return missing


## Whether *path*, a property path of the kind `set_indexed` takes, names a
## property *target* has at every step.
static func _has_path(target: Object, path: String) -> bool:
    var at: Object = target
    var steps := path.split(":")
    for index in steps.size():
        var step := steps[index]
        if at == null or not (step in at):
            return false
        if index < steps.size() - 1:
            var next: Variant = at.get(step)
            if not next is Object:
                return false
            at = next
    return true
