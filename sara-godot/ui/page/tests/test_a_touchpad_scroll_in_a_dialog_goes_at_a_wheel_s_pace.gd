## A touchpad's scroll in a dialog does not run to the bottom.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Scrolling with two fingers inside Preferences or another dialog was far too
## fast and jumped to the bottom. On Wayland Godot hands a touchpad's two finger
## scroll over as a pan whose delta is the compositor's axis value, ten for a
## wheel click, and the engine's ScrollContainer and [SaStep] both read that
## delta as notches, so one click's worth of fingers went ten clicks.
##
## A pan now moves a page a logical pixel for every pixel of delta, because ten
## pixels of finger moving a page 48 to 75 was still too fast. So the scroll
## tests here send pans whose deltas add up to
## [constant SaStep.PAN_PER_NOTCH] ten times over, in uneven pieces the way
## fingers send them, and read the page 100 logical pixels down, within one,
## where ten wheel notches put it four to eight times as far. A wheel notch, a
## whole one and a Windows touchpad's fraction of one, still moves exactly as far
## as the wheel always has. The three are Preferences, the frame every filter's
## dialog scrolls its page in, and a value control on that page, which still
## steps once for every notch of pan.
##
## The events go in through the window's `push_input`, the GUI pass a hand's
## takes, because the fault is in which handler reads them and in what order:
## [SaScrollPace] runs on the scroll's `gui_input` signal ahead of the engine's
## own handler. The suite cannot advance a frame, so the layout the next frame
## would make is made by hand, as `test_a_wheel_over_the_volume_scrolls_the_page.gd`
## does.
extends "res://tests/test_framework.gd"

## Ten notches cut unevenly, in notches: they add up to exactly ten, and every
## piece and every running sum is a fraction a float holds exactly.
const PIECES: Array[float] = [1.25, 0.75, 3.0, 0.25, 1.75, 3.0]

## How far ten notches' delta of pan moves a page, in logical pixels: as far
## as the fingers moved.
const TEN_NOTCHES_OF_PAN: float = 10.0 * SaStep.PAN_PER_NOTCH

## The engine's `ScrollBar::PAGE_DIVISOR` (`scene/gui/scroll_bar.h`), which no
## script can read: a plain `ScrollContainer` moves an eighth of its page for a
## wheel notch.
const PAGE_DIVISOR: float = 8.0

## The plain dialog's window, logical, shorter than its page by far.
const DIALOG := Vector2i(520, 320)

## How many rows the plain dialog's page has, enough for ten notches of an
## eighth of a page each and more.
const ROWS: int = 60

var _host: Node = null
var _was_embedding: bool = false
var _was_hooked: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _was_hooked = tree.node_added.is_connected(SaScrollPace.take)
    SaScrollPace.install(tree)
    _host = Node.new()
    _host.name = "B20ScrollPaceHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    if not _was_hooked and tree.node_added.is_connected(SaScrollPace.take):
        tree.node_added.disconnect(SaScrollPace.take)
    tree.root.gui_embed_subwindows = _was_embedding


func test_a_pan_of_the_compositor_s_one_click_is_one_notch() -> void:
    var pan := _pan(1.0)
    assert_eq(pan.delta, Vector2(0.0, 10.0), "A wheel click is ten of a pan's delta under Mutter and Weston")
    assert_eq(SaStep.notches(pan), Vector2(0.0, 1.0), "and reads as one notch down")
    assert_eq(SaStep.notches(_wheel(MOUSE_BUTTON_WHEEL_DOWN)), Vector2(0.0, 1.0), "as a clicky wheel's notch does")
    var quarter := SaStep.notches(_wheel(MOUSE_BUTTON_WHEEL_DOWN, 0.25))
    assert_eq(quarter, Vector2(0.0, 0.25), "and a Windows touchpad's quarter is a quarter")


