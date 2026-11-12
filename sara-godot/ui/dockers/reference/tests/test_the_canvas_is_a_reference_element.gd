## The canvas as an element on a reference board.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Compare adds the canvas as a normal element that can also be flipped,
## greyed or cropped. What is here is the model's half of that, which needs no window and no GPU:
## the element is a `Picture` like every other, it saves as a flag and never as
## pixels, and every rectangle answer a crop, a flip and a resize ask of it is
## written against its size rather than against an image it does not have.
##
## The two assertions that matter are `test_the_saved_board_holds_no_image_data`
## and `test_the_element_redraws_on_a_composite_and_not_on_a_frame`, which is the
## one case here that needs a GPU, because a composite is a dispatch. The picture
## of it is `scenarios/the-canvas-is-a-reference-element.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The last case composites a surface, which is a compute dispatch.
const REQUIRES_GPU := true

## A canvas size no shipped picture has, so a rectangle that came from the wrong
## place is visibly wrong rather than accidentally right.
const CANVAS := Vector2i(640, 360)

# --- One element, like every other ---------------------------------------------


## The Canvas button puts one live picture on the board at the canvas's size,
## and a second press answers the same one: two elements would be one texture
## with two rectangles, which says nothing the board's own zoom does not.
func test_the_canvas_is_one_live_picture_and_a_second_add_finds_it() -> void:
    var board := SaReferenceBoard.new()
    var first := board.add_canvas(CANVAS)

    assert_true(first.live, "The element is live")
    assert_eq(first.live_size, CANVAS, "at the canvas's size")
    assert_eq(first.rect.size, Vector2(CANVAS), "and drawn at that size in board units")
    assert_eq(first.path, "", "with no path, because it is not a file")
    assert_false(first.is_missing(), "and it is not a placeholder")

    var second := board.add_canvas(Vector2i(800, 600))
    assert_eq(second, first, "A second add answers the element already there")
    assert_eq(board.pictures.size(), 1, "and the board still has one")
    assert_eq(second.live_size, Vector2i(800, 600), "with the size it was asked for now")


## It goes to the right of what is already on the board, the way an opened
## picture does, so adding it never covers a reference the painter placed.
func test_the_canvas_lands_beside_the_pictures_already_there() -> void:
    var board := SaReferenceBoard.new()
    var placed := board.restore_path("res://no/such/picture.png", Rect2(0.0, 0.0, 300.0, 200.0))
    var live := board.add_canvas(CANVAS)

    assert_true(live.rect.position.x >= placed.rect.end.x, "The element starts right of the picture")
    assert_eq(board.canvas_picture(), live, "and the board finds it as its canvas element")


# --- Saved as itself --------------------------------------------------------------


## The first assertion. The header carries a flag and a rectangle and
## the four toggles, and nothing that could hold a pixel: no image, no texture,
## no base64, and a size a few hundred bytes long whatever the canvas holds.
func test_the_saved_board_holds_no_image_data() -> void:
    var board := SaReferenceBoard.new()
    var live := board.add_canvas(CANVAS)
    live.flip_h = true
    live.greyscale = true
    live.set_crop(Rect2i(40, 20, 320, 180))
    var header := board.to_header()
    var entry: Dictionary = (header["pictures"] as Array)[0]

    assert_true(bool(entry.get("canvas", false)), "The element is written as the canvas")
    assert_eq(String(entry["path"]), "", "with no path")
    for key: String in entry:
        assert_true(
            key in ["path", "rect", "canvas", "flip", "greyscale", "on_top", "crop"],
            "%s is a key a board has always written, not pixels" % key
        )
    var text := JSON.stringify(header)
    assert_true(text.length() < 400, "and the whole board is %d characters, not an image" % text.length())
    assert_false(text.contains("PNG") or text.contains("base64"), "with nothing encoded in it")


## And back: the element is the canvas again, its rectangle and its toggles where
## they were, and its size left for the docker to take from whatever document is
## open, because a board saved beside one painting and opened beside another
## shows the second.
func test_the_board_reopens_with_the_element_still_the_canvas() -> void:
    var board := SaReferenceBoard.new()
    var live := board.add_canvas(CANVAS)
    live.rect = Rect2(12.0, 34.0, 320.0, 180.0)
    live.flip_h = true
    live.on_top = true
    var back := SaReferenceBoard.from_header(board.to_header())
    var element := back.canvas_picture()

    assert_not_null(element, "The reopened board has a canvas element")
    assert_true(element.live, "and it is live, not a picture of the canvas")
    assert_eq(element.rect, Rect2(12.0, 34.0, 320.0, 180.0), "in the rectangle it was saved in")
    assert_true(element.flip_h, "still flipped")
    assert_true(element.on_top, "and still on top")
    assert_eq(element.live_size, Vector2i.ZERO, "with its size waiting for the document the docker binds")


