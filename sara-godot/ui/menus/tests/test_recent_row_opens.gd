## A press on a recent row in the File menu opens that file.
##
## The recent files are rows of the File menu's own popup, ids from
## `SaFileMenu.ID_RECENT_BASE` up. A press on a row reaches `on_id_pressed`,
## whose `match` names the fixed ids only, so a press on a recent row has to
## reach `_on_recent_pressed` by its own route.
##
## The open itself needs a live document, which needs Sara's own main scene,
## which no suite has (`test_file_menu_open_order.gd` says why). So the document
## flow the menu runs here records the path `open_path` is handed instead of
## opening it. With no document `confirm_discard` runs its callable at once,
## which is the same guard a painter meets with nothing unsaved. The flow is
## `SaDocumentFiles`, so the recording is there and the menu is handed it
## through the seam `files()`. What a painter sees is
## `scenarios/a-recent-file-in-the-file-menu-does-not-open.json`.
extends "res://tests/test_framework.gd"

static var scratch_first: String = SaDataRoot.path("d52-first.sad")
static var scratch_second: String = SaDataRoot.path("d52-second.sad")


## The document flow with its open recorded rather than performed.
class RecordingFiles:
    extends SaDocumentFiles

    var opened: Array[String] = []

    func open_path(path: String) -> void:
        opened.append(path)


## The File menu, running the recording flow. The flow is a child of the bar the
## popup hangs from, so freeing the bar frees it.
class RecordingFileMenu:
    extends SaFileMenu

    var flow := RecordingFiles.new()

    var opened: Array[String]:
        get:
            return flow.opened

    func _init(menu_popup: SaChoicePopup) -> void:
        super(menu_popup)
        host().add_child(flow)

    func files() -> SaDocumentFiles:
        return flow


var _saved_recent: Array = []


func before_each() -> void:
    _saved_recent = SaSettings.recent_files()


func after_each() -> void:
    SaSettings.remove_recent_file(scratch_first)
    SaSettings.remove_recent_file(scratch_second)
    var now := SaSettings.recent_files()
    for i in range(_saved_recent.size() - 1, -1, -1):
        var path: String = _saved_recent[i]
        if not now.has(path):
            SaSettings.add_recent_file(path)


## A detached bar and a recording File menu on its popup, with two recent paths
## in the order the list keeps them: newest first, so scratch_first is row 0.
func _menu() -> Array:
    SaSettings.add_recent_file(scratch_second)
    SaSettings.add_recent_file(scratch_first)
    var bar := TopMenuBar.new()
    bar._ready()
    var menu := RecordingFileMenu.new(bar.menus["File"])
    menu.populate()
    return [bar, menu]


func test_a_press_on_the_second_recent_row_opens_that_file() -> void:
    var built := _menu()
    var bar: TopMenuBar = built[0]
    var menu: RecordingFileMenu = built[1]

    var recent := SaSettings.recent_files()
    assert_eq(recent[0], scratch_first, "The newest recent path is row 0")
    assert_eq(recent[1], scratch_second, "and the one before it is row 1")

    menu.on_id_pressed(SaFileMenu.ID_RECENT_BASE + 1)
    assert_eq(menu.opened, [scratch_second] as Array[String], "The second row's press reaches the open with its own path")

    menu.on_id_pressed(SaFileMenu.ID_RECENT_BASE)
    assert_eq(menu.opened, [scratch_second, scratch_first] as Array[String], "and the first row's press opens the first")
    bar.free()


## The press a painter makes goes through the popup, not straight to the handler,
## so the row is pressed the way a click presses it.
func test_a_click_on_the_row_goes_through_the_popup_to_the_open() -> void:
    var built := _menu()
    var bar: TopMenuBar = built[0]
    var menu: RecordingFileMenu = built[1]

    var popup: SaChoicePopup = bar.menus["File"]
    var row := SaMenu.key(SaFileMenu.ID_RECENT_BASE + 1)
    assert_true(popup.row_ids().has(row), "The File menu carries a row for the second recent file")
    popup.chosen.emit(row)
    assert_eq(menu.opened, [scratch_second] as Array[String], "and choosing it opens that file")
    bar.free()


## A row past the list, and the fixed ids, are not a recent open.
func test_the_fixed_rows_and_a_row_past_the_list_open_nothing_recent() -> void:
    var built := _menu()
    var bar: TopMenuBar = built[0]
    var menu: RecordingFileMenu = built[1]

    menu.on_id_pressed(SaFileMenu.ID_RECENT_BASE + 40)
    assert_true(menu.opened.is_empty(), "A row past the end of the list opens nothing")
    bar.free()
