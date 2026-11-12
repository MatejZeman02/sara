## The Reference docker: a board of pictures with its own view, a
## drag that moves one, a normalise, boards under tabs, a click that takes a
## colour off a picture, and the board saved with the document as paths and
## rectangles.
##
## The docker is built but never added to the SceneTree, because adding a
## `Window` to the tree in a headless test hangs. Its
## own `_ready` is what needs a tree, and nothing under test here does: the
## view is two numbers, a drag is three events, and a sample reads an `Image`.
##
## What a capture proves instead is that the board is on screen at all and
## comes back after a save, which is `scenarios/the-reference-board.json`.
extends "res://tests/test_framework.gd"

const REFERENCE_IMAGE := "res://ui/icon.png"
const SECOND_IMAGE := "res://ui/icon-bw.png"
const GRADIENT := "res://tests/data/import_gradient.png"


## A docker with a picture area of a known size, since a Control outside a tree
## has none and every view number is measured against it.
func _docker(room: Vector2 = Vector2(200, 200)) -> ReferenceDocker:
    var docker := ReferenceDocker.new()
    docker.board_view.size = room
    return docker


func _press(docker: ReferenceDocker, at: Vector2, pressed: bool, alt: bool = false, shift: bool = false) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = at
    event.alt_pressed = alt
    event.shift_pressed = shift
    docker.board_view.input(event)


func _move(docker: ReferenceDocker, at: Vector2) -> void:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    docker.board_view.input(event)


func test_the_docker_is_registered_like_every_other_builtin() -> void:
    var source := FileAccess.get_file_as_string("res://ui/main/sa_builtin_dockers.gd")
    assert_true(source.contains('[SaDockerIds.REFERENCE, "Reference"'), "The docker is in the built-in list")
    assert_true(source.contains('&"docker_reference"'), "with the action name its toggle is bound to")

    var chords: Array = SaAppCommands.DOCKER_COMMANDS
    var named := false
    for row: Array in chords:
        if String(row[0]) == "docker_reference":
            named = true
            assert_eq(String(row[1]), "ReferenceDocker", "and the command points at the registered id")
    assert_true(named, "The chord is in SaAppCommands with the other dockers that shipped without one")


## The two Preferences rows are declared on the option layer, so the
## Reference page draws them, and neither is drawn by hand.
func test_the_two_preferences_rows_are_declared_not_drawn() -> void:
    var docker := _docker()
    var keys: Array = []
    for spec: Dictionary in SaSettings.docker_options("ReferenceDocker"):
        keys.append(spec["key"])
    assert_true(keys.has(ReferenceDocker.OPTION_STORE), "Where a board is kept is a row, got %s" % [keys])
    assert_true(keys.has(ReferenceDocker.OPTION_NORMALISE), "and what Normalise makes the same is the other")
    assert_eq(
        String(SaSettings.get_docker_option("ReferenceDocker", ReferenceDocker.OPTION_STORE)),
        "document",
        "The document is the default"
    )
    assert_eq(
        String(SaSettings.get_docker_option("ReferenceDocker", ReferenceDocker.OPTION_NORMALISE)), "height", "and one height is"
    )
    docker.free()


## Fit shows the whole board centred, and never magnifies: a small reference
## blown up to fill the docker is a blurred one, and the wheel is there for a
## painter who wants that.
func test_fit_shows_the_whole_board_and_never_magnifies() -> void:
    var docker := _docker(Vector2(200, 100))
    assert_true(docker.load_image(REFERENCE_IMAGE), "The reference loads")
    var report := docker.report()
    assert_eq(report["boards"][0]["pictures"][0]["rect"], [0.0, 0.0, 1024.0, 1024.0], "1024 square at the origin")

    # 100 / 1024 is the tighter of the two, and the picture is centred across
    # the width it does not need.
    assert_almost_eq(docker.board().zoom, 100.0 / 1024.0, 1e-6, "Fit takes the smaller ratio")
    assert_almost_eq(docker.board().offset.x, (200.0 - 100.0) * 0.5, 0.5, "and centres what is left over")
    assert_almost_eq(docker.board().offset.y, 0.0, 0.5, "with nothing left over the other way")

    var wide := _docker(Vector2(4000, 4000))
    wide.load_image(REFERENCE_IMAGE)
    assert_almost_eq(wide.board().zoom, 1.0, 1e-6, "A docker larger than the picture stops at 1x rather than blurring it")
    docker.free()
    wide.free()


