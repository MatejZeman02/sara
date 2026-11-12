## The welcome window, the depth an opened picture is read at
## and the grid each have a Preferences row.
##
## Three choices a painter made once and could not find again: Show this at
## start lived only on the window it hid, the depth only in the question Sara
## asks on open, and the grid's switch only in View while its size sat on
## Display. Each row is driven the way a hand would and read back from the
## setting, and the two rows another surface writes are read back after that
## surface wrote, with the page open, because a row that showed what it was
## built with would be the stale switch the Display page's roll-off once was.
extends "res://tests/test_framework.gd"

var _saved_welcome: bool = true
var _saved_depth: String = "f32"
var _saved_grid: bool = false


func before_each() -> void:
    _saved_welcome = SaSettings.welcome_at_start
    _saved_depth = SaSettings.import_depth
    _saved_grid = SaSettings.show_grid


func after_each() -> void:
    SaSettings.welcome_at_start = _saved_welcome
    SaSettings.import_depth = _saved_depth
    SaSettings.show_grid = _saved_grid


## The row *key* of *page*, and the section it sits in, so a row that landed
## under the wrong heading fails here.
func _row_in(page: SaSettingsPage, section: String, key: StringName) -> SaPageRow:
    for block: SaPageSection in page.page.sections:
        for row: SaPageRow in block.rows:
            if row.key == key:
                assert_eq(block.title, section, "%s is under %s" % [key, section])
                return row
    return null


func test_the_welcome_row_writes_the_setting() -> void:
    SaSettings.welcome_at_start = true
    var page := SaGeneralPage.new()
    var row := _row_in(page, "Starting", &"welcome_at_start")
    assert_not_null(row, "General carries the welcome row")
    if row != null:
        assert_eq(row.label, "Show the welcome window", "under the title the request names")
        assert_true(row.reads(), "Built on, as the setting is")
        row.drive(false)
        assert_false(SaSettings.welcome_at_start, "and a press off writes the setting off")
        row.drive(true)
        assert_true(SaSettings.welcome_at_start, "and on again")
    page.free()


func test_the_depth_row_writes_the_setting_in_the_dialogs_words() -> void:
    SaSettings.import_depth = "f32"
    var page := SaFilesPage.new()
    var row := _row_in(page, "Importing", &"import_depth")
    assert_not_null(row, "Files carries the depth row")
    if row != null:
        assert_eq(row.label, "Bit depth for opened pictures", "under the title the wording sweep gave it")
        var shown := (row.control as SaChoiceButton).choice_labels()
        var dialog := SaImportFitDialog.new()
        var asked := (dialog.page.row(&"depth").control as SaChoiceButton).choice_labels()
        dialog.free()
        assert_eq(shown, asked, "The row offers what the dialog's Bit depth row offers, in its words, %s" % [shown])
        assert_eq(row.reads(), "f32", "Built on 32-bit float, as the setting is")
        assert_true(
            row.explanation.contains("16-bit float by default"), "and its sentence names the default a fresh profile opens on"
        )
        row.drive(SaSettings.IMPORT_DEPTHS.find("f16"))
        assert_eq(SaSettings.import_depth, "f16", "and picking 16-bit float writes f16")
        assert_eq(
            SaImportFitDialog.remembered_depth(),
            SaColorSpace.Depth.F16,
            "which is the depth the open question opens on and an .ora is read at"
        )
    page.free()


func test_the_grid_row_writes_the_setting_and_sits_above_the_size() -> void:
    SaSettings.show_grid = false
    var page := SaDisplayPage.new()
    var row := _row_in(page, "Grid", &"show_grid")
    assert_not_null(row, "Display carries the grid switch")
    if row != null:
        assert_eq(row.label, "Show the grid", "under the title the View menu's command reads as")
        var keys: Array[StringName] = []
        for block: SaPageSection in page.page.sections:
            if block.title == "Grid":
                for each: SaPageRow in block.rows:
                    keys.append(each.key)
        assert_eq(keys, [&"show_grid", &"grid_size"] as Array[StringName], "The switch is above the size")
        var size_hint := page.page.row(&"grid_size").explanation
        assert_false(size_hint.contains("Toggle Grid"), "and the size no longer points away")
        row.drive(true)
        assert_true(SaSettings.show_grid, "A press on writes the grid on")
        row.drive(false)
        assert_false(SaSettings.show_grid, "and off again")
    page.free()


## The View menu's Toggle Grid writes the setting behind an open page, and the
## switch follows it rather than showing what it was built with.
func test_the_grid_row_reads_on_after_view_toggle_grid() -> void:
    SaSettings.show_grid = false
    var page := SaDisplayPage.new()
    var row := page.page.row(&"show_grid")
    assert_false(row.reads(), "Built off")
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(SaTestFixtures.make_menu_registries().commands)
    (bar.menu("View") as SaViewMenu).on_id_pressed(SaViewMenu.ID_GRID)
    assert_true(SaSettings.show_grid, "Toggle Grid turned the grid on")
    assert_true(row.reads(), "and the open page's switch reads on")
    bar.free()
    page.free()


## The welcome window's own switch writes the setting behind an open page, and
## the row follows it.
func test_the_welcome_row_reads_off_after_the_windows_switch_is_turned_off() -> void:
    SaSettings.welcome_at_start = true
    var page := SaGeneralPage.new()
    var row := page.page.row(&"welcome_at_start")
    assert_true(row.reads(), "Built on")
    var window := SaWelcomeWindow.new()
    assert_true(window.show_at_start.button_pressed, "The window's switch starts on as well")
    window.show_at_start.button_pressed = false
    assert_false(SaSettings.welcome_at_start, "Turning it off wrote the setting")
    assert_false(row.reads(), "and the open page's row reads off")
    window.free()
    page.free()
