## A drag down turns the Oklab cloud the way it turns the gamut solid.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Y axis rotation was reversed on the Oklab solid in
## Preferences, and the same sign stood in the Graph docker's cloud:
## `turn_by` added the drag to the pitch, so a drag down carried the far side
## of the cloud down and the near side up. The two 3D pictures in the app answer
## the same buttons and the same wheel, and they turned opposite ways in the
## vertical, which is worse than both being wrong.
##
## The shape of the assertions is `ui/color_space/tests/test_gamut_solid_view.gd`'s, on
## purpose: the same drag, the same "a known point rises", so the two pictures
## are graded against one sentence.
##
## What a painter sees is
## `scenarios/the-oklab-clouds-answer-pan-zoom-and-rotation.json`, whose
## dumps read `pitch` and `reference_pitch` before and after a drag down.
extends "res://tests/test_framework.gd"

## The kernel's own projection of the vertical, mirrored so an assertion can be
## about the picture rather than about a number behind it.
##
## `shaders/compute/graph.gmacs`'s `project_point` runs on the GPU and no test
## can call it, so these two lines are copied: `turned.y * cos_pitch -
## turned.z * sin_pitch`, and then `0.5 - screen_at.y * scale` for a screen
## whose y grows downwards. The yaw is left out of `_white_height` because the
## point chosen sits on the axis the yaw turns about. `_cloud_screen` below
## carries the yaw as well, for the yaw cases.
const CLOUD_ZOOM := 0.4
## `graph.gmacs`'s `SCOPE_RANGE`, which `project_lab` divides a and b by.
const SCOPE_RANGE := 0.4


## Where the top of the neutral axis lands, in the square's own coordinates.
##
## The counterpart of the white corner: white is the top of the lightness axis
## in both pictures, and a tip of either one moves it. `pt.x` and `pt.z` are
## zero there, so the yaw drops out and the height is `cos(pitch)` alone.
func _white_height(plot: SaGraphPlot) -> float:
    var turned := Vector3(0.0, 1.0, 0.0)
    var screen_y := turned.y * cos(plot.cloud_pitch) - turned.z * sin(plot.cloud_pitch)
    return 0.5 - screen_y * CLOUD_ZOOM * maxf(plot.cloud_zoom, 0.01)


## Where an Oklab colour lands in the cloud, in the square's own coordinates,
## x growing right and y growing down. The kernel's `project_lab` and
## `project_point` line for line: a and b over `SCOPE_RANGE`, lightness to
## minus one to one, turned by the yaw about the lightness axis, tipped by the
## pitch, and the zoom. The pan is left out because a turn does not move it.
func _cloud_screen(plot: SaGraphPlot, lab: Vector3) -> Vector2:
    var pt := Vector3(lab.y / SCOPE_RANGE, lab.x * 2.0 - 1.0, lab.z / SCOPE_RANGE)
    var cos_yaw := cos(plot.cloud_yaw)
    var sin_yaw := sin(plot.cloud_yaw)
    var turned := Vector3(pt.x * cos_yaw + pt.z * sin_yaw, pt.y, pt.z * cos_yaw - pt.x * sin_yaw)
    var screen_at := Vector2(turned.x, turned.y * cos(plot.cloud_pitch) - turned.z * sin(plot.cloud_pitch))
    var scale := CLOUD_ZOOM * maxf(plot.cloud_zoom, 0.01)
    return Vector2(0.5 + screen_at.x * scale, 0.5 - screen_at.y * scale)


## An Oklab colour off the lightness axis, towards positive b, so a turn about
## that axis moves it and neither picture's yaw drops out of the sum.
const OFF_AXIS := Vector3(0.6, 0.0, 0.15)


## Both pictures looking from the same place: yaw zero and the same pitch, so a
## drag is compared from one view rather than from each picture's own rest.
func _level(docker: GraphDocker, solid: SaGamutSolid, pitch: float) -> void:
    for target: SaGraphPlot in [docker.plot, docker.reference_plot]:
        target.cloud_yaw = 0.0
        target.cloud_pitch = pitch
    solid.yaw = 0.0
    solid.pitch = pitch


## A docker on the cloud, built and never added to the tree the way the other graph suites
## build one: a `Window` in the tree hangs a headless run.
func _docker() -> GraphDocker:
    var docker := GraphDocker.new()
    docker.show_mode("cloud")
    docker.reset_view()
    return docker


## The reported case. Forty pixels of drag is what the scenario uses, and `apply_gesture` scales a motion by 0.01.
func test_a_drag_down_raises_the_white_end_of_the_cloud() -> void:
    var docker := _docker()
    var before := _white_height(docker.plot)
    docker.turn_by(Vector2(0.0, 0.4))
    var after := _white_height(docker.plot)
    var pitch := docker.plot.cloud_pitch
    docker.free()

    assert_true(after < before, "A drag down moves the white end up, %s then %s" % [before, after])
    assert_true(pitch < SaGraphPlot.CLOUD_PITCH, "because the drag lowered the pitch rather than raising it")


## And the other way, or the fix is a sign that only reads right once.
func test_a_drag_up_lowers_the_white_end_of_the_cloud() -> void:
    var docker := _docker()
    var before := _white_height(docker.plot)
    docker.turn_by(Vector2(0.0, -0.4))
    var after := _white_height(docker.plot)
    var pitch := docker.plot.cloud_pitch
    docker.free()

    assert_true(after > before, "A drag up moves the white end down, %s then %s" % [before, after])
    assert_true(pitch > SaGraphPlot.CLOUD_PITCH, "because the drag raised the pitch")


