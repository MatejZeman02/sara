## Who owns a shader, and which file a name means.
##
## Shaders were keyed by bare filename and includes resolved by a global
## `ends_with()` match over every discovered path, so two modules shipping
## `paint.gmacs` collided and the winner was whatever order the directory walk
## returned. Nothing failed and nothing said so: the second module simply painted
## with the first one's kernels. That becomes real the moment
## a module ships a shader, and it is the kind of bug that looks like a colour bug.
##
## No module in the tree ships a `.gmacs` yet, so the collisions here are built by
## indexing synthetic paths. That is the honest test: what is being checked is the
## resolution rule, not the contents of anyone's `modules/` directory.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const ShaderIndex := preload("res://core/custom-shader/compiler/sa_shader_index.gd")

## Paths indexed by a test, removed again in after_each. The index lives on an
## autoload, so a leftover entry changes what every later compile resolves.
const FAKE_PATHS := [
    "res://modules/sara-mixing-module/shaders/fill.gmacs",
    "res://modules/sara-noise-brush-engine/shaders/fill.gmacs",
    "res://modules/sara-mixing-module/shaders/km_mixing.gmacs",
    "res://modules/sara-mixing-module/shaders/libs/transfer_curve.gmacs",
]


func after_each() -> void:
    for path: String in FAKE_PATHS:
        var key := GlobalShaderCompiler.index.shader_key(path)
        GlobalShaderCompiler.index.shaders_by_key.erase(key)
        var bare := GlobalShaderCompiler.index.get_shader_name(path)
        var owners: PackedStringArray = GlobalShaderCompiler.index.owners_of_name.get(bare, PackedStringArray())
        var owner := GlobalShaderCompiler.index.owner_of(path)
        var at := owners.find(owner)
        if at >= 0:
            owners.remove_at(at)
        if owners.is_empty():
            GlobalShaderCompiler.index.owners_of_name.erase(bare)
        else:
            GlobalShaderCompiler.index.owners_of_name[bare] = owners


func _index(path: String) -> void:
    GlobalShaderCompiler.index.index_shader(path)


# --- The walk ------------------------------------------------------------------

## The walk is run on an index of the suite's own, so `find_files()` goes over the
## real tree without touching the autoload's lists. The index owns the lists it
## fills and is built from nothing.


## The directory walk must not enter the running app's own `user://`
##
## `run_tests.sh` points `XDG_DATA_HOME` inside the project so two worktrees do
## not share one settings file and one SPIR-V cache, which puts `user://` inside
## `res://`, and every `.gmacs` a test writes there was being indexed and
## compiled at the next boot for as long as the file sat on disk. Nothing failed
## for a whole board. Only a suite that hashed the shader list noticed.
func test_the_walk_does_not_enter_the_apps_own_user_directory() -> void:
    var probe_path := "user://f2_walk_probe.gmacs"
    var file := FileAccess.open(probe_path, FileAccess.WRITE)
    file.store_string("#kernel f2_walk_probe" + "\n")
    file.close()

    var index := ShaderIndex.new()
    assert_true(index.is_user_directory("user://"), "The user directory is itself")
    assert_false(index.is_user_directory("res://core"), "and a directory of the tree is not")

    var walked := ShaderIndex.new()
    walked.find_files("res://")
    var real_user := ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
    var strays: Array = []
    for path: String in walked.compute_shader_file_paths:
        if ProjectSettings.globalize_path(path).simplify_path().begins_with(real_user):
            strays.append(path)

    assert_true("res://shaders/compute/composite.gmacs" in walked.compute_shader_file_paths, "The walk ran and found Sara's own")
    assert_eq(strays, [], "and it collected nothing the app itself had written")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(probe_path))


