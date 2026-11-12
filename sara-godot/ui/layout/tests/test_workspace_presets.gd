## Named docker layouts: save one, switch to it, find it again after a restart,
## and delete it.
##
## `list_presets` answers the five Sara ships as well, so the
## assertions about what a painter saved go through `_own`, which is that list
## with the five taken off it.
extends "res://tests/test_framework.gd"

const HOST := Vector2i(1200, 800)
const DOCKER_SIZE := Vector2i(200, 150)
static var scratch_layout_path: String = SaDataRoot.path("test_workspace_presets.cfg")
static var scratch_presets_dir: String = SaDataRoot.path("layouts")

var _root: Node = null
var _viewport: SubViewport = null
var _host: Control = null
var _docker: Window = null
var _store: DockerLayoutStore = null
var _stores: Array[DockerLayoutStore] = []


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _root = Node.new()
    _root.name = "WorkspacePresetsTestHost"
    EventBus.add_child(_root)

    _viewport = SubViewport.new()
    _viewport.size = HOST
    _viewport.gui_embed_subwindows = true
    _root.add_child(_viewport)

    _host = Control.new()
    _host.set_anchors_preset(Control.PRESET_FULL_RECT)
    _viewport.add_child(_host)

    _docker = Window.new()
    _docker.size = DOCKER_SIZE
    _host.add_child(_docker)

    # Both ends, not just the far one. `_own` is the layouts list with the
    # shipped names taken off, so anything another suite left in the shared
    # `user://layouts` reads here as a layout this one saved. A suite that drives the real dockers forks
    # `default` on its first edit, the way the app does, so there is something to
    # leave.
    _clear_presets_dir()
    _store = _new_store()


func after_each() -> void:
    for store in _stores:
        if is_instance_valid(store):
            store.free()
    _stores.clear()
    if _root != null:
        _root.free()
        _root = null
    if FileAccess.file_exists(scratch_layout_path):
        DirAccess.remove_absolute(scratch_layout_path)
    _clear_presets_dir()


func _clear_presets_dir() -> void:
    var dir := DirAccess.open(scratch_presets_dir)
    if dir == null:
        return
    for file_name in dir.get_files():
        DirAccess.remove_absolute(scratch_presets_dir.path_join(file_name))
    DirAccess.remove_absolute(scratch_presets_dir)


## A second store over the same file, which is what a restart looks like from
## here: nothing carried in memory, everything read back from disk.
##
## Deliberately not added to the tree. `reapply_deferred` returns at once for a
## store that is not in one, and in one it awaits sixty process frames against a
## compositor that is not there, which leaves the whole run waiting for a quit
## that never comes. `restore_all` has already set the geometry by then, which is
## what these cases read.
func _new_store() -> DockerLayoutStore:
    var store := DockerLayoutStore.new()
    store.path = scratch_layout_path
    store.dockers_provider = func() -> Array: return [{"id": "ProbeDocker", "name": "Probe", "node": _docker}]
    store.save_allowed = func() -> bool: return true
    _stores.append(store)
    return store


func test_a_saved_layout_is_listed_and_becomes_the_current_one() -> void:
    _docker.position = Vector2i(300, 200)
    assert_true(_store.save_preset("Painting"), "The save reports success")
    assert_eq(_own(_store), ["Painting"] as Array[String], "and the name is in the list")
    assert_eq(_store.current_preset(), "Painting", "and it is the layout in use")


## The point of the feature: two arrangements, and switching puts the docker
## where the chosen one says.
func test_switching_between_two_layouts_moves_the_docker() -> void:
    _docker.position = Vector2i(300, 200)
    _store.save_preset("Left")
    _docker.position = Vector2i(800, 500)
    _store.save_preset("Right")

    _store.load_preset("Left")
    assert_eq(_docker.position, Vector2i(300, 200), "Switching back puts the docker where Left says")
    assert_eq(_store.current_preset(), "Left", "and Left is what the store reports")

    _store.load_preset("Right")
    assert_eq(_docker.position, Vector2i(800, 500), "and forward again puts it where Right says")


## Presets are files, so a store built fresh over the same path finds them.
func test_a_layout_survives_a_restart() -> void:
    _docker.position = Vector2i(420, 310)
    _store.save_preset("Overnight")

    var reopened := _new_store()
    assert_eq(_own(reopened), ["Overnight"] as Array[String], "A fresh store lists what the last one saved")
    assert_eq(reopened.current_preset(), "Overnight", "and knows which one is in use")

    _docker.position = Vector2i(0, 0)
    reopened.load_preset("Overnight")
    assert_eq(_docker.position, Vector2i(420, 310), "and puts the docker back where it was")


## Deleting the layout a painter is working in forgets the name and leaves the
## dockers alone. Moving them as well would be a second, unasked-for change.
func test_deleting_a_layout_forgets_the_name_and_moves_nothing() -> void:
    _docker.position = Vector2i(275, 190)
    _store.save_preset("Doomed")
    assert_true(_store.delete_preset("Doomed"), "The delete reports success")
    assert_true(_own(_store).is_empty(), "and the name is gone")
    # `default` rather than "": a painter is always in some layout, and
    # the one they are in after forgetting a name is the one a fresh profile is
    # in. Their dockers have not moved, so the next edit makes `default (custom)`.
    assert_eq(_store.current_preset(), "default", "and the default is what is current")
    assert_eq(_docker.position, Vector2i(275, 190), "and the docker has not moved")


func test_an_empty_name_saves_nothing_and_a_missing_one_loads_nothing() -> void:
    assert_false(_store.save_preset(""), "An empty name saves nothing")
    assert_true(_own(_store).is_empty(), "so nothing was written")
    assert_false(_store.load_preset("never-saved"), "Loading a layout that is not there reports failure")


## A name that would be a path is written under a file name that is not one, so
## a layout called "a/b" cannot land outside the layouts folder.
func test_a_name_with_a_separator_is_stored_sanitised() -> void:
    assert_true(_store.save_preset("a/b"), "The save goes through")
    assert_eq(_own(_store), ["a_b"] as Array[String], "under a name with no separator in it")


## The layouts the painter saved, which is the list with the shipped ones taken
## off the front of it.
func _own(store: DockerLayoutStore) -> Array[String]:
    var out: Array[String] = []
    for preset_name in store.list_presets():
        if not SaDockerLayoutPresets.SHIPPED.has(preset_name):
            out.append(preset_name)
    return out
