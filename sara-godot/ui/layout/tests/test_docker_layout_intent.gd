## Where a docker is, versus where the user put it.
extends "res://tests/test_framework.gd"

const HOST_LARGE := Vector2i(1200, 800)
const HOST_SMALL := Vector2i(500, 400)
const DOCKER_SIZE := Vector2i(200, 150)
const CHOSEN := Vector2i(900, 600)

var _root: Node = null
var _viewport: SubViewport = null
var _host: Control = null
var _docker: Window = null
var _store: DockerLayoutStore = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _root = Node.new()
    _root.name = "DockerIntentTestHost"
    EventBus.add_child(_root)

    _viewport = SubViewport.new()
    _viewport.size = HOST_LARGE
    _viewport.gui_embed_subwindows = true
    _root.add_child(_viewport)

    _host = Control.new()
    _host.set_anchors_preset(Control.PRESET_FULL_RECT)
    _viewport.add_child(_host)

    _docker = Window.new()
    _docker.size = DOCKER_SIZE
    _host.add_child(_docker)
    _docker.position = CHOSEN

    _store = DockerLayoutStore.new()
    _store.path = SaDataRoot.path("test_docker_intent.cfg")
    _store.dockers_provider = func() -> Array: return [{"name": "Probe", "node": _docker}]
    _store.save_allowed = func() -> bool: return true
    _root.add_child(_store)


func after_each() -> void:
    if _root != null:
        _root.free()
        _root = null
    if FileAccess.file_exists(SaDataRoot.path("test_docker_intent.cfg")):
        DirAccess.remove_absolute(SaDataRoot.path("test_docker_intent.cfg"))


## Shrinking the window pushes a docker inward so it stays reachable, and growing
## it again has to put the docker back.
##
## The clamp is Godot's and it is right on its own. What was wrong is that the
## clamped position was then saved as though the user had dragged it there, so the
## dockers ended up stranded in the middle of the canvas and stayed there.
func test_a_docker_pushed_in_by_a_shrink_comes_back_when_there_is_room() -> void:
    _store.save()
    _viewport.size = HOST_SMALL
    # What the host does when there is no longer room for the chosen position.
    _docker.position = Vector2i(HOST_SMALL - DOCKER_SIZE)
    _store.save()

    _viewport.size = HOST_LARGE
    _store.reflow_to_host()
    assert_eq(_docker.position, CHOSEN, "Back where the user left it, not where the shrink put it")


## A move the host had room for is the user's, and is kept.
func test_a_docker_the_user_moves_stays_moved() -> void:
    _store.save()
    var moved := Vector2i(300, 200)
    _docker.position = moved
    _store.save()

    _store.reflow_to_host()
    assert_eq(_docker.position, moved, "A position the host had room for is a choice, and it sticks")

    _viewport.size = HOST_SMALL
    _store.reflow_to_host()
    _viewport.size = HOST_LARGE
    _store.reflow_to_host()
    assert_eq(_docker.position, moved, "and it survives a shrink and a grow")


## A drag to a position the host has no room for is still the painter's.
##
## The geometric guess above is the right rule when nobody knows whose doing a
## position is, and it is the wrong one the moment somebody does. A docker
## dragged past the left edge has a remembered position that no longer fits, so
## every later save read the live position as a reflow and dropped it: the
## docker's intent froze where the first off-host drag left it, and the settle
## loop then put the window back there once a frame for sixty frames. On the
## running app four drags of the Minimap left it where the second one put it.
##
## `save(true)` is the painter's own save, which `docker_layout_changed` is
## emitted by the drag handle and the resizer alone to mark.
func test_a_drag_the_host_has_no_room_for_is_still_the_painters() -> void:
    _store.save()
    var off_host := Vector2i(-400, 200)
    _docker.position = off_host
    _store.save(true)
    assert_eq(_store.value_for("Probe", "position", Vector2i()), off_host, "The store follows the painter off the edge")

    # The drag back, which is the one a store could drop: the remembered
    # position no longer fits, so the geometric rule called this a reflow.
    var back := Vector2i(300, 200)
    _docker.position = back
    _store.save(true)
    assert_eq(_store.value_for("Probe", "position", Vector2i()), back, "and follows it back again")

    _store.reflow_to_host()
    assert_eq(_docker.position, back, "so a reflow leaves it where the painter last put it")


## The same pair of saves without the painter's mark keeps the old rule, which is
## what carries a docker back when the window grows.
##
## The freeze needs two saves and the second is the one that shows it. The first
## takes the off-host position, because the rule asks whether the *remembered*
## position fits and at that point the remembered one is the one on the host. The
## second asks the same question of an off-host memory, gets no, and reads the
## live position as the app's doing whatever it is. That is the whole defect and
## it is right in every case but a drag.
func test_a_move_nobody_claims_is_still_read_as_a_reflow() -> void:
    _store.save()
    var off_host := Vector2i(-400, 200)
    _docker.position = off_host
    _store.save()
    assert_eq(_store.value_for("Probe", "position", Vector2i()), off_host, "The first save takes it, the memory having fitted")

    _docker.position = Vector2i(300, 200)
    _store.save()
    assert_eq(
        _store.value_for("Probe", "position", Vector2i()),
        off_host,
        "and the second keeps the memory, because an off-host memory reads every later move as a reflow"
    )


