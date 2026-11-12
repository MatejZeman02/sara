## The pop-up palette (`PaletteDocker`) carries a brush HUD.
##
## Under the ring, the shown tool's Radius, Opacity and Flow as sliders built
## from the tool's own option specs by key, so a tool shows the rows it
## declares and no others. Each check builds the app's three modules through the
## door and a machine bound to their registry, then opens the palette with that
## machine's tool active and reads the HUD.
##
## The docker is never added to a tree, because a window added to one in a headless run hangs,
## so it is opened the way the engine opens it in one: shown, and then told so
## by its `visibility_changed`, which a window outside a tree does not emit of
## its own. The running app's proof is
## `scenarios/the-pop-up-palette-carries-a-brush-hud.json`.
extends "res://tests/test_framework.gd"

## The machine builds every tool, which needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _palette: PaletteDocker = null

## What the eraser and the brush held before a check moved them, put back after.
var _held: Dictionary = {}


func before_each() -> void:
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
    _held.clear()
    for id: StringName in [&"brush", &"eraser"]:
        for key: StringName in PaletteBrushHud.KEYS:
            _held[[id, key]] = _read(id, key)
    _palette = PaletteDocker.new()
    _palette.visible = false
    _palette.hud.machine = _machine


func after_each() -> void:
    for pair: Array in _held:
        _write(pair[0], pair[1], _held[pair])
    _palette.free()
    _palette = null
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    for module: SaModule in _modules:
        module.unregister(_registries.context)
        _registries.context.for_module(module.get_id()).remove_all_registrations()
    _modules.clear()
    _registries = null


func test_the_eraser_shows_its_own_three_sliders() -> void:
    _machine.set_active_tool(&"eraser")
    _write(&"eraser", &"opacity", 0.4)
    _write(&"eraser", &"flow", 0.7)
    _open()
    var hud := _palette.hud
    assert_eq(String(_shown().get("tool", "")), "eraser", "the HUD reads the eraser, the tool in hand")
    for key: StringName in PaletteBrushHud.KEYS:
        var slider: FactorSlider = hud.sliders[key]
        assert_true(slider.visible, "the eraser declares %s, so its row shows" % key)
        assert_almost_eq(slider.value, float(_read(&"eraser", key)), 1e-6, "and the %s row holds the eraser's own value" % key)
    assert_almost_eq(hud.sliders[&"opacity"].value, 0.4, 1e-6, "the eraser's opacity, not the brush's")
    assert_eq(hud.sliders[&"radius"].prefix, "Radius: ", "each row is worded by the eraser's spec")
    assert_eq(_palette.hud.get_parent(), _palette.ring.get_parent(), "the HUD is in the palette's column")
    assert_true(_palette.hud.get_index() > _palette.ring.get_index(), "under the ring")


func test_a_move_writes_the_eraser_and_says_so_on_the_bus() -> void:
    _machine.set_active_tool(&"eraser")
    _open()
    var brush_radius: float = _read(&"brush", &"radius")
    var heard: Array[int] = [0]
    var listen := func() -> void: heard[0] += 1
    EventBus.tool_options_moved.connect(listen)
    var radius: FactorSlider = _palette.hud.sliders[&"radius"]
    var wanted := clampf(float(_read(&"eraser", &"radius")) * 2.0, radius.min_value, radius.max_value)
    # What a drag does and what the `control` step does: the value, then the
    # slider's own signal.
    radius.set_value_no_signal(wanted)
    radius.value_changed.emit(radius.value)
    EventBus.tool_options_moved.disconnect(listen)
    assert_almost_eq(float(_read(&"eraser", &"radius")), wanted, 1e-6, "the move writes the eraser's radius")
    assert_almost_eq(float(_read(&"brush", &"radius")), brush_radius, 1e-6, "and leaves the brush's alone")
    assert_eq(heard[0], 1, "it says so on the bus once, which the bar and the docker read")


func test_a_tool_with_no_flow_shows_two_sliders() -> void:
    _machine.set_active_tool(NoiseModuleScript.TOOL_ID)
    _open()
    var shown: Array = []
    for row: Dictionary in _shown()["rows"]:
        if row["visible"]:
            shown.append(row["key"])
    assert_eq(String(_shown()["tool"]), String(NoiseModuleScript.TOOL_ID), "the HUD reads the noise engine")
    assert_eq(shown, ["radius", "opacity"], "which declares no Flow, so two sliders show")
    assert_false(_palette.hud.sliders[&"flow"].visible, "and the Flow row hides")


func test_a_change_made_elsewhere_shows_the_next_time_the_palette_opens() -> void:
    _machine.set_active_tool(&"brush")
    _open()
    var before: float = _palette.hud.sliders[&"radius"].value
    _palette.visible = false
    # The bracket key's path, which moves the brush and tells the bus while the
    # palette is away.
    SaShortcutKeys.nudge_brush_radius(_machine, 0.01)
    var after := float(_read(&"brush", &"radius"))
    assert_false(is_equal_approx(after, before), "the key moved the brush")
    _open()
    assert_almost_eq(_palette.hud.sliders[&"radius"].value, after, 1e-6, "and the palette shows the new radius when it opens")


## Shows the palette and tells it so, which is what the engine does for a
## window in a tree.
func _open() -> void:
    _palette.visible = true
    _palette.visibility_changed.emit()


func _shown() -> Dictionary:
    return _palette.hud.report(Vector2.ZERO)


func _spec(id: StringName, key: StringName) -> SaOptionSpec:
    for spec: SaOptionSpec in _machine.get_descriptor(id).options:
        if spec != null and spec.key == key:
            return spec
    return null


func _read(id: StringName, key: StringName) -> Variant:
    return ToolOptionControls.read_spec(_spec(id, key), _machine.get_tool(id))


func _write(id: StringName, key: StringName, value: Variant) -> void:
    ToolOptionControls.write_spec(_spec(id, key), value, _machine.get_tool(id))
