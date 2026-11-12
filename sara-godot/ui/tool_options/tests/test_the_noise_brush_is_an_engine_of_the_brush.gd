## The noise brush is an engine of the Brush, not a tool of its own.
##
## The noise brush counts as a brush tool, so the toolbox draws one Brush,
## its shelf holds the presets of both engines, and the preset picked decides
## which engine paints the next stroke. The noise module still registers what
## paints through the door, as an engine of the Brush rather than a tool.
##
## Everything here is built the way the app builds it: the three modules
## registered through the door, a machine bound to their registry, and the real
## bar, docker, toolbox and router asked what a painter's hand asks them. A
## stroke is a press and a release through the machine, and the noise engine is
## known to have painted it by the seed it lays every stroke's field with, which
## is never nought.
extends "res://tests/test_framework.gd"

## The machine builds every tool, which needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const NoiseSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const ToolBoxDockerScript = preload("res://ui/dockers/toolbox/toolbox_docker.gd")

## Where the dabs land, inside the first chunk.
const AT := Vector2(100.0, 100.0)

## The noise preset's size, which a stamp preset loaded after it does not touch.
const GRAIN_RADIUS := 0.07

static var scratch_dir: String = SaDataRoot.path("test_d33_presets")
static var usage_dir: String = SaDataRoot.path("test_d33_usage")

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _host: Node = null
var _bar: ToolOptionsBar = null


func before_each() -> void:
    _clear(scratch_dir)
    _clear(usage_dir)
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    # The stamp first, as the app loads it, so a fresh machine starts on the
    # Brush rather than on the fill.
    _modules.clear()
    for script: GDScript in [StampModuleScript, BaseModuleScript, NoiseModuleScript]:
        var module: SaModule = script.new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)
    _surface.view.mouse_position = AT


func after_each() -> void:
    SaUsageTally.stop()
    if _host != null:
        EventBus.remove_child(_host)
        _host.free()
        _host = null
        _bar = null
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    for module: SaModule in _modules:
        module.unregister(_registries.context)
        _registries.context.for_module(module.get_id()).remove_all_registrations()
    _modules.clear()
    _registries = null
    _clear(scratch_dir)
    _clear(usage_dir)


## The bar and the Brush Presets docker in the tree, over a store holding a
## stamp preset and a noise preset of a size the stamp's is not.
func _shelf() -> BrushPresetsDocker:
    _host = Node.new()
    # In the tree, because the docker finds the bar's preset group by name from
    # the scene root.
    EventBus.add_child(_host)
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_dir
    _bar.preset_store.save_preset("Ink", StampSettingsScript.new())
    var grain: Resource = NoiseSettingsScript.new()
    grain.radius = GRAIN_RADIUS
    _bar.preset_store.save_preset("Grain", grain)
    _bar._ready()
    var docker := BrushPresetsDocker.new()
    _host.add_child(docker)
    docker.rebind()
    return docker


func _toolbox() -> ToolBoxDocker:
    var docker := ToolBoxDockerScript.new() as ToolBoxDocker
    docker.name = "ToolBoxDocker"
    docker.target_tool_machine = _machine
    docker.rebuild_from_registry(_registries.tools)
    return docker


## One press and release through the machine, and whether the noise engine laid
## it: its field seed is nought before and never nought after a stroke of its own.
func _stroke_is_noise() -> bool:
    var noise := _machine.get_tool(NoiseModuleScript.TOOL_ID) as StateNoiseBrushScript
    noise.field_seed = 0
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    _machine.handle_input(press)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    _machine.handle_input(release)
    return noise.field_seed != 0


func _key(keycode: Key, unicode: int = 0) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.unicode = unicode
    event.pressed = true
    return event


func _router() -> ShortcutRouter:
    var router := ShortcutRouter.new()
    router.canvas_provider = func() -> SaCanvas: return null
    router.tool_machine_provider = func() -> ToolMachine: return _machine
    return router


