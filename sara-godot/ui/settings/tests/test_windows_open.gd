## Every window Sara can open must actually open, and come up usable.
##
## This suite exists because the Preferences window did not. It was hand-built as
## a bare `Window` rather than through `DockerWindow`, so it had no cursor
## overlay, no drag handle and no resizer, and nothing anywhere exercised it. The
## pointer vanished over its title bar for as long as it existed.
##
## The dockers were covered only in the sense that `test_ui_components` builds
## them under a *detached* parent and calls `_ready()` by hand. That never puts a
## window in the scene tree, so it cannot answer "does this open".
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true


## `sara_chrome` marks the windows that draw their own title bar and therefore owe
## a drag handle and a resizer. Everything here draws its own now: Godot's title
## bar sits outside the window's viewport, where a CursorOverlay cannot reach.
static func _windows_under_test() -> Array[Dictionary]:
    return [
        {"name": "ToolBoxDocker", "path": "res://ui/dockers/toolbox/toolbox_docker.gd", "sara_chrome": true},
        {"name": "ColorDocker", "path": "res://ui/dockers/color/color_docker.gd", "sara_chrome": true},
        {"name": "LayersDocker", "path": "res://ui/dockers/layers/layers_docker.gd", "sara_chrome": true},
        {"name": "InfoDocker", "path": "res://ui/dockers/panels/info_docker.gd", "sara_chrome": true},
        {"name": "ToolOptionsDocker", "path": "res://ui/dockers/tool_options/tool_options_docker.gd", "sara_chrome": true},
        {"name": "SaSettingsWindow", "path": "res://ui/settings/sa_settings_window.gd", "sara_chrome": true},
        {
            "name": "NewDocumentDialog",
            "path": "res://ui/dialogs/document/new_document/new_document_dialog.gd",
            "sara_chrome": true
        },
        {"name": "ColorSpaceDialog", "path": "res://ui/color_space/color_space_dialog.gd", "sara_chrome": true},
        {"name": "SaMessage", "path": "res://ui/dialogs/sa_message.gd", "sara_chrome": true},
    ]


func test_every_window_opens_with_a_cursor_overlay() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This suite needs the real scene tree to open a window in")
    if tree == null:
        return

    # Adding a Window to the scene tree is only safe while the root viewport
    # embeds subwindows. Without embedding it maps a real OS window and the run
    # blocks until the watchdog fires. Whether it embeds is a *user setting*
    # (SaSettings.embed_subwindows), so it is forced here rather than assumed,
    # and put back afterwards.
    var previous_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true

    # Not `tree.root`. The runner calls this from its own `_ready`, and a parent
    # that is mid-`_ready` rejects `add_child` outright, leaving the node
    # orphaned rather than failing loudly. An
    # autoload finished its own `_ready` long before the scene loaded, so it is
    # an in-tree parent that is not busy.
    var host := Node.new()
    host.name = "WindowOpenTestHost"
    EventBus.add_child(host)

    for entry: Dictionary in _windows_under_test():
        var window_name: String = entry["name"]
        var window: Window = load(entry["path"]).new()
        window.name = window_name
        host.add_child(window)
        window.show()

        assert_true(window.is_inside_tree(), "%s should be in the tree once added" % window_name)
        assert_true(window.visible, "%s should be visible after show()" % window_name)
        assert_true(window.is_embedded(), "%s must embed here, or this test maps a real OS window" % window_name)

        # The OS cursor is hidden process-wide while the brush ring is drawn, and
        # a Control can only draw inside its own viewport. A window with no
        # overlay therefore leaves the pointer invisible over it, which is the
        # exact bug this suite was written for.
        assert_not_null(window.get_node_or_null("CursorOverlay"), "%s needs its own CursorOverlay" % window_name)

        if entry["sara_chrome"]:
            assert_true(window.borderless, "%s draws its own chrome, so it must be borderless" % window_name)
            assert_not_null(
                window.find_child("DragHandleInput", true, false),
                "%s needs a drag handle, or ALT-drag does nothing" % window_name
            )
            assert_not_null(window.find_child("Resizer", true, false), "%s needs a resizer" % window_name)

        # A dialog has no system close affordance once it is borderless, so it
        # has to carry its own way out. The Preferences window shipped without
        # one and could not be closed at all.
        if window is SaDialogWindow:
            assert_not_null(window.close_button, "%s is a dialog and needs a close button" % window_name)
            # The × asks the window to close, the request Escape makes too,
            # and the window answers it by hiding.
            assert_true(window.close_requested.is_connected(window.hide), "%s close button must close it" % window_name)

            # The drag bar grows past BASE_DRAG_H whenever the title font needs
            # more room, and the content offset must follow, or every page draws
            # its first rows over the title strip.
            var bar_min: float = window.drag_handle.get_combined_minimum_size().y
            assert_true(
                window.content.offset_top + 0.5 >= bar_min,
                "%s content starts at %.1f but the drag bar needs %.1f" % [window_name, window.content.offset_top, bar_min]
            )

        window.free()

    host.free()
    tree.root.gui_embed_subwindows = previous_embedding


