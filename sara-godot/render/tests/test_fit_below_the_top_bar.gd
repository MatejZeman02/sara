## View > Fit to View and View > Center place the document in the part of the
## canvas the top bar leaves.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The main canvas reaches under the top bar on purpose, so a fit measured on that whole area put the top 86 texels of a 768
## square under the menus at an interface scale of 1.25. What is stated here is
## the arithmetic on a view whose top strip is covered, the real view reading its
## covers off the group, and main putting the bar in that group. The shots at 1.0
## and 1.25 are `scenarios/fit-to-view-puts-the-documents-top-under-the-top-bar.json`.
##
## The status line along the bottom edge is a cover as well, so
## the fit lands between the bar and the line: the arithmetic on a view covered
## at both edges, the real line read off the group by the real view, and main
## building the line. Its shots are
## `scenarios/a-status-line-says-the-zoom-size-and-colour-space.json`.
extends "res://tests/test_framework.gd"

## A real SaCanvas builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

const MAIN := "res://ui/main/main.gd"

## The window d11's dump reported at an interface scale of 1.25, in logical
## units, and the bar over it: 117 device pixels.
const WINDOW := Vector2(1536.0, 838.4)
const BAR := 93.6

var _host: Node = null


## A fake view whose top *top* units and bottom *bottom* units are drawn over,
## which is what the canvas view answers under the top bar and above the status
## line.
class CoveredView:
    extends SaTestFixtures.FakeView

    var covered_top: float = 0.0
    var covered_bottom: float = 0.0

    func _init(top: float, bottom: float = 0.0) -> void:
        covered_top = top
        covered_bottom = bottom
        viewport_size = WINDOW

    func get_visible_rect() -> Rect2:
        return Rect2(0.0, covered_top, viewport_size.x, viewport_size.y - covered_top - covered_bottom)


## Parented to an autoload rather than to the root, for the reason
## `test_canvas_view.gd` gives: the runner calls a suite from its own `_ready`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "D41TestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


func test_a_fit_lands_all_four_edges_below_a_covered_top_strip() -> void:
    var view := CoveredView.new(BAR)
    view.zoom = 3.0
    view.pan = Vector2(-400.0, -400.0)

    view.fit(Vector2i(768, 768))

    var top_left := view.document_to_screen(Vector2.ZERO)
    var bottom_right := view.document_to_screen(Vector2(768.0, 768.0))
    assert_almost_eq(view.zoom, (WINDOW.y - BAR) / 768.0, 1e-5, "The height left under the bar decides the zoom")
    assert_almost_eq(top_left.y, BAR, 1e-3, "The document's top edge is the bar's bottom edge, not under it")
    assert_almost_eq(bottom_right.y, WINDOW.y, 1e-3, "and its bottom edge is the window's")
    assert_true(top_left.x >= 0.0 and bottom_right.x <= WINDOW.x, "and both sides are inside the window")
    assert_almost_eq(top_left.x + bottom_right.x, WINDOW.x, 1e-3, "centred across it")


## The fit d41 filed, kept as the answer for a view with nothing over it: flush
## with the window's top, which under a bar of 93.6 hides about 86 texels.
func test_a_view_with_nothing_over_it_still_fits_the_whole_area() -> void:
    var view := SaTestFixtures.FakeView.new()
    view.viewport_size = WINDOW

    view.fit(Vector2i(768, 768))

    assert_almost_eq(view.document_to_screen(Vector2.ZERO).y, 0.0, 1e-3, "Nothing covered, so the top is the window's")
    assert_almost_eq(BAR / view.zoom, 85.7, 0.1, "which is the 86 texels the shot showed under the bar")


func test_centre_puts_the_middle_in_the_middle_of_what_is_left() -> void:
    var view := CoveredView.new(BAR)
    view.zoom = 0.8
    view.pan = Vector2(-900.0, -900.0)

    view.center(Vector2i(768, 768))

    var middle := view.document_to_screen(Vector2(384.0, 384.0))
    assert_almost_eq(view.zoom, 0.8, 1e-6, "The zoom is the painter's")
    assert_almost_eq(middle.x, WINDOW.x * 0.5, 1e-3, "The document's middle is the window's across")
    assert_almost_eq(middle.y, BAR + (WINDOW.y - BAR) * 0.5, 1e-3, "and the middle of what the bar leaves down")


