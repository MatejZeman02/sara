## A click on a scroll bar's track brings the handle to the click.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A click where the scroll handle is not should jump the handle there, not just
## move it a bit in that direction. These press a themed bar's track at three
## places, a `ScrollContainer`'s vertical bar and a lone horizontal one, and
## read the value that puts the handle's middle at each press, within one step.
## They press the same place again and read no move, which is the engine
## finding the press on its handle, and they drag on from a jump and drag the
## handle itself and read the engine's drag moving it as before.
##
## **The engine's geometry, written out here.** The handle's length and travel
## are private to `ScrollBar`, so `_middle` reads them the way
## `scene/gui/scroll_bar.cpp` writes `get_area_size`, `get_grabber_size` and
## `get_grabber_offset`, apart from [SaScrollJump]'s own reading, so a wrong
## reading there fails here. The events go in through the window's
## `push_input`, the GUI pass a hand's takes.
extends "res://tests/test_framework.gd"

## The window, logical, and the list's page, far taller than the window.
const WINDOW := Vector2i(400, 300)
const ROWS: int = 120

## Where along each track the presses land, as a share of its length.
const PLACES: Array[float] = [0.9, 0.2, 0.6]

var _host: Node = null
var _was_embedding: bool = false
var _was_hooked: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _was_hooked = tree.node_added.is_connected(SaScrollJump.take)
    SaScrollJump.install(tree)
    _host = Node.new()
    _host.name = "ScrollJumpHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    if not _was_hooked and tree.node_added.is_connected(SaScrollJump.take):
        tree.node_added.disconnect(SaScrollJump.take)
    tree.root.gui_embed_subwindows = _was_embedding


func test_a_press_on_a_list_s_vertical_track_puts_the_handle_s_middle_there() -> void:
    var built := _list()
    await _settle()
    var bar: ScrollBar = (built["scroll"] as ScrollContainer).get_v_scroll_bar()
    assert_true(bar.max_value > bar.page * 3.0, "the list is several pages long, %s of %s" % [bar.page, bar.max_value])
    _press_three_places(built["window"], bar)


func test_a_press_on_a_lone_horizontal_track_puts_the_handle_s_middle_there() -> void:
    var built := _lone_bar()
    await _settle()
    _press_three_places(built["window"], built["bar"])


func test_dragging_on_from_a_jump_moves_the_handle_with_the_pen() -> void:
    var built := _list()
    await _settle()
    var window: Window = built["window"]
    var bar: ScrollBar = (built["scroll"] as ScrollContainer).get_v_scroll_bar()
    var at := _point(bar, 0.3)
    _push(window, _button(at, true))
    var jumped := bar.value
    assert_true(jumped > 0.0, "the press jumped the handle, %s" % jumped)
    _push(window, _motion(at + Vector2(0.0, 40.0)))
    _push(window, _button(at + Vector2(0.0, 40.0), false))
    var moved := _drag_value(bar, jumped, 40.0)
    var said := "dragging on 40 pixels moved it as the engine's drag does, %s for %s"
    assert_almost_eq(bar.value, moved, bar.step + 0.001, said % [bar.value, moved])


func test_a_press_on_the_handle_drags_it_as_before() -> void:
    var built := _list()
    await _settle()
    var window: Window = built["window"]
    var bar: ScrollBar = (built["scroll"] as ScrollContainer).get_v_scroll_bar()
    bar.value = (bar.max_value - bar.page) / 2.0
    var start := bar.value
    var on_handle := _local_to_window(bar, _middle(bar))
    _push(window, _button(on_handle, true))
    assert_eq(bar.value, start, "a press on the handle moves nothing")
    _push(window, _motion(on_handle - Vector2(0.0, 30.0)))
    _push(window, _button(on_handle - Vector2(0.0, 30.0), false))
    var moved := _drag_value(bar, start, -30.0)
    var said := "dragging it 30 pixels up moved it as before, %s for %s"
    assert_almost_eq(bar.value, moved, bar.step + 0.001, said % [bar.value, moved])


## Presses *bar*'s track at each of `PLACES`, reads the handle's middle there,
## and presses the same place again and reads no move.
func _press_three_places(window: Window, bar: ScrollBar) -> void:
    var axis := _axis(bar)
    for share: float in PLACES:
        var at := _point(bar, share)
        var along: float = (at - bar.get_global_rect().position)[axis]
        assert_true(not _on_handle(bar, along), "%s of the way along is off the handle before the press" % share)
        _click(window, at)
        var middle := _middle(bar)
        var one_step := absf(_middle_at(bar, bar.value + maxf(bar.step, 0.001)) - middle)
        var said := "a press %s of the way along puts the handle's middle at %s, it is at %s"
        assert_almost_eq(middle, along, one_step + 0.5, said % [share, along, middle])
        var landed := bar.value
        _click(window, at)
        assert_eq(bar.value, landed, "a second press there is on the handle and moves nothing")


