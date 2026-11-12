## Autoload singleton that discovers, orders and registers feature modules.
##
## Discovery accepts two layouts, under two roots:
##   res://modules/<name>/module.gd            - one module per repository
##   res://modules/<repo>/<name>/module.gd     - several modules per repository
##
## The nested form exists because a git submodule and a Sara module are not the
## same unit: sara-base-modules is one repository holding the stamp brush, the
## eraser, fill, the eyedropper and navigation as separate modules.
##
## The second root is the user's, `user://modules`, so a module can be dropped
## in beside an installed build rather than only packed into it. Loading a
## script from there is running code the painter put there, so the Modules
## menu shows the folder, every module that loaded, and every one that was
## refused with the reason, rather than an always-ticked list. A packaged
## module wins a name clash, because the user root is scanned second and a
## duplicate id is refused with the reason saying so.
extends Node

## Registered and running: module_id -> SaModule.
var loaded_modules: Dictionary[StringName, SaModule] = {}

## Discovered but refused, with the reason: module_id -> String. The Modules
## menu can show real state instead of a cosmetic checkmark that is always ticked.
var failed_modules: Dictionary[StringName, String] = {}

## Discovered and left out because the painter switched it off on Preferences >
## Modules, or because it needs one that is: module_id -> the reason. Kept apart
## from `failed_modules`, because a choice is not a fault and is never pushed as
## an error.
var off_modules: Dictionary[StringName, String] = {}

## The native modules whose library this start did not load: the module's name
## -> the library file it looked for. Kept apart from `failed_modules`, because
## the module itself may well have registered, with nothing to offer.
var missing_libraries: Dictionary[String, String] = {}

## Every module discovered, by id, with the name it gives itself, so the
## Preferences page can name a module that is off as well as one that loaded.
var module_names: Dictionary[StringName, String] = {}

## What the painter switched off, read from the setting at the start. A suite
## hands its own list to [method load_and_register_modules] instead.
var _switched_off := SaSwitchedOff.new([])

const MODULES_ROOT := "res://modules"
## The painter's own modules, a folder under the data root.
const USER_MODULES_FOLDER := "modules"
const MODULE_SCRIPT := "module.gd"

## Where user modules are read from. A test points it somewhere it can write.
var user_modules_root: String = SaDataRoot.path(USER_MODULES_FOLDER)

## A third root, named on the command line as `--modules-dir=<path>`, scanned
## after the other two.
##
## A capture needs a module the app does not ship, to prove that a module's
## layouts are listed, loaded and forked. Staging one under `user://modules`
## before the run is not something a scenario file can do, and a fixture module
## under `res://modules` would load in the real app, which is worse than either.
## A flag is the only door that lets one scenario carry its own module and no
## ordinary launch see it.
##
## Read once at load rather than kept as a setting: a profile that could name a
## modules root would be a profile that can load code, and this is a testing seam
## rather than a feature.
const MODULES_DIR_FLAG := "--modules-dir="

## An environment variable that stands in for the packaged root, so the gate
## can launch the app against an empty directory and prove that the skeleton
## boots with `modules/` empty, which the README claimed and nothing tested.
## An environment variable rather than a flag, because the gate sets it around
## one launch and no scenario should be able to ask for a Sara with its tools
## gone. Read once, at discovery, like the flag.
const PACKAGED_ROOT_VARIABLE := "SARA_MODULES_ROOT"

## What each module says of itself, refused ones included: module_id ->
## its `SaModuleManifest`, read from the folder's `manifest.cfg` before any of
## the module's code ran and completed by its functions where the file is
## silent. The loader asks the manifest for the version, the API version and
## the dependencies, so a manifest wins over the functions.
var manifests: Dictionary[StringName, SaModuleManifest] = {}

## Where each module came from, refused ones included: module_id -> "packaged"
## or "user". The menu says, because a module the painter did not put there
## and one they did are different answers to "what is this".
var origins: Dictionary[StringName, String] = {}

## Which folder each module was read from: module_id -> the directory holding
## its `module.gd`.
##
## The loader always knew this and never wrote it down, because nothing asked. A
## module may ship a folder of layouts beside its script, and the presets class
## has to be able to find it without knowing anything about modules. Recorded
## for a refused module too, under whichever id it was refused as, because the
## folder is a fact about the disk rather than about the module having loaded.
var module_dirs: Dictionary[StringName, String] = {}

## The name of the folder a module puts its shipped layouts in.
const LAYOUTS_DIR := "layouts"

## The module no setting switches off, for the page that lists the rest.
const SKELETON_ID := SaSwitchedOff.SKELETON

## What compiling each non-packaged module's kernels answered, module_id ->
## `{"rebuilt", "failed", "unchanged"}` in the shape
## `GlobalShaderCompiler.reload_changed` answers. Kept so the reload's record
## and a suite can read what the last load of a module's kernels did, which
## the compiler's own report does not split by module.
var kernel_results: Dictionary[StringName, Dictionary] = {}

