## Help opens the welcome window again.
##
## The window is reachable again from Help, so the row is one
## id, one entry above Keyboard Shortcuts and one command, `help_welcome`, that
## emits the signal the boot emits. The window itself is `MainDialogs`', which
## builds it on first ask and keeps it, so this suite holds that the menu asks
## rather than building a second surface.
##
## Built detached and `_ready()`ed by hand, the way `test_settings_menu.gd`
## builds its bar: a popup is a `Window`, and a bar in the tree hangs a headless
## run. The press is `emit.call_deferred`, which nothing here waits for: a test
## that awaits drops every assertion after the await, and the claim
## that needs a frame is `scenarios/help-reopens-the-welcome-window.json`,
## which presses the row and reads the welcome window back in the dump.
extends "res://tests/test_framework.gd"

var _bar: TopMenuBar = null
var _menu: SaHelpMenu = null


func before_each() -> void:
    _bar = TopMenuBar.new()
    _bar._ready()
    var note_mode := SaNoteMode.new()
    _bar.add_child(note_mode)
    _bar.bind_commands(SaTestFixtures.make_menu_registries(note_mode).commands)
    _menu = _bar.menu("Help") as SaHelpMenu


func after_each() -> void:
    _menu = null
    if _bar != null:
        _bar.free()
        _bar = null


## Documentation's 502 left with its row and no row took the
## number, so the four ids left keep theirs.
func test_the_new_id_is_505_and_the_four_before_it_are_unmoved() -> void:
    assert_eq(SaHelpMenu.ID_WELCOME, 505, "505 was free, so nothing a stored order holds has to move")
    assert_eq(
        [SaHelpMenu.ID_ABOUT, SaHelpMenu.ID_SHORTCUTS, SaHelpMenu.ID_REPORT, SaHelpMenu.ID_NOTE],
        [500, 501, 503, 504],
        "and the four ids the menu still has keep their numbers"
    )


## Nine rows, with Colour Spaces under the Manual, Documentation and Connect an
## Agent in the Develop section of Modules, and the Display and Tablet rows
## grouped with Keyboard Shortcuts above About. The table in `test_menus.gd`
## holds the whole menu, so this reads the ids alone and leaves the labels to
## it. The Manual comes first, under the heading of the ways to learn.
func test_the_manual_is_the_first_of_nine_rows() -> void:
    assert_not_null(_menu, "The bar builds the Help menu")
    if _menu == null:
        return
    var ids: Array[int] = []
    for row_id: StringName in _menu.popup.row_ids():
        ids.append(SaMenu.id_of(row_id))
    assert_eq(ids, [506, 505, 510, 503, 504, 508, 509, 501, 500], "the Manual stands first and About last")


## The deferred half, read the way the other menu suites read their own: the emit is not
## awaited, so what is asserted is that the row asks on the bus the boot asks on
## and that `MainDialogs` answers it there.
func test_a_press_asks_for_the_window_rather_than_building_one() -> void:
    var source := FileAccess.get_file_as_string("res://ui/menus/sa_menu_commands.gd")
    assert_false(source.is_empty(), "The file the menu's commands live in is readable")
    assert_true(
        source.contains("_emit_later.bind(EventBus.welcome_requested)"),
        "The Welcome command emits the signal that opens the window"
    )
    assert_true(source.contains("request.emit.call_deferred()"), "deferred out of the popup's handler")
    assert_false(source.contains("SaWelcomeWindow"), "and builds no window of its own, which would be a second welcome surface")
    var dialogs := FileAccess.get_file_as_string("res://ui/main/main_dialogs.gd")
    assert_true(
        dialogs.contains("EventBus.welcome_requested.connect(open_welcome)"),
        "MainDialogs listens for the request and builds the window on first ask"
    )
