## A picture copied in a browser pastes into the Reference
## docker with Ctrl+V or its right click.
##
## A painter finds a picture in a browser, copies it, and pastes it with
## Control-V while the Reference docker is focused or with its right click.
##
## Built outside the tree the way the other Reference suites build the docker,
## because a `Window` in the tree hangs a headless run, and the clipboard is the
## seam `ReferencePaste.desktop_picture`, because a run on a desktop would
## paste whatever its painter last copied. The running app's side, a real
## wl-copy on the nested compositor, a real Ctrl+V over the docker and over the
## canvas, a real right click and a save opened again, is the scenario of the same
## subject under `scenarios/`.
extends "res://tests/test_framework.gd"

const REFERENCE_IMAGE := "res://ui/icon.png"
const PICTURE_SIZE := Vector2i(40, 30)

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
    docker.board_view.size = Vector2(300, 200)
    return docker


func _holds(picture: SaDesktopPicture) -> void:
    ReferencePaste.desktop_picture = func() -> SaDesktopPicture: return picture


func _browser_picture() -> SaDesktopPicture:
    var image := Image.create_empty(PICTURE_SIZE.x, PICTURE_SIZE.y, false, Image.FORMAT_RGBA8)
    image.fill(Color(0.2, 0.6, 0.9, 1.0))
    return SaDesktopPicture.new(image, "wl-paste")


func _notice_says() -> String:
    var notice := SaMessage.notice_widget()
    return notice.label.text if notice != null and notice.showing() else ""


func _pasted_files() -> PackedStringArray:
    var out := PackedStringArray()
    var folder := ReferencePaste.folder()
    if DirAccess.dir_exists_absolute(folder):
        for name in DirAccess.get_files_at(folder):
            out.append(folder.path_join(name))
    return out


## The key's paste: one picture on the board, centred in the view, a PNG of the
## clipboard's size in the pasted references folder under the data root, and
## the board kept by that file's path.
func test_the_key_puts_the_clipboard_on_the_board_as_a_png_of_its_own() -> void:
    _holds(_browser_picture())
    var docker := _docker()
    var before := _pasted_files()
    var placed := docker.paste_at(docker.board_view.size / 2.0)
    assert_not_null(placed, "The paste placed a picture")
    var board := docker.board()
    assert_eq(board.pictures.size(), 1, "one picture is on the board")
    assert_true(placed.path.begins_with(ReferencePaste.folder()), "kept in the pasted references folder")
    assert_true(placed.path.get_file().begins_with("pasted-"), "named for the paste's date and time")
    _written.append(placed.path)
    assert_eq(_pasted_files().size(), before.size() + 1, "one PNG was written")
    var image := Image.load_from_file(placed.path)
    assert_eq(image.get_size(), PICTURE_SIZE, "at the clipboard's size")
    var centre := board.to_view(placed.rect.get_center())
    assert_almost_eq(centre.x, 150.0, 0.5, "centred in the view across")
    assert_almost_eq(centre.y, 100.0, 0.5, "and down")
    assert_eq(docker.board_view.selected(), placed, "and selected")
    docker.free()


## A file a file manager copied comes by its own path, and nothing is written.
func test_a_copied_file_is_added_by_its_own_path() -> void:
    var path := ProjectSettings.globalize_path(SaDataRoot.path("copied_file.png"))
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(FileAccess.get_file_as_bytes(REFERENCE_IMAGE))
    file.close()
    _written.append(path)
    _holds(SaDesktopPicture.new(SaImageImport.read(path), path))
    var docker := _docker()
    var before := _pasted_files()
    var placed := docker.paste_at(Vector2(20, 20))
    assert_not_null(placed, "The copied file is placed")
    assert_eq(placed.path, path, "by its own path")
    assert_eq(_pasted_files(), before, "and nothing is written")
    docker.free()


## An empty clipboard says so in the corner and adds nothing.
func test_an_empty_clipboard_says_so_and_adds_nothing() -> void:
    _holds(null)
    var docker := _docker()
    assert_null(docker.paste_at(Vector2(10, 10)), "Nothing is placed")
    assert_eq(docker.board().pictures.size(), 0, "the board is empty")
    assert_eq(_notice_says(), tr(ReferencePaste.NOTHING), "and the corner says why")
    docker.free()


