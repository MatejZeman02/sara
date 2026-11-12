## Preferences > Modules: every module Sara found, packaged and the painter's,
## with its name, where it came from and a switch, so a painter keeps the
## modules they use and leaves the rest out.
##
## A switch writes `SaSettings.modules_off`, and the loader reads it once at
## the start, so a change takes effect at the next start and the page says so.
## Putting a module down while Sara runs is what the loader's reload does for
## the painter's own modules, and a packaged module's tools, filters and the
## documents holding its layers are not built to be taken away under them.
##
## Sara Skeleton has no switch, because Sara does not run without it. A module
## left out because it needs one that is off says so under its name, and its
## own switch stays as the painter set it, so switching the other on again
## brings both back.
class_name SaModulesPage
extends SaSettingsPage

## The page's title in the sidebar, the English a door names it by.
const TITLE := "Modules"


func build(ui: SaPage) -> void:
    var listed := ui.section("Modules")
    listed.note(tr("A module switched on or off here is loaded or left out from the next start of Sara."))
    for entry: Dictionary in entries():
        var module_id := StringName(entry["id"])
        var key := StringName("module_%s" % String(module_id).replace("-", "_"))
        if module_id == ModuleLoader.SKELETON_ID:
            listed.custom(String(entry["name"]), _always_on()).named(&"module_sara_skeleton")
            continue
        var row := listed.toggle(String(entry["name"]), ModuleSwitch.new(module_id), ^"on").named(key)
        row.explain(line_of(entry))


## Every module the loader knows of, the skeleton first and then in the order
## the Modules menu lists them: loaded, refused, left out. Each is
## `{"id", "name", "origin", "state", "reason"}`, where state is "on", "off"
## or "refused".
static func entries() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for module_id: StringName in ModuleLoader.loaded_modules:
        var mod: SaModule = ModuleLoader.loaded_modules[module_id]
        out.append(_entry(module_id, mod.get_name(), "on", ""))
    for module_id: StringName in ModuleLoader.failed_modules:
        out.append(_entry(module_id, String(module_id), "refused", ModuleLoader.failed_modules[module_id]))
    for module_id: StringName in ModuleLoader.off_modules:
        var title := String(ModuleLoader.module_names.get(module_id, module_id))
        out.append(_entry(module_id, title, "off", ModuleLoader.off_modules[module_id]))
    return out


static func _entry(module_id: StringName, title: String, state: String, reason: String) -> Dictionary:
    return {
        "id": String(module_id),
        "name": title,
        "origin": String(ModuleLoader.origins.get(module_id, "packaged")),
        "state": state,
        "reason": reason,
    }


## The skeleton's row in place of a switch, a line that wraps.
func _always_on() -> Label:
    var line := Label.new()
    line.text = tr("Always on, because Sara does not run without it.")
    line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return line


## What a module's row says under its name: where it came from, its id, and
## when it is not running now, why.
static func line_of(entry: Dictionary) -> String:
    var from := TranslationServer.translate("Built into Sara")
    if entry["origin"] != "packaged":
        from = (
            TranslationServer.translate("From the folder %s")
            % String(ModuleLoader.module_dirs.get(StringName(entry["id"]), "")).get_file()
        )
    var said := "%s, %s." % [from, entry["id"]]
    match entry["state"]:
        "off":
            said += " " + TranslationServer.translate("Off at this start, %s.") % entry["reason"]
        "refused":
            said += " " + TranslationServer.translate("Refused at this start, %s.") % entry["reason"]
    return said


## One module's switch, the target of its row: on unless the setting lists it.
## Writing it puts the id into the setting or takes it out, and nothing else.
class ModuleSwitch:
    extends RefCounted

    var _module_id: StringName

    var on: bool:
        get:
            return not SaSettings.modules_off.has(String(_module_id))
        set(value):
            var off: Array = SaSettings.modules_off.duplicate()
            off.erase(String(_module_id))
            if not value:
                off.append(String(_module_id))
            SaSettings.modules_off = off

    func _init(module_id: StringName) -> void:
        _module_id = module_id
