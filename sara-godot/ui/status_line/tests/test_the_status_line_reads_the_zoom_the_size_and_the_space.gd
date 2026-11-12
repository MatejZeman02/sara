## The status line along the bottom edge reads the zoom, the document's size and
## its colour space, and reads them again after a zoom and a new document.
## The zoom is two figures, Zoom against the fit and Pixels
## against the screen, which `core/api/tests/test_the_zoom_reads_as_the_picture_s_size_on_screen.gd`
## holds in full.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The runner is synchronous, so a change is followed by the reading the line
## queued for the end of the frame, taken by hand with `refresh()`, and the
## suite reads that the change queued it first. That the line is a cover Fit
## leaves room for is `render/tests/test_fit_below_the_top_bar.gd`'s, and the
## running app at 1920 by 1080 and on the 1280 by 1024 panel is
## `scenarios/a-status-line-says-the-zoom-size-and-colour-space.json`.
extends "res://tests/test_framework.gd"

## A real easel holds the document, and an easel needs a RenderingDevice.
const REQUIRES_GPU := true

var _host: Node = null
var _surface: SaSurface = null
var _line: SaStatusLine = null


## A fake view on a window at an interface scale, which is all the zoom's
## reading asks of a view beyond the zoom itself.
class ScaledView:
    extends SaTestFixtures.FakeView

    var content_scale: float = 1.0

    func get_content_scale() -> float:
        return content_scale


## Parented to an autoload rather than to the root, for the reason
## `test_canvas_view.gd` gives: the runner calls a suite from its own `_ready`.
func before_each() -> void:
    _host = Control.new()
    _host.name = "StatusLineTestHost"
    EventBus.add_child(_host)
    _surface = SaTestFixtures.make_surface(Vector2i(256, 256))
    _line = SaStatusLine.new(func() -> SaSurface: return _surface)
    _host.add_child(_line)
    _line.refresh()


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    SaTestFixtures.teardown(_surface)
    _surface = null
    _line = null


func test_the_line_reads_the_three_words_of_the_document_it_opens_on() -> void:
    assert_eq(_line.zoom_label.text, "Zoom 26%", "A 256 square at a true scale of one is a quarter of its fit in 1000")
    assert_eq(_line.pixels_label.text, "Screen 100%", "and one texel on one pixel of a view with no interface scale")
    assert_eq(_line.size_label.text, "256 x 256 px", "The size is the document's, in pixels")
    assert_eq(_line.space_label.text, "sRGB, F32", "The space is the document's, with its depth")


func test_a_zoom_is_read_at_the_end_of_the_frame_it_happened_in() -> void:
    _surface.view.set_zoom(2.5)

    assert_true(_line._queued, "The view's transform_changed queued a reading")
    assert_eq(_line.zoom_label.text, "Zoom 26%", "which is not taken before the frame ends")
    _line.refresh()
    assert_eq(_line.zoom_label.text, "Zoom 64%", "and reads the new zoom once it is")
    assert_eq(_line.pixels_label.text, "Screen 250%", "and the new pixels")
    assert_false(_line._queued, "and asks for no second one")


func test_a_new_document_is_read_with_its_size_and_its_space() -> void:
    _surface.get_document().reset_to_default(Vector2i(1024, 768), SaColorSpace.display_p3().with_depth(SaColorSpace.Depth.F16))

    assert_true(_line._queued, "A new document's colour space queued a reading")
    _line.refresh()
    assert_eq(_line.size_label.text, "1024 x 768 px", "The new size, which the document had only after its space was announced")
    assert_eq(_line.space_label.text, "Display P3, F16", "and the new space with its depth")


func test_a_resize_is_read() -> void:
    _surface.get_document().canvas_size = Vector2i(300, 200)
    EventBus.document_resized.emit(_surface.get_document(), Vector2i(300, 200))

    assert_true(_line._queued, "A resize queued a reading")
    _line.refresh()
    assert_eq(_line.size_label.text, "300 x 200 px", "and the line reads the size the crop left")


## Pixels 100% is one texel on one device pixel, so at an interface scale of
## 1.25 it is a zoom of 0.8, where Actual Pixels puts the view.
func test_the_pixels_read_a_hundred_per_cent_after_actual_pixels_at_every_scale() -> void:
    var view := ScaledView.new()
    view.content_scale = 1.25
    view.zoom_to_actual_pixels(Vector2.ZERO)

    assert_almost_eq(view.get_zoom(), 0.8, 1e-6, "Actual Pixels at 1.25")
    assert_eq(SaStatusLine.pixels_text(view), "Screen 100%", "reads as the hundred per cent it is named for")


