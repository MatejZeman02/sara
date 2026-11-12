## With Advanced on, the Tool Options docker shows its check and its values
## whole, at the default width and at its floor.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The check once read "Adva" and the value cells read "100%,
## Pressure" and "100%, no sensor" cut at the docker's right edge. A value
## button asked for its text's width, the scroll's horizontal mode is disabled
## so the column asked for its widest row, and the column ran past the docker or
## the docker grew to hold it, 350 at its default 300 on the running app. Now a
## value button clips with an ellipsis above a small floor, and
## `ToolOptionsDocker.LabelledRow` gives a value its whole width before the
## label gets the rest.
##
## The docker is built detached under a plain Node, as the other suites here
## build it, and its containers are sorted by hand, outside in, because a suite
## cannot await the frame a `queue_sort` is answered on.
## `scenarios/advanced-mode-shows-its-check-and-its-values-whole.json` is the
## same on the running app.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

## The docker's default width and its floor, in logical pixels.
const DEFAULT_WIDTH := 300
const FLOOR_WIDTH := 160

var _surface: SaSurface
var _machine: ToolMachine
var _host: Node
var _docker: ToolOptionsDocker
var _advanced: bool

## Where the column lives in the docker, and the host in the tree it is lent to.
var _home: Node
var _stage: Control


func before_each() -> void:
    _advanced = SaSettings.advanced_options
    SaSettings.advanced_options = true
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _host = Node.new()
    _docker = ToolOptionsDocker.new()
    _host.add_child(_docker)
    _docker.target_tool_machine = _machine
    _machine.set_active_tool(&"brush")
    _docker.sync_from_tool()
    # The two values that were cut, put on the rows they were cut on,
    # so the claim does not rest on what a fresh brush happens to carry.
    var settings: Object = _machine.get_tool(&"brush").get("settings")
    var opacity := settings.get("opacity_option") as SaCurveOption
    opacity.enabled = true
    opacity.use_curve = true
    opacity.strength = 1.0
    opacity.set_sensor(SaSensor.create(SaSensor.Id.PRESSURE, true))
    var flow := settings.get("flow_option") as SaCurveOption
    flow.enabled = true
    flow.use_curve = true
    flow.strength = 1.0
    _docker.sync_values_from_tool()


func after_each() -> void:
    if _stage != null:
        var column := _stage.get_child(0)
        _stage.remove_child(column)
        _home.add_child(column)
        _home.move_child(column, 0)
        _stage.free()
        _stage = null
    _host.free()
    Fixtures.teardown(_surface, _machine)
    SaSettings.advanced_options = _advanced


## At the default width every row and the check lie inside the docker, and the
## two values that were cut read whole.
func test_at_the_default_width_the_check_and_every_value_are_whole() -> void:
    var column := _lay_out(DEFAULT_WIDTH)
    var width := DockerUtils.px(DEFAULT_WIDTH)
    assert_true(
        column.get_combined_minimum_size().x <= width,
        "The column asks for %d at most, within the docker's %d" % [column.get_combined_minimum_size().x, width]
    )
    _assert_the_check_is_whole(column, width)
    _assert_every_row_is_inside(column, width)
    for key: StringName in [&"opacity_option", &"flow_option"]:
        var button := _docker.options.control(key) as Button
        assert_true(
            button.size.x >= _text_width(button, button.text) - 0.5,
            "'%s' has its whole width, %d for %d" % [button.text, button.size.x, _text_width(button, button.text)]
        )
        assert_false(button.tooltip_text.begins_with(button.text), "and its tooltip says what the option does")
    var label := _label_of(&"saturation_option")
    if label != null:
        assert_true(
            label.size.x >= _text_width(label, label.text) - 0.5, "The longest label, '%s', reads whole as well" % label.text
        )


