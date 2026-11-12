## An idle Sara walked its whole tree twice a frame to find its windows, and
## now walks it only after the tree changed.
##
## The cursor package asks which windows stand over the pointer every frame,
## once for the main window's ring and once for the OS cursor sync. Each asking
## walked all 3,100 nodes, 120 to 200 microseconds, which was most of what an
## idle Sara on Windows took above a tenth of a core. `SaCursorRing.WindowWalk`
## keeps the list until `SceneTree.tree_changed`, and these suites hold it to the
## answers the walk gave: a window added, freed or moved among its siblings is
## seen at once, and a window shown or hidden is seen without any change to the
## tree.
extends "res://tests/test_framework.gd"

var _host: Control = null


func before_each() -> void:
    _host = Control.new()
    _host.name = "WindowWalkHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


func _window(parent: Node, window_name: String) -> Window:
    var window := Window.new()
    window.name = window_name
    window.visible = false
    parent.add_child(window)
    return window


func _names(windows: Array[Window]) -> Array[String]:
    var names: Array[String] = []
    for window in windows:
        names.append(String(window.name))
    return names


## A second asking with nothing changed answers from what the first walked.
func test_a_still_tree_is_walked_once() -> void:
    var inner := Control.new()
    _host.add_child(inner)
    _window(inner, "Deep")
    _window(_host, "Near")
    var first := SaCursorRing.WindowWalk.under(_host, false)
    assert_eq(_names(first), ["Deep", "Near"], "The walk finds a window however deep, in tree order")
    var key := "%d/%s" % [_host.get_instance_id(), false]
    assert_true(SaCursorRing.WindowWalk._walked.has(key), "and keeps what it found")
    assert_eq(_names(SaCursorRing.WindowWalk.under(_host, false)), ["Deep", "Near"], "which the next asking answers from")


## A window added, moved or freed changes the tree, and the next asking sees it.
func test_a_changed_tree_is_walked_again() -> void:
    var first := _window(_host, "First")
    SaCursorRing.WindowWalk.under(_host, false)
    var second := _window(_host, "Second")
    assert_eq(_names(SaCursorRing.WindowWalk.under(_host, false)), ["First", "Second"], "A window added is found")
    _host.move_child(second, 0)
    assert_eq(_names(SaCursorRing.WindowWalk.under(_host, false)), ["Second", "First"], "a window moved is found where it went")
    first.free()
    assert_eq(_names(SaCursorRing.WindowWalk.under(_host, false)), ["Second"], "and a window freed is gone")


## Nothing below a window that embeds its own is its parent's, which is where
## the walk stops.
func test_the_walk_stops_at_a_window_that_embeds() -> void:
    var outer := _window(_host, "Outer")
    outer.gui_embed_subwindows = true
    _window(outer, "Inside")
    assert_eq(_names(SaCursorRing.WindowWalk.under(_host, false)), ["Outer"], "A window embedded in another belongs to that one")


## A window that embeds nothing does not hold the windows below it, which stand
## in the same viewport as it does. The note box is one, a child of the window
## the note was taken in and embedded beside it.
func test_the_walk_goes_on_below_a_window_that_embeds_nothing() -> void:
    var outer := _window(_host, "Outer")
    outer.gui_embed_subwindows = false
    _window(outer, "Inside")
    assert_eq(
        _names(SaCursorRing.WindowWalk.under(_host, false)), ["Outer", "Inside"], "The box beside the window it was opened from"
    )


## An internal child is walked only when asked for, and the two answers are
## kept apart.
func test_internal_children_are_their_own_answer() -> void:
    var menu := Window.new()
    menu.name = "Internal"
    menu.visible = false
    _host.add_child(menu, false, Node.INTERNAL_MODE_BACK)
    assert_eq(_names(SaCursorRing.WindowWalk.under(_host, false)), [], "Without internal children a menu is not found")
    assert_eq(_names(SaCursorRing.WindowWalk.under(_host, true)), ["Internal"], "and with them it is")


## Shown and hidden change no tree, so the scans filter the kept list afresh.
func test_showing_a_window_needs_no_walk() -> void:
    var window := _window(_host, "Shown")
    assert_eq(SaCursorRing.windows_of_their_own(_host).size(), 0, "A hidden window stands over nothing")
    window.show()
    var own := SaCursorRing.windows_of_their_own(_host)
    var embedded := SaCursorRing.embedded_subwindows(_host)
    assert_eq(own.size() + embedded.size(), 1, "Shown, it is found by one scan or the other at once")
    window.hide()
    var found := SaCursorRing.windows_of_their_own(_host).size() + SaCursorRing.embedded_subwindows(_host).size()
    assert_eq(found, 0, "and hidden again by neither")


## A node outside the tree has no signal to forget by, so it is walked every
## time and nothing is kept for it.
func test_a_root_outside_the_tree_is_walked_each_time() -> void:
    var loose := Control.new()
    var window := Window.new()
    window.name = "Loose"
    loose.add_child(window)
    assert_eq(_names(SaCursorRing.WindowWalk.under(loose, false)), ["Loose"], "A detached root is walked")
    assert_false(SaCursorRing.WindowWalk._walked.has("%d/%s" % [loose.get_instance_id(), false]), "and nothing is kept for it")
    loose.free()
