## The Tablet page's tablet driver row says the driver in use now.
##
## The row wrote "In use here: WinTab" once, when the page was declared, and
## went on saying it after a switch to Windows Ink and after Preferences was
## closed and opened again. The list's first entry read a bare lowercase
## "auto". The page here is handed the drivers Windows names and a stand-in
## engine, because the suite runs on Linux where the engine names none.
extends "res://tests/test_framework.gd"

var _host: Node = null
var _page: SaTabletPage = null
var _saved: String
## The stand-in engine's driver in use, a dictionary so the lambdas share it.
var _engine: Dictionary = {}


func before_each() -> void:
    _saved = SaSettings.tablet_driver
    _engine = {"live": "wintab"}
    _host = Node.new()
    _host.name = "Host"
    EventBus.add_child(_host)
    _page = SaTabletPage.new(_windows())
    _host.add_child(_page)


func after_each() -> void:
    SaSettings.tablet_driver = _saved
    if is_instance_valid(_page):
        _page.free()
    if is_instance_valid(_host):
        _host.free()


## The four names the engine gives on Windows with a WinTab driver installed,
## and an engine that resolves `auto` the way `tablet_set_current_driver` does.
func _windows() -> SaTabletDriver:
    var engine := _engine
    return SaTabletDriver.new(
        PackedStringArray(["auto", "winink", "wintab", "dummy"]),
        "wintab",
        func(driver_name: String) -> void: engine["live"] = "winink" if driver_name == "auto" else driver_name,
        func() -> String: return String(engine["live"])
    )


func _row() -> SaPageRow:
    return _page.page.row(SaTabletPage.DRIVER_ROW)


func _hint_on_screen() -> String:
    var hint := _row().line.get_node_or_null(^"Labels/Hint") as Label
    return hint.text if hint != null else ""


func _index_of(driver_name: String) -> int:
    var choices: Array = _row().choices
    for i in choices.size():
        if String(choices[i]["id"]) == driver_name:
            return i
    return -1


func test_the_row_starts_on_the_driver_in_use() -> void:
    assert_not_null(_row(), "the page declares the driver row")
    assert_true(_row().explanation.ends_with("In use here: WinTab."), "'%s'" % _row().explanation)


func test_a_switch_is_said_at_once_without_a_relaunch() -> void:
    _row().drive(_index_of("winink"))
    assert_eq(String(_engine["live"]), "winink", "the engine was switched")
    assert_true(_row().explanation.ends_with("In use here: Windows Ink."), "the row's field, '%s'" % _row().explanation)
    assert_true(_hint_on_screen().ends_with("In use here: Windows Ink."), "and its line, '%s'" % _hint_on_screen())


## Automatic is said as what it resolved to, not as "auto".
func test_a_switch_to_automatic_names_what_it_picked() -> void:
    _row().drive(_index_of("auto"))
    assert_true(_row().explanation.ends_with("In use here: Windows Ink."), "'%s'" % _row().explanation)


## Closing and opening Preferences hides and shows the page. A switch made while
## it was hidden, by another page or the engine's fallback, is read on show.
func test_the_page_shown_again_reads_the_driver_again() -> void:
    _page.hide()
    _engine["live"] = "winink"
    _page.show()
    assert_true(_row().explanation.ends_with("In use here: Windows Ink."), "'%s'" % _row().explanation)
    assert_true(_hint_on_screen().ends_with("In use here: Windows Ink."), "and on screen, '%s'" % _hint_on_screen())


func test_every_entry_is_capitalised() -> void:
    var labels: Array = []
    for entry: Dictionary in _row().choices:
        var label := String(entry["label"])
        labels.append(label)
        assert_eq(label.left(1), label.left(1).to_upper(), "'%s' starts on a capital" % label)
    assert_eq(labels, ["Automatic (Windows Ink)", "Windows Ink", "WinTab", "None"], "every entry a painter can read")


## Without Windows Ink on offer, automatic is WinTab, and a name the table does
## not know is still raised.
func test_automatic_names_wintab_where_ink_is_missing_and_an_unknown_name_is_raised() -> void:
    var driver := SaTabletDriver.new(PackedStringArray(["auto", "wintab", "x11"]), "wintab")
    assert_eq(driver.label_of("auto"), "Automatic (WinTab)", "auto picks WinTab here")
    assert_eq(driver.label_of("x11"), "X11", "an unknown name is not shown lowercase")
    assert_eq(SaTabletDriver.new(PackedStringArray(["auto"]), "auto").label_of("auto"), "Automatic", "nothing to pick")