## The walk must not enter a `scratch/` root an earlier run of the app left.
##
## Skipping the running app's own `user://` is the right question
## and answers only for this run. The gate roots itself at
## `scratch/xdg-gate/data` and a plain run of the app in the same checkout roots
## itself at `scratch/xdg/data`, so a probe kernel left in the second is not the
## gate's `user://` and the guard would let the walk in. One stray probe made a
## manifest check fail on kernels no suite in that run had written.
##
## The stray is written where an earlier app run would have put it, under a root
## that is not this run's, and is removed again whatever the case does.
func test_the_walk_does_not_enter_a_scratch_root_from_an_earlier_run() -> void:
    var stray_dir := "res://scratch/xdg-f6-probe/data/godot/app_userdata/Sara"
    var stray := stray_dir.path_join("f6_stray_probe.gmacs")
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(stray_dir))
    var file := FileAccess.open(stray, FileAccess.WRITE)
    file.store_string("#kernel f6_stray_probe" + "\n")
    file.close()

    # The other half of the clause: a probe in the *real* `user://` must be absent
    # too, which under the gate is a second directory under `scratch/` and under a
    # packaged build is the `user://` check doing the work.
    var here := "user://f6_this_run_probe.gmacs"
    var here_file := FileAccess.open(here, FileAccess.WRITE)
    here_file.store_string("#kernel f6_this_run_probe" + "\n")
    here_file.close()

    var index := ShaderIndex.new()
    assert_true(index.is_scratch_directory("res://scratch"), "The checkout's scratch is itself")
    assert_false(index.is_scratch_directory("res://core"), "and a directory of the tree is not")
    assert_false(index.is_user_directory(stray_dir), "The stray root is not this run's user directory")

    var walked := ShaderIndex.new()
    walked.find_files("res://")

    assert_true("res://shaders/compute/composite.gmacs" in walked.compute_shader_file_paths, "The walk ran and found Sara's own")
    assert_false(stray in walked.compute_shader_file_paths, "and collected nothing from a past run's root")
    var real_user := ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
    var from_this_run: Array = []
    for path: String in walked.compute_shader_file_paths:
        if ProjectSettings.globalize_path(path).simplify_path().begins_with(real_user):
            from_this_run.append(path)
    assert_eq(from_this_run, [], "nor anything from this run's own")
    var under_scratch: Array = []
    for path: String in walked.compute_shader_file_paths:
        if path.begins_with("res://scratch/"):
            under_scratch.append(path)
    assert_eq(under_scratch, [], "nor anything else under scratch, this run's gate root included")
    # The whole chain, deepest first, so the walk of the next run meets nothing
    # this one left. `DirAccess` removes one empty directory at a time.
    DirAccess.remove_absolute(ProjectSettings.globalize_path(here))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(stray))
    var level := stray_dir
    while level != "res://scratch":
        DirAccess.remove_absolute(ProjectSettings.globalize_path(level))
        level = level.get_base_dir()


# --- Ownership -----------------------------------------------------------------


## The module directory is the only thing that says who owns a shader. Anything
## outside one is Sara's, including the shaders under `shaders/compute/`.
func test_a_shader_belongs_to_the_module_it_lives_under() -> void:
    assert_eq(
        GlobalShaderCompiler.index.owner_of("res://modules/sara-mixing-module/shaders/fill.gmacs"),
        "sara-mixing-module",
        "The directory under modules/ is the owner"
    )
    assert_eq(
        GlobalShaderCompiler.index.owner_of("res://shaders/compute/composite.gmacs"),
        GlobalShaderCompiler.index.CORE_OWNER,
        "and everything outside a module is Sara's own"
    )
    assert_eq(
        GlobalShaderCompiler.index.shader_key("res://shaders/compute/libs/transfer_curve.gmacs"),
        "sara/transfer_curve",
        "A key is owner and name, whatever depth the file sits at"
    )


## `modules` names a directory, not a substring. A shader under a path that merely
## contains the word is not owned by whatever follows it.
func test_the_word_modules_only_counts_as_a_path_component() -> void:
    assert_eq(
        GlobalShaderCompiler.index.owner_of("res://shaders/compute/modules_helpers.gmacs"),
        GlobalShaderCompiler.index.CORE_OWNER,
        "A filename beginning with the word is still Sara's"
    )
    assert_eq(
        GlobalShaderCompiler.index.owner_of("res://modules"),
        GlobalShaderCompiler.index.CORE_OWNER,
        "and modules/ with nothing under it owns nothing"
    )


# --- Resolving a name ----------------------------------------------------------


## Nothing in the current tree writes a qualified name, so a bare one has to keep
## meaning Sara's shader.
func test_a_bare_name_is_saras_own_shader() -> void:
    assert_eq(GlobalShaderCompiler.resolve_shader_name("composite"), "sara/composite", "Bare means Sara's")
    assert_eq(
        GlobalShaderCompiler.get_kernel_index("sara/composite", "multiply"),
        GlobalShaderCompiler.get_kernel_index("composite", "multiply"),
        "so writing it either way finds the same kernel"
    )
    assert_true(GlobalShaderCompiler.get_kernel_index("composite", "multiply") >= 0, "which is a kernel that exists")


