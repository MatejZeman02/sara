## The borrow, a docker shown under the pointer with a return
## address, and nothing written to the layout while it is out.
##
## The layout store forks a preset on a drag and saves the live layout on a
## hide, so a docker that jumped to the pointer and back would have taught the
## workspace preset a position the painter never chose. The borrow is a
## state apart from the ones the store keeps.
##
## The windows here are never added to a tree: a `Window` in a suite hangs the
## run, and nothing here needs
## one drawn. Out of a tree the store runs no settle loop, so what is asserted
## is the state the loop would read, through `_placed_value`.
extends "res://tests/test_framework.gd"

static var scratch_layout_path: String = SaDataRoot.path("test_u1_borrow_layout.cfg")
const SECTION: String = "ColorDocker"
const HOME := Vector2i(400, 300)
const SIZE := Vector2i(321, 480)
## Half of SIZE, truncated the way the store truncates it.
const HALF := Vector2i(160, 240)


func after_each() -> void:
    if FileAccess.file_exists(scratch_layout_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_layout_path))


## A store with one docker at HOME, and the file written once from it, so the
## file is what a painter's session left behind.
func _store_with(win: Window) -> DockerLayoutStore:
    var store := DockerLayoutStore.new()
    store.path = scratch_layout_path
    var config := {"node": win, "id": SECTION, "name": "Colour Picker"}
    store.dockers_provider = func() -> Array: return [config]
    store.save(true)
    return store


func _docker(visible: bool) -> Window:
    var win := Window.new()
    win.name = SECTION
    win.position = HOME
    win.size = SIZE
    win.visible = visible
    return win


func test_a_borrowed_docker_sits_under_the_point_and_goes_back() -> void:
    var win := _docker(true)
    var store := _store_with(win)
    var on_disk := FileAccess.get_file_as_bytes(scratch_layout_path)
    assert_true(on_disk.size() > 0, "the layout file exists before the borrow")
    var stored_before: Dictionary = store.stored_positions()
    assert_eq(stored_before.get(SECTION), HOME, "the layout holds the painter's position")

    var point := Vector2i(800, 500)
    assert_true(store.borrow(win, SECTION, point), "the borrow is taken")
    assert_true(store.is_borrowed(SECTION), "and the store says so")
    assert_eq(win.position, point - HALF, "the docker is centred on the point")
    assert_true(Rect2i(win.position, win.size).has_point(point), "so the pointer is inside it")
    assert_true(win.visible, "and shown")
    assert_eq(FileAccess.get_file_as_bytes(scratch_layout_path), on_disk, "the file on disk is byte for byte what it was")
    assert_eq(store.stored_positions().get(SECTION), HOME, "stored_positions still answers the old position")
    assert_eq(store._placed_value(SECTION, "position", Vector2i()), win.position, "the settle loop holds the borrow")

    assert_true(store.give_back(SECTION), "the docker is given back")
    assert_false(store.is_borrowed(SECTION), "and nothing is borrowed")
    assert_eq(win.position, HOME, "its position is back")
    assert_eq(win.size, SIZE, "its size is back")
    assert_true(win.visible, "and it is still shown, as it was")
    assert_eq(store._placed_value(SECTION, "position", Vector2i()), HOME, "the settle loop holds the layout again")
    assert_eq(FileAccess.get_file_as_bytes(scratch_layout_path), on_disk, "and the return wrote nothing either")
    assert_false(store.give_back(SECTION), "a second return has nothing to give back")

    win.free()
    store.free()


func test_a_hidden_docker_goes_back_to_hidden() -> void:
    var win := _docker(false)
    var store := _store_with(win)

    store.borrow(win, SECTION, Vector2i(700, 400))
    assert_true(win.visible, "a hidden docker is shown by the borrow")
    store.give_back(SECTION)
    assert_false(win.visible, "and hidden again by the return")
    assert_eq(win.position, HOME, "where it was")

    win.free()
    store.free()


