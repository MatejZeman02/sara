## Closing a message window by its button is not the reason a capture run
## finishes and then fails to quit.
##
## Forty runs of the same scenario under the offscreen compositor,
## twenty closing by the button and twenty closing by Escape, hung once each,
## which is the engine's Wayland shutdown hang and not a
## route. What a test can hold is the half that is about this class: the button route ends
## exactly where Escape ends, with the window answered, hidden and on its way
## out, so nothing a scenario closed is still alive when `quit()` is called.
##
## The dialog is opened inside the real tree with subwindows embedded, the way
## `test_sa_message.gd` does, because visibility means nothing outside a tree.
## The close is `SaMessage.capture_message`, the same static a scenario step
## reaches, rather than the buttons underneath it, so what is asserted is what a
## scenario actually gets. The question is built by `confirm` under a host of
## this suite's own rather than by the door's `ask` step, because that one
## parents to `tree.root` and the root is busy setting up children while a suite
## runs. `live_dialog` finds it either way, which is the half that matters here.
extends "res://tests/test_framework.gd"

var _previous_embedding: bool = true
var _host: Node = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "CloseTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _previous_embedding


## A two-button question up on screen, and the window a `close` step will reach.
func _ask() -> SaMessage:
    var tree := Engine.get_main_loop() as SceneTree
    var labels := PackedStringArray(["Cancel", "Quit"])
    var dialog := SaMessage.confirm(_host, "Close", "Close", labels, func(_i: int) -> void: pass, 0)
    assert_true(dialog.visible, "The question is up")
    return SaMessage.live_dialog(tree)


func _close(route: String) -> String:
    var tree := Engine.get_main_loop() as SceneTree
    return SaMessage.capture_message(tree, {"close": route})


## The filing's own route, and the line a scenario reads back from it.
func test_the_button_route_answers_the_cancel_index() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var dialog := _ask()
    assert_not_null(dialog, "The capture door's question is the live one")

    var said := _close("button")
    assert_eq(said, "SaCapture: message closed by button, answered 0", "answered as cancel: %s" % said)
    assert_false(dialog.visible, "and the window is down")
    assert_true(dialog.is_queued_for_deletion(), "and on its way out rather than parked in the tree")
    assert_null(SaMessage.live_dialog(tree), "so nothing is up for a later step to find")


## Escape ends in the same four states. The filing's asymmetry, if it were in
## this class, would be a difference here, and there is none.
func test_the_escape_route_ends_where_the_button_route_ends() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var dialog := _ask()
    assert_not_null(dialog, "The capture door's question is the live one")

    var said := _close("escape")
    assert_eq(said, "SaCapture: message closed by escape, answered 0", "answered as cancel: %s" % said)
    assert_false(dialog.visible, "and the window is down")
    assert_true(dialog.is_queued_for_deletion(), "and on its way out, exactly as the button leaves it")
    assert_null(SaMessage.live_dialog(tree), "so nothing is up for a later step to find")


## A button close that left the window findable would be a scenario's next step
## closing a ghost, and a window nothing can find is a window nothing holds.
func test_a_second_button_close_finds_nothing_left() -> void:
    _ask()
    assert_eq(_close("button"), "SaCapture: message closed by button, answered 0", "The first close answers")
    assert_eq(_close("button"), "SaCapture: no message window is up to close", "and the second finds nothing")