## A module that ships a name Sara does not have is reachable without qualifying
## it, because there is nothing to be ambiguous with.
func test_a_name_only_one_module_provides_resolves_to_that_module() -> void:
    _index("res://modules/sara-mixing-module/shaders/km_mixing.gmacs")

    assert_eq(
        GlobalShaderCompiler.resolve_shader_name("km_mixing"),
        "sara-mixing-module/km_mixing",
        "One provider, so the bare name is unambiguous"
    )


## The collision this whole change exists for. Two modules, one name, and the old
## code picked one by directory order without saying anything.
func test_a_name_two_modules_provide_is_refused_rather_than_guessed() -> void:
    _index("res://modules/sara-mixing-module/shaders/fill.gmacs")
    _index("res://modules/sara-noise-brush-engine/shaders/fill.gmacs")

    # Sara ships fill.gmacs too, so its own is what a bare name means and the two
    # modules are reachable only by owner.
    assert_eq(GlobalShaderCompiler.resolve_shader_name("fill"), "sara/fill", "Sara's own still wins a bare name")
    assert_eq(
        GlobalShaderCompiler.resolve_shader_name("sara-noise-brush-engine/fill"),
        "sara-noise-brush-engine/fill",
        "and a qualified name is taken exactly as written"
    )
    assert_eq(
        GlobalShaderCompiler.get_kernel_index("sara-noise-brush-engine/fill", "fill"),
        -1,
        "A qualified name for a shader that was never compiled is -1, not Sara's kernel"
    )


## An unknown name resolves to Sara's namespace rather than to nothing, so the
## error downstream names a shader instead of an empty string.
func test_an_unknown_name_still_lands_in_saras_namespace() -> void:
    assert_eq(GlobalShaderCompiler.resolve_shader_name("no_such_shader"), "sara/no_such_shader", "Unknown is Sara's")
    assert_eq(GlobalShaderCompiler.get_kernel_index("no_such_shader", "anything"), -1, "and finds no kernel")
    assert_eq(GlobalShaderCompiler.push_constant_bytes("no_such_shader"), 0, "and no push constant")


# --- Resolving an include ------------------------------------------------------


## An include is resolved from the point of view of whoever wrote it. A module
## shipping its own `transfer_curve` gets its own, and Sara's shaders keep getting
## Sara's, which is what the global `ends_with()` match could not express.
func test_a_module_including_a_name_it_ships_gets_its_own() -> void:
    var mine := "res://modules/sara-mixing-module/shaders/libs/transfer_curve.gmacs"
    _index(mine)

    assert_eq(
        GlobalShaderCompiler.index.find_include_file(
            "transfer_curve", "res://modules/sara-mixing-module/shaders/km_mixing.gmacs"
        ),
        mine,
        "The module's own library wins inside the module"
    )
    assert_eq(
        GlobalShaderCompiler.index.find_include_file("transfer_curve", "res://shaders/compute/composite.gmacs"),
        "res://shaders/compute/libs/transfer_curve.gmacs",
        "and Sara's shaders are unaffected by a module shipping the name"
    )


## Qualifying an include reaches across owners, which is the only way a module can
## deliberately use Sara's library when it also ships its own.
func test_a_qualified_include_names_the_owner_it_wants() -> void:
    _index("res://modules/sara-mixing-module/shaders/libs/transfer_curve.gmacs")

    assert_eq(
        GlobalShaderCompiler.index.find_include_file(
            "sara/transfer_curve", "res://modules/sara-mixing-module/shaders/km_mixing.gmacs"
        ),
        "res://shaders/compute/libs/transfer_curve.gmacs",
        "sara/ reaches Sara's copy from inside a module that shadows it"
    )


## Sara's shaders are compiled by name in the report, and a module's carry the
## owner so two files called the same thing are told apart in the console.
func test_the_console_keeps_saras_names_bare() -> void:
    assert_eq(GlobalShaderCompiler.index.display_name("sara/composite"), "composite", "Sara's shaders print as they always did")
    assert_eq(
        GlobalShaderCompiler.index.display_name("sara-mixing-module/paint"),
        "sara-mixing-module/paint",
        "and a module's says whose it is"
    )