## The right click on empty board has a Paste row, and its press puts the
## picture's centre at the click. With an empty clipboard the row is there,
## dimmed and disabled, and a press does nothing.
func test_the_right_click_on_empty_board_pastes_at_the_click() -> void:
    var docker := _docker()
    var view := docker.board_view
    _holds(null)
    assert_true(view.fill_menu(null, Vector2(60, 50)), "The empty board opens the menu")
    assert_eq(view.menu.row_ids(), [ReferencePictureView.PASTE] as Array[StringName], "with Paste alone on it")
    assert_true(view.menu.is_disabled(ReferencePictureView.PASTE), "dimmed with nothing on the clipboard")
    assert_false(view.menu.press_row(ReferencePictureView.PASTE), "and a press does nothing")
    assert_eq(docker.board().pictures.size(), 0, "the board stays empty")

    _holds(_browser_picture())
    assert_true(view.fill_menu(null, Vector2(60, 50)), "Opened again with a picture copied")
    assert_false(view.menu.is_disabled(ReferencePictureView.PASTE), "Paste is lit")
    assert_true(view.menu.press_row(ReferencePictureView.PASTE), "and its press takes")
    var board := docker.board()
    assert_eq(board.pictures.size(), 1, "one picture is on the board")
    var placed := board.pictures[0]
    _written.append(placed.path)
    var centre := board.to_view(placed.rect.get_center())
    assert_almost_eq(centre.x, 60.0, 0.5, "its centre at the click across")
    assert_almost_eq(centre.y, 50.0, 0.5, "and down")

    assert_true(view.fill_menu(placed, Vector2(60, 50)), "Over a picture the menu opens")
    assert_true(view.menu.row_ids().has(ReferencePictureView.PASTE), "and has Paste too")
    assert_true(view.menu.row_ids().has(ReferencePictureView.REMOVE), "beside Remove from Board")
    docker.free()


## Ctrl+V with no Reference docker under the pointer or holding the focus is
## the canvas's: the docker declines and the command goes on to the document's
## paste. The docker here is outside the tree, so it never wants the paste.
func test_a_paste_aimed_elsewhere_is_left_to_the_canvas() -> void:
    _holds(_browser_picture())
    var docker := _docker()
    assert_false(docker.wants_paste(), "A docker off screen does not want the paste")
    assert_false(ReferenceDocker.take_paste(Engine.get_main_loop() as SceneTree), "so the paste goes on to the canvas")
    assert_false(ReferenceDocker.take_paste(null), "and with no tree as well")
    assert_eq(docker.board().pictures.size(), 0, "and the board is unchanged")
    docker.free()


## A document saved with a pasted reference and opened again carries the
## board with the pasted file's path, and that board shows the picture.
func test_a_pasted_reference_comes_back_with_the_document() -> void:
    _holds(_browser_picture())
    var docker := _docker()
    var placed := docker.paste_at(Vector2(100, 100))
    _written.append(placed.path)
    var document := SaDocument.new()
    document.setup_default_document(Vector2i(64, 64), SaCompositor.new())
    document.reference_boards = docker.to_header()
    var path := SaDataRoot.path("pasted_reference.sad")
    assert_eq(SaExport.save_sad(document, path, 0), OK, "Saved")
    _written.append(ProjectSettings.globalize_path(path))
    var read := SaDocument.new()
    assert_eq(SaExport.load_sad(read, path, SaCompositor.new()), OK, "and read back")
    var again := _docker()
    again.restore(read.reference_boards)
    var board := again.board()
    assert_eq(board.pictures.size(), 1, "The board comes back with the picture")
    assert_eq(board.pictures[0].path, placed.path, "kept by the pasted file")
    assert_false(board.pictures[0].is_missing(), "and the picture is read")
    assert_eq(board.pictures[0].image.get_size(), PICTURE_SIZE, "at its size")
    document.free()
    read.free()
    docker.free()
    again.free()
