## A reference picture can be removed, its hover bar is small
## enough to leave the picture seen, and the plus adds pictures.
##
## A painter must be able to delete a picture from the reference docker. The
## four buttons (flip, grey, crop, top) must not hide the picture, and the plus
## sign adds pictures, not a new board.
##
## Built outside the tree the way the hover bar's suite builds the docker,
## because a `Window` in the tree hangs a headless run. The running app's side,
## real clicks on a real docker, is the scenario of the same subject under
## `scenarios/`.
extends "res://tests/test_framework.gd"

const REFERENCE_IMAGE := "res://ui/icon.png"

var _paths: PackedStringArray = PackedStringArray()
var _platform_before: SaFilePicker.Platform = null


func before_each() -> void:
    _platform_before = SaFilePicker.platform
    SaFilePicker.platform = StandIn.new()
    _paths.clear()
    var bytes := FileAccess.get_file_as_bytes(REFERENCE_IMAGE)
    for i in range(3):
        var path := SaDataRoot.path("reference_%d.png" % i)
        var file := FileAccess.open(path, FileAccess.WRITE)
        file.store_buffer(bytes)
        file.close()
        _paths.append(path)


func after_each() -> void:
    var cancelled := 0
    while SaFilePicker.newest() != null and cancelled < 100:
        SaFilePicker.newest().cancel()
        cancelled += 1
    assert_null(SaFilePicker.newest(), "A cancelled picker goes away")
    SaFilePicker.platform = _platform_before
    for path in _paths:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _docker() -> ReferenceDocker:
    var docker := ReferenceDocker.new()
    docker.board_view.size = Vector2(SaUI.pxf(300), SaUI.pxf(200))
    return docker


