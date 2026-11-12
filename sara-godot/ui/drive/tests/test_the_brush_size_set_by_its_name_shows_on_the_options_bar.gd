## The brush's size set by its name lands on the brush and on the options bar's
## slider, and the slider says the name a binding keeps.
##
## Built the way the app builds it: the modules registered through the door, a
## machine bound to their registry and the real bar over it, as the Backspace
## suite of the options bar builds them. The resolver is handed the machine and
## nothing of the bar, so the slider following is the bar's own reading of the
## tool after `tool_options_moved`.
extends "res://tests/test_framework.gd"

## The machine builds every tool, which needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")

const SIZE := &"tool/brush/radius"

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _host: Node = null
var _bar: ToolOptionsBar = null
var _values: SaAppDrive = null


func before_each() -> void:
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
    _host = Node.new()
    EventBus.add_child(_host)
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar._ready()
    _bar._sync_ui_from_settings()
    var machine := _machine
    _values = SaAppDrive.new(func() -> ToolMachine: return machine)


func after_each() -> void:
    _values = null
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


func _brush_size() -> float:
    return float(_machine.get_tool(&"brush").get("settings").radius)


func _bar_slider() -> FactorSlider:
    return _bar.control_for(&"radius") as FactorSlider


## The ask: the size set by its name, then read on the brush and on the bar.
func test_the_size_set_by_its_name_is_the_brushs_and_the_bars() -> void:
    var slider := _bar_slider()
    assert_not_null(slider, "The bar has a Size slider")
    assert_eq(slider.value_name, SIZE, "The bar's Size slider names the brush's radius")
    assert_eq(SaAppDrive.name_of(slider), SIZE, "The resolver reads the same name off the slider")
    assert_true(_values.can_move(SIZE), "The brush's size can be moved with the brush registered")

    assert_true(_values.write(SIZE, 0.2), "The size is written by its name")
    assert_almost_eq(_brush_size(), 0.2, 1e-6, "The brush holds the size set")
    assert_almost_eq(slider.value, 0.2, 1e-6, "The bar's slider shows the size set")
    assert_almost_eq(_values.read(SIZE), 0.2, 1e-6, "The resolver reads the size back by its name")


## Across its range: the top of a drag is the soft ceiling the Size row's drag
## stops at, the middle is the geometric middle that drag has, and a value
## written past the drag goes on to the hard end as a typed one does.
func test_the_size_moves_across_its_range_as_the_slider_drags() -> void:
    var spread := _values.range_of(SIZE)
    assert_almost_eq(spread.x, ToolMachine.BRUSH_RADIUS_MIN, 1e-9, "The range starts at the smallest brush")
    assert_almost_eq(spread.y, ToolMachine.BRUSH_RADIUS_SOFT_MAX, 1e-9, "The range ends where a drag of the row stops")
    assert_almost_eq(spread.y, _bar_slider().drag_max(), 1e-9, "which is the bar's slider's own ceiling")

    assert_true(_values.write_ratio(SIZE, 1.0), "The size is set at the top of its range")
    assert_almost_eq(_brush_size(), ToolMachine.BRUSH_RADIUS_SOFT_MAX, 1e-6, "The brush is at the top of its range")
    assert_almost_eq(_bar_slider().value, ToolMachine.BRUSH_RADIUS_SOFT_MAX, 1e-6, "So is the bar's slider")

    assert_true(_values.write_ratio(SIZE, 0.5), "The size is set half way")
    var middle := sqrt(ToolMachine.BRUSH_RADIUS_MIN * ToolMachine.BRUSH_RADIUS_SOFT_MAX)
    assert_almost_eq(_brush_size(), middle, 1e-6, "Half way on a geometric row is the geometric mean")
    assert_almost_eq(_values.read_ratio(SIZE), 0.5, 1e-6, "The ratio reads back where it was set")
    var slider := _bar_slider()
    assert_almost_eq(slider.ratio_of_value(slider.value, slider.drag_max()), 0.5, 1e-6, "The bar's drag stands half way too")

    assert_true(_values.write(SIZE, 99.0), "A size past the range is still written")
    assert_almost_eq(_brush_size(), ToolMachine.BRUSH_RADIUS_MAX, 1e-6, "and held to the hard end")


## A name the tools do not know cannot be moved, and nothing is written.
func test_a_name_no_tool_answers_cannot_be_moved() -> void:
    var before := _brush_size()
    for missing: StringName in [&"tool/brush/no_such_key", &"tool/no_such_tool/radius", &"tool/brush", &""]:
        assert_false(_values.can_move(missing), "'%s' cannot be moved" % missing)
        assert_false(_values.write(missing, 0.3), "'%s' writes nothing" % missing)
        assert_true(is_nan(_values.read(missing)), "'%s' reads as nothing" % missing)
    assert_almost_eq(_brush_size(), before, 1e-9, "The brush keeps its size")
