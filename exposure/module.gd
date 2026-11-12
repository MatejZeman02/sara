# The Exposure docker as a module of its own.
#
# It holds nothing the skeleton needs, every row writing through a door another
# place owns, so it registers here through the call a third-party module's
# docker makes, which is hard rule 6 shown on a docker.
#
# Its own folder rather than the base module's tree, because the base module is
# a repository of its own and the docker reads it only by a filter id it looks
# up when the row is drawn. Without the base module the Layer row says that no
# module registers the Exposure filter, and the View and Paint rows still work.
#
# The docker is reached by a path beside this file and not by a class name, as
# the kaleidoscope's filter is, so a copy of the folder builds its own.
#
# SPDX-License-Identifier: GPL-3.0-or-later
extends SaModule

const ExposureDocker := preload("exposure_docker.gd")

## What the docker holds, its row's tooltip in the Window menu.
const SENTENCE := "The view's exposure, the paint's and the active layer's values, each in stops."


func get_id() -> StringName:
    return &"exposure"


func get_name() -> String:
    return "Exposure"


## No chord: the Window menu opens it as it opens every docker, and nothing in
## it is reached often enough to hold one. The window is handed this context's
## filters and layer types, read when it is built rather than now, so it finds
## the Exposure filter whichever module registered it and whenever.
func register(ctx: SaContext) -> void:
    ctx.register_docker(ExposureDocker.DOCKER_ID, "Exposure", _factory(ctx), &"", SENTENCE)


func _factory(ctx: SaContext) -> Callable:
    return func() -> Window:
        var docker := ExposureDocker.new()
        docker.filter_registry = ctx.filters
        docker.layer_types = ctx.layer_types
        return docker
