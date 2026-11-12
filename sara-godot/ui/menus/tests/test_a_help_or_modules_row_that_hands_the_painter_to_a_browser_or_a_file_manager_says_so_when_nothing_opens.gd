## A Help or Modules row that hands the painter to a browser
## or a file manager says so when nothing opens, and Report a Problem names
## Take a Note.
##
## Help > Report a Problem must not stay silent on a seat with
## no browser, where the menu would close and nothing say why. `SaMenuCommands.opener`
## holds the call the rows make, so this suite makes it fail, or succeed, and
## reads what the corner was told on `EventBus.paint_refused`. The desktop's
## own opener is never run here, since on a desktop it would open a
## browser: the scenario `report-a-problem-with-no-browser-says-so.json`
## runs it on a seat whose `xdg-open` fails.
extends "res://tests/test_framework.gd"

var _registries: SaRegistries = null
var _said: PackedStringArray = []
var _asked: PackedStringArray = []


func before_each() -> void:
    _registries = SaTestFixtures.make_menu_registries()
    _said.clear()
    _asked.clear()
    EventBus.paint_refused.connect(_hear)


func after_each() -> void:
    if EventBus.paint_refused.is_connected(_hear):
        EventBus.paint_refused.disconnect(_hear)
    SaMenuCommands.opener = SaMenuCommands.desktop_open
    _registries = null


func _hear(line: String) -> void:
    _said.append(line)


## An opener that answers *answer* and keeps what it was asked to open.
func _answering(answer: Error) -> Callable:
    return func(url: String) -> Error:
        _asked.append(url)
        return answer


## The engine's `OS.shell_open` answers OK on Linux before `xdg-open` has run,
## so the rows go through Sara's own opener, which watches it.
func test_the_rows_open_through_sara_s_own_opener() -> void:
    var source := (load("res://ui/menus/sa_menu_commands.gd") as GDScript).source_code
    assert_true(source.contains("static var opener: Callable = desktop_open"), "the seam starts as the desktop opener")
    assert_true(source.contains('OS.create_process("xdg-open"'), "which starts xdg-open itself on Linux")
    assert_true(source.contains("OS.get_process_exit_code(pid) > 0"), "and reads how it ended")


func test_report_a_problem_with_no_browser_gives_the_address_and_names_take_a_note() -> void:
    SaMenuCommands.opener = _answering(FAILED)
    assert_true(_registries.commands.execute(&"help_report"), "Report a Problem runs")
    assert_eq(_asked.size(), 1, "it asked for one address")
    if _asked.is_empty():
        return
    assert_true(_asked[0].begins_with(SaHelpMenu.REPORT_URL + "&"), "the issue form: %s" % _asked[0])
    var version := SaBuildInfo.version_line(SaBuildInfo.read()).uri_encode()
    assert_true(_asked[0].contains("&version=" + version), "with the version filled in")
    assert_true(_asked[0].contains("&system="), "and the system")
    assert_true(_asked[0].contains(RenderingServer.get_video_adapter_name().uri_encode()), "which names the graphics card")
    assert_eq(_said.size(), 1, "and the corner was told once")
    if _said.is_empty():
        return
    assert_true(_said[0].contains(SaHelpMenu.REPORT_URL), "the line writes the issues address out: %s" % _said[0])
    assert_true(_said[0].contains("Take a Note"), "and names Take a Note, which needs no browser")
    assert_true(_said[0].contains("No browser answered"), "and says why nothing opened")


func test_documentation_with_no_browser_names_the_page_and_its_address() -> void:
    SaMenuCommands.opener = _answering(FAILED)
    assert_true(_registries.commands.execute(&"help_documentation"), "Documentation runs")
    assert_eq(_said.size(), 1, "the corner was told once")
    if _said.is_empty():
        return
    assert_true(_said[0].contains(SaModulesMenu.DOCUMENTATION_URL), "the line holds the address: %s" % _said[0])
    assert_false(_said[0].contains("Take a Note"), "Take a Note is for a problem, not for the pages")


func test_the_user_modules_folder_that_is_not_shown_says_where_it_is() -> void:
    SaMenuCommands.opener = _answering(ERR_FILE_NOT_FOUND)
    assert_true(_registries.commands.execute(&"modules_open_folder"), "Open User Modules Folder runs")
    assert_eq(_said.size(), 1, "the corner was told once")
    if _said.is_empty():
        return
    assert_true(_said[0].contains(ModuleLoader.user_modules_path()), "the line names the folder: %s" % _said[0])
    assert_true(_said[0].contains("folder could not be shown"), "and says it was not shown")


func test_a_row_whose_browser_opened_says_nothing() -> void:
    SaMenuCommands.opener = _answering(OK)
    for row: StringName in [&"help_report", &"help_documentation", &"modules_open_folder"]:
        assert_true(_registries.commands.execute(row), "%s runs" % row)
    assert_eq(_asked.size(), 3, "each row asked the opener")
    assert_eq(_said, PackedStringArray(), "and a desktop that opened every one leaves the corner empty")


func test_the_manuals_web_link_says_the_same() -> void:
    SaMenuCommands.opener = _answering(FAILED)
    var manual := SaManualWindow.new()
    manual._on_link("https://example.org/colour")
    manual.free()
    assert_eq(_said.size(), 1, "a web link with no browser tells the corner")
    if not _said.is_empty():
        assert_true(_said[0].contains("https://example.org/colour"), "with the address written out")
