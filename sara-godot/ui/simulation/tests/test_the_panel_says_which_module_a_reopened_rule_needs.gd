## A document opened where the module of its simulation's rule
## is missing keeps the record, and the panel says which module it needs.
##
## The rule is the simulation suites' test rule, registered under a module of the suite's own
## that the suite takes away between the save and the load. The follower is
## driven by calling `_process`, as the panel suite drives it.
extends "res://tests/test_framework.gd"

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const FRAME := 1.0 / 60.0
const GONE_MODULE := &"k8-panel-gone"

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _host: Node = null
var _docker: ToolOptionsDocker = null
var _follower: SaSimulationPanel = null
var _path: String = ""


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    _surface = Fixtures.make_surface(Vector2i(512, 256))
    _registries = Fixtures.make_registries(_surface)
    var base := BaseModule.new()
    base.register(_registries.context.for_module(base.get_id()))
    var gone := _registries.context.for_module(GONE_MODULE)
    gone.register_simulation_rule(&"shift_right", "Shift Right", "sara/simulation_test_rules", "shift_right", 1)
    _host = Node.new()
    _docker = ToolOptionsDocker.new()
    _host.add_child(_docker)
    _follower = SaSimulationPanel.new(_registries, _docker)
    _host.add_child(_follower)
    _path = ProjectSettings.globalize_path(SaDataRoot.path("k8_panel_needs.sad"))


func after_each() -> void:
    _host.free()
    _surface.get_document().free()
    _surface.easel.free()
    _surface = null
    _registries = null
    DirAccess.remove_absolute(_path)
    SaProblems.pending_refusals = PackedStringArray()


func _frames(count: int) -> void:
    for _i in count:
        _follower._process(FRAME)


func _panel() -> Control:
    return _docker.find_child("SimulationPanel", true, false) as Control


func _needs() -> Label:
    var panel := _panel()
    return panel.find_child("SimulationNeeds", true, false) as Label if panel != null else null


## A paint layer called Simulated, active, with *rule_key* on it, saved and
## opened again into the same document with the layer active once more.
func _reopened(rule_key: StringName, take_away: StringName) -> SaLayer:
    var document := _surface.get_document()
    var layer := SaLayerOps.new(document).add(&"")
    layer.name = "Simulated"
    document.set_active_layer(layer)
    layer.get_or_create_chunk(Vector2i(0, 0))
    SaSimulation.put_on(layer, _registries.simulation_rules.find(rule_key))
    assert_eq(SaExport.save_sad(document, _path, 0), OK, "The document saves")
    if take_away != &"":
        _registries.simulation_rules.unregister_module(take_away)
    assert_eq(SaExport.load_sad(document, _path, _surface.easel.compositor), OK, "and opens again")
    var opened := document.get_node_or_null("Simulated") as SaLayer
    assert_not_null(opened, "with the simulated layer")
    if opened != null:
        document.set_active_layer(opened)
    return opened


func test_the_panel_names_the_module_a_reopened_rule_needs() -> void:
    var layer := _reopened(&"shift_right", GONE_MODULE)
    assert_not_null(SaSimulation.record_of(layer), "The record is kept though its module is gone")
    _frames(1)
    assert_not_null(_panel(), "so the panel stands")
    var needs := _needs()
    assert_not_null(needs, "with a line for what the rule needs")
    if needs == null:
        return
    assert_true(needs.visible, "shown")
    assert_true(needs.text.contains(String(GONE_MODULE)), "naming the module, '%s'" % needs.text)
    var panel: Dictionary = _follower.report().get("panel", {})
    assert_eq(panel.get("needs"), needs.text, "and the state dump says the same")
    assert_eq(_follower.report().get("module"), String(GONE_MODULE), "with the record's module")


func test_a_reopened_rule_whose_module_is_loaded_needs_nothing() -> void:
    _reopened(&"spread", &"")
    _frames(1)
    var needs := _needs()
    assert_not_null(needs, "The panel stands with its line")
    if needs == null:
        return
    assert_false(needs.visible, "hidden")
    assert_eq(needs.text, "", "and empty, for Spread's module is loaded")
    assert_eq(_follower.report().get("panel", {}).get("needs"), "", "as the state dump says")
    assert_eq(_follower.report().get("module"), "sara-base-modules", "and the record names the base module")
