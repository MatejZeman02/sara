## The Tool Options docker keeps its rows when the interface
## scale changes live.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Setting `ui_scale` to 1.25 while Sara ran, and the
## docker was left with its title, the Advanced check and the line naming what
## the bar holds. Every row was still visible, in a scroll no row tall. The
## rows sit in a scroll, which asks for no height of its own, so the docker's
## floor held none of them, and the default layout's fit, which runs again on
## a scale change and gives up height from the lowest docker of a column first,
## took the Reference docker to its floor and then Tool Options to its own:
## 138 units on a 1920 by 1048 window at 1.25, where the rows need 136 more.
##
## This boots the real dockers in a viewport that embeds them, as
## `test_the_default_layout_opens_its_columns_under_the_bar.gd` does, restores
## the shipped default, and changes the scale the way `SaSettingsApply` does:
## the host's logical size shrinks by the scale, `ui_scale_changed` is emitted,
## and the store fits the layout again. The running app's proof is
## `scenarios/the-tool-options-docker-keeps-its-rows-when-the-interface-scale-changes-live.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const ToolOptionsFloor = preload("res://ui/dockers/tool_options/tool_options_floor.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

## A bar this wide shows every control it holds, so the docker leaves out Size,
## Opacity and the blend mode, as the running app's bar does at 1920.
const ROOMY := 4000.0

## A capture's window, the one the fault was met on.
const WINDOW := Vector2i(1920, 1048)

## The scales, in order: there, and back.
const SCALES: Array[float] = [1.0, 1.25, 1.0]

## A fresh profile, so the bar holds what a fresh bar holds.
static var scratch_profile: String = SaDataRoot.path("test_d25_live_scale_profile.cfg")

## The live layout file, absent before each boot, so the store copies the
## shipped default the way a first run does.
static var scratch_layout: String = SaDataRoot.path("test_d25_docker_layout.cfg")

var _saved_path: String
var _saved_row: bool
var _saved_user: float
var _saved_override: float
var _surface: SaSurface
var _machine: ToolMachine
var _options: ToolOptionsBar
var _bar: TopMenuBar
var _host: Node


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    _saved_row = SaSettings.second_row
    _saved_user = SaUI.user_scale
    _saved_override = SaUI.os_scale_override
    SaUI.os_scale_override = 1.0
    SaUI.user_scale = 1.0
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_scratch_files()
    SaSettings.load_settings()
    SaSettings.second_row = false
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _options = ToolOptionsBar.new()
    _options.target_tool_machine = _machine
    _options._ready()
    _bar = TopMenuBar.new()
    _bar.add_tool_options(_options)
    # Parented to an autoload rather than to the root, because the runner calls
    # a suite from its own `_ready`.
    _host = Node.new()
    _host.name = "D25Host"
    EventBus.add_child(_host)
    _host.add_child(_bar)
    _bar.set_anchor(SIDE_RIGHT, 0.0)
    _bar.size.x = ROOMY
    _bar.apply_layout_settings()


func after_each() -> void:
    _host.free()
    Fixtures.teardown(_surface, _machine)
    _remove_scratch_files()
    SaUI.user_scale = _saved_user
    SaUI.os_scale_override = _saved_override
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    SaSettings.second_row = _saved_row


## At 1.0, at 1.25 and back at 1.0, the docker shows every row it showed before
## the change, and its scroll is tall enough for the first of them to be read.
func test_a_live_scale_change_keeps_the_brush_rows_on_the_docker() -> void:
    var viewport := _viewport()
    var dockers := _boot(viewport)
    var docker := dockers.registered_docker_node(SaDockerIds.TOOL_OPTIONS) as ToolOptionsDocker
    var rows := docker.shown_keys()
    assert_true(rows.size() > ToolOptionsFloor.ROWS, "The brush shows more rows than the floor holds: %s" % [rows])
    for scale in SCALES:
        _change_scale(viewport, dockers, scale)
        var at := "at %s" % scale
        assert_eq(docker.shown_keys(), rows, "The docker shows the same rows %s" % at)
        var scroll := docker.find_child("Scroll", true, false) as ScrollContainer
        var shown := _scroll_height(docker, scroll)
        var wanted := _first_rows_height(docker)
        var said := "%s the scroll is %d units, and the first %d rows want %d" % [at, shown, ToolOptionsFloor.ROWS, wanted]
        assert_true(shown >= wanted, said)
    _host.remove_child(viewport)
    viewport.free()


