## A module for the reload scenario, a tool and a docker a reload puts
## down and registers again.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it. The scenario
## reaches it with `--modules-dir=res://tests/fixtures/r1-reload/modules`, a
## folder of its own rather than `tests/fixtures/modules`, because every
## scenario that loads that one would find this tool in its toolbox. The
## `modules` in the path is what files a kernel under this folder's name, were
## it to ship one.
extends SaModule

const Fixtures = preload("res://tests/fixtures.gd")
const ProbeDocker = preload("res://tests/fixtures/r1-reload/modules/r1-reload-fixture/probe_docker.gd")


func get_id() -> StringName:
    return &"r1-reload-fixture"


func get_name() -> String:
    return "R1 Reload Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    var tool := SaToolDescriptor.create(&"r1_reload_probe", Fixtures.FakeTool)
    tool.display_name = "R1 Probe"
    ctx.register_tool(tool)
    ctx.register_docker(&"R1ProbeDocker", "R1 Probe", _make_docker)


func _make_docker() -> Window:
    return ProbeDocker.new()
