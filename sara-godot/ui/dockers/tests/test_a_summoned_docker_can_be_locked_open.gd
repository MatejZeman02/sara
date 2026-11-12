## The lock on a summoned docker: a docker a painter holds open stays while the
## pointer walks away, the button on its own bar is what sets the hold, and
## unlocking hands it back to the ordinary leave.
##
## A summoned docker can be spawned and locked. The running app's proof is `scenarios/a-summoned-docker-can-be-locked-open.json`.
## The windows here are built and never put in a tree, for the capture pitfall
## page's reason: a `DockerWindow` in a tree maps a real OS window and hangs a
## headless run. `@tool` because the fixture below extends `DockerWindow`, which
## is a tool script, and the annotation is file-wide. No suite is ever a node in
## a scene, so nothing here runs in the editor.
@tool
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

static var scratch_layout_path: String = SaDataRoot.path("test_r3_summon_layout.cfg")
const SECTION: String = "LayersDocker"
const HOME := Vector2i(1500, 120)
const SIZE := Vector2i(300, 400)
const POINT := Vector2i(700, 500)
## Far enough from any rectangle this suite draws to be past every reach.
const AWAY := Vector2(100, 100)
const REACH: float = 57.6
const DWELL: int = 1000


## A docker with a drag bar and a title in it, which is all the frame's own
## button building asks for: `_init_docker` and the one child are what a real
## docker's `_init` leaves behind, and the same calls `test_d3` makes.
class BarredDocker:
    extends DockerWindow

    func _init() -> void:
        _init_docker("BarredDocker", "Barred", Vector2i(200, 160), Vector2i(80, 60))
        wrap_controls = false
        drag_handle = PanelContainer.new()
        drag_handle.add_child(Label.new())
        add_child(drag_handle)
        _build_hide_button()


var _dwell_before: Variant = null


func before_each() -> void:
    _dwell_before = SaSettings.module_preference(
        SaDockerBorrow.MODULE_ID, SaDockerBorrow.DWELL_KEY, SaDockerBorrow.DEFAULT_DWELL_MS
    )
    SaDockerBorrow.new().dwell_ms = DWELL


func after_each() -> void:
    SaSettings.set_module_preference(SaDockerBorrow.MODULE_ID, SaDockerBorrow.DWELL_KEY, _dwell_before)
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
    var config := {"node": win, "id": SECTION, "name": "Layers"}
    store.dockers_provider = func() -> Array: return [config]
    store.save(true)
    return store


func test_a_locked_docker_waits_out_the_dwell_and_unlocking_hands_it_back() -> void:
    var win := _docker(false)
    var store := _store_with(win)
    var summon := DockerSummon.new(store)

    assert_true(summon.summon(win, SECTION, POINT, 10000), "the chord summons the docker")
    SaDockerLock.set_locked(win, true)
    assert_true(SaDockerLock.is_locked(win), "and the lock is on it")
    assert_true(store.is_borrowed(SECTION), "on a borrow")

    assert_false(summon.step(SECTION, AWAY, REACH, 20000), "a locked docker waits for nothing")
    assert_false(summon.step(SECTION, AWAY, REACH, 90000), "however long the pointer is away")
    assert_true(store.is_borrowed(SECTION), "and it is still out")
    assert_true(win.visible, "shown")
    assert_eq(store.stored_positions().get(SECTION), HOME, "with the layout still holding the painter's position")

    SaDockerLock.set_locked(win, false)
    assert_false(SaDockerLock.is_locked(win), "unlocked")
    assert_false(summon.step(SECTION, AWAY, REACH, 90100), "the dwell starts afresh from the unlock")
    assert_false(summon.step(SECTION, AWAY, REACH, 90500), "and waits it out")
    assert_true(summon.step(SECTION, AWAY, REACH, 91500), "a full dwell away sends it back")
    assert_false(store.is_borrowed(SECTION), "nothing is borrowed after the leave")
    assert_false(win.visible, "back to shut, where the summon found it")
    assert_eq(win.position, HOME, "at the painter's own rectangle")

    summon.free()
    win.free()
    store.free()


