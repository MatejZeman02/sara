## The default layout opens Tool Options in its column under
## the bar, at 1920 by 1048 and at 1280 by 1024, with the Brush Presets under
## it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A retake of the shot records found Tool Options' title bar across the menu
## bar from Edit to Select, with Brush Presets stacked on it, in every picture
## the default layout opened. The line at the docker's foot, which names the
## rows the bar holds, wraps. A docker is hidden at boot and a hidden window
## lays out nothing, so the engine held the line at its own minimum width, one
## pixel, where it read one letter a row and asked the column for 1113 units.
## The layout store reads the column's want as the docker's floor when it fits
## the default layout, and a docker taller than the window is clamped to its
## top.
##
## `ui/layout/fit/tests/test_the_default_layout_fits_the_screen.gd` fits probe
## windows whose floors it writes down, and it passed throughout. This suite
## boots the real dockers instead, hidden in a viewport that embeds them the
## way the main window does, with Tool Options bound to a brush beside a roomy
## bar so its foot line is written while it is hidden, as at boot. The store
## then restores the shipped default and every docker it opens is read. The
## running app's proof is
## `scenarios/the-default-layout-opens-tool-options-and-brush-presets-in-their-column-under-the-bar.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

## A bar this wide shows every control it holds, so the docker leaves out Size,
## Opacity and the blend mode and names them at its foot.
const ROOMY := 4000.0

## A capture's window, and the screen a Windows run met the default on.
const HOSTS: Array[Vector2i] = [Vector2i(1920, 1048), Vector2i(1280, 1024)]

## The dockers a fresh profile opens. The Brush Presets is one, because the
## window is hard to find otherwise.
const OPENED: Array[String] = [
    "BrushPresetsDocker",
    "ColorDocker",
    "LayersDocker",
    "MinimapDocker",
    "ToolBoxDocker",
    "ToolOptionsDocker",
]

## A fresh profile, so the bar holds what a fresh bar holds.
static var scratch_profile: String = SaDataRoot.path("test_d23_default_layout_profile.cfg")

## The live layout file, absent before each boot, so the store copies the
## shipped default the way a first run does.
static var scratch_layout: String = SaDataRoot.path("test_d23_docker_layout.cfg")

var _saved_path: String
var _saved_row: bool
var _surface: SaSurface
var _machine: ToolMachine
var _options: ToolOptionsBar
var _bar: TopMenuBar
var _host: Node


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    _saved_row = SaSettings.second_row
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
    _host.name = "D23Host"
    EventBus.add_child(_host)
    _host.add_child(_bar)
    # A bar outside a container keeps the width written to it only with its
    # anchors pinned together.
    _bar.set_anchor(SIDE_RIGHT, 0.0)
    _bar.size.x = ROOMY
    _bar.apply_layout_settings()


func after_each() -> void:
    _host.free()
    Fixtures.teardown(_surface, _machine)
    _remove_scratch_files()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    SaSettings.second_row = _saved_row


## At both sizes every docker the default opens has its title bar below the
## menu bar and lies wholly on the window, and no two of them overlap. Tool
## Options heads the left column, and the Brush Presets stands open in that
## column under it.
func test_every_docker_the_default_opens_stands_under_the_bar_and_beside_the_others() -> void:
    for host_size in HOSTS:
        var dockers := _boot(host_size)
        var top := dockers.below_bar()
        var rects := _shown(dockers)
        var names := rects.keys()
        names.sort()
        assert_eq(", ".join(names), ", ".join(OPENED), "The default opens its six dockers at %s" % host_size)
        var window := Rect2i(Vector2i(0, top), host_size - Vector2i(0, top))
        for i in names.size():
            var name_i: String = names[i]
            var rect: Rect2i = rects[name_i]
            var below := "%s's title bar starts below the bar's %d at %s: %s" % [name_i, top, host_size, rect]
            assert_true(rect.position.y >= top, below)
            assert_true(window.encloses(rect), "and the whole of it is on the window, %s in %s" % [rect, window])
            for j in range(i + 1, names.size()):
                var other: Rect2i = rects[names[j]]
                var apart := "%s %s and %s %s overlap at %s" % [name_i, rect, names[j], other, host_size]
                assert_false(rect.intersects(other), apart)
        var tool_options: Rect2i = rects["ToolOptionsDocker"]
        var heads := "Tool Options heads its column, level with the Minimap, the head of the right column, at %s" % host_size
        assert_eq(tool_options.position.y, rects["MinimapDocker"].position.y, heads)
        var presets := dockers.registered_docker_node(SaDockerIds.BRUSH_PRESETS) as Window
        assert_true(presets.visible, "and the Brush Presets is open at %s" % host_size)
        var shown: Rect2i = rects["BrushPresetsDocker"]
        assert_eq(shown.position.x, tool_options.position.x, "in Tool Options' column at %s" % host_size)
        assert_true(shown.position.y >= tool_options.end.y, "under it, %s below %s" % [shown, tool_options])
        _host.remove_child(dockers.get_parent())
        dockers.get_parent().free()


## The cause, read on its own: while the docker is hidden its foot line is laid
## out at least as wide as the narrowest row, so the column asks for no more
## height than the docker opens at, where it asked for 1113.
func test_a_hidden_docker_asks_no_taller_than_it_opens() -> void:
    var dockers := _boot(HOSTS[0], false)
    var docker := dockers.registered_docker_node(SaDockerIds.TOOL_OPTIONS) as ToolOptionsDocker
    assert_false(docker.visible, "The docker is hidden, as at boot")
    var foot := docker._foot_line
    assert_true((foot.get_parent() as Control).visible, "and its foot line is on")
    assert_true(foot.text.ends_with(" on the top bar."), "naming what the bar holds: '%s'" % foot.text)
    assert_true(foot.size.x >= ToolOptionsDocker.WRAP_FLOOR, "The line is laid out %d wide, not one pixel" % foot.size.x)
    var floor_height := DockerWindow.column_min_height(docker)
    assert_true(
        floor_height < ToolOptionsDocker.DEFAULT_SIZE.y,
        "The column asks for %d, under the %d the docker opens at" % [floor_height, ToolOptionsDocker.DEFAULT_SIZE.y]
    )


## The registry's dockers in a viewport of *host_size* that embeds them, with
## the bar bound and Tool Options following a brush, and the shipped default
## restored when *restore* says so. Every docker is hidden until the restore,
## as at boot.
func _boot(host_size: Vector2i, restore: bool = true) -> MainDockers:
    var viewport := SubViewport.new()
    viewport.size = host_size
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
    if restore:
        if FileAccess.file_exists(scratch_layout):
            DirAccess.remove_absolute(scratch_layout)
        dockers.load_docker_layout()
    return dockers


## Section to rectangle for every docker open on *dockers*' host.
func _shown(dockers: MainDockers) -> Dictionary:
    var out: Dictionary = {}
    for config: Dictionary in dockers.get_docker_config():
        var win: Window = config["node"]
        if win.visible:
            out[config["id"]] = Rect2i(win.position, win.size)
    return out


func _remove_scratch_files() -> void:
    for path: String in [scratch_layout, ProjectSettings.globalize_path(scratch_profile)]:
        for suffix: String in ["", ".bak", ".broken"]:
            if FileAccess.file_exists(path + suffix):
                DirAccess.remove_absolute(path + suffix)
