## The learned lead reads the canvas view's four edges.
##
## The lead takes "the distance to each of the four edges of the canvas
## view, in logical pixels, clipped at a horizon of about three hundred and
## scaled to one", because "in the middle of the screen a person behaves
## differently than in a corner". The weights are fitted from
## recorded strokes, and until a fit with the edges ships the rows read none, so the
## claim is asserted on rows handed to the predictor: two motions alike in every
## displacement, one beside the right edge of the view and one in its middle,
## and the lead differs between them.
extends "res://tests/test_framework.gd"

const VIEW := Rect2(Vector2(40.0, 30.0), Vector2(1200.0, 800.0))


## The shipped rows with an edge block spliced in before each bias, every
## edge weight nothing but the right edge's *room* on x: the further the edge,
## the further the lead runs on, which is what a hand that slows at a wall would
## teach a fit.
func _rows_with_edges(room: float) -> Array:
    var rows: Array = []
    var taps := 2 * SaCursorLeadWeights.TAPS
    for shipped: Array in SaCursorLeadWeights.WEIGHTS:
        var row: Array = []
        for axis in 2:
            var start := axis * (taps + 1)
            row.append_array(shipped.slice(start, start + taps))
            row.append_array([0.0, 0.0, room if axis == 0 else 0.0, 0.0])
            row.append(shipped[start + taps])
        rows.append(row)
    return rows


## A predictor fed a sweep right at *pixels_per_second* for half a second, ending
## at *end*, sampled the way a frame loop at sixty hertz would.
func _swept_to(end: Vector2, pixels_per_second: float, rows: Array) -> SaCursorPrediction:
    var prediction := SaCursorPrediction.new(rows)
    var frames := 30
    for i in frames + 1:
        var at := float(i) / 60.0
        var back := pixels_per_second * (float(frames) / 60.0 - at)
        prediction.sample(end - Vector2(back, 0.0), int(at * 1_000_000.0) + 1_000_000)
    return prediction


func test_a_distance_is_clipped_at_the_horizon_and_scaled_to_one() -> void:
    var middle := SaCursorPrediction.edge_distances(VIEW.get_center(), VIEW)
    assert_eq(middle, PackedFloat32Array([1.0, 1.0, 1.0, 1.0]), "far from every edge all four read one")
    var near := SaCursorPrediction.edge_distances(Vector2(VIEW.end.x - 60.0, VIEW.get_center().y), VIEW)
    assert_almost_eq(near[2], 60.0 / SaCursorPrediction.EDGE_HORIZON, 0.0001, "sixty pixels from the right edge")
    assert_eq(near[0], 1.0, "and far from the left")
    var outside := SaCursorPrediction.edge_distances(Vector2(VIEW.end.x + 50.0, VIEW.position.y + 10.0), VIEW)
    assert_eq(outside[2], 0.0, "past the edge is at it, never below nothing")
    assert_almost_eq(outside[1], 10.0 / SaCursorPrediction.EDGE_HORIZON, 0.0001, "ten pixels under the top")
    var unknown := SaCursorPrediction.edge_distances(Vector2(5.0, 5.0), Rect2())
    assert_eq(unknown, PackedFloat32Array([1.0, 1.0, 1.0, 1.0]), "no view known reads as its middle")


## The same motion near an edge and away from it leads
## differently, which rows without a position term could never do.
func test_the_same_motion_leads_differently_beside_an_edge() -> void:
    var rows := _rows_with_edges(6.0)
    assert_eq(SaCursorPrediction.row_edges(rows), SaCursorPrediction.EDGE_COUNT, "the rows read four edges")
    var near := _swept_to(Vector2(VIEW.end.x - 30.0, VIEW.get_center().y), 600.0, rows)
    var away := _swept_to(VIEW.get_center(), 600.0, rows)
    var near_steps := near.grid_displacements()
    var away_steps := away.grid_displacements()
    assert_eq(near_steps.size(), away_steps.size())
    for i in near_steps.size():
        assert_almost_eq(near_steps[i], away_steps[i], 0.001, "the two motions are alike in displacement %d" % i)
    var near_lead := near.learned_lead(0.016, VIEW)
    var away_lead := away.learned_lead(0.016, VIEW)
    assert_true(away_lead.x > 0.0, "the middle leads the way the hand goes")
    assert_true(
        near_lead.x < away_lead.x - 1.0,
        "beside the right edge the lead holds back: %.2f against %.2f" % [near_lead.x, away_lead.x]
    )
    assert_almost_eq(near_lead.y, away_lead.y, 0.001, "and only along the edge's own axis")


## The rows shipped today were fitted before the recorder carried the view,
## so they read no position and the lead is the same wherever the hand is.
func test_the_rows_without_edges_read_no_position() -> void:
    var rows: Array = SaCursorLeadWeights.WEIGHTS
    var edges := SaCursorPrediction.row_edges(rows)
    if edges > 0:
        assert_eq(edges, SaCursorPrediction.EDGE_COUNT, "a fit with the edges reads all four")
        return
    var near := _swept_to(Vector2(VIEW.end.x - 30.0, VIEW.get_center().y), 600.0, rows)
    var away := _swept_to(VIEW.get_center(), 600.0, rows)
    var gap := near.learned_lead(0.016, VIEW).distance_to(away.learned_lead(0.016, VIEW))
    assert_almost_eq(gap, 0.0, 0.001, "no edge term, no difference")


## A table of a width the code cannot read is the fit's answer rather than
## weights applied to the wrong inputs.
func test_rows_of_another_width_fall_back_to_the_fit() -> void:
    var odd: Array = [[1.0, 2.0, 3.0, 4.0], [1.0, 2.0, 3.0, 4.0], [1.0, 2.0, 3.0, 4.0], [1.0, 2.0, 3.0, 4.0]]
    var prediction := _swept_to(VIEW.get_center(), 600.0, odd)
    assert_eq(prediction.learned_lead(0.016, VIEW), prediction.lead(0.016))


## A window with no canvas in it has no view, which reads as the middle.
func test_a_window_with_no_canvas_has_no_view() -> void:
    var window := Window.new()
    assert_eq(SaCursorPrediction.view_at(window, Vector2(10.0, 10.0)), Rect2())
    window.free()