## A second picture lands to the right of the first rather than on top of it,
## and a fit shows both.
func test_several_pictures_land_beside_each_other() -> void:
    var docker := _docker(Vector2(400, 200))
    docker.open_paths(PackedStringArray([REFERENCE_IMAGE, SECOND_IMAGE, GRADIENT]))
    var board := docker.board()
    assert_eq(board.pictures.size(), 3, "Three pictures on one board")
    assert_true(board.pictures[1].rect.position.x >= board.pictures[0].rect.end.x, "the second right of the first")
    assert_true(board.pictures[2].rect.position.x >= board.pictures[1].rect.end.x, "and the third right of that")
    var bounds := board.bounds()
    assert_almost_eq(board.zoom, minf(400.0 / bounds.size.x, 200.0 / bounds.size.y), 1e-6, "Fit shows all three")
    docker.free()


## Zoom keeps the board point under the pointer under the pointer, which is
## the rule the canvas's own wheel follows and the reason the offset moves
## with it.
func test_zoom_holds_the_point_it_is_asked_about() -> void:
    var docker := _docker()
    docker.load_image(REFERENCE_IMAGE)
    var at := Vector2(60.0, 80.0)
    var before := docker.board_view.texel_at(at)
    docker.board_view.zoom_about(at, 4.0)
    assert_eq(docker.board_view.texel_at(at), before, "The same texel is under the point after a 4x zoom")
    docker.board_view.zoom_about(at, 0.25)
    assert_eq(docker.board_view.texel_at(at), before, "and after zooming back out")

    docker.board_view.zoom_about(at, 1e6)
    assert_true(docker.board().zoom <= SaReferenceBoard.MAX_ZOOM, "The zoom stops at its ceiling, %f" % docker.board().zoom)
    docker.board_view.zoom_about(at, 1e-6)
    assert_true(docker.board().zoom >= SaReferenceBoard.MIN_ZOOM, "and at its floor, %f" % docker.board().zoom)
    docker.free()


## A pan moves the board and nothing else. The canvas view is not asked about
## and not written, which is the whole of "its own zoom and pan".
func test_a_pan_moves_the_board_and_leaves_the_texel_map_consistent() -> void:
    var docker := _docker()
    docker.load_image(REFERENCE_IMAGE)
    var at := Vector2(100.0, 100.0)
    var texel := docker.board_view.texel_at(at)
    docker.board_view.pan_by(Vector2(30.0, -20.0))
    assert_eq(docker.board_view.texel_at(at + Vector2(30.0, -20.0)), texel, "The texel moved with the board")
    docker.free()


