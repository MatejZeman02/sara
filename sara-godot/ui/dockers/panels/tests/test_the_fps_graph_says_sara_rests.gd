## The FPS graph says Sara rests rather than falling to zero.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A graph that drops to zero when nothing is happening is confusing, and it
## needs y axis values to say how many FPS it shows. The docker is handed a minute of
## motion and then a minute of rest the way `_process` hands it the engine's
## clock, drawn-frame count and low processor mode, and the graph is read after
## every point that lands.
extends "res://tests/test_framework.gd"

const DOCKER := preload("res://ui/dockers/panels/info_docker.gd")

## Ticks a second, a hundred as in the other FPS suites, and the microseconds between two.
const TICKS: int = 100
const TICK_USEC: int = 10_000

## A strip with room for values 20 wide and 16 tall up its left.
const LABEL := Vector2(20.0, 16.0)
const AREA := Vector2(216.0, 64.0)


## Hands *docker* *seconds* of frames from *at*, the clock and the frame count,
## at *per_second* drawn frames while moving, or at rest with the one frame in
## two seconds a landing point asks for. The clock starts on a whole point, so
## a point lands every two seconds of ticks, and *each_point* is called after
## each. Answers the clock and the count where it stopped.
func _feed(docker: InfoDocker, at: Vector2i, seconds: int, per_second: int, resting: bool, each_point: Callable) -> Vector2i:
    var now := at.x
    var frames := at.y
    var every := roundi(float(TICKS) / float(per_second)) if per_second > 0 else 2 * TICKS
    for i in range(seconds * TICKS):
        now += TICK_USEC
        if i % every == 0:
            frames += 1
        docker.follow_frame(now, frames, resting)
        if (i + 1) % (2 * TICKS) == 0:
            each_point.call()
    return Vector2i(now, frames)


func test_a_minute_of_rest_after_a_minute_of_motion_is_drawn_as_rest() -> void:
    var docker: InfoDocker = DOCKER.new()
    var graph := docker._section_boxes["GPU"].fps_graph
    var value := docker._section_boxes["GPU"].rows["FPS"][1] as Label
    var plot := SaInfoFpsGraph.plot_rect(AREA, LABEL)
    var word := Vector2(46.0, 16.0)
    docker.follow_frame(0, 0, false)
    var at := _feed(docker, Vector2i(0, 0), 60, 50, false, func() -> void: pass)
    assert_eq(graph.samples.size(), SaInfoFpsGraph.SAMPLES, "a minute of motion fills the graph")
    assert_eq(graph.lines(plot).size(), 1, "as one line")
    assert_eq(value.text, "50", "and the row reads the frames of the last second")

    var checks := {"points": 0, "floor": 0, "inside": 0, "labelled": 0, "number": 0}
    var watch := func() -> void:
        checks["points"] += 1
        var so_far := graph.idle_rects(plot)
        var rest_left := so_far[-1].position.x if not so_far.is_empty() else plot.end.x
        for run in graph.lines(plot):
            for point in run:
                if point.y >= plot.end.y - 1.0:
                    checks["floor"] += 1
                if point.x > rest_left + 0.001:
                    checks["inside"] += 1
        if not graph.rest_labels(plot, word).is_empty():
            checks["labelled"] += 1
        if value.text.is_valid_int():
            checks["number"] += 1
    _feed(docker, at, 60, 0, true, watch)

    assert_eq(checks["points"], SaInfoFpsGraph.SAMPLES, "a minute of rest lands thirty points")
    assert_eq(checks["floor"], 0, "and at none of them is a point of the line drawn at the floor")
    assert_eq(checks["inside"], 0, "or anywhere inside the rest, the line stops where it begins")
    assert_eq(checks["number"], 0, "the number never reads 0, or any count, at rest")
    assert_eq(value.text, "resting", "it reads the word")
    var labelled: int = checks["labelled"]
    assert_true(labelled >= SaInfoFpsGraph.SAMPLES - 10, "the band carries the word once it is wide enough, %d times" % labelled)
    assert_true(graph.lines(plot).is_empty(), "after a minute of rest there is no line at all")
    var bands := graph.idle_rects(plot)
    assert_eq(bands.size(), 1, "but one band")
    assert_eq(graph.rest_labels(plot, word).size(), 1, "with the word in it")
    for i in range(graph.samples.size()):
        assert_true(graph.samples[i] < 1.0, "and a dump still reads what the engine drew at rest, point %d" % i)
    docker.free()


