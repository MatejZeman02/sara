## The boot's fit is taken again once the top bar and the window have their sizes.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The main canvas fits its document before `ui/` has built the bar and before the
## compositor has settled the window, so the fit `SaCanvas.resize_canvas` makes at
## boot measured a window with nothing over it. `SaBootFit` holds that fit through
## every size change until the view is moved or a button is pressed. What is
## stated here is the hold on a real canvas in a viewport with a cover, and the
## shots are `scenarios/the-boots-fit-is-taken-before-the-top-bar-has-a-size.json`
## with its `-restart` twin.
extends "res://tests/test_framework.gd"

## A real SaCanvas builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

var _host: Node = null


## Parented to an autoload rather than to the root, for the reason
## `test_canvas_view.gd` gives: the runner calls a suite from its own `_ready`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "D43TestHost"
    EventBus.add_child(_host)
    # A Size of 100, so the opening Ctrl+0's row gives is the fit read here.
    # Its 90 is `test_the_zoom_reads_as_the_picture_s_size_on_screen`'s.
    SaSettings.reset_zoom_size = 100


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    SaSettings.reset_zoom_size = SaView.RESET_SIZE


## The boot's shape: the canvas fits with nothing over it, then the bar gets its
## height.
func test_a_cover_that_gets_its_size_after_the_fit_is_fitted_below() -> void:
    var viewport := _viewport(Vector2i(800, 600))
    var canvas := _canvas(viewport, Vector2i(256, 256))
    var cover := _cover(viewport, Rect2(0.0, 0.0, 800.0, 0.0))
    canvas.resize_canvas(Vector2i(1024, 1024))
    assert_almost_eq(canvas.position.y, 0.0, 1e-3, "With nothing over it yet the fit takes the whole height")
    var hold := _hold(canvas, cover, null)

    cover.size = Vector2(800.0, 50.0)
    assert_true(hold._queued, "The cover's new size queues a fit for the end of the frame")
    hold.fit_again()

    var zoom := 550.0 / 1024.0
    assert_almost_eq(canvas.scale.x, zoom, 1e-4, "The height the cover leaves decides the zoom")
    assert_almost_eq(canvas.position.y, 50.0, 1e-3, "The document's top is the cover's bottom edge")
    assert_almost_eq(canvas.position.y + 1024.0 * zoom, 600.0, 1e-3, "and its bottom the viewport's")
    assert_true(hold._held, "A fit it made itself does not end the hold")


## The window settling smaller after the fit, which the resize handler answers by
## moving the pan by half the change and keeping the zoom.
func test_a_viewport_that_settles_smaller_is_fitted_again() -> void:
    var viewport := _viewport(Vector2i(800, 640))
    var canvas := _canvas(viewport, Vector2i(256, 256))
    var cover := _cover(viewport, Rect2(0.0, 0.0, 800.0, 0.0))
    canvas.resize_canvas(Vector2i(1024, 1024))
    var hold := _hold(canvas, cover, null)

    cover.size = Vector2(800.0, 50.0)
    hold.fit_again()
    viewport.size = Vector2i(800, 600)
    assert_almost_eq(canvas.position.y, 30.0, 1e-3, "The handler alone would leave the top 20 under the cover")
    assert_true(hold._queued, "The viewport's new size queues a fit")
    hold.fit_again()

    var zoom := 550.0 / 1024.0
    assert_almost_eq(canvas.scale.x, zoom, 1e-4, "Refitted to what the smaller viewport leaves")
    assert_almost_eq(canvas.position.y, 50.0, 1e-3, "with the top below the cover")
    assert_almost_eq(canvas.position.y + 1024.0 * zoom, 600.0, 1e-3, "and the bottom inside the viewport")
    assert_almost_eq(canvas.position.x + 512.0 * zoom, 400.0, 1e-3, "centred across the width")