var _context: SaContext = null

## Directories that held no module, kept for the summary rather than printed as
## they are found - an empty submodule is normal, not a problem to interrupt for.
var _skipped: Dictionary[String, String] = {}

## Set false by the test runner: a suite that loads modules four times should not
## stamp four module tables into the middle of the test transcript.
var verbose: bool = true


## Nothing to build, and here for the boot mark alone, whose gap since the
## autoload before it is this script's own load.
func _init() -> void:
    SaBootMarks.mark(&"module_loader_init")


## A document that names a module left out of this start says so on screen.
func _ready() -> void:
    EventBus.document_loaded.connect(_on_document_loaded)


## Each module the opened document names and this start left out, said as a
## problem with its name and the reason, rather than a canvas that shows less
## and says nothing. A refusal rather than a fault, because nothing broke: the
## painter left the module out, and the file keeps what it holds for it.
func _on_document_loaded(document: SaDocument) -> void:
    for module_id: StringName in _switched_off.off_named_by(document):
        SaProblems.refuse(
            "ModuleLoader",
            (
                TranslationServer.translate(
                    "This document uses the module %s, which is %s, so what it adds is kept in the file and not shown."
                )
                % [module_id, off_modules[module_id]]
            )
        )


## Whether the painter asked *module_id* off, as the setting stood at the start.
func asked_off(module_id: StringName) -> bool:
    return _switched_off.asked_off(module_id)


## Loads every module found under res://modules and registers it against `ctx`.
##
## Called before the UI is built, so the toolbox and the blend dropdowns can be
## populated from the registries rather than hardcoding their buttons, which
## they would have to if this ran after the UI existed.
##
## *switched_off* is the ids to leave out, the setting's when null, which is
## what a start passes. A suite passes its own so the profile is never written.
func load_and_register_modules(ctx: SaContext, switched_off: Variant = null) -> void:
    _context = ctx
    var asked: Array = SaSettings.modules_off
    if switched_off is Array:
        asked = switched_off
    _switched_off = SaSwitchedOff.new(asked)
    off_modules = _switched_off.reasons
    # Not cleared: the skeleton's own built-in module registers itself here
    # before discovery runs, and it is a loaded module like any other.
    failed_modules.clear()
    _skipped.clear()

    var discovered := _discover_modules()
    if discovered.is_empty():
        push_warning("[ModuleLoader] No modules found under %s or %s." % [packaged_root(), user_modules_root])
        return

    _register_discovered(discovered)
    name_missing_libraries(packaged_root())

    if verbose:
        report()


## Each native module under *root* whose `.gdextension` names a library for
## this platform that Godot did not load, filed in `missing_libraries` and said
## once as a fault, naming the module and the file.
##
## A list with no line for this platform says nothing. The build writes a
## module's list from what its `bin/` holds, so a missing line is a platform
## the library was never built for, Android among them, or a build that said at
## the time that the library failed: a choice or an old word, not a fault of
## this start. A line whose library is not loaded is one, an install that left
## the file behind or a build that dropped it since.
func name_missing_libraries(root: String) -> void:
    missing_libraries.clear()
    for list_path in SaNativeLibraries.lists(root):
        var looked_for := SaNativeLibraries.unloaded(list_path)
        if looked_for.is_empty():
            continue
        var module := _module_in(list_path.get_base_dir())
        missing_libraries[module] = looked_for
        SaProblems.report(
            "ModuleLoader",
            (
                TranslationServer.translate(
                    "The module %s could not load its library %s, so this Sara runs without what the module adds."
                )
                % [module, looked_for]
            )
        )


## The name of the module read from *dir_path*, or the folder's own name for a
## library with no `module.gd` beside it, which the TIFF reader's LZW is.
func _module_in(dir_path: String) -> String:
    for module_id: StringName in module_dirs:
        if module_dirs[module_id].trim_suffix("/") == dir_path.trim_suffix("/"):
            return module_names.get(module_id, String(module_id))
    return dir_path.trim_suffix("/").get_file()


