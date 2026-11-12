## Liquify is an engine of the
## Brush, its modes and settings kept as presets.
##
## The request: "Can we have all the liquify tool options in between brush
## presets?" So each shipped liquify preset picked with the Brush in hand puts
## the liquify engine in the hand with that preset's mode, size, strength and
## direction, a stamp preset picked over an open session commits it as one undo
## step, Save As... keeps the four rows, the Liquify command picks the liquify
## preset used last, and neither the toolbox nor the Tools menu offers liquify
## as a tool of its own.
##
## Built the way the app builds it: the stamp and base modules registered
## through the door, a machine bound to their registry, and the real bar and
## Brush Presets docker in the tree, whose shelves install the shipped presets
## into a scratch folder as they install them into a painter's.
extends "res://tests/test_framework.gd"

## The machine builds every tool and the session's chunks are textures, so this
## needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const StateScript = preload("res://modules/sara-base-modules/base/liquify/state_liquify.gd")
const SettingsScript = preload("res://modules/sara-base-modules/base/liquify/liquify_settings.gd")
const PresetsScript = preload("res://modules/sara-base-modules/base/liquify/liquify_presets.gd")
const LiquifyScript = preload("res://modules/sara-base-modules/base/liquify/sa_liquify.gd")
const ToolBoxDockerScript = preload("res://ui/dockers/toolbox/toolbox_docker.gd")

const CANVAS := Vector2i(512, 256)
## A red stripe across the first chunk, which the push drags right.
const STRIPE := Vector2i(100, 116)
const ROW: float = 128.0
const RED := Color(0.9, 0.1, 0.1, 1.0)
## The stamp preset written beside the shelves, the one picked to leave.
const INK: String = "Ink"

static var scratch_dir: String = SaDataRoot.path("test_u32_presets")

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _host: Node = null
var _bar: ToolOptionsBar = null
var _docker: BrushPresetsDocker = null
## The Liquify command's memory as the run found it, put back after each test.
var _kept_last: Variant = null


func before_each() -> void:
    _clear(scratch_dir)
    _surface = Fixtures.make_surface(CANVAS)
    _registries = Fixtures.make_registries(_surface)
    # The stamp first, as the app loads it, so a fresh machine starts on the
    # Brush.
    _modules.clear()
    for script: GDScript in [StampModuleScript, BaseModuleScript]:
        var module: SaModule = script.new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    _kept_last = SaSettings.module_preference(&"sara-base-modules", LiquifyScript.LAST_PRESET_KEY, "")
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)


func after_each() -> void:
    SaSettings.set_module_preference(&"sara-base-modules", LiquifyScript.LAST_PRESET_KEY, _kept_last)
    if _host != null:
        EventBus.remove_child(_host)
        _host.free()
        _host = null
        _bar = null
        _docker = null
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    for module: SaModule in _modules:
        module.unregister(_registries.context)
        _registries.context.for_module(module.get_id()).remove_all_registrations()
    _modules.clear()
    _registries = null
    _clear(scratch_dir)


## The bar and the Brush Presets docker in the tree, over a scratch store with
## a stamp preset of its own beside what the shelves install.
func _shelf() -> void:
    _host = Node.new()
    # In the tree, because the docker and the Liquify command find the bar's
    # preset group by name from the scene root.
    EventBus.add_child(_host)
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_dir
    _bar.preset_store.save_preset(INK, StampSettingsScript.new())
    # The shelf the module registers, installed as the bar installs it in the
    # app, where the role is read off the main scene's registries, which a
    # suite's scene is not.
    var shelf := _registries.roles.script_for(LiquifyScript.PRESETS_ROLE)
    _bar.preset_store.install_shipped(_settings(), shelf)
    _bar._ready()
    _docker = BrushPresetsDocker.new()
    _host.add_child(_docker)
    _docker.rebind()


## The liquify engine's settings, the one resource every surface's tool holds.
func _settings() -> Resource:
    return _machine.get_tool(LiquifyScript.TOOL_ID).get("settings")


static func _clear(dir: String) -> void:
    if not DirAccess.dir_exists_absolute(dir):
        return
    for file in DirAccess.get_files_at(dir):
        DirAccess.remove_absolute(dir.path_join(file))
    DirAccess.remove_absolute(dir)


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## A fresh active layer whose first chunk holds the red stripe.
func _paint() -> SaLayer:
    var doc := _surface.get_document()
    var layer := SaLayerOps.new(doc).add(&"", null, 1.0)
    doc.active_layer = layer
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    var texture := chunk.albedo()
    var side := chunk.pixel_size()
    var image := Image.create_empty(side, side, false, _image_format(texture))
    for y in side:
        for x in side:
            image.set_pixel(x, y, RED if x >= STRIPE.x and x < STRIPE.y else Color(0.0, 0.0, 0.0, 0.0))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    layer.mark_unresolved(Vector2i.ZERO)
    doc.invalidate_chunks([Vector2i.ZERO])
    return layer


