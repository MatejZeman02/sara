## One composed docker's window: its drag bar, and under it a view of each
## element the library places in it, in the library's order.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The views are `PlacedViews`, the column a shipped docker draws what is placed
## in it with as well, so how a view is built, how it waits for a module's view
## and how a switch hides it is said there once.
## This window adds the drag bar over it and the scroll round it, and keeps no
## state of an element's own, because a placed element is a second view of the
## same state as at home.
##
## Built by `SaComposedDockers` alone, which hands it its id, its name and what
## it holds.
@tool
extends DockerWindow

## What a new composed docker opens at: a column as wide as the Toolbox's and
## tall enough for a handful of rows.
const DEFAULT_SIZE := Vector2i(240, 320)

## The smallest it can be resized to, a drag bar and a row under it.
const MIN_SIZE := Vector2i(120, 80)

## Where the Window menu opens one that no layout has placed, over the canvas
## and clear of the menus.
const FIRST_PLACE := Vector2i(720, 300)

const ColumnScroll := preload("res://ui/dockers/docker_column_scroll.gd")
const PlacedViews := preload("placed_views.gd")

## The column the views stand in, under the drag bar and inside the scroll, and
## the window's [member DockerWindow.placed_column] as well.
var placed: PlacedViews


func _init(docker_id: StringName, docker_title: String, elements: Array) -> void:
    _init_docker(String(docker_id), docker_title, DEFAULT_SIZE, MIN_SIZE)
    position = FIRST_PLACE
    var column := SaMake.column(_control_node, "VBoxContainer")
    column.set_anchors_preset(Control.PRESET_FULL_RECT)
    drag_handle = DockerUtils.make_drag_bar(docker_title)
    column.add_child(drag_handle)
    placed = PlacedViews.new()
    placed_column = placed
    ColumnScroll.wrap(column, placed)
    placed.hold(elements)


func _ready() -> void:
    _setup_docker_ready()
    if not SaSettings.profile_changed.is_connected(apply_layout_settings):
        SaSettings.profile_changed.connect(apply_layout_settings)
    apply_layout_settings()


func apply_layout_settings() -> void:
    apply_docker_base_layout(settings_category())


## Takes *docker_title* as its title, for a rename, and has the drag bar read
## it again as it does on a change of locale.
func retitle(docker_title: String) -> void:
    title = docker_title
    notification(NOTIFICATION_TRANSLATION_CHANGED)


## The view of each element it holds, in order, null where one still waits.
func views() -> Array[Control]:
    return placed.views()
