## The docker rows and the layouts under the Window menu.
##
## The bar is built the way `test_menus.gd` builds one, detached, because a
## `Window` added to the scene tree hangs a suite. The docker rows need the UI
## registry and a layout store, which is all `MainDockers` is built with,
## and the test hands it the Window menu's own popup,
## which is the call `SaWindowMenu._add_items` makes in the running app. What a
## detached bar cannot show, the scenario `dockers-under-window.json` shoots
## in the app itself.
extends "res://tests/test_framework.gd"


## The answers `MainDockers` asks of the layout store, all of which a docker
## row press reaches it for. Stubbed rather than real so a press here writes no
## layout file and lists no shipped preset.
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


func _bar() -> TopMenuBar:
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(SaTestFixtures.make_menu_registries().commands)
    return bar


## Two registered dockers with a Window each, and the dockers built over them
## with a stub store. The windows are children of a plain host, which frees
## everything under it at the end of a test.
func _stub() -> Node:
    var host := Node.new()
    var registries := SaRegistries.new()
    for entry: Array in [["StubA", "Stub A"], ["StubB", "Stub B"]]:
        var id := StringName(entry[0])
        var win := Window.new()
        win.name = String(id)
        host.add_child(win)
        registries.ui.register_docker(id, String(entry[1]), func() -> Window: return Window.new(), &"docker_stub")
        registries.ui.set_docker_node(id, win)
    host.add_child(MainDockers.new(registries.ui, StubStore.new()))
    return host


func _dockers(host: Node) -> MainDockers:
    return host.get_node("MainDockers") as MainDockers


## The list's own column, in order: rows, separators and headings alike. The
## same walk `test_menus.gd` does, because a separator and a heading are not
## rows and where they stand is half of what this suite is about.
func _rows(popup: SaChoicePopup) -> Array:
    var rows := []
    var column := popup.get_node_or_null(NodePath("ChoiceBody/ChoiceScroll/ChoiceColumn"))
    if column == null:
        return rows
    for child in column.get_children():
        if child is HSeparator:
            rows.append(["---", -1])
            continue
        if child is Label:
            rows.append([">", (child as Label).text])
            continue
        var row := child as SaChoiceRow
        if row == null:
            continue
        var button := popup.label_button(row.id)
        var text := button.text if button != null else ""
        if popup.check_box(row.id) != null:
            rows.append(["*", text, SaMenu.id_of(row.id)])
        else:
            rows.append([text, SaMenu.id_of(row.id)])
    return rows


func test_the_bar_makes_no_dockers_menu() -> void:
    assert_false(TopMenuBar.MENU_NAMES.has("Dockers"), "Dockers is not one of the bar's menus")
    var bar := _bar()
    assert_false(bar.menus.has("Dockers"), "and the bar makes no popup for it")
    assert_true(bar.menus.has("Window"), "Window is still there")
    bar.free()


## The three window rows keep their own ids, in a range of six hundreds, so that
## the docker rows appended under them can be numbered from zero.
func test_the_window_menu_opens_with_its_own_three_rows() -> void:
    var bar := _bar()
    var rows := _rows(bar.menus["Window"])
    assert_eq(
        rows,
        [
            ["*", "Fullscreen", SaWindowMenu.ID_FULLSCREEN],
            ["---", -1],
            ["New Window for Second Monitor", SaWindowMenu.ID_NEW_SECONDARY],
            ["---", -1],
            ["Move All Dockers to Main Window", SaWindowMenu.ID_GATHER_DOCKERS],
        ],
        "A bar with no app behind it carries the three window rows and nothing else"
    )
    assert_eq(SaWindowMenu.ID_FULLSCREEN, 602, "Fullscreen is clear of the docker rows numbered from zero")
    bar.free()


func test_the_window_menu_carries_a_row_per_docker_and_the_layouts() -> void:
    var bar := _bar()
    var popup: SaChoicePopup = bar.menus["Window"]
    var main := _stub()
    var dockers := _dockers(main)
    dockers.append_menu_rows(popup)

    assert_true(popup.row_ids().has(&"docker_0"), "The first docker has a row")
    assert_true(popup.row_ids().has(&"docker_1"), "and so does the second")
    assert_false(popup.row_ids().has(&"docker_2"), "and there is no third, there being two registered")
    assert_eq(SaMenu.id_of(&"docker_0"), -1, "A docker row is not one of the menu's own item ids")
    assert_true(popup.section_titles().has("Layouts"), "and the layouts keep their own heading below the dockers")
    var labels := popup.row_labels()
    assert_eq(
        labels.slice(3), ["Focus Mode", "Stub A", "Stub B", "No saved layouts"], "Focus Mode, the two dockers, the empty answer"
    )

    var rows := _rows(popup)
    assert_eq(rows.size(), 11, "Three window rows, two gaps, Focus Mode, two dockers, a gap, the Layouts heading and its row")
    # The "Dockers" heading is not among them, because a detached bar has no app
    # to ask and the heading is the Window menu's half of the split: it decides
    # the section is worth opening before it asks for a row to go under it. The
    # scenario shoots the assembled menu in the app, heading and all.
    assert_false(popup.section_titles().has("Dockers"), "A bar with no app behind it opens no docker section")

    main.free()
    bar.free()


func test_pressing_a_docker_row_still_toggles_that_docker() -> void:
    var bar := _bar()
    var popup: SaChoicePopup = bar.menus["Window"]
    var main := _stub()
    var dockers := _dockers(main)
    dockers.dockers_menu = popup
    dockers.boot_finished()
    dockers.append_menu_rows(popup)

    var first: Window = dockers.ui.get_docker_entry(&"StubA")["node"] as Window
    # A new `Window` is visible until something hides it, which is what the
    # layout store does for every docker the painter has closed.
    first.hide()
    assert_false(first.visible, "A docker the layout never opened starts hidden")
    assert_true(popup.press_row(&"docker_0"), "The row is there to press")
    assert_true(first.visible, "and pressing it shows the docker")
    assert_true(popup.press_row(&"docker_0"), "The row is still there")
    assert_false(first.visible, "and a second press puts it away again")

    main.free()
    bar.free()


## The link a detached bar cannot hold: the Window menu is what asks the dockers
## for their rows. A source read, the shape `test_shell_doors.gd` uses for the
## same kind of seam.
func test_the_window_menu_asks_the_dockers_for_their_rows() -> void:
    var source := FileAccess.get_file_as_string("res://ui/menus/window_menu.gd")
    assert_true(
        source.contains("dockers.append_grouped_rows(self)"), "The Window menu appends the docker rows into its own lists"
    )
    assert_true(source.contains('find_child("MainDockers"'), "and reaches the node that owns them by name")
