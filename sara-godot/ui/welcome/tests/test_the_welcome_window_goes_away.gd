## The Welcome window goes away as Blender's splash does, on a
## press outside it, on a document opened and on a document made, and stays up
## for a press on itself or on a dialog, a cancelled picker and a file that
## would not load.
##
## The windows are built and never added to a tree, for the reason
## `test_welcome_window.gd` gives, so the press is asked of the two statics
## the window decides by, and the presses themselves are
## `scenarios/a-press-on-the-canvas-puts-the-welcome-window-away.json`, once
## embedded and once not. A document made through New and Create is
## `scenarios/new-and-create-put-the-welcome-window-away.json`.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, because opening and making a document rebinds the
## easel's textures.
const REQUIRES_GPU := true

static var scratch_fixture: String = SaDataRoot.path("d10-the-document-opened.sad")
static var scratch_missing: String = SaDataRoot.path("d10-a-file-that-is-not-there.sad")
const SIZE := Vector2i(64, 64)

var _saved_recent: Array = []
var _canvas: SaCanvas = null
var _files: SaDocumentFiles = null
var _welcome: SaWelcomeWindow = null
var _dialogs: MainDialogs = null


func before_each() -> void:
    _saved_recent = SaSettings.recent_files()
    for path: String in _saved_recent:
        SaSettings.remove_recent_file(str(path))
    _canvas = SaCanvas.new()
    _canvas.canvas_size = SIZE
    _canvas.easel = SaEasel.create_default(SIZE, null, SaColorSpace.oklab())
    _canvas.add_child(_canvas.easel)
    assert_eq(SaExport.save_sad(_canvas.document, scratch_fixture, 0), OK, "the fixture is written")
    _files = SaDocumentFiles.new(func() -> SaCanvas: return _canvas)
    _welcome = SaWelcomeWindow.new()
    _welcome.visible = true
    _dialogs = MainDialogs.new(null, func() -> SaCanvas: return _canvas, _welcome)
    # What the window's Open does once the flow is in a tree, which a suite's is not.
    _files.document_opened.connect(_welcome._on_document_opened)


func after_each() -> void:
    for path: String in [scratch_fixture, scratch_missing]:
        DirAccess.remove_absolute(WelcomePreviewCache.cache_path(path))
        SaSettings.remove_recent_file(path)
        DirAccess.remove_absolute(path)
    for i in range(_saved_recent.size() - 1, -1, -1):
        SaSettings.add_recent_file(str(_saved_recent[i]))
    _dialogs.free()
    _welcome.free()
    _files.free()
    _canvas.free()


func test_a_press_is_a_button_or_a_touch_going_down() -> void:
    var left := InputEventMouseButton.new()
    left.button_index = MOUSE_BUTTON_LEFT
    left.pressed = true
    assert_true(SaPutAway.is_press(left), "a left press is a press")
    var right := InputEventMouseButton.new()
    right.button_index = MOUSE_BUTTON_RIGHT
    right.pressed = true
    assert_true(SaPutAway.is_press(right), "and so is a right one")
    left.pressed = false
    assert_false(SaPutAway.is_press(left), "a release is not")
    var wheel := InputEventMouseButton.new()
    wheel.button_index = MOUSE_BUTTON_WHEEL_UP
    wheel.pressed = true
    assert_false(SaPutAway.is_press(wheel), "the wheel scrolls rather than presses")
    var touch := InputEventScreenTouch.new()
    touch.pressed = true
    assert_true(SaPutAway.is_press(touch), "a touch landing is a press")
    var motion := InputEventMouseMotion.new()
    assert_false(SaPutAway.is_press(motion), "and a motion is none")


## Where a press on the main window lands, among what is embedded in it.
func test_a_press_on_the_window_or_a_dialog_keeps_it_and_elsewhere_closes_it() -> void:
    _welcome.position = Vector2i(400, 200)
    _welcome.size = Vector2i(720, 480)
    var dialog := Window.new()
    dialog.borderless = true
    dialog.position = Vector2i(1200, 100)
    dialog.size = Vector2i(300, 200)
    var docker := DockerWindow.new()
    docker.position = Vector2i(20, 100)
    docker.size = Vector2i(250, 400)
    var embedded: Array[Window] = [_welcome, dialog, docker]

    assert_false(SaWelcomeWindow.press_closes(Vector2(500, 300), embedded), "a press on a card or a pane keeps it")
    assert_false(SaWelcomeWindow.press_closes(Vector2(401, 201), embedded), "and so does one on its own bar")
    var on_dialog := SaWelcomeWindow.press_closes(Vector2(1300, 150), embedded)
    assert_false(on_dialog, "a press on a dialog, New Document or the picker, keeps it")
    assert_true(SaWelcomeWindow.press_closes(Vector2(100, 300), embedded), "a press on a docker closes it")
    assert_true(SaWelcomeWindow.press_closes(Vector2(1000, 900), embedded), "and a press on the canvas does")
    var nothing: Array[Window] = []
    assert_true(
        SaWelcomeWindow.press_closes(Vector2(1000, 900), nothing), "with nothing embedded, every press on the main window does"
    )
    dialog.visible = false
    assert_true(SaWelcomeWindow.press_closes(Vector2(1300, 150), embedded), "a dialog put away covers nothing")
    dialog.free()
    docker.free()


func test_a_file_opened_puts_the_window_away() -> void:
    _files.open_path(scratch_fixture)
    assert_eq(_canvas.document.file_path, scratch_fixture, "the file is the document")
    assert_false(_welcome.visible, "and the window is away")


func test_a_file_that_would_not_load_leaves_it_up() -> void:
    _files.open_path(scratch_missing)
    assert_true(_welcome.visible, "no document landed, so the window stays, as for a cancelled picker")


func test_create_in_new_document_puts_the_window_away() -> void:
    _dialogs._on_new_document_confirmed(Vector2i(96, 48), SaColorSpace.oklab(), 72.0)
    assert_eq(_canvas.document.canvas_size, Vector2i(96, 48), "the document is made")
    assert_false(_welcome.visible, "and the window is away")


## A card chosen while the boot runs is dropped when a press puts the window away.
func test_a_window_put_away_during_the_boot_drops_the_held_card() -> void:
    SaSettings.add_recent_file(scratch_fixture)
    var booting := SaWelcomeWindow.new(true)
    var grid: WelcomeRecentGrid = null
    for child in booting.recent_pane.recent_grid.get_children():
        grid = child as WelcomeRecentGrid
    assert_not_null(grid, "the boot's window carries its grid")
    if grid != null:
        grid.cards[0].pressed.emit()
        assert_false(grid.row_report()[0]["held"], "the card chosen is drawn whole")
        booting.hide()
        # What the engine announces for a window in a tree, and not for a detached one.
        booting.visibility_changed.emit()
        assert_true(grid.row_report()[0]["held"], "and once the window is away it is held with the rest, chosen no more")
    booting.free()
