## A WinTab that cannot start says so on the Tablet page's driver row, and
## Sara reads the pen through Windows Ink for the session.
##
## On 4 October the engine logged "WinTab context creation failed." eight
## times, the row still read "In use here: WinTab", and the pen arrived as a
## mouse with no pressure, because Wacom's service was not running. The engine
## says so only in verbose mode, so a helper opens a context the way it does
## and Sara goes by its answer. The page here is handed a stand-in engine, as
## the suite has no tablet.
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
    _host.name = "WinTabHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaTabletDriver._falls_back("")
    SaSettings.tablet_driver = _saved
    if is_instance_valid(_page):
        _page.free()
    if is_instance_valid(_host):
        _host.free()


## The page over a stand-in Windows engine whose driver in use is *live*.
func _open_page(live: String) -> SaPageRow:
    _engine["live"] = live
    var engine := _engine
    var driver := SaTabletDriver.new(
        PackedStringArray(["auto", "winink", "wintab", "dummy"]),
        live,
        func(driver_name: String) -> void: engine["live"] = "winink" if driver_name == "auto" else driver_name,
        func() -> String: return String(engine["live"])
    )
    _page = SaTabletPage.new(driver)
    _host.add_child(_page)
    return _page.page.row(SaTabletPage.DRIVER_ROW)


func test_a_wintab_that_failed_is_said_with_the_driver_that_reads_the_pen() -> void:
    SaTabletDriver._falls_back("failed")
    var row := _open_page("winink")
    assert_true(row.explanation.contains("WinTab failed to start"), "'%s'" % row.explanation)
    assert_true(row.explanation.ends_with("In use here: Windows Ink."), "'%s'" % row.explanation)


func test_a_wintab_that_opened_says_nothing_of_a_failure() -> void:
    SaTabletDriver._falls_back("open")
    var row := _open_page("wintab")
    assert_false(row.explanation.contains("failed"), "'%s'" % row.explanation)
    assert_true(row.explanation.ends_with("In use here: WinTab."), "'%s'" % row.explanation)


## A painter who picks Windows Ink by hand is not told WinTab failed.
func test_ink_picked_by_hand_says_nothing_of_a_failure() -> void:
    SaTabletDriver._falls_back("")
    var row := _open_page("winink")
    assert_false(row.explanation.contains("failed"), "'%s'" % row.explanation)


## Only a context that would not open sends the session to Windows Ink.
func test_no_other_answer_goes_to_ink() -> void:
    for answer: String in ["open", "absent", "unknown", ""]:
        assert_false(SaTabletDriver._falls_back(answer), "'%s' leaves the driver alone" % answer)
        assert_eq(SaTabletDriver.wintab_found, answer, "and is kept")


## The helper runs end to end on Windows: a DLL that is not there is absent.
func test_the_helper_answers_for_a_dll_that_is_not_there() -> void:
    if OS.get_name() != "Windows":
        skip("the helper is PowerShell's, so it runs on Windows only")
        return
    var missing := ProjectSettings.globalize_path("res://no-such-folder/wintab32.dll")
    assert_eq(SaTabletDriver._ask(missing), "absent", "a DLL that is not there")