## A board without a canvas element writes exactly what it wrote before this
## unit, so an older Sara reading a newer file sees nothing it does not know.
func test_a_board_without_the_canvas_writes_no_canvas_key() -> void:
    var board := SaReferenceBoard.new()
    board.restore_path("res://no/such/picture.png", Rect2(0.0, 0.0, 100.0, 100.0))
    var entry: Dictionary = (board.to_header()["pictures"] as Array)[0]

    assert_false(entry.has("canvas"), "No canvas key on a plain picture")


# --- The toggles, without an image -----------------------------------------------


## A crop on the element is a crop of the canvas's texels, drawn where those
## texels were, which is the same paper-cutting rule every picture follows.
func test_a_crop_cuts_the_canvas_and_clearing_it_puts_it_back() -> void:
    var board := SaReferenceBoard.new()
    var live := board.add_canvas(CANVAS)
    var whole := live.rect

    live.set_crop(Rect2i(160, 90, 320, 180))
    assert_eq(live.region(), Rect2i(160, 90, 320, 180), "The region is the crop")
    assert_eq(live.rect.size, Vector2(320.0, 180.0), "drawn at the crop's size")
    assert_eq(live.rect.position, whole.position + Vector2(160.0, 90.0), "where those texels were")

    live.set_crop(Rect2i())
    assert_eq(live.region(), Rect2i(Vector2i.ZERO, CANVAS), "Clearing it shows the whole canvas")
    assert_eq(live.rect, whole, "back where it was")


## A flip mirrors the texel under a point, so the hover and the crop drag land on
## the part of the canvas the painter is pointing at.
func test_a_flip_mirrors_the_canvas_texel_under_a_point() -> void:
    var board := SaReferenceBoard.new()
    var live := board.add_canvas(CANVAS)
    var near_left := live.rect.position + Vector2(10.0, 10.0)

    assert_eq(live.texel_at(near_left), Vector2i(10, 10), "Unflipped, the left edge is the left edge")
    live.flip_h = true
    # Ten units in from the left is the left edge of texel 10, and its mirror is
    # the left edge of texel 630 counted from the other side, which is the rule
    # the flip test holds a picture to.
    assert_eq(live.texel_at(near_left), Vector2i(CANVAS.x - 10, 10), "Flipped, it is the right edge")


## The element is not drawn in the board's own pass, because it needs the
## canvas's material, so the pass is handed no texture for it.
func test_the_element_hands_the_board_pass_no_texture() -> void:
    var board := SaReferenceBoard.new()
    var live := board.add_canvas(CANVAS)
    live.greyscale = true

    assert_null(live.shown_texture(), "No texture, grey or not")
    assert_null(live.image, "and no image on the CPU at all")


## With no document behind it the element is a placeholder, the way a missing
## file is, rather than a zero-sized rectangle nobody can grab.
func test_an_element_with_no_canvas_is_a_placeholder() -> void:
    var board := SaReferenceBoard.new()
    var live := board.add_canvas(Vector2i.ZERO)

    assert_true(live.is_missing(), "No canvas size is a placeholder")
    assert_eq(live.rect.size, SaReferenceBoard.PLACEHOLDER_SIZE, "at the placeholder's size")
    assert_eq(live.region(), Rect2i(), "with nothing to show")


# --- Redrawn on a composite, not on a frame --------------------------------------


## The second assertion. Polling the element with nothing composited
## asks for no redraw however many frames pass, and a composite asks for exactly
## one. What is counted is `redraws`, the element's own tally of the redraws it
## asked for, so the claim is about the decision and not about a frame counter.
func test_the_element_redraws_on_a_composite_and_not_on_a_frame() -> void:
    var surface := Fixtures.make_surface(Vector2i(256, 256))
    var element := ReferenceCanvasElement.new()
    var easel := surface.easel

    assert_true(element.refresh_from(easel, null), "The first poll binds the output and draws")
    var after_bind := element.redraws
    for frame in 30:
        element.refresh_from(easel, null)
    assert_eq(element.redraws, after_bind, "Thirty polls with no composite ask for no redraw")

    easel.request_full_composite()
    easel.process_pending_composite()
    assert_true(element.refresh_from(easel, null), "A composite moves the element")
    assert_eq(element.redraws, after_bind + 1, "and asks for exactly one redraw")
    assert_eq(element.drawn_composite, easel.composite_count, "at the composite it saw")

    for frame in 30:
        element.refresh_from(easel, null)
    assert_eq(element.redraws, after_bind + 1, "and thirty more polls still ask for none")

    element.free()
    Fixtures.teardown(surface, null)