func test_preferences_pans_of_ten_notches_delta_move_it_as_far_as_the_fingers() -> void:
    var prefs := SaSettingsWindow.new()
    _host.add_child(prefs)
    prefs.show()
    assert_true(prefs.show_page("Keyboard shortcuts"), "Preferences opens its longest page")
    prefs.kept_pages.bring_in(&"", true)
    _lay_out(prefs)
    var scroll := prefs.content_scroll
    var bar := scroll.get_v_scroll_bar()
    var notch := SaUI.px(SaSettingsWindow.SaSettingsScroll.WHEEL_STEP)
    var travel := bar.max_value - bar.page
    assert_true(travel > 10.0 * notch, "the page has more than ten notches to travel, %s" % travel)
    assert_false(_hooked(scroll), "and Preferences reads its own pans, the filter leaves its scroll alone")
    var at := _inside(scroll)

    _to_top(scroll)
    _send(prefs, _wheel(MOUSE_BUTTON_WHEEL_DOWN), at)
    assert_eq(scroll.scroll_vertical, notch, "A wheel notch moves Preferences %d pixels, as it always has" % notch)
    _send(prefs, _wheel(MOUSE_BUTTON_WHEEL_DOWN, 0.5), at)
    assert_eq(scroll.scroll_vertical, notch + int(round(notch * 0.5)), "and a Windows touchpad's half notch half that")

    _to_top(scroll)
    for _notch in 10:
        _send(prefs, _wheel(MOUSE_BUTTON_WHEEL_DOWN), at)
    var by_wheel := bar.value
    assert_almost_eq(by_wheel, 10.0 * notch, 0.001, "Ten notches move it ten times as far")

    _to_top(scroll)
    for piece: float in PIECES:
        _send(prefs, _pan(piece), at)
    var said := "Pans of ten notches' delta move it %s pixels, not the wheel's %s, %s"
    assert_almost_eq(bar.value, TEN_NOTCHES_OF_PAN, 1.0, said % [TEN_NOTCHES_OF_PAN, by_wheel, bar.value])

    _to_top(scroll)
    for _flick in 100:
        _send(prefs, _pan(0.1), at)
    var crawled := "and so do a hundred pans of one pixel each, %s"
    assert_almost_eq(bar.value, TEN_NOTCHES_OF_PAN, 1.0, crawled % bar.value)


func test_a_filter_dialog_s_page_pans_of_ten_notches_delta_move_it_as_far_as_the_fingers() -> void:
    var built := _filter_page()
    var window: Window = built["window"]
    var scroll: ScrollContainer = built["scroll"]
    var bar := scroll.get_v_scroll_bar()
    var notch := bar.page / PAGE_DIVISOR
    assert_true(notch > 0.0, "the page has a height to move an eighth of")
    var travel := bar.max_value - bar.page
    assert_true(travel > 10.0 * notch, "and more than ten notches to travel, %s" % travel)
    assert_true(_hooked(scroll), "the filter took the plain scroll as it entered the tree")
    var at := _inside(scroll)

    _to_top(scroll)
    _send(window, _wheel(MOUSE_BUTTON_WHEEL_DOWN), at)
    assert_almost_eq(bar.value, notch, 0.001, "A wheel notch moves the page an eighth of itself, as the engine always has")
    _send(window, _wheel(MOUSE_BUTTON_WHEEL_DOWN, 0.25), at)
    assert_almost_eq(bar.value, notch * 1.25, 0.001, "and a Windows touchpad's quarter notch a quarter of that")

    _to_top(scroll)
    for _notch in 10:
        _send(window, _wheel(MOUSE_BUTTON_WHEEL_DOWN), at)
    var by_wheel := bar.value
    assert_almost_eq(by_wheel, 10.0 * notch, 0.001, "Ten notches move it ten times as far")

    _to_top(scroll)
    for piece: float in PIECES:
        _send(window, _pan(piece), at)
    var said := "Pans of ten notches' delta move it %s pixels, not the wheel's %s, %s"
    assert_almost_eq(bar.value, TEN_NOTCHES_OF_PAN, 1.0, said % [TEN_NOTCHES_OF_PAN, by_wheel, bar.value])

    for piece: float in PIECES:
        _send(window, _pan(-piece), at)
    assert_almost_eq(bar.value, 0.0, 1.0, "and the same pans up bring it back to the top, %s" % bar.value)