## At the floor the docker stops where a control with a width of its own stops
## it, a curve's graph or the stamp's pattern chooser, and at that width the
## check keeps its word, every row ends inside, and a value that no longer fits
## is cut with its whole text in the tooltip.
func test_at_the_floor_a_cut_value_says_its_whole_text_in_the_tooltip() -> void:
    var column := _lay_out(FLOOR_WIDTH)
    var rows_box := _docker._rows_box
    var content := DockerUtils.px(FLOOR_WIDTH) - (column.get_combined_minimum_size().x - rows_box.get_combined_minimum_size().x)
    var held_by: Array[String] = []
    for key: StringName in _docker.shown_keys():
        var row := _docker._rows.get(key, null) as Control
        if row == null or not row.visible or row.get_combined_minimum_size().x <= content:
            continue
        held_by.append(String(row.name))
        var labelled := row as ToolOptionsRow
        assert_not_null(labelled, "%s is wider than the floor and is a labelled row" % row.name)
        if labelled == null:
            continue
        var control := labelled.get_child(labelled.get_child_count() - 1) as Control
        assert_false(control is Button or control is FactorSlider, "%s is not held wide by a value or a slider" % row.name)
        assert_eq(
            row.get_combined_minimum_size().x,
            control.get_combined_minimum_size().x,
            "%s asks for its control's own width, with the label above it rather than beside" % row.name
        )
    assert_false(held_by.is_empty(), "The brush has a control with a width of its own, %s" % ", ".join(held_by))

    var width := column.size.x
    _assert_the_check_is_whole(column, width)
    _assert_every_row_is_inside(column, width)
    var cut := 0
    for key: StringName in [&"opacity_option", &"flow_option"]:
        var button := _docker.options.control(key) as Button
        assert_eq(button.text_overrun_behavior, SaTheme.TEXT_CUT, "'%s' cuts with the theme's ellipsis" % button.text)
        if button.size.x < _text_width(button, button.text) - 0.5:
            cut += 1
            assert_eq(button.tooltip_text.get_slice("\n", 0), button.text, "and cut, its tooltip opens with its whole text")
    assert_true(cut > 0, "At the floor at least one of the two values is cut, %d were" % cut)


## Lays the docker out at *logical_width* and answers the column every row and
## the header sit in.
##
## The column is lent to a host inside the tree for the measuring, because a
## box container lays out only the children visible in the tree, and is given
## back before the docker is freed. The docker itself stays out, so its
## `_ready` never runs, as in every other suite here.
func _lay_out(logical_width: int) -> Control:
    var column := _docker.drag_handle.get_parent() as Control
    _home = column.get_parent()
    _home.remove_child(column)
    _stage = Control.new()
    _stage.name = "AdvancedStage"
    EventBus.add_child(_stage)
    _stage.add_child(column)
    column.size = Vector2(DockerUtils.px(logical_width), DockerUtils.px(700))
    _sort(column)
    # Twice, because a row that put its control under its label asked for a
    # new height on the first pass.
    _sort(column)
    return column


func _sort(node: Node) -> void:
    if node is Container:
        (node as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child: Node in node.get_children():
        _sort(child)


func _assert_the_check_is_whole(column: Control, width: float) -> void:
    var check := _docker.header.check
    var rect := _rect_in(check, column)
    assert_true(
        rect.size.x >= check.get_combined_minimum_size().x - 0.5,
        "The check is as wide as its whole word, %d for %d" % [rect.size.x, check.get_combined_minimum_size().x]
    )
    assert_true(rect.position.x >= 0.0 and rect.end.x <= width + 0.5, "and lies inside the docker, %s in %d" % [rect, width])


func _assert_every_row_is_inside(column: Control, width: float) -> void:
    var outside: Array[String] = []
    for row: StringName in _docker.shown_keys():
        var node := _docker._rows.get(row, null) as Control
        if node == null or not node.visible:
            continue
        var rect := _rect_in(node, column)
        if rect.end.x > width + 0.5:
            outside.append("%s ends at %d" % [node.name, rect.end.x])
        for child in node.get_children():
            var part := child as Control
            if part != null and part.visible and _rect_in(part, column).end.x > width + 0.5:
                outside.append("%s/%s ends at %d" % [node.name, part.name, _rect_in(part, column).end.x])
    assert_true(outside.is_empty(), "Every row ends inside the docker's %d: %s" % [width, ", ".join(outside)])


## *control*'s rectangle in *column*'s space, summed up the parents, because
## nothing here is in a tree for a global rectangle to mean anything.
func _rect_in(control: Control, column: Control) -> Rect2:
    var at := Vector2.ZERO
    var node: Control = control
    while node != null and node != column:
        at += node.position
        node = node.get_parent() as Control
    return Rect2(at, control.size)


func _label_of(key: StringName) -> Label:
    var row := _docker._rows.get(key, null) as Control
    return row.get_node_or_null("Label") as Label if row != null else null


## How wide *text* draws on *control*, its stylebox's margins included.
func _text_width(control: Control, text: String) -> float:
    var font := control.get_theme_font("font")
    var font_size := control.get_theme_font_size("font_size")
    var box := control.get_theme_stylebox("normal")
    return ceilf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + box.get_minimum_size().x)
