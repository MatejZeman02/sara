## A touchpad's two finger scroll moves a dialog's page as far
## as the fingers move.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Scrolling with two fingers inside dialog windows was too fast. The pan read ten pixels of a pan as one
## wheel notch, and a notch is an eighth of a plain scroll's page or 48 logical
## pixels of Preferences', so ten pixels of finger still moved a page 48 to 75.
## A pan's delta is the compositor's axis value in logical pixels, and now it
## moves a page that many logical pixels, in [SaScrollPace] and in
## Preferences' `SaSettingsScroll` alike.
##
## Each test sends pans adding up to 100 pixels into a page, in uneven pieces
## the way fingers send them and then in a slow finger's quarter pixels, and
## reads the page moved 100 logical pixels within one. Each reads a wheel notch
## moving the page as far as it did before, an eighth of the page for a plain
## scroll and 48 logical pixels for Preferences. The events go in through the
## window's `push_input`, the GUI pass a hand's takes, for the reason
## `test_a_touchpad_scroll_in_a_dialog_goes_at_a_wheel_s_pace.gd` gives,
## and the layout the next frames would make is made by hand.
extends "res://tests/test_framework.gd"

## The finger travel every test sends, in logical pixels.
const TRAVEL: float = 100.0

## 100 pixels cut unevenly, every piece and every running sum a value a float
## holds exactly.
const PIECES: Array[float] = [12.5, 7.5, 30.0, 2.5, 17.5, 30.0]

## A slow finger's piece, a quarter of a pixel, which a bar that rounded every
## event to a whole pixel would never move by.
const CRAWL: float = 0.25

## The engine's `ScrollBar::PAGE_DIVISOR` (`scene/gui/scroll_bar.h`), which no
## script can read: a plain `ScrollContainer` moves an eighth of its page for a
## wheel notch.
const PAGE_DIVISOR: float = 8.0

## The plain dialog's window, logical, shorter than its page by far.
const DIALOG := Vector2i(520, 320)

## How many rows the plain dialog's page has, enough for 100 pixels and more.
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
    _host.name = "ScrollHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    if not _was_hooked and tree.node_added.is_connected(SaScrollPace.take):
        tree.node_added.disconnect(SaScrollPace.take)
    tree.root.gui_embed_subwindows = _was_embedding


func test_a_dialog_s_plain_scroll_moves_a_hundred_pixels_for_a_hundred_of_pan() -> void:
    var built := _filter_page()
    var window: Window = built["window"]
    var scroll: ScrollContainer = built["scroll"]
    assert_true(_hooked(scroll), "the filter took the frame's plain scroll as it entered the tree")
    _read_pace(window, scroll, scroll.get_v_scroll_bar().page / PAGE_DIVISOR, "the filter's page")


func test_preferences_moves_a_hundred_pixels_for_a_hundred_of_pan() -> void:
    var prefs := SaSettingsWindow.new()
    _host.add_child(prefs)
    prefs.show()
    assert_true(prefs.show_page("Keyboard shortcuts"), "Preferences opens its longest page")
    prefs.kept_pages.bring_in(&"", true)
    _lay_out(prefs)
    assert_false(_hooked(prefs.content_scroll), "and reads its own pans, the filter leaves its scroll alone")
    var notch := float(SaUI.px(SaSettingsWindow.SaSettingsScroll.WHEEL_STEP))
    _read_pace(prefs, prefs.content_scroll, notch, "Preferences")


## Reads *scroll* in *window* moving 100 logical pixels for pans of 100, in
## pieces and in a crawl, and back to the top for the same pans up, and a wheel
## notch still moving it *notch*.
func _read_pace(window: Window, scroll: ScrollContainer, notch: float, what: String) -> void:
    var bar := scroll.get_v_scroll_bar()
    var travel := bar.max_value - bar.page
    assert_true(travel > 2.0 * TRAVEL, "%s has more than %d pixels to travel, %s" % [what, 2.0 * TRAVEL, travel])
    var at := _inside(scroll)

    bar.value = 0.0
    for piece: float in PIECES:
        _send(window, _pan(piece), at)
    assert_almost_eq(bar.value, TRAVEL, 1.0, "Pans of 100 pixels move %s 100 logical pixels, %s" % [what, bar.value])
    for piece: float in PIECES:
        _send(window, _pan(-piece), at)
    assert_almost_eq(bar.value, 0.0, 1.0, "and the same pans up bring it back to the top, %s" % bar.value)

    for _crawl in int(TRAVEL / CRAWL):
        _send(window, _pan(CRAWL), at)
    var said := "A slow finger's %d quarter pixels move it 100 too, the fraction kept on the bar, %s"
    assert_almost_eq(bar.value, TRAVEL, 1.0, said % [int(TRAVEL / CRAWL), bar.value])

    bar.value = 0.0
    _send(window, _wheel(), at)
    assert_almost_eq(bar.value, notch, 0.001, "A wheel notch moves %s %s pixels, as it did before" % [what, notch])


## A pan of *delta* pixels down, negative for up, as a compositor sends it.
func _pan(delta: float) -> InputEventPanGesture:
    var event := InputEventPanGesture.new()
    event.delta = Vector2(0.0, delta)
    return event


func _wheel() -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_WHEEL_DOWN
    event.pressed = true
    event.factor = 1.0
    return event


## *event* at *at* through *window*'s GUI pass, and a wheel's release after it.
func _send(window: Window, event: InputEvent, at: Vector2) -> void:
    var gesture := event as InputEventGesture
    if gesture != null:
        gesture.position = at
        window.push_input(gesture, true)
        return
    var pressed := event as InputEventMouseButton
    pressed.position = at
    pressed.global_position = at
    window.push_input(pressed, true)
    var release := pressed.duplicate() as InputEventMouseButton
    release.pressed = false
    window.push_input(release, true)


## A point on *scroll*'s page clear of its rows' controls and of its bar, in
## its window's coordinates.
func _inside(scroll: ScrollContainer) -> Vector2:
    var rect := scroll.get_global_rect()
    return Vector2(rect.position.x + 4.0, rect.get_center().y)


## Whether [SaScrollPace] hooked *scroll*.
func _hooked(scroll: ScrollContainer) -> bool:
    for link: Dictionary in scroll.gui_input.get_connections():
        var heard: Callable = link["callable"]
        if heard.get_method() == &"_on_gui_input":
            return true
    return false


## A filter dialog's frame in a window of its own, its page of labels taller
## than the window.
func _filter_page() -> Dictionary:
    var window := Window.new()
    window.title = "A filter's page"
    window.position = Vector2i(40, 40)
    window.size = Vector2i(SaUI.px(DIALOG.x), SaUI.px(DIALOG.y))
    _host.add_child(window)
    SaUI.apply_to_window(window)
    var frame := SaFilterDialogFrame.new()
    window.add_child(frame)
    for row in ROWS:
        var label := Label.new()
        label.text = "Row %d" % row
        frame.rows.add_child(label)
    _lay_out(window)
    return {"window": window, "scroll": frame.scroll}


## The layout the next frames would make, every container sorted three times
## over for the sizes to settle.
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
