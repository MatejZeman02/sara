## Every engine the skeleton constructs is asked for through
## the registries by role name, and a module registers a subclass under the
## role to replace it, or removes a built-in by id.
##
## A module can change, add or remove almost anything, by subclassing a
## core class and re-implementing what it wants, and the skeleton then uses
## its version. The fixture module under
## `tests/fixtures/modules/role-fixture/` is the third-party half, registered
## through `SaContext` and nothing else, and the three cases below are its
## clauses in order: the Canvas Size dialog builds the module's
## crop, the toolbox no longer shows the tool the module removed, and the
## console names both modules when a role is claimed twice.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")

const FIXTURE_MODULE = preload("res://tests/fixtures/modules/role-fixture/module.gd")
const COUNTING_CROP = preload("res://tests/fixtures/modules/role-fixture/counting_crop.gd")
const ToolBoxDockerScript = preload("res://ui/dockers/toolbox/toolbox_docker.gd")

const FIXTURE_ID := &"role-fixture"


## What `MainDialogs` is built from: the registries and a canvas provider, held
## by a node that stands in for `Main` as the dialog's parent.
class FakeMain:
    extends Node
    var registries: SaRegistries
    var canvas: SaCanvas

    func get_canvas() -> SaCanvas:
        return canvas


func before_each() -> void:
    COUNTING_CROP.forget()


func after_each() -> void:
    ModuleLoader.loaded_modules.erase(FIXTURE_ID)


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    return registries


## The fixture module registered through the public door, into registries
## that already hold the skeleton's engines and one tool it can remove.
func _with_fixture(registries: SaRegistries) -> SaModule:
    var module := FIXTURE_MODULE.new()
    module.register(registries.context.for_module(module.get_id()))
    return module


## The `transform` role is not in this list: the engine followed the
## tool that was its only asker into the base module, which registers the role
## the way it registers `flood` and `gradient`. What the skeleton still owns is
## what this case reads, and the three transform scenarios are what prove the
## fourth reaches the tool that asks for it.
func test_the_skeleton_registers_its_engines_under_roles() -> void:
    var registries := _registries()
    for role: StringName in [&"crop", &"resample", &"selection_filters", &"live_transform"]:
        assert_true(registries.roles.has(role), "The skeleton registered '%s'" % role)
        assert_eq(registries.roles.owner_of(role), &"sara-skeleton", "under its own id")
    assert_eq(registries.roles.script_for(&"crop"), SaCrop, "and the crop role answers the skeleton's crop")
    assert_null(registries.roles.script_for(&"nothing"), "A role nobody registered answers null")


## The first clause: a crop subclass under the role, and the Canvas
## Size dialog uses it. Through `MainDialogs`, which is the class the dialog's
## confirm reaches, and through the document's size, which is the proof the
## subclass did the work rather than only being asked.
func test_the_canvas_size_dialog_builds_the_modules_crop() -> void:
    var registries := _registries()
    _with_fixture(registries)
    assert_eq(registries.roles.script_for(&"crop"), COUNTING_CROP, "The role answers the module's subclass")

    var main := FakeMain.new()
    main.registries = registries
    main.canvas = SaCanvas.new()
    main.canvas.canvas_size = Vector2i(512, 512)
    main.canvas.easel = SaEasel.create_default(main.canvas.canvas_size)
    main.canvas.add_child(main.canvas.easel)
    main.add_child(main.canvas)
    var dialogs := MainDialogs.new(registries, main.get_canvas)
    main.add_child(dialogs)

    dialogs._on_canvas_size_confirmed(Vector2i(640, 400), Vector2i(0, 0))
    assert_eq(COUNTING_CROP.resizes, [Vector2i(640, 400)], "The dialog resized through the module's crop")
    assert_eq(main.canvas.document.canvas_size, Vector2i(640, 400), "and the document is the size it asked for")
    main.free()


## The crop tool asks a role too. Its box is a live crop of
## the active layer, the skeleton's live transform under `live_transform`,
## because a module sees the door only. The tool is handed the registry the
## way the machine hands it, and reads the role when a session opens.
func test_the_crop_tool_reads_the_live_transform_role() -> void:
    var registries := _registries()
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var machine := ToolMachine.new()
    machine.name = "ToolMachine"
    machine._ready()
    machine.bind(surface, Fixtures.make_tool_registry(), registries.roles)
    var tool: ToolState = machine.registered_tools[&"crop"]
    assert_eq(tool.roles, registries.roles, "The machine handed the tool the role registry")
    assert_eq(tool._live(), SaLiveTransform, "and the tool's crop is the skeleton's live transform")
    Fixtures.teardown(surface, machine)