func _axis(bar: ScrollBar) -> int:
    return 1 if bar is VScrollBar else 0


## A point *share* of the way along *bar*'s track and across its middle, in
## its window's coordinates.
func _point(bar: ScrollBar, share: float) -> Vector2:
    var rect := bar.get_global_rect()
    if _axis(bar) == 1:
        return Vector2(rect.get_center().x, rect.position.y + rect.size.y * share)
    return Vector2(rect.position.x + rect.size.x * share, rect.get_center().y)


func _local_to_window(bar: ScrollBar, along: float) -> Vector2:
    var rect := bar.get_global_rect()
    if _axis(bar) == 1:
        return Vector2(rect.get_center().x, rect.position.y + along)
    return Vector2(rect.position.x + along, rect.get_center().y)


## The engine's sizes for *bar*: the decrement arrow, the handle box's own
## length, and the length the handle's start travels.
func _geometry(bar: ScrollBar) -> Dictionary:
    var axis := _axis(bar)
    var grabber := bar.get_theme_stylebox(&"grabber")
    var least: float = grabber.get_minimum_size()[axis]
    var decrement: float = bar.get_theme_icon(&"decrement").get_size()[axis]
    var increment: float = bar.get_theme_icon(&"increment").get_size()[axis]
    var area: float = bar.size[axis] - bar.get_theme_stylebox(&"scroll").get_minimum_size()[axis]
    area -= decrement + increment + least
    return {"decrement": decrement, "least": least, "area": area}


## Where the handle's middle stands along *bar* at *value*.
func _middle_at(bar: ScrollBar, value: float) -> float:
    var g := _geometry(bar)
    var span := bar.max_value - bar.min_value
    var length: float = bar.page / span * float(g["area"]) + float(g["least"])
    var offset: float = float(g["area"]) * (value - bar.min_value) / span
    return float(g["decrement"]) + offset + length / 2.0


func _middle(bar: ScrollBar) -> float:
    return _middle_at(bar, bar.value)


func _on_handle(bar: ScrollBar, along: float) -> bool:
    var g := _geometry(bar)
    var span := bar.max_value - bar.min_value
    var length: float = bar.page / span * float(g["area"]) + float(g["least"])
    return absf(along - _middle(bar)) < length / 2.0


## The value the engine's drag gives *bar* from *start* after *pixels* of
## travel: the ratio moves by the pixels over the handle's travel.
func _drag_value(bar: ScrollBar, start: float, pixels: float) -> float:
    var g := _geometry(bar)
    var span := bar.max_value - bar.min_value
    var ratio := (start - bar.min_value) / span + pixels / float(g["area"])
    return clampf(bar.min_value + ratio * span, bar.min_value, bar.max_value - bar.page)


func _click(window: Window, at: Vector2) -> void:
    _push(window, _button(at, true))
    _push(window, _button(at, false))


func _push(window: Window, event: InputEvent) -> void:
    window.push_input(event, true)


func _button(at: Vector2, down: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = down
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
    event.position = at
    event.global_position = at
    return event


func _motion(at: Vector2) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    event.position = at
    event.global_position = at
    return event


func _window() -> Window:
    var window := Window.new()
    window.title = "A themed scroll bar"
    window.position = Vector2i(40, 40)
    window.size = Vector2i(SaUI.px(WINDOW.x), SaUI.px(WINDOW.y))
    _host.add_child(window)
    SaUI.apply_to_window(window)
    return window


## A list of labels taller than its window, in a plain `ScrollContainer`.
func _list() -> Dictionary:
    var window := _window()
    var scroll := ScrollContainer.new()
    window.add_child(scroll)
    scroll.size = Vector2(WINDOW)
    var rows := VBoxContainer.new()
    scroll.add_child(rows)
    for row in ROWS:
        var label := Label.new()
        label.text = "Row %d" % row
        rows.add_child(label)
    _lay_out(window)
    return {"window": window, "scroll": scroll}


## A lone horizontal bar along the window's foot, a page a tenth of its range.
func _lone_bar() -> Dictionary:
    var window := _window()
    var bar := HScrollBar.new()
    bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    bar.max_value = 1000.0
    bar.page = 100.0
    bar.step = 1.0
    window.add_child(bar)
    _lay_out(window)
    return {"window": window, "bar": bar}


## Frames enough for the scroll to lay out its page and size its bars, which it
## does deferred to a frame of its own.
func _settle() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    for _frame in 3:
        await tree.process_frame


func _lay_out(window: Window) -> void:
    for _pass in 3:
        _sort(window)


func _sort(node: Node) -> void:
    if node is Container:
        node.notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child in node.get_children():
        _sort(child)
    if node is Control:
        (node as Control).update_minimum_size()
