## ALT and a double click on a docker's drag handle open that docker's own
## Preferences, which is its line on Layouts and dockers since the docker
## pages folded into one.
##
## The gesture is ALT + double click on the docker, which opens its preferences
## window, and the only part of it that needed deciding is which page it lands
## on. Preferences reopened wherever it was last left is not the docker's
## settings, so the gesture resolves a page or does nothing, and doing nothing
## is asserted here as hard as doing something: an ALT double click that fell
## through to the docker's own controls would press whatever button sat under
## the second click.
extends "res://tests/test_framework.gd"


## A Window that answers `settings_category` the way a DockerWindow does, so the
## mapping can be exercised without building a docker, which maps a real OS
## window and hangs the run.
class StubDocker:
    extends Window

    var category: String = ""

    func settings_category() -> String:
        return category


func _press(alt: bool = true, double_click: bool = false) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.alt_pressed = alt
    event.double_click = double_click
    return event


func _release(alt: bool = true) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = false
    event.alt_pressed = alt
    return event


## A bound handle over a window that answers *category*, or over a plain Window
## when *category* is empty, which is what a dialog sharing this handle is.
func _handle(category: String) -> DockerDragHandle:
    var window: Window = StubDocker.new() if not category.is_empty() else Window.new()
    if window is StubDocker:
        window.category = category
    window.size = Vector2i(200, 150)
    var handle_control := Control.new()
    window.add_child(handle_control)
    var handle := DockerDragHandle.new()
    handle.bind(window, handle_control)
    return handle


func _drop(handle: DockerDragHandle) -> void:
    handle._window.free()
    handle.free()


# --- The mapping ---------------------------------------------------------------------


## Every docker's settings key reaches Layouts and dockers and its own line
## there, and the top bar's, which is no docker's, reaches its section there, or
## the gesture opens nothing over a window that plainly has settings.
func test_every_settings_category_resolves_to_its_line() -> void:
    var categories := SaSettings.reorderable_categories()
    assert_true(categories.size() >= 5, "The five const categories are the floor")

    for entry: Dictionary in categories:
        var category := String(entry["id"])
        var handle := _handle(category)

        assert_eq(
            DockerDragHandle.settings_page_of(handle._window),
            SaDockersPage.TITLE,
            "'%s' should resolve to Layouts and dockers" % category
        )
        assert_eq(DockerDragHandle.settings_row_of(handle._window), SaDockersPage.line_key(category), "on its own line")

        _drop(handle)


## The one docker whose node name is not its settings key. `ColorDocker` answers
## "ColorPicker" because every saved profile carries that word, so a mapping
## that used the node name would send the Colour Picker to no line at all.
func test_the_colour_docker_reaches_the_line_its_old_key_names() -> void:
    var handle := _handle("ColorPicker")

    assert_eq(DockerDragHandle.settings_page_of(handle._window), SaDockersPage.TITLE, "The old key still finds the page")
    assert_eq(DockerDragHandle.settings_row_of(handle._window), &"docker_ColorPicker", "and the line")

    _drop(handle)


## A category registered at runtime is found the same way a const one is, which
## is rule six read from the other end: a module's docker gets the gesture
## without a line here.
func test_a_runtime_category_reaches_its_line_too() -> void:
    assert_true(
        SaSettings.register_layout_category("F1TestDocker", "F1 Test Docker", ["Drag Handle"]), "A fresh category registers"
    )
    var handle := _handle("F1TestDocker")

    assert_eq(DockerDragHandle.settings_page_of(handle._window), SaDockersPage.TITLE, "the gesture finds the page")
    assert_eq(DockerDragHandle.settings_row_of(handle._window), &"docker_F1TestDocker", "and the module's line on it")

    _drop(handle)
    SaSettings.unregister_layout_category("F1TestDocker")


## Preferences, About and the filter dialogs share this handle through
## `SaDialogWindow` and answer no category, so there is no page to open over
## their title bars.
func test_a_window_that_is_not_a_docker_has_no_page() -> void:
    var handle := _handle("")

    assert_eq(DockerDragHandle.settings_page_of(handle._window), "", "A plain Window answers nothing")
    assert_eq(DockerDragHandle.settings_row_of(handle._window), &"", "and has no line")

    _drop(handle)