## Registers every module of *discovered* in dependency order, refusing what
## needs a newer API or a dependency that did not register. The boot's
## discovery and the reload both end here, so a reloaded module passes the
## same gates a module read at the start does.
##
## A module that did not ship with Sara has its kernels compiled first,
## because the walk from `res://` never reached its folder and its `register`
## may build a pass over them.
func _register_discovered(discovered: Dictionary[StringName, SaModule]) -> void:
    var ordered := _resolve_dependencies(discovered)
    for module_id: StringName in ordered:
        var module: SaModule = discovered[module_id]
        var manifest := _manifest_in(module_id, discovered)
        module_names[module_id] = manifest.name
        if not _switched_off.reason(module_id, manifest.dependency_ids()).is_empty():
            continue

        if manifest.sara_api > SaContext.API_VERSION:
            _fail(module_id, "needs API version %d but this build provides %d" % [manifest.sara_api, SaContext.API_VERSION])
            continue

        var unsatisfied := _unsatisfied_dependencies(module_id, discovered)
        if not unsatisfied.is_empty():
            _fail(module_id, "unsatisfied dependencies: %s" % ", ".join(unsatisfied))
            continue

        if origins.get(module_id, "packaged") != "packaged":
            kernel_results[module_id] = SaModuleReload.compile_kernels(str(module_dirs.get(module_id, "")))

        var scoped := _context.for_module(module_id)
        module.context = scoped
        module.own_folder = str(module_dirs.get(module_id, ""))
        # Timed from outside register() rather than inside it, so a third-party
        # module is measured the same way a built-in is (hard rule 6).
        # Work the module asked a registry for, its catalogue, is that kind's
        # share, so it comes off the module's own rather than counting twice.
        var register_began := Time.get_ticks_usec()
        var work_before := SaBootMarks.work_total_usec()
        module.register(scoped)
        var asked := SaBootMarks.work_total_usec() - work_before
        SaBootMarks.module_usec[module_id] = Time.get_ticks_usec() - register_began - asked
        loaded_modules[module_id] = module
        EventBus.module_loaded.emit(String(module_id))


## Unregisters one module and removes everything it put in the registries.
## *layers* are the open documents' layers, which let go of the module's hooks
## on its types. A reload hands them in and shutdown does not.
func unload_module(module_id: StringName, layers: Array = []) -> void:
    var module: SaModule = loaded_modules.get(module_id, null)
    if module == null:
        return
    var scoped: SaContext = module.context
    module.unregister(scoped)
    if scoped != null:
        scoped.remove_all_registrations(layers)
    module.context = null
    loaded_modules.erase(module_id)


## Puts every module down in the reverse of the order it came up, so a module
## leaves before the ones it depends on and can still ask them for anything
## while it goes. `loaded_modules` is filled in dependency
## order, a dependency before its dependents. The context goes too, because it
## holds the registries the modules left, and a suite's held ones answered
## `SaImageFormatRegistry.shared()` with the PNG format unregistered.
func unload_all() -> void:
    var ids: Array = loaded_modules.keys()
    ids.reverse()
    for module_id: StringName in ids:
        unload_module(module_id)
    _context = null


## Modules are unregistered at shutdown, which is also what releases everything
## they registered: descriptors hold tool scripts and shared settings, and the
## loader holds the modules, so leaving them loaded at exit leaks the whole chain.
func _exit_tree() -> void:
    unload_all()
    SaTrail.teardown("the modules are put down")


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        unload_all()


## Puts down every module that did not ship with Sara and reads the user's
## folders again, so a painter writing a module sees the change without a
## restart.
##
## A packaged module is not reloaded, because its files cannot change while
## the build runs. A user module that is loaded is put down first, a refusal
## from the user's folders is forgotten and asked again, and a module added to
## the folder since the start is read in for the first time. The scripts are
## loaded with the resource cache ignored, so an edited `module.gd` and every
## script it preloads is the new text, and the module's kernels are compiled
## again before it registers.
##
## Answers `{"reloaded": [ids], "failed": {id: reason}, "kernels": {id:
## result}}`. A module that fails is left down and filed in `failed_modules`
## with its reason, which the Modules menu draws: Sara is one module short and
## says so, rather than keeping the old code and claiming it reloaded.
func reload_user_modules() -> Dictionary[String, Variant]:
    var record: Dictionary[String, Variant] = {"reloaded": [], "failed": {}, "kernels": {}}
    if _context == null:
        return record
    var holder := SaModuleReload.new(_context)
    # Last registered is put down first, the order `unload_all` keeps.
    var ids: Array = loaded_modules.keys()
    ids.reverse()
    for module_id: StringName in ids:
        if origins.get(module_id, "packaged") == "packaged":
            continue
        holder.put_down(module_id)
        unload_module(module_id, _context.open_layers())
    for module_id: StringName in failed_modules.keys().duplicate():
        if origins.get(module_id, "packaged") != "packaged":
            failed_modules.erase(module_id)
    for module_id: StringName in off_modules.keys().duplicate():
        if origins.get(module_id, "packaged") != "packaged":
            off_modules.erase(module_id)

    var discovered: Dictionary[StringName, SaModule] = {}
    for root: Array in _user_roots():
        var root_path: String = root[0]
        var origin: String = root[1]
        _scan_root(root_path, origin, discovered, true)
    _register_discovered(discovered)
    holder.pick_up()

    var reloaded: Array = record["reloaded"]
    for module_id: StringName in discovered:
        if loaded_modules.has(module_id):
            reloaded.append(module_id)
            record["kernels"][module_id] = kernel_results.get(module_id, {})
    for module_id: StringName in failed_modules:
        if origins.get(module_id, "packaged") != "packaged":
            record["failed"][module_id] = failed_modules[module_id]
    if verbose:
        report()
    return record