## The two pictures agree, which is the half of the claim a sign on its own does
## not cover. The same drag on each, and both tops move the same way.
func test_the_cloud_and_the_gamut_solid_turn_the_same_way() -> void:
    var docker := _docker()
    var cloud_before := _white_height(docker.plot)
    docker.turn_by(Vector2(0.0, 0.4))
    var cloud_after := _white_height(docker.plot)
    docker.free()

    var solid := SaGamutSolid.new()
    var solid_before := solid.project(solid.to_oklab(Vector3(1, 1, 1)))
    solid.turn_by(Vector2(0.0, 0.4))
    var solid_after := solid.project(solid.to_oklab(Vector3(1, 1, 1)))
    solid.free()

    assert_true(cloud_after < cloud_before, "the cloud's white end rises on a drag down")
    assert_true(solid_after.y < solid_before.y, "and so does the solid's white corner")


## The clamp is untouched, so a pitch at its limit still stops in both panels at
## once rather than one creeping past the other. Driven far enough that the
## limit is what stops it and not the drag running out.
func test_the_pitch_still_stops_at_the_limit_in_both_panels() -> void:
    var docker := _docker()
    for _push in 20:
        docker.turn_by(Vector2(0.0, 1.0))
    var canvas_pitch := docker.plot.cloud_pitch
    var reference_pitch := docker.reference_plot.cloud_pitch
    docker.free()

    assert_almost_eq(canvas_pitch, -SaGraphPlot.CLOUD_PITCH_LIMIT, 0.0001, "a long drag down stops at the lower limit")
    assert_eq(reference_pitch, canvas_pitch, "and the reference panel stopped at the same place")


## A drag right moves the same off-axis colour the same way across the
## screen in both pictures. The cloud's kernel turns by minus the solid's yaw,
## so the two only agree when the cloud's `turn_by` takes the drag off its yaw
## where the solid's adds it.
func test_a_drag_right_moves_an_off_axis_colour_the_same_way_in_both() -> void:
    var docker := _docker()
    var solid := SaGamutSolid.new()
    _level(docker, solid, 0.3)

    var cloud_before := _cloud_screen(docker.plot, OFF_AXIS)
    var solid_before := solid.project(OFF_AXIS)
    docker.turn_by(Vector2(0.4, 0.0))
    solid.turn_by(Vector2(0.4, 0.0))
    var cloud_after := _cloud_screen(docker.plot, OFF_AXIS)
    var solid_after := solid.project(OFF_AXIS)
    docker.free()
    solid.free()

    var cloud_dx := cloud_after.x - cloud_before.x
    var solid_dx := solid_after.x - solid_before.x
    assert_true(absf(cloud_dx) > 0.001 and absf(solid_dx) > 0.001, "both pictures move the colour sideways at all")
    assert_true(
        signf(cloud_dx) == signf(solid_dx),
        "a drag right moves it the same way in both, cloud %s, solid %s" % [cloud_dx, solid_dx]
    )


## And a drag down, which already agrees, checked from the same level
## view so the two axes are graded the same way.
func test_a_drag_down_moves_an_off_axis_colour_the_same_way_in_both() -> void:
    var docker := _docker()
    var solid := SaGamutSolid.new()
    _level(docker, solid, 0.3)

    var cloud_before := _cloud_screen(docker.plot, OFF_AXIS)
    var solid_before := solid.project(OFF_AXIS)
    docker.turn_by(Vector2(0.0, 0.4))
    solid.turn_by(Vector2(0.0, 0.4))
    var cloud_after := _cloud_screen(docker.plot, OFF_AXIS)
    var solid_after := solid.project(OFF_AXIS)
    docker.free()
    solid.free()

    var cloud_dy := cloud_after.y - cloud_before.y
    var solid_dy := solid_after.y - solid_before.y
    assert_true(absf(cloud_dy) > 0.001 and absf(solid_dy) > 0.001, "both pictures move the colour up or down at all")
    assert_true(
        signf(cloud_dy) == signf(solid_dy), "a drag down moves it the same way in both, cloud %s, solid %s" % [cloud_dy, solid_dy]
    )


## The sense Sara settled on, said once for both axes: the colour on the near
## side, positive b at yaw zero, goes against the pointer. A drag right carries
## it left and a drag down carries it up, in the cloud as in the solid, which is
## what the reported bug left the solid doing.
func test_the_near_side_goes_against_the_pointer_on_both_axes_in_the_cloud() -> void:
    var docker := _docker()
    var solid := SaGamutSolid.new()
    _level(docker, solid, 0.0)

    var start := _cloud_screen(docker.plot, OFF_AXIS)
    docker.turn_by(Vector2(0.4, 0.0))
    var after_right := _cloud_screen(docker.plot, OFF_AXIS)
    _level(docker, solid, 0.0)
    docker.turn_by(Vector2(0.0, 0.4))
    var after_down := _cloud_screen(docker.plot, OFF_AXIS)
    docker.free()
    solid.free()

    assert_true(after_right.x < start.x, "a drag right carries the near side of the cloud left")
    assert_true(after_down.y < start.y, "and a drag down carries it up")
