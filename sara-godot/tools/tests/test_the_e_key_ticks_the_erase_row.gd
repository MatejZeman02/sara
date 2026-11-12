## The E key ticks the Tool Options docker's Erase row as well as the bar's
## eraser switch.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## E runs `brush_toggle_eraser`, whose handler flips `eraser_toggled` on the
## brush and writes neither surface. The bar heard the setter's
## `EventBus.brush_eraser_toggled` and ticked its switch, the docker did not, so
## its row, whose tip reads "(E) Erase with the brush", stayed unticked while the
## brush erased. The wiring is test_shortcut_router.gd's, because
## `Fixtures.make_bound_machine()` throws its commands registry away.
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


func test_e_ticks_the_bar_and_the_docker_and_a_second_press_unticks_both() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    var module: SaModule = load("res://modules/sara-base-modules/stamp-brush/module.gd").new()
    module.register(registries.context.for_module(module.get_id()))
    var machine := ToolMachine.new()
    machine.name = "ToolMachine"
    machine._ready()
    machine.bind(surface, registries.tools)
    machine.set_active_tool(&"brush")

    var router := ShortcutRouter.new()
    router.canvas_provider = func() -> SaCanvas: return null
    router.tool_machine_provider = func() -> ToolMachine: return machine
    router.bind_commands(registries.commands)

    var host := Node.new()
    var bar := ToolOptionsBar.new()
    host.add_child(bar)
    bar.target_tool_machine = machine
    bar._ready()
    var docker := ToolOptionsDocker.new()
    host.add_child(docker)
    docker.target_tool_machine = machine
    docker.peer_bar = bar

    var bar_switch := bar.options.control(&"eraser_toggled") as BaseButton
    var docker_row := docker.options.control(&"eraser_toggled") as BaseButton
    assert_not_null(bar_switch, "The bar has an eraser switch")
    assert_not_null(docker_row, "and the docker has an Erase row")
    assert_false(bar_switch.button_pressed, "The switch starts unticked")
    assert_false(docker_row.button_pressed, "and so does the row")

    assert_true(router.handle(_key_e()), "E is somebody's")
    assert_true(machine.active_tool.eraser_toggled, "and turns the brush into an eraser")
    assert_true(bar_switch.button_pressed, "The bar's switch shows it")
    assert_true(docker_row.button_pressed, "and so does the docker's Erase row")

    assert_true(router.handle(_key_e()), "A second E answers too")
    assert_false(machine.active_tool.eraser_toggled, "and turns the brush back")
    assert_false(bar_switch.button_pressed, "The bar's switch lets go")
    assert_false(docker_row.button_pressed, "and so does the docker's Erase row")

    host.free()
    module.unregister(registries.context)
    Fixtures.teardown(surface, machine)
    router.free()
