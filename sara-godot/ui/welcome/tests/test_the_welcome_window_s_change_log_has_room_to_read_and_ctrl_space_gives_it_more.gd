## The welcome window's change log has room to read and
## Ctrl+Space gives it more. The change log on the welcome screen was too
## small, and Ctrl+Space did not make its area any bigger.
##
## The band was a third of the window's width at any width, so the maximised
## window's 1536 logical units gave it 512 and the News scroll fell from 140 to
## 51. The band now stops at `WelcomePicture.BAND_CEILING`, and what a taller
## window adds goes to the scroll. The window is opened in an embedded screen
## and fitted by hand, the way the band suite beside this one opens it. How it
## looks in the running app is the scenario of the same name.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## The first row below a one-row bar, which is `MainDockers.below_bar`'s floor.
const BAR := 65

## The maximised window's logical size on a 1920 by 1048 host at the maximise's
## 1.25, read off the running app's dump.
const TALL := Vector2i(1536, 838)

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
    _host.name = "U144WelcomeHost"
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


func test_the_band_is_a_third_of_the_width_below_the_ceiling_and_the_ceiling_above() -> void:
    var opening := WelcomePicture.band_height(SaWelcomeWindow.PANES_SIZE.x)
    assert_true(WelcomePicture.BAND_CEILING > opening, "the opening width is under the ceiling")
    assert_eq(WelcomePicture.band_height(720), 240, "a third of 720")
    assert_eq(WelcomePicture.band_height(840), WelcomePicture.BAND_CEILING, "840 reaches the ceiling")
    assert_eq(WelcomePicture.band_height(TALL.x), WelcomePicture.BAND_CEILING, "and %d stays at it" % TALL.x)


func test_a_taller_window_gives_its_height_to_the_news_scroll() -> void:
    SaUI.user_scale = 1.0
    var window := _opened(Vector2i(1920, 1080))
    window.news_pane.reveal()
    _settle(window)
    var opening := _read(window)
    assert_eq(opening["band"], 240, "the band opens at a third of 720: %s" % opening)
    assert_true(opening["scroll"] >= opening["three_notes"], "the opening scroll holds three notes: %s" % opening)

    window.size = TALL
    _settle(window)
    var tall := _read(window)
    assert_eq(tall["band"], WelcomePicture.BAND_CEILING, "the band stops at its ceiling: %s" % tall)
    assert_true(tall["scroll"] > opening["scroll"], "the scroll is taller at the taller size: %s against %s" % [tall, opening])
    var gained: int = TALL.y - int(opening["window"])
    var grew: int = tall["scroll"] - opening["scroll"]
    assert_true(grew >= floori(gained / 2.0), "the scroll takes %d, at least half the %d the window gained" % [grew, gained])
    # What is not the band, the feedback request or the scroll is the strip, the margins, the
    # tab bar, the pane's title and the button row, the same at either size.
    var same := absi(tall["rest"] - opening["rest"]) <= 1
    assert_true(same, "so the scroll is the window less the band and the feedback request: %s against %s" % [tall, opening])


## The heights the feedback request is about, in whole logical units.
func _read(window: SaWelcomeWindow) -> Dictionary:
    var scroll := window.news_pane.find_child("NewsScroll", true, false) as Control
    var ask := window.news_pane.find_child(WelcomeNewsPane.ASK_BLOCK, true, false) as Control
    var read := {
        "window": window.size.y,
        "band": ceili(window.band.custom_minimum_size.y),
        "ask": roundi(ask.size.y),
        "scroll": roundi(scroll.size.y),
        "three_notes": ceili(SaWelcomeWindow.three_notes_tall(scroll)),
    }
    read["rest"] = read["window"] - read["band"] - read["ask"] - read["scroll"]
    return read


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
