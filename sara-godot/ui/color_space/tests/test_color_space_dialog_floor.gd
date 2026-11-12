## The Document Colour Space dialog cannot be dragged, or scaled, into cropping
## its own buttons.
##
## The dialog got cropped at the bottom, so half of
## it was not visible, and the half was the Cancel, Assign and Convert row. The
## constructor guessed a 600 by 430 floor and nothing measured the column, so the
## two disagreed the moment anything grew: the Font size preference multiplies
## every label and button height and `SaUI.scale()` leaves it out on purpose, so
## at 1.6 the column wanted 476 and the window still offered 430.
##
## Measured off the minimum the layout demands rather than off where a button
## landed, for the reason `test_windows_open` gives beside its own sibling of
## this test: a container lays its children out on a later frame and a suite runs
## inside `_ready`. The minimum is available at once and is the thing that was
## wrong.
extends "res://tests/test_framework.gd"

## The browser inside the dialog draws its gamut through the rendering device.
const REQUIRES_GPU := true


func test_the_floor_is_measured_rather_than_guessed() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This test needs the real scene tree, for the theme a Label measures against")
    if tree == null:
        return

    var previous_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "ColorSpaceFloorTestHost"
    EventBus.add_child(host)

    var dialog := ColorSpaceDialog.new()
    host.add_child(dialog)
    dialog.show()
    _settle(dialog)
    dialog.fit_to_content()

    assert_eq(dialog.logical_min_size, dialog.content_minimum(), "The floor is what the column asked for")
    assert_true(
        dialog.logical_min_size.x >= ColorSpaceDialog.FLOOR_SIZE.x,
        "and never narrower than the guess, which is what keeps the diagram readable"
    )
    assert_true(dialog.logical_size.y >= dialog.logical_min_size.y, "The size it opens at is at least the floor it lands on")

    dialog.size = dialog.min_size
    assert_true(
        float(dialog.size.y) >= float(dialog.content_minimum().y),
        "At its floor the dialog is %d tall and its column needs %d" % [dialog.size.y, dialog.content_minimum().y]
    )

    dialog.free()
    host.free()
    tree.root.gui_embed_subwindows = previous_embedding


func test_the_font_size_preference_lifts_the_floor_with_it() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This test needs the real scene tree")
    if tree == null:
        return

    var previous_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "ColorSpaceFontFloorTestHost"
    EventBus.add_child(host)

    # The gate runs res://tests/run_all.tscn rather than the app, so nothing has
    # built the theme yet. Built here and put back, the way test_ui_font does.
    var was_shared := SaUI.shared_theme
    var saved_scale := SaUI.user_font_scale
    SaUI.init_global_theme(null)
    SaUI.user_font_scale = 1.0
    SaUI.refresh_font_sizes()

    var dialog := ColorSpaceDialog.new()
    host.add_child(dialog)
    dialog.show()
    _settle(dialog)
    dialog.fit_to_content()
    var small := dialog.content_minimum()

    SaUI.user_font_scale = SaUI.MAX_FONT_SCALE
    SaUI.refresh_font_sizes()
    # A theme rewritten in place reaches its controls on the next frame, and a
    # suite runs inside `_ready`. Said here rather than waited for.
    dialog.propagate_notification(Control.NOTIFICATION_THEME_CHANGED)
    _settle(dialog)
    dialog.fit_to_content()
    var large := dialog.content_minimum()

    assert_true(large.y > small.y, "The largest Font size needs more room than the smallest: %d over %d" % [large.y, small.y])
    assert_eq(dialog.logical_min_size, large, "and the floor followed it there rather than staying at the guess")
    assert_true(dialog.size.y >= dialog.min_size.y, "The window was lifted to its new floor rather than left under it")

    dialog.free()
    host.free()
    SaUI.user_font_scale = saved_scale
    SaUI.refresh_font_sizes()
    SaUI.shared_theme = was_shared
    tree.root.gui_embed_subwindows = previous_embedding


func test_the_buttons_report_themselves_inside_the_window() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This test needs the real scene tree")
    if tree == null:
        return

    var previous_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "ColorSpaceCaptureTestHost"
    EventBus.add_child(host)

    assert_eq(ColorSpaceDialog.capture_state(tree.root), {}, "A dialog nobody opened reports nothing")

    var dialog := ColorSpaceDialog.new()
    host.add_child(dialog)
    dialog.show()
    _settle(dialog)
    dialog.fit_to_content()

    var report := ColorSpaceDialog.capture_state(tree.root)
    assert_false(report.is_empty(), "An open dialog reports itself")
    var buttons := report.get("buttons", {}) as Dictionary
    assert_eq(buttons.size(), 3, "Cancel, Assign and Convert")
    for named: String in ["CancelButton", "AssignButton", "ConvertButton"]:
        assert_true(buttons.has(named), "%s is in the dump, with its rectangle" % named)
    assert_eq(
        report.get("logical_min_size"),
        SaReportShapes.vec(Vector2(dialog.content_minimum())),
        "The dump carries the measured floor"
    )

    dialog.free()
    host.free()
    tree.root.gui_embed_subwindows = previous_embedding


## Every wrapping label asked again and every container sorted, outside in, twice.
##
## The column holds a wrapping line about the two buttons, and a wrapping `Label`
## answers the height of its whole text one character wide until the frame that
## lays it out. The app has that frame and a suite has none, so it is asked for
## by hand, the trade `test_the_about_window_fits_a_screen.gd` makes.
func _settle(dialog: ColorSpaceDialog) -> void:
    for _round in 2:
        _remeasure_labels(dialog.content)
        _sort_children(dialog.content)


func _remeasure_labels(node: Node) -> void:
    for child: Node in node.get_children():
        var label := child as Label
        if label != null and label.autowrap_mode != TextServer.AUTOWRAP_OFF:
            label.update_minimum_size()
        _remeasure_labels(child)


func _sort_children(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)