## A left drag on a picture moves it in board units, raises it to the top,
## and selects it. A Shift drag over the empty board pans instead, the plain
## drag there being the selection's box.
func test_a_drag_moves_the_picture_under_it() -> void:
    var docker := _docker(Vector2(400, 200))
    docker.open_paths(PackedStringArray([REFERENCE_IMAGE, SECOND_IMAGE]))
    var board := docker.board()
    var first := board.pictures[0]
    var second := board.pictures[1]
    var was := first.rect.position
    var from := board.view_rect(first).get_center()
    var offset_before := board.offset

    _press(docker, from, true)
    _move(docker, from + Vector2(20.0, 10.0))
    _move(docker, from + Vector2(40.0, 20.0))
    _press(docker, from + Vector2(40.0, 20.0), false)

    var moved := first.rect.position - was
    assert_almost_eq(moved.x, 40.0 / board.zoom, 1e-3, "Moved right by the drag in board units")
    assert_almost_eq(moved.y, 20.0 / board.zoom, 1e-3, "and down")
    assert_eq(board.pictures[1], first, "The dragged picture is on top now")
    assert_eq(board.pictures[0], second, "and the other under it")
    assert_true(docker.report()["boards"][0]["pictures"][1]["selected"], "and it is the selected one")
    assert_eq(board.offset, offset_before, "The view did not move")

    var empty := Vector2(1.0, 199.0)
    assert_null(board.picture_at(board.to_board(empty)), "The corner is empty board")
    _press(docker, empty, true, false, true)
    _move(docker, empty + Vector2(5.0, 5.0))
    _move(docker, empty + Vector2(15.0, 5.0))
    _press(docker, empty + Vector2(15.0, 5.0), false, false, true)
    assert_almost_eq(board.offset.x, offset_before.x + 15.0, 1e-3, "A Shift drag on the empty board pans")
    docker.free()


## Normalise brings every picture to one height in a row, left to right in the
## order they stood, and the other two readings are the same row measured by
## width or by area.
func test_normalise_is_one_height_in_a_row_by_default() -> void:
    var docker := _docker(Vector2(400, 200))
    docker.open_paths(PackedStringArray([GRADIENT, REFERENCE_IMAGE]))
    var board := docker.board()
    var gradient := board.pictures[0]
    var square := board.pictures[1]
    assert_true(
        gradient.rect.size.y != square.rect.size.y,
        "Two pictures of different heights, %s and %s" % [gradient.rect.size, square.rect.size]
    )
    board.move(square, Vector2(-5000.0, 0.0))

    docker.normalise()
    assert_almost_eq(gradient.rect.size.y, SaReferenceBoard.NORMAL_HEIGHT, 1e-3, "One height")
    assert_almost_eq(square.rect.size.y, SaReferenceBoard.NORMAL_HEIGHT, 1e-3, "for both")
    assert_almost_eq(square.rect.position.x, 0.0, 1e-3, "The one that stood left is first")
    assert_almost_eq(
        gradient.rect.position.x, square.rect.end.x + SaReferenceBoard.NORMAL_GAP, 1e-3, "and the other a gap after it"
    )
    var aspect := float(gradient.image.get_width()) / float(gradient.image.get_height())
    assert_almost_eq(gradient.rect.size.x / gradient.rect.size.y, aspect, 1e-3, "Proportions are kept")

    board.normalise("width")
    assert_almost_eq(gradient.rect.size.x, square.rect.size.x, 1e-3, "The width reading is one width")
    board.normalise("area")
    assert_almost_eq(
        gradient.rect.size.x * gradient.rect.size.y, square.rect.size.x * square.rect.size.y, 1.0, "and the area reading one area"
    )
    docker.free()


## A board per subject, each a tab: adding, selecting, renaming and closing,
## and the last board is emptied rather than removed.
func test_boards_are_tabs() -> void:
    var docker := _docker()
    docker.load_image(REFERENCE_IMAGE)
    var second := docker.add_board("The mug")
    assert_eq(second, 1, "The second board is the second tab")
    assert_eq(docker._tabs.bar.tab_count, 2, "and the bar shows two")
    assert_eq(docker._tabs.bar.get_tab_title(1), "The mug", "named as asked")
    assert_eq(docker.board().pictures.size(), 0, "and empty")
    docker.load_image(SECOND_IMAGE)
    docker.select_board(0)
    assert_eq(String(docker.board().pictures[0].path), REFERENCE_IMAGE, "The first board still has its picture")
    docker.rename_board(0, "The character")
    assert_eq(docker._tabs.bar.get_tab_title(0), "The character", "Renamed")
    docker.close_board(0)
    assert_eq(docker._boards.size(), 1, "Closed")
    assert_eq(String(docker.board().pictures[0].path), SECOND_IMAGE, "and the mug's board is what is left")
    docker.close_board(0)
    assert_eq(docker._boards.size(), 1, "The last board stays")
    assert_eq(docker.board().pictures.size(), 0, "emptied")
    docker.free()


