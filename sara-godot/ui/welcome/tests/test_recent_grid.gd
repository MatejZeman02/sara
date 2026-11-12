## The recent pane's cards: one card per recent path in the order
## the list keeps them, a picture where the file carries one, a placeholder where
## it does not, a dimmed card that will not open where the file is gone, and a
## remove control that shortens the list the File menu reads too.
##
## The file with a picture is written here by hand, a v4 header holding only the
## `preview` key and a WebP blob, because saving a real document needs Sara's own
## main scene and `SaSadFile.read_preview` asks the file for nothing else. What the
## cards look like on the running app is
## `scenarios/the-recent-pane-is-a-grid-with-a-thumbnail-and-a-date.json`.
extends "res://tests/test_framework.gd"

static var scratch_with_preview: String = SaDataRoot.path("w3-with-preview.sad")
static var scratch_no_preview: String = SaDataRoot.path("w3-no-preview.sad")
static var scratch_missing: String = SaDataRoot.path("w3-this-file-is-not-there.sad")


## The document flow with its open recorded rather than performed, the way
## `test_recent_row_opens.gd` records it.
class RecordingFiles:
    extends SaDocumentFiles

    var opened: Array[String] = []

    func open_path(path: String) -> void:
        opened.append(path)


var _saved_recent: Array = []


func before_each() -> void:
    _saved_recent = SaSettings.recent_files()
    for path: String in _saved_recent:
        SaSettings.remove_recent_file(str(path))
    _write_preview_sad(scratch_with_preview)
    var plain := FileAccess.open(scratch_no_preview, FileAccess.WRITE)
    plain.store_string("not a document with a picture in it")
    plain.close()
    DirAccess.remove_absolute(scratch_missing)
    # Oldest first, so the list reads newest first as the picture, the plain
    # file and the missing one.
    SaSettings.add_recent_file(scratch_missing)
    SaSettings.add_recent_file(scratch_no_preview)
    SaSettings.add_recent_file(scratch_with_preview)


func after_each() -> void:
    for path: String in [scratch_with_preview, scratch_no_preview, scratch_missing]:
        SaSettings.remove_recent_file(path)
        DirAccess.remove_absolute(path)
    for i in range(_saved_recent.size() - 1, -1, -1):
        SaSettings.add_recent_file(str(_saved_recent[i]))


## A v4 `.sad` that carries a 64 by 36 preview and nothing else.
func _write_preview_sad(path: String) -> void:
    var picture := Image.create(64, 36, false, Image.FORMAT_RGBA8)
    picture.fill(Color(0.8, 0.3, 0.2))
    var blob := picture.save_webp_to_buffer(true, 0.9)
    var header := {"preview": {"offset": 0, "size": blob.size(), "format": "webp", "width": 64, "height": 36}}
    var raw := JSON.stringify(header).to_utf8_buffer()
    var packed := raw.compress(SaSadFile.SAD_BLOB_COMPRESS)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(SaSadFile.SAD_MAGIC_V4.to_ascii_buffer())
    file.store_32(SaSadFile.SAD_VERSION)
    file.store_32(packed.size())
    file.store_32(raw.size())
    file.store_buffer(packed)
    file.store_buffer(blob)
    file.close()


## The rows of the File menu's recent heading, which reads the same list.
func _menu_recent_rows(bar: TopMenuBar) -> int:
    var popup: SaChoicePopup = bar.menus["File"]
    var ids := popup.row_ids()
    var count := 0
    for i in SaSettingsValues.MAX_RECENT_FILES:
        if ids.has(SaMenu.key(SaFileMenu.ID_RECENT_BASE + i)):
            count += 1
    return count


func test_the_report_is_three_cards_in_list_order_with_the_missing_one_marked() -> void:
    assert_not_null(SaSadFile.read_preview(scratch_with_preview), "the hand-written file does carry a picture")
    var grid := WelcomeRecentGrid.new()
    var report := grid.row_report()
    assert_eq(report.size(), 3, "three cards for three recent paths")
    assert_eq(
        report.map(func(row: Dictionary) -> String: return row["path"]),
        SaSettings.recent_files(),
        "in the order recent_files() gives"
    )
    var missing := report.map(func(row: Dictionary) -> bool: return row["missing"])
    assert_eq(missing, [false, false, true], "the third is the missing one")
    var preview := report.map(func(row: Dictionary) -> bool: return row["preview"])
    assert_eq(preview, [true, false, false], "and only the first has a picture")
    assert_eq(report[0]["name"], "w3-with-preview.sad", "a card is named by the file")
    assert_eq(report[0]["folder"], SaDataRoot.folder(), "with its folder under the name")
    assert_false(str(report[0]["date"]).is_empty(), "and a date for a file that is there")
    assert_eq(report[2]["date"], "", "and none for one that is not")

    assert_not_null(grid.cards[0].get_parent().find_child("Thumbnail", true, false), "the file with a picture draws it")
    var placeholder := grid.cards[1].get_parent().find_child("Placeholder", true, false)
    assert_not_null(placeholder, "the file without one draws the placeholder")
    assert_false(grid.cards[0].disabled, "a card whose file is there opens")
    assert_true(grid.cards[2].disabled, "and the missing one does not")
    var missing_date: Label = grid.cards[2].get_parent().find_child("Date", true, false)
    assert_eq(missing_date.text, "missing", "the missing card says so where the date would be")
    grid.free()


func test_the_remove_control_shortens_the_list_and_the_file_menu_with_it() -> void:
    var bar := TopMenuBar.new()
    bar._ready()
    var menu := SaFileMenu.new(bar.menus["File"])
    menu.populate()
    assert_eq(_menu_recent_rows(bar), 3, "the File menu starts with three recent rows")

    var grid := WelcomeRecentGrid.new()
    var remove: Button = grid.cards[2].get_parent().find_child("RecentRemove2", true, false)
    remove.pressed.emit()

    assert_eq(SaSettings.recent_files().size(), 2, "the list is two long")
    assert_false(SaSettings.recent_files().has(scratch_missing), "without the path whose card was pressed")
    assert_eq(grid.row_report().size(), 2, "the grid drew itself again from it")
    assert_eq(_menu_recent_rows(bar), 2, "and the File menu's rows are two long with it")
    assert_false(FileAccess.file_exists(scratch_missing), "nothing was written to make the missing file")
    assert_true(FileAccess.file_exists(scratch_no_preview), "and a remove of a file that is there leaves it there")
    (grid.cards[1].get_parent().find_child("RecentRemove1", true, false) as Button).pressed.emit()
    assert_true(FileAccess.file_exists(scratch_no_preview), "even once its card is gone")
    grid.free()
    bar.free()


func test_a_card_opens_through_the_file_menus_guard() -> void:
    var files := RecordingFiles.new()
    var grid := WelcomeRecentGrid.new(files)
    grid.cards[1].pressed.emit()
    assert_eq(files.opened, [scratch_no_preview] as Array[String], "a press on a card reaches open_path with its own path")
    grid.free()
    files.free()


func test_the_date_is_the_shape_a_note_writes() -> void:
    var text := WelcomeRecentGrid.date_text(0)
    var shape := RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$")
    assert_not_null(shape.search(text), "year, month and day, as a note writes its date")
