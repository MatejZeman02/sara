## E toggles the eraser of the document in front.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `brush_toggle_eraser` took the tool machine of the first surface that was
## not embedded, the document Sara opened at start-up, so a painter working in
## a second document toggled the first one's brush and saw nothing happen. The
## handler now takes the surface whose easel is the front one.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true


func _key_e() -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = KEY_E
    event.physical_keycode = KEY_E
    event.pressed = true
    return event


func _brush_machine(surface: SaSurface, registries: SaRegistries) -> ToolMachine:
    var machine := ToolMachine.new()
    machine.name = "ToolMachine"
    machine._ready()
    machine.bind(surface, registries.tools)
    machine.set_active_tool(&"brush")
    surface.tool_machine = machine
    return machine


func test_e_toggles_the_second_documents_brush_and_leaves_the_first_alone() -> void:
    var first := Fixtures.make_surface()
    var second := Fixtures.make_surface()
    var registries := SaRegistries.new()
    registries.build_context(func() -> SaEasel: return second.easel, func() -> Array: return [first, second])
    registries.register_builtins()
    var module: SaModule = load("res://modules/sara-base-modules/stamp-brush/module.gd").new()
    module.register(registries.context.for_module(module.get_id()))
    var first_machine := _brush_machine(first, registries)
    var second_machine := _brush_machine(second, registries)

    var router := ShortcutRouter.new()
    router.canvas_provider = func() -> SaCanvas: return null
    router.tool_machine_provider = func() -> ToolMachine: return second_machine
    router.bind_commands(registries.commands)

    assert_true(router.handle(_key_e()), "E is somebody's")
    assert_true(second_machine.active_tool.eraser_toggled, "E turns the front document's brush into an eraser")
    assert_false(first_machine.active_tool.eraser_toggled, "and leaves the first document's brush painting")

    assert_true(router.handle(_key_e()), "A second E answers too")
    assert_false(second_machine.active_tool.eraser_toggled, "and turns the front document's brush back to painting")
    assert_false(first_machine.active_tool.eraser_toggled, "with the first document's brush still untouched")

    module.unregister(registries.context)
    first.tool_machine = null
    second.tool_machine = null
    Fixtures.teardown(first, first_machine)
    Fixtures.teardown(second, second_machine)
    router.free()
