## The fifteenth registry: where input comes from when Godot does not hand it
## to a control by itself, a MIDI controller the first. A module registers an
## [SaInputSource] through [method SaContext.register_input_source], and the
## settings, the door's `midi` step and the state dump ask it by its id, none of
## them naming the module. Why there is one at all is the source's note.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A source follows the settings it names.** The registry hears the
## settings' [signal SaSettingsValues.changed] once anything is registered and
## calls [method SaInputSource.apply] on each source that names the property, so
## no file of the settings has to know which setting opens which device. A
## source is applied once as it registers too, which is the start for one a
## module brings at boot.
class_name SaInputSourceRegistry
extends RefCounted

## Registration and removal.
signal changed

## `{"source": SaInputSource, "module": StringName}` apiece, oldest first.
var _sources: Array[Dictionary] = []

## The settings a source follows, the painter's unless a suite hands its own.
var _settings: SaSettingsValues = null


## *settings* is what a source's setting moves on, the painter's profile when
## none is given.
func _init(settings: SaSettingsValues = null) -> void:
    _settings = settings


## Registers *source* for *module_id* and applies it. Refused for no source, a
## source with no id, or an id already registered.
func register(source: SaInputSource, module_id: StringName = &"") -> bool:
    if source == null:
        push_error("SaInputSourceRegistry: an input source cannot be null.")
        return false
    if String(source.id).is_empty():
        push_error("SaInputSourceRegistry: an input source needs an id.")
        return false
    if source_of(source.id) != null:
        push_error("SaInputSourceRegistry: an input source '%s' is already registered." % source.id)
        return false
    _sources.append({"source": source, "module": module_id})
    _hear_settings()
    changed.emit()
    source.apply()
    return true


## Removes every source *module_id* registered, each released first so the
## inputs it opened are closed.
func unregister_module(module_id: StringName) -> void:
    var kept: Array[Dictionary] = []
    var gone: Array[SaInputSource] = []
    for held: Dictionary in _sources:
        if held["module"] != module_id:
            kept.append(held)
        else:
            gone.append(held["source"])
    if gone.is_empty():
        return
    _sources = kept
    for source: SaInputSource in gone:
        source.release()
    changed.emit()


## The source registered under *source_id*, or null when none is.
func source_of(source_id: StringName) -> SaInputSource:
    for held: Dictionary in _sources:
        var source: SaInputSource = held["source"]
        if source.id == source_id:
            return source
    return null


## Every source, oldest first.
func listed() -> Array[SaInputSource]:
    var out: Array[SaInputSource] = []
    for held: Dictionary in _sources:
        out.append(held["source"])
    return out


## A setting moved, so every source that names *property* is applied again.
func setting_changed(property: StringName) -> void:
    for source: SaInputSource in listed():
        if source.settings.has(property):
            source.apply()


## The dump's blocks, each source's own under its id.
func capture_states() -> Dictionary:
    var out := {}
    for source: SaInputSource in listed():
        out[String(source.id)] = source.capture_state()
    return out


## Feeds *spec* to the source under *source_id* as its device would, and
## answers the line the door's step prints, which says so when no source of
## that id is registered.
func simulate(source_id: StringName, spec: Dictionary) -> String:
    var source := source_of(source_id)
    if source == null:
        return "SaCapture: no input source %s is registered, so %s went nowhere" % [source_id, JSON.stringify(spec)]
    return source.simulate(spec)


## The registry the main scene holds, or null where no main scene holds
## registries, as in a suite. A walk to the main scene, so it is asked at a door
## step and a dump and never per frame.
static func in_app() -> SaInputSourceRegistry:
    var tree := Engine.get_main_loop() as SceneTree
    var main_node: Node = tree.current_scene if tree != null else null
    if main_node == null or not ("registries" in main_node):
        return null
    var registries: SaRegistries = main_node.get("registries")
    return registries.input_sources if registries != null else null


## Connects the settings once the first source arrives, so the many bare
## contexts a suite builds never listen to the painter's profile.
func _hear_settings() -> void:
    if _settings == null:
        _settings = SaSettings
    if not _settings.changed.is_connected(setting_changed):
        _settings.changed.connect(setting_changed)