func test_a_zoom_made_by_anything_else_ends_the_hold() -> void:
    var viewport := _viewport(Vector2i(800, 600))
    var canvas := _canvas(viewport, Vector2i(256, 256))
    var cover := _cover(viewport, Rect2(0.0, 0.0, 800.0, 0.0))
    canvas.resize_canvas(Vector2i(256, 256))
    var hold := _hold(canvas, cover, null)

    SaCanvasView.for_canvas(canvas).set_zoom(3.0)
    var placed := canvas.position
    cover.size = Vector2(800.0, 50.0)
    hold.fit_again()

    assert_almost_eq(canvas.scale.x, 3.0, 1e-4, "The zoom the painter chose stays")
    assert_true(canvas.position.is_equal_approx(placed), "and so does the pan")
    assert_false(hold._held, "and the hold is over")
    cover.size = Vector2(800.0, 80.0)
    assert_false(hold._queued, "A size change after it queues nothing")


func test_a_pan_alone_ends_the_hold_too() -> void:
    var viewport := _viewport(Vector2i(800, 600))
    var canvas := _canvas(viewport, Vector2i(256, 256))
    var cover := _cover(viewport, Rect2(0.0, 0.0, 800.0, 0.0))
    canvas.resize_canvas(Vector2i(256, 256))
    var hold := _hold(canvas, cover, null)

    canvas.position += Vector2(10.0, 0.0)
    var placed := canvas.position
    cover.size = Vector2(800.0, 50.0)
    hold.fit_again()

    assert_true(canvas.position.is_equal_approx(placed), "A pan of ten units is the painter's, not the boot's")
    assert_false(hold._held, "and it ends the hold")


func test_a_press_in_the_window_ends_the_hold() -> void:
    var viewport := _viewport(Vector2i(800, 600))
    var canvas := _canvas(viewport, Vector2i(256, 256))
    var cover := _cover(viewport, Rect2(0.0, 0.0, 800.0, 0.0))
    canvas.resize_canvas(Vector2i(256, 256))
    # Detached, because a Window in the tree maps a real one and stalls the run.
    var window := Window.new()
    var hold := _hold(canvas, cover, window)

    var motion := InputEventMouseMotion.new()
    window.window_input.emit(motion)
    assert_true(hold._held, "A pointer passing over the window is not the painter starting")
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    window.window_input.emit(press)
    assert_false(hold._held, "A press is")
    var placed := canvas.position
    cover.size = Vector2(800.0, 50.0)
    hold.fit_again()
    assert_true(canvas.position.is_equal_approx(placed), "and the view stays where the stroke was made")

    hold.free()
    window.free()


func test_the_main_window_holds_its_boot_fit_over_the_top_bar() -> void:
    var source := FileAccess.get_file_as_string("res://ui/main/main.gd")
    assert_true(source.contains("_hold_the_boot_fit()"), "Main's _ready holds the boot's fit")
    assert_true(
        source.contains("var covers: Array[Control] = [custom_title_bar, status_line]"),
        "with the top bar and the status line along the bottom as the covers it waits for"
    )


func _viewport(viewport_size: Vector2i) -> SubViewport:
    var viewport := SubViewport.new()
    viewport.size = viewport_size
    _host.add_child(viewport)
    return viewport


func _canvas(viewport: SubViewport, canvas_size: Vector2i) -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = canvas_size
    viewport.add_child(canvas)
    return canvas


func _cover(viewport: SubViewport, rect: Rect2) -> Control:
    var cover := Control.new()
    cover.position = rect.position
    cover.size = rect.size
    cover.add_to_group(SaCanvasView.COVER_GROUP)
    viewport.add_child(cover)
    return cover


func _hold(canvas: SaCanvas, cover: Control, window: Window) -> SaBootFit:
    var covers: Array[Control] = [cover]
    var hold := SaBootFit.new(canvas, SaCanvasView.for_canvas(canvas), covers, window)
    _host.add_child(hold)
    assert_true(hold._queued, "Joining the tree queues a fit, for a bar that already had its size")
    # The end of the frame that fit was queued for, so the next assertion about
    # a queued fit is about the size change that follows and not this one.
    hold.fit_again()
    assert_false(hold._queued, "and running it clears the queue")
    return hold
