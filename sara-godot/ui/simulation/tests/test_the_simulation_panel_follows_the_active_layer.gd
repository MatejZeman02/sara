## The simulation's panel stands in Tool Options while the
## active layer carries a simulation, its buttons play, pause, step and reset
## it, its slider sets the speed, and the count says where it stands.
##
## The follower is driven by calling `_process` with a delta of the suite's
## own, so a frame is a call and no clock decides a count. The docker is a
## Window, built detached under a plain Node as its own suites build it.
extends "res://tests/test_framework.gd"

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const FRAME := 1.0 / 60.0

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _host: Node = null
var _docker: ToolOptionsDocker = null
var _follower: SaSimulationPanel = null


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    _surface = Fixtures.make_surface(Vector2i(512, 256))
    _registries = Fixtures.make_registries(_surface)
    var base := BaseModule.new()
    base.register(_registries.context.for_module(base.get_id()))
    _host = Node.new()
    _docker = ToolOptionsDocker.new()
    _host.add_child(_docker)
    _follower = SaSimulationPanel.new(_registries, _docker)
    _host.add_child(_follower)


func after_each() -> void:
    _host.free()
    _surface.get_document().free()
    _surface.easel.free()
    _surface = null
    _registries = null


func _frames(count: int) -> void:
    for _i in count:
        _follower._process(FRAME)


func _panel() -> Control:
    return _docker.find_child("SimulationPanel", true, false) as Control


func _press(button_name: String) -> void:
    var button := _panel().find_child(button_name, true, false) as Button
    assert_not_null(button, "The panel holds %s" % button_name)
    if button != null:
        button.pressed.emit()


## A paint layer of its own, active, with Spread on it.
func _simulated() -> SaLayer:
    var document := _surface.get_document()
    var layer := SaLayerOps.new(document).add(&"")
    document.set_active_layer(layer)
    layer.get_or_create_chunk(Vector2i(0, 0))
    SaSimulation.put_on(layer, _registries.simulation_rules.find(&"spread"))
    return layer


func test_the_panel_stands_while_the_active_layer_carries_a_simulation() -> void:
    _frames(1)
    assert_null(_panel(), "No layer with a simulation is active, so no panel stands")
    assert_true(_follower.report().is_empty(), "and the report is empty")
    var layer := _simulated()
    _frames(1)
    var panel := _panel()
    assert_not_null(panel, "Spread on the active layer shows the panel")
    assert_true(_docker._filter_panel == panel, "through `show_filter_panel`")
    for each: String in ["SimulationPlay", "SimulationPause", "SimulationStep", "SimulationReset", "SimulationSpeed"]:
        assert_not_null(panel.find_child(each, true, false), "with %s" % each)
    var report := _follower.report()
    assert_eq(report.get("rule"), "spread", "The report names the rule")
    assert_eq((report.get("panel", {}) as Dictionary).get("count"), "Step 0, paused", "and the count the panel shows")
    SaSimulation.take_off(layer)
    _frames(1)
    assert_true(_docker._filter_panel == null, "Taken off, the panel goes and the rows come back")


func test_play_runs_ten_steps_over_sixty_frames_and_pause_step_and_reset_do_what_they_say() -> void:
    var layer := _simulated()
    var record := SaSimulation.record_of(layer)
    _frames(1)
    _press("SimulationPlay")
    assert_true(record.playing, "Play plays it")
    _frames(60)
    assert_eq(record.steps, 10, "Sixty frames at ten a second count ten steps")
    var report := _follower.report()
    var panel_report: Dictionary = report.get("panel", {})
    assert_eq(panel_report.get("count"), "Step 10, playing", "The count the panel shows is the record's")
    assert_false(panel_report.get("play_enabled"), "and Play is not offered while it plays")
    _press("SimulationPause")
    assert_false(record.playing, "Pause pauses it")
    _frames(60)
    assert_eq(record.steps, 10, "and paused frames count nothing")
    _press("SimulationStep")
    assert_eq(record.steps, 11, "Step runs the rule once")
    _press("SimulationReset")
    assert_eq(record.steps, 0, "Reset counts from nought")
    var slider := _panel().find_child("SimulationSpeed", true, false) as FactorSlider
    slider.step_by_units(20.0)
    assert_eq(record.speed, 30.0, "Twenty units up the slider sets thirty steps a second")
    _press("SimulationPlay")
    _frames(60)
    assert_eq(record.steps, 30, "and sixty frames at thirty a second count thirty")


func test_choosing_another_layer_pauses_the_one_playing() -> void:
    var layer := _simulated()
    var record := SaSimulation.record_of(layer)
    _frames(1)
    _press("SimulationPlay")
    _frames(30)
    assert_eq(record.steps, 5, "It plays five steps")
    var document := _surface.get_document()
    var other := SaLayerOps.new(document).add(&"")
    document.set_active_layer(other)
    _frames(30)
    assert_false(record.playing, "Another layer chosen, it pauses")
    assert_eq(record.steps, 5, "and steps no more")
    assert_true(_docker._filter_panel == null, "and its panel goes")
