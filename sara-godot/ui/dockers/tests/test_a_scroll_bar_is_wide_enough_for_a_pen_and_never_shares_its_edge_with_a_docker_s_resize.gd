## A scroll bar is wide enough for a pen and never shares its edge with a
## docker's resize.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The default Godot bars are hard to use on a Wacom tablet. They are tiny and
## too close to the resizing of the docker windows, so instead of grabbing one
## a press triggers the resizing. The engine's bar was eight
## wide, and a docker's right edge strip, four wide, lay over its outer half,
## so a pen aimed at the bar resized the docker.
##
## A floating docker whose column holds a scrolling list is built in a screen
## at a UI scale of 1 and of 2, the scale a `SubViewport` stretched by its
## `size_2d_override` the way the main window's is, with the four edges
## `MainDockers` gives every docker. The bar is measured on the screen, and so
## are its distance from the right edge strip and from the grip below it. Then
## a pen press one screen pixel in from the bar's outer edge, and a drag down,
## are pushed into the docker's window, where its own hit test decides who
## takes them: the list has to scroll and the docker keep its size.
@tool
extends "res://tests/test_framework.gd"

## The narrowest the bar may be, in logical pixels, which the screen shows
## times the UI scale. Sixteen is twice the engine's eight.
const BAR_AT_LEAST := 16.0

## The least clear room between the bar and anything that resizes the docker,
## the right edge strip beside it and the grip below it, in logical pixels.
const GAP_AT_LEAST := 6.0

const SCREEN := Vector2i(1280, 1024)
const AT := Vector2i(200, 150)
const OPENED := Vector2i(300, 320)


## A docker with a drag bar and a list taller than it, its column filling the
## window to the right edge, which is where every scrolling docker puts its bar.
class ListDocker:
    extends DockerWindow

    var list: ScrollContainer = null

    func _init() -> void:
        _init_docker("U782ListDocker", "List", OPENED, Vector2i(160, 160))
        var column := VBoxContainer.new()
        column.name = "Column"
        column.set_anchors_preset(Control.PRESET_FULL_RECT)
        _control_node.add_child(column)
        drag_handle = PanelContainer.new()
        drag_handle.custom_minimum_size = Vector2(0, 24)
        column.add_child(drag_handle)
        list = ScrollContainer.new()
        list.name = "List"
        list.size_flags_vertical = Control.SIZE_EXPAND_FILL
        list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        column.add_child(list)
        var rows := VBoxContainer.new()
        rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        list.add_child(rows)
        for i in 40:
            var row := Label.new()
            row.text = "Row %d" % i
            row.custom_minimum_size = Vector2(0, 28)
            rows.add_child(row)

    func _ready() -> void:
        _setup_docker_ready()


var _host: Node = null
var _kept_embedding: bool = true
var _kept_theme: Theme = null


func before_each() -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    _kept_embedding = root.gui_embed_subwindows
    root.gui_embed_subwindows = true
    _kept_theme = SaUI.shared_theme
    SaUI.init_global_theme(null)
    _host = Node.new()
    _host.name = "U782Host"
    EventBus.add_child(_host)


func after_each() -> void:
    DockerDragHandle.capture_pointer = null
    if _host != null:
        _host.free()
        _host = null
    SaUI.shared_theme = _kept_theme
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding


## The docker, shown with its edges, in a screen of `SCREEN` at *scale*.
func _docker_at(scale: float) -> ListDocker:
    var screen := SubViewport.new()
    screen.size = Vector2i(Vector2(SCREEN) * scale)
    screen.size_2d_override = SCREEN
    screen.size_2d_override_stretch = true
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    var docker := ListDocker.new()
    docker.position = AT
    screen.add_child(docker)
    assert_true(SaDockerEdges.attach(docker), "the docker has its four edges")
    docker.show()
    docker.size = OPENED
    return docker


func _settle() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    for i in 4:
        await tree.process_frame


## *control*'s rectangle on the screen, in the screen's own pixels: its place
## in its window, the window's place in the screen's logical space, and the
## screen's stretch to its pixels.
func _on_screen(control: Control) -> Rect2:
    var window := control.get_window()
    var screen := window.get_parent() as Viewport
    var in_window := window.get_final_transform() * control.get_global_rect()
    return screen.get_final_transform() * Rect2(in_window.position + Vector2(window.position), in_window.size)


## The part of the grip that takes a press, on the screen.
func _grip_square(docker: ListDocker) -> Rect2:
    var drawn := _on_screen(docker.resizer)
    var side: float = float(docker.resizer.get("side")) * drawn.size.x / docker.resizer.size.x
    return Rect2(drawn.position.x, drawn.end.y - side, drawn.size.x, side)


