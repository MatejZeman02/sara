## A forked default layout fits the window after a live change
## of the interface scale.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Opening a docker forks the default to Default (Custom), and a later change of
## scale must not only keep the fork's dockers on the host at the size the old
## scale left them. Opened at 1.0 and changed live to 1.25, Layers
## would stand from 314 to 838 over the Colour Picker and the Reference over Tool
## Options, both feet on the host's edge under the status line.
##
## This boots the real dockers in a viewport that embeds them, as the default column suite
## does, on the 1920 by 1080 window the default was written for, opens the
## closed Reference at 1.0 so the layout forks, and changes the scale live. The
## running app is
## `scenarios/a-forked-default-layout-fits-the-window-after-a-live-change-of-the.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

## A bar this wide shows every control it holds, as the running app's does.
const ROOMY := 4000.0

## The window the default was written for.
const WINDOW := Vector2i(1920, 1080)

static var scratch_profile: String = SaDataRoot.path("test_a2_column_profile.cfg")
static var scratch_layout: String = SaDataRoot.path("test_a2_docker_layout.cfg")

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
    _host.name = "A2Host"
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


## Opened at 1.0 with the closed Reference opened, so the layout forks, and
## changed live to 1.25: every open docker stands inside the window with its
## foot above the status line, over no docker it did not cover at 1.0, and no
## smaller than its floor.
func test_the_fork_fits_the_window_at_1_25() -> void:
    var dockers := _forked_at_one()
    var before := _open_rects(dockers)
    _change_scale(dockers, 1.25)
    var after := _open_rects(dockers)
    assert_eq(after.keys(), before.keys(), "The same dockers are open: %s" % [after.keys()])
    var line := _above_the_line(1.25)
    var host := Vector2i(Vector2(WINDOW) / 1.25)
    for section: String in after:
        var rect: Rect2i = after[section]
        assert_true(rect.position.x >= 0 and rect.end.x <= host.x, "%s %s is inside the window" % [section, rect])
        assert_true(rect.position.y >= 0 and rect.end.y <= line, "%s %s ends above the line at %d" % [section, rect, line])
        var win := _window(dockers, section)
        assert_true(
            rect.size.x >= win.min_size.x and rect.size.y >= win.min_size.y, "%s keeps its floor %s" % [section, win.min_size]
        )
        for other: String in after:
            if other != section and not before[section].intersects(before[other]):
                assert_false(rect.intersects(after[other]), "%s %s is clear of %s %s" % [section, rect, other, after[other]])


## The fork changed back to 1.0 stands where it stood before the change, after
## a save at 1.25 as well, since a save comes with every focus a window loses,
## and the store's memory holds it there.
func test_the_fork_changed_back_to_1_0_stands_where_it_stood() -> void:
    var dockers := _forked_at_one()
    var before := _open_rects(dockers)
    _change_scale(dockers, 1.25)
    dockers.layout_store.save()
    _change_scale(dockers, 1.0)
    assert_eq(_open_rects(dockers), before, "Every docker is back where the fork had it")
    assert_eq(_stored_rects(dockers, 1.0), before, "and the file holds the painter's rectangles")
    # The settle loop re-asserts what the store's memory answers, and the
    # running app's Reference stayed at its fitted place when that was still
    # the place the fit had given it.
    var held := dockers.layout_store.stored_positions()
    for section: String in before:
        assert_eq(held.get(section), before[section].position, "%s is held where the painter put it" % section)


## A change of scale that leaves every docker of the fork inside the host moves
## nothing, which a change to 0.8 does, the host growing to 2400 by 1350.
func test_a_change_that_leaves_the_fork_inside_moves_nothing() -> void:
    var dockers := _forked_at_one()
    var before := _open_rects(dockers)
    _change_scale(dockers, 0.8)
    assert_eq(_open_rects(dockers), before, "Nothing moved at 0.8")


## The default booted at 1.0 with the closed Reference opened as a painter
## opens it, which forks the layout.
func _forked_at_one() -> MainDockers:
    var dockers := _boot_at(1.0)
    dockers.toggle_docker_by_id(SaDockerIds.REFERENCE)
    assert_true(dockers.registered_docker_node(SaDockerIds.REFERENCE).visible, "The chord opens the Reference")
    assert_true(
        dockers.layout_store.current_preset().ends_with(SaDockerLayoutPresets.FORK_SUFFIX),
        "and the layout forks: %s" % dockers.layout_store.current_preset()
    )
    return dockers


## The rectangle of each open docker of *dockers*, by section.
func _open_rects(dockers: MainDockers) -> Dictionary:
    var out: Dictionary = {}
    for config: Dictionary in dockers.get_docker_config():
        var win: Window = config["node"] as Window
        if win != null and win.visible:
            out[DockerLayoutStore.section_for(config)] = Rect2i(win.position, win.size)
    return out


## The rectangle the live file holds for each open docker of *dockers*, at
## *scale*.
func _stored_rects(dockers: MainDockers, scale: float) -> Dictionary:
    var live := ConfigFile.new()
    live.load(dockers.layout_store.path)
    var out: Dictionary = {}
    for section: String in _open_rects(dockers):
        var pos: Vector2i = live.get_value(section, "position", Vector2i())
        var sz: Vector2i = live.get_value(section, "size", Vector2i())
        out[section] = Rect2i(Vector2i(Vector2(pos) * scale), Vector2i(Vector2(sz) * scale))
    return out


func _window(dockers: MainDockers, section: String) -> Window:
    for config: Dictionary in dockers.get_docker_config():
        if DockerLayoutStore.section_for(config) == section:
            return config["node"] as Window
    return null


## The registry's dockers in a viewport of the window's size at *scale*, with
## the bar bound, Tool Options following a brush and the shipped default
## restored, as at a first boot at that scale.
func _boot_at(scale: float) -> MainDockers:
    SaUI.user_scale = scale
    var viewport := SubViewport.new()
    viewport.name = "A2Viewport"
    viewport.size = WINDOW
    viewport.size_2d_override = Vector2i(Vector2(WINDOW) / scale) if scale != 1.0 else Vector2i()
    viewport.gui_embed_subwindows = true
    _host.add_child(viewport)
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


## The last boot's viewport freed and its layout file gone, so the next boot is
## a first run again.
func _drop_the_boot() -> void:
    var viewport := _host.get_node_or_null("A2Viewport")
    if viewport != null:
        _host.remove_child(viewport)
        viewport.free()
    _remove_scratch_files()
    SaUI.user_scale = 1.0


## The scale change `SaSettingsApply._apply_ui_scale` makes, as the default column suite
## makes it: the host shrinks by the scale, the bus says so, and the store fits
## the layout again.
func _change_scale(dockers: MainDockers, scale: float) -> void:
    SaUI.user_scale = scale
    var viewport := dockers.get_parent() as SubViewport
    viewport.size_2d_override = Vector2i(Vector2(WINDOW) / scale) if scale != 1.0 else Vector2i()
    EventBus.ui_scale_changed.emit(SaUI.scale())
    dockers.layout_store.reflow_to_host()


## The last row a docker's foot may reach at *scale*, the status line's top.
func _above_the_line(scale: float) -> int:
    return int(WINDOW.y / scale) - SaDockerLayoutRefit.status_rows_in(1.0)


func _remove_scratch_files() -> void:
    for path: String in [scratch_layout, ProjectSettings.globalize_path(scratch_profile)]:
        for suffix: String in ["", ".bak", ".broken"]:
            if FileAccess.file_exists(path + suffix):
                DirAccess.remove_absolute(path + suffix)
