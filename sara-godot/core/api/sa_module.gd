## Base class for every feature module.
##
## Modules register tools, blend modes, commands and UI through SaContext. The
## skeleton's own built-ins go through the same path (core/loader/skeleton_module.gd),
## so an API gap shows up as a broken built-in rather than as a bug report.
##
## A `manifest.cfg` beside the module's scripts says what the module is before
## any of its code runs, and its keys win over the functions below
## (`SaModuleManifest`). A module with no manifest is described by them alone.
##
## A module that leaves `register()` as it is here, or a folder with no
## `module.gd` at all, has every script in its folder that the door registers
## made and registered for it, as Blender's `auto_load` does for an add-on. A
## filter, a tool, a blend mode, a command, a layer type, a view transform, a
## pen source, an image format or an input source each extend their class and
## need nothing else. A module that overrides `register()` registers by hand,
## in the order and under the conditions it writes.
class_name SaModule extends RefCounted

## Set by ModuleLoader before register(): the module's own context view, so
## unregister() can find it without the module storing one.
var context: SaContext = null

## Set by ModuleLoader before register(), as *context* is, or made with: the
## folder the module was read from, whose scripts the default `register()`
## walks. Named so a module's own `folder` stays its own.
var own_folder: String = ""


## *made_of* is for the loader, which makes a folder with no `module.gd` as a
## bare module of that folder. A `module.gd` never passes it.
func _init(made_of: String = "") -> void:
    own_folder = made_of


## Stable identity, used for registration attribution and dependencies.
## Defaults to the folder name, a hyphen in it read as an underscore, so the
## folder `box-blur` is the module `box_blur`. Override only for a good reason.
func get_id() -> StringName:
    return StringName(own_folder.trim_suffix("/").get_file().replace("-", "_"))


## Human-readable name, drawn over the module's group in every menu that sorts
## its rows by who registered them, and in the Modules menu's own list.
##
## Read off the id rather than fixed. The smallest module is `get_id()` and
## `register()` and nothing else, so this default is what a student's first
## module is called, and a fixed **Unnamed Module** over the one row they went
## looking for would read as a broken install. A name derived from what the module
## did declare reads as a module nobody has renamed yet, which is true, rather
## than as a broken install.
##
## The id and not the folder, of the two candidates. The id is the word its
## author chose, `box_blur`, where the folder is only where the files happen to
## sit, and a module with no id of its own takes its folder's name as its id.
##
## Title case rather than sentence case, because a derived name lands in the
## same list as the two written by hand, "Sara Skeleton" and "Sara Base Tools",
## and one lowercase row among them reads as the odd one out. Hyphens go the
## way `capitalize()` already takes underscores, so a folder-shaped id such as
## `sara-base-modules` reads as words too.
##
## A module that declares no id and was made of no folder answers a fixed name,
## having nothing to derive one from.
func get_name() -> String:
    var id := String(get_id())
    return "Unnamed Module" if id.is_empty() else id.replace("-", " ").capitalize()


## The module's semantic version. A module whose folder holds a `manifest.cfg`
## writes its version there, where a release moves it, and the manifest wins
## over this function (`SaModuleManifest`). Without either a
## module is "0.0.0".
func get_version() -> String:
    return SaModuleManifest.NO_VERSION


## The SaContext.API_VERSION this module was written against, the `sara_api` of
## a manifest, which wins where it is written. The loader refuses
## a module that needs a newer API than the skeleton provides, which turns a
## confusing runtime failure into one clear message.
func get_api_version() -> int:
    return SaContext.API_VERSION


## Module ids that must be registered before this one. A manifest's
## `[dependencies]` section wins over this list and can name the oldest
## version of each that will do.
func get_dependencies() -> PackedStringArray:
    return []


## Register everything this module provides. Called once at startup.
##
## Left as it is, every script under *own_folder* that extends a class the door
## registers is made with no arguments and registered, in the order of its
## path. A `tests` folder is not read, nor is a script that is abstract or whose
## constructor asks for an argument, which is a helper the module makes itself.
func register(ctx: SaContext) -> void:
    FolderRegistration.register_folder(ctx, own_folder)


## Undo register(). The loader already removes registry entries this module made,
## so override only for extra teardown (disconnecting signals, freeing GPU
## resources).
func unregister(_ctx: SaContext) -> void:
    pass


