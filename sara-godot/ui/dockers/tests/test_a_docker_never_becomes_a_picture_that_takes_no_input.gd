## Colour Picker, dragged,
## summoned and given back, ended as a picture that took no input and that
## Windows listed as a window not visible.
##
## The replay through the door with the subwindows off,
## `scenarios/a-docker-never-becomes-a-picture-that-takes-no-input.json`,
## did not reproduce it on Linux. What this suite holds is what reading the
## summon's hide and show found: the check that puts the next sighting in the
## log, and the one path of Sara's own that hid a docker still out on a summon,
## its close, which left the borrow behind to show the closed docker again on
## its way home. The windows are built and never put in a tree, because a
## `Window` in a tree maps a real OS window and hangs a headless run.
extends "res://tests/test_framework.gd"

const POINT := Vector2i(700, 500)
const HOME := Vector2i(1500, 120)
const AWAY := Vector2(100, 100)
const REACH: float = 57.6


## The layout store `MainDockers` is built with, with the answers that write a
## file or wait on a compositor stubbed, as `test_dockers_under_window.gd`
## stubs them.
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


var _dwell_before: Variant = null


func before_each() -> void:
    _dwell_before = SaSettings.module_preference(
        SaDockerBorrow.MODULE_ID, SaDockerBorrow.DWELL_KEY, SaDockerBorrow.DEFAULT_DWELL_MS
    )
    SaDockerBorrow.new().dwell_ms = 1000


func after_each() -> void:
    SaSettings.set_module_preference(SaDockerBorrow.MODULE_ID, SaDockerBorrow.DWELL_KEY, _dwell_before)


## One registered docker, shown at its home in the layout, and the dockers node
## built over it. The window is a child of a plain host, which frees everything
## under it at the end of a test.
func _stub() -> Node:
    var host := Node.new()
    var registries := SaRegistries.new()
    var win := Window.new()
    win.name = "ColorDocker"
    win.position = HOME
    win.size = Vector2i(280, 480)
    host.add_child(win)
    registries.ui.register_docker(&"ColorDocker", "Colour Picker", func() -> Window: return Window.new(), &"docker_stub")
    registries.ui.set_docker_node(&"ColorDocker", win)
    host.add_child(MainDockers.new(registries.ui, StubStore.new()))
    return host


func _dockers(host: Node) -> MainDockers:
    return host.get_node("MainDockers") as MainDockers


func _section(dockers: MainDockers) -> String:
    return DockerLayoutStore.section_for(dockers.get_docker_config()[0])


func test_a_summoned_docker_hidden_by_something_else_is_named() -> void:
    var host := _stub()
    var dockers := _dockers(host)
    var win := dockers.get_docker_config()[0]["node"] as Window
    var section := _section(dockers)
    var summon: DockerSummon = dockers.summon

    assert_eq(summon.hidden_while_counted(win, section), "", "a docker shown in the layout is shown")
    assert_true(summon.summon(win, section, POINT, 10000), "the chord summons it")
    assert_eq(summon.hidden_while_counted(win, section), "", "out on a summon and shown, nothing is wrong")

    win.visible = false
    var fault := summon.hidden_while_counted(win, section)
    assert_true(fault.contains(section), "hidden while it is out, the check names the docker: %s" % fault)
    assert_true(fault.contains("summon"), "and says the summon still holds it")

    win.visible = true
    summon.send_back(section)
    assert_eq(summon.hidden_while_counted(win, section), "", "given back, nothing holds it any more")
    win.visible = false
    assert_eq(summon.hidden_while_counted(win, section), "", "so the layout hiding it afterwards is no fault")
    host.free()


## A docker with no OS window of its own, which a detached window and an
## embedded one both are, is never asked about the display server's list.
func test_a_window_with_no_os_window_is_not_asked_about_one() -> void:
    var host := _stub()
    var dockers := _dockers(host)
    var win := dockers.get_docker_config()[0]["node"] as Window
    assert_false(DockerLayoutStore.owns_os_window(win), "a detached window owns no OS window")
    assert_eq(dockers.summon.hidden_while_counted(win, _section(dockers)), "", "and is not a fault for lacking one")
    host.free()


## The docker's own close, on a docker out on a summon. It hid the
## window and leave the borrow, so the leave a second later gave the docker
## back with the visibility it had before the summon and showed again the
## docker the painter had just closed.
func test_closing_a_summoned_docker_sends_it_back_and_it_stays_closed() -> void:
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(SaTestFixtures.make_menu_registries().commands)
    var popup: SaChoicePopup = bar.menus["Window"]
    var host := _stub()
    var dockers := _dockers(host)
    dockers.dockers_menu = popup
    dockers.boot_finished()
    dockers.append_menu_rows(popup)
    var win := dockers.get_docker_config()[0]["node"] as Window
    var section := _section(dockers)
    var summon: DockerSummon = dockers.summon
    # Shut in the layout, so the close that sends it home leaves it shut. A
    # docker shown in the layout goes home shown.
    win.visible = false

    assert_true(summon.summon(win, section, POINT, 10000), "summoned from the far side")
    assert_true(dockers.layout_store.is_borrowed(section), "and out on a borrow")
    win.close_requested.emit()
    assert_false(win.visible, "the close sends it home shut")
    assert_false(dockers.layout_store.is_borrowed(section), "and no borrow outlives it")
    assert_eq(summon.hidden_while_counted(win, section), "", "so the check has nothing to say about Sara's own close")
    assert_eq(win.position, HOME, "it went home before it was hidden")

    assert_false(summon.step(section, AWAY, REACH, 20000), "the leave has nothing to send back")
    assert_false(summon.step(section, AWAY, REACH, 21500), "nor a full dwell later")
    assert_false(win.visible, "and the closed docker stays closed")
    host.free()
    bar.free()
