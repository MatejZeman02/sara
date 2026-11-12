## A `.sad` can carry its reference pictures inside it, as a
## Preferences option.
##
## Embedding is an option. A board kept paths only,
## so a painting sent to another machine opened with an empty frame where each
## picture was. With Preferences > Files' "Keep reference pictures inside the
## file" on, which starts off, a save stores each picture's own file bytes beside
## its path, and an open reads them when the path does not resolve.
##
## Built outside the tree as the other Reference suites build the docker. The
## running app's side, a real paste and a real save opened again after both
## originals are deleted, is the scenario of the same subject.
extends "res://tests/test_framework.gd"

const PICTURE := "res://tests/data/import_gradient.png"
const PASTED_SIZE := Vector2i(40, 30)

var _kept_reader: Callable
var _kept_switch: bool = true
var _written: PackedStringArray = PackedStringArray()


func before_each() -> void:
    _kept_reader = ReferencePaste.desktop_picture
    _kept_switch = SaSettings.sad_keeps_reference_pictures
    _written.clear()


func after_each() -> void:
    ReferencePaste.desktop_picture = _kept_reader
    SaSettings.sad_keeps_reference_pictures = _kept_switch
    for path in _written:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


func _docker() -> ReferenceDocker:
    var docker := ReferenceDocker.new()
    docker.board_view.size = Vector2(300, 200)
    return docker


## A picture from a file on disk, a copy of the project's gradient, so the
## suite can delete it as a painter's tidy folder would.
func _file_picture() -> String:
    var path := ProjectSettings.globalize_path(SaDataRoot.path("from-a-file.png"))
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(FileAccess.get_file_as_bytes(PICTURE))
    file.close()
    _written.append(path)
    return path


## A board holding a pasted picture and a picture from a file, and a second
## board holding the file's picture again.
func _boards() -> ReferenceDocker:
    var image := Image.create_empty(PASTED_SIZE.x, PASTED_SIZE.y, false, Image.FORMAT_RGBA8)
    image.fill(Color(0.2, 0.6, 0.9, 1.0))
    image.set_pixel(3, 4, Color(0.9, 0.1, 0.2, 1.0))
    var docker := _docker()
    var pasted := docker.paste_at(Vector2(150, 100), SaDesktopPicture.new(image, "wl-paste"))
    assert_not_null(pasted, "The paste placed a picture")
    _written.append(pasted.path)
    var path := _file_picture()
    assert_eq(docker.open_paths(PackedStringArray([path])), 1, "and the file's picture is on the board")
    docker.add_board("Again")
    assert_eq(docker.open_paths(PackedStringArray([path])), 1, "and on a second board")
    return docker


func _document(docker: ReferenceDocker) -> SaDocument:
    var document := SaDocument.new()
    document.setup_default_document(Vector2i(64, 64), SaCompositor.new())
    document.reference_boards = docker.to_header()
    return document


func _save(document: SaDocument, named: String, keep: bool) -> String:
    SaSettings.sad_keeps_reference_pictures = keep
    var path := ProjectSettings.globalize_path(SaDataRoot.path(named))
    assert_eq(SaExport.save_sad(document, path, 0), OK, "Saved %s" % named)
    _written.append(path)
    return path


## The docker a painter would see after opening *path*.
func _opened(path: String) -> ReferenceDocker:
    var read := SaDocument.new()
    assert_eq(SaExport.load_sad(read, path, SaCompositor.new()), OK, "Opened %s" % path.get_file())
    var docker := _docker()
    docker.restore(read.reference_boards)
    read.free()
    return docker


func _same_pixels(one: Image, other: Image) -> bool:
    var a := one.duplicate() as Image
    var b := other.duplicate() as Image
    a.convert(Image.FORMAT_RGBAF)
    b.convert(Image.FORMAT_RGBAF)
    return a.get_size() == b.get_size() and a.get_data() == b.get_data()


