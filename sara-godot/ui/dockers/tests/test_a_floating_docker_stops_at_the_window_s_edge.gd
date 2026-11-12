## A floating docker dragged past the window's edge stops with its strip in
## reach.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The finding: a painter dragged the Layers docker by its bar to the lower
## middle of the window and let go, and it hung below the status bar with its
## button row and grip off screen. A close and Shift+T brought it back, so the
## reopen had a clamp and the drag had none. The drag now has the reopen's
## whole-inside clamp. A docker may stand partly past the left, the right
## and the bottom edge, and the original fault is still kept
## from happening: the drag stops while [constant SaDockerLayoutFit.STRIP_IN_REACH]
## of the title strip, its buttons and its grip, is on the window and below the
## bar. The running app is
## `scenarios/a-floating-docker-stops-at-the-window-s-edge-while-dragged.json`.
## Here are the rule on each edge, two drags driven like a hand on a docker
## embedded in a 1280 by 1024 window under a bar, and the reopen, which still
## opens a docker whole.
extends "res://tests/test_framework.gd"

const HOST := Vector2i(1280, 1024)
const SIZE := Vector2i(300, 500)

## The first row below the bar at 1280 by 1024, `MainDockers.below_bar`.
const BAR := 79

## The window below the bar, where a drag keeps the strip.
const BELOW_BAR := Rect2i(0, BAR, 1280, 1024 - BAR)

const STRIP := SaDockerLayoutFit.STRIP_IN_REACH

var _kept_inset: Callable = Callable()
var _kept_embedding: bool = true
var _host: Node = null


func before_each() -> void:
    _kept_inset = SaDialogWindow.top_inset
    SaDialogWindow.top_inset = func() -> int: return BAR
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    # A window added outside the screen below would map a real OS window and
    # block the run, so the root embeds as well.
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "S68DragHostTest"
    EventBus.add_child(_host)


func after_each() -> void:
    SaDialogWindow.top_inset = _kept_inset
    DockerDragHandle.capture_pointer = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null


func test_a_place_inside_the_host_is_kept() -> void:
    assert_eq(SaDockerLayoutFit.reached(Vector2i(200, 300), SIZE, BELOW_BAR), Vector2i(200, 300), "Nothing to mend")


func test_each_edge_stops_the_window_with_its_strip_in_reach() -> void:
    var left := SaDockerLayoutFit.reached(Vector2i(-400, 300), SIZE, BELOW_BAR)
    assert_eq(left, Vector2i(STRIP.x - SIZE.x, 300), "Left edge, the strip's right end left in")
    assert_eq(SaDockerLayoutFit.reached(Vector2i(200, -40), SIZE, BELOW_BAR), Vector2i(200, BAR), "Top edge, below the bar")
    var right := SaDockerLayoutFit.reached(Vector2i(1200, 300), SIZE, BELOW_BAR)
    assert_eq(right, Vector2i(HOST.x - STRIP.x, 300), "Right edge, the strip's head left in")
    var bottom := SaDockerLayoutFit.reached(Vector2i(200, 1100), SIZE, BELOW_BAR)
    assert_eq(bottom, Vector2i(200, HOST.y - STRIP.y), "Bottom edge, the strip's whole height left in")
    var corner := SaDockerLayoutFit.reached(Vector2i(2000, 2000), SIZE, BELOW_BAR)
    assert_eq(corner, Vector2i(HOST.x - STRIP.x, HOST.y - STRIP.y), "A corner")


## A docker past an edge by less than the strip allows stands where it was put.
func test_a_docker_partly_past_an_edge_stands_where_it_is() -> void:
    for at: Vector2i in [Vector2i(-100, 300), Vector2i(1100, 300), Vector2i(200, 900)]:
        assert_eq(SaDockerLayoutFit.reached(at, SIZE, BELOW_BAR), at, "Partly outside at %s and kept" % at)


## The toolbox is 60 wide, narrower than the strip, and keeps all of it.
func test_a_docker_narrower_than_the_strip_keeps_its_whole_width() -> void:
    var narrow := Vector2i(60, 400)
    assert_eq(SaDockerLayoutFit.reached(Vector2i(-30, 300), narrow, BELOW_BAR), Vector2i(0, 300), "Left edge")
    assert_eq(SaDockerLayoutFit.reached(Vector2i(1250, 300), narrow, BELOW_BAR), Vector2i(1220, 300), "Right edge")


func test_an_empty_host_is_no_clamp() -> void:
    assert_eq(SaDockerLayoutFit.reached(Vector2i(5000, -70), SIZE, Rect2i()), Vector2i(5000, -70), "No host, no clamp")