## A row the docker has not laid out yet stacks its label over its control,
## and the floor is read side by side regardless. A docker hidden at boot lays
## its rows out at no width, and a floor read then was 379 units, which the
## layout store's settle kept as the docker's height.
func test_the_floor_reads_a_stacked_row_side_by_side() -> void:
    var row := ToolOptionsRow.new("", false)
    var label := Label.new()
    label.name = "Label"
    label.text = "Size by Pressure"
    row.add_child(label)
    var control := Button.new()
    control.text = "Off"
    row.add_child(control)
    row.size = Vector2(1, 0)
    row._place()
    # Asked afresh, because a control outside the tree keeps the minimum it
    # cached before the row stacked.
    var stacked := row.get_minimum_size().y
    var beside := maxf(label.get_combined_minimum_size().y, control.get_combined_minimum_size().y)
    assert_true(stacked > beside, "A row at no width stacks, %d over %d" % [stacked, beside])
    assert_eq(ToolOptionsFloor.side_by_side_height(row), beside, "and the floor reads it side by side")
    row.free()


## A tool with fewer rows than the floor holds asks for what it has, so the
## crop tool's docker is not held taller than its three rows.
func test_a_tool_with_fewer_rows_asks_for_what_it_has() -> void:
    var host := Node.new()
    var docker := ToolOptionsDocker.new()
    host.add_child(docker)
    docker.target_tool_machine = _machine
    _machine.set_active_tool(&"crop")
    docker.sync_from_tool()
    var shown := docker.shown_keys().size()
    assert_true(shown > 0 and shown < ToolOptionsFloor.ROWS, "Crop shows %d rows" % shown)
    var scroll := docker.find_child("Scroll", true, false) as ScrollContainer
    assert_eq(int(scroll.custom_minimum_size.y), _first_rows_height(docker), "and the scroll asks for those and no more")
    host.free()


## The viewport the dockers are embedded in, the main window's stand-in.
func _viewport() -> SubViewport:
    var viewport := SubViewport.new()
    viewport.size = WINDOW
    viewport.gui_embed_subwindows = true
    _host.add_child(viewport)
    return viewport


## The registry's dockers in *viewport*, with the bar bound, Tool Options
## following a brush and the shipped default restored, as at a first boot.
func _boot(viewport: SubViewport) -> MainDockers:
    var store := DockerLayoutStore.new()
    store.path = scratch_layout
    var dockers := MainDockers.new(SaUIRegistry.new(), store)
    viewport.add_child(dockers)
    dockers.bind_bar(_bar)
    dockers.register_builtin_dockers()
    var tool_options := dockers.registered_docker_node(SaDockerIds.TOOL_OPTIONS) as ToolOptionsDocker
    tool_options.peer_bar = _options
    tool_options.target_tool_machine = _machine
    _machine.set_active_tool(&"brush")
    tool_options.sync_from_tool()
    dockers.load_docker_layout()
    return dockers


## The scale change `SaSettingsApply._apply_ui_scale` makes: the main window's
## content shrinks to the window over the scale, the bus announces it, and the
## store fits the layout to the new host, which `MainDockers` does on both.
func _change_scale(viewport: SubViewport, dockers: MainDockers, scale: float) -> void:
    SaUI.user_scale = scale
    viewport.size_2d_override = Vector2i(Vector2(WINDOW) / scale) if scale != 1.0 else Vector2i()
    EventBus.ui_scale_changed.emit(SaUI.scale())
    dockers.layout_store.reflow_to_host()


## How tall *docker*'s scroll is at the size the layout gave the docker: the
## column, which is the window less the grip's corner but never shorter than
## its own minimum, less everything else in it.
func _scroll_height(docker: ToolOptionsDocker, scroll: ScrollContainer) -> int:
    var column := docker.content_column()
    var least := column.get_combined_minimum_size().y
    var around := least - scroll.get_combined_minimum_size().y
    return int(maxf(docker.size.y + column.offset_bottom, least) - around)


## The first rows the docker shows, side by side, with the gaps between them
## and the margin around them.
func _first_rows_height(docker: ToolOptionsDocker) -> int:
    var rows := docker._rows_box
    var held := 0.0
    var counted := 0
    for key: StringName in docker.shown_keys():
        if counted == ToolOptionsFloor.ROWS:
            break
        held += (docker._rows[key] as Control).get_combined_minimum_size().y
        counted += 1
    var margin := rows.get_parent() as MarginContainer
    held += rows.get_theme_constant(&"separation") * maxi(counted - 1, 0)
    held += margin.get_theme_constant(&"margin_top") + margin.get_theme_constant(&"margin_bottom")
    return int(held)


func _remove_scratch_files() -> void:
    for path: String in [scratch_layout, ProjectSettings.globalize_path(scratch_profile)]:
        for suffix: String in ["", ".bak", ".broken"]:
            if FileAccess.file_exists(path + suffix):
                DirAccess.remove_absolute(path + suffix)
