## The Tool Options docker takes its opening height once.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every docker has an opening height, "a docker's first size, computed when it
## is first shown", and this docker asks for it from
## `sync_from_tool` rather than from `_ready` because at ready it has no rows to
## measure: the tools bind after the modules load. `sync_from_tool` then runs
## again on every tool change, document open, preset load and registry change,
## so the grow was not a first size at all.
##
## What that cost is on the running app rather than in theory. The layout store
## re-asserts each docker's stored size for sixty frames after startup, so a
## grow inside that window is put back and a grow after it stands: the docker
## was 430 logical pixels tall in a run that opened a document in the first
## second and 540 in a run that opened one a moment later. Two runs of the same
## app disagreeing on a docker's height by 110 is what
## `scripts/test_door_scenario.py` caught.
##
## The stored layout is the painter's last word on the height, so only the
## opening sync may raise it. `scenarios/a-sessions-tool-options-docker-is-taller-than-the-files.json`
## is the same claim on the assembled dockers.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true


## The sync that has rows to measure is the one that takes the height, and no
## later sync takes it again.
func test_the_opening_height_is_taken_by_the_first_sync_that_has_rows() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var host := Node.new()
    var docker := ToolOptionsDocker.new()
    host.add_child(docker)

    assert_false(docker._took_its_opening_height, "A docker with no machine has nothing to measure")
    assert_true(docker.shown_keys().is_empty(), "and shows no row")

    docker.target_tool_machine = machine
    assert_false(docker.shown_keys().is_empty(), "Binding the machine builds the brush's rows")
    assert_true(docker._took_its_opening_height, "and that sync is the one that takes the opening height")

    # Every later sync, in the four shapes that reach `sync_from_tool`: a tool
    # change, a document resize, a preset load and a registry change. None of
    # them may take it a second time, because by then the stored layout has been
    # applied and nothing puts it back.
    machine.set_active_tool(&"lasso")
    docker.sync_from_tool()
    docker._on_document_resized(null, Vector2i(512, 384))
    docker._on_preset_loaded("anything")
    docker.options.binding._on_registry_changed()
    assert_true(docker._took_its_opening_height, "It stays taken")
    assert_false(docker.shown_keys().is_empty(), "and the rows still follow the tool")

    host.free()
    Fixtures.teardown(surface, machine)


## A sync with no row to measure is not the opening one, which is why the flag
## is not simply "the first sync". Main hands this docker its machine before the
## modules have loaded, and the descriptor it finds then declares nothing.
func test_a_sync_with_no_rows_does_not_take_the_height() -> void:
    var host := Node.new()
    var docker := ToolOptionsDocker.new()
    host.add_child(docker)

    docker.sync_from_tool()
    assert_false(docker._took_its_opening_height, "No machine, no rows, no opening height")
    host.free()


## The grow itself is untouched: what changed is who asks for it and how often.
## A docker asked directly still rises to its content, up to the cap, which is
## the opening-height claim and the half a narrower guard could have broken.
func test_the_grow_still_raises_a_short_docker_to_its_content() -> void:
    DockerWindow.forget_painter_sizing()
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var host := Node.new()
    var docker := ToolOptionsDocker.new()
    host.add_child(docker)
    docker.target_tool_machine = machine

    var content := DockerWindow.column_content_height(docker)
    var cap := DockerWindow.content_height_cap(docker)
    assert_true(content > 0, "The docker's rows want a height, %d" % content)
    docker.size = Vector2i(docker.size.x, docker.min_size.y)
    docker.grow_to_content()
    assert_eq(docker.size.y, mini(content, cap), "and asking directly raises it there, capped at %d" % cap)

    host.free()
    Fixtures.teardown(surface, machine)