## The roots that are not the build's own, as `[path, origin]`: the user's
## folder, then the one `--modules-dir=` named. The same two, in the same
## order, `_discover_modules` scans after the packaged root.
func _user_roots() -> Array:
    var roots: Array = []
    if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(user_modules_root)):
        roots.append([user_modules_root, "user"])
    var named := modules_dir_from_command_line()
    if not named.is_empty() and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(named)):
        roots.append([named, "command line"])
    return roots


func is_loaded(module_id: StringName) -> bool:
    return loaded_modules.has(module_id)


# --- Discovery ----------------------------------------------------------------


## module_id -> SaModule instance.
func _discover_modules() -> Dictionary[StringName, SaModule]:
    var discovered: Dictionary[StringName, SaModule] = {}
    var packaged := packaged_root()
    if DirAccess.dir_exists_absolute(packaged) or DirAccess.open(packaged) != null:
        _scan_root(packaged, "packaged", discovered)
    else:
        push_warning("[ModuleLoader] %s not found." % packaged)
    # The user root is optional and usually absent. Its absence is the empty
    # state the menu shows, not a warning.
    for root: Array in _user_roots():
        var root_path: String = root[0]
        var origin: String = root[1]
        _scan_root(root_path, origin, discovered)
    return discovered


## The packaged root: `res://modules`, or the directory the environment names
## in its place. Not static, for the reason the flag reader below is not.
func packaged_root() -> String:
    var named := OS.get_environment(PACKAGED_ROOT_VARIABLE)
    return MODULES_ROOT if named.is_empty() else named


## The path `--modules-dir=` named, or empty. Reads user arguments only, so it
## cannot collide with one of Godot's own flags.
##
## Not static, although it reads nothing off this node: the loader is an autoload
## and every caller has the instance, and a static reached through an instance is
## a warning `./scripts/check_lsp.sh` fails a run over.
func modules_dir_from_command_line() -> String:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with(MODULES_DIR_FLAG):
            return arg.substr(MODULES_DIR_FLAG.length())
    return ""


## The `module.gd` of every packaged module, in both layouts, read off the
## folders without loading one, so the boot can hand them to a worker thread
## while the welcome window is up. The modules stage then finds
## them loaded, and registering is all it does on the main thread.
func packaged_script_paths() -> PackedStringArray:
    var found := PackedStringArray()
    var root := packaged_root()
    for entry in DirAccess.get_directories_at(root):
        if entry.begins_with("."):
            continue
        var entry_path := root.path_join(entry)
        if _script_exists(entry_path.path_join(MODULE_SCRIPT)):
            found.append(entry_path.path_join(MODULE_SCRIPT))
            continue
        for sub in DirAccess.get_directories_at(entry_path):
            var sub_script := entry_path.path_join(sub).path_join(MODULE_SCRIPT)
            if not sub.begins_with(".") and _script_exists(sub_script):
                found.append(sub_script)
    return found


## The packaged scripts the boot compiles ahead, every one but those of the
## modules [param off_ids] switches off, which the start leaves unread.
func wanted_script_paths(off_ids: Array) -> PackedStringArray:
    return SaSwitchedOff.wanted_scripts(packaged_script_paths(), off_ids)


## Every module under one root, in both layouts, tagged with where it came from.
## *fresh* reads every script from disk again, which only the reload asks for.
func _scan_root(root_path: String, origin: String, discovered: Dictionary[StringName, SaModule], fresh: bool = false) -> void:
    var root := DirAccess.open(root_path)
    if root == null:
        return
    for entry in root.get_directories():
        if entry.begins_with("."):
            continue
        var entry_path := root_path.path_join(entry)

        # A module.gd at the top level means the repository *is* one module,
        # and so does a script there with no module.gd, which registers itself.
        if _script_exists(entry_path.path_join(MODULE_SCRIPT)) or SaModule.FolderRegistration.holds_script(entry_path):
            _instantiate(entry_path, entry, origin, discovered, fresh)
            continue

        # Otherwise each subdirectory holding a module.gd, or a script of its
        # own beside none, is a module, as the base modules' box blur is.
        var nested := DirAccess.open(entry_path)
        if nested == null:
            continue
        var found_any := false
        for sub in nested.get_directories():
            if sub.begins_with("."):
                continue
            var sub_path := entry_path.path_join(sub)
            if _script_exists(sub_path.path_join(MODULE_SCRIPT)) or SaModule.FolderRegistration.holds_script(sub_path):
                _instantiate(sub_path, sub, origin, discovered, fresh)
                found_any = true
        if not found_any:
            _skipped["%s/%s" % [origin, entry]] = "no module.gd"


