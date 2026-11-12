## The Info docker's FPS row and graph.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The graph is fed a known series through `tick`, the way the docker feeds it
## the engine's clock and drawn-frame count, and read back as points and idle
## marks. The row is read after each frame the docker is handed. What changed at rest, the line, the word and the axis, is held in
## `test_the_fps_graph_says_sara_rests.gd`.
extends "res://tests/test_framework.gd"

const DOCKER := preload("res://ui/dockers/panels/info_docker.gd")

const SECOND: int = 1_000_000

## Sixty frames a second, as microseconds between two.
const FRAME: int = 16_667

## A strip with room for values 20 wide and 16 tall up its left.
const PLOT := Rect2(24.0, 8.0, 270.0, 48.0)


## Ticks *graph* from *start* for *seconds* at *per_second* drawn frames,
## answering the clock and the frame count where it stopped.
func _run(graph: SaInfoFpsGraph, start: Vector2i, seconds: int, per_second: int, resting: bool) -> Vector2i:
    var now := start.x
    var frames := start.y
    # A hundred ticks a second, and a drawn frame every *every* of them.
    var step := 10_000
    var every := roundi(100.0 / float(per_second)) if per_second > 0 else -1
    for i in range(seconds * 100):
        now += step
        if every > 0 and i % every == 0:
            frames += 1
        graph.tick(now, frames, resting)
    return Vector2i(now, frames)


func test_a_known_series_becomes_its_points() -> void:
    var graph := SaInfoFpsGraph.new()
    graph.tick(0, 0, false)
    var at := _run(graph, Vector2i(0, 0), 4, 50, false)
    at = _run(graph, at, 4, 25, false)
    assert_eq(graph.samples.size(), 4, "eight seconds are four points")
    assert_almost_eq(graph.samples[0], 50.0, 1.0, "the first two seconds drew fifty a second")
    assert_almost_eq(graph.samples[3], 25.0, 1.0, "and the last two twenty-five")
    var lines := graph.lines(PLOT)
    assert_eq(lines.size(), 1, "a busy minute is one line")
    var line := lines[0]
    assert_eq(line.size(), 4, "a point per sample")
    assert_almost_eq(line[3].x, PLOT.end.x, 0.001, "the newest at the right edge")
    assert_almost_eq(line[2].x, PLOT.end.x - SaInfoFpsGraph.slot_width(PLOT.size), 0.001, "one slot apart")
    assert_almost_eq(graph.top(), 60.0, 0.001, "below sixty the top is sixty")
    assert_almost_eq(line[0].y, PLOT.end.y - 50.0 / 60.0 * PLOT.size.y, 0.5, "fifty is five sixths up")
    graph.free()


func test_a_minute_is_all_it_keeps() -> void:
    var graph := SaInfoFpsGraph.new()
    for i in range(SaInfoFpsGraph.SAMPLES + 5):
        graph.push_sample(float(i), false)
    assert_eq(graph.samples.size(), SaInfoFpsGraph.SAMPLES, "thirty points, a minute")
    assert_eq(graph.idle.size(), SaInfoFpsGraph.SAMPLES, "and a mark each")
    assert_almost_eq(graph.samples[0], 5.0, 0.001, "the oldest five fell off")
    graph.free()


func test_a_fast_point_raises_the_top_by_a_step() -> void:
    var graph := SaInfoFpsGraph.new()
    graph.push_sample(144.0, false)
    assert_almost_eq(graph.top(), 180.0, 0.001, "144 rounds up to three steps of sixty")
    graph.free()
    graph = SaInfoFpsGraph.new()
    graph.push_sample(60.4, false)
    assert_almost_eq(graph.top(), 60.0, 0.001, "and a hair over sixty is still a graph of sixty")
    graph.free()


