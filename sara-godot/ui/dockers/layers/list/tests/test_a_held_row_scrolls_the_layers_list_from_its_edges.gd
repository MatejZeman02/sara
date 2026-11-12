## Dragging a layer's row to the docker's top or bottom edge scrolls the list.
##
## A layer held to be put down below what is visible should start scrolling the
## list of layers when it approaches the end. Forty layers stand in a list that
## shows about ten, the top row is pressed with a mouse event delivered to the
## root, the pointer is carried into the bottom band and held there, and the
## frames that follow are `SaLayerListEdgeScroll.step`, called straight because
## a suite that awaits drops every assertion after the await. The
## docker is a Window and cannot stand in this tree, so its list is lifted out
## of it into a plain Control, still wired by the docker's keeper, which
## drops its rows.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Forty with the background, which the default document already carries.
const LAYERS := 40
const SHOWN_ROWS := 10
const FRAME := 1.0 / 60.0

var _easel: SaEasel
var _doc: SaDocument
var _canvas: SaCanvas
var _docker: LayersDocker
var _host: Control
var _list: SaLayerList


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(128, 128))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _easel.document
    _doc.active_layer.name = "Layer 1"
    var ops := SaLayerOps.new(_doc)
    for i in range(2, LAYERS):
        ops.add().name = "Layer %d" % i
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.target_canvas = _canvas
    _docker.list_keeper.listen()
    _docker.sync_layer_list()
    _list = _docker.item_list
    _list.get_parent().remove_child(_list)
    _list.owner = null
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    _host = Control.new()
    _host.name = "EdgeScrollHost"
    EventBus.add_child(_host)
    _host.add_child(_list)
    _list.position = Vector2(20, 20)
    _list.size = Vector2(240, 400)
    _lay_out()
    _list.size = Vector2(240, _list.rows[0].size.y * SHOWN_ROWS + 2.0 * (SHOWN_ROWS - 1))
    _lay_out()


func after_each() -> void:
    _release_input()
    _host.remove_child(_list)
    _list.free()
    _host.free()
    _host = null
    _docker.free()
    _canvas.free()
    _easel.free()


## The container and the column sort when the frame ends, and this suite never
## lets one end, so they are told to now. A rebuild's old rows wait in the
## column for that end as well, queued to go, and are taken out first.
func _lay_out() -> void:
    for child in _list.vbox.get_children():
        if child.is_queued_for_deletion():
            _list.vbox.remove_child(child)
    for i in 2:
        _list.vbox.notification(Container.NOTIFICATION_SORT_CHILDREN)
        _list.notification(Container.NOTIFICATION_SORT_CHILDREN)


func _edge() -> SaLayerListEdgeScroll:
    return _list.get_node("EdgeScroll") as SaLayerListEdgeScroll


func _end() -> int:
    var bar := _list.get_v_scroll_bar()
    return int(bar.max_value - bar.page)


