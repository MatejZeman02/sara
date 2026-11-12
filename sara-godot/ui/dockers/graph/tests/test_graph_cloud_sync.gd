## The two Oklab clouds answer pan, zoom and rotation, and answer together.
##
## The reference graph responds to pan, zoom and rotation in the Oklab 3D
## variant, and the two cloud graphs' movements are synced, so the view stays
## the same for both. Panning inside one copies the action to the other.
##
## The docker is built and never added to the SceneTree, the way the other graph suites
## build it, because a `Window` in the tree hangs a headless run. What is
## proved here is the routing and the sync: that either panel's gesture reaches
## the handler, and that both plots hold the same four numbers afterwards. That
## it is visible on screen, and that a source of reference alone still answers a
## drag with the canvas's panel hidden, is proved on the running app by
## `scenarios/the-oklab-clouds-answer-pan-zoom-and-rotation.json`.
extends "res://tests/test_framework.gd"


## A docker on the cloud, which is the only mode with a viewpoint to move.
func _docker() -> GraphDocker:
    var docker := GraphDocker.new()
    docker.show_mode("cloud")
    docker.reset_view()
    return docker


## The four view numbers of a plot, as the one value an assertion can compare.
func _view(plot: SaGraphPlot) -> Array:
    return [plot.cloud_yaw, plot.cloud_pitch, plot.cloud_pan, plot.cloud_zoom]


# --- The routing ----------------------------------------------------------------


## The first half. The reference panel was IGNORE with no connection, so
## a pointer on it reached nothing at all.
func test_both_panels_take_the_pointer() -> void:
    var docker := _docker()

    var canvas_filter := docker._picture.mouse_filter
    var reference_filter := docker._reference_picture.mouse_filter
    var canvas_wired := docker._picture.gui_input.get_connections().size()
    var reference_wired := docker._reference_picture.gui_input.get_connections().size()
    docker.free()

    assert_eq(canvas_filter, Control.MOUSE_FILTER_STOP, "The canvas's panel takes the pointer")
    assert_eq(reference_filter, Control.MOUSE_FILTER_STOP, "and so does the reference's")
    assert_eq(canvas_wired, 1, "The canvas's panel is wired to the handler")
    assert_eq(reference_wired, 1, "and so is the reference's")


## Every other mode is a flat picture, and a gesture on it changes nothing.
func test_a_gesture_outside_the_cloud_is_not_taken() -> void:
    var docker := _docker()
    docker.show_mode("histogram")

    docker.drag_on("reference", Vector2(90.0, 0.0), false)
    var view := _view(docker.reference_plot)
    docker.free()

    assert_eq(view[0], SaGraphPlot.CLOUD_YAW, "A drag over a histogram turns nothing")


# --- The sync -------------------------------------------------------------------


## The second half, from the canvas's panel.
func test_a_drag_on_the_canvas_panel_turns_both_clouds() -> void:
    var docker := _docker()

    docker.drag_on("canvas", Vector2(90.0, -30.0), false)
    var canvas_view := _view(docker.plot)
    var reference_view := _view(docker.reference_plot)
    docker.free()

    assert_true(canvas_view[0] != SaGraphPlot.CLOUD_YAW, "The drag turned the canvas's cloud")
    assert_eq(reference_view, canvas_view, "and the reference's is looked at from the same place")


## And from the reference's, which is the panel that answered nothing before.
func test_a_drag_on_the_reference_panel_turns_both_clouds() -> void:
    var docker := _docker()

    docker.drag_on("reference", Vector2(90.0, -30.0), false)
    var canvas_view := _view(docker.plot)
    var reference_view := _view(docker.reference_plot)
    docker.free()

    assert_true(reference_view[0] != SaGraphPlot.CLOUD_YAW, "The drag turned the reference's cloud")
    assert_eq(canvas_view, reference_view, "and the canvas's is looked at from the same place")


## Shift is the pan branch, and it copies over too.
func test_a_shift_drag_pans_both_clouds() -> void:
    var docker := _docker()

    docker.drag_on("reference", Vector2(12.0, 8.0), true)
    var canvas_view := _view(docker.plot)
    var reference_view := _view(docker.reference_plot)
    docker.free()

    assert_true(canvas_view[2] != Vector2.ZERO, "The shift drag moved the canvas's cloud")
    assert_eq(reference_view, canvas_view, "and the reference's went with it")