func _dimmed(docker: BrushPresetsDocker, preset_name: String) -> bool:
    docker.after_pick.settle_all()  # the redim a switch leaves for the next frame
    var cells: Dictionary = docker.engine_marks.report()["cells"]
    return bool((cells.get(preset_name, {}) as Dictionary).get("dimmed", false))


func _faces(docker: ToolBoxDocker) -> Dictionary:
    var faces := {}
    for entry: Dictionary in docker.toolbox_report()["buttons"]:
        if entry.has("category"):
            faces[entry["category"]] = entry["face"]
    return faces


## "It should still count as a brush tool": one Brush button, no noise tool on
## it or anywhere in the toolbox, and the noise engine registered through the
## door all the same.
func test_the_toolbox_shows_one_brush_and_no_noise_tool() -> void:
    var tools := _registries.tools
    var descriptor := tools.get_descriptor(NoiseModuleScript.TOOL_ID)
    assert_not_null(descriptor, "The noise module registers what paints through the door")
    assert_true(descriptor.is_brush_engine, "as an engine of the Brush")
    assert_eq(descriptor.owner_module, NoiseModuleScript.new().get_id(), "under its own module's name")
    var listed: Array[StringName] = []
    for tool: SaToolDescriptor in tools.list_tools():
        listed.append(tool.id)
    assert_true(listed.has(&"brush"), "The tools a painter is offered hold the Brush")
    assert_false(listed.has(NoiseModuleScript.TOOL_ID), "and not the noise brush")
    assert_eq(tools.tool_of(NoiseModuleScript.TOOL_ID), &"brush", "which counts as the Brush")
    assert_eq(
        tools.engines_of(&"brush"),
        [&"brush", &"liquify", NoiseModuleScript.TOOL_ID] as Array[StringName],
        "one of the Brush's engines, after the stamp and liquify"
    )

    var docker := _toolbox()
    assert_null(docker.button_for_tool(String(NoiseModuleScript.TOOL_ID)), "The toolbox has no button for the noise brush")
    var brushes := 0
    for entry: Dictionary in docker.toolbox_report()["buttons"]:
        var members: Array = entry.get("members", [])
        assert_false(members.has(String(NoiseModuleScript.TOOL_ID)), "and no flyout offers it")
        brushes += members.count("brush")
    assert_eq(brushes, 1, "One Brush, offered once")

    _machine.set_active_tool(NoiseModuleScript.TOOL_ID)
    # What the bus hands a toolbox in the tree, which this one is not.
    docker._on_event_tool_changed(String(_machine.active_tool_name))
    var button := docker.button_for_tool("brush")
    assert_true(button.button_pressed, "Painting with the noise engine lights the Brush's button")
    assert_eq(_faces(docker).get("paint"), "brush", "which keeps the Brush's face")
    docker.free()


## A noise preset picked from the presets bar makes the next stroke a noise
## stroke, and a stamp preset makes it a stamp stroke again, with the Brush in
## hand throughout.
func test_a_preset_from_the_bar_picks_the_engine_of_the_next_stroke() -> void:
    _machine.set_active_tool(&"brush")
    _shelf()
    var engines := _bar.preset_box.preset_engines()
    assert_true(engines.has(&"stamp") and engines.has(&"noise"), "The Brush takes both engines' presets: %s" % [engines])

    assert_true(_bar.preset_box.load_preset("Grain"), "The bar loads the noise preset")
    assert_eq(_machine.active_tool_name, NoiseModuleScript.TOOL_ID, "onto the noise engine")
    assert_almost_eq(float(_machine.active_tool.get("settings").radius), GRAIN_RADIUS, 1e-6, "which holds its size")
    assert_true(_stroke_is_noise(), "and the next stroke is a noise stroke")

    assert_true(_bar.preset_box.load_preset("Ink"), "The bar loads the stamp preset")
    assert_eq(_machine.active_tool_name, &"brush", "back onto the stamp")
    assert_true(_machine.active_tool is StateBrushScript, "whose engine is the stamp's")
    assert_false(_stroke_is_noise(), "and the next stroke is a stamp stroke")


