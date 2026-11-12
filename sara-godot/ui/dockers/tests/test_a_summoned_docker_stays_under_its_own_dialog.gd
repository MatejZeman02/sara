## A summoned docker stays while a window it opened is up.
##
## The Reference docker must not close when toggled by docker under cursor after
## clicking its 'Open' button and leaving it with the mouse to browse the opened
## window for a reference. The leave watches the pointer, and
## a file dialog is a window the pointer has every reason to be in, so the docker
## went back under its own dialog and the files picked had nowhere to land.
##
## Two shapes of that window, and the cases here are one each. A dialog this app
## draws is a `Window` child of the docker and says so through `visible`. A picker
## the platform draws is not a node of the tree at all:
## `SaFilePicker` puts it up through the display server, so the summon asks it
## whether a node of the docker has one waiting, and the case proves an answered
## picker does not hold twice. The platform is a stand-in, so no window goes up.
##
## The windows are never added to a tree, for the capture pitfall page's reason,
## so the summon is driven through its own `step` with the clock handed in, and
## the running app's proof is the scenario named for the unit.
extends "res://tests/test_framework.gd"

static var scratch_layout_path: String = SaDataRoot.path("test_w2_summon_layout.cfg")
const SECTION: String = "ReferenceDocker"
const HOME := Vector2i(1500, 120)
const SIZE := Vector2i(320, 400)
const POINT := Vector2i(700, 500)
## Far enough from the rectangle this suite draws to be past any reach.
const AWAY := Vector2(100, 100)
const REACH: float = 57.6
const DWELL: int = 1000

var _dwell_before: Variant = null
var _platform_before: SaFilePicker.Platform = null


func before_each() -> void:
    _dwell_before = SaSettings.module_preference(SaDockerBorrow.MODULE_ID, SaDockerBorrow.DWELL_KEY)
    SaDockerBorrow.new().dwell_ms = DWELL
    _platform_before = SaFilePicker.platform
    SaFilePicker.platform = StandIn.new()


func after_each() -> void:
    SaSettings.set_module_preference(SaDockerBorrow.MODULE_ID, SaDockerBorrow.DWELL_KEY, _dwell_before)
    var cancelled := 0
    while SaFilePicker.newest() != null and cancelled < 100:
        SaFilePicker.newest().cancel()
        cancelled += 1
    assert_null(SaFilePicker.newest(), "A cancelled picker goes away")
    SaFilePicker.platform = _platform_before
    if FileAccess.file_exists(scratch_layout_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_layout_path))


func _docker(visible: bool) -> Window:
    var win := Window.new()
    win.name = SECTION
    win.position = HOME
    win.size = SIZE
    win.visible = visible
    return win


## A store with the one docker and the file written once from it, which is the
## layout a painter's session left behind.
func _store_with(win: Window) -> DockerLayoutStore:
    var store := DockerLayoutStore.new()
    store.path = scratch_layout_path
    var config := {"node": win, "id": SECTION, "name": "Reference"}
    store.dockers_provider = func() -> Array: return [config]
    store.save(true)
    return store


## A picker a row of the docker asked for, as `ReferenceDocker.open_dialog` asks:
## the platform's own window, which no node of the tree stands for.
func _picker(win: Window) -> SaFilePicker:
    var row := Control.new()
    win.add_child(row)
    return SaFilePicker.open(row, SaFilePicker.Mode.OPEN_FILES, PackedStringArray(), Callable())


func test_a_drawn_dialog_holds_the_docker_until_it_closes() -> void:
    var win := _docker(true)
    var store := _store_with(win)
    var summon := DockerSummon.new(store)
    var dialog := Window.new()
    dialog.name = "RenamePicture"
    dialog.visible = false
    win.add_child(dialog)

    assert_true(summon.summon(win, SECTION, POINT, 10000), "the chord summons the docker")
    assert_false(summon.step(SECTION, AWAY, REACH, 10100), "the pointer past the reach starts the dwell")

    dialog.visible = true
    assert_false(summon.step(SECTION, AWAY, REACH, 20000), "a window the docker opened holds it")
    assert_false(summon.step(SECTION, AWAY, REACH, 60000), "however long the painter browses it")

    dialog.visible = false
    assert_false(summon.step(SECTION, AWAY, REACH, 60100), "the window closed, so the dwell starts again")
    assert_false(summon.step(SECTION, AWAY, REACH, 60900), "and it is a full wait from there")
    assert_true(summon.step(SECTION, AWAY, REACH, 61100), "after which the docker goes back")

    assert_false(store.is_borrowed(SECTION), "nothing is borrowed after the leave")
    assert_eq(win.position, HOME, "and the docker is where the painter left it")

    summon.free()
    win.free()
    store.free()