## Every layout a loaded module ships, as
## `{"<module id>/<layout name>": path}`.
##
## A module may ship layouts, a folder of layout files inside the module, listed
## and forked the same way as the built-in ones. The name carries the module because two
## modules may both ship a `default`, and because a painter reading the list has
## to be able to tell whose a layout is.
##
## Loaded modules only. A module that was refused has a folder on disk and no
## business offering the painter a layout, and a refused module's layouts
## appearing in the menu is how a broken module would still change the app.
##
## Sorted, so the menu's order is the same on every machine rather than whatever
## the filesystem hands back.
func module_layouts() -> Dictionary[String, String]:
    var out: Dictionary[String, String] = {}
    var names: Array[String] = []
    for module_id: StringName in loaded_modules:
        var dir_path := str(module_dirs.get(module_id, ""))
        if dir_path.is_empty():
            continue
        var layouts_path := dir_path.path_join(LAYOUTS_DIR)
        var dir := DirAccess.open(layouts_path)
        if dir == null:
            continue
        for file_name in dir.get_files():
            if not file_name.ends_with(".cfg"):
                continue
            var listed := "%s/%s" % [module_id, file_name.get_basename()]
            out[listed] = layouts_path.path_join(file_name)
            names.append(listed)
    names.sort()
    var sorted: Dictionary[String, String] = {}
    for listed: String in names:
        sorted[listed] = String(out[listed])
    return sorted


## The user root as a path a file manager can open, made if it is missing, so
## the menu entry that opens it always has somewhere to go.
func user_modules_path() -> String:
    var absolute := ProjectSettings.globalize_path(user_modules_root)
    if not DirAccess.dir_exists_absolute(absolute):
        DirAccess.make_dir_recursive_absolute(absolute)
    return absolute


## Exported builds remap .gd to .gdc or add .remap, so all four spellings count.
func _script_exists(path: String) -> bool:
    return (
        ResourceLoader.exists(path)
        or FileAccess.file_exists(path)
        or FileAccess.file_exists(path + ".remap")
        or FileAccess.file_exists(path.replace(".gd", ".gdc"))
    )


## Reads one folder's `module.gd` into *discovered*.
##
## *fresh* reads the folder's scripts from disk again. A bare `load` hands back
## the cached script, and the reload would register the old code. Godot updates
## the one script object in place, so an instance of the old module still alive
## runs the new text as well, which is why the reload puts the module down
## before it reads the folder.
func _instantiate(
    dir_path: String, fallback_id: String, origin: String, discovered: Dictionary[StringName, SaModule], fresh: bool = false
) -> void:
    var script_path := dir_path.path_join(MODULE_SCRIPT)
    # Read before any script of the module is loaded, so a module that fails
    # to load is described too, and a manifest that cannot be taken refuses
    # the module before its code runs.
    var manifest := SaModuleManifest.read(dir_path)
    if not manifest.problem.is_empty():
        _refuse(StringName(fallback_id.replace("-", "_")), origin, dir_path, discovered, fresh, manifest.problem)
        return
    # Asked of the text before any script is loaded, because the load is where
    # the parse error the refusal replaces is printed.
    if origin != "packaged":
        var refusal := _declared_class_name(dir_path)
        if refusal.is_empty():
            refusal = UnwrittenAbstracts.refusal(dir_path)
        if not refusal.is_empty():
            _refuse(StringName(fallback_id), origin, dir_path, discovered, fresh, refusal)
            return
    if fresh:
        _reread_scripts(dir_path, script_path)
    # A module the painter left off is filed by its manifest alone, because
    # compiling its script is most of what it would cost the start.
    if not _script_exists(script_path) or _switched_off.unread(manifest):
        _file_module(SaModule.new(dir_path), manifest, fallback_id, origin, discovered, fresh)
        return
    var script := _load_module_script(script_path, fresh)
    if script == null:
        _refuse(StringName(fallback_id), origin, dir_path, discovered, fresh, "module.gd failed to load")
        return
    # A script that did not parse still loads, and `new()` on it is a script
    # error of its own on top of the parse error the load already printed.
    if not script.can_instantiate():
        var unwritten := UnwrittenAbstracts.refusal(dir_path)
        var reason := unwritten if not unwritten.is_empty() else "module.gd did not parse, the console names the line"
        _refuse(StringName(fallback_id), origin, dir_path, discovered, fresh, reason)
        return

    # A module's script is whatever the module wrote, a `Script` to the type
    # checker, so its constructor is known only at run time.
    @warning_ignore("unsafe_method_access")
    var instance: Variant = script.new()
    if not (instance is SaModule):
        var unwritten := UnwrittenAbstracts.refusal(dir_path)
        var reason := unwritten if not unwritten.is_empty() else "module.gd does not extend SaModule"
        _refuse(StringName(fallback_id), origin, dir_path, discovered, fresh, reason)
        return

    var module: SaModule = instance
    _file_module(module, manifest, fallback_id, origin, discovered, fresh)


