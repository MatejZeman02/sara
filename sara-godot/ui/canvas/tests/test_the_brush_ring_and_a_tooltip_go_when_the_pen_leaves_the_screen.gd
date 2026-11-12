## The brush ring and a tooltip go when the pen leaves the screen.
##
## The cursor must not stay when the pen is away, and a layer's tooltip, "Its
## tooth stands in relief", left standing over the canvas after the pen moved on.
##
## What Godot 4.7's Android port sends when a pen leaves hover range is
## Android's `ACTION_HOVER_EXIT` made into one more `InputEventMouseMotion` at
## the pen's last place, with no pressure and no buttons, and then nothing. So
## the suite plays exactly that, through the window the way the engine hands it
## on, with [member SaCursorPolicy.pen_silence_means_gone] on as it is on
## Android, and reads what is left once the pen has stayed quiet.
##
## A headless display maps no window and shows no tooltip, so the cases skip
## there, as the Windows Ink suite beside this one does.
extends "res://tests/test_framework.gd"

## A canvas builds an easel and the rows carry thumbnails, both of which need a
## RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const RING := 12.0
## A point on the canvas clear of the docker and of the top left corner, where
## the windows other suites leave in the root stand.
const CANVAS_POINT := Vector2(1000.0, 700.0)
const DOCKER_AT := Vector2(200.0, 150.0)
const DOCKER_SIZE := Vector2(360.0, 400.0)
## Longer than the pen's quiet of [constant SaPointerDevice.PEN_SILENCE_USEC],
## with room for a loaded gate.
const WAIT_SEC := 2.4

var _host: Node = null
var _registries: SaRegistries = null
var _docker: LayersDocker = null
var _previous_mode: String = "auto"
var _previous_silence: bool = false
var _previous_mouse_mode: int = Input.MOUSE_MODE_VISIBLE


func before_each() -> void:
    _previous_mode = SaSettings.software_cursor
    _previous_silence = SaCursorPolicy.pen_silence_means_gone
    _previous_mouse_mode = Input.get_mouse_mode()
    SaSettings.software_cursor = "always"
    SaCursorPolicy.pen_silence_means_gone = true
    SaCursorPolicy.forget_pointer_device()
    _registries = Fixtures.make_registries()
    _host = Node.new()
    _host.name = "U369PenLeavesTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    _let_the_hover_go()
    SaCursorPolicy.forget_pointer_device()
    SaCursorPolicy.pen_silence_means_gone = _previous_silence
    SaSettings.software_cursor = _previous_mode
    if _host != null:
        _host.free()
        _host = null
    if _docker != null:
        _docker.free()
        _docker = null
    _registries = null
    if Input.get_mouse_mode() != _previous_mouse_mode:
        Input.set_mouse_mode(_previous_mouse_mode as Input.MouseMode)


func _no_window_maps() -> bool:
    if DisplayServer.get_name() != "headless":
        return false
    skip("a headless display maps no window and shows no tooltip, so no case played the pen leaving")
    return true


func _root() -> Window:
    return (Engine.get_main_loop() as SceneTree).root


## A canvas over the whole window that wants a ring, with an overlay beside it
## the way every window has one.
func _canvas() -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(128, 128)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    _host.add_child(canvas)
    canvas.position = Vector2.ZERO
    canvas.size = _root().get_visible_rect().size
    canvas.cursor_ring_radius = RING
    _host.add_child(CursorOverlay.new())
    return canvas


## A Layers docker over a Canvas ground, whose row carries the tooth's
## mountains and the tooltip that was left standing.
##
## A docker is a window of its own, which a suite cannot map, for the reason
## `render/cursor/tests/test_a_window_of_its_own.gd` gives. So the docker is
## built out of the tree as its sibling suites build it, and the panel it would
## show, rows and all, is lent to a place in the main window, where the pen's
## hover is handed to it as the engine hands it to the docker on Android, whose
## windows are all embedded in the one.
func _height_mark(canvas: SaCanvas) -> Control:
    var ground := SaLayerOps.new(canvas.easel.document).add(&"canvas", _registries.layer_types)
    ground.name = "Canvas"
    _docker = LayersDocker.new()
    _docker.target_canvas = canvas
    _docker._ready()
    _docker.bind_registries(_registries.blend_modes, _registries.layer_types)
    _docker.sync_layer_list()
    var body := _docker.get_child(0) as Control
    _docker.remove_child(body)
    var place := Control.new()
    place.position = DOCKER_AT
    place.size = DOCKER_SIZE
    _host.add_child(place)
    place.add_child(body)
    body.position = Vector2.ZERO
    body.size = DOCKER_SIZE
    _sort_children(place)
    var list: SaLayerList = _docker.item_list
    for i in list.row_count():
        var layer: SaLayer = list.layer_at(i)
        if layer != null and str(layer.name) == "Canvas":
            return list.rows[i].height_mark
    return null


## Sorts every container under *node*, outside in, so the rectangles below it
## are the ones the running app would draw.
func _sort_children(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)