## The narrowest band a word is written in is one it fits, with its pad either
## side, and a band one slot wide carries none.
func test_a_band_carries_the_word_only_where_it_fits() -> void:
    var graph := SaInfoFpsGraph.new()
    var plot := SaInfoFpsGraph.plot_rect(AREA, LABEL)
    var step := SaInfoFpsGraph.slot_width(plot.size)
    var word := Vector2(46.0, 16.0)
    graph.push_sample(60.0, false)
    graph.push_sample(0.5, true)
    graph.push_sample(60.0, false)
    assert_eq(graph.idle_rects(plot).size(), 1, "one resting point is a band")
    assert_true(graph.rest_labels(plot, word).is_empty(), "one slot wide, with no word")
    var needed := ceili((word.x + 2.0 * SaInfoFpsGraph.REST_WORD_PAD) / step)
    for _i in range(needed):
        graph.push_sample(0.5, true)
    var labels := graph.rest_labels(plot, word)
    assert_eq(labels.size(), 1, "%d slots carry it" % needed)
    var band := graph.idle_rects(plot)[-1]
    assert_true(band.encloses(labels[0]), "inside the band")
    assert_almost_eq(labels[0].get_center().x, band.get_center().x, 0.001, "centred")
    graph.free()


## A point the hand moved for most of is the rate it moved at, so the line does
## not dip into the rest that follows it.
func test_a_point_that_ends_in_a_rest_reads_the_rate_the_hand_had() -> void:
    var docker: InfoDocker = DOCKER.new()
    var graph := docker._section_boxes["GPU"].fps_graph
    docker.follow_frame(0, 0, false)
    var at := _feed(docker, Vector2i(0, 0), 1, 50, false, func() -> void: pass)
    # A fifth of a second more of motion, then the rest, inside the one point.
    var now := at.x
    var frames := at.y
    for i in range(20):
        now += 10_000
        if i % 2 == 0:
            frames += 1
        docker.follow_frame(now, frames, false)
    for _i in range(80):
        now += 10_000
        docker.follow_frame(now, frames, true)
    assert_eq(graph.samples.size(), 1, "two seconds are one point")
    assert_false(graph.idle[0], "spent mostly moving")
    assert_almost_eq(graph.samples[0], 50.0, 1.0, "at fifty a second, not the thirty the whole span averages")
    docker.free()


## The text of each of *marks*, top first.
func _texts(marks: Array) -> Array:
    return marks.map(func(mark: Array) -> String: return mark[0])


func test_the_axis_names_the_top_the_line_is_scaled_to() -> void:
    var graph := SaInfoFpsGraph.new()
    var plot := SaInfoFpsGraph.plot_rect(AREA, LABEL)
    for _i in range(3):
        graph.push_sample(60.0, false)
    var marks := graph.axis_marks(plot, LABEL.y)
    assert_eq(_texts(marks), ["60", "30", "0"], "a graph of sixty names sixty, thirty and nought")
    assert_almost_eq(float(marks[0][1]), plot.position.y, 0.001, "sixty at the top of the plot")
    assert_almost_eq(float(marks[2][1]), plot.end.y, 0.001, "nought at its floor")
    var sixty: float = graph.lines(plot)[0][2].y
    assert_almost_eq(sixty, float(marks[0][1]), 0.001, "and a point of sixty stands at the value saying sixty")

    graph.push_sample(110.0, false)
    marks = graph.axis_marks(plot, LABEL.y)
    assert_almost_eq(graph.top(), 120.0, 0.001, "a point of 110 steps the top to 120")
    assert_eq(_texts(marks), ["120", "60", "0"], "and the values step with it")
    var line: PackedVector2Array = graph.lines(plot)[0]
    assert_almost_eq(line[2].y, float(marks[1][1]), 0.001, "a point of sixty now stands at the value that says sixty, half way")
    assert_almost_eq(line[3].y, plot.end.y - 110.0 / 120.0 * plot.size.y, 0.001, "and 110 eleven twelfths up")

    for _i in range(SaInfoFpsGraph.SAMPLES):
        graph.push_sample(0.5, true)
    assert_almost_eq(graph.top(), 60.0, 0.001, "a rest has no line, so it scales nothing, and the top comes back to sixty")
    graph.free()


## The values sit in a gutter of their own left of the line, and a strip too
## short for three writes two.
func test_the_values_have_room_of_their_own() -> void:
    var plot := SaInfoFpsGraph.plot_rect(AREA, LABEL)
    assert_almost_eq(plot.position.x, LABEL.x + SaInfoFpsGraph.AXIS_GAP, 0.001, "the line starts right of the widest value")
    assert_almost_eq(plot.end.x, AREA.x, 0.001, "and runs to the right edge")
    assert_almost_eq(plot.position.y, LABEL.y * 0.5, 0.001, "half a value in from the top, so the top's value is not cut")
    assert_almost_eq(plot.end.y, AREA.y - LABEL.y * 0.5, 0.001, "and from the floor")
    var graph := SaInfoFpsGraph.new()
    var short := SaInfoFpsGraph.plot_rect(Vector2(AREA.x, 44.0), LABEL)
    assert_eq(graph.axis_marks(short, LABEL.y).size(), 2, "the height the strip had names the top and the floor only")
    assert_eq(graph.axis_marks(plot, LABEL.y).size(), 3, "the height it has now names the half as well")
    assert_true(float(SaInfoFpsGraph.HEIGHT) >= AREA.y, "which is the height it asks for")
    graph.free()
