# The Sphere docker as a module of its own.
#
# It holds nothing the skeleton needs, reading the canvas the main window shows
# and the Environment view's maths every module may read, so it registers here
# through the call a third-party module's docker makes, which is hard rule 6
# shown on a docker, as the Exposure module beside it shows it.
#
# Its own folder rather than the base module's tree, because the base module is
# a repository of its own and the docker needs nothing of it: the ball is drawn
# by the canvas's shader and the Environment view's include, both the skeleton's.
#
# The docker and its shader include are reached by a path beside this file and
# not by a class name, so a copy of the folder builds its own.
#
# SPDX-License-Identifier: GPL-3.0-or-later
extends SaModule

const SphereDocker := preload("sphere_docker.gd")

## What the docker holds, its row's tooltip in the Window menu.
const SENTENCE := "The panorama on a ball seen from outside, turned by a drag, for judging it as a light source."


func get_id() -> StringName:
    return &"sphere"


func get_name() -> String:
    return "Sphere"


## No chord, as the built-in had none: the Window menu opens it as it opens every
## docker. The window shows the main window's canvas, found when it is shown.
func register(ctx: SaContext) -> void:
    ctx.register_docker(SphereDocker.DOCKER_ID, "Sphere", _factory, &"", SENTENCE)


func _factory() -> Window:
    return SphereDocker.new()