## The frame's half: the bar carries the button, it is offered only while the
## docker is out, and a press is what turns the hold on and off.
func test_the_button_on_the_bar_holds_the_docker_and_lets_it_go() -> void:
    var docker := BarredDocker.new()

    assert_not_null(docker.lock_button, "the drag bar carries a lock button")
    assert_false(docker.lock_button.visible, "which a docker that is not out does not show")
    assert_false(SaDockerLock.is_locked(docker), "and nothing is locked yet")

    SaDockerLock.offer(docker, true)
    assert_true(docker.lock_button.visible, "offered, and the button is on the bar")

    docker.lock_button.pressed.emit()
    assert_true(SaDockerLock.is_locked(docker), "a press holds the docker")
    assert_true(docker.lock_button.button_pressed, "and the button says so")
    assert_eq(
        docker.lock_button.tooltip_text,
        TranslationServer.translate(SaDockerLock.HOLD_TOOLTIP),
        "with the tooltip that says what the state is"
    )

    docker.lock_button.pressed.emit()
    assert_false(SaDockerLock.is_locked(docker), "a second press lets it go")
    assert_false(docker.lock_button.button_pressed, "and the button follows")

    docker.lock_button.pressed.emit()
    assert_true(SaDockerLock.is_locked(docker), "so a press after that holds it again")
    SaDockerLock.offer(docker, false)
    assert_false(docker.lock_button.visible, "the button goes with the borrow")
    SaDockerLock.forget(docker)
    assert_false(SaDockerLock.is_locked(docker), "and what the summon sends back leaves no lock behind")

    docker.free()


## A docker something closed is not held open, and the leave every docker has
## takes it back.
func test_a_docker_that_closed_forgets_its_lock() -> void:
    var win := _docker(false)
    var store := _store_with(win)
    var summon := DockerSummon.new(store)

    summon.summon(win, SECTION, POINT, 10000)
    SaDockerLock.set_locked(win, true)
    win.hide()
    assert_false(summon.step(SECTION, AWAY, REACH, 90000), "a closed docker is not held open")
    assert_false(SaDockerLock.is_locked(win), "its lock went with the close")

    assert_false(summon.step(SECTION, AWAY, REACH, 90100), "and the ordinary dwell starts over it")
    assert_true(summon.step(SECTION, AWAY, REACH, 92000), "which sends the borrow back")

    # The other way a summoned docker closes, its own chord twice within the
    # second, takes the lock with it as well.
    summon.summon(win, SECTION, POINT, 30000)
    SaDockerLock.set_locked(win, true)
    assert_true(summon.summon(win, SECTION, POINT, 30400), "the second press answers")
    assert_false(store.is_borrowed(SECTION), "and closes the docker")
    assert_false(SaDockerLock.is_locked(win), "with the lock forgotten")

    summon.free()
    win.free()
    store.free()


func test_the_chord_with_ctrl_summons_the_docker_locked() -> void:
    var registries := Fixtures.make_registries()
    var win := _docker(false)
    var store := _store_with(win)
    var summon := DockerSummon.new(store)
    var summoned: Array = []
    SaAppCommands.register_all(
        registries,
        func(_docker_id: StringName) -> void: pass,
        Callable(),
        func(docker_id: StringName, locked: bool) -> void:
            summoned.append([docker_id, locked])
            summon.summon(win, SECTION, POINT, 10000, locked)
    )

    var descriptor := registries.commands.get_descriptor(SaAppCommands.locked_summon_id(&"docker_layers"))
    assert_not_null(descriptor, "the locked summon is registered beside the plain one")
    assert_eq(
        SaCommandRegistry.format_events(descriptor.default_events), "Ctrl+Alt+Shift+T", "on the summon chord with Ctrl held"
    )
    assert_eq(String(descriptor.category), "docker", "under the dockers on the Keyboard Shortcuts page")
    assert_eq(
        SaShortcutStore.chords_for(SaAppCommands.locked_summon_id(&"docker_layers")),
        ["Ctrl+Alt+Shift+T"] as Array[String],
        "and the InputMap holds it"
    )

    var event := InputEventKey.new()
    event.keycode = KEY_T
    event.physical_keycode = KEY_T
    event.ctrl_pressed = true
    event.shift_pressed = true
    event.alt_pressed = true
    event.pressed = true
    assert_true(registries.commands.try_handle_input(event), "the chord is consumed by the command it belongs to")
    assert_eq(summoned, [[&"LayersDocker", true]], "which asks its door for a locked summon")
    assert_true(store.is_borrowed(SECTION), "the docker is out")
    assert_true(SaDockerLock.is_locked(win), "held open")

    summon.free()
    win.free()
    store.free()
