## The Pop-up Palette's Eraser gives the blend mode back.
##
## The Eraser slot loads a preset that carries the Erase blend mode, and the
## settings kept it for good: the Paint tool in the toolbox ran no load, the
## Erase toggle is a separate switch, and the dropdown went on saying Erase while
## a stroke took paint away. The bar's preset group now remembers a load that
## took the brush to Erase from another mode, and puts the mode back when the
## painter picks a painting tool that is not the Eraser, or turns the toggle off.
##
## Everything is built the way the app builds it: the modules registered through
## the door, a machine bound to their registry and the real bar for the preset
## group. The scenario of the same name strikes the whole walk over the booted app.
extends "res://tests/test_framework.gd"

## The machine builds every tool, which needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

const ERASE := &"erase"
const NORMAL := &"normal"
const MULTIPLY := &"multiply"

static var scratch_dir: String = SaDataRoot.path("test_s18_eraser_blend")

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _host: Node = null
var _bar: ToolOptionsBar = null
## What `EventBus.preset_loaded` announced since the bar was built, in order.
var _announced: Array[String] = []


func before_each() -> void:
    _clear(scratch_dir)
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
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
    _announced.clear()
    EventBus.preset_loaded.connect(_on_preset_loaded)


func after_each() -> void:
    if EventBus.preset_loaded.is_connected(_on_preset_loaded):
        EventBus.preset_loaded.disconnect(_on_preset_loaded)
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


func _on_preset_loaded(stored_name: String) -> void:
    _announced.append(stored_name)


func _clear(path: String) -> void:
    if not DirAccess.dir_exists_absolute(path):
        return
    for file_name: String in DirAccess.get_files_at(path):
        DirAccess.remove_absolute(path.path_join(file_name))
    DirAccess.remove_absolute(path)


## The bar over a store holding an eraser, a second one and a pencil, shown the
## brush. The first two carry the Erase blend mode and the pencil does not.
func _bar_over_the_store() -> ToolOptionsPresets:
    _host = Node.new()
    EventBus.add_child(_host)
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_dir
    _bar.preset_store.save_preset("Eraser", _recipe(ERASE))
    _bar.preset_store.save_preset("Soft Eraser", _recipe(ERASE))
    _bar.preset_store.save_preset("Pencil", _recipe(NORMAL))
    _bar._ready()
    return _bar.preset_box


func _recipe(mode: StringName) -> Resource:
    var recipe: Resource = StampSettingsScript.new()
    recipe.blend_mode = mode
    return recipe


func _brush_blend() -> StringName:
    return _machine.get_tool(&"brush").settings.blend_mode


func _set_brush_blend(mode: StringName) -> void:
    _machine.get_tool(&"brush").settings.blend_mode = mode


## The ask: the Eraser slot, then the Paint tool, and the dropdown reads Normal
## again with no preset claiming the brush.
func test_the_paint_tool_after_the_eraser_slot_paints_with_normal() -> void:
    var presets := _bar_over_the_store()
    assert_true(presets.load_preset("Eraser"), "The Eraser slot loads")
    assert_eq(_brush_blend(), ERASE, "and the brush erases")
    assert_eq(presets.selected_preset, "Eraser", "with the Eraser in the hand")

    _announced.clear()
    _machine.set_active_tool(&"brush")
    assert_eq(_brush_blend(), NORMAL, "The Paint tool, picked again, puts Normal back")
    assert_eq(presets.selected_preset, "", "and the Eraser slot is no longer in use")
    assert_eq(_announced, [""] as Array[String], "which every surface hears once as the brush put on no preset")
    assert_eq(_bar.read_option(&"blend_mode"), NORMAL, "and the bar reads Normal off it, the dropdown on the scenario's shot")


func test_the_mode_the_brush_had_comes_back_not_normal() -> void:
    var presets := _bar_over_the_store()
    _set_brush_blend(MULTIPLY)
    presets.load_preset("Eraser")
    assert_eq(_brush_blend(), ERASE, "The eraser took Multiply away")
    _machine.set_active_tool(&"brush")
    assert_eq(_brush_blend(), MULTIPLY, "and the pick of the Paint tool gives Multiply back")


func test_the_eraser_tool_gives_nothing_back_and_the_paint_tool_after_it_does() -> void:
    var presets := _bar_over_the_store()
    presets.load_preset("Eraser")
    _machine.set_active_tool(&"eraser")
    assert_eq(_brush_blend(), ERASE, "The Eraser tool paints on settings of its own, so the brush's mode stays")
    assert_eq(presets.selected_preset, "Eraser", "and the preset stays in the hand")
    _machine.set_active_tool(&"brush")
    assert_eq(_brush_blend(), NORMAL, "and the Paint tool after it gives the mode back")


func test_a_tool_that_does_not_paint_gives_nothing_back() -> void:
    var presets := _bar_over_the_store()
    presets.load_preset("Eraser")
    _machine.set_active_tool(&"hand")
    assert_eq(_brush_blend(), ERASE, "The Hand tool leaves the brush as it is")
    assert_eq(presets.selected_preset, "Eraser", "and the preset in the hand")


## A held Space swaps to the Hand and back through `tool_changed` and no pick, and
## a painter panning has not chosen to stop erasing.
func test_a_tool_changed_that_nobody_picked_gives_nothing_back() -> void:
    var presets := _bar_over_the_store()
    presets.load_preset("Eraser")
    EventBus.tool_changed.emit("brush")
    assert_eq(_brush_blend(), ERASE, "A swap back to the brush is not a pick")
    assert_eq(presets.selected_preset, "Eraser", "and the preset stays in the hand")