## A click takes the colour under it and puts it on the wheel through
## `EventBus.color_picked`, which is the one door the colour store listens at,
## so the reference is not a second writer of the foreground. A press that
## lifts where it landed is the click, and a drag is not.
func test_a_sample_goes_out_through_the_one_colour_door() -> void:
    var docker := _docker()
    docker.load_image(REFERENCE_IMAGE)
    var heard: Array[Color] = []
    var listener := func(color: Color) -> void: heard.append(color)
    EventBus.color_picked.connect(listener)

    var at := Vector2(100.0, 100.0)
    assert_true(docker.sample_at(at), "A point on the picture is a sample")
    assert_eq(heard.size(), 1, "announced once")
    var report := docker.report()
    assert_eq(
        [heard[0].r, heard[0].g, heard[0].b, heard[0].a],
        report["sampled_display"],
        "and what went out is what the dump says went out"
    )

    _press(docker, at, true)
    _press(docker, at, false)
    assert_eq(heard.size(), 2, "A click that does not wander samples on the lift")
    _press(docker, at, true)
    _move(docker, at + Vector2(30.0, 0.0))
    _press(docker, at + Vector2(30.0, 0.0), false)
    assert_eq(heard.size(), 2, "and a drag does not")
    _press(docker, at, true, true)
    _move(docker, at + Vector2(3.0, 0.0))
    _press(docker, at + Vector2(3.0, 0.0), false)
    assert_eq(heard.size(), 4, "Alt samples on the press and as it goes")

    var off := docker.board_view.texel_at(Vector2(-40.0, -40.0))
    assert_eq(off, Vector2i(-1, -1), "A point beside the picture is not a texel")
    assert_false(docker.sample_at(Vector2(-40.0, -40.0)), "so it is not a sample either")
    assert_eq(heard.size(), 4, "and nothing more was announced")

    EventBus.color_picked.disconnect(listener)
    docker.free()


## A PNG's texel is already a display colour and passes through. An EXR's is
## linear and has to be encoded, or a mid grey lands at 0.214 where it belongs
## at 0.5, which is the bug `SaImageImport.space_for` exists to name.
func test_the_source_space_decides_whether_a_texel_is_converted() -> void:
    var docker := _docker()
    docker.load_image(REFERENCE_IMAGE)
    var space := docker.board().pictures[0].source_space
    assert_eq(String(space.id), "srgb", "A PNG arrives in sRGB")

    var grey := Color(0.5, 0.5, 0.5, 1.0)
    assert_almost_eq(space.to_display(grey).r, 0.5, 1e-4, "so a mid grey passes through")
    var linear := SaColorSpace.linear_srgb()
    assert_true(
        linear.to_display(grey).r > 0.7, "where the same value in a linear source is encoded to %f" % linear.to_display(grey).r
    )
    docker.free()


