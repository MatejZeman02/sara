## `Kind.CURVE` is a row, and the brush tip's falloff is on it.
##
## `Kind.CURVE` is a bare response curve with no sensors. An imported Krita
## falloff lands on `SaBrushTip.softness_curve`, a `Curve`, and the row is the
## surface that shows it.
##
## The row is built here rather than through the brush editor window, which
## `ui/brush_editor/tests/test_brush_editor_window.gd` already stands up: this is about one kind
## and the maths behind it, and both surfaces build their rows through the same
## `ToolOptionControls`, so a control that works here works on both.
##
## `scenarios/the-falloff-curve-gets-a-row.json` is the same claim on the
## running app, where the graph is shot, dragged and shot again beside the stroke
## each shape paints.
extends "res://tests/test_framework.gd"


## What the row is declared over: a settings resource with a `Curve` on it, the
## shape `SaBrushTip` has and the stamp brush declares `tip:softness_curve`
## against.
class FalloffSettings:
    extends Resource

    @export var softness_curve: Curve = null


## A settings resource that declares no curve at all, for the row that has to be
## skipped rather than crash.
class BareSettings:
    extends Resource

    @export var amount: float = 0.5


class FalloffTool:
    extends ToolState

    var settings: Resource = null

    func _init(with_settings: Resource) -> void:
        settings = with_settings


var _host: Control = null
var _controls: ToolOptionControls = null
var _written: Array = []


func before_each() -> void:
    _host = Control.new()
    _host.name = "B2Host"
    _controls = ToolOptionControls.new(_host)
    _controls.option_written.connect(func(key: StringName, value: Variant) -> void: _written.append([key, value]))
    _written.clear()


func after_each() -> void:
    _controls = null
    if _host != null:
        _host.free()
        _host = null


## A descending falloff, which is what a tip has to hold: coverage 1 at the
## centre and 0 at the rim.
func _descending() -> Curve:
    var curve := Curve.new()
    curve.add_point(Vector2(0.0, 1.0))
    curve.add_point(Vector2(1.0, 0.0))
    return curve


func _spec() -> SaOptionSpec:
    var spec := SaOptionSpec.make(&"tip_falloff", "Falloff", SaOptionSpec.Kind.CURVE)
    spec.property = ^"softness_curve"
    return spec


func _descriptor(spec: SaOptionSpec) -> SaToolDescriptor:
    var descriptor := SaToolDescriptor.new()
    descriptor.id = &"b2_tool"
    descriptor.options.assign([spec] as Array[SaOptionSpec])
    return descriptor


func _build(settings: Resource, spec: SaOptionSpec) -> FalloffTool:
    var tool := FalloffTool.new(settings)
    _controls.build_for(_descriptor(spec))
    _controls.sync(tool, &"b2_tool", 1.0)
    return tool


func _graph() -> SaCurveEditor:
    return SaCurveRow.graph_of(_controls.control(&"tip_falloff"))


func test_the_reserved_kind_builds_a_row_for_a_bare_curve() -> void:
    var settings := FalloffSettings.new()
    settings.softness_curve = _descending()
    _build(settings, _spec())
    var control := _controls.control(&"tip_falloff")
    assert_not_null(control, "A CURVE spec builds a control, where it used to build nothing")
    assert_eq(control.name, "TipFalloffCurve", "named the way every other row is, so a dump reads")
    assert_not_null(_graph(), "and the graph is inside it")


## The frame is an `AspectRatioContainer` for a reason a comment cannot prove:
## both surfaces zero a control's minimum width, so a bare editor would come out
## as wide as the page and 160 tall.
func test_the_graph_stays_square_when_the_row_zeroes_its_width() -> void:
    var settings := FalloffSettings.new()
    settings.softness_curve = _descending()
    _build(settings, _spec())
    var frame := _controls.control(&"tip_falloff") as AspectRatioContainer
    assert_not_null(frame, "The row's control is the aspect frame")
    assert_eq(frame.ratio, 1.0, "held square")
    frame.custom_minimum_size.x = 0
    assert_true(frame.custom_minimum_size.y > 0.0, "and the height is what keeps it from collapsing")