## On, both pictures come back with their pixels and rectangles after both
## originals are deleted, and off, both are placeholders in their rectangles.
func test_a_file_saved_with_the_switch_on_opens_whole_after_the_originals_are_gone() -> void:
    var docker := _boards()
    var board := docker._boards[0]
    var originals: Array[Image] = [board.pictures[0].image, board.pictures[1].image]
    var rects: Array[Rect2] = [board.pictures[0].rect, board.pictures[1].rect]
    var paths: Array[String] = [board.pictures[0].path, board.pictures[1].path]
    var document := _document(docker)
    var kept := _save(document, "kept.sad", true)
    var plain := _save(document, "plain.sad", false)
    for path in paths:
        DirAccess.remove_absolute(path)
        assert_false(FileAccess.file_exists(path), "%s is deleted" % path.get_file())

    var whole := _opened(kept)
    assert_eq(whole._boards.size(), 2, "Both boards come back")
    for i in range(2):
        var picture := whole._boards[0].pictures[i]
        assert_false(picture.is_missing(), "%s is read from the file" % paths[i].get_file())
        assert_true(picture.image != null and _same_pixels(picture.image, originals[i]), "with its own pixels")
        assert_eq(picture.rect, rects[i], "in its rectangle")
        assert_eq(picture.path, paths[i], "and still named by its path")
    assert_false(whole._boards[1].pictures[0].is_missing(), "The second board's picture comes back too")

    var empty := _opened(plain)
    for i in range(2):
        var picture := empty._boards[0].pictures[i]
        assert_true(picture.is_missing(), "Off, %s is a placeholder" % paths[i].get_file())
        assert_eq(picture.rect, rects[i], "in its rectangle")

    # Saved again on the machine where the paths are gone, the bytes the file
    # brought are stored again, so a third machine opens it whole as well.
    var again := SaDocument.new()
    again.setup_default_document(Vector2i(64, 64), SaCompositor.new())
    again.reference_boards = whole.to_header()
    var resaved := _save(again, "saved-again.sad", true)
    var third := _opened(resaved)
    assert_false(third._boards[0].pictures[0].is_missing(), "A save where the paths are gone keeps the pasted picture")
    assert_false(third._boards[0].pictures[1].is_missing(), "and the file's")
    var header := SaSadFile.header_at(resaved)
    assert_false(JSON.stringify(header).contains('"bytes"'), "and never writes the bytes into the header")
    for opened: ReferenceDocker in [whole, empty, third]:
        opened.free()
    docker.free()
    document.free()
    again.free()


## On is larger than off by about the two pictures' bytes, and the picture on
## two boards is counted once.
func test_the_file_grows_by_each_picture_once() -> void:
    var docker := _boards()
    var board := docker._boards[0]
    var pasted_bytes := FileAccess.get_file_as_bytes(board.pictures[0].path).size()
    var file_bytes := FileAccess.get_file_as_bytes(board.pictures[1].path).size()
    var document := _document(docker)
    var kept := FileAccess.get_file_as_bytes(_save(document, "kept.sad", true)).size()
    var plain := FileAccess.get_file_as_bytes(_save(document, "plain.sad", false)).size()
    var grown := kept - plain
    var pictures := pasted_bytes + file_bytes
    assert_true(grown >= pictures, "On grows the file by the pictures' %d bytes at least, it grew %d" % [pictures, grown])
    # The header's two entries naming the blobs are the rest, compressed, and
    # a third copy of the file's picture would be thousands of bytes more.
    assert_true(grown < pictures + 200, "and by not much more, the picture on two boards stored once, %d" % grown)
    assert_true(file_bytes > 200, "a margin the second copy would be past, at %d bytes" % file_bytes)
    var header := SaSadFile.header_at(ProjectSettings.globalize_path(SaDataRoot.path("kept.sad")))
    assert_eq((header.get(SaSadReferencePictures.PICTURES_KEY, []) as Array).size(), 2, "Two pictures stored for three slots")
    docker.free()
    document.free()


## A file with stored pictures whose originals still resolve reads the
## originals, so an edit made outside Sara shows.
func test_a_path_that_resolves_wins_over_the_stored_bytes() -> void:
    var docker := _boards()
    var path := docker._boards[0].pictures[1].path
    var document := _document(docker)
    var kept := _save(document, "kept.sad", true)
    var edited := Image.create_empty(12, 9, false, Image.FORMAT_RGBA8)
    edited.fill(Color(0.0, 1.0, 0.0, 1.0))
    assert_eq(edited.save_png(path), OK, "The original is edited outside Sara")
    var opened := _opened(kept)
    assert_eq(opened._boards[0].pictures[1].image.get_size(), Vector2i(12, 9), "and the open shows the edit")
    opened.free()
    docker.free()
    document.free()


## The switch is a row on the Files page and a key of the profile, off by
## default.
func test_the_switch_is_a_files_preference_off_by_default() -> void:
    assert_eq(SaSettingsKeys.place_of(&"sad_keeps_reference_pictures"), ["files", "keep_reference_pictures"], "Kept under files")
    var fresh := SaSettingsValues.new()
    assert_false(fresh.sad_keeps_reference_pictures, "and off in a fresh profile")
    fresh.free()
    var source := FileAccess.get_file_as_string("res://ui/settings/pages/files_page.gd")
    assert_true(source.contains('"Keep reference pictures inside the file"'), "The Files page carries the row")