## The board goes to disk as paths and rectangles and comes back the same, a
## path that is gone comes back as a placeholder in its rectangle, and no
## board at all is an empty docker.
func test_the_board_is_paths_and_rectangles_and_comes_back() -> void:
    var docker := _docker(Vector2(400, 200))
    docker.open_paths(PackedStringArray([REFERENCE_IMAGE, SECOND_IMAGE]))
    docker.add_board("The mug")
    docker.load_image(GRADIENT)
    docker.board().move(docker.board().pictures[0], Vector2(100.0, 50.0))
    var header := docker.to_header()
    assert_eq(header.size(), 2, "Two boards")
    assert_eq(header[1]["pictures"][0]["rect"], [100.0, 50.0, 300.0, 200.0], "with the moved rectangle, %s" % [header[1]])
    var text := JSON.stringify(header)
    assert_false(text.contains("image"), "and nothing but paths and rectangles in it")

    var back := _docker(Vector2(400, 200))
    back.restore(JSON.parse_string(text))
    assert_eq(back._boards.size(), 2, "Both boards come back")
    assert_eq(back._boards[1].name, "The mug", "by name")
    assert_eq(back._boards[1].pictures[0].rect, Rect2(100.0, 50.0, 300.0, 200.0), "in their rectangles")
    assert_false(back._boards[1].pictures[0].is_missing(), "with the picture")

    var gone := SaReferenceBoard.from_header(
        {"name": "Gone", "pictures": [{"path": "/nowhere/at/all.png", "rect": [10.0, 20.0, 300.0, 200.0]}]}
    )
    assert_eq(gone.pictures.size(), 1, "A path that is gone keeps its slot")
    assert_true(gone.pictures[0].is_missing(), "as a placeholder")
    assert_eq(gone.pictures[0].rect, Rect2(10.0, 20.0, 300.0, 200.0), "in its rectangle")

    back.restore([])
    assert_eq(back._boards.size(), 0, "No board is an empty docker")
    assert_false(bool(back.report()["loaded"]), "with nothing loaded")
    docker.free()
    back.free()


## The `.sad` carries the boards under a key an older Sara ignores, and a file
## without the key opens with none.
func test_the_sad_carries_the_boards_as_an_additive_key() -> void:
    var document := SaDocument.new()
    document.setup_default_document(Vector2i(64, 64), SaCompositor.new())
    document.reference_boards = [
        {"name": "B", "zoom": 1.0, "offset": [0, 0], "pictures": [{"path": REFERENCE_IMAGE, "rect": [0, 0, 8, 8]}]}
    ]
    var path := SaDataRoot.path("f3_board_test.sad")
    assert_eq(SaExport.save_sad(document, path, 0), OK, "Saved")
    var read := SaDocument.new()
    read.reference_boards = [{"stale": true}]
    assert_eq(SaExport.load_sad(read, path, SaCompositor.new()), OK, "and read back")
    assert_eq(read.reference_boards.size(), 1, "with the board")
    assert_eq(String(read.reference_boards[0]["name"]), "B", "by name")

    var plain := SaDocument.new()
    plain.setup_default_document(Vector2i(64, 64), SaCompositor.new())
    assert_eq(SaExport.save_sad(plain, path, 0), OK, "A document with no board saves")
    assert_eq(SaExport.load_sad(read, path), OK, "and opens")
    assert_true(read.reference_boards.is_empty(), "with none, rather than the previous document's")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    document.free()
    read.free()
    plain.free()


## Clearing forgets every board, so a docker left open on files that have
## moved is not a docker showing something that is no longer there.
func test_clearing_forgets_the_boards() -> void:
    var docker := _docker()
    docker.load_image(REFERENCE_IMAGE)
    assert_true(bool(docker.report()["loaded"]), "Loaded")
    docker.clear()
    var report := docker.report()
    assert_false(bool(report["loaded"]), "and gone")
    assert_eq((report["boards"] as Array).size(), 0, "with no board left")
    assert_eq(docker.board_view.texel_at(Vector2(10.0, 10.0)), Vector2i(-1, -1), "and nothing left to sample")
    docker.free()


## A path that is not an image is a reported problem and a docker that keeps
## showing whatever it had, rather than a blank one and no reason.
func test_an_unreadable_path_changes_nothing() -> void:
    var docker := _docker()
    docker.load_image(REFERENCE_IMAGE)
    # The loader reports through SaProblems, which pushes an engine error, and a
    # deliberate push_error fails a run. The announcement is turned off for the
    # one call rather than the reporting, so the refusal is still the refusal.
    var was := SaProblems.announce
    SaProblems.announce = false
    assert_false(
        docker.load_image("res://ui/dockers/reference/reference_docker.gd"), "A resource that is not an image is refused"
    )
    SaProblems.announce = was
    assert_eq(docker.board().pictures.size(), 1, "and what was showing is still showing")
    docker.free()
