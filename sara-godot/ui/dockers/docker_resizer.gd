## A bottom-right handle for resizing borderless floating docker windows.
##
## The grip holds the window's top-left still and puts its own corner under the
## pointer, so a drag down moves the bottom edge and a drag right the right one.
## It does not grow about the centre the way the ALT and right button drag
## does: a grip that did lifted the Brush Presets docker's top over the menu bar
## when pulled down, and a painter holding a corner expects the other edges to
## stay. The arithmetic is `DockerDragHandle.grip_rect`, beside the centred one,
## and the rectangle it is kept in is `DockerDragHandle.resize_host_of`, the
## host less the main window's bar.
##
## It is the grip of `SaDialogWindow` as well, so Preferences, New Document and
## the other dialogs resize from the corner too, which is what a painter
## expects of a dialog.
##
## **`DisplayServer.window_start_resize` is still not used.** It handed a native
## window's interactive resize to the compositor, which grows towards a corner
## the compositor picks, and it could not be asked to stop at the bar. The grip
## tracks the pointer itself on a native window as well as on an embedded one,
## one `position` and one `size` write per motion event, which shows no lag on
## Wayland.
extends Control

class_name DockerResizer

const DockerDragHandleScript = preload("res://ui/dockers/docker_drag_handle.gd")

## Half of what it was, in logical pixels. The reason: a button at a
## docker's bottom right, the Layers docker's own More button among them, sat
## under the grip's square at every size and needed the column pushed up to
## reach it. `reserve_grip_corner` reads this same constant off the live
## control, so the corner it holds clear shrinks with the grip rather than
## needing a second number kept in step by hand.
const SIZE: float = 12.0

## The grip's side on a touch screen, in logical pixels, twice the desktop's. A
## pen tip on a tablet lands a few pixels off where the painter aims and a
## finger covers more than twelve, so a square of twelve is hard to hit rather
## than taken. Twenty-four takes a press anywhere within sixteen of the
## corner with room to spare, and `reserve_grip_corner` reserves the same
## twenty-four under the column, so no button sits beneath it.
const TOUCH_SIZE: float = 24.0

## The clear band between the grip and the column above it, in logical pixels.
## A docker's vertical scroll bar runs down the same right edge the grip sits
## in, and with the column stopping a grip's height short of the bottom the
## bar ended exactly on the grip's top. A pen aimed at the bar's lower end
## landed on the grip a pixel or two low and resized the docker instead of
## scrolling it. The band is part of the control, so every reader of
## `custom_minimum_size.y` reserves it with the grip, and `_has_point` leaves it
## dead: a press there neither scrolls nor resizes.
const GAP: float = 8.0

## The platforms a docker is resized by touch on, by `OS.get_name()`.
const TOUCH_PLATFORMS: PackedStringArray = ["Android", "iOS"]

## The grip's side as built, `SIZE` on a desktop and `TOUCH_SIZE` on a touch
## platform. Read by a suite, written only here.
var side: float = SIZE

## The control's height, the grip's side and `GAP` above it. Read by a suite,
## written only here.
var reach: float = SIZE + GAP

var _is_resizing: bool = false
var _resize_start_size: Vector2i
var _resize_start_position: Vector2i
var _resize_anchor: Vector2
var _target_window: Window


## *platform* is `OS.get_name()` unless a suite names another, the way
## `SaSettingsLayout` takes one.
func _init(target: Window = null, platform: String = OS.get_name()) -> void:
    name = "DockerResizer"
    _target_window = target
    side = side_for(platform)
    reach = side + GAP
    custom_minimum_size = Vector2(side, reach)
    size = custom_minimum_size
    mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
    mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
    # Pin to bottom-right corner.
    anchor_left = 1.0
    anchor_top = 1.0
    anchor_right = 1.0
    anchor_bottom = 1.0
    var sz := int(side)
    offset_left = -sz
    offset_top = -int(reach)
    offset_right = 0
    offset_bottom = 0

    gui_input.connect(_on_gui_input)


## Only the grip's own square at the bottom takes a press, and the band of
## `GAP` above it passes through to nothing, so the cursor and the press stop at
## the same line the drawing does.
func _has_point(point: Vector2) -> bool:
    return point.x >= 0.0 and point.x <= size.x and point.y >= size.y - side and point.y <= size.y


## The grip's side on *platform*.
static func side_for(platform: String) -> float:
    return TOUCH_SIZE if TOUCH_PLATFORMS.has(platform) else SIZE


func _on_gui_input(event: InputEvent) -> void:
    if _target_window == null:
        return

    if event is InputEventMouseButton or event is InputEventScreenTouch:
        if event.is_pressed():
            _is_resizing = true
            _resize_start_size = _target_window.size
            _resize_start_position = _target_window.position
            _resize_anchor = DockerDragHandleScript.pointer_in_parent_space_of(_target_window)
            accept_event()
        else:
            _is_resizing = false
            if EventBus:
                EventBus.docker_layout_changed.emit()
            accept_event()

    elif (event is InputEventMouseMotion or event is InputEventScreenDrag) and _is_resizing:
        var drag := DockerDragHandleScript.pointer_in_parent_space_of(_target_window) - _resize_anchor
        var rect: Rect2i = DockerDragHandleScript.grip_rect(
            _resize_start_position,
            _resize_start_size,
            drag,
            DockerDragHandleScript.minimum_size_of(_target_window),
            DockerDragHandleScript.resize_host_of(_target_window)
        )
        # The size first, for the reason the drag handle gives: a position
        # written while the window is still the old size can be clamped against
        # the host edge, and a clamped position is not a chosen one.
        _target_window.size = rect.size
        _target_window.position = rect.position
        accept_event()


func _draw() -> void:
    var sz := size
    var col_light := SaTheme.palette.grip_light
    var col_dark := SaTheme.palette.grip_dark
    # Logical units: the window's content_scale_factor does the scaling.
    # Half of what the line width was, the same halving SIZE took, so the
    # three lines keep the proportions they had at 24 rather than reading as
    # three thick bars stacked into half the room.
    var line_w := side / SIZE

    # The picture scales with the grip, so the larger touch grip draws its
    # three lines across the same share of its square as the desktop's do.
    var k := side / SIZE

    # Three parallel diagonal grip lines (drawn dark then light for depth),
    # positioned as fractions of SIZE so a further resize keeps the same
    # picture rather than the lines drifting out of the box.
    for i: float in [2.0, 4.5, 7.0]:
        draw_line(Vector2(sz.x - k * (i + 2.5), sz.y - k * 1.5), Vector2(sz.x - k * 1.5, sz.y - k * (i + 2.5)), col_dark, line_w)
        draw_line(Vector2(sz.x - k * (i + 3.0), sz.y - k * 2.0), Vector2(sz.x - k * 2.0, sz.y - k * (i + 3.0)), col_light, line_w)


## The grip's half of the `docker_resize` capture step: one press at *start*, one
## motion *by* away, one release, through the same handler a hand goes through.
## Driven from `DockerDragHandle.capture_resize`, which owns the pointer override
## the two of them read.
func capture_drag(start: Vector2, by: Vector2) -> void:
    DockerDragHandleScript.capture_pointer = start
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    _on_gui_input(press)
    DockerDragHandleScript.capture_pointer = start + by
    _on_gui_input(InputEventMouseMotion.new())
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    _on_gui_input(release)