func test_a_value_control_on_the_page_steps_once_for_each_notch_of_pan() -> void:
    var built := _filter_page()
    var window: Window = built["window"]
    var scroll: ScrollContainer = built["scroll"]
    var knob: SaValueControl = built["knob"]
    var at := knob.get_global_rect().get_center()
    assert_true(scroll.get_global_rect().has_point(at), "the control is on the visible part of the page")

    _send(window, _wheel(MOUSE_BUTTON_WHEEL_UP), at)
    assert_almost_eq(knob.value, 1.0, 0.001, "A wheel notch up is one step, as it always was")
    _send(window, _wheel(MOUSE_BUTTON_WHEEL_UP, 0.5), at)
    _send(window, _wheel(MOUSE_BUTTON_WHEEL_UP, 0.5), at)
    assert_almost_eq(knob.value, 2.0, 0.001, "and two halves of a Windows touchpad's are one more")

    for piece: float in PIECES:
        _send(window, _pan(-piece), at)
    assert_almost_eq(knob.value, 12.0, 0.001, "Pans of ten notches' delta up are ten steps, not a hundred")
    assert_almost_eq(scroll.get_v_scroll_bar().value, 0.0, 0.001, "and the control took them, so the page stayed")


## A pan of *notches* down, negative for up, with the delta a compositor sends.
func _pan(notches: float) -> InputEventPanGesture:
    var event := InputEventPanGesture.new()
    event.delta = Vector2(0.0, notches * SaStep.PAN_PER_NOTCH)
    return event


## A wheel press, *factor* a fraction of a notch as a Windows touchpad sends it.
func _wheel(index: MouseButton, factor: float = 1.0) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = index
    event.pressed = true
    event.factor = factor
    return event


## *event* at *at* through *window*'s GUI pass, and a wheel's release after it.
func _send(window: Window, event: InputEventWithModifiers, at: Vector2) -> void:
    var pointed := event as InputEventMouse
    if pointed == null:
        var gesture := event as InputEventGesture
        gesture.position = at
        window.push_input(gesture, true)
        return
    pointed.position = at
    pointed.global_position = at
    window.push_input(pointed, true)
    var release := pointed.duplicate() as InputEventMouseButton
    release.pressed = false
    window.push_input(release, true)


## A point on *scroll*'s page clear of its rows' controls and of its bar, in
## its window's coordinates.
func _inside(scroll: ScrollContainer) -> Vector2:
    var rect := scroll.get_global_rect()
    return Vector2(rect.position.x + 4.0, rect.get_center().y)


func _to_top(scroll: ScrollContainer) -> void:
    scroll.get_v_scroll_bar().value = 0.0


## Whether [SaScrollPace] hooked *scroll*.
func _hooked(scroll: ScrollContainer) -> bool:
    for link: Dictionary in scroll.gui_input.get_connections():
        var heard: Callable = link["callable"]
        if heard.get_method() == &"_on_gui_input":
            return true
    return false


## A filter dialog's frame in a window of its own, its page taller than the
## window, with a value control as its first row.
func _filter_page() -> Dictionary:
    var window := Window.new()
    window.title = "A filter's page"
    window.position = Vector2i(40, 40)
    window.size = Vector2i(SaUI.px(DIALOG.x), SaUI.px(DIALOG.y))
    _host.add_child(window)
    SaUI.apply_to_window(window)
    var frame := SaFilterDialogFrame.new()
    window.add_child(frame)
    var knob := SaValueControl.new(0.0, -100.0, 100.0, 1.0)
    knob.custom_minimum_size = Vector2(SaUI.px(240), SaUI.px(32))
    frame.rows.add_child(knob)
    for row in ROWS:
        var label := Label.new()
        label.text = "Row %d" % row
        frame.rows.add_child(label)
    _lay_out(window)
    return {"window": window, "scroll": frame.scroll, "knob": knob}


## The layout the next frames would make, every container sorted three times
## over for the sizes to settle. The children that fill the window took its
## size as they entered it.
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