func test_the_control_shows_the_curve_the_tool_holds() -> void:
    var settings := FalloffSettings.new()
    var curve := _descending()
    curve.add_point(Vector2(0.5, 0.25))
    settings.softness_curve = curve
    _build(settings, _spec())
    var points := _graph().points
    assert_eq(points.size(), 3, "Three points on the curve, three on the graph")
    assert_almost_eq(points[1].x, 0.5, 1e-4, "at the x the curve holds")
    assert_almost_eq(points[1].y, 0.25, 1e-4, "and the y")


func test_the_control_reads_back_what_was_drawn() -> void:
    var settings := FalloffSettings.new()
    settings.softness_curve = _descending()
    _build(settings, _spec())
    _graph().set_points(PackedVector2Array([Vector2(0.0, 1.0), Vector2(0.4, 0.8), Vector2(1.0, 0.0)]))
    var written := settings.softness_curve
    assert_eq(written.point_count, 3, "The drag wrote three points onto the tool's own curve")
    assert_almost_eq(written.get_point_position(1).x, 0.4, 1e-4, "at the x that was drawn")
    assert_almost_eq(written.get_point_position(1).y, 0.8, 1e-4, "and the y")


## The write is a fresh `Curve` rather than the held one edited in place, which
## is what lets the dirty check see it at all.
func test_the_drag_replaces_the_curve_rather_than_editing_it() -> void:
    var settings := FalloffSettings.new()
    var before := _descending()
    settings.softness_curve = before
    _build(settings, _spec())
    _graph().set_points(PackedVector2Array([Vector2(0.0, 1.0), Vector2(0.4, 0.8), Vector2(1.0, 0.0)]))
    assert_false(settings.softness_curve == before, "A new resource is on the settings")
    assert_eq(before.point_count, 2, "and the one that was there is untouched")


func test_a_drag_reports_the_write_the_dirty_indicator_listens_for() -> void:
    var settings := FalloffSettings.new()
    settings.softness_curve = _descending()
    _build(settings, _spec())
    _graph().set_points(PackedVector2Array([Vector2(0.0, 1.0), Vector2(0.4, 0.8), Vector2(1.0, 0.0)]))
    assert_eq(_written.size(), 1, "One write reported")
    assert_eq(_written[0][0], &"tip_falloff", "for this row")
    assert_true(_written[0][1] is Curve, "carrying the curve itself")


## `sync` mutes the controls while it mirrors, so showing a value must not write
## it straight back and mark a brush nobody touched as changed.
func test_showing_a_value_does_not_report_a_write() -> void:
    var settings := FalloffSettings.new()
    settings.softness_curve = _descending()
    _build(settings, _spec())
    _written.clear()
    _controls.sync(FalloffTool.new(settings), &"b2_tool", 1.0)
    assert_eq(_written.size(), 0, "A mirror is not a move")


func test_a_tool_with_no_curve_behind_the_row_is_skipped_rather_than_crashing() -> void:
    var spec := _spec()
    spec.property = ^"nothing_of_the_sort"
    _build(BareSettings.new(), spec)
    assert_not_null(_controls.control(&"tip_falloff"), "The row is still built")
    assert_eq(_graph().points.size(), 2, "and shows the identity rather than an empty square")


func test_a_null_curve_shows_the_identity() -> void:
    var settings := FalloffSettings.new()
    settings.softness_curve = null
    _build(settings, _spec())
    var points := _graph().points
    assert_eq(points.size(), 2, "The diagonal, which is a curve nobody has drawn yet")
    assert_almost_eq(points[0].y, 0.0, 1e-4, "from the bottom left")
    assert_almost_eq(points[1].y, 1.0, 1e-4, "to the top right")


## The whole reason `curve_of` sets tangents. A `Curve` bakes cubic Hermite
## through the tangents it holds, and a fresh point's are zero, so the two-point
## descending curve Godot bakes without them is an S that leaves and arrives flat
## while the graph beside it draws a straight line.
func test_the_baked_curve_is_the_curve_the_graph_draws() -> void:
    var points := PackedVector2Array([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])
    var curve := SaCurveRow.curve_of(points)
    var drawn := SaCurveEditor.sample_curve(points, 65)
    for index in drawn.size():
        var at := float(index) / float(drawn.size() - 1)
        assert_almost_eq(curve.sample_baked(at), drawn[index], 5e-3, "The bake follows the drawing at x %f" % at)