## The alpha along the middle row of the first chunk.
static func _row(layer: SaLayer) -> PackedFloat32Array:
    var chunk: SaChunk = layer.chunks.get(Vector2i.ZERO, null)
    var row := PackedFloat32Array()
    if chunk == null:
        return row
    var texture := chunk.albedo()
    var side := chunk.pixel_size()
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var texels := Image.create_from_data(side, side, false, _image_format(texture), bytes)
    for x in side:
        row.append(texels.get_pixel(x, int(ROW)).a)
    return row


static func _farthest(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
    var most := 0.0
    for i in mini(a.size(), b.size()):
        most = maxf(most, absf(a[i] - b[i]))
    return most


## The Done-when's first half: each shipped liquify preset picked with the Brush
## in hand puts the liquify engine in the hand with that preset's mode, size,
## strength and direction.
func test_each_shipped_liquify_preset_puts_liquify_in_hand_with_its_settings() -> void:
    _machine.set_active_tool(&"brush")
    _shelf()
    var entries := PresetsScript.entries()
    assert_eq(entries.size(), 5, "Five presets ship, a mode each that moves paint and both ways of the twirl")
    for entry: Dictionary in entries:
        var preset_name: String = entry["name"]
        assert_eq(
            _bar.preset_box.preset_store.engine_for(preset_name),
            SettingsScript.PRESET_ENGINE,
            "%s ships as a liquify preset" % preset_name
        )
        _machine.set_active_tool(&"brush")
        assert_eq(_bar.preset_box.preset_engine(), &"stamp", "The Brush is in hand on the stamp before %s" % preset_name)
        assert_true(_bar.preset_box.load_preset(preset_name), "%s loads" % preset_name)
        assert_eq(_machine.active_tool_name, LiquifyScript.TOOL_ID, "%s puts the liquify engine in the hand" % preset_name)
        assert_true(_machine.active_tool is StateScript, "whose tool is liquify's")
        assert_eq(_bar.preset_box.selected_preset, preset_name, "and %s is the preset in hand" % preset_name)
        var wanted: Dictionary = entry["settings"]
        var held := _settings()
        assert_eq(held.mode, int(wanted["mode"]), "%s's mode" % preset_name)
        assert_eq(held.direction, int(wanted["direction"]), "%s's direction" % preset_name)
        assert_almost_eq(held.size, float(wanted["size"]), 1e-4, "%s's size" % preset_name)
        assert_almost_eq(held.strength, float(wanted["strength"]), 1e-4, "%s's strength" % preset_name)
        assert_true(_machine.active_tool.get("settings") == held, "which the tool in hand reads")


## The five cover every mode that moves paint already laid: Push, Twirl both
## ways, Shrink and Grow. Reconstruct and Smooth work only on what the same
## session pushed, so a preset of either changes nothing picked from the shelf
## and they are left to the Mode row.
func test_the_shelf_covers_every_mode_and_both_twirls() -> void:
    var seen := {}
    for entry: Dictionary in PresetsScript.entries():
        var wanted: Dictionary = entry["settings"]
        var key := (
            "%d/%d" % [wanted["mode"], wanted["direction"]] if int(wanted["mode"]) == StateScript.TWIRL else str(wanted["mode"])
        )
        seen[key] = entry["name"]
        assert_eq(
            PresetsScript.licence_for(entry["bundle"]), "GPL-3.0-or-later", "%s carries the module's licence" % entry["name"]
        )
        assert_false(String(entry["about"]).is_empty(), "%s says what it does" % entry["name"])
    for mode: int in [StateScript.PUSH, StateScript.SHRINK, StateScript.GROW]:
        assert_true(seen.has(str(mode)), "A preset of mode %d" % mode)
    for mode: int in [StateScript.RECONSTRUCT, StateScript.SMOOTH]:
        assert_false(seen.has(str(mode)), "No preset of mode %d" % mode)
    assert_true(seen.has("%d/%d" % [StateScript.TWIRL, StateScript.CLOCKWISE]), "A clockwise twirl")
    assert_true(seen.has("%d/%d" % [StateScript.TWIRL, StateScript.ANTICLOCKWISE]), "and an anticlockwise one")


## The Done-when's second half: a stamp preset picked over an open liquify
## session leaves liquify the way leaving the tool does, its session committed
## as one undo step, which one undo takes back whole.
func test_a_stamp_preset_commits_the_session_as_one_undo_step() -> void:
    _machine.set_active_tool(&"brush")
    _shelf()
    var layer := _paint()
    var doc := _surface.get_document()
    var before := _row(layer)
    assert_true(_bar.preset_box.load_preset(PresetsScript.FIRST), "Liquify Push loads")
    _settings().strength = 1.0
    var tool := _machine.active_tool as StateScript
    tool.press(Vector2(STRIPE.x - 10, ROW))
    tool.drag_to(Vector2(STRIPE.y + 30, ROW))
    tool.release()
    assert_true(_machine.holds_session(), "The push left a session open")
    var pushed := _row(layer)
    assert_true(_farthest(before, pushed) > 0.5, "which moved the stripe, by %f" % _farthest(before, pushed))
    var version := doc.undo_redo.get_version()

    assert_true(_bar.preset_box.load_preset(INK), "A stamp preset loads over it")
    assert_eq(_machine.active_tool_name, &"brush", "onto the stamp engine")
    assert_false(tool.holds_session(), "The session is closed")
    assert_eq(doc.undo_redo.get_version(), version + 1, "as one undo step")
    assert_almost_eq(_farthest(pushed, _row(layer)), 0.0, 1e-3, "keeping the pushed paint")

    doc.undo_redo.undo()
    assert_almost_eq(_farthest(before, _row(layer)), 0.0, 1e-3, "and one undo puts the stripe back")
    doc.undo_redo.redo()
    assert_almost_eq(_farthest(pushed, _row(layer)), 0.0, 1e-3, "which a redo pushes again")


## "it leaves the toolbox and the Tools menu": the tools a painter is offered
## hold no liquify, the Brush counts it as one of its engines, the toolbox has
## no button for it, and the Brush Presets docker lists its presets lit beside
## the stamp's.
func test_liquify_is_an_engine_and_no_tool_of_its_own() -> void:
    var tools := _registries.tools
    var descriptor := tools.get_descriptor(LiquifyScript.TOOL_ID)
    assert_not_null(descriptor, "The base module registers liquify through the door")
    assert_true(descriptor.is_brush_engine, "as an engine of the Brush")
    assert_eq(descriptor.preset_engine, SettingsScript.PRESET_ENGINE, "taking its own settings' presets")
    assert_true(descriptor.shared_settings is SettingsScript, "which every surface's tool shares")
    assert_eq(_registries.roles.script_for(LiquifyScript.PRESETS_ROLE), PresetsScript, "and its shelf under the engine's role")
    var listed: Array[StringName] = []
    for tool: SaToolDescriptor in tools.list_tools():
        listed.append(tool.id)
    assert_false(listed.has(LiquifyScript.TOOL_ID), "The tools offered, the toolbox's and the Tools menu's, hold no liquify")
    assert_eq(tools.tool_of(LiquifyScript.TOOL_ID), &"brush", "which counts as the Brush")
    assert_true(tools.engines_of(&"brush").has(LiquifyScript.TOOL_ID), "one of the Brush's engines")

    var toolbox := ToolBoxDockerScript.new() as ToolBoxDocker
    toolbox.name = "ToolBoxDocker"
    toolbox.target_tool_machine = _machine
    toolbox.rebuild_from_registry(tools)
    assert_null(toolbox.button_for_tool(String(LiquifyScript.TOOL_ID)), "The toolbox has no Liquify button")
    for entry: Dictionary in toolbox.toolbox_report()["buttons"]:
        var members: Array = entry.get("members", [])
        assert_false(members.has(String(LiquifyScript.TOOL_ID)), "and no flyout offers it")
    toolbox.free()

    _machine.set_active_tool(&"brush")
    _shelf()
    assert_true(_docker.tool_engines().has(SettingsScript.PRESET_ENGINE), "The docker lists liquify's presets under the Brush")
    var cells: Dictionary = _docker.engine_marks.report()["cells"]
    for entry: Dictionary in PresetsScript.entries():
        assert_true(cells.has(entry["name"]), "%s is a cell of the docker" % entry["name"])
        assert_false(bool((cells.get(entry["name"], {}) as Dictionary).get("dimmed", true)), "lit under the Brush")
    assert_true(cells.has(INK), "beside the stamp preset")


## Save As... with liquify in hand keeps the four rows as a liquify preset,
## which loads them back.
func test_save_as_keeps_the_current_liquify_settings() -> void:
    _machine.set_active_tool(&"brush")
    _shelf()
    assert_true(_bar.preset_box.load_preset("Liquify Twirl Anticlockwise"), "A twirl loads")
    var held := _settings()
    held.size = 333.0
    held.strength = 0.25
    var stored := _bar.preset_box.save_current_as_preset("My Twirl")
    assert_eq(stored, "My Twirl", "Save As... writes the settings in hand")
    assert_eq(_bar.preset_box.preset_store.engine_for(stored), SettingsScript.PRESET_ENGINE, "as a liquify preset")
    assert_true(_bar.preset_box.load_preset(INK), "The stamp in hand again")
    assert_true(_bar.preset_box.load_preset(stored), "and the saved one loads")
    assert_eq(_machine.active_tool_name, LiquifyScript.TOOL_ID, "with liquify in hand")
    assert_eq(held.mode, StateScript.TWIRL, "twirling")
    assert_eq(held.direction, StateScript.ANTICLOCKWISE, "anticlockwise")
    assert_almost_eq(held.size, 333.0, 1e-4, "at the size saved")
    assert_almost_eq(held.strength, 0.25, 1e-4, "and the strength")


## The Liquify command picks the liquify preset used last, from the stamp, and
## Liquify Push before any was used. Its memory is the one a save leaves too.
func test_the_liquify_command_picks_the_last_liquify_preset_used() -> void:
    SaSettings.set_module_preference(&"sara-base-modules", LiquifyScript.LAST_PRESET_KEY, "")
    _machine.set_active_tool(&"brush")
    _shelf()
    var commands := _registries.commands
    assert_true(commands.execute(LiquifyScript.COMMAND_ID), "Liquify runs before any liquify preset was used")
    assert_eq(_bar.preset_box.selected_preset, PresetsScript.FIRST, "and picks Liquify Push")
    assert_eq(_machine.active_tool_name, LiquifyScript.TOOL_ID, "with liquify in hand")

    assert_true(_bar.preset_box.load_preset("Liquify Shrink"), "Liquify Shrink loads")
    assert_true(_bar.preset_box.load_preset(INK), "then the stamp")
    assert_eq(_machine.active_tool_name, &"brush", "which puts the stamp in hand")
    assert_true(commands.execute(LiquifyScript.COMMAND_ID), "Liquify runs")
    assert_eq(_machine.active_tool_name, LiquifyScript.TOOL_ID, "putting liquify in hand")
    assert_eq(_bar.preset_box.selected_preset, "Liquify Shrink", "with the liquify preset used last")
    assert_eq(_settings().mode, StateScript.SHRINK, "and its mode")

    _machine.set_active_tool(&"eraser")
    assert_true(commands.execute(LiquifyScript.COMMAND_ID), "Liquify runs from the eraser as well")
    assert_eq(_machine.active_tool_name, LiquifyScript.TOOL_ID, "putting liquify in hand")

    _bar.preset_box.save_current_as_preset("My Shrink")
    _bar.preset_box.load_preset(INK)
    commands.execute(LiquifyScript.COMMAND_ID)
    assert_eq(_bar.preset_box.selected_preset, "My Shrink", "A preset saved with liquify in hand is the one used last")

    _bar.preset_box.preset_store.delete_preset("My Shrink")
    _bar.preset_box.load_preset(INK)
    assert_true(commands.execute(LiquifyScript.COMMAND_ID), "One deleted since")
    assert_eq(_bar.preset_box.selected_preset, PresetsScript.FIRST, "gives way to Liquify Push")


## A painter's older profile, whose toolbox order, visibility and
## groups name liquify, comes back with none of the three: the row would be a
## Preferences switch for a button nobody builds.
func test_a_profile_naming_the_liquify_tool_loses_its_row() -> void:
    var config := ConfigFile.new()
    config.set_value("meta", "version", 21)
    config.set_value("profile_order", "ToolBoxDocker", ["Brush Tool", "Transform Tool", "Liquify Tool"])
    config.set_value("profile_visibility", "ToolBoxDocker_Liquify Tool", false)
    config.set_value("profile_docker_option", "ToolBoxDocker_groups", [["transform", "liquify"], ["liquify"]])
    SaSettingsMigrations.apply(config, 21)
    assert_eq(config.get_value("profile_order", "ToolBoxDocker"), ["Brush Tool", "Transform Tool"], "The order loses the row")
    assert_false(config.has_section_key("profile_visibility", "ToolBoxDocker_Liquify Tool"), "and its visibility")
    assert_eq(config.get_value("profile_docker_option", "ToolBoxDocker_groups"), [["transform"]], "and the groups their liquify")
    assert_false(SaSettingsLayout.DEFAULT_ORDERS["ToolBoxDocker"].has("Liquify Tool"), "A fresh profile has no such row")