## The second clause: the module removes a built-in tool by id, and the
## toolbox no longer shows it.
func test_a_removed_tool_leaves_the_toolbox() -> void:
    var registries := _registries()
    var skeleton := registries.context.for_module(&"sara-base-modules")
    var marquee := Fixtures.make_tool_descriptor(FIXTURE_MODULE.REMOVED_TOOL)
    marquee.category = &"select"
    assert_true(skeleton.register_tool(marquee), "The tool is registered before the module loads")
    var toolbox := ToolBoxDockerScript.new()
    toolbox.name = "ToolBoxDocker"
    toolbox.rebuild_from_registry(registries.tools)
    assert_not_null(toolbox.button_for_tool(String(FIXTURE_MODULE.REMOVED_TOOL)), "and the toolbox shows it")

    _with_fixture(registries)
    assert_false(registries.tools.has(FIXTURE_MODULE.REMOVED_TOOL), "The module took the tool away by id")
    assert_null(toolbox.button_for_tool(String(FIXTURE_MODULE.REMOVED_TOOL)), "and the toolbox no longer shows it")
    toolbox.free()


## The third clause: the console line names both modules when a role
## is claimed twice. The line is read through the signal that carries the
## same two names the printed line does, and through `claim_line`, which is
## the one place the words live.
func test_the_console_names_both_modules_when_a_role_is_claimed_twice() -> void:
    var registries := _registries()
    var heard: Array = []
    registries.roles.replaced.connect(
        func(role: StringName, previous: StringName, module: StringName) -> void: heard.append([role, previous, module])
    )

    _with_fixture(registries)
    assert_eq(heard, [[&"crop", &"sara-skeleton", FIXTURE_ID]], "One replacement, naming the skeleton and the module")
    var line := SaRoleRegistry.claim_line(&"crop", &"sara-skeleton", FIXTURE_ID)
    assert_true(line.contains("'sara-skeleton'") and line.contains("'role-fixture'"), "and the console line carries both")
    assert_eq(registries.roles.claimants_of(&"crop"), [&"sara-skeleton", FIXTURE_ID], "Both claims are kept, oldest first")


## Unloading the module uncovers the skeleton's crop rather than leaving the
## role empty, which is what a stack of claims is for.
func test_unloading_the_module_uncovers_the_skeletons_engine() -> void:
    var registries := _registries()
    var module := _with_fixture(registries)
    registries.context.for_module(module.get_id()).remove_all_registrations()
    assert_eq(registries.roles.script_for(&"crop"), SaCrop, "The skeleton's crop is back on top")
    assert_eq(registries.roles.owner_of(&"crop"), &"sara-skeleton", "under its own id")
    assert_eq(registries.roles.claimants_of(&"crop"), [&"sara-skeleton"], "and the module's claim is gone")


## The by-id removals the four registries learned, so a module can take a
## command, a blend mode, a docker or a view transform away the way it takes
## a tool.
func test_every_registry_removes_a_registration_by_id() -> void:
    var registries := _registries()
    assert_true(registries.commands.has(&"layer_clip_to_below"), "A skeleton command to remove")
    registries.commands.unregister(&"layer_clip_to_below")
    assert_false(registries.commands.has(&"layer_clip_to_below"), "The command is gone")

    assert_true(registries.blend_modes.has(&"multiply"), "A skeleton blend mode to remove")
    registries.blend_modes.unregister(&"multiply")
    assert_false(registries.blend_modes.has(&"multiply"), "The blend mode is gone")
    assert_true(registries.blend_modes.has(&"normal"), "and the others stay")

    var ctx := registries.context.for_module(&"someone")
    ctx.register_docker(&"e4_docker", "E4", func() -> Window: return Window.new())
    registries.ui.unregister_docker(&"e4_docker")
    assert_false(registries.ui.has_docker(&"e4_docker"), "The docker is gone")

    var transform := SaViewTransformDescriptor.create(&"e4_transform", "E4", SaViewTransformDescriptor.Kind.TOGGLE)
    assert_true(ctx.register_view_transform(transform), "A view transform to remove")
    registries.view_transforms.unregister(&"e4_transform")
    assert_false(registries.view_transforms.has(&"e4_transform"), "The view transform is gone")
