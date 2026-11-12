## A blending mode command moves the tool in hand of the document in front,
## never the first document's.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every open document holds a tool machine of its own. A pick or a step of the
## blending mode moves the machine of the surface whose easel is in front, the
## way E toggles the eraser there, so a painter who took up the Eraser on a
## second document never finds the first one's Brush multiplying.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const BlendModeCommands = preload("res://core/loader/skeleton_blend_mode_commands.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

var _first: SaSurface = null
var _second: SaSurface = null
var _registries: SaRegistries = null
var _module: SaModule = null
var _first_machine: ToolMachine = null
var _second_machine: ToolMachine = null
## The surface whose easel the context reports in front.
var _front: SaSurface = null


func before_each() -> void:
    _first = Fixtures.make_surface()
    _second = Fixtures.make_surface()
    _front = _second
    _registries = SaRegistries.new()
    _registries.build_context(
        func() -> SaEasel: return _front.easel if _front != null else null, func() -> Array: return [_first, _second]
    )
    _registries.register_builtins()
    _module = load("res://modules/sara-base-modules/stamp-brush/module.gd").new()
    _module.register(_registries.context.for_module(_module.get_id()))
    _first_machine = _machine(_first, &"brush")
    _second_machine = _machine(_second, &"eraser")


func after_each() -> void:
    for machine: ToolMachine in [_first_machine, _second_machine]:
        for tool_id: StringName in [&"brush", &"eraser"]:
            var settings := _settings(machine, tool_id)
            if settings != null:
                settings.set(&"blend_mode", &"erase" if tool_id == &"eraser" else &"normal")
    _module.unregister(_registries.context)
    _module = null
    _first.tool_machine = null
    _second.tool_machine = null
    Fixtures.teardown(_first, _first_machine)
    Fixtures.teardown(_second, _second_machine)
    _first_machine = null
    _second_machine = null
    _first = null
    _second = null
    _front = null
    _registries = null


func _machine(surface: SaSurface, tool_id: StringName) -> ToolMachine:
    var machine := ToolMachine.new()
    machine.name = "ToolMachine"
    machine._ready()
    machine.bind(surface, _registries.tools)
    machine.set_active_tool(tool_id)
    surface.tool_machine = machine
    return machine


func _settings(machine: ToolMachine, tool_id: StringName) -> Resource:
    var tool: Object = machine.get_tool(tool_id)
    return tool.get(&"settings") as Resource if tool != null else null


func _mode(machine: ToolMachine, tool_id: StringName) -> StringName:
    return StringName(_settings(machine, tool_id).get(&"blend_mode"))


func test_the_two_documents_start_as_the_probe_found_them() -> void:
    assert_eq(_first_machine.active_tool_name, &"brush", "The first document has the Brush in hand")
    assert_eq(_second_machine.active_tool_name, &"eraser", "and the second, in front, the Eraser")
    assert_eq(_mode(_first_machine, &"brush"), &"normal", "The first document's Brush starts at Normal")
    assert_eq(_mode(_second_machine, &"eraser"), &"erase", "and the front Eraser at Erase")
    assert_eq(
        BlendModeCommands.target_settings(_registries.context),
        _settings(_second_machine, &"eraser"),
        "A press reads the front document's Eraser"
    )


## The probe's case: Multiply picked with the second document in front.
func test_a_pick_moves_the_front_eraser_and_leaves_the_first_brush_at_normal() -> void:
    assert_true(_registries.commands.execute(&"blend_mode_multiply"), "The pick is taken")
    assert_eq(_mode(_first_machine, &"brush"), &"normal", "The first document's Brush stays at Normal")
    assert_eq(_mode(_second_machine, &"eraser"), &"multiply", "and the front document's Eraser takes Multiply")


func test_a_step_moves_the_front_eraser_and_leaves_the_first_brush_at_normal() -> void:
    var order := BlendModeCommands.walk_order(_registries.blend_modes)
    var at := order.find(&"erase")
    assert_true(at >= 0 and at < order.size() - 1, "Erase has a mode after it: %s" % [order])
    assert_true(_registries.commands.execute(&"blend_mode_next"), "The step is taken")
    assert_eq(_mode(_first_machine, &"brush"), &"normal", "The first document's Brush stays at Normal")
    assert_eq(_mode(_second_machine, &"eraser"), order[at + 1], "and the front document's Eraser moves one row on")


## Bringing the first document forward again turns the commands to it.
func test_with_the_first_document_in_front_the_first_brush_moves() -> void:
    _front = _first
    assert_true(_registries.commands.execute(&"blend_mode_multiply"), "The pick is taken")
    assert_eq(_mode(_first_machine, &"brush"), &"multiply", "The first document's Brush takes Multiply")
    assert_eq(_mode(_second_machine, &"eraser"), &"erase", "and the second document's Eraser keeps Erase")


## With no easel in front the first surface that is not embedded stands in.
func test_with_no_easel_in_front_the_first_document_stands_in() -> void:
    _front = null
    assert_eq(
        BlendModeCommands.target_settings(_registries.context),
        _settings(_first_machine, &"brush"),
        "The first document's Brush is the target"
    )