## The bar pressed and dragged to the lower middle of the window, the
## finding's own gesture, through the title bar's `gui_input`, and then on
## below the window's foot.
func test_a_bar_drag_let_go_low_keeps_the_strip_and_the_grip_in_reach() -> void:
    var window := _embedded(Vector2i(900, 100))
    var bar := _bar()
    var handle := DockerDragHandle.new()
    _host.add_child(handle)
    handle.bind(window, bar)
    var press := Vector2(window.position) + Vector2(150, 10)
    DockerDragHandle.capture_pointer = press
    bar.gui_input.emit(_button(true, false))
    DockerDragHandle.capture_pointer = Vector2(640, 1000)
    bar.gui_input.emit(InputEventMouseMotion.new())
    assert_eq(window.position, Vector2i(640 - 150, 990), "It follows the pointer below the window's foot")
    DockerDragHandle.capture_pointer = Vector2(640, 1500)
    bar.gui_input.emit(InputEventMouseMotion.new())
    bar.gui_input.emit(_button(false, false))
    assert_eq(window.position, Vector2i(640 - 150, HOST.y - STRIP.y), "and stops with the strip's height left in")
    assert_true(_in_reach(window), "The strip's head, the lock and the grip, stands on the window")


## The ALT drag past the right edge, through `handle_input`.
func test_an_alt_drag_past_the_right_edge_stops_with_the_strip_in() -> void:
    var window := _embedded(Vector2i(400, 200))
    var handle := DockerDragHandle.new()
    _host.add_child(handle)
    handle.bind(window, _bar())
    var start := Vector2(window.position) + Vector2(SIZE) * 0.5
    DockerDragHandle.capture_pointer = start
    handle.handle_input(_button(true, true))
    DockerDragHandle.capture_pointer = start + Vector2(2000, 30)
    handle.handle_input(DockerDragHandle.held_motion(MOUSE_BUTTON_MASK_LEFT))
    handle.handle_input(_button(false, true))
    assert_eq(window.position, Vector2i(HOST.x - STRIP.x, 230), "The strip's head rests inside the right edge")
    assert_true(_in_reach(window), "The grip is on the window")


## The Window menu's show keeps the whole rule. `fit_inside` with the window's
## own centre for the pointer, as `MainDockers.toggle_docker` asks it, opens a
## docker whole, since one that appears half hidden reads as a fault.
func test_the_reopen_still_opens_a_docker_whole() -> void:
    var window := _embedded(Vector2i(100, 100))
    var at := Vector2i(640, 1000)
    var fitted := DockerDragHandle.fit_inside(window, at, Vector2(at) + Vector2(SIZE) * 0.5)
    assert_eq(fitted, DockerDragHandle.clamp_to_host(at, SIZE, HOST), "The whole-inside clamp")
    assert_eq(fitted, Vector2i(640, 524), "The bottom edge rests on the window's")


func test_the_reopens_clamp_stops_each_edge_whole() -> void:
    assert_eq(DockerDragHandle.clamp_to_host(Vector2i(-40, 300), SIZE, HOST), Vector2i(0, 300), "Left edge")
    assert_eq(DockerDragHandle.clamp_to_host(Vector2i(1200, 300), SIZE, HOST), Vector2i(980, 300), "Right edge")
    assert_eq(DockerDragHandle.clamp_to_host(Vector2i(200, 900), SIZE, HOST), Vector2i(200, 524), "Bottom edge")
    var big := Vector2i(1400, 1100)
    assert_eq(DockerDragHandle.clamp_to_host(Vector2i(60, 80), big, HOST), Vector2i(), "A window larger than the host")
    assert_eq(DockerDragHandle.clamp_to_host(Vector2i(5000, -70), SIZE, Vector2i()), Vector2i(5000, -70), "No host")


## Whether the head of *window*'s title strip, where the lock and the grip
## stand, is on the window below the bar, its whole height and the strip's width.
func _in_reach(window: Window) -> bool:
    return BELOW_BAR.encloses(Rect2i(window.position, STRIP))


## A window embedded in a 1280 by 1024 screen.
func _embedded(at: Vector2i) -> Window:
    var screen := SubViewport.new()
    screen.size = HOST
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    var window := Window.new()
    window.min_size = Vector2i(80, 60)
    window.position = at
    window.size = SIZE
    screen.add_child(window)
    return window


## A title bar under the host, so the run frees it.
func _bar() -> Control:
    var bar := Control.new()
    _host.add_child(bar)
    return bar


static func _button(down: bool, alt: bool) -> InputEventMouseButton:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = down
    button.alt_pressed = alt
    return button