func test_a_zoom_below_ten_per_cent_keeps_a_tenth() -> void:
    var view := SaTestFixtures.FakeView.new()
    var square := Vector2i(1000, 1000)
    view.zoom = 0.154
    assert_eq(SaStatusLine.zoom_text(view, square), "Zoom 15%", "From ten up, whole per cents")
    assert_eq(SaStatusLine.pixels_text(view), "Screen 15%", "for both figures")
    view.zoom = 0.05
    assert_eq(SaStatusLine.zoom_text(view, square), "Zoom 5.0%", "and below it a tenth")
    view.zoom = 0.01
    assert_eq(SaStatusLine.zoom_text(view, square), "Zoom 1.0%", "down to the view's floor")
    assert_eq(SaStatusLine.zoom_text(view, Vector2i.ZERO), "", "and no figure for a document with nothing to fit")


## A document tagged with a gamut no preset is has no preset's name, and the
## line calls it by the gamut, the way the presets' own names read.
func test_a_space_no_preset_names_is_called_by_its_gamut() -> void:
    var adobe := SaColorSpace.create(
        SaColorSpace.ID_CUSTOM, SaColorNames.adobe_rgb_primaries(), SaColorSpace.WHITE_D65, SaTransferFunction.srgb()
    )
    assert_eq(SaStatusLine.space_text(adobe), "Adobe RGB, F32", "A custom space in RGB is its gamut")
    var in_oklab := adobe.with_coordinates(SaColorSpace.Coordinates.OKLAB).with_depth(SaColorSpace.Depth.F16)
    assert_eq(SaStatusLine.space_text(in_oklab), "Oklab over Adobe RGB, F16", "and in Oklab says so")
    var odd := SaColorSpace.create(
        SaColorSpace.ID_CUSTOM,
        PackedVector2Array([Vector2(0.5, 0.3), Vector2(0.3, 0.5), Vector2(0.2, 0.1)]),
        SaColorSpace.WHITE_D65,
        SaTransferFunction.srgb()
    )
    assert_eq(SaStatusLine.space_text(odd), "Custom, F32", "A gamut nobody names is Custom")
    assert_eq(SaStatusLine.space_text(SaColorSpace.oklab_p3()), "Oklab over Display P3, F32", "A preset keeps its own name")


func test_a_surface_that_answers_nothing_leaves_the_line_empty() -> void:
    var empty := SaStatusLine.new(func() -> SaSurface: return null)
    _host.add_child(empty)
    empty.refresh()

    assert_eq(empty.zoom_label.text, "", "No view, no zoom")
    assert_eq(empty.pixels_label.text, "", "and no pixels")
    assert_eq(empty.size_label.text, "", "no document, no size")
    assert_eq(empty.space_label.text, "", "and no space")


## File > Open can hand the canvas a different view, and the line follows the
## one its surface answers now rather than the one it first saw.
func test_following_again_moves_the_line_to_the_surfaces_view_now() -> void:
    var first := _surface.view
    _surface.view = SaTestFixtures.FakeView.new()
    _line.follow()
    _line.refresh()

    first.set_zoom(4.0)
    assert_false(_line._queued, "The view it left no longer queues a reading")
    _surface.view.set_zoom(0.6)
    assert_true(_line._queued, "and the one it follows does")
    _line.refresh()
    assert_eq(_line.pixels_label.text, "Screen 60%", "and is the one read")


func test_the_line_is_a_cover_along_the_bottom_edge_24_units_high() -> void:
    assert_true(_line.is_in_group(SaCanvasView.COVER_GROUP), "The line is in the group Fit reads its covers from")
    assert_eq(_line.anchor_top, 1.0, "It hangs from the bottom edge")
    assert_eq(_line.anchor_left, 0.0, "across the whole width")
    assert_eq(_line.anchor_right, 1.0, "to the right edge")
    assert_almost_eq(_line.custom_minimum_size.y, float(SaStatusLine.HEIGHT), 1e-6, "and is 24 units high at the least")
    assert_eq(SaStatusLine.HEIGHT, 24, "which is the height the line is designed for")
    assert_true(_line.zoom_label.tooltip_text.length() > 0, "Each word says what it is when the pointer rests on it")
    assert_true(_line.pixels_label.tooltip_text.contains("one pixel of the screen"), "the Screen figure as well")
    assert_eq(_line.zoom_label.mouse_filter, Control.MOUSE_FILTER_PASS, "which a label ignoring the mouse could not")
