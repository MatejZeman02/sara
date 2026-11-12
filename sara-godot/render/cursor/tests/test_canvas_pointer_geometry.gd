## Which canvas, if any, owns the pixel under the pointer.
##
## Every function here answers that question, and every one of them has been
## wrong in a way that left the user with no pointer at all: the OS cursor is
## hidden process-wide while a software ring is drawn, so a wrong answer hides
## the cursor and draws the ring somewhere the user cannot see.
##
## These need real embedded windows rather than detached ones. A `Window` that
## is not in the scene tree reports `is_embedded() == false`, so a detached
## fixture makes `embedded_subwindows()` return nothing whatever the tree shape,
## and the test would pass against a function that always returned an empty
## array.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

var _host: Node = null
var _previous_embedding: bool = true


## Adding a Window to the scene tree is only safe while the root viewport embeds
## subwindows. Without embedding it maps a real OS window and the run blocks
## until the watchdog fires. Whether it embeds is a user setting, so it is forced
## here and put back afterwards.
##
## The host is parented to an autoload rather than to the root: the runner calls
## this from its own `_ready`, and a parent mid-`_ready` rejects `add_child`,
## leaving the node orphaned rather than failing loudly.
func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "PointerGeometryTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _previous_embedding


## A live canvas registered in `window`, sized past the window on purpose.
##
## _ready() scales the canvas to fit the viewport, so the geometry is set
## afterwards: the interesting case is a canvas bigger than what is showing it.
func _registered_canvas(window: Window, ring: float = 12.0) -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    window.add_child(canvas)
    canvas.position = Vector2.ZERO
    canvas.scale = Vector2.ONE
    canvas.size = Vector2(1920, 1080)
    canvas.cursor_ring_radius = ring
    return canvas


## A live canvas in whatever window *parent* already sits in, for the tests that
## have to use the real one because a popup will not embed inside a fixture.
func _registered_canvas_under(parent: Node, ring: float = 12.0) -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    parent.add_child(canvas)
    canvas.position = Vector2.ZERO
    canvas.scale = Vector2.ONE
    canvas.size = Vector2(1920, 1080)
    canvas.cursor_ring_radius = ring
    return canvas


func _embedded_window(parent: Node, window_size := Vector2i(200, 120)) -> Window:
    var window := Window.new()
    window.borderless = true
    window.size = window_size
    parent.add_child(window)
    window.show()
    return window


# --- Finding the windows drawn over the canvas -------------------------------------


## The bug this function exists for. Dockers are children of Main, not of the
## `Window`, so scanning the window's own children found none of them and the
## pointer over a docker read as "over the canvas". The live probe reported it
## as: found 3 embedded docker(s), the window's own children hold 0.
func test_a_window_nested_below_the_root_is_still_found() -> void:
    var middle := Node.new()
    _host.add_child(middle)
    var deeper := Node.new()
    middle.add_child(deeper)
    var docker := _embedded_window(deeper)

    assert_true(docker.is_embedded(), "The fixture must embed, or this test is measuring nothing")
    assert_eq(_host.get_children().size(), 1, "The host's own children hold no Window at all")
    assert_eq(SaCursorPolicy.embedded_subwindows(_host).size(), 1, "and the scan finds it anyway, three levels down")


## Anything below a Window that embeds its own is embedded in *that* window and
## measured in its coordinates, so returning it would mean testing an inner rect
## against the outer window's pointer.
func test_the_scan_stops_at_each_window_that_embeds() -> void:
    var outer := _embedded_window(_host)
    outer.gui_embed_subwindows = true
    var inner := Window.new()
    inner.borderless = true
    outer.add_child(inner)
    inner.show()

    var found := SaCursorPolicy.embedded_subwindows(_host)

    assert_eq(found.size(), 1, "Only the outer window belongs to this coordinate space")
    assert_true(found[0] == outer, "and it is the outer one")


## A window that embeds nothing leaves the windows below it in the space it
## stands in, so the scan finds them beside it. The note box is one, opened
## from the Brush Editor and embedded beside it in the root.
func test_the_scan_goes_on_below_a_window_that_embeds_nothing() -> void:
    var outer := _embedded_window(_host)
    outer.gui_embed_subwindows = false
    var inner := Window.new()
    inner.borderless = true
    outer.add_child(inner)
    inner.show()

    var found := SaCursorPolicy.embedded_subwindows(_host)

    assert_true(inner.is_embedded(), "The inner window is embedded where the outer one is")
    assert_eq(found.size(), 2, "so both belong to this coordinate space")
    assert_true(found.has(inner), "the inner one among them")


## A hidden docker covers nothing, so counting it would suppress the ring over
## canvas the user can actually see.
func test_a_hidden_window_is_not_counted() -> void:
    var docker := _embedded_window(_host)
    docker.hide()

    assert_true(SaCursorPolicy.embedded_subwindows(_host).is_empty(), "An invisible window is not over anything")


func test_scanning_nothing_finds_nothing() -> void:
    assert_true(SaCursorPolicy.embedded_subwindows(null).is_empty(), "A null root is empty, not a crash")


func test_several_windows_at_one_level_are_all_found() -> void:
    _embedded_window(_host)
    _embedded_window(_host)
    _embedded_window(_host)

    assert_eq(SaCursorPolicy.embedded_subwindows(_host).size(), 3, "Every docker counts, not just the first")


# --- Which window is being asked ----------------------------------------------------


