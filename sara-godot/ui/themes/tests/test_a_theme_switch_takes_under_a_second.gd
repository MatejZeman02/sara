## A colour theme switch with Preferences open takes under a
## second.
##
## A switch once took around fifteen seconds, and 0.2 s after the walks
## were batched. Nearly all of the fifteen seconds was not the
## switch's own call, which is about 100 ms, but the deferred walks of every
## window wearing the shared theme, one walk for each `changed` the theme
## emitted. The runner has no frames to wait on, so this times what it can
## run in one call, the switch and one walk of an open Preferences, and holds
## their sum at the switch's count of emissions under a second.
extends "res://tests/test_framework.gd"

## A switch the painter does not wait on.
const BUDGET_USEC := 1000000

var _saved_theme: String = "default"
var _saved_shared: Theme = null
var _heard: int = 0


func before_each() -> void:
    _saved_theme = SaTheme.palette_id
    _saved_shared = SaUI.shared_theme
    _heard = 0


func after_each() -> void:
    SaTheme.use_named(_saved_theme)
    SaUI.shared_theme = _saved_shared


func _on_changed() -> void:
    _heard += 1


func test_a_switch_with_preferences_open_costs_under_a_second() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This test needs the real scene tree")
    if tree == null:
        return
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    SaTheme.use_named("default")
    SaUI.init_global_theme(null)
    var shared := SaUI.shared_theme

    var host := Node.new()
    host.name = "N9PreferencesHost"
    EventBus.add_child(host)
    var window := SaSettingsWindow.new()
    window.theme = shared
    host.add_child(window)
    window.show()
    # A page is built when it is first shown, and these two are where the
    # painter switches from, the choice on Interface and the editor behind its
    # Edit colours…
    assert_true(window.show_page(SaSettingsWindow.INTERFACE_PAGE), "Preferences shows Interface")
    assert_true(window.show_colours(), "and the theme's colours")

    shared.changed.connect(_on_changed)
    var began := Time.get_ticks_usec()
    SaTheme.use_named("photoshop")
    var switch_usec := Time.get_ticks_usec() - began
    shared.changed.disconnect(_on_changed)

    began = Time.get_ticks_usec()
    window.propagate_notification(Control.NOTIFICATION_THEME_CHANGED)
    var walk_usec := Time.get_ticks_usec() - began
    var nodes := _count(window)

    var cost := switch_usec + _heard * walk_usec
    var reading := "a switch of %d us and %d walks of %d us over %d nodes, %d us" % [switch_usec, _heard, walk_usec, nodes, cost]
    assert_true(nodes > 100, "The walk crossed a built Preferences, %s" % reading)
    assert_true(_heard >= 1, "The switch told the windows at all, %s" % reading)
    assert_true(cost < BUDGET_USEC, "A theme switch with Preferences open costs under a second, %s" % reading)

    window.hide()
    host.free()
    tree.root.gui_embed_subwindows = was_embedding


func _count(root: Node) -> int:
    var total := 0
    for child: Node in root.get_children(true):
        total += 1 + _count(child)
    return total
