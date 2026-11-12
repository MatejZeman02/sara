## The reference beside the canvas, both graphs, and the four per-picture
## toggles.
##
## The docker is built but never added to the SceneTree, the way the other
## Reference suites build it, because a `Window` in the tree hangs a headless run. What needs
## the tree, the compare pane bound to the canvas and the Graph docker finding
## the selected reference, is proved on the running app by
## `scenarios/the-reference-beside-the-canvas-and-both-graphs.json`. What
## is proved here is the model, the gesture and the second plot.
extends "res://tests/test_framework.gd"

const REFERENCE_IMAGE := "res://ui/icon.png"
const GRADIENT := "res://tests/data/import_gradient.png"

## The second plot dispatches for real.
const REQUIRES_GPU := true


func _docker(room: Vector2 = Vector2(200, 200)) -> ReferenceDocker:
    var docker := ReferenceDocker.new()
    docker.board_view.size = room
    return docker


func _press(docker: ReferenceDocker, at: Vector2, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = at
    docker.board_view.input(event)


func _move(docker: ReferenceDocker, at: Vector2) -> void:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    docker.board_view.input(event)


# --- The four toggles on the model -------------------------------------------


## A flip mirrors the texel under a point, so a sample off a flipped picture
## is the colour the painter sees there.
func test_a_flip_mirrors_the_texel_under_a_point() -> void:
    var board := SaReferenceBoard.new()
    var picture := board.add_path(REFERENCE_IMAGE)
    var width := picture.image.get_width()
    var near_left := picture.rect.position + Vector2(0.5, 0.5)
    assert_eq(picture.texel_at(near_left), Vector2i(0, 0), "Unflipped, the left edge is texel 0")
    picture.flip_h = true
    assert_eq(picture.texel_at(near_left).x, width - 1, "Flipped, the left edge is the last texel")
    assert_eq(picture.texel_at(near_left).y, 0, "and the row is unchanged")


## A crop shows only the rectangle kept, drawn where those texels were, and
## clearing it brings the whole picture back to where it stood.
func test_a_crop_cuts_the_paper_and_clearing_it_puts_it_back() -> void:
    var board := SaReferenceBoard.new()
    var picture := board.add_path(REFERENCE_IMAGE)
    var whole := picture.rect
    var size := picture.image.get_size()
    var kept := Rect2i(Vector2i(10, 20), Vector2i(30, 40))
    picture.set_crop(kept)
    assert_eq(picture.crop, kept, "The crop is the rectangle asked for")
    assert_eq(picture.region(), kept, "and the region drawn is it")
    assert_eq(picture.rect.position, whole.position + Vector2(10.0, 20.0), "drawn where those texels were")
    assert_eq(picture.rect.size, Vector2(30.0, 40.0), "at the size they were")
    assert_eq(
        picture.texel_at(picture.rect.position + Vector2(0.5, 0.5)),
        Vector2i(10, 20),
        "The first texel shown is the crop's corner"
    )
    assert_eq(picture.texel_at(whole.position + Vector2(0.5, 0.5)), Vector2i(-1, -1), "and what was cut is off the picture")

    picture.set_crop(Rect2i())
    assert_eq(picture.crop, Rect2i(), "Cleared")
    assert_eq(picture.rect, whole, "and the whole picture is back where it stood")
    assert_eq(picture.region(), Rect2i(Vector2i.ZERO, size), "showing all of it")


## A picture kept on top is drawn last and found first, whatever a raise did
## to the rest, and taking it off the top puts it back in its place.
func test_always_on_top_draws_last_and_is_found_first() -> void:
    var board := SaReferenceBoard.new()
    var first := board.add_path(REFERENCE_IMAGE)
    var second := board.add_path(REFERENCE_IMAGE)
    board.move(second, first.rect.position - second.rect.position)
    assert_eq(board.picture_at(first.rect.get_center()), second, "The later picture is over the earlier one")
    first.on_top = true
    assert_eq(board.ordered()[-1], first, "On top, the first is drawn last")
    assert_eq(board.picture_at(first.rect.get_center()), first, "and is the one a click finds")
    board.raise(second)
    assert_eq(board.picture_at(first.rect.get_center()), first, "A raise of the other does not get past it")
    first.on_top = false
    assert_eq(board.picture_at(first.rect.get_center()), second, "and off the top it falls back under")


## The four flags go into the header and come back, and a picture with none
## of them writes the plain header.
func test_the_flags_are_saved_with_the_board_and_a_plain_picture_is_unchanged() -> void:
    var board := SaReferenceBoard.new("Flags")
    var plain := board.add_path(REFERENCE_IMAGE)
    var flagged := board.add_path(REFERENCE_IMAGE)
    flagged.flip_h = true
    flagged.greyscale = true
    flagged.on_top = true
    flagged.set_crop(Rect2i(4, 6, 20, 10))
    var header := board.to_header()
    var entries: Array = header["pictures"]
    assert_eq((entries[0] as Dictionary).keys(), ["path", "rect"], "A plain picture's entry is the two plain keys")
    assert_true(bool(entries[1]["flip"]), "The flip is written")
    assert_true(bool(entries[1]["greyscale"]), "and the greyscale")
    assert_true(bool(entries[1]["on_top"]), "and on top")
    assert_eq(entries[1]["crop"], [4, 6, 20, 10], "and the crop, in texels")

    var back := SaReferenceBoard.from_header(header)
    var restored := back.pictures[1]
    assert_true(restored.flip_h and restored.greyscale and restored.on_top, "All three flags come back")
    assert_eq(restored.crop, Rect2i(4, 6, 20, 10), "and the crop")
    assert_eq(restored.rect, flagged.rect, "in the cropped rectangle, not moved a second time")
    assert_false(
        back.pictures[0].flip_h or back.pictures[0].greyscale or back.pictures[0].on_top, "and the plain one stays plain"
    )
    assert_eq(plain.crop, Rect2i(), "with no crop")


## The greyscale is a second texture made once from the image.
func test_greyscale_is_a_second_texture_made_once() -> void:
    var board := SaReferenceBoard.new()
    var picture := board.add_path(REFERENCE_IMAGE)
    assert_eq(picture.shown_texture(), picture.texture, "In colour the picture's own texture is drawn")
    picture.greyscale = true
    var grey := picture.shown_texture()
    assert_true(grey != picture.texture, "Grey is another texture")
    assert_eq(grey.get_size(), picture.texture.get_size(), "of the same size")
    assert_eq(picture.shown_texture(), grey, "made once and kept")


# --- The toggles from the docker ----------------------------------------------


## The hover bar's picture is the one under the pointer, or the selected one
## while the pointer is on the docker, and a toggle lands on it.
func test_the_bar_follows_the_pointer_and_a_toggle_lands_on_its_picture() -> void:
    var docker := _docker()
    docker.open_paths(PackedStringArray([REFERENCE_IMAGE, REFERENCE_IMAGE]))
    var board := docker.board()
    var first := board.pictures[0]
    var second := board.pictures[1]
    docker.board_view.pointer_entered()
    assert_eq(docker.board_view.hover_target(), second, "Opened last, the second is selected and is the bar's")

    _move(docker, board.view_rect(first).get_center())
    assert_eq(docker.board_view.hover_target(), first, "Under the pointer, the first is the bar's")
    docker.board_view.toggle("flip")
    assert_true(first.flip_h, "and the toggle lands on it")
    assert_false(second.flip_h, "not on the selected one")

    docker.board_view.pointer_left()
    docker.board_view.pointer_entered()
    assert_eq(docker.board_view.hover_target(), second, "Off every picture, the selected one is the bar's again")
    docker.board_view.toggle("greyscale")
    docker.board_view.toggle("on_top")
    assert_true(second.greyscale and second.on_top, "and both toggles land on it")
    assert_true(docker.report()["boards"][0]["pictures"][1]["greyscale"], "which the dump says")
    docker.free()


## Crop from the bar is a mode: the next drag on the selected picture is the
## rectangle to keep, and the second press of the button clears the crop.
func test_crop_mode_takes_the_next_drag_as_the_rectangle() -> void:
    var docker := _docker()
    docker.open_paths(PackedStringArray([REFERENCE_IMAGE]))
    var board := docker.board()
    var picture := board.pictures[0]
    var whole := picture.rect
    var before := board.view_rect(picture)

    # The bar is up only with the pointer on the docker, and a hand
    # that presses Crop is there.
    docker.board_view.pointer_entered()
    docker.board_view.toggle("crop")
    assert_true(docker.board_view.crop_mode, "Crop with no crop enters crop mode")
    assert_eq(picture.crop, Rect2i(), "and nothing is cropped yet")

    # A drag over the middle half of the picture, in the picture Control.
    var from := before.position + before.size * 0.25
    var to := before.position + before.size * 0.75
    _press(docker, from, true)
    _move(docker, (from + to) * 0.5)
    assert_true(docker.board_view.crop_in_progress().size.x > 0.0, "The drag draws its rectangle as it goes")
    _move(docker, to)
    _press(docker, to, false)

    assert_false(docker.board_view.crop_mode, "The lift leaves crop mode")
    var size := picture.image.get_size()
    assert_true(picture.crop.size.x > 0 and picture.crop.size.y > 0, "and the picture is cropped")
    assert_almost_eq(float(picture.crop.position.x) / float(size.x), 0.25, 0.05, "to the quarter the drag started at")
    assert_almost_eq(float(picture.crop.size.x) / float(size.x), 0.5, 0.05, "and half the width")
    assert_true(whole.encloses(picture.rect), "and the cropped rectangle lies inside where the picture was")

    docker.board_view.toggle("crop")
    assert_eq(picture.crop, Rect2i(), "Crop again clears it")
    assert_eq(picture.rect, whole, "and the whole picture is back")
    docker.free()


## The compare pane is gone, replaced by the canvas as an element on the board,
## and the docker says so rather than keeping a toggle that
## splits nothing. The element's own proof is
## `ui/dockers/reference/tests/test_the_canvas_is_a_reference_element.gd`.
func test_the_compare_pane_is_gone_and_the_canvas_button_is_there() -> void:
    var docker := _docker()
    assert_false("compare" in docker, "No compare flag on the docker")
    assert_false(docker.report().has("compare"), "and none in the dump")
    assert_not_null(docker.find_child("CanvasButton", true, false), "The Canvas button is on the row")
    assert_null(docker.find_child("CompareButton", true, false), "and the Compare button is not")
    docker.free()


# --- The second plot ------------------------------------------------------------


## A reference uploaded once is a texture the scope bins a sample a texel,
## and the counts are the picture's, so the graph beside the canvas's is the
## reference's own.
func test_the_second_plot_bins_the_uploaded_reference() -> void:
    var image := (ResourceLoader.load(GRADIENT) as Texture2D).get_image()
    var texture := SaGraphPlot.upload_image(image, 128)
    assert_not_null(texture, "The picture uploads")
    assert_true(maxi(texture.size.x, texture.size.y) <= 128, "scaled to the longest side asked for")

    var plot := SaGraphPlot.new()
    var ok := plot.run_over_document(texture, texture.size, SaColorSpace.srgb(), "histogram")
    assert_true(ok, "and a histogram pass runs over it")
    var counts := plot.read_counts()
    var total := 0
    for i in SaGraphPlot.BINS:
        total += counts[i]
    # The picture's alpha runs from 96 to 255, and a
    # sample counts with the chance of its alpha, so the bins add to its alpha.
    @warning_ignore("static_called_on_instance")
    var uploaded := SaExport.get_texture_image_float(texture)
    var weight := 0.0
    for y in uploaded.get_height():
        for x in uploaded.get_width():
            weight += uploaded.get_pixel(x, y).a
    assert_true(
        absf(total - weight) <= weight * 0.02, "Every sample landed in a red bin by its alpha, %d of %.0f" % [total, weight]
    )
    assert_true(plot.read_largest() > 0, "and the largest bin is not empty")
    var filled := 0
    for i in SaGraphPlot.BINS:
        if counts[i] > 0:
            filled += 1
    assert_true(filled >= 64, "A gradient spreads over the scale rather than one bin, %d bins filled" % filled)

    plot = null
    texture = null


## The Graph docker's source is one of the three, the reference's picture
## shows for the two that ask for it, and the dump carries the source and the
## pass count.
func test_the_graph_docker_offers_three_sources() -> void:
    var docker := GraphDocker.new()
    assert_eq(docker.source, "canvas", "The canvas alone to start")
    assert_false(docker._reference_picture.visible, "and no second picture")
    docker.show_source("both")
    assert_true(docker._picture.visible and docker._reference_picture.visible, "Both shows both")
    docker.show_source("reference")
    assert_false(docker._picture.visible, "Reference hides the canvas's")
    assert_true(docker._reference_picture.visible, "and shows the reference's")
    docker.show_source("nothing")
    assert_eq(docker.source, "canvas", "A word nothing knows is the canvas")
    var report := docker.view_report()
    assert_eq(report["source"], "canvas", "which the dump says")
    assert_eq(int(report["reference_passes"]), 0, "with no pass over a reference yet")
    docker.free()