## Without the window-bounds guard every window answered for the whole screen,
## so the info docker's scratchpad claimed a pointer that was really over
## another docker and hid the OS cursor for a ring nobody could see.
##
## The canvas here is deliberately larger than the window holding it, which is
## the ordinary case at any zoom above fit. That is what makes the guard load
## bearing: a point can be outside the window and still inside the canvas rect,
## and only the guard stops this window from claiming it. A test using a canvas
## that fits inside its window would pass with the guard deleted.
func test_a_pointer_outside_the_window_is_not_that_windows_business() -> void:
    var window := _embedded_window(_host, Vector2i(200, 120))
    var canvas := _registered_canvas(window)

    var inside := SaCursorPolicy.cursor_ring_radius_at(window, Vector2(100, 60))
    var outside_the_window := SaCursorPolicy.cursor_ring_radius_at(window, Vector2(900, 700))

    assert_almost_eq(inside, 12.0, 0.001, "Over the canvas, inside the window, the ring is reported")
    assert_true(canvas.get_global_rect().has_point(Vector2(900, 700)), "The far point really is inside the canvas rect")
    assert_true(outside_the_window < 0.0, "but outside the window it is another window's business")


func test_a_canvas_outside_any_window_reports_no_ring() -> void:
    assert_true(SaCursorPolicy.cursor_ring_radius_at(null, Vector2.ZERO) < 0.0, "No window, no ring")


## The single source of truth for "where is the pointer", so the decision to
## hide the OS cursor and the decision to draw a ring cannot disagree.
func test_the_pointer_of_no_window_is_off_screen() -> void:
    assert_eq(SaCursorPolicy.pointer_in_window(null), Vector2(-1.0, -1.0), "A missing window has no pointer in it")


# --- An open menu is a window too ----------------------------------------------


## A `PopupMenu` opened for a `MenuButton`, left visible for the caller to test
## and hidden again by `after_each` when the host is freed.
##
## `popup()` rather than the button's own `show_popup()`, which is what
## `SaMenuDriver` does for the same reason: nothing here is pressing the
## button, and a list popped up behind its owner's back has left the app unable
## to quit before, so the popup is placed by hand and never by the theme.
##
## Rows rather than a size, because `popup()` shrinks the window to its content
## and an empty menu comes back 40 by 8 whatever size was asked for. A fixture
## built from a size therefore tested points outside its own menu.
func _open_menu(parent: Node, at: Vector2i, rows: int) -> PopupMenu:
    var button := MenuButton.new()
    parent.add_child(button)
    var popup := button.get_popup()
    popup.borderless = true
    for i in rows:
        popup.add_item("Row %d" % i)
    popup.position = at
    popup.popup()
    return popup


## A `PopupMenu` is an *internal* child of whoever owns it, so a
## scan that asks only for ordinary children finds every docker and no menu at
## all, and the brush preset list opens downwards out of the tool options bar
## and across the canvas. The rows over the canvas were read as being over the
## canvas, the ring was claimed and drawn underneath the menu where nobody could
## see it, and mouse mode being process-wide took the OS cursor with it.
func test_an_open_menu_is_invisible_to_the_ordinary_scan() -> void:
    _open_menu(_host, Vector2i(40, 40), 8)

    assert_true(SaCursorPolicy.embedded_subwindows(_host).is_empty(), "The ordinary scan is what missed it")
    assert_eq(SaCursorPolicy.embedded_subwindows(_host, true).size(), 1, "and asking for internal children finds it")


## The fix, at both ends of the menu rather than at its centre: the preset list
## is tall enough to cross whatever lies under it, and a painter saw the cursor
## survive its top rows and vanish over its lower ones.
##
## The host window is the real one rather than a fixture, because a popup opened
## inside an embedded `Window` does not embed a second time: `is_embedded()`
## comes back false, its `position` is then in screen coordinates, and the scan
## skips it. Nesting is not what the note is about anyway. The preset list opens
## in the main window.
func test_an_open_menu_owns_the_pixels_it_covers() -> void:
    var window := (Engine.get_main_loop() as SceneTree).root
    _registered_canvas_under(_host)
    var menu := _open_menu(_host, Vector2i(100, 20), 12)

    # Read back rather than assumed, for the reason `_open_menu` records.
    var rect := Rect2(Vector2(menu.position), Vector2(menu.size))
    var top_row := rect.position + Vector2(rect.size.x * 0.5, 2.0)
    var last_row := rect.end - Vector2(rect.size.x * 0.5, 2.0)
    var beside_it := rect.position - Vector2(20.0, 0.0)

    assert_true(SaCursorPolicy.pointer_is_over_embedded_window(window, top_row), "The menu owns its top row")
    assert_true(
        SaCursorPolicy.pointer_is_over_embedded_window(window, last_row), "and its last row, which is the half that broke"
    )
    assert_false(SaCursorPolicy.pointer_is_over_embedded_window(window, beside_it), "and nothing beside it")
    assert_true(SaCursorPolicy.cursor_ring_radius_at(window, top_row) < 0.0, "so no ring is claimed under the menu")
    assert_true(SaCursorPolicy.cursor_ring_radius_at(window, last_row) < 0.0, "at either end of it")


## The ring is refused because something is drawn over it, not because the
## canvas stopped asking for one. Without this the test above would pass against
## a fix that simply switched the ring off, which would take the brush cursor
## with it.
func test_the_canvas_still_asks_for_a_ring_under_the_menu() -> void:
    var window := (Engine.get_main_loop() as SceneTree).root
    _registered_canvas_under(_host)
    var menu := _open_menu(_host, Vector2i(100, 20), 12)
    var last_row := Rect2(Vector2(menu.position), Vector2(menu.size)).end - Vector2(menu.size.x * 0.5, 2.0)

    assert_almost_eq(SaCursorPolicy.canvas_ring_radius_at(window, last_row), 12.0, 0.001, "The canvas is still under there")
    assert_true(SaCursorPolicy.cursor_ring_radius_at(window, last_row) < 0.0, "and the menu is what refuses it")
