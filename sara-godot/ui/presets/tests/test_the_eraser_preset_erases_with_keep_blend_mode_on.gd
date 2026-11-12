## The Eraser preset erases with Keep Blend Mode on.
##
## Picking the Eraser preset with the brush in
## hand once painted a black block, because Keep Blend Mode kept the brush's own
## mode and the Eraser's Erase never landed. Keep Blend Mode now keeps the
## painter's mode across presets that paint only, an erasing preset sets Erase
## whatever the switch says, and `SaBrushPresetErase` gives the mode back.
##
## Built the way the app builds it: the modules registered through the door, a
## machine bound to their registry, the real bar with the shipped Eraser recipe
## in its store, and the compositor handed the built-in blend modes so a wash
## erase lands under the erase rule at the commit. The picture is
## `scenarios/the-eraser-preset-erases-with-keep-blend-mode-on.json`.
extends "res://tests/test_framework.gd"

## Paints and reads the layer back.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

const CANVAS := Vector2i(256, 256)
const MULTIPLY := &"multiply"

static var scratch_dir: String = SaDataRoot.path("test_eraser_keep_blend")

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _host: Node = null
var _bar: ToolOptionsBar = null
var _keep_was: bool = false


func before_each() -> void:
    _clear(scratch_dir)
    _keep_was = SaSettings.keep_blend_mode
    _surface = Fixtures.make_surface(CANVAS)
    _registries = Fixtures.make_registries(_surface)
    _surface.easel.compositor.set_registry(_registries.blend_modes)
    _modules.clear()
    for script: GDScript in [StampModuleScript, BaseModuleScript]:
        var module: SaModule = script.new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)
    _machine.set_active_tool(&"brush")


func after_each() -> void:
    SaSettings.keep_blend_mode = _keep_was
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


## Empties the suite's own folder and nothing else. A run where the store failed
## to parse left *path* empty, which `get_files_at` reads as the project's root,
## and the cleanup took every file at the top of `sara-godot` with it.
func _clear(path: String) -> void:
    if not path.ends_with("test_eraser_keep_blend") or not DirAccess.dir_exists_absolute(path):
        return
    for file_name: String in DirAccess.get_files_at(path):
        DirAccess.remove_absolute(path.path_join(file_name))
    DirAccess.remove_absolute(path)


## "A suite turns Keep Blend Mode on with the brush in Multiply, loads Eraser
## and reads Erase, paints a stroke over paint and reads the alpha go down, then
## picks Paint and reads Multiply back."
func test_the_eraser_erases_over_paint_with_keep_on_and_multiply_comes_back() -> void:
    var presets := _bar_over_the_shipped_eraser()
    _bar.keep_blend_chk.button_pressed = true
    assert_true(_bar.preset_store.keep_blend_mode, "The Keep toggle turns Keep Blend Mode on")
    var brush := _machine.get_tool(&"brush") as StateBrushScript
    brush.settings.blend_mode = MULTIPLY

    assert_true(presets.load_preset("Eraser"), "The Eraser loads")
    assert_eq(brush.settings.blend_mode, SaLayer.BLEND_MODE.ERASE, "and the brush reads Erase, Keep Blend Mode or not")

    var layer := SaLayerOps.new(_surface.get_document()).add()
    layer.fill(Color.RED)
    var middle := Vector2i(CANVAS.x >> 1, CANVAS.y >> 1)
    var before := _alpha_at(layer, middle)
    assert_almost_eq(before, 1.0, 1e-3, "The layer starts painted")
    _stroke(brush, Vector2(40.0, middle.y), Vector2(CANVAS.x - 40.0, middle.y))
    var after := _alpha_at(layer, middle)
    assert_true(after < before - 0.5, "The stroke takes the paint away: alpha %.3f after %.3f" % [after, before])
    assert_almost_eq(_alpha_at(layer, Vector2i(middle.x, 8)), 1.0, 1e-3, "and leaves what it did not cross")

    _machine.set_active_tool(&"brush")
    assert_eq(brush.settings.blend_mode, MULTIPLY, "The pick of Paint gives Multiply back")
    assert_eq(presets.selected_preset, "", "and the Eraser is no longer in hand")


## The shipped table's own recipe, so the suite meets the Eraser the painter did.
func _bar_over_the_shipped_eraser() -> ToolOptionsPresets:
    _host = Node.new()
    EventBus.add_child(_host)
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_dir
    for entry: Dictionary in SaShippedPresets.entries():
        if String(entry["name"]) == "Eraser":
            _bar.preset_store.save_preset("Eraser", SaShippedPresets.build(StateBrushScript.BrushSettingsScript, entry))
    assert_true(_bar.preset_store.has_preset("Eraser"), "The shipped Eraser is in the store")
    _bar._ready()
    return _bar.preset_box


## A press at *from*, motions to *to* at full pressure and the release.
func _stroke(brush: ToolState, from: Vector2, to: Vector2, steps: int = 40) -> void:
    var view := _surface.view
    view.mouse_position = from
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = from
    brush.handle_input(press)
    for i in range(1, steps + 1):
        view.mouse_position = from.lerp(to, float(i) / float(steps))
        var motion := InputEventMouseMotion.new()
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.position = view.mouse_position
        motion.pressure = 1.0
        brush.handle_input(motion)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    brush.handle_input(release)


## The alpha of *layer* at document pixel *at*, read off its chunk's texels.
func _alpha_at(layer: SaLayer, at: Vector2i) -> float:
    for grid_pos: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid_pos]
        var edge := chunk.pixel_size()
        var local := at - grid_pos * edge
        if local.x < 0 or local.y < 0 or local.x >= edge or local.y >= edge:
            continue
        var texture := chunk.albedo()
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
        var image_format := Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF
        return Image.create_from_data(edge, edge, false, image_format, bytes).get_pixel(local.x, local.y).a
    return 0.0
