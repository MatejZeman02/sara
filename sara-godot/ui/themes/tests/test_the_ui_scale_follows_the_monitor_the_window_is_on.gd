## A window's scale is the scale of the screen that window is
## on, and the one writer runs again when a window is dragged to another one.
##
## This matters on a 5:4 monitor at 100 percent beside a 4K one at 200
## percent, where every window would read one of the two. Two monitors are faked
## through SaUI.screen_override and SaUI.screen_scales_override, because a
## suite runs on one screen and the whole test would otherwise prove nothing.
extends "res://tests/test_framework.gd"

var _saved_user: float = 1.0
var _saved_os: float = -1.0
var _saved_screen: int = -1
var _saved_screens: Dictionary = {}


func before_each() -> void:
    _saved_user = SaUI.user_scale
    _saved_os = SaUI.os_scale_override
    _saved_screen = SaUI.screen_override
    _saved_screens = SaUI.screen_scales_override.duplicate()
    SaUI.user_scale = 1.0
    SaUI.os_scale_override = -1.0
    SaUI.screen_override = 0
    # The pair of monitors: screen 0 is the 4K monitor at 2x, screen 1
    # the 5:4 one at 1x, and a window belongs to whichever holds it.
    SaUI.screen_scales_override = {0: 2.0, 1: 1.0}


func after_each() -> void:
    SaUI.user_scale = _saved_user
    SaUI.os_scale_override = _saved_os
    SaUI.screen_override = _saved_screen
    SaUI.screen_scales_override = _saved_screens


## The reading itself: the same window asks a different screen and gets a
## different answer. Both screens once answered with whichever one
## the app called current, so a window dragged to the other kept its old scale.
func test_a_window_reads_the_scale_of_the_screen_it_is_on() -> void:
    var window := Window.new()
    assert_almost_eq(SaUI.window_scale(window), 2.0, 0.0001, "A window on the 4K monitor is at 2x")

    SaUI.screen_override = 1
    assert_almost_eq(SaUI.window_scale(window), 1.0, 0.0001, "The same window on the 5:4 monitor is at 1x")

    SaUI.screen_override = 0
    assert_almost_eq(SaUI.window_scale(window), 2.0, 0.0001, "and moving it back is 2x again")
    window.free()


## A window that is in no tree has no screen of its own to read, which is a
## suite's window and a docker's before it is parented. -1 is what the display
## server's own queries take to mean the current screen.
func test_a_window_in_no_tree_answers_for_the_current_screen() -> void:
    var window := Window.new()
    SaUI.screen_override = -1
    SaUI.screen_scales_override = {-1: 1.5}
    assert_eq(SaUI.screen_of(window), -1, "A detached window is on no screen")
    assert_almost_eq(SaUI.window_scale(window), 1.5, 0.0001, "and asks the display server for the current one")
    window.free()


## A screen change moves the scale exactly once, and the sweep
## that finds nothing moved writes nothing.
func test_the_sweep_moves_the_scale_once_when_the_screen_changes() -> void:
    var window := Window.new()
    SaUI.apply_to_window(window)
    assert_almost_eq(window.content_scale_factor, 2.0, 0.0001, "The window starts on the 4K monitor")

    SaUI.screen_override = 1
    assert_eq(SaUI.apply_to_windows([window]), 1, "One window changed screen, so the sweep writes one")
    assert_almost_eq(window.content_scale_factor, 1.0, 0.0001, "and the write is the 5:4 monitor's scale")

    assert_eq(SaUI.apply_to_windows([window]), 0, "A second sweep with nothing moved writes nothing")
    assert_almost_eq(window.content_scale_factor, 1.0, 0.0001, "and the scale stays where the first sweep put it")
    window.free()


## The user's preference is still a multiplier on top of whatever the screen
## says, so it survives a move rather than being replaced by the screen's own
## number.
func test_the_user_preference_multiplies_the_screens_own_scale() -> void:
    SaUI.user_scale = 1.5
    var window := Window.new()
    assert_almost_eq(SaUI.scale_for(window), 3.0, 0.0001, "2x from the 4K screen, times 1.5 from the preference")

    SaUI.screen_override = 1
    assert_almost_eq(SaUI.scale_for(window), 1.5, 0.0001, "1x from the other screen, times the same preference")
    window.free()


## An embedded subwindow renders inside its host's already scaled viewport, so
## the sweep leaves it to the host rather than writing it a second factor.
func test_the_sweep_leaves_an_embedded_window_to_its_host() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var previous: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true

    var host := Node.new()
    host.name = "W2EmbeddedHost"
    EventBus.add_child(host)
    var embedded := Window.new()
    host.add_child(embedded)
    assert_true(embedded.is_embedded(), "The fixture must embed, or this test measures nothing")

    assert_eq(SaUI.apply_to_windows([embedded]), 0, "An embedded window is its host's business, not the sweep's")

    host.free()
    tree.root.gui_embed_subwindows = previous


## The walk the follower runs. A window that arrives later is found by being in
## the tree, with nothing anywhere having to register it.
func test_the_walk_finds_the_root_and_any_window_under_it() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var previous: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true

    var host := Node.new()
    host.name = "W2WalkHost"
    EventBus.add_child(host)
    var inner := Window.new()
    host.add_child(inner)

    var found := SaUI.windows_in(tree)
    assert_true(found.has(tree.root), "The root window is the app's own and is in the walk")
    assert_true(found.has(inner), "and a window parented under anything is found without registering")
    assert_eq(found.count(tree.root), 1, "The root is a Window, so the walk yields it once rather than twice (d3)")

    var distinct := {}
    for window in found:
        distinct[window] = true
    assert_eq(found.size(), distinct.size(), "and no window is listed twice, whatever the tree holds (d3)")

    host.free()
    tree.root.gui_embed_subwindows = previous


## The app-wide answer is unchanged: `scale()` still reports the current
## screen's scale for the callers that have no window in hand.
func test_the_app_wide_scale_is_the_current_screens() -> void:
    assert_almost_eq(SaUI.scale(), 2.0, 0.0001, "The current screen is the 4K one")
    SaUI.screen_override = 1
    assert_almost_eq(SaUI.scale(), 1.0, 0.0001, "and it follows the current screen")