## The same from the Brush Presets docker, whose grid lights both engines'
## presets under the Brush and dims the noise ones under the eraser, which
## paints with the stamp alone.
func test_a_preset_from_the_docker_picks_the_engine_of_the_next_stroke() -> void:
    _machine.set_active_tool(&"brush")
    var docker := _shelf()
    assert_false(_dimmed(docker, "Grain"), "The noise preset is lit under the Brush")
    assert_false(_dimmed(docker, "Ink"), "and so is the stamp one")
    assert_eq(
        docker.tool_engines(), [&"stamp", &"liquify", &"noise"] as Array[StringName], "the Brush's engines, the stamp first"
    )

    assert_true(docker.apply_preset("Grain"), "A press on the noise cell loads it")
    assert_eq(_machine.active_tool_name, NoiseModuleScript.TOOL_ID, "onto the noise engine")
    assert_true(_stroke_is_noise(), "and the next stroke is a noise stroke")
    assert_false(_dimmed(docker, "Ink"), "The stamp preset stays lit under the noise engine")

    assert_true(docker.apply_preset("Ink"), "A press on the stamp cell loads it")
    assert_eq(_machine.active_tool_name, &"brush", "onto the stamp")
    assert_false(_stroke_is_noise(), "and the next stroke is a stamp stroke")

    _machine.set_active_tool(&"eraser")
    assert_true(_dimmed(docker, "Grain"), "The eraser takes stamp presets alone, so the noise one is dimmed")
    assert_false(docker.apply_preset("Grain"), "and refused")
    assert_eq(_machine.active_tool_name, &"eraser", "with the eraser still in hand")


## B, the Brush's button and the size keys work the same under either engine,
## and B after the eraser picks the engine the Brush last painted with.
func test_b_picks_the_brush_under_either_engine() -> void:
    _machine.set_active_tool(NoiseModuleScript.TOOL_ID)
    var router := _router()
    var toolbox := _toolbox()
    _machine.set_active_tool(&"eraser")
    router.handle(_key(KEY_B))
    assert_eq(_machine.active_tool_name, NoiseModuleScript.TOOL_ID, "B after the eraser is the Brush on the noise engine")
    router.handle(_key(KEY_B))
    assert_eq(_machine.active_tool_name, NoiseModuleScript.TOOL_ID, "and B again keeps it there")

    var settings: Resource = _machine.active_tool.get("settings")
    var before := float(settings.radius)
    router.handle(_key(KEY_BRACKETRIGHT, 93))
    assert_true(float(settings.radius) > before, "] grows the noise engine's size, %f to %f" % [before, float(settings.radius)])

    _machine.set_active_tool(&"eraser")
    toolbox._select_tool("brush")
    assert_eq(_machine.active_tool_name, NoiseModuleScript.TOOL_ID, "The Brush's button after the eraser is the noise engine too")

    _machine.set_active_tool(&"brush")
    _machine.set_active_tool(&"eraser")
    router.handle(_key(KEY_B))
    assert_eq(_machine.active_tool_name, &"brush", "Having painted with the stamp, B is the Brush on the stamp")
    toolbox.free()
    router.free()


## The eraser toggle is the Brush's under either engine: E flips the noise
## engine into erasing and back rather than handing over to the eraser tool.
func test_the_eraser_toggle_works_under_the_noise_engine() -> void:
    _machine.set_active_tool(NoiseModuleScript.TOOL_ID)
    var noise := _machine.active_tool as StateNoiseBrushScript
    assert_false(noise.eraser_toggled, "The noise engine starts painting")
    assert_true(_registries.commands.execute(&"brush_toggle_eraser"), "The toggle runs")
    assert_eq(_machine.active_tool_name, NoiseModuleScript.TOOL_ID, "with the Brush still in hand")
    assert_true(noise.eraser_toggled, "and the noise engine erasing")
    _registries.commands.execute(&"brush_toggle_eraser")
    assert_false(noise.eraser_toggled, "and a second toggle paints again")