func test_a_wheel_on_either_panel_zooms_both() -> void:
    var docker := _docker()

    docker.wheel_on("reference", true)
    var after_reference := [docker.plot.cloud_zoom, docker.reference_plot.cloud_zoom]
    docker.wheel_on("canvas", false)
    var after_canvas := [docker.plot.cloud_zoom, docker.reference_plot.cloud_zoom]
    docker.free()

    assert_true(after_reference[0] > 1.0, "A wheel on the reference's panel zoomed the canvas's cloud")
    assert_eq(after_reference[1], after_reference[0], "and its own by the same factor")
    assert_almost_eq(after_canvas[0], 1.0, 1e-5, "A wheel back on the canvas's panel undid it")
    assert_eq(after_canvas[1], after_canvas[0], "on both")


## The clamps are read once and written to both, so neither cloud creeps past
## the other at a limit.
##
## The limit reached is the lower one since the pitch's sign was turned around,
## and that is the whole of the change here: a drag down lowers the pitch now,
## the way it always did on the gamut solid. What this asserts is unchanged, that
## both panels stop at the same number in the same call.
func test_the_pitch_limit_stops_both_at_once() -> void:
    var docker := _docker()

    for _i in 40:
        docker.turn_by(Vector2(0.0, 0.5))
    var canvas_pitch := docker.plot.cloud_pitch
    var reference_pitch := docker.reference_plot.cloud_pitch
    docker.free()

    assert_eq(canvas_pitch, -SaGraphPlot.CLOUD_PITCH_LIMIT, "The canvas's cloud stopped at the limit")
    assert_eq(reference_pitch, canvas_pitch, "and the reference's stopped there with it")


## A reset is a viewpoint like any other and goes to both.
func test_a_reset_puts_both_clouds_back() -> void:
    var docker := _docker()
    docker.drag_on("canvas", Vector2(120.0, 40.0), false)

    docker.reset_view()
    var canvas_view := _view(docker.plot)
    var reference_view := _view(docker.reference_plot)
    docker.free()

    assert_eq(canvas_view, [SaGraphPlot.CLOUD_YAW, SaGraphPlot.CLOUD_PITCH, Vector2.ZERO, 1.0], "The canvas's is home")
    assert_eq(reference_view, canvas_view, "and so is the reference's")


# --- What the re-bin and the dump say -------------------------------------------


## `_refresh_reference` returns early on an unchanged picture, mode and panel,
## and a viewpoint is none of the three. Without this the second cloud holds the
## angle it was last binned at however far the first one turns, which is the
## known trap.
func test_moving_the_view_makes_the_reference_pass_stale() -> void:
    var docker := _docker()
    docker.show_source("both")
    # A pass with no Reference docker in the tree finds no picture and uploads
    # nothing, and still marks the mode it ran for, which is the guard in question. Written by the docker itself, never from here.
    docker._refresh_reference()
    var armed := docker._seen_reference_mode

    docker.turn_by(Vector2(0.2, 0.0))
    var mode := docker._seen_reference_mode
    var asked := docker.reduction.asked
    docker.free()

    assert_eq(armed, "cloud", "A pass leaves the reference's guard on the mode it ran for")
    assert_eq(mode, "", "and moving the view says that pass is stale")
    assert_true(asked, "beside the canvas's, which asks the reduction service for a pass")


## The dump carries both viewpoints, so a reader is not left comparing two
## pictures by eye.
func test_the_dump_carries_both_viewpoints() -> void:
    var docker := _docker()
    docker.drag_on("reference", Vector2(50.0, 20.0), false)

    var report := docker.view_report()
    docker.free()

    assert_eq(report["reference_yaw"], report["yaw"], "The dump's two yaws are one number")
    assert_eq(report["reference_pitch"], report["pitch"], "and the two pitches")
    assert_eq(report["reference_pan"], report["pan"], "and the two pans")
    assert_eq(report["reference_zoom"], report["zoom"], "and the two zooms")
