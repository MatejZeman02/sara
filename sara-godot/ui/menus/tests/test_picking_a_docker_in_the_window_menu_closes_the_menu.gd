## A press on a docker's row in the Window menu toggles the
## docker and closes the list, and a tick in another menu keeps its list open.
##
## The bar is detached, as `test_dockers_under_window.gd` builds it, so the
## Window menu here is one seated over a stub `MainDockers` rather than one that
## finds the node in a running scene. Everything the menu does after it has the
## dockers is its own code, which is what is read. The scenario
## `picking-a-docker-in-the-window-menu-closes-the-menu.json` reads the
## same in the app.
extends "res://tests/test_framework.gd"


## The answers `MainDockers` asks of the layout store, stubbed so a press here
## writes no layout file and lists no shipped preset.
class StubStore:
    extends DockerLayoutStore

    func save(_by_painter: bool = false) -> void:
        pass

    func fork_for_painter_edit() -> String:
        return ""

    func reapply_deferred(_win: Window, _section: String) -> void:
        pass

    func list_presets() -> Array[String]:
        return []

    func current_preset() -> String:
        return ""


## A Window menu handed its dockers, where the app's finds them in the scene.
class SeatedWindowMenu:
    extends SaWindowMenu

    var seated: MainDockers

    func _init(menu_popup: SaChoicePopup, dockers: MainDockers) -> void:
        super(menu_popup)
        seated = dockers

    func _main_dockers() -> MainDockers:
        return seated


func _bar() -> TopMenuBar:
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(SaTestFixtures.make_menu_registries().commands)
    return bar


## One registered docker, Undo History, with a Window under a plain host that
## frees everything under it at the end of a test.
func _host() -> Node:
    var host := Node.new()
    var registries := SaRegistries.new()
    var win := Window.new()
    win.name = "History"
    host.add_child(win)
    registries.ui.register_docker(&"History", "Undo History", func() -> Window: return Window.new(), &"docker_stub")
    registries.ui.set_docker_node(&"History", win)
    host.add_child(MainDockers.new(registries.ui, StubStore.new()))
    return host


func test_a_docker_row_shows_or_hides_its_docker_and_closes_the_list() -> void:
    var popup := SaChoicePopup.new()
    var host := _host()
    var dockers := host.get_node("MainDockers") as MainDockers
    dockers.dockers_menu = popup
    dockers.boot_finished()
    var menu := SeatedWindowMenu.new(popup, dockers)
    menu.populate()

    var history: Window = dockers.ui.get_docker_entry(&"History")["node"] as Window
    history.hide()
    assert_eq(SaMenu.labels_of(popup).has("Undo History"), true, "The Window menu carries the Undo History row")

    # A stub docker no kind names goes under Other, the last kind's submenu.
    var other := MainDockers.FIRST_KIND_ROW + MainDockers.KINDS.size() - 1
    popup.visible = true
    var list := SaMenu.open_group(menu.popup, other)
    list.visible = true
    assert_true(list.press_row(&"docker_0"), "The row is there to press, on its kind's submenu")
    assert_true(history.visible, "Pressing it shows the docker")
    assert_false(list.visible, "and the submenu is gone")
    assert_false(popup.visible, "and the list behind it with it")

    menu.populate()
    popup.visible = true
    list = SaMenu.open_group(menu.popup, other)
    list.visible = true
    assert_true(list.press_row(&"docker_0"), "The row is there again in the list opened anew")
    assert_false(history.visible, "Pressing it again hides the docker")
    assert_false(popup.visible, "and the list is gone again")

    popup.visible = true
    assert_true(popup.press_row(MainDockers.FOCUS_MODE_ROW), "Focus Mode is a row of the same list")
    assert_false(popup.visible, "and a press on it closes the list as a docker's does")
    if SaFocusMode.active:
        dockers.toggle_all_dockers()

    host.free()
    popup.free()


func test_a_tick_in_the_view_menu_keeps_its_list_open() -> void:
    var bar := _bar()
    var popup: SaChoicePopup = bar.menus["View"]
    var row := SaMenu.key(SaViewMenu.ID_WINDOW_CONTROLS)
    popup = SaMenu.list_holding(popup, row)
    assert_true(popup.check_box(row) != null, "Show Window Buttons is a tick row of the View menu")
    popup.visible = true
    var before := popup.is_checked(row)
    assert_true(popup.press_row(row), "The tick is there to press")
    assert_eq(popup.is_checked(row), not before, "the press turns it")
    assert_true(popup.visible, "and the list stays open for the next tick")
    popup.press_row(row)
    bar.free()
