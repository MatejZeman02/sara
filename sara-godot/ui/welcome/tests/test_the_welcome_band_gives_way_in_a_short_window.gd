## The Welcome window's band gives way to the panes in a host
## too short for both, so New and Open stay inside the window.
##
## The band sat above the panes at a third of the window's width, and at a
## scale of 2 on a 1280 by 800 screen the window was 592 by 335 with New, Open
## and the switch from 337 down. The band is the one row that can be shorter, so
## it takes what the rows under it leave. On a screen with the room it is the
## third the band drew.
##
## The window is opened in an embedded screen of the logical size a screen has at
## its scale and fitted by hand after one sort, the way
## `test_every_dialog_opens_inside_the_window_at_every_size_and_scale` opens every
## dialog. How it looks in the running app is
## `scenarios/the-welcome-window-at-interface-scale-2.json`.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## The first row below a one-row bar, which is `MainDockers.below_bar`'s floor.
const BAR := 65

var _kept_scale: float = 1.0
var _kept_font_scale: float = 1.0
var _kept_theme: Theme = null
var _kept_inset: Callable = Callable()
var _kept_embedding: bool = true
var _host: Node = null


func before_each() -> void:
    _kept_scale = SaUI.user_scale
    _kept_font_scale = SaUI.user_font_scale
    _kept_theme = SaUI.shared_theme
    SaUI.user_font_scale = 1.0
    SaUI.init_global_theme(null)
    _kept_inset = SaDialogWindow.top_inset
    SaDialogWindow.top_inset = func() -> int: return BAR
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "D1WelcomeBandHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaUI.user_scale = _kept_scale
    SaUI.user_font_scale = _kept_font_scale
    SaUI.shared_theme = _kept_theme
    SaDialogWindow.top_inset = _kept_inset
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null


func test_on_a_short_screen_the_band_gives_way_and_the_buttons_stay_inside() -> void:
    SaUI.user_scale = 2.0
    var window := _opened(Vector2i(640, 400))
    var third := WelcomePicture.band_height(window.size.x)
    var band := ceili(window.band.custom_minimum_size.y)
    assert_true(band < third, "the band is %d, under the %d a third of %d would be" % [band, third, window.size.x])
    assert_true(band > 0, "and still shows")
    var under := ceili((window.band.get_parent().get_child(1) as Control).get_combined_minimum_size().y)
    var strip := ceili(window.title_strip_height())
    var fits := "strip %d, band %d and panes %d fit a window %d tall" % [strip, band, under, window.size.y]
    assert_true(strip + band + under <= window.size.y, fits)
    for button: String in ["NewButton", "OpenButton", "ShowAtStart"]:
        var rect := (window.find_child(button, true, false) as Control).get_global_rect()
        assert_true(Rect2(Vector2.ZERO, Vector2(window.size)).encloses(rect), "%s at %s is inside the window" % [button, rect])


func test_on_a_screen_with_the_room_the_band_is_a_third_of_the_width() -> void:
    SaUI.user_scale = 1.0
    var window := _opened(Vector2i(1920, 1080))
    assert_eq(window.size.x, SaWelcomeWindow.PANES_SIZE.x, "the window opens at its own width")
    var third := WelcomePicture.band_height(window.size.x)
    assert_eq(ceili(window.band.custom_minimum_size.y), third, "and the band is a third of it")


## A wrapping label under the band takes its height on the frame after the
## window's size, which is when the Recent pane's sentence went to two lines in
## the running app. The band hears its column for that. The engine says so on a
## deferred call that no frame runs here, so the suite says it.
func test_a_row_under_the_band_that_grows_takes_its_height_off_the_band() -> void:
    SaUI.user_scale = 2.0
    var window := _opened(Vector2i(640, 400))
    var before := ceili(window.band.custom_minimum_size.y)
    window.tabs.custom_minimum_size.y = window.tabs.get_combined_minimum_size().y + 20.0
    window.band.get_parent().minimum_size_changed.emit()
    assert_eq(ceili(window.band.custom_minimum_size.y), before - 20, "the band gives the 20 the panes took")
    window.tabs.custom_minimum_size.y = 0.0
    window.band.get_parent().minimum_size_changed.emit()
    assert_eq(ceili(window.band.custom_minimum_size.y), before, "and takes them back when the panes let go")


## The Welcome window on a fresh screen of *logical* units, opened and fitted.
func _opened(logical: Vector2i) -> SaWelcomeWindow:
    var window := SaWelcomeWindow.new()
    var screen := SubViewport.new()
    screen.size = logical
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    screen.add_child(window)
    window.popup_centered()
    _settle(window)
    window.fit_opening_size()
    _settle(window)
    return window


## Lays *window* out the way a drawn frame would, the dialog suite's way.
func _settle(window: Window) -> void:
    for _pass in range(2):
        _sort_children(window)
        _ask_again(window)
    var kept := window.size
    window.size = kept + Vector2i.ONE
    window.size = kept
    _sort_children(window)


func _sort_children(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)


func _ask_again(node: Node) -> void:
    for child: Node in node.get_children():
        _ask_again(child)
        if child is Control:
            (child as Control).update_minimum_size()