## A painter's save leaves a docker the shrink pushed its memory. The
## save a show or a close of another docker makes is the painter's, and it must
## not take every docker's live position as chosen, or one docker opened in a
## small window strands every pushed one where the shrink left it.
func test_a_painters_save_leaves_a_pushed_docker_its_memory() -> void:
    _store.save()
    _viewport.size = HOST_SMALL
    _store.reflow_to_host()
    assert_true(_docker.position != CHOSEN, "The shrink moved it in")
    _store.save(true)

    _viewport.size = HOST_LARGE
    _store.reflow_to_host()
    assert_eq(_docker.position, CHOSEN, "and a painter's save made while it was pushed did not make that the choice")


## A reflow leaves a docker the painter put over the bar where it is, the
## store's `top_inset` notwithstanding, since dockers may go anywhere.
func test_a_reflow_leaves_a_docker_over_the_bar_where_it_was_put() -> void:
    _store.top_inset = func() -> int: return 65
    _docker.position = Vector2i(300, 10)
    _store.save(true)
    _store.reflow_to_host()
    assert_eq(_docker.position, Vector2i(300, 10), "A docker over the bar stays over it")

    _viewport.size = Vector2i(500, 180)
    _store.reflow_to_host()
    assert_eq(_docker.position, Vector2i(300, 10), "and so it does on a host too short for the whole docker")


## While there is not enough room, the docker is fitted onto the host as a
## shipped layout's is: its distance from the right edge kept,
## since it stands in the right half, and its foot above the status line.
func test_a_docker_stays_inside_a_host_too_small_for_it() -> void:
    _store.save()
    _viewport.size = HOST_SMALL
    _store.reflow_to_host()

    var gap := HOST_LARGE.x - CHOSEN.x - DOCKER_SIZE.x
    assert_eq(_docker.position.x + _docker.size.x, HOST_SMALL.x - gap, "Kept %d from the right edge" % gap)
    var line := HOST_SMALL.y - SaDockerLayoutRefit.status_rows_in(1.0)
    assert_eq(_docker.position.y + _docker.size.y, line, "with its foot on the status line rather than off the window")
    assert_true(_docker.position.x >= 0 and _docker.position.y >= 0, "and never outside the other two edges")


## An embedded subwindow hands back the id of the real window it is drawn into.
##
## This is the whole of the 2x2 collapse. `_settle_against_compositor` checked for
## a valid window id before talking to the DisplayServer, which reads as "does this
## window exist to the OS". It does not: an embedded subwindow has no OS window of
## its own and reports its host's id, so geometry meant for a docker was applied to
## the main window.
##
## It stayed hidden because Sara starts maximised and a maximised window ignores a
## size change. Unmaximised, the settle loop walked the main window down to a
## docker's size and kept going: 900x560, 50x64, 26x32, 2x2, one step per pass.
##
## Hosted under the root rather than under the SubViewport the other tests use,
## because a SubViewport is not a window and a child of one reports -1, which is
## the answer the old check wanted and not the one the real app gives.
func test_an_embedded_window_reports_the_id_of_the_window_it_is_drawn_into() -> void:
    var root: Window = (Engine.get_main_loop() as SceneTree).root
    var previous := root.gui_embed_subwindows
    root.gui_embed_subwindows = true

    var docker := Window.new()
    docker.size = DOCKER_SIZE
    _root.add_child(docker)

    assert_true(docker.is_embedded(), "Embedded, like every docker Sara shows")
    assert_eq(docker.get_window_id(), root.get_window_id(), "and it reports the main window's id, not its own")
    assert_true(docker.get_window_id() != DisplayServer.INVALID_WINDOW_ID, "A valid id, which is what made the old check useless")
    assert_false(DockerLayoutStore.owns_os_window(docker), "so it must not be handed to the DisplayServer")

    docker.free()
    root.gui_embed_subwindows = previous


## A real top-level window still is one, or the settle loop would stop working for
## the case it was written for.
func test_a_top_level_window_still_owns_one() -> void:
    var root: Window = (Engine.get_main_loop() as SceneTree).root
    assert_false(root.is_embedded(), "The root is nobody's subwindow")
    assert_true(DockerLayoutStore.owns_os_window(root), "and the DisplayServer knows about it")
    assert_false(DockerLayoutStore.owns_os_window(null), "A window that is not there owns nothing")