## Files *module*, read from the folder of *manifest*, into *discovered* under
## the id its manifest gives, then its function, then the folder's name with a
## hyphen read as an underscore.
func _file_module(
    module: SaModule,
    manifest: SaModuleManifest,
    fallback_id: String,
    origin: String,
    discovered: Dictionary[StringName, SaModule],
    fresh: bool
) -> void:
    var dir_path := manifest.folder
    manifest.complete(module, fallback_id)
    var module_id: StringName = manifest.id
    if not manifest.problem.is_empty():
        _refuse(module_id, origin, dir_path, discovered, fresh, manifest.problem)
        return

    # Asked before the origin is written, or the winner of the clash would be
    # filed as coming from the loser's folder. On a reload a loaded module
    # counts too, because the packaged modules stay up and are not in
    # *discovered*, and a user module taking one's id is the clash the boot
    # refuses.
    if _is_taken(module_id, discovered, fresh):
        _refuse(module_id, origin, dir_path, discovered, fresh, "duplicate module id, another folder already provides it")
        return
    origins[module_id] = origin
    module_dirs[module_id] = dir_path
    manifests[module_id] = manifest
    discovered[module_id] = module


## The manifest of *module_id*, or null for an id no module has. The skeleton's
## own module, put in [member loaded_modules] before discovery, has its manifest
## made from its functions each time it is asked for.
func manifest_of(module_id: StringName) -> SaModuleManifest:
    return _manifest_in(module_id, {})


## The manifest of *module_id* among *discovered* and the loaded modules, read
## from its folder at discovery, or made from the functions of a module that
## came in some other way, never kept, so a module filed by hand is asked again.
func _manifest_in(module_id: StringName, discovered: Dictionary[StringName, SaModule]) -> SaModuleManifest:
    if manifests.has(module_id):
        return manifests[module_id]
    var module: SaModule = discovered.get(module_id, loaded_modules.get(module_id, null))
    return null if module == null else SaModuleManifest.of_module(module)


## The folder's script, taken from the threaded request the boot made for it
## when one stands. The boot asks a worker for every packaged module's script
## while the welcome window draws, and a request holds a token until
## `load_threaded_get` collects it. A bare `load` hands back the same script but
## leaves the token, and each of the five was an object leaked at exit.
## Collecting it waits for the worker, as a bare `load` of a path it is loading
## would. A failed request is collected as well and the script loaded here.
func _load_module_script(script_path: String, fresh: bool) -> Script:
    if not fresh and ResourceLoader.load_threaded_get_status(script_path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
        var requested := ResourceLoader.load_threaded_get(script_path) as Script
        if requested != null:
            return requested
    var cache_mode := ResourceLoader.CACHE_MODE_IGNORE if fresh else ResourceLoader.CACHE_MODE_REUSE
    return ResourceLoader.load(script_path, "", cache_mode) as Script


## Whether *module_id* already belongs to a module: one read earlier in this
## scan, or on a reload one that stayed up, which a packaged module always does.
func _is_taken(module_id: StringName, discovered: Dictionary[StringName, SaModule], fresh: bool) -> bool:
    return discovered.has(module_id) or (fresh and loaded_modules.has(module_id))


## Files a folder that did not load, with its origin and its folder, under its
## own id or, when a module that won already holds that id, under a key of its
## own. Writing the refusal under the winner's id would mark the winner as
## failed, and writing its origin and folder there is what once filed a packaged
## module as the user's, compiled the refused copy's kernels and let the reload
## put the packaged module down.
func _refuse(
    module_id: StringName,
    origin: String,
    dir_path: String,
    discovered: Dictionary[StringName, SaModule],
    fresh: bool,
    reason: String
) -> void:
    var key := module_id
    if _is_taken(module_id, discovered, fresh):
        key = StringName("%s (%s)" % [module_id, origin])
    origins[key] = origin
    module_dirs[key] = dir_path
    _fail(key, reason)


## The refusal for a folder whose scripts declare a `class_name`, or empty.
##
## A script outside `res://` never enters the global class cache, so a name
## there either reaches the build's own class of that name, which is how a copy
## of the kaleidoscope with its id changed built the shipped filter, or hides it
## and fails to parse at the reload. The module reaches its scripts by `preload`
## instead, and the sentence says so in the Modules menu.
func _declared_class_name(dir_path: String) -> String:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return ""
    for sub in dir.get_directories():
        if not sub.begins_with("."):
            var found := _declared_class_name(dir_path.path_join(sub))
            if not found.is_empty():
                return found
    for file_name in dir.get_files():
        if file_name.get_extension() != "gd":
            continue
        for line in FileAccess.get_file_as_string(dir_path.path_join(file_name)).split("\n"):
            if line.begins_with("class_name "):
                return (
                    "%s declares class_name %s, reach it from module.gd by preload of its path instead"
                    % [file_name, line.trim_prefix("class_name ").get_slice(" ", 0).strip_edges()]
                )
    return ""


## Reads every script a module holds loaded from disk again, `module.gd`
## aside, which the caller reads last.
##
## Each one separately, because the cache mode that claims to be deep is not
## for a script: measured on 4.7, `CACHE_MODE_IGNORE_DEEP` on a `module.gd`
## rereads that file and leaves the tool or the docker it preloads as the
## cache had it, so an edit to the module's tool would reload as the old tool.
## Updated in place, a preloaded script is the object the module's constant
## already holds, so the module sees the new text. Nothing outside the folder is
## reread, a skeleton script a module preloads least of all.
##
## Only a script the cache holds, which is what a start read: `module.gd` and
## whatever it reaches by `preload` or `load`. A script nothing reaches, a
## module's own test with a base class from `res://tests/` above all, was never
## parsed by the start, and parsing it here would log an error for each one that
## the next start does not. One that a module has added since the start and
## preloads is not in the cache either, and the `preload` reads it from disk
## when `module.gd` is loaded, so it is no less new.
func _reread_scripts(dir_path: String, script_path: String) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    for sub in dir.get_directories():
        if not sub.begins_with("."):
            _reread_scripts(dir_path.path_join(sub), script_path)
    for file_name in dir.get_files():
        var file_path := dir_path.path_join(file_name)
        if file_name.get_extension() == "gd" and file_path != script_path and ResourceLoader.has_cached(file_path):
            ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_IGNORE)