## A profile of an older version, whose toolbox layout names the noise
## brush in its order, its visibility and its groups, comes back with none of
## the three and every other entry kept. A recorded session's tool step naming
## `noise_brush` lands on the Brush, holding the noise preset it last loaded.
func test_a_profile_naming_the_noise_brush_loads_onto_the_brush() -> void:
    var config := ConfigFile.new()
    config.set_value("meta", "version", 17)
    config.set_value("profile_order", "ToolBoxDocker", ["Brush Tool", "Noise Brush Tool", "Eraser Tool"])
    config.set_value("profile_visibility", "ToolBoxDocker_Noise Brush Tool", false)
    config.set_value("profile_visibility", "ToolBoxDocker_Eraser Tool", true)
    config.set_value("profile_docker_option", "ToolBoxDocker_groups", [["brush", "noise_brush", "eraser"], ["noise_brush"]])
    SaSettingsMigrations.apply(config, 17)
    assert_eq(
        config.get_value("profile_order", "ToolBoxDocker"), ["Brush Tool", "Eraser Tool"], "The order loses the noise brush's row"
    )
    assert_false(config.has_section_key("profile_visibility", "ToolBoxDocker_Noise Brush Tool"), "and its visibility")
    assert_true(config.has_section_key("profile_visibility", "ToolBoxDocker_Eraser Tool"), "and keeps the eraser's")
    assert_eq(
        config.get_value("profile_docker_option", "ToolBoxDocker_groups"),
        [["brush", "eraser"]],
        "The groups keep the Brush's with the noise brush out, and the group it was alone in goes"
    )

    _machine.set_active_tool(&"brush")
    _shelf()
    assert_true(_bar.preset_box.load_preset("Grain"), "A noise preset loaded")
    _bar.preset_box.load_preset("Ink")
    _machine.set_active_tool(&"eraser")
    var toolbox := _toolbox()
    _machine.set_active_tool(NoiseModuleScript.TOOL_ID)
    toolbox._on_event_tool_changed(String(_machine.active_tool_name))
    assert_true(toolbox.button_for_tool("brush").button_pressed, "The step naming the noise brush lights the Brush")
    assert_eq(_bar.preset_box.preset_engine(), &"noise", "on the noise engine")
    assert_almost_eq(
        float(_machine.active_tool.get("settings").radius), GRAIN_RADIUS, 1e-6, "holding the noise preset it last loaded"
    )
    toolbox.free()


## The tally counts either engine as the Brush: a switch between the engines is
## no switch, and a noise stroke is a stroke of the Brush.
func test_the_tally_counts_either_engine_as_the_brush() -> void:
    _machine.set_active_tool(&"eraser")
    var tally := SaUsageTally.start(Engine.get_main_loop() as SceneTree, usage_dir)
    tally.tools = _registries.tools
    _machine.set_active_tool(NoiseModuleScript.TOOL_ID)
    _machine.set_active_tool(&"brush")
    _machine.set_active_tool(NoiseModuleScript.TOOL_ID)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    SaUsageTally.tool_input(press, NoiseModuleScript.TOOL_ID)
    var release := press.duplicate() as InputEventMouseButton
    release.pressed = false
    SaUsageTally.tool_input(release, NoiseModuleScript.TOOL_ID)
    var report := tally.report()
    var switches: Dictionary = report["tools"]
    assert_false(switches.has(String(NoiseModuleScript.TOOL_ID)), "No switch is counted to the noise brush: %s" % [switches])
    var to_brush := 0
    for source: String in switches.get("brush", {}):
        to_brush += int(switches["brush"][source])
    assert_eq(to_brush, 1, "and the three switches between the engines count as one to the Brush")
    assert_eq(int(report["strokes"].get("brush", 0)), 1, "The noise stroke is the Brush's")
    assert_false((report["strokes"] as Dictionary).has(String(NoiseModuleScript.TOOL_ID)), "and nobody else's")


func _clear(folder: String) -> void:
    var dir := DirAccess.open(folder)
    if dir == null:
        return
    for file: String in dir.get_files():
        dir.remove(file)