## A pen's hover, known for a pen by its tilt, handed to the window as the
## engine hands an event on. *at* is in the window's own coordinates.
func _hover(at: Vector2) -> void:
    var root := _root()
    var motion := InputEventMouseMotion.new()
    motion.tilt = Vector2(0.2, -0.1)
    motion.pressure = 0.0
    motion.position = root.get_final_transform() * at
    motion.global_position = motion.position
    root.push_input(motion)


## What Godot's Android port makes of `ACTION_HOVER_EXIT`: the same motion at
## the pen's last place, and nothing after it.
func _hover_exit(at: Vector2) -> void:
    _hover(at)


## A motion of the mouse outside the window, so no case leaves a Control
## hovered behind it for the suites after it.
func _let_the_hover_go() -> void:
    var gone := InputEventMouseMotion.new()
    gone.position = Vector2(-1.0, -1.0)
    gone.global_position = gone.position
    _root().push_input(gone)


func _wait() -> void:
    await (Engine.get_main_loop() as SceneTree).create_timer(WAIT_SEC).timeout
    await (Engine.get_main_loop() as SceneTree).process_frame


## What the root's overlay draws for the pointer, asked the way
## `CursorOverlay._draw_body` asks.
func _drawn() -> StringName:
    var root := _root()
    var at := SaCursorPolicy.pointer_in_window(root)
    return (
        CursorOverlay
        . resolve_cursor(
            SaCursorPolicy.cursor_ring_radius_at(root, at),
            SaCursorPolicy.pointer_is_tablet,
            SaCursorPolicy.wants_software_pointer(root, at),
        )
    )


## The text of the engine's tooltip standing anywhere in the window, or "" for
## none: a label dressed as the engine dresses its tooltip's, in a window that
## is showing.
func _tooltip_shown() -> String:
    for found in _root().find_children("*", "Label", true, false):
        var label := found as Label
        if label.theme_type_variation == &"TooltipLabel" and label.is_visible_in_tree() and not label.text.is_empty():
            return label.text
    return ""


func test_the_ring_goes_once_the_pen_has_left_hover_range() -> void:
    if _no_window_maps():
        return
    _canvas()
    _hover(CANVAS_POINT - Vector2(4.0, 0.0))
    _hover(CANVAS_POINT)
    assert_eq(_drawn(), &"ring", "A pen hovering over the canvas has its ring")

    _hover_exit(CANVAS_POINT)
    assert_eq(_drawn(), &"ring", "The hover exit reads as one more hover, so the ring is still drawn at once")
    await _wait()
    var at := SaCursorPolicy.pointer_in_window(_root())
    var said := "Once the pen has been quiet, it is in no place in the window, got %s" % at
    assert_false(_root().get_visible_rect().has_point(at), said)
    assert_eq(_drawn(), &"system", "and the ring is gone")

    _hover(CANVAS_POINT + Vector2(30.0, 0.0))
    assert_eq(_drawn(), &"ring", "The pen coming back into range has its ring again")


## A pen pressed and held still sends nothing either, and is on the canvas.
func test_a_pen_held_down_and_still_keeps_its_ring() -> void:
    if _no_window_maps():
        return
    _canvas()
    _hover(CANVAS_POINT)
    var press := InputEventMouseMotion.new()
    press.tilt = Vector2(0.2, -0.1)
    press.pressure = 0.4
    press.button_mask = MOUSE_BUTTON_MASK_LEFT
    press.position = CANVAS_POINT
    SaCursorPolicy.note_pointer_device(press, _root())
    assert_false(
        SaCursorPolicy.note_pen_silence(_root(), Time.get_ticks_usec() + SaPointerDevice.PEN_SILENCE_USEC * 4),
        "A pen with its tip down is never taken for gone however long it rests"
    )
    var at := SaCursorPolicy.pointer_in_window(_root())
    assert_eq(at, CANVAS_POINT, "and its place stays where it rests")


func test_a_layer_s_tooltip_goes_with_the_pen() -> void:
    if _no_window_maps():
        return
    var canvas := _canvas()
    var mark := _height_mark(canvas)
    assert_true(mark != null and mark.visible, "The Canvas ground's row shows the tooth's mountains")
    var over := mark.get_global_rect().get_center()
    _hover(over - Vector2(1.0, 0.0))
    _hover(over)
    assert_eq(_root().gui_get_hovered_control(), mark, "The pen hovers the mountains")
    # The engine opens a tooltip once the pointer has rested for its delay, so
    # the pen rests here, short of the quiet that would say it has gone.
    var opened := ""
    for i in 60:
        await (Engine.get_main_loop() as SceneTree).create_timer(0.025).timeout
        opened = _tooltip_shown()
        if not opened.is_empty():
            break
    assert_true(opened.contains("tooth"), "and its tooltip opens, read %s" % opened)

    _hover_exit(over)
    await _wait()
    assert_eq(_tooltip_shown(), "", "Once the pen has left range no tooltip is left over the canvas")
    assert_eq(_root().gui_get_hovered_control(), null, "and nothing is left hovered")
    assert_eq(_drawn(), &"system", "and no ring or arrow is drawn")