## A refusal is always recorded. It is only *announced* when verbose. The test
## that proves a dependency cycle is refused would otherwise print an engine
## error and a backtrace into the middle of the test transcript, and
## run_tests.sh treats a stray error as a failed run.
func _fail(module_id: StringName, reason: String) -> void:
    failed_modules[module_id] = reason
    if verbose:
        push_error("[ModuleLoader] '%s' refused: %s" % [module_id, reason])


# --- Ordering -----------------------------------------------------------------


## A dependency is satisfied only when it actually registered, which is not the
## same as having been found.
##
## Checking `discovered` alone had two holes. A module refused for needing a
## newer API stayed in `discovered`, so its dependents registered against
## something that was never there. And a cycle refuses only the member the walk
## re-entered, leaving the other one ordered and registering against the refused
## one. Both produced a module running with a dependency that does not exist,
## which surfaces far from the cause.
##
## The third hole was the opposite: the skeleton's own built-in is put straight
## into `loaded_modules` before discovery, so it never appears in `discovered`
## and anything depending on it was refused as missing.
##
## Registration walks the topological order, so every dependency has already
## been decided by the time this is asked about a dependent - except inside a
## cycle, which is exactly the case that must fail.
##
## A dependency that registered at a version older than the manifest asks for
## is unsatisfied too, and the line names both versions.
func _unsatisfied_dependencies(module_id: StringName, discovered: Dictionary[StringName, SaModule]) -> Array[String]:
    var manifest := _manifest_in(module_id, discovered)
    var unsatisfied: Array[String] = []
    for dep in manifest.dependency_ids():
        var dep_id := StringName(dep)
        if loaded_modules.has(dep_id):
            var too_old := manifest.too_old(dep, manifest_of(dep_id).version)
            if not too_old.is_empty():
                unsatisfied.append(too_old)
            continue
        if discovered.has(dep_id):
            unsatisfied.append("%s (refused)" % dep)
        else:
            unsatisfied.append("%s (not found)" % dep)
    return unsatisfied


## Topological sort. A cycle refuses the modules involved rather than pushing an
## error and carrying on into an order nothing defines.
func _resolve_dependencies(discovered: Dictionary[StringName, SaModule]) -> Array[StringName]:
    var ordered: Array[StringName] = []
    var visited: Dictionary[StringName, bool] = {}
    var visiting: Dictionary[StringName, bool] = {}
    for module_id: StringName in discovered:
        _visit(module_id, discovered, visited, visiting, ordered)
    return ordered


func _visit(
    module_id: StringName,
    discovered: Dictionary[StringName, SaModule],
    visited: Dictionary[StringName, bool],
    visiting: Dictionary[StringName, bool],
    ordered: Array[StringName]
) -> void:
    if visited.has(module_id):
        return
    if visiting.has(module_id):
        _fail(module_id, "cyclic dependency")
        return

    visiting[module_id] = true
    var manifest: SaModuleManifest = _manifest_in(module_id, discovered) if discovered.has(module_id) else null
    if manifest != null:
        for dep in manifest.dependency_ids():
            var dep_id := StringName(dep)
            if discovered.has(dep_id):
                _visit(dep_id, discovered, visited, visiting, ordered)
    visiting.erase(module_id)
    visited[module_id] = true

    # A module refused for a cycle must not also be ordered for registration.
    if not failed_modules.has(module_id):
        ordered.append(module_id)


