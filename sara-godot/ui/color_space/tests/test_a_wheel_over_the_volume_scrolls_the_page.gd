## Over the gamut volume a plain wheel scrolls the page and
## Ctrl+wheel zooms the volume.
##
## Over the gamut volume the scroll wheel must not stop scrolling the page
## and zoom the volume instead. The volume took every wheel, so a painter
## reading down Preferences, Colour Spaces stopped wherever the pointer crossed
## it.
##
## The page is the one Preferences builds, `SaColorSpacesPage`, in a scroll as
## the Preferences window puts it, in an embedded window of its own. The wheel
## goes in through `push_input`, the GUI pass the pointer takes, because the
## fix is in which control the event reaches and a call on `apply_gesture` would
## not prove the page moved. The suite cannot advance a frame, so the layout the
## next frame would make is made by hand, the way `test_windows_open.gd` does.
extends "res://tests/test_framework.gd"

const WINDOW := Vector2i(640, 420)

var _host: Node = null
var _was_embedding: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding


## The page in a scroll in a window, laid out, scrolled to the bottom so a wheel
## up has somewhere to go.
func _page_in_a_scroll() -> Dictionary:
    _host = Node.new()
    _host.name = "WheelHost"
    EventBus.add_child(_host)
    var window := Window.new()
    window.title = "Preferences in a scroll"
    window.position = Vector2i(40, 40)
    window.size = WINDOW
    _host.add_child(window)
    SaUI.apply_to_window(window)

    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    window.add_child(scroll)
    var page := SaColorSpacesPage.new()
    page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(page)
    _lay_out(scroll)
    scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
    _lay_out(scroll)
    return {"window": window, "scroll": scroll, "solid": page.browser.solid}


func _lay_out(scroll: ScrollContainer) -> void:
    scroll.size = Vector2(WINDOW)
    for _pass in 3:
        _sort(scroll)


func _sort(node: Node) -> void:
    if node is Container:
        node.notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child in node.get_children():
        _sort(child)
    if node is Control:
        (node as Control).update_minimum_size()


## One wheel notch up over the middle of *solid*'s visible part, through the
## window's GUI pass.
func _wheel_up_over(window: Window, scroll: ScrollContainer, solid: SaGamutSolid, ctrl: bool) -> void:
    var seen := solid.get_global_rect().intersection(scroll.get_global_rect())
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_WHEEL_UP
    event.pressed = true
    event.factor = 1.0
    event.ctrl_pressed = ctrl
    event.position = seen.get_center()
    event.global_position = seen.get_center()
    window.push_input(event, true)
    var release := event.duplicate() as InputEventMouseButton
    release.pressed = false
    window.push_input(release, true)


func test_a_plain_wheel_over_the_volume_scrolls_the_page_and_leaves_the_zoom() -> void:
    var built := _page_in_a_scroll()
    var scroll: ScrollContainer = built["scroll"]
    var solid: SaGamutSolid = built["solid"]
    assert_true(scroll.get_v_scroll_bar().max_value > float(WINDOW.y), "the page is taller than its window, so it scrolls")
    var seen := solid.get_global_rect().intersection(scroll.get_global_rect())
    assert_true(seen.size.y > 20.0, "the volume is on screen at the bottom of the page, %s" % seen)
    assert_true(solid.scrolling_page() == scroll, "and the volume knows the page around it scrolls")

    var before := scroll.scroll_vertical
    _wheel_up_over(built["window"], scroll, solid, false)
    assert_true(scroll.scroll_vertical < before, "a plain wheel scrolled the page, %d then %d" % [before, scroll.scroll_vertical])
    assert_eq(solid.zoom, 1.0, "and left the volume's zoom alone")


func test_ctrl_wheel_over_the_volume_zooms_it_and_leaves_the_page() -> void:
    var built := _page_in_a_scroll()
    var scroll: ScrollContainer = built["scroll"]
    var solid: SaGamutSolid = built["solid"]

    var before := scroll.scroll_vertical
    _wheel_up_over(built["window"], scroll, solid, true)
    assert_true(solid.zoom > 1.0, "Ctrl+wheel up zoomed the volume in, to %s" % solid.zoom)
    assert_eq(scroll.scroll_vertical, before, "and the page stayed where it was")


## Where the volume stands alone the wheel keeps zooming, which is allowed
## and `test_gamut_solid_view.gd` has always driven.
func test_a_volume_standing_alone_zooms_on_a_plain_wheel() -> void:
    var solid := SaGamutSolid.new()
    solid.space = SaColorSpace.srgb()
    solid.size = Vector2(320.0, 240.0)
    var wheel := InputEventMouseButton.new()
    wheel.button_index = MOUSE_BUTTON_WHEEL_UP
    wheel.pressed = true
    wheel.position = solid.size * 0.5
    var taken := solid.apply_gesture(wheel)
    var zoom := solid.zoom
    solid.free()

    assert_true(taken, "a wheel over a volume with no page around it is taken")
    assert_true(zoom > 1.0, "and zooms it in, to %s" % zoom)