func test_the_erase_toggle_going_off_gives_the_mode_back() -> void:
    var presets := _bar_over_the_store()
    presets.load_preset("Eraser")
    var brush := _machine.get_tool(&"brush")
    brush.set(&"eraser_toggled", true)
    assert_eq(_brush_blend(), ERASE, "Turned on, nothing changes")
    assert_eq(presets.selected_preset, "Eraser", "and the Eraser is still in the hand")
    brush.set(&"eraser_toggled", false)
    assert_eq(_brush_blend(), NORMAL, "Turned off, the brush paints with Normal again")
    assert_eq(presets.selected_preset, "", "and the Eraser slot goes dark")


## Chosen in the dropdown with no load behind it, Erase is the painter's.
func test_an_erase_chosen_by_hand_is_never_touched() -> void:
    var presets := _bar_over_the_store()
    _bar.write_option(&"blend_mode", ERASE)
    assert_eq(_brush_blend(), ERASE, "Erase picked in the dropdown")
    presets.load_preset("Eraser")
    _machine.set_active_tool(&"brush")
    assert_eq(_brush_blend(), ERASE, "stays through a load of the Eraser and a pick of the Paint tool")
    assert_eq(presets.selected_preset, "Eraser", "with the Eraser in the hand")
    _bar.write_option(&"blend_mode", ERASE)
    _machine.get_tool(&"brush").set(&"eraser_toggled", true)
    _machine.get_tool(&"brush").set(&"eraser_toggled", false)
    assert_eq(_brush_blend(), ERASE, "and through the toggle going off")


func test_erase_picked_by_hand_after_the_load_keeps_it_and_the_preset() -> void:
    var presets := _bar_over_the_store()
    presets.load_preset("Eraser")
    _bar.write_option(&"blend_mode", ERASE)
    _machine.set_active_tool(&"brush")
    assert_eq(_brush_blend(), ERASE, "Erase picked by hand after the load is the painter's now")
    assert_eq(presets.selected_preset, "Eraser", "and it is the mode the preset carries, so it stays in the hand")


func test_another_mode_picked_by_hand_puts_the_preset_down() -> void:
    var presets := _bar_over_the_store()
    presets.load_preset("Eraser")
    _announced.clear()
    _bar.write_option(&"blend_mode", MULTIPLY)
    assert_eq(presets.selected_preset, "", "A mode the preset does not carry ends the preset's claim")
    assert_eq(_announced, [""] as Array[String], "which the Pop-up Palette and the grid hear")
    _machine.set_active_tool(&"brush")
    assert_eq(_brush_blend(), MULTIPLY, "and the pick of the Paint tool leaves the painter's mode")


func test_the_docker_writing_the_mode_is_heard_too() -> void:
    var presets := _bar_over_the_store()
    presets.load_preset("Eraser")
    _set_brush_blend(MULTIPLY)
    _bar.show_written_option(&"blend_mode", MULTIPLY)
    assert_eq(presets.selected_preset, "", "A mode written on the Tool Options docker puts the preset down")
    _machine.set_active_tool(&"brush")
    assert_eq(_brush_blend(), MULTIPLY, "and nothing is given back over it")


## Keep blend no longer cancels an eraser: the load sets
## Erase and owes the mode back as it does with the switch off. The walk with a
## stroke over paint is `test_the_eraser_preset_erases_with_keep_blend_mode_on`.
func test_keep_blend_still_lets_the_eraser_erase_and_gives_the_mode_back() -> void:
    var presets := _bar_over_the_store()
    _bar.preset_store.keep_blend_mode = true
    _set_brush_blend(MULTIPLY)
    presets.load_preset("Eraser")
    assert_eq(_brush_blend(), ERASE, "With Keep blend on the Eraser still erases")
    _machine.set_active_tool(&"brush")
    assert_eq(_brush_blend(), MULTIPLY, "and the pick of the Paint tool gives Multiply back")


func test_keep_blend_keeps_the_mode_across_a_preset_that_paints() -> void:
    var presets := _bar_over_the_store()
    _bar.preset_store.keep_blend_mode = true
    _set_brush_blend(MULTIPLY)
    presets.load_preset("Pencil")
    assert_eq(_brush_blend(), MULTIPLY, "The pencil leaves the painter's Multiply")
    _bar.write_option(&"blend_mode", NORMAL)
    assert_eq(presets.selected_preset, "Pencil", "and a mode picked by hand does not put it down, for it never set the mode")


func test_a_second_eraser_keeps_the_first_loads_memory() -> void:
    var presets := _bar_over_the_store()
    presets.load_preset("Eraser")
    presets.load_preset("Soft Eraser")
    assert_eq(_brush_blend(), ERASE, "A second eraser still erases")
    _machine.set_active_tool(&"brush")
    assert_eq(_brush_blend(), NORMAL, "and the pick gives back the mode from before the first")


func test_a_preset_that_paints_after_the_eraser_ends_the_debt() -> void:
    var presets := _bar_over_the_store()
    presets.load_preset("Eraser")
    presets.load_preset("Pencil")
    assert_eq(_brush_blend(), NORMAL, "The pencil carries Normal")
    _set_brush_blend(ERASE)
    _machine.set_active_tool(&"brush")
    assert_eq(_brush_blend(), ERASE, "so an Erase put on the brush after it is not the eraser's to take back")


func test_new_preset_ends_the_debt() -> void:
    var presets := _bar_over_the_store()
    presets.load_preset("Eraser")
    presets.new_preset()
    assert_eq(_brush_blend(), NORMAL, "New puts the defaults on the brush, Normal among them")
    _set_brush_blend(ERASE)
    _machine.set_active_tool(&"brush")
    assert_eq(_brush_blend(), ERASE, "and nothing is owed after it")
