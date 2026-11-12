## A picture pasted onto the reference board arrives fitted to the board.
##
## A 256 pixel picture once landed on a board 137 pixels tall, at y -72, so
## half of it showed. Built outside the tree as the paste suite builds the docker, with the clipboard behind the seam
## `ReferencePaste.desktop_picture`.
extends "res://tests/test_framework.gd"

const VIEW := Vector2(300, 137)

var _kept_reader: Callable
var _host: Node = null
var _written: PackedStringArray = PackedStringArray()


func before_each() -> void:
    _kept_reader = ReferencePaste.desktop_picture
    _host = Node.new()
    _host.name = "ReferencePasteHost"
    EventBus.add_child(_host)
    SaMessage.install(_host)
    _written.clear()


func after_each() -> void:
    ReferencePaste.desktop_picture = _kept_reader
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    for path in _written:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


func _docker() -> ReferenceDocker:
    var docker := ReferenceDocker.new()
    docker.board_view.size = VIEW
    return docker


func _holds(side: Vector2i) -> void:
    var image := Image.create_empty(side.x, side.y, false, Image.FORMAT_RGBA8)
    image.fill(Color(0.8, 0.3, 0.2, 1.0))
    var picture := SaDesktopPicture.new(image, "wl-paste")
    ReferencePaste.desktop_picture = func() -> SaDesktopPicture: return picture


func _inside(rect: Rect2, room: Vector2) -> bool:
    var grown := Rect2(Vector2(-0.5, -0.5), room + Vector2.ONE)
    return grown.encloses(rect)


## The finding itself: a 256 pixel picture pasted by the key onto a view 137
## pixels tall is drawn whole inside the view, at a zoom no higher than 1.0.
func test_a_picture_taller_than_the_view_is_shown_whole() -> void:
    _holds(Vector2i(256, 256))
    var docker := _docker()
    var placed := docker.paste_at(VIEW / 2.0)
    assert_not_null(placed, "The paste placed a picture")
    _written.append(placed.path)
    var board := docker.board()
    var drawn := board.view_rect(placed)
    assert_true(_inside(drawn, VIEW), "its whole rectangle is inside the view, drawn at %s" % [drawn])
    assert_true(board.zoom < 1.0, "the board zoomed out to show it")
    assert_true(board.zoom <= 1.0, "and never above 1.0")
    docker.free()


## The right click's row on a board zoomed out already: a picture that fits
## the view at that zoom is not refitted either.
func test_a_large_picture_that_fits_at_the_boards_zoom_leaves_it_alone() -> void:
    _holds(Vector2i(256, 256))
    var docker := _docker()
    var board := docker.board()
    board.zoom = 0.25
    var placed := docker.paste_at(Vector2(150, 70))
    assert_not_null(placed, "The paste placed a picture")
    _written.append(placed.path)
    assert_almost_eq(board.zoom, 0.25, 0.0001, "the zoom is left alone")
    var centre := board.to_view(placed.rect.get_center())
    assert_almost_eq(centre.x, 150.0, 0.5, "centred at the point across")
    assert_almost_eq(centre.y, 70.0, 0.5, "and down")
    docker.free()


## A small picture pasted by the right click's row lands centred at the click
## and the board's zoom and offset are as they were.
func test_a_small_picture_by_the_right_click_lands_at_the_point_and_keeps_the_zoom() -> void:
    _holds(Vector2i(40, 30))
    var docker := _docker()
    var view := docker.board_view
    var board := docker.board()
    var zoom_before := board.zoom
    var offset_before := board.offset
    assert_true(view.fill_menu(null, Vector2(60, 50)), "The empty board opens the menu")
    assert_true(view.menu.press_row(ReferencePictureView.PASTE), "and Paste takes")
    assert_eq(board.pictures.size(), 1, "one picture is on the board")
    var placed := board.pictures[0]
    _written.append(placed.path)
    var centre := board.to_view(placed.rect.get_center())
    assert_almost_eq(centre.x, 60.0, 0.5, "its centre at the click across")
    assert_almost_eq(centre.y, 50.0, 0.5, "and down")
    assert_almost_eq(board.zoom, zoom_before, 0.0001, "the zoom unchanged")
    assert_eq(board.offset, offset_before, "and the view not moved")
    docker.free()
