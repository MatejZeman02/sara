## Backspace over a brush's slider puts back the value the loaded preset gives
## that option.
##
## Flow once read 50 per cent before a Backspace and at nought
## after, and a stroke laid after it left the layer clear. A brush slider is
## built with a range and no value, the loaded preset's value arrives after the
## slider is in the tree, and `FactorSlider` took the value it held at `_ready`
## as the one Backspace restores, which was the range's floor.
##
## Everything here is built the way the app builds it: the modules registered
## through the door, a machine bound to their registry, the real bar for the
## preset group and a second `ToolOptionControls` standing for the Tool Options
## docker, because Flow and Hardness are on the docker and not on the bar.
extends "res://tests/test_framework.gd"

## The machine builds every tool, which needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## The four sliders under test, and what Paint and Ink hold for each, none of
## them a default of the settings and none of them a slider's range floor.
const KEYS: Array[StringName] = [&"radius", &"opacity", &"flow", &"hardness"]
const PAINT := {&"radius": 0.045, &"opacity": 0.8, &"flow": 0.5, &"hardness": 0.35}
const INK := {&"radius": 0.12, &"opacity": 0.6, &"flow": 0.9, &"hardness": 0.95}

const CANVAS_MIN := 1000.0

static var scratch_dir: String = SaDataRoot.path("test_d100_presets")

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _host: Node = null
var _bar: ToolOptionsBar = null
var _docker: ToolOptionControls = null


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


func after_each() -> void:
    _docker = null
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


## The bar over a store holding Paint and Ink, and the docker's controls beside
## it built from the same machine, both shown the brush before any preset loads.
func _surfaces_over_the_store() -> void:
    _host = Node.new()
    EventBus.add_child(_host)
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_dir
    _bar.preset_store.save_preset("Paint", _settings_holding(PAINT))
    _bar.preset_store.save_preset("Ink", _settings_holding(INK))
    _bar._ready()
    var rows := Control.new()
    _host.add_child(rows)
    _docker = ToolOptionControls.new(rows)
    _docker.for_docker = true
    _docker.binding.follow(_machine)
    _docker.sync(_machine.get_tool(&"brush"), &"brush", CANVAS_MIN)


func _settings_holding(values: Dictionary) -> Resource:
    var settings: Resource = StampSettingsScript.new()
    settings.radius = values[&"radius"]
    settings.opacity = values[&"opacity"]
    settings.flow.value = values[&"flow"]
    settings.hardness.value = values[&"hardness"]
    return settings


## The slider of *key* on the docker's controls, which holds all four.
func _slider(key: StringName) -> FactorSlider:
    return _docker.control(key) as FactorSlider


## What a hand does: the value moves and the slider says so, which is what
## writes it to the tool.
func _move(slider: FactorSlider, to: float) -> void:
    slider.value = to
    slider.value_changed.emit(to)


func _backspace_over(slider: FactorSlider) -> void:
    var key := InputEventKey.new()
    key.keycode = KEY_BACKSPACE
    key.pressed = true
    slider._on_mouse_entered()
    slider._unhandled_key_input(key)
    slider._on_mouse_exited()


## The ask: Paint loaded, each of the four moved, Backspace over each, and each
## reads back at Paint's value on the slider and on the tool behind it.
func test_backspace_puts_each_slider_back_at_paints_value() -> void:
    _surfaces_over_the_store()
    assert_true(_bar.preset_box.load_preset("Paint"), "Paint loads")
    var brush := _machine.get_tool(&"brush")

    for key in KEYS:
        var slider := _slider(key)
        assert_not_null(slider, "%s has a slider on the docker" % key)
        _move(slider, 0.97 if key != &"radius" else 0.2)
        _backspace_over(slider)
        assert_almost_eq(slider.value, PAINT[key], 1e-5, "Backspace over %s puts Paint's value back on the slider" % key)
        assert_almost_eq(float(_docker.read(key, brush, &"brush")), PAINT[key], 1e-5, "and on the brush behind it")


## The bar's own two, which the walk's second probe pressed Backspace over.
func test_the_bars_radius_and_opacity_answer_the_same() -> void:
    _surfaces_over_the_store()
    assert_true(_bar.preset_box.load_preset("Paint"), "Paint loads")
    for key: StringName in [&"radius", &"opacity"]:
        var slider := _bar.control_for(key) as FactorSlider
        assert_not_null(slider, "The bar shows a %s slider" % key)
        _move(slider, 0.01)
        _backspace_over(slider)
        assert_almost_eq(slider.value, PAINT[key], 1e-5, "Backspace over the bar's %s puts Paint's value back" % key)


## "A preset loaded later moves the default with it."
func test_a_preset_loaded_later_moves_the_default() -> void:
    _surfaces_over_the_store()
    assert_true(_bar.preset_box.load_preset("Paint"), "Paint loads")
    assert_true(_bar.preset_box.load_preset("Ink"), "and Ink after it")
    for key in KEYS:
        var slider := _slider(key)
        _move(slider, 0.3)
        _backspace_over(slider)
        assert_almost_eq(slider.value, INK[key], 1e-5, "Backspace over %s puts Ink's value back, the preset in the hand" % key)


## A drag, a tool switch and a canvas resize all `sync` the controls, and a
## default that followed the sync would be whatever the painter had just moved
## the slider to.
func test_a_sync_after_a_drag_leaves_the_default_where_the_preset_put_it() -> void:
    _surfaces_over_the_store()
    assert_true(_bar.preset_box.load_preset("Paint"), "Paint loads")
    var slider := _slider(&"flow")
    _move(slider, 0.1)
    _docker.sync(_machine.get_tool(&"brush"), &"brush", CANVAS_MIN * 2.0)
    _backspace_over(slider)
    assert_almost_eq(slider.value, PAINT[&"flow"], 1e-5, "Backspace still answers Paint after a sync over the moved value")


## The key the brush and the eraser share has a default for each, so Backspace
## under the eraser is not Paint's radius written onto the eraser.
func test_the_eraser_keeps_a_default_of_its_own() -> void:
    _surfaces_over_the_store()
    var eraser := _machine.get_tool(&"eraser")
    var radius_at_first := float(eraser.settings.radius)
    assert_true(_bar.preset_box.load_preset("Paint"), "Paint loads onto the brush")
    var slider := _slider(&"radius")

    _docker.sync(eraser, &"eraser", CANVAS_MIN)
    _move(slider, 0.2)
    _backspace_over(slider)
    assert_almost_eq(slider.value, radius_at_first, 1e-5, "Backspace under the eraser puts the eraser's own radius back")

    _docker.sync(_machine.get_tool(&"brush"), &"brush", CANVAS_MIN)
    _move(slider, 0.2)
    _backspace_over(slider)
    assert_almost_eq(slider.value, PAINT[&"radius"], 1e-5, "and back under the brush it is Paint's again")


func _clear(path: String) -> void:
    if not DirAccess.dir_exists_absolute(path):
        return
    for file_name in DirAccess.get_files_at(path):
        DirAccess.remove_absolute(path.path_join(file_name))
    DirAccess.remove_absolute(path)
