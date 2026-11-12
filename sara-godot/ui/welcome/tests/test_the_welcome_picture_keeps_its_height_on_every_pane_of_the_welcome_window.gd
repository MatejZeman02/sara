## The welcome picture keeps its height on every pane.
##
## On a tablet the picture was seen resizing when the Quick settings pane came
## in front. The band takes the room the rows under it leave, and
## a `TabContainer` measures only the pane in front, so the band was shorter on
## the pane with the tallest minimum and jumped at each change of tab. The panes
## are measured together now, so the band is one height whichever is in front.
##
## The window is opened in an embedded screen of a logical size and fitted by hand,
## the way `test_the_welcome_band_gives_way_in_a_short_window` opens it. How it
## looks in the running app is
## `scenarios/the-welcome-picture-keeps-its-height-on-every-pane-of-the-welcome-window.json`.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## The first row below a one-row bar, which is `MainDockers.below_bar`'s floor.
const BAR := 65

## The Lenovo Yoga Tab Plus, 2944 by 1840 at the scale of 1.70 it opens at, in
## logical units.
const TABLET := Vector2i(1732, 1082)

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
    SaUI.user_scale = 1.0
    SaUI.user_font_scale = 1.0
    SaUI.init_global_theme(null)
    _kept_inset = SaDialogWindow.top_inset
    SaDialogWindow.top_inset = func() -> int: return BAR
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "U833WelcomeBandHost"
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


func test_at_the_tablet_s_size_the_band_is_one_height_on_every_pane() -> void:
    var window := _opened(TABLET)
    var heights := _heights_on_every_pane(window)
    assert_eq(heights.size(), 4, "four panes shown: %s" % [heights])
    for at in range(1, heights.size()):
        var said := "pane %d's band %d against Recent's %d, all %s" % [at, heights[at], heights[0], heights]
        assert_eq(heights[at], heights[0], said)


func test_at_the_floor_size_the_band_is_one_height_on_every_pane() -> void:
    var window := _opened(TABLET)
    window.size = window.min_size
    _settle(window)
    var heights := _heights_on_every_pane(window)
    for at in range(1, heights.size()):
        var said := "at the floor %s pane %d's band %d, all %s" % [window.size, at, heights[at], heights]
        assert_eq(heights[at], heights[0], said)


func test_at_the_opening_size_the_band_is_a_third_of_the_width_on_every_pane() -> void:
    var window := _opened(TABLET)
    assert_eq(window.size.x, SaWelcomeWindow.PANES_SIZE.x, "the window opens at its own width")
    var third := WelcomePicture.band_height(window.size.x)
    var heights := _heights_on_every_pane(window)
    for at in range(heights.size()):
        assert_eq(heights[at], third, "pane %d's band at the opening size, all %s" % [at, heights])


## A window too short for the band still shrinks it, by the same on every pane.
func test_in_a_host_too_short_the_band_gives_way_alike_on_every_pane() -> void:
    SaUI.user_scale = 2.0
    var window := _opened(Vector2i(640, 400))
    var heights := _heights_on_every_pane(window)
    assert_true(heights[0] < WelcomePicture.band_height(window.size.x), "the band gives way: %s" % [heights])
    for at in range(1, heights.size()):
        assert_eq(heights[at], heights[0], "pane %d's band %d against Recent's %d" % [at, heights[at], heights[0]])


## The band's height with each pane in front in turn, read off the laid out band.
func _heights_on_every_pane(window: SaWelcomeWindow) -> Array[int]:
    var heights: Array[int] = []
    for pane in range(window.tabs.get_tab_count()):
        window.tabs.current_tab = pane
        _settle(window)
        heights.append(roundi(window.band.size.y))
    return heights


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


## Lays *window* out the way a drawn frame would, the dialog suite's way, and
## tells the window Recent's minimum changed and the band its column did, calls
## the engine defers to a frame that never runs here.
func _settle(window: SaWelcomeWindow) -> void:
    for _pass in range(2):
        _sort_children(window)
        _ask_again(window)
    window.recent_pane.minimum_size_changed.emit()
    _ask_again(window)
    window.band.get_parent().minimum_size_changed.emit()
    var kept := window.size
    window.size = kept + Vector2i.ONE
    window.size = kept
    _sort_children(window)
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
