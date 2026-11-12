## A docker shown by its Window menu row or its chord lands with
## its whole frame inside the host, moved as little as possible.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Undo History was placed at y 1000, and ticking it gave a docker whose
## title alone was on screen. `toggle_docker` showed a docker and had the store
## put it back where it was stored, with no fit to the window, and the store's
## settle loop re-asserted that place for sixty frames. A summon was fitted
## already, through the borrow. Now the show fits the stored place and notes the
## fitted one in the store before anything re-asserts, so a stored place off the
## window from an older profile is mended at the next show, and the save the
## tick makes writes it to the file.
##
## The window is built and never put in a tree, because a `Window` in a tree
## maps a real OS window and hangs the run, which `test_a_docker_never_becomes_a_picture_that_takes_no_input.gd`
## says too. So its host is the screen's usable rectangle, which the offscreen
## gate gives as the 1920 by 1080 of its compositor, and the case says so and
## stops where a machine gives none.
extends "res://tests/test_framework.gd"

const SECTION := "UndoDocker"
const SIZE := Vector2i(240, 340)

static var scratch_layout_path: String = SaDataRoot.path("test_n21_window_menu_fit.cfg")


## The layout store with the answers that fork a preset stubbed, as
## `test_dockers_under_window.gd` stubs them, and everything else real: what it
## holds, what it re-asserts and what it writes are the claim.
class NoForkStore:
    extends DockerLayoutStore

    func fork_for_painter_edit() -> String:
        return ""

    func list_presets() -> Array[String]:
        return []

    func current_preset() -> String:
        return ""


func after_each() -> void:
    if FileAccess.file_exists(scratch_layout_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_layout_path))


## One registered docker, hidden, with its stored place *stored* in a layout file
## as an older profile would have left it, and the dockers node built over it.
func _stub(stored: Vector2i) -> Node:
    var cfg := ConfigFile.new()
    cfg.set_value(SECTION, "position", stored)
    cfg.set_value(SECTION, "size", SIZE)
    cfg.set_value(SECTION, "visible", false)
    cfg.save(scratch_layout_path)

    var host := Node.new()
    var registries := SaRegistries.new()
    var win := Window.new()
    win.name = SECTION
    win.position = Vector2i(Vector2(stored) * SaUI.window_scale(win))
    win.size = SIZE
    win.visible = false
    host.add_child(win)
    registries.ui.register_docker(&"UndoDocker", "Undo History", func() -> Window: return Window.new(), &"docker_stub")
    registries.ui.set_docker_node(&"UndoDocker", win)
    var store := NoForkStore.new()
    store.path = scratch_layout_path
    host.add_child(MainDockers.new(registries.ui, store))
    return host


func _dockers(host: Node) -> MainDockers:
    return host.get_node("MainDockers") as MainDockers


func _window(host: Node) -> Window:
    return _dockers(host).get_docker_config()[0]["node"] as Window


## The fitted place, read back from the file the tick's save wrote, in the
## window's units.
func _on_disk() -> Vector2i:
    var cfg := ConfigFile.new()
    cfg.load(scratch_layout_path)
    return cfg.get_value(SECTION, "position", Vector2i())


func test_a_docker_stored_off_the_foot_of_the_window_is_shown_inside_it() -> void:
    var host := _stub(Vector2i(2, 1000))
    var win := _window(host)
    var room := DockerDragHandle.host_size_of(win)
    if room.x < SIZE.x or room.y < SIZE.y:
        skip("no screen to fit a docker into, so the host a show fits to is unknown")
        host.free()
        return
    var stored := win.position
    assert_true(
        stored.y + win.size.y > room.y,
        "The stored place puts the docker past the foot of the host: %s in %s" % [str(stored), str(room)]
    )

    _dockers(host).toggle_docker(0)

    var shown := Rect2i(win.position, win.size)
    assert_true(win.visible, "The row's toggle showed the docker")
    assert_true(
        Rect2i(Vector2i(), room).encloses(shown), "with its whole frame inside the host: %s in %s" % [str(shown), str(room)]
    )
    assert_eq(win.position.x, stored.x, "moved as little as possible, so not sideways")
    assert_eq(win.position.y, room.y - win.size.y, "and up only until its foot meets the host's")
    var store := _dockers(host).layout_store
    assert_eq(
        store.value_for(SECTION, "position", Vector2i()),
        win.position,
        "The store holds the fitted place, which is what it re-asserts"
    )
    assert_eq(store.stored_positions().get(SECTION), win.position, "and answers it as the docker's position")
    assert_eq(
        _on_disk(),
        Vector2i(Vector2(win.position) / SaUI.window_scale(win)),
        "The tick's save wrote the mended place to the file, so the next start opens it there"
    )
    host.free()


## Off the right edge and above the top, both corners are brought in, each by
## the least that puts the frame inside.
func test_a_docker_stored_off_the_corner_is_brought_in_on_both_axes() -> void:
    var host := _stub(Vector2i(5000, -200))
    var win := _window(host)
    var room := DockerDragHandle.host_size_of(win)
    if room.x < SIZE.x or room.y < SIZE.y:
        skip("no screen to fit a docker into, so the host a show fits to is unknown")
        host.free()
        return
    _dockers(host).toggle_docker(0)
    assert_eq(win.position, Vector2i(room.x - win.size.x, 0), "The docker is brought in to the right edge and down to the top")
    host.free()


## A docker whose stored place is inside the host is shown exactly there: the
## fit moves nothing the painter put somewhere reachable.
func test_a_docker_stored_inside_the_window_is_shown_where_it_was() -> void:
    var host := _stub(Vector2i(1200, 680))
    var win := _window(host)
    var room := DockerDragHandle.host_size_of(win)
    if room.x < 1200 + SIZE.x or room.y < 680 + SIZE.y:
        skip("a screen smaller than 1440 by 1020, where the stored place is not inside")
        host.free()
        return
    var stored := win.position
    _dockers(host).toggle_docker(0)
    assert_true(win.visible, "The docker is shown")
    assert_eq(win.position, stored, "where it was stored, untouched")
    host.free()
