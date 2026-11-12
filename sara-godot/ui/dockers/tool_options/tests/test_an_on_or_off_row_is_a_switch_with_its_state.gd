## Tool Options draws an on or off row as a switch with its state.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Erase row was an icon alone, stretched across the value column, so it
## read as an empty text field and looked like the curve button beside it. Now
## every toggle row writes On or Off beside its icon and sits at its own width at the column's start.
##
## The docker is built detached under a plain Node and laid out by hand, as
## the Advanced mode suite does it. `scenarios/tool-options-draws-an-on-or-off-row-as-a-switch-with-its-state.json`
## is the same on the running app.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

## The docker's default width, in logical pixels.
const DEFAULT_WIDTH := 300

var _surface: SaSurface
var _machine: ToolMachine
var _host: Node
var _docker: ToolOptionsDocker

## Where the column lives in the docker, and the host in the tree it is lent to.
var _home: Node
var _stage: Control


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _host = Node.new()
    _docker = ToolOptionsDocker.new()
    _host.add_child(_docker)
    _docker.target_tool_machine = _machine
    _machine.set_active_tool(&"brush")
    _docker.sync_from_tool()


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


## Erase writes Off, then On once it is pressed, and keeps its icon beside the
## word.
func test_erase_writes_off_and_then_on() -> void:
    var erase := _docker.options.control(&"eraser_toggled") as Button
    assert_not_null(erase, "The brush has an Erase row")
    if erase == null:
        return
    assert_not_null(erase.icon, "and it keeps its icon")
    assert_false(erase.button_pressed, "A fresh brush paints")
    assert_eq(erase.text, "Off", "and its Erase row says so in a word")

    erase.button_pressed = true
    assert_eq(erase.text, "On", "Pressed, the row says On")
    erase.button_pressed = false
    assert_eq(erase.text, "Off", "and Off again when it is let go")


## Laid out at the docker's default width, the switch is narrower than the
## value column, at the column's start, and as wide on as off.
func test_erase_is_narrower_than_the_value_column() -> void:
    var erase := _docker.options.control(&"eraser_toggled") as Button
    assert_not_null(erase, "The brush has an Erase row")
    if erase == null:
        return
    _lay_out(DEFAULT_WIDTH)
    var row := erase.get_parent() as ToolOptionsRow
    var label := row.get_node("Label") as Label
    var column := row.size.x - label.size.x
    assert_true(erase.size.x < column, "The switch is %d wide in a value column of %d" % [erase.size.x, column])
    var asked := erase.get_minimum_size().x
    assert_true(erase.size.x >= asked - 0.5, "and is not cut, %d for %d" % [erase.size.x, asked])
    assert_true(erase.position.x <= label.size.x + DockerUtils.px(16), "It sits at the column's start, at %d" % erase.position.x)
    var off_width := erase.size.x
    erase.button_pressed = true
    _sort(row)
    assert_almost_eq(erase.size.x, off_width, 0.5, "and turning it on does not move its edge")
    erase.button_pressed = false
    erase.button_pressed = true
    _sort(row)
    assert_almost_eq(erase.size.x, off_width, 0.5, "nor does turning it on a second time")
    # An expanding icon is drawn in whatever room the word leaves, and at the
    # word's own width it was not drawn at all.
    var font := erase.get_theme_font("font")
    var word := font.get_string_size("Off", HORIZONTAL_ALIGNMENT_LEFT, -1, erase.get_theme_font_size("font_size")).x
    var icon_room := erase.get_theme_constant("icon_max_width")
    var room := word + icon_room
    assert_true(erase.size.x >= room, "The icon has room beside the word, %d for %d" % [erase.size.x, room])


## Every toggle row of the brush says On or Off, the ones with a word of their
## own as well as Erase with its icon.
func test_every_toggle_row_says_on_or_off() -> void:
    var tool_id := _docker.shown_tool_id()
    var toggles := 0
    for key: StringName in _docker.shown_keys():
        var spec := _docker.options.spec_for(key, tool_id)
        if spec == null or spec.kind != SaOptionSpec.Kind.BOOL:
            continue
        var button := _docker.options.control(key) as Button
        if button == null:
            continue
        toggles += 1
        var expected := "On" if button.button_pressed else "Off"
        assert_eq(button.text, expected, "%s says %s" % [key, expected])
        assert_eq(button.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN, "and is not stretched across the row")
    assert_true(toggles > 0, "The brush shows at least one toggle row, %d" % toggles)


## Lays the docker out at *logical_width*, as the Advanced mode suite does.
func _lay_out(logical_width: int) -> Control:
    var column := _docker.drag_handle.get_parent() as Control
    _home = column.get_parent()
    _home.remove_child(column)
    _stage = Control.new()
    _stage.name = "SwitchStage"
    EventBus.add_child(_stage)
    _stage.add_child(column)
    column.size = Vector2(DockerUtils.px(logical_width), DockerUtils.px(700))
    _sort(column)
    _sort(column)
    return column


func _sort(node: Node) -> void:
    if node is Container:
        (node as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child: Node in node.get_children():
        _sort(child)
