## New from Clipboard opens the copied picture as a new document.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The desktop clipboard is the seam `SaNewFromClipboard.desktop_picture`,
## because a run on a desktop would read whatever was copied there last. Each case sets it to a picture or to nothing.
## What the real `wl-copy` and the File menu do is the scenario's to show.
extends "res://tests/test_framework.gd"

## Real uploads into real chunks.
const REQUIRES_GPU := true

const CANVAS := Vector2i(512, 256)

## A size no preset has, an odd one.
const ODD_SIZE := Vector2i(1237, 811)

## A region off the chunk grid, so the new document has to move it to its origin.
const REGION := Rect2i(37, 21, 150, 90)

var _kept_reader: Callable = Callable()
var _host: Node = null
var _easel: SaEasel = null
## Sara's own clipboard, which the open documents share, made for each case.
var _held: SaClipboard = null


func before_each() -> void:
    _kept_reader = SaNewFromClipboard.desktop_picture
    _host = Node.new()
    _host.name = "U273Host"
    EventBus.add_child(_host)
    SaMessage.install(_host)
    _easel = SaEasel.create_default(CANVAS)
    _held = SaClipboard.new()


func after_each() -> void:
    SaNewFromClipboard.desktop_picture = _kept_reader
    if _easel != null and is_instance_valid(_easel):
        _easel.free()
    if _host != null and is_instance_valid(_host):
        _host.free()
    _easel = null
    _host = null
    _held = null


func _desktop_holds(picture: SaDesktopPicture, calls: Array = []) -> void:
    SaNewFromClipboard.desktop_picture = func() -> SaDesktopPicture:
        calls.append(true)
        return picture


func _texel(layer: SaLayer, x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var texture := layer.get_field(Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE))
    if texture == null:
        return Color(0.0, 0.0, 0.0, 0.0)
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(texture)
    return image.get_pixel(x % SaChunk.SIZE, y % SaChunk.SIZE)


func _notice_says() -> String:
    var notice := SaMessage.notice_widget()
    return notice.label.text if notice != null and notice.showing() else ""


func _layers(document: SaDocument) -> Array[SaLayer]:
    return SaLayerOps.new(document).layers()


## A picture of a size no preset has becomes a document of that size, with the
## picture its one layer under the picture's name, and nothing to undo.
func test_a_desktop_picture_becomes_a_document_of_its_size() -> void:
    var image := Image.create_empty(ODD_SIZE.x, ODD_SIZE.y, false, Image.FORMAT_RGBA8)
    image.fill(Color(1.0, 0.0, 0.0, 1.0))
    image.fill_rect(Rect2i(Vector2i(1200, 800), Vector2i(37, 11)), Color(0.0, 0.0, 1.0, 1.0))
    _desktop_holds(SaDesktopPicture.new(image, "the engine", null, "a reference"))
    var document := _easel.document
    var source := SaNewFromClipboard.read(document, _held)
    assert_not_null(source, "The clipboard holds a picture")
    var layer := source.make(document)
    assert_not_null(layer, "The document was made")
    assert_eq(document.canvas_size, ODD_SIZE, "at the picture's size")
    assert_eq(_layers(document).size(), 1, "with the picture its one layer")
    assert_eq(str(layer.name), "a reference", "named after the picture")
    assert_almost_eq(_texel(layer, 4, 4).r, 1.0, 1e-3, "holding the picture")
    assert_almost_eq(_texel(layer, 1236, 810).b, 1.0, 1e-3, "to its far corner")
    assert_false(document.undo_redo.has_undo(), "and nothing to undo")
    assert_true(document.modified, "Unsaved, so Save asks where")


## A region copied in Sara becomes a document of the region's size holding it,
## and the desktop is not asked.
func test_a_region_copied_in_sara_becomes_a_document_of_its_size() -> void:
    var document := _easel.document
    var painted := SaLayerOps.new(document).add()
    painted.fill(Color(0.0, 1.0, 0.0, 1.0))
    document.set_active_layer(painted)
    document.selection.select_rect(REGION)
    assert_true(_held.copy(document, painted) > 0, "Copy took something")
    var calls: Array = []
    _desktop_holds(null, calls)
    var source := SaNewFromClipboard.read(document, _held)
    assert_not_null(source, "Sara's clipboard holds a picture")
    var layer := source.make(document)
    assert_not_null(layer, "The document was made")
    assert_eq(document.canvas_size, REGION.size, "at the region's size")
    assert_eq(_layers(document).size(), 1, "with the region its one layer")
    assert_almost_eq(_texel(layer, 0, 0).g, 1.0, 1e-3, "holding the region from its corner")
    assert_almost_eq(_texel(layer, REGION.size.x - 1, REGION.size.y - 1).a, 1.0, 1e-3, "to its far corner")
    assert_almost_eq(_texel(layer, REGION.size.x, 0).a, 0.0, 1e-3, "and nothing past it")
    assert_true(calls.is_empty(), "The desktop clipboard was not read")
    assert_false(document.undo_redo.has_undo(), "and nothing to undo")


## With nothing on either clipboard nothing is made and the corner says why.
func test_nothing_on_either_clipboard_opens_nothing_and_says_so() -> void:
    _desktop_holds(null)
    var document := _easel.document
    var before := document.get_child_count()
    var size := document.canvas_size
    assert_null(SaNewFromClipboard.read(document, _held), "Nothing to make a document from")
    assert_eq(document.get_child_count(), before, "The document is as it was")
    assert_eq(document.canvas_size, size, "at its own size")
    assert_eq(_notice_says(), SaNewFromClipboard.NO_PICTURE, "and the corner says the clipboard holds no picture")


## An empty picture is no picture, as Paste already judges one under Wayland.
func test_an_empty_desktop_picture_is_no_picture() -> void:
    _desktop_holds(SaDesktopPicture.new(Image.new(), "the engine"))
    assert_null(SaNewFromClipboard.read(_easel.document, _held), "An empty picture makes nothing")
    assert_eq(_notice_says(), SaNewFromClipboard.NO_PICTURE, "and the corner says so")


## The row stands under New in the File menu's commands, and the search finds it.
func test_the_command_is_registered_for_the_file_menu() -> void:
    var titles: Array[String] = []
    for command: SaCommandDescriptor in SaMenuCommands.new(Callable(), Callable(), Callable(), Callable()).commands():
        titles.append(String(command.id))
    var at := titles.find("file_new_from_clipboard")
    assert_true(at > 0, "New from Clipboard is a command")
    assert_eq(titles[at - 1], "file_new", "right after New")