## One line per module: what loaded, what was refused and why, what was empty.
##
## The same information the loader has, rather than a checkmark for
## everything whatever the outcome.
func report() -> void:
    SaConsole.section("MODULES")
    for module_id: StringName in loaded_modules:
        SaConsole.item(
            "✓",
            SaConsole.OK,
            String(module_id),
            "%s, %s" % [manifest_of(module_id).version_and_commit(), origins.get(module_id, "packaged")]
        )
    for module_id: StringName in failed_modules:
        SaConsole.item(
            "✗", SaConsole.ERR, String(module_id), "%s, %s" % [failed_modules[module_id], origins.get(module_id, "packaged")]
        )
    for module: String in missing_libraries:
        SaConsole.item("✗", SaConsole.ERR, module, "no library, %s" % missing_libraries[module])
    for module_id: StringName in off_modules:
        SaConsole.item("○", SaConsole.DIM, String(module_id), off_modules[module_id], 26, SaConsole.DIM)
    for entry: String in _skipped:
        SaConsole.item("·", SaConsole.DIM, entry, _skipped[entry], 26, SaConsole.DIM)
    SaConsole.blank()


# --- Abstract methods ---------------------------------------------------------


## The abstract methods a module's scripts leave unwritten, as the loader's
## refusal.
##
## A script that extends an `@abstract` class and does not write one of its
## abstract methods fails to parse, and so does the `module.gd` that preloads
## it, with the engine's line in the console and a `module.gd` that still
## instantiates as a bare object. The loader reads the folder's text instead, so
## the Modules menu names the file, the class and the method at the start
## rather than at the first run.
class UnwrittenAbstracts:
    ## The refusal for *dir_path*, or empty when every script writes every
    ## abstract method it inherits.
    static func refusal(dir_path: String) -> String:
        var dir := DirAccess.open(dir_path)
        if dir == null:
            return ""
        for sub in dir.get_directories():
            if not sub.begins_with("."):
                var found := refusal(dir_path.path_join(sub))
                if not found.is_empty():
                    return found
        for file_name in dir.get_files():
            if file_name.get_extension() != "gd":
                continue
            var text := FileAccess.get_file_as_string(dir_path.path_join(file_name))
            var found := _of_text(text, dir_path)
            if not found.is_empty():
                return "%s does not write %s, which %s declares @abstract" % [file_name, found[1], found[0]]
        return ""

    ## The base's name and the first abstract method *text* leaves unwritten,
    ## or an empty array.
    static func _of_text(text: String, dir_path: String) -> PackedStringArray:
        var extends_line := RegEx.create_from_string("(?m)^extends\\s+(\\S+)").search(text)
        if extends_line == null or text.contains("@abstract"):
            return PackedStringArray()
        var named := extends_line.get_string(1)
        var base := _base_script(named, dir_path)
        if base == null or not base.is_abstract():
            return PackedStringArray()
        for method: String in _abstract_methods(base):
            if RegEx.create_from_string("(?m)^func\\s+%s\\s*\\(" % method).search(text) == null:
                var base_name := String(base.get_global_name())
                return PackedStringArray([base_name if not base_name.is_empty() else named, "%s()" % method])
        return PackedStringArray()

    ## The script *named* reaches, a global class or a quoted path, or null for
    ## an engine class.
    static func _base_script(named: String, dir_path: String) -> Script:
        if named.begins_with('"'):
            var path := named.trim_prefix('"').trim_suffix('"')
            if path.is_relative_path():
                path = dir_path.path_join(path)
            return load(path) as Script if ResourceLoader.exists(path) else null
        for entry: Dictionary in ProjectSettings.get_global_class_list():
            if str(entry["class"]) == named:
                return load(str(entry["path"])) as Script
        return null

    ## The methods *base* leaves abstract. The list names a method once per
    ## class of the chain that writes it, and one written without the flag
    ## anywhere below the abstract declaration is not abstract any more.
    static func _abstract_methods(base: Script) -> PackedStringArray:
        var abstract: PackedStringArray = []
        var written: PackedStringArray = []
        for method: Dictionary in base.get_script_method_list():
            var method_name := str(method["name"])
            var flags: int = method["flags"]
            if flags & METHOD_FLAG_VIRTUAL_REQUIRED:
                abstract.append(method_name)
            else:
                written.append(method_name)
        var left: PackedStringArray = []
        for method_name in abstract:
            if not written.has(method_name) and not left.has(method_name):
                left.append(method_name)
        return left