func test_a_popup_deeper_in_the_docker_counts_and_a_hidden_window_does_not() -> void:
    var win := _docker(true)
    var store := _store_with(win)
    var summon := DockerSummon.new(store)
    var row := Control.new()
    win.add_child(row)
    var menu := PopupMenu.new()
    menu.visible = false
    row.add_child(menu)

    summon.summon(win, SECTION, POINT, 10000)
    assert_false(summon.step(SECTION, AWAY, REACH, 20000), "a hidden popup two levels down holds nothing")

    menu.visible = true
    assert_false(summon.step(SECTION, AWAY, REACH, 30000), "it holds the docker once it is open")
    assert_false(summon.step(SECTION, AWAY, REACH, 60000), "for as long as it is")

    menu.visible = false
    assert_false(summon.step(SECTION, AWAY, REACH, 60000), "and gives it back when it closes")
    assert_true(summon.step(SECTION, AWAY, REACH, 61000), "so the dwell ends a full wait later")

    summon.free()
    win.free()
    store.free()


func test_a_picker_the_platform_draws_holds_the_docker_until_it_returns() -> void:
    var win := _docker(true)
    var store := _store_with(win)
    var summon := DockerSummon.new(store)
    var picker := _picker(win)

    assert_true(summon.summon(win, SECTION, POINT, 10000), "the chord summons the docker")
    assert_true(win.find_children("*", "Window", true, false).is_empty(), "the platform's picker is no window of the tree")

    assert_false(summon.step(SECTION, AWAY, REACH, 20000), "and it holds the docker all the same")
    assert_false(summon.step(SECTION, AWAY, REACH, 60000), "however long the painter browses it")

    picker.answer(true, PackedStringArray(["res://icon.svg"]), 0)
    assert_false(summon.step(SECTION, AWAY, REACH, 60100), "the platform's window has returned, so the dwell starts")
    assert_false(summon.step(SECTION, AWAY, REACH, 60900), "and runs its full length")
    assert_true(summon.step(SECTION, AWAY, REACH, 61100), "after which the docker goes back")

    # The picker answered is off the list, so the second summon is the case that
    # a picker holds once and not forever.
    assert_true(summon.summon(win, SECTION, POINT, 70000), "a second summon takes it out again")
    assert_false(summon.step(SECTION, AWAY, REACH, 70100), "the dwell runs")
    assert_true(summon.step(SECTION, AWAY, REACH, 71100), "to its end")

    summon.free()
    win.free()
    store.free()


func test_a_cancelled_picker_lets_the_docker_go_too() -> void:
    var win := _docker(true)
    var store := _store_with(win)
    var summon := DockerSummon.new(store)
    var picker := _picker(win)

    summon.summon(win, SECTION, POINT, 10000)
    assert_false(summon.step(SECTION, AWAY, REACH, 30000), "the picker holds the docker")

    picker.answer(false, PackedStringArray(), 0)
    assert_false(summon.step(SECTION, AWAY, REACH, 31000), "cancelling it is the window returning as well")
    assert_true(summon.step(SECTION, AWAY, REACH, 32100), "so the docker goes back a dwell later")

    summon.free()
    win.free()
    store.free()


## The platform with a picker and no window.
class StandIn:
    extends SaFilePicker.Platform

    func has_picker() -> bool:
        return true

    func show(_picker: SaFilePicker, _platform_filters: PackedStringArray, _parent_id: int, _answer: Callable) -> void:
        pass