## The real view over a real canvas: a cover along the top and one along the
## bottom narrow the area, and a hidden cover, a Control outside the group and a
## cover in another viewport do not.
func test_the_canvas_view_reads_its_covers_off_the_group() -> void:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(800, 600)
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    viewport.add_child(canvas)

    _cover(viewport, Rect2(0.0, 0.0, 800.0, 50.0), true, true)
    _cover(viewport, Rect2(0.0, 570.0, 800.0, 30.0), true, true)
    _cover(viewport, Rect2(0.0, 0.0, 800.0, 300.0), true, false)
    _cover(viewport, Rect2(0.0, 0.0, 800.0, 200.0), false, true)
    var elsewhere := SubViewport.new()
    elsewhere.size = Vector2i(800, 600)
    _host.add_child(elsewhere)
    _cover(elsewhere, Rect2(0.0, 0.0, 800.0, 400.0), true, true)

    var view := SaCanvasView.for_canvas(canvas)
    var area := view.get_visible_rect()
    assert_almost_eq(area.position.y, 50.0, 1e-3, "The top cover's bottom edge is where the visible area starts")
    assert_almost_eq(area.end.y, 570.0, 1e-3, "and the bottom cover's top edge is where it ends")
    assert_almost_eq(area.size.x, 800.0, 1e-3, "and the width is the viewport's")

    view.fit(Vector2i(256, 256))
    assert_almost_eq(view.document_to_screen(Vector2.ZERO).y, 50.0, 1e-3, "The fitted document starts below the top cover")
    assert_almost_eq(view.document_to_screen(Vector2(256.0, 256.0)).y, 570.0, 1e-3, "and ends above the bottom one")


## A cover taller than the window leaves nothing, and the fit falls back to the
## whole area rather than to a zoom of nothing.
func test_a_cover_over_everything_leaves_the_whole_area() -> void:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(400, 300)
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(64, 64)
    viewport.add_child(canvas)
    _cover(viewport, Rect2(0.0, 0.0, 400.0, 300.0), true, true)

    var area := SaCanvasView.for_canvas(canvas).get_visible_rect()
    assert_almost_eq(area.size.y, 300.0, 1e-3, "Nothing left to fit into is answered with the whole area")


## Read as source, because main needs the whole application to build: the
## scenario is the proof the bar is found, and this keeps the line from leaving.
func test_main_puts_the_top_bar_in_the_cover_group() -> void:
    var source := FileAccess.get_file_as_string(MAIN)
    assert_true(source.contains("custom_title_bar.add_to_group(SaCanvasView.COVER_GROUP)"), "The top bar is a cover")


func test_a_fit_lands_above_the_status_line() -> void:
    var line := float(SaStatusLine.HEIGHT)
    var view := CoveredView.new(BAR, line)
    view.zoom = 3.0
    view.pan = Vector2(-400.0, -400.0)

    view.fit(Vector2i(768, 768))

    var top_left := view.document_to_screen(Vector2.ZERO)
    var bottom_right := view.document_to_screen(Vector2(768.0, 768.0))
    assert_almost_eq(view.zoom, (WINDOW.y - BAR - line) / 768.0, 1e-5, "The height between the bar and the line decides the zoom")
    assert_almost_eq(top_left.y, BAR, 1e-3, "The document's top edge is the bar's bottom edge")
    assert_almost_eq(bottom_right.y, WINDOW.y - line, 1e-3, "and its bottom edge the line's top, not under the words")


## The real line, anchored along the bottom of a real viewport, is found by the
## real view the way the top bar is, and a fit ends at its top edge.
func test_the_canvas_view_reads_the_status_line_off_the_group() -> void:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(800, 600)
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    viewport.add_child(canvas)
    _cover(viewport, Rect2(0.0, 0.0, 800.0, 50.0), true, true)
    var line := SaStatusLine.new(Callable())
    viewport.add_child(line)

    var view := SaCanvasView.for_canvas(canvas)
    var area := view.get_visible_rect()
    assert_almost_eq(line.get_global_rect().position.y, 600.0 - SaStatusLine.HEIGHT, 1e-3, "The line hangs from the bottom edge")
    assert_almost_eq(area.end.y, 600.0 - SaStatusLine.HEIGHT, 1e-3, "and the visible area ends at its top")

    view.fit(Vector2i(256, 256))
    assert_almost_eq(
        view.document_to_screen(Vector2(256.0, 256.0)).y,
        600.0 - SaStatusLine.HEIGHT,
        1e-3,
        "so the fitted document ends above it"
    )

    line.visible = false
    assert_almost_eq(view.get_visible_rect().end.y, 600.0, 1e-3, "and a hidden line hides nothing")


## Read as source for the reason the bar's line is: main builds the line, which
## puts itself in the group, and the boot's fit waits for its size too.
func test_main_builds_the_status_line_and_the_boot_fit_waits_for_it() -> void:
    var source := FileAccess.get_file_as_string(MAIN)
    assert_true(source.contains("status_line = SaStatusLine.new("), "Main builds the status line")
    assert_true(source.contains("[custom_title_bar, status_line]"), "and the boot's fit counts it among the covers")


func _cover(viewport: SubViewport, rect: Rect2, shown: bool, grouped: bool) -> Control:
    var cover := Control.new()
    cover.position = rect.position
    cover.size = rect.size
    cover.visible = shown
    if grouped:
        cover.add_to_group(SaCanvasView.COVER_GROUP)
    viewport.add_child(cover)
    return cover