## An id nobody registered is a docker whose page was never built, and the
## lookup says so rather than handing back the id as a title.
func test_an_unregistered_category_has_no_page() -> void:
    var handle := _handle("NoSuchDocker")

    assert_eq(DockerDragHandle.settings_page_of(handle._window), "", "An unknown key resolves to no page")
    assert_eq(DockerDragHandle.settings_row_of(handle._window), &"", "and no line")

    _drop(handle)


# --- The gesture ---------------------------------------------------------------------


func test_alt_double_click_is_consumed_and_starts_no_drag() -> void:
    var handle := _handle("LayersDocker")

    assert_true(handle.handle_input(_press(true, true)), "The double click belongs to the gesture")
    assert_true(handle._is_alt_opening, "and asked for a page")
    assert_false(handle._is_alt_dragging, "without also moving the docker")

    _drop(handle)


## A Button acts on release, not on press, so a release the gesture leaves alone
## fires whatever control the second click landed on. The two drags consume
## theirs for the same reason.
func test_the_release_after_it_is_consumed_too() -> void:
    var handle := _handle("LayersDocker")
    handle.handle_input(_press(true, true))

    assert_true(handle.handle_input(_release()), "The release is part of the gesture")
    assert_false(handle._is_alt_opening, "and ends it")

    _drop(handle)


## The first press of a double click carries no `double_click` flag, so it is
## the move gesture, and the second press has to reach the page rather than
## start a second move.
func test_the_first_press_still_moves_and_the_second_opens() -> void:
    var handle := _handle("LayersDocker")

    assert_true(handle.handle_input(_press()), "The first press is the ALT move")
    assert_true(handle._is_alt_dragging, "and starts one")
    handle.handle_input(_release())
    assert_false(handle._is_alt_dragging, "which the release ends")

    assert_true(handle.handle_input(_press(true, true)), "The second press is the double click")
    assert_true(handle._is_alt_opening, "and asks for the page")
    assert_false(handle._is_alt_dragging, "rather than starting the move again")

    _drop(handle)


## Nothing at all, which is the clause the second half of the rule turns on: a docker
## with no page must not open Preferences wherever it was left, and the press
## must not reach the controls under it either.
func test_a_docker_with_no_page_consumes_the_click_and_opens_nothing() -> void:
    var handle := _handle("NoSuchDocker")

    assert_true(handle.handle_input(_press(true, true)), "The press is still swallowed")
    assert_false(handle._is_alt_opening, "and nothing was asked for")

    _drop(handle)


func test_a_double_click_without_alt_passes_through() -> void:
    var handle := _handle("LayersDocker")

    assert_false(handle.handle_input(_press(false, true)), "A plain double click is the docker's own")
    assert_false(handle._is_alt_opening, "and asks for no page")

    _drop(handle)


# --- Where it lands ------------------------------------------------------------------


## The page and the row the gesture asks for, handed to Preferences the way
## `MainDialogs.open_preferences` hands them, land on Layouts and dockers with
## the docker's line marked. The request itself is deferred and goes out on the
## bus, so it is read here from the two lookups it is made of, and the running
## app's half is the `docker_page` step of the scenario.
func test_what_the_gesture_asks_for_lands_on_the_dockers_line() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null or RenderingServer.get_rendering_device() == null:
        skip("a run without a RenderingDevice has no window in the tree to land a row in")
        return
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "N81AltHost"
    EventBus.add_child(host)
    var window := SaSettingsWindow.new()
    host.add_child(window)
    var handle := _handle("LayersDocker")

    window.toggle(DockerDragHandle.settings_page_of(handle._window), DockerDragHandle.settings_row_of(handle._window))
    var content := window.content_container
    assert_true(content.get_child(content.get_child_count() - 1) is SaDockersPage, "Preferences opens Layouts and dockers")
    assert_eq(String(window.search.report()["highlighted_row"]), "Layers", "on the Layers line, marked")

    _drop(handle)
    window.hide()
    host.free()
    tree.root.gui_embed_subwindows = was_embedding