func _key(code: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = true
    return event


## The paths of the board as it was last kept: the settings' copy when the
## boards are kept there, which is where a docker outside a document keeps them,
## and the header a document would be handed otherwise.
func _saved_paths(docker: ReferenceDocker) -> Array:
    var out: Array = []
    var kept: Variant = docker.to_header()
    if docker._store() == "settings":
        kept = SaSettings.config.get_value(ReferenceDocker.SETTINGS_SECTION, ReferenceDocker.SETTINGS_KEY, [])
    for entry: Dictionary in kept:
        for picture: Variant in entry.get("pictures", []):
            if picture is Dictionary:
                out.append(String((picture as Dictionary).get("path", "")))
    return out


## Three pictures, one removed through the right click's Remove from Board and
## one with Delete: two left, then one, the files on disk as they were, and
## the board saved without them.
func test_a_picture_comes_off_through_the_menu_and_through_delete() -> void:
    var docker := _docker()
    var sums: Array[String] = []
    for path in _paths:
        sums.append(FileAccess.get_md5(path))
    assert_eq(docker.open_paths(_paths), 3, "Three pictures are placed")
    var board := docker.board()
    var view := docker.board_view
    var first := board.pictures[0]

    assert_true(view.fill_menu(first), "The menu opens over a picture")
    assert_true(view.menu.row_ids().has(ReferencePictureView.REMOVE), "and offers Remove from Board")
    assert_true(view.menu.row_labels().has("Remove from Board"), "by that name")
    assert_true(view.menu.press_row(ReferencePictureView.REMOVE), "which a press chooses")
    assert_eq(board.pictures.size(), 2, "Two pictures are left")
    assert_false(board.pictures.has(first), "and the one under the menu is gone")
    assert_false(_saved_paths(docker).has(_paths[0]), "the saved board does not hold it")

    var second := board.pictures[0]
    view.select_picture(second)
    assert_true(view.erase(_key(KEY_DELETE)), "Delete takes the selected picture off")
    assert_eq(board.pictures.size(), 1, "one is left")
    assert_false(board.pictures.has(second), "and it is not the one deleted")
    assert_null(view.selected(), "nothing is selected after")
    assert_eq(_saved_paths(docker), [String(_paths[2])], "the saved board holds the last alone")

    var last := board.pictures[0]
    view.select_picture(last)
    assert_true(view.erase(_key(KEY_BACKSPACE)), "Backspace does the same")
    assert_true(board.pictures.is_empty(), "and the board is empty")
    assert_false(view.erase(_key(KEY_DELETE)), "Delete with nothing selected takes nothing")

    for i in range(_paths.size()):
        assert_true(FileAccess.file_exists(_paths[i]), "File %d is still on disk" % i)
        assert_eq(FileAccess.get_md5(_paths[i]), sums[i], "and unchanged")
    docker.free()


## A chord with Delete is not the erase, so Ctrl+Delete never takes a picture.
func test_a_chord_on_delete_removes_nothing() -> void:
    var docker := _docker()
    docker.open_paths(_paths)
    var key := _key(KEY_DELETE)
    key.ctrl_pressed = true
    assert_false(docker.board_view.erase(key), "Ctrl+Delete is not the erase")
    assert_eq(docker.board().pictures.size(), 3, "and all three stay")
    docker.free()


## Removing the soloed picture leaves solo: the board draws what is left.
func test_removing_the_soloed_picture_leaves_solo() -> void:
    var docker := _docker()
    docker.open_paths(_paths)
    var board := docker.board()
    var middle := board.pictures[1]
    assert_true(docker.board_view.toggle_solo(middle), "Solo on the middle picture")
    assert_true(docker.board_view.fill_menu(middle), "The menu opens in solo")
    assert_true(docker.board_view.menu.press_row(ReferencePictureView.REMOVE), "Remove from Board takes")
    assert_null(board.soloed(), "Solo is left")
    assert_eq(board.ordered().size(), 2, "and the other two are drawn")
    assert_eq(docker.report()["solo"], -1, "the dump says no solo")
    docker.free()


## The router leaves bare Delete and Backspace to a window that keeps them, and
## the Reference docker is one, while the layer's Clear keeps them elsewhere.
func test_the_router_leaves_the_erase_keys_to_the_docker() -> void:
    var docker := _docker()
    assert_true(ShortcutRouter.erase_keys_kept(docker, null, _key(KEY_DELETE)), "Delete is the docker's")
    assert_true(ShortcutRouter.erase_keys_kept(docker, null, _key(KEY_BACKSPACE)), "and so is Backspace")
    var chord := _key(KEY_DELETE)
    chord.ctrl_pressed = true
    assert_false(ShortcutRouter.erase_keys_kept(docker, null, chord), "a chord is not")
    assert_false(ShortcutRouter.erase_keys_kept(docker, null, _key(KEY_A)), "nor another key")
    var other := Window.new()
    assert_false(ShortcutRouter.erase_keys_kept(other, null, _key(KEY_DELETE)), "Another window leaves Delete to Clear Layer")
    other.free()
    docker.free()


## Over a picture of 40 by 30 logical pixels the bar stands outside the
## picture, and over a large one on it, each button no taller than 16.
func test_the_bar_leaves_a_small_picture_seen() -> void:
    var docker := _docker()
    docker.open_paths(PackedStringArray([_paths[0], _paths[1]]))
    var board := docker.board()
    var view := docker.board_view
    board.zoom = 1.0
    board.offset = Vector2.ZERO
    var small := board.pictures[0]
    var large := board.pictures[1]
    small.rect = Rect2(Vector2(SaUI.pxf(60), SaUI.pxf(80)), Vector2(SaUI.pxf(40), SaUI.pxf(30)))
    large.rect = Rect2(Vector2(SaUI.pxf(120), SaUI.pxf(10)), Vector2(SaUI.pxf(160), SaUI.pxf(150)))

    view.select_picture(small)
    view.pointer_entered()
    view.sync_bar()
    var bar := Rect2(view._bar.row.position, view._bar.row.size)
    var picture := board.view_rect(small)
    assert_eq(picture.size, Vector2(SaUI.pxf(40), SaUI.pxf(30)), "The small picture is 40 by 30 on screen")
    assert_true(bar.size.x > 0.0 and bar.size.y > 0.0, "The bar has a size")
    assert_false(bar.intersects(picture), "and stands outside the small picture, %s beside %s" % [bar, picture])
    assert_true(bar.position.y + bar.size.y <= picture.position.y + 0.5, "above it")

    small.rect.position.y = 0.0
    view.sync_bar()
    bar = Rect2(view._bar.row.position, view._bar.row.size)
    picture = board.view_rect(small)
    assert_false(bar.intersects(picture), "At the top edge it still stands outside")
    assert_true(bar.position.y >= picture.end.y - 0.5, "below the picture, with no room above")

    view.select_picture(large)
    view.sync_bar()
    bar = Rect2(view._bar.row.position, view._bar.row.size)
    picture = board.view_rect(large)
    assert_true(picture.encloses(bar), "Over a large picture the bar stands on it")
    for id: String in view._bar._buttons:
        var button := view._bar._buttons[id] as Button
        var tall := button.get_combined_minimum_size().y
        assert_true(tall <= SaUI.pxf(16), "%s is %.1f tall, no taller than 16 logical pixels" % [id, tall])
        assert_true(button.icon != null, "%s is an icon" % id)
        assert_true(button.tooltip_text.length() > 0, "%s keeps its tooltip" % id)
    docker.free()


## A pressed toggle reads apart from an unpressed one: its box is another
## colour.
func test_a_pressed_toggle_is_plainly_marked() -> void:
    var docker := _docker()
    var button := docker.board_view._bar._buttons["flip"] as Button
    var normal := button.get_theme_stylebox("normal") as StyleBoxFlat
    var pressed := button.get_theme_stylebox("pressed") as StyleBoxFlat
    assert_true(normal != null and pressed != null, "Both states have a box")
    assert_true(normal.bg_color != pressed.bg_color, "and the pressed one is another colour")
    docker.free()


## The plus asks for the file picker, for pictures, and says so.
func test_the_plus_asks_for_pictures() -> void:
    var docker := _docker()
    var plus := docker.find_child("AddPicturesButton", true, false) as Button
    assert_not_null(plus, "The plus is there")
    assert_eq(plus.tooltip_text, "Add pictures to this board", "and says what it does")
    var boards := docker.to_header().size()
    plus.pressed.emit()
    var picker := SaFilePicker.newest()
    assert_not_null(picker, "A press asks for the file picker")
    assert_eq(picker.mode, SaFilePicker.Mode.OPEN_FILES, "for several files")
    assert_eq(docker.to_header().size(), boards, "and makes no board")
    picker.answer(true, PackedStringArray([_paths[0]]), 0)
    assert_eq(docker.board().pictures.size(), 1, "The file picked lands on the board")
    docker.free()


## A new board comes from the strip's right click menu and from a double click
## on its empty part, and the menu's Rename and Close act on the tab.
func test_a_new_board_comes_from_the_strip() -> void:
    var docker := _docker()
    docker.board()
    var tabs := docker._tabs
    assert_eq(tabs.bar.tab_count, 1, "One board to start")
    tabs.fill_menu(-1)
    assert_eq(
        tabs.menu.row_ids(),
        [ReferenceTabs.NEW_BOARD, ReferenceTabs.RENAME_BOARD, ReferenceTabs.CLOSE_BOARD],
        "The strip's menu is New Board, Rename and Close"
    )
    assert_true(tabs.menu.press_row(ReferenceTabs.NEW_BOARD), "New Board takes")
    assert_eq(tabs.bar.tab_count, 2, "and makes a second board")

    var click := InputEventMouseButton.new()
    click.button_index = MOUSE_BUTTON_LEFT
    click.pressed = true
    click.double_click = true
    click.position = Vector2(SaUI.pxf(5000), SaUI.pxf(5))
    assert_eq(tabs.bar.get_tab_idx_at_point(click.position), -1, "The click is on the empty strip")
    tabs.bar.gui_input.emit(click)
    assert_eq(tabs.bar.tab_count, 3, "and a double click there makes a third")

    tabs.fill_menu(0)
    assert_true(tabs.menu.press_row(ReferenceTabs.CLOSE_BOARD), "Close from the menu takes")
    assert_eq(tabs.bar.tab_count, 2, "and the first board goes")
    docker.free()


class StandIn:
    extends SaFilePicker.Platform

    func has_picker() -> bool:
        return true

    func show(_picker: SaFilePicker, _filters: PackedStringArray, _parent_id: int, _answer: Callable) -> void:
        pass
