## A module may ship layouts, listed and forked the same way.
##
## A module may ship layouts, a folder of layout files inside the module,
## listed and forked the same way, which is where a module's own layout such as
## `photo_editing` comes from.
##
## Three claims. The loader finds a `layouts/` folder beside a module's script
## and names what is in it after the module. The presets class lists those with
## the four the skeleton ships, ahead of the painter's own. And an edit under one
## forks, because a module's folder is as read-only as `res://layouts` is.
##
## `scenarios/module-ships-layouts.json` drives the real app with the fixture
## module under `tests/fixtures/modules`, reached by `--modules-dir=`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## Where the fixture module the scenario uses lives. Staged under `user://` here
## instead, because a suite that pointed the loader at `res://` would be reading
## the same folder the scenario does and neither would be proving the discovery.
static var scratch_user_root: String = SaDataRoot.path("test_l2_modules")

const LAYOUT_MODULE := """extends SaModule


func get_id() -> StringName:
    return &"l2-fixture"


func get_name() -> String:
    return "L2 Fixture"


func register(_ctx: SaContext) -> void:
    pass
"""

const ONE_LAYOUT := """[_layout_meta_]

os_scale=1.0
preset="l2-fixture/desk"

[ToolBoxDocker]

position=Vector2i(4, 96)
size=Vector2i(60, 400)
visible=true
"""


func after_each() -> void:
    ModuleLoader.unload_all()
    ModuleLoader.user_modules_root = SaDataRoot.path(ModuleLoader.USER_MODULES_FOLDER)
    _remove_user_root()


func _stage(folder: String, layouts: Dictionary) -> void:
    var dir := scratch_user_root.path_join(folder)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
    var script := FileAccess.open(dir.path_join("module.gd"), FileAccess.WRITE)
    script.store_string(LAYOUT_MODULE)
    script.close()
    if layouts.is_empty():
        return
    var layouts_dir := dir.path_join(ModuleLoader.LAYOUTS_DIR)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(layouts_dir))
    for file_name: String in layouts:
        var file := FileAccess.open(layouts_dir.path_join(file_name), FileAccess.WRITE)
        file.store_string(String(layouts[file_name]))
        file.close()


func _remove_user_root() -> void:
    var absolute := ProjectSettings.globalize_path(scratch_user_root)
    if not DirAccess.dir_exists_absolute(absolute):
        return
    for folder in DirAccess.get_directories_at(absolute):
        var module_dir := absolute.path_join(folder)
        var layouts_dir := module_dir.path_join(ModuleLoader.LAYOUTS_DIR)
        if DirAccess.dir_exists_absolute(layouts_dir):
            for file_name in DirAccess.get_files_at(layouts_dir):
                DirAccess.remove_absolute(layouts_dir.path_join(file_name))
            DirAccess.remove_absolute(layouts_dir)
        for file_name in DirAccess.get_files_at(module_dir):
            DirAccess.remove_absolute(module_dir.path_join(file_name))
        DirAccess.remove_absolute(module_dir)
    DirAccess.remove_absolute(absolute)


func _load(folder: String, layouts: Dictionary) -> void:
    _stage(folder, layouts)
    ModuleLoader.user_modules_root = scratch_user_root
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    ModuleLoader.verbose = false
    ModuleLoader.load_and_register_modules(registries.context)
    ModuleLoader.verbose = true


func test_the_loader_writes_down_where_each_module_came_from() -> void:
    _load("desk-module", {})
    assert_true(ModuleLoader.is_loaded(&"l2-fixture"), "The fixture module loaded")
    assert_eq(
        String(ModuleLoader.module_dirs.get(&"l2-fixture", "")),
        scratch_user_root.path_join("desk-module"),
        "and the loader recorded the folder it was read from, which the loader did not always do"
    )
    assert_false(String(ModuleLoader.module_dirs.get(&"sara-base-modules", "")).is_empty(), "for a packaged module too")


func test_a_layouts_folder_is_listed_under_the_modules_name() -> void:
    _load("desk-module", {"desk.cfg": ONE_LAYOUT})
    var listed := ModuleLoader.module_layouts()
    assert_true(listed.has("l2-fixture/desk"), "Named for the module and the file: %s" % listed.keys())
    assert_true(String(listed["l2-fixture/desk"]).ends_with("layouts/desk.cfg"), "pointing at the file itself")


func test_a_module_with_no_layouts_folder_offers_none() -> void:
    _load("desk-module", {})
    assert_false(ModuleLoader.module_layouts().has("l2-fixture/desk"), "Nothing to offer and nothing offered")


## Only `.cfg`. A module's `layouts/` folder is a folder like any other and a
## README or a screenshot in it must not become a row in the menu.
func test_only_layout_files_are_listed() -> void:
    _load("desk-module", {"desk.cfg": ONE_LAYOUT, "README.md": "not a layout"})
    var listed := ModuleLoader.module_layouts()
    assert_true(listed.has("l2-fixture/desk"), "The layout is listed")
    assert_false(listed.has("l2-fixture/README"), "and the readme beside it is not")


## The command-line root the scenario reaches its fixture through, which is the
## only door that lets one capture carry a module no ordinary launch sees.
func test_the_modules_dir_flag_is_read_out_of_the_user_arguments() -> void:
    assert_eq(ModuleLoader.MODULES_DIR_FLAG, "--modules-dir=", "The flag the scenario writes")
    # Nothing named it on this run, so the seam answers empty rather than
    # guessing at a path.
    assert_eq(ModuleLoader.modules_dir_from_command_line(), "", "and no run of the suite names one")


## The fork, which is the half of "listed and forked the same way" that has a
## name in it. A module's layout is read-only, so an edit under one has to fork,
## and the forked name has to be a name the list can hold.
func test_a_module_layout_forks_under_a_name_the_list_can_hold() -> void:
    _load("desk-module", {"desk.cfg": ONE_LAYOUT})
    var store := DockerLayoutStore.new()
    var presets := SaDockerLayoutPresets.new(store.path)

    assert_true(presets.is_shipped("l2-fixture/desk"), "A module's layout is read-only, like the four that ship")
    assert_true(presets.list().has("l2-fixture/desk"), "and it is on the one list the menu reads")
    var forked := presets.target_name("l2-fixture/desk")
    assert_eq(forked, forked.validate_filename(), "The fork is already a legal file name, so nothing renames it later")
    assert_true(forked.ends_with(SaDockerLayoutPresets.FORK_SUFFIX), "and the suffix is what says it is a fork")
    assert_false(forked.contains("/"), "with the slash gone, or the list and `current` would disagree")

    assert_eq(presets.target_name("mine"), "mine", "A painter's own name still saves under itself")
    assert_eq(presets.target_name("default"), "default (custom)", "and the four that ship fork as they always did")

    store.free()


## The four the skeleton ships come first, then the modules', then the painter's.
func test_the_modules_layouts_sit_between_the_shipped_and_the_painters() -> void:
    _load("desk-module", {"desk.cfg": ONE_LAYOUT})
    var store := DockerLayoutStore.new()
    var presets := SaDockerLayoutPresets.new(store.path)
    var listed := presets.list()

    var at := listed.find("l2-fixture/desk")
    assert_true(at >= SaDockerLayoutPresets.SHIPPED.size(), "After the four that ship")
    for i in SaDockerLayoutPresets.SHIPPED.size():
        assert_true(listed.find(SaDockerLayoutPresets.SHIPPED[i]) < at, "which lead the list as they did")

    store.free()
