## The Stats docker as a module of the base modules: numbers about the
## picture, computed only while the docker is open and its switch is on.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A docker that is not core's belongs in a module rather than in `SaDockerIds`
## and `SaBuiltinDockers`. Its numbers come from `SaReductions`, the service
## behind the door in `core/api/reduction` that the Graph docker registers its
## pass with too, so it registers here through the call a third-party module's
## docker makes, hard rule 6 shown on a docker, the way Exposure and Sphere do.
##
## Without this module the Window menu offers no Stats, and a layout that names
## `StatsDocker` draws nothing for it, since the layout store places only the
## dockers that are registered.
extends SaModule

const Docker := preload("stats_docker.gd")


func get_id() -> StringName:
    return &"sara-stats"


func get_name() -> String:
    return "Sara Stats"


## No chord: a docker's chord is a row of the command table and of the Keyboard
## Shortcuts page, and the Stats docker has neither yet.
func register(ctx: SaContext) -> void:
    ctx.register_docker(Docker.DOCKER_ID, "Stats", func() -> Window: return Docker.new(), &"", Docker.SENTENCE)


## The registry drops the docker this module registered when its context is
## torn down, so there is nothing to undo here.
func unregister(_ctx: SaContext) -> void:
    pass