## A press or release of the left button at *at*, handed to `Input` as the
## display server hands it. `Input` keeps whether the button is down, which the
## drag asks, and delivers the event to the root window itself.
func _button(at: Vector2, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    event.position = at
    event.global_position = at
    Input.parse_input_event(event)
    Input.flush_buffered_events()


func _motion(at: Vector2) -> void:
    var event := InputEventMouseMotion.new()
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    event.position = at
    event.global_position = at
    Input.parse_input_event(event)
    Input.flush_buffered_events()


func _release_input() -> void:
    if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = false
        Input.parse_input_event(event)
        Input.flush_buffered_events()


## The top row pressed in its middle and carried *travel* down, past the drag's
## threshold, with the rows laid out again after the press rebuilt them.
func _pick_up_the_top_row(travel: float) -> Vector2:
    var start := _list.rows[0].get_global_rect().get_center()
    assert_true(_list.get_global_rect().has_point(start), "the top row is in view to be pressed")
    _button(start, true)
    _lay_out()
    var at := start + Vector2(0, travel)
    _motion(at)
    return at


func _order() -> Array[String]:
    var out: Array[String] = []
    for child in _doc.get_children():
        if child is SaLayer:
            out.append(String(child.name))
    return out


func test_holding_a_row_in_the_bottom_band_scrolls_to_the_end_and_drops_there() -> void:
    assert_true(_end() > 0, "forty rows do not fit in a list of ten, scroll end %d" % _end())
    var before := _order()
    assert_eq(before[before.size() - 1], "Layer %d" % (LAYERS - 1), "the newest layer is the top of the stack")
    var rect := _list.get_global_rect()
    var held := _pick_up_the_top_row(rect.end.y - 6.0 - _list.rows[0].get_global_rect().get_center().y)
    assert_true(_list.dragging, "the press and the travel began a drag")
    assert_eq(_list.scroll_vertical, 0, "nothing has scrolled before a frame")
    var frames := 0
    while _list.scroll_vertical < _end() and frames < 600:
        _edge().step(FRAME)
        frames += 1
    assert_eq(_list.scroll_vertical, _end(), "the held pointer scrolled the list to its end in %d frames" % frames)
    assert_false(_edge().step(FRAME), "and at the end it scrolls no further")
    _lay_out()
    var last := _list.rows.size() - 1
    # The column ends in a band of no row under the last, where a press and
    # drag scrolls the list, so the pointer at the end stands on the last row
    # or on that band, and either drops after the last row.
    var last_top := _list.rows[last].get_global_rect().position.y
    assert_true(held.y >= last_top, "the pointer is over the last row or the band under it now")
    assert_eq(_list.drop_row, last, "and the drop mark followed it there")
    _button(held, false)
    var after := _order()
    assert_false(_list.dragging, "the release ended the drag")
    assert_eq(after[0], "Layer %d" % (LAYERS - 1), "the top layer went to the bottom of the stack, %s" % [after])
    assert_eq(after.size(), LAYERS, "and no layer was lost")
    assert_true(_doc.undo(), "the move is undone")
    assert_eq(_order(), before, "and one undo puts the whole stack back, so the move was one history step")


func test_holding_a_row_in_the_middle_scrolls_nothing() -> void:
    var middle := _list.get_global_rect().get_center()
    var start := _list.rows[0].get_global_rect().get_center()
    _pick_up_the_top_row(middle.y - start.y)
    assert_true(_list.dragging, "the press and the travel began a drag")
    _list.scroll_vertical = 200
    _lay_out()
    var at := _list.scroll_vertical
    assert_eq(at, 200, "the list stands part way down")
    for i in 120:
        _edge().step(FRAME)
    assert_eq(_list.scroll_vertical, at, "two seconds held in the middle moved nothing")


func test_the_speed_grows_toward_the_edge_and_is_nothing_between_the_bands() -> void:
    var rect := Rect2(0, 0, 200, 400)
    var band := SaLayerListEdgeScroll.BAND
    assert_eq(SaLayerListEdgeScroll.speed_at(rect, Vector2(100, 200)), 0.0, "the middle is still")
    var inner := SaLayerListEdgeScroll.speed_at(rect, Vector2(100, band + 1.0))
    assert_eq(inner, 0.0, "just past the top band's inner side is still")
    var near := SaLayerListEdgeScroll.speed_at(rect, Vector2(100, 399))
    var far := SaLayerListEdgeScroll.speed_at(rect, Vector2(100, 400 - band * 0.75))
    assert_true(near > far and far > 0.0, "the bottom band scrolls down, faster nearer the edge, %f and %f" % [near, far])
    assert_true(SaLayerListEdgeScroll.speed_at(rect, Vector2(100, 1)) < 0.0, "the top band scrolls up")
    var top := SaLayerListEdgeScroll.TOP_SPEED
    var below := SaLayerListEdgeScroll.speed_at(rect, Vector2(100, 430))
    assert_eq(below, top, "below the list, over the buttons, it goes at the top speed")
    assert_eq(SaLayerListEdgeScroll.speed_at(rect, Vector2(100, -20)), -top, "and above it the same upward")
    assert_eq(SaLayerListEdgeScroll.speed_at(rect, Vector2(210, 399)), 0.0, "and so is beside it")
