## Picking a brush preset puts the brush in the hand.
##
## With the lasso out, picking Inked Pen in Brush Presets must not leave the
## lasso in the hand, where the next press would start a selection. The bar shows the brush's
## settings under a tool that keeps none, so the preset group read the brush's
## engine off them and asked for no switch, and the bar's switch looked for an
## engine among the lasso's, which has none.
##
## Everything here is built the way the app builds it: the three modules
## registered through the door, a machine bound to their registry, and the real
## bar asked what the docker's cell asks it, `load_preset`.
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

## The sizes the two presets are stored at, neither of which is a default.
const INK_RADIUS := 0.31
const GRAIN_RADIUS := 0.07

static var scratch_dir: String = SaDataRoot.path("test_n25_presets")

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _host: Node = null
var _bar: ToolOptionsBar = null


func before_each() -> void:
    _clear(scratch_dir)
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    _modules.clear()
    for script: GDScript in [StampModuleScript, BaseModuleScript, NoiseModuleScript]:
        var module: SaModule = script.new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)


func after_each() -> void:
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


## The bar in the tree over a store holding a stamp preset and a noise preset,
## each of a size the settings do not start at.
func _bar_over_the_store() -> void:
    _host = Node.new()
    EventBus.add_child(_host)
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_dir
    var ink: Resource = StampSettingsScript.new()
    ink.radius = INK_RADIUS
    _bar.preset_store.save_preset("Ink", ink)
    var grain: Resource = NoiseSettingsScript.new()
    grain.radius = GRAIN_RADIUS
    _bar.preset_store.save_preset("Grain", grain)
    _bar._ready()


func _radius_in_hand() -> float:
    return float(_machine.active_tool.get("settings").radius)


## The lasso in hand: Ink lands on the brush, and the brush is
## what the next press reaches.
func test_a_stamp_preset_under_the_lasso_puts_the_brush_in_the_hand() -> void:
    _machine.set_active_tool(&"lasso")
    _bar_over_the_store()
    assert_eq(_machine.active_tool_name, &"lasso", "The lasso is in the hand before the pick")
    assert_true(_bar.preset_box.takes_no_presets(), "and it takes no presets")

    assert_true(_bar.preset_box.load_preset("Ink"), "The pick loads")
    assert_eq(_machine.active_tool_name, &"brush", "and the brush is in the hand")
    assert_true(_machine.active_tool is StateBrushScript, "on the stamp engine")
    assert_almost_eq(_radius_in_hand(), INK_RADIUS, 1e-6, "holding the preset's size")
    assert_eq(_bar.shown_tool_id(), &"brush", "which the bar shows now")
    assert_eq(_bar.preset_box.selected_preset, "Ink", "and the preset is the one marked")


## The same under the eyedropper, which keeps no settings either.
func test_a_stamp_preset_under_the_eyedropper_puts_the_brush_in_the_hand() -> void:
    _machine.set_active_tool(&"eyedropper")
    _bar_over_the_store()
    assert_true(_bar.preset_box.load_preset("Ink"), "The pick loads")
    assert_eq(_machine.active_tool_name, &"brush", "and the brush is in the hand")
    assert_almost_eq(_radius_in_hand(), INK_RADIUS, 1e-6, "holding the preset's size")


## A noise preset under the lasso reaches the brush's second engine, the way a
## pick under the brush does.
func test_a_noise_preset_under_the_lasso_puts_the_noise_engine_in_the_hand() -> void:
    _machine.set_active_tool(&"lasso")
    _bar_over_the_store()
    assert_true(_bar.preset_box.load_preset("Grain"), "The pick loads")
    assert_eq(_machine.active_tool_name, NoiseModuleScript.TOOL_ID, "and the noise engine is in the hand")
    assert_almost_eq(_radius_in_hand(), GRAIN_RADIUS, 1e-6, "holding the preset's size")


## The eraser takes stamp presets itself, so the pick changes its settings and
## not the tool.
func test_a_stamp_preset_under_the_eraser_leaves_the_eraser_in_the_hand() -> void:
    _machine.set_active_tool(&"eraser")
    _bar_over_the_store()
    assert_false(_bar.preset_box.takes_no_presets(), "The eraser takes presets")
    assert_true(_bar.preset_box.load_preset("Ink"), "The pick loads")
    assert_eq(_machine.active_tool_name, &"eraser", "and the eraser stays in the hand")
    assert_almost_eq(_radius_in_hand(), INK_RADIUS, 1e-6, "holding the preset's size")


## The brush keeps today's behaviour both ways: a stamp preset stays on the
## stamp, and a noise preset moves to the noise engine.
func test_the_brush_keeps_its_own_switch() -> void:
    _machine.set_active_tool(&"brush")
    _bar_over_the_store()
    assert_false(_bar.preset_box.takes_no_presets(), "The brush takes presets")
    assert_true(_bar.preset_box.load_preset("Ink"), "A stamp preset loads")
    assert_eq(_machine.active_tool_name, &"brush", "with the brush in the hand")
    assert_true(_bar.preset_box.load_preset("Grain"), "A noise preset loads")
    assert_eq(_machine.active_tool_name, NoiseModuleScript.TOOL_ID, "and the noise engine takes the hand")


## A preset whose engine no registered tool takes leaves the tool alone. The
## store refuses to copy it onto the brush's settings, as it always did, and the
## lasso is still in the hand for the painter to see why.
func test_a_preset_no_tool_takes_leaves_the_lasso_in_the_hand() -> void:
    _machine.set_active_tool(&"lasso")
    _bar_over_the_store()
    var ghost: Resource = StampSettingsScript.new()
    _bar.preset_store.save_preset("Ghost", ghost)
    var stored: Resource = _bar.preset_store.load_preset("Ghost")
    stored.set_meta(SaPresetMeta.ENGINE_META, &"ghost")
    assert_eq(ResourceSaver.save(stored, scratch_dir.path_join("Ghost.tres")), OK, "A preset of an engine nobody has is written")
    _bar.preset_store.forget_tags()
    assert_eq(_bar.preset_store.engine_for("Ghost"), &"ghost", "and reads as that engine")

    assert_false(_bar.preset_box.load_preset("Ghost"), "The pick is refused")
    assert_eq(_machine.active_tool_name, &"lasso", "and the lasso stays in the hand")


func _clear(path: String) -> void:
    if not DirAccess.dir_exists_absolute(path):
        return
    for file_name in DirAccess.get_files_at(path):
        DirAccess.remove_absolute(path.path_join(file_name))
    DirAccess.remove_absolute(path)