## A dialog has to be tall enough for the layout it builds, or its own buttons go
## off the bottom edge.
##
## Both colour dialogs shipped exactly like that. The colour space preview is
## three drawings and a readout put straight into the column above the button row,
## and a VBoxContainer's minimum is the sum of its children's, so the column
## demanded several times what the window had: File > New wanted 3586 against 660
## and Image > Colour Space 3716 against 500. Create, Assign and Convert were
## simply not on screen. Nothing clips, so there was no visual sign of it, and
## resizing did not help because the preview grew with the window.
##
## Measured as the minimum the layout demands rather than by looking at where the
## button landed, because a container only lays its children out on a later frame
## and this suite runs inside `_ready`. The minimum is available immediately and
## is the thing that was wrong.
func test_a_dialog_is_tall_enough_for_its_own_buttons() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This test needs the real scene tree, for the theme a Label measures against")
    if tree == null:
        return

    var previous_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "DialogFitTestHost"
    EventBus.add_child(host)

    for path: String in [
        "res://ui/dialogs/document/new_document/new_document_dialog.gd", "res://ui/color_space/color_space_dialog.gd"
    ]:
        var window: Window = load(path).new()
        host.add_child(window)
        window.show()

        var root_container := _outermost_container(window.content)
        assert_not_null(root_container, "%s should build its page inside a container" % window.name)
        if root_container != null:
            _lay_out(root_container, Vector2(window.size))
            var needed: float = root_container.get_combined_minimum_size().y
            assert_true(
                needed <= float(window.size.y),
                (
                    "%s opens at %d tall and its layout needs %d, so its buttons are off-screen"
                    % [window.name, window.size.y, int(needed)]
                )
            )
        window.free()

    host.free()
    tree.root.gui_embed_subwindows = previous_embedding


## The first Container under *node*, which is the one whose minimum size is the
## whole page's.
## Gives *root* the window's size and sorts every container under it once, which
## is the pass the next frame would make.
##
## A label that wraps asks for as many lines as its width allows, and before the
## first sort that width is nothing, so a page of titled rows reads thousands of
## pixels tall until it is laid out. The sort is synchronous and the minimum is
## read after it, so what is measured is still the minimum and not a position.
func _lay_out(root: Container, size: Vector2) -> void:
    root.size = size
    for _pass in 2:
        _sort(root)


func _sort(node: Node) -> void:
    if node is Container:
        node.notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child in node.get_children():
        _sort(child)
    # A resized label marks its lines stale without dropping the minimum its
    # parents cached, so the cache is dropped here, the way the frame would.
    if node is Control:
        (node as Control).update_minimum_size()


func _outermost_container(node: Node) -> Container:
    if node == null:
        return null
    for child in node.get_children():
        if child is Container:
            return child as Container
        var found := _outermost_container(child)
        if found != null:
            return found
    return null


## Every reorderable category must reach Preferences: the top bar as a page,
## and every docker as a line on Layouts and dockers.
##
## Adding one takes one edit, not three in two files (the element list in
## SaSettings.DEFAULT_ORDERS, a page title in the settings window, and a third
## dictionary mapping the title back to the key), because missing any of them
## would leave the docker with no settings page and nothing to say so.
func test_every_settings_category_has_a_preferences_page() -> void:
    var window := SaSettingsWindow.new()
    var dockers := SaDockersPage.new()

    for category_id: String in SaSettings.DEFAULT_ORDERS:
        assert_true(
            SaSettings.CATEGORY_TITLES.has(category_id),
            "%s has settings but no page title, so it would never appear in Preferences" % category_id
        )
        var title: String = SaSettings.CATEGORY_TITLES.get(category_id, "")
        assert_not_null(dockers.page.row(SaDockersPage.line_key(category_id)), "Layouts and dockers has a '%s' line" % title)
        assert_false(window.categories.has(title), "'%s' has no page in the sidebar" % title)
        assert_eq(
            SaSettingsWindow.internal_category_for(title),
            category_id,
            "The '%s' page should resolve back to its settings" % title
        )
        assert_false(SaSettings.get_layout_order(category_id).is_empty(), "%s should declare the elements it can reorder" % title)

    # And the fixed pages must not collide with a category name, but for the
    # Recorder's, the recorder's own settings named for the docker.
    # A door asking for Recorder opens that page, and the docker's line is on
    # Layouts and dockers, where the docker's drag bar opens it by its key.
    var shared := {"Recorder": SaSettingsWindow.internal_category_for("Recorder")}
    for page: String in SaSettingsWindow.FIXED_PAGES:
        var category: String = shared.get(page, "")
        assert_eq(SaSettingsWindow.internal_category_for(page), category, "'%s' is a fixed page, not a docker's list" % page)

    dockers.free()
    window.free()


## A docker registered at runtime, a module's, gets a line on Layouts and
## dockers with no edit to SaSettings, which is the whole point of
## register_layout_category.
func test_runtime_docker_category_gets_a_preferences_page() -> void:
    assert_true(
        SaSettings.register_layout_category("TestModuleDocker", "Test Module Docker", ["Drag Handle", "Resizer"]),
        "A fresh category id should register"
    )
    assert_false(SaSettings.register_layout_category("TestModuleDocker", "Again", ["Drag Handle"]), "A taken id must be refused")
    assert_false(
        SaSettings.register_layout_category("ColorPicker", "Impostor", ["Drag Handle"]), "A const category must not be shadowed"
    )
    assert_eq(
        SaSettings.get_layout_order("TestModuleDocker"),
        ["Drag Handle", "Resizer"],
        "The registered elements are the category's default order"
    )

    var found := false
    for entry: Dictionary in SaSettings.reorderable_categories():
        if entry["id"] == "TestModuleDocker":
            found = true
            assert_eq(entry["title"], "Test Module Docker", "The page keeps the registered title")
    assert_true(found, "The runtime category should be listed alongside the const ones")

    var dockers := SaDockersPage.new()
    assert_not_null(dockers.page.row(SaDockersPage.line_key("TestModuleDocker")), "Layouts and dockers gives it a line")
    assert_eq(
        SaSettingsWindow.internal_category_for("Test Module Docker"),
        "TestModuleDocker",
        "The title should resolve back to its settings key"
    )
    dockers.free()

    SaSettings.unregister_layout_category("TestModuleDocker")
    assert_true(SaSettings.get_layout_order("TestModuleDocker").is_empty(), "Unregister must remove the order again")