func test_the_bar_is_wide_and_clear_of_both_resizes_at_scales_1_and_2() -> void:
    for scale: float in [1.0, 2.0]:
        var docker := _docker_at(scale)
        await _settle()
        var bar := docker.list.get_v_scroll_bar()
        assert_true(bar.visible, "at %s the list scrolls, so its bar shows" % scale)
        var bar_rect := _on_screen(bar)
        var strip := _on_screen(docker.get_node("Control/EdgeRight") as Control)
        var grip := _grip_square(docker)
        var window_right := _on_screen(docker.get_node("Control") as Control).end.x
        assert_almost_eq(strip.end.x, window_right, 0.5, "at %s the right strip lies along the window's right edge" % scale)
        assert_true(
            bar_rect.size.x >= BAR_AT_LEAST * scale - 0.5,
            "at %s the bar is %s on the screen, %s at least" % [scale, bar_rect.size.x, BAR_AT_LEAST * scale]
        )
        var beside := strip.position.x - bar_rect.end.x
        assert_true(
            beside >= GAP_AT_LEAST * scale - 0.5,
            "at %s the bar ends %s short of the right strip, %s at least" % [scale, beside, GAP_AT_LEAST * scale]
        )
        var above := grip.position.y - bar_rect.end.y
        var said := "at %s the bar ends %s above the grip, %s at least" % [scale, above, GAP_AT_LEAST * scale]
        assert_true(above >= GAP_AT_LEAST * scale - 0.5, said)
        docker.get_parent().free()


## The grabber is drawn narrower than the bar, and a press anywhere across the
## bar's width at the grabber's height takes it, so the target is the wider one.
func test_the_grabber_is_drawn_inside_a_wider_target() -> void:
    var grabber := SaUI.shared_theme.get_stylebox("grabber", "VScrollBar") as StyleBoxFlat
    assert_not_null(grabber, "the grabber is a flat box")
    if grabber == null:
        return
    var drawn := BAR_AT_LEAST - grabber.border_width_left - grabber.border_width_right
    assert_true(drawn >= 8.0 and drawn < BAR_AT_LEAST, "the grabber draws %s of the bar's %s" % [drawn, BAR_AT_LEAST])
    assert_eq(grabber.border_color.a, 0.0, "and the band either side of it is not drawn")
    assert_true(grabber.get_minimum_size().y >= 24.0, "and a long list leaves it %s long" % grabber.get_minimum_size().y)


func test_a_press_one_pixel_in_from_the_bar_s_outer_edge_scrolls_and_never_resizes() -> void:
    for scale: float in [1.0, 2.0]:
        var docker := _docker_at(scale)
        await _settle()
        var bar := docker.list.get_v_scroll_bar()
        # In the window's own pixels, which is where a pushed event lands.
        var bar_in_window := bar.get_global_rect()
        var one_pixel := 1.0 / scale
        var at := Vector2(bar_in_window.end.x - one_pixel, bar_in_window.position.y + 8.0)
        var size_before := docker.size
        var scrolled_before := docker.list.scroll_vertical
        _pen(docker, at, Vector2(0, 120))
        await _settle()
        assert_eq(docker.size, size_before, "at %s the docker keeps its size" % scale)
        assert_true(
            docker.list.scroll_vertical > scrolled_before,
            "at %s the list scrolled, from %d to %d" % [scale, scrolled_before, docker.list.scroll_vertical]
        )
        docker.get_parent().free()


## A pen press at *start* in the window's pixels, dragged by *by* in six reports
## and lifted, as a pen's left button and motion reach Godot.
func _pen(docker: Window, start: Vector2, by: Vector2) -> void:
    var origin := Vector2(docker.position)
    DockerDragHandle.capture_pointer = origin + start
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.button_mask = MOUSE_BUTTON_MASK_LEFT
    press.pressed = true
    press.position = start
    press.global_position = start
    docker.push_input(press)
    var at := start
    for i in 6:
        var step := by / 6.0
        at += step
        DockerDragHandle.capture_pointer = origin + at
        var motion := InputEventMouseMotion.new()
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.position = at
        motion.global_position = at
        motion.relative = step
        motion.pressure = 0.6
        docker.push_input(motion)
    var lift := InputEventMouseButton.new()
    lift.button_index = MOUSE_BUTTON_LEFT
    lift.pressed = false
    lift.position = at
    lift.global_position = at
    docker.push_input(lift)
    DockerDragHandle.capture_pointer = null
