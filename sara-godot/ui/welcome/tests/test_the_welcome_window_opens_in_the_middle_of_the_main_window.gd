## "The Welcome window appears in the top-right side of the
## screen instead of in the middle."
##
## The window is held against the middle of the viewport it is embedded in, the
## first time and every time after, from `SaBoot.put_up` and from `open`, which
## is what Help > Welcome calls. The boot's copy follows a main window that
## takes another size after it is up, and stays where a painter dragged it.
## The host is a `SubViewport` that embeds, so its size is the suite's to change
## where the test runner's own window is not. With the subwindows off a window
## is placed against the main window on the screen, and a window that maps one
## of the OS's own hangs the run, so that case is held on the rectangle the
## window measures and the place it works out, and the scenario
## `the-welcome-window-opens-in-the-middle-of-the-main-window` opens it twice
## as a window of its own.
extends "res://tests/test_framework.gd"

const HOST_SIZE := Vector2i(1920, 1080)

var _host: SubViewport = null
var _previous_embedding: bool = true


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    _host = SubViewport.new()
    _host.name = "D84Host"
    _host.size = HOST_SIZE
    _host.gui_embed_subwindows = true
    _host.render_target_update_mode = SubViewport.UPDATE_DISABLED
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _previous_embedding


func test_the_boots_window_opens_in_the_middle() -> void:
    var welcome := SaWelcomeWindow.new(true)
    SaBoot.put_up(welcome, _host)
    assert_true(welcome.is_embedded(), "The boot's window is embedded in the host")
    assert_eq(welcome.position, _middle_for(welcome), "and opens with its middle on the host's")


func test_help_opens_it_in_the_middle_the_first_time_and_every_time_after() -> void:
    var welcome := SaWelcomeWindow.new()
    _host.add_child(welcome)
    welcome.open()
    assert_eq(welcome.position, _middle_for(welcome), "The first open is in the middle")
    welcome.hide()
    welcome.open()
    assert_eq(welcome.position, _middle_for(welcome), "and so is the second")
    welcome.position += Vector2i(300, -120)
    welcome.hide()
    welcome.open()
    assert_eq(welcome.position, _middle_for(welcome), "and an open after a drag starts in the middle again")


func test_the_window_follows_a_main_window_that_changes_size_under_it() -> void:
    var welcome := SaWelcomeWindow.new(true)
    SaBoot.put_up(welcome, _host)
    # The boot's window went up on a main window that had not taken its final
    # size, which is how it stood 16 pixels low of the middle on a 1048 high
    # window, and further off on a screen of another size.
    _host.size = Vector2i(1366, 728)
    welcome.follow_the_main_window()
    assert_eq(welcome.position, _middle_for(welcome), "A smaller main window takes it to its new middle")
    _host.size = Vector2i(2560, 1400)
    welcome.follow_the_main_window()
    assert_eq(welcome.position, _middle_for(welcome), "and so does a larger one")


func test_a_window_the_painter_moved_stays_where_it_was_put() -> void:
    var welcome := SaWelcomeWindow.new(true)
    SaBoot.put_up(welcome, _host)
    # Up and to the right, because the window is 720 high with the band above its panes,
    # and one dragged down would end past the bottom of the 900 the host
    # shrinks to, where the engine pushes it back inside and nothing here moved it.
    var put := welcome.position + Vector2i(200, -40)
    welcome.position = put
    _host.size = Vector2i(1600, 900)
    welcome.follow_the_main_window()
    assert_eq(welcome.position, put, "A dragged window is not taken back to the middle")


func test_a_hidden_window_does_not_move() -> void:
    var welcome := SaWelcomeWindow.new(true)
    SaBoot.put_up(welcome, _host)
    welcome.hide()
    var was := welcome.position
    _host.size = Vector2i(1600, 900)
    welcome.follow_the_main_window()
    assert_eq(welcome.position, was, "A main window that changes size under a hidden one leaves it alone")


func test_with_subwindows_off_it_measures_the_main_window_on_the_screen() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = false
    var welcome := SaWelcomeWindow.new()
    welcome.visible = false
    # Under the autoload rather than the root, which the runner is still
    # setting up children of.
    EventBus.add_child(welcome)
    assert_false(welcome.is_embedded(), "Under a root that embeds nothing the window is its own")
    var main := Rect2i(tree.root.position, tree.root.size)
    assert_eq(welcome.main_rect(), main, "and measures the main window where it is on the screen")
    welcome.free()


func test_the_middle_is_the_middle_of_the_rectangle_it_is_given() -> void:
    var main := Rect2i(Vector2i(2560, 40), Vector2i(1920, 1048))
    var at := SaWelcomeWindow.centred_in(main, Vector2i(720, 480))
    assert_eq(at, Vector2i(2560 + 600, 40 + 284), "A main window on a second screen has its middle there")
    var window_rect := Rect2i(at, Vector2i(720, 480))
    assert_eq(window_rect.get_center(), main.get_center(), "and the two rectangles share a centre")


## Where *welcome* stands with its middle on the host's, the host's visible
## rectangle less the window, halved.
func _middle_for(welcome: Window) -> Vector2i:
    var host := Vector2i(_host.get_visible_rect().size)
    @warning_ignore("integer_division")
    return Vector2i((host.x - welcome.size.x) / 2, (host.y - welcome.size.y) / 2)