func test_a_save_during_a_borrow_writes_nothing() -> void:
    var win := _docker(true)
    var store := _store_with(win)
    var on_disk := FileAccess.get_file_as_bytes(scratch_layout_path)

    store.borrow(win, SECTION, Vector2i(900, 600))
    store.save(true)
    assert_eq(
        FileAccess.get_file_as_bytes(scratch_layout_path), on_disk, "a painter's save while the docker is out leaves the file"
    )
    assert_eq(store.stored_positions().get(SECTION), HOME, "and the cache still holds the painter's rectangle")

    store.give_back(SECTION)
    win.position = Vector2i(420, 320)
    store.save(true)
    assert_true(
        FileAccess.get_file_as_bytes(scratch_layout_path) != on_disk,
        "a save after the return writes the painter's move, so the skip was the borrow's"
    )

    win.free()
    store.free()


## A borrow near an edge is fitted, and a second borrow keeps the first address.
func test_a_borrow_is_fitted_and_keeps_its_first_address() -> void:
    var win := _docker(true)
    var store := _store_with(win)
    var host := DockerDragHandle.host_size_of(win)

    store.borrow(win, SECTION, host + Vector2i(50, 50))
    if host != Vector2i():
        assert_true(win.position.x + win.size.x <= host.x, "the right edge stays on screen")
        assert_true(win.position.y + win.size.y <= host.y, "and the bottom one")
    store.borrow(win, SECTION, Vector2i(600, 400))
    assert_eq(win.position, Vector2i(600, 400) - HALF, "a second borrow moves the docker")
    store.give_back(SECTION)
    assert_eq(win.position, HOME, "and the return goes to where the painter left it, not the first borrow")

    win.free()
    store.free()


## A borrowed docker dragged by its title stays where it was
## dropped. The drag handle moves the window and emits `docker_layout_changed`,
## whose answer is `save(true)`, so that save is the line that tells the store.
## The settle loop reads `_placed_value` once a frame, which is what it would
## have written back over the drag.
func test_a_borrowed_docker_dragged_stays_where_it_was_dropped() -> void:
    var win := _docker(true)
    var store := _store_with(win)
    var on_disk := FileAccess.get_file_as_bytes(scratch_layout_path)

    store.borrow(win, SECTION, Vector2i(800, 500))
    var dropped := win.position + Vector2i(-200, -100)
    win.position = dropped
    store.save(true)
    assert_eq(store._placed_value(SECTION, "position", Vector2i()), dropped, "the settle loop holds the drop")
    assert_eq(FileAccess.get_file_as_bytes(scratch_layout_path), on_disk, "the drag of a borrowed docker writes nothing")
    assert_eq(store.stored_positions().get(SECTION), HOME, "and the layout keeps the painter's rectangle")

    var sized := SIZE + Vector2i(40, 60)
    win.size = sized
    store.save(true)
    assert_eq(store._placed_value(SECTION, "size", Vector2i()), sized, "a resize while it is out holds too")

    assert_true(store.give_back(SECTION), "the docker is given back")
    assert_eq(win.position, HOME, "to its address, not to the drop")
    assert_eq(win.size, SIZE, "at its own size")
    assert_eq(store._placed_value(SECTION, "position", Vector2i()), HOME, "and the settle loop holds the layout again")

    win.free()
    store.free()


## A save the app made, the compositor settling a window, is not the painter
## and does not move the borrow.
func test_a_save_not_by_the_painter_leaves_the_borrow() -> void:
    var win := _docker(true)
    var store := _store_with(win)

    store.borrow(win, SECTION, Vector2i(800, 500))
    var at := win.position
    win.position = at + Vector2i(30, 30)
    store.save(false)
    assert_eq(store._placed_value(SECTION, "position", Vector2i()), at, "the borrow stays where the summon put it")

    win.free()
    store.free()


## A scenario's `docker` step on a borrowed docker moves the borrow and leaves
## the layout, the same rule as the painter's drag.
func test_a_noted_placement_of_a_borrowed_docker_moves_the_borrow() -> void:
    var win := _docker(true)
    var store := _store_with(win)

    store.borrow(win, SECTION, Vector2i(800, 500))
    win.position = Vector2i(250, 150)
    assert_true(store.note_placement(win), "the placement is noted")
    assert_eq(store._placed_value(SECTION, "position", Vector2i()), Vector2i(250, 150), "the settle loop holds it")
    assert_eq(store.stored_positions().get(SECTION), HOME, "and the layout does not learn it")
    store.give_back(SECTION)
    assert_eq(win.position, HOME, "the return still goes home")

    win.free()
    store.free()
