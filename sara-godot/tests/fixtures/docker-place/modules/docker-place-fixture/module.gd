## A module that registers two dockers with a default place and nothing else:
## one at the right of the window and one at the left.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it, and not beside the
## other fixture modules either, since every scenario that names their folder
## would open these two dockers over its shots. A scenario reaches it with
## `--modules-dir=res://tests/fixtures/docker-place/modules`. No layout Sara ships names
## either docker, which is the claim: each opens at its side in every one.
extends SaModule

const Docker := preload("res://tests/fixtures/docker-place/modules/docker-place-fixture/place_docker.gd")

const RIGHT_ID := &"PlaceFixtureRightDocker"
const LEFT_ID := &"PlaceFixtureLeftDocker"


func get_id() -> StringName:
    return &"docker-place-fixture"


func get_name() -> String:
    return "Docker Place Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    ctx.register_docker(RIGHT_ID, "Right Place", _factory.bind(RIGHT_ID, "Right Place"), &"", "", &"right", 0)
    ctx.register_docker(LEFT_ID, "Left Place", _factory.bind(LEFT_ID, "Left Place"), &"", "", &"left", 0)


static func _factory(docker_id: StringName, title: String) -> Window:
    return Docker.new(docker_id, title)