func test_a_rest_is_marked_as_one_stretch() -> void:
    var graph := SaInfoFpsGraph.new()
    graph.tick(0, 0, false)
    var at := _run(graph, Vector2i(0, 0), 4, 50, false)
    at = _run(graph, at, 6, 0, true)
    at = _run(graph, at, 2, 50, false)
    assert_eq(graph.idle, [false, false, true, true, true, false] as Array[bool], "the six seconds of rest are three marks")
    assert_almost_eq(graph.samples[3], 0.0, 0.001, "and they drew nothing")
    var rects := graph.idle_rects(PLOT)
    assert_eq(rects.size(), 1, "one run of rest is one band")
    var step := SaInfoFpsGraph.slot_width(PLOT.size)
    var lines := graph.lines(PLOT)
    assert_eq(lines.size(), 2, "and the line stops at it, so the busy points either side are two lines")
    assert_eq(lines[0].size(), 2, "two points before")
    assert_eq(lines[1].size(), 1, "and one after")
    assert_almost_eq(rects[0].position.x, lines[0][1].x, 0.001, "the band starting where the last busy point stands")
    assert_almost_eq(rects[0].end.x, lines[1][0].x - step, 0.001, "and ending at the last resting point")
    assert_almost_eq(rects[0].size.x, 3.0 * step, 0.001, "three slots wide")
    assert_almost_eq(rects[0].position.y, PLOT.position.y, 0.001, "from the top")
    assert_almost_eq(rects[0].size.y, PLOT.size.y, 0.001, "to the floor")
    graph.free()


func test_the_number_is_the_frames_of_the_last_second() -> void:
    var graph := SaInfoFpsGraph.new()
    graph.tick(0, 0, false)
    var frames := 0
    for i in range(1, 61):
        frames += 1
        assert_true(graph.tick(i * FRAME, frames, false), "frame %d moves the number" % i)
        assert_eq(graph.fps_now, i, "and it counts the frames so far")
    graph.tick(61 * FRAME, frames + 1, false)
    assert_eq(graph.fps_now, 60, "a second of frames holds sixty, the first aged out")
    graph.tick(3 * SECOND, frames + 1, false)
    assert_eq(graph.fps_now, 0, "and a second with nothing drawn is zero")
    graph.free()


func test_the_row_follows_each_frame_while_the_hand_moves() -> void:
    var docker: InfoDocker = DOCKER.new()
    var gpu := docker._section_boxes["GPU"]
    var row: Array = gpu.rows["FPS"]
    var value := row[1] as Label
    assert_not_null(gpu.fps_graph, "the GPU section carries the graph")
    assert_eq(gpu.fps_graph.get_parent(), gpu, "in the GPU box")
    assert_eq(gpu.fps_graph.get_index(), gpu.get_child_count() - 1, "under its rows")
    docker.follow_frame(0, 0, false)
    for i in range(1, 11):
        docker.follow_frame(i * FRAME, i, false)
        assert_eq(value.text, str(i), "frame %d is on the row" % i)
    docker.free()


func test_a_write_of_the_shown_text_touches_nothing() -> void:
    var docker: InfoDocker = DOCKER.new()
    var gpu := docker._section_boxes["GPU"]
    var value := gpu.rows["FPS"][1] as Label
    docker.follow_frame(0, 0, true)
    assert_eq(value.text, "resting", "a docker shown at rest reads the word at once")
    var writes := gpu.fps_row_writes
    docker.follow_frame(SaInfoFpsGraph.SAMPLE_USEC, 0, true)
    docker.follow_frame(2 * SaInfoFpsGraph.SAMPLE_USEC - FRAME, 1, true)
    docker.follow_frame(2 * SaInfoFpsGraph.SAMPLE_USEC, 1, true)
    assert_eq(gpu.fps_graph.samples.size(), 2, "two points land")
    assert_eq(gpu.fps_row_writes, writes, "and the word is not set again, so the label has nothing to redraw")
    docker.follow_frame(2 * SaInfoFpsGraph.SAMPLE_USEC + FRAME, 2, false)
    assert_eq(value.text, "2", "the hand moving writes the frames of the last second, the one the point asked for among them")
    assert_eq(gpu.fps_row_writes, writes + 1, "once")
    docker.free()


func test_the_report_carries_the_graph() -> void:
    var docker: InfoDocker = DOCKER.new()
    docker._section_boxes["GPU"].fps_graph.push_sample(30.0, true)
    var report := docker._section_boxes["GPU"].fps_graph.report()
    assert_eq(report["samples"], [30.0], "the points")
    assert_eq((report["idle"] as Array).size(), 1, "a mark per point")
    assert_true(bool(report["idle"][0]), "and which rested")
    assert_almost_eq(float(report["top"]), 60.0, 0.001, "the top the line is scaled to")
    assert_eq(report["axis"], [], "no values before the first draw")
    assert_false(bool(report["resting"]), "and whether the number reads the word")
    assert_eq(report["fps_text"], "0", "which it does not before a tick at rest")
    docker.free()