func test_a_curve_left_at_zero_tangents_would_not_have_followed_the_drawing() -> void:
    var bare := Curve.new()
    bare.add_point(Vector2(0.0, 1.0))
    bare.add_point(Vector2(1.0, 0.0))
    var straight := 1.0 - 0.25
    assert_true(
        absf(bare.sample_baked(0.25) - straight) > 0.05,
        "The default bake is an S, which is why the tangents are set rather than left"
    )


func test_a_three_point_shape_bakes_the_way_it_is_drawn() -> void:
    var points := PackedVector2Array([Vector2(0.0, 1.0), Vector2(0.3, 0.8), Vector2(1.0, 0.0)])
    var curve := SaCurveRow.curve_of(points)
    var drawn := SaCurveEditor.sample_curve(points, 65)
    for index in drawn.size():
        var at := float(index) / float(drawn.size() - 1)
        assert_almost_eq(curve.sample_baked(at), drawn[index], 1e-2, "The bake follows the drawing at x %f" % at)


func test_a_curves_range_survives_the_round_trip() -> void:
    var wide := Curve.new()
    wide.min_value = -1.0
    wide.max_value = 1.0
    wide.add_point(Vector2(0.0, 1.0))
    wide.add_point(Vector2(1.0, -1.0))
    var points := SaCurveRow.points_of(wide)
    assert_almost_eq(points[0].y, 1.0, 1e-4, "The top of the range is the top of the graph")
    assert_almost_eq(points[1].y, 0.0, 1e-4, "and the bottom is the bottom")
    var back := SaCurveRow.curve_of(points, wide)
    assert_eq(back.min_value, -1.0, "and the range comes back")
    assert_eq(back.max_value, 1.0, "at both ends")
    assert_almost_eq(back.get_point_position(1).y, -1.0, 1e-4, "with the point where it was")


## A defect this suite guards against. `SaBrushEditorSession.settings_match` walks
## `PROPERTY_USAGE_SCRIPT_VARIABLE`, and a `Curve` has none: its points are in
## the engine's `_data`. Two different shapes compared as the same brush, so the
## editor's dirty indicator would have said "no changes" after a redrawn falloff.
func test_the_dirty_check_sees_a_redrawn_falloff() -> void:
    var before := _descending()
    var after := SaCurveRow.curve_of(PackedVector2Array([Vector2(0.0, 1.0), Vector2(0.4, 0.8), Vector2(1.0, 0.0)]))
    assert_false(SaBrushEditorSession.values_match(before, after), "A redrawn curve is a changed brush")
    assert_true(SaBrushEditorSession.values_match(before, _descending()), "and the same shape is not")


func test_the_dirty_check_still_matches_a_curve_with_itself() -> void:
    var curve := _descending()
    assert_true(SaBrushEditorSession.values_match(curve, curve), "One curve is itself")
    assert_true(SaBrushEditorSession.values_match(null, null), "and two absent ones are the same absence")
    assert_false(SaBrushEditorSession.values_match(curve, null), "where one absent one is not")


## A settings resource holding a falloff is compared through the same door, so
## the row's write reaches the indicator rather than stopping at `values_match`.
func test_a_settings_resource_carries_the_curve_into_the_comparison() -> void:
    var left := FalloffSettings.new()
    var right := FalloffSettings.new()
    left.softness_curve = _descending()
    right.softness_curve = _descending()
    assert_true(SaBrushEditorSession.settings_match(left, right), "Two brushes with the same falloff match")
    right.softness_curve = SaCurveRow.curve_of(PackedVector2Array([Vector2(0.0, 1.0), Vector2(0.4, 0.8), Vector2(1.0, 0.0)]))
    assert_false(SaBrushEditorSession.settings_match(left, right), "and two with different ones do not")