## Ends Sara with *code* as its exit code, *why* opening the quit's trail. For a
## module that runs Sara for one job and ends it, a lesson filmed for a video,
## and never for a painter's quit, which asks about unsaved work first. It goes
## through `SaTrail.hand_over` as every quit of Sara's does, which wakes the
## Wayland driver's join at the engine's teardown: a bare `quit()` on a nested
## weston hung there about one run in six.
static func quit_sara(code: int, why: String) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return
    tree.quit(code)
    SaTrail.hand_over(tree, why)


## The default `register()`: what a module's folder holds, registered by the
## class each script extends.
class FolderRegistration:
    ## The folder a module's own test sits in, never read, because a test's base
    ## class comes from `res://tests/` and a build ships without it.
    const TESTS := "tests"

    ## Registers every script under *dir_path* that the door takes.
    static func register_folder(ctx: SaContext, dir_path: String) -> void:
        if dir_path.is_empty():
            return
        for path: String in scripts(dir_path):
            var script := load(path) as Script
            if script != null and registrable(script):
                # The script is whatever the module wrote, so its constructor is
                # known only at run time, as the loader's `module.gd` is.
                @warning_ignore("unsafe_method_access")
                var made: Object = script.new()
                register_made(ctx, made)

    ## Whether *dir_path* holds a script at its top, the mark of a module
    ## written with no `module.gd`, which the loader reads as one.
    static func holds_script(dir_path: String) -> bool:
        for file_name in DirAccess.get_files_at(dir_path):
            if file_name.trim_suffix(".remap").get_extension() in ["gd", "gdc"]:
                return true
        return false

    ## Every script under *dir_path* but `module.gd`, sorted, so the order is
    ## the same on every machine. An exported build lists `x.gd.remap` or
    ## `x.gdc` for `x.gd`, and both are read as the `x.gd` that `load` takes.
    static func scripts(dir_path: String) -> PackedStringArray:
        var found: PackedStringArray = []
        _walk(dir_path, dir_path, found)
        found.sort()
        return found

    static func _walk(dir_path: String, top: String, found: PackedStringArray) -> void:
        var dir := DirAccess.open(dir_path)
        if dir == null:
            return
        for sub in dir.get_directories():
            if not sub.begins_with(".") and sub != TESTS:
                _walk(dir_path.path_join(sub), top, found)
        for file_name in dir.get_files():
            var named := file_name.trim_suffix(".remap")
            if named.get_extension() == "gdc":
                named = named.get_basename() + ".gd"
            if named.get_extension() != "gd" or (dir_path == top and named == "module.gd"):
                continue
            var path := dir_path.path_join(named)
            if not found.has(path):
                found.append(path)

    ## Whether *script* extends a class the door registers and can be made with
    ## no arguments.
    static func registrable(script: Script) -> bool:
        if not script.can_instantiate() or script.is_abstract() or _asks_arguments(script):
            return false
        var base := script.get_base_script()
        while base != null:
            if kinds().has(base):
                return true
            base = base.get_base_script()
        return false

    ## The classes the door registers an instance of, each with a call of its
    ## own in *register_made*.
    static func kinds() -> Array[Script]:
        return [
            SaFilter,
            SaToolDescriptor,
            SaBlendModeDescriptor,
            SaCommandDescriptor,
            SaLayerTypeDescriptor,
            SaViewTransformDescriptor,
            SaPenSource,
            SaImageFormat,
            SaInputSource,
        ]

    static func _asks_arguments(script: Script) -> bool:
        for method: Dictionary in script.get_script_method_list():
            if str(method["name"]) == "_init":
                var args: Array = method["args"]
                var defaults: Array = method["default_args"]
                return args.size() > defaults.size()
        return false

    static func register_made(ctx: SaContext, made: Object) -> void:
        if made is SaFilter:
            ctx.register_filter(made as SaFilter)
        elif made is SaToolDescriptor:
            ctx.register_tool(made as SaToolDescriptor)
        elif made is SaBlendModeDescriptor:
            ctx.register_blend_mode(made as SaBlendModeDescriptor)
        elif made is SaCommandDescriptor:
            ctx.register_command(made as SaCommandDescriptor)
        elif made is SaLayerTypeDescriptor:
            ctx.register_layer_type(made as SaLayerTypeDescriptor)
        elif made is SaViewTransformDescriptor:
            ctx.register_view_transform(made as SaViewTransformDescriptor)
        elif made is SaPenSource:
            ctx.register_pen_source(made as SaPenSource)
        elif made is SaImageFormat:
            ctx.register_image_format(made as SaImageFormat)
        elif made is SaInputSource:
            ctx.register_input_source(made as SaInputSource)
