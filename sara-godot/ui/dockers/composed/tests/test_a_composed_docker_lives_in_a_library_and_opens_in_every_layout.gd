## A composed docker lives in a library of its own and opens in
## every layout.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Composed dockers live in a library of their own,
## available in every layout, and a layout records only whether each is shown
## and where. So the suite makes one of two test elements and reads the
## library's file for it, finds it registered and its window holding the two
## views, saves a layout with it open and reads that file for its place and
## nothing of what it holds, and loads a layout that never named it.
## The rest is the late view a module registers after the window is built, a
## change, and the delete that leaves no trace in the registry, the file or
## the tree.
##
## Everything it writes is under a folder of its own in the data root: the
## library, the live layout and the layouts saved beside it, all removed after
## each test. The registry is the suite's own, so the app's dockers never hear
## of these.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const ComposedDocker := preload("res://ui/dockers/composed/composed_docker.gd")
const CATEGORY := "ElementsFixture"
const FIRST := "Probe First"
const SECOND := "Probe Second"
const LATE := "Probe Late"
const DOCKER_NAME := "Probe Docker"
const HOST := Vector2i(1200, 800)

static var scratch_dir: String = SaDataRoot.path("test_d2_composed")
static var library_path: String = scratch_dir.path_join("composed_dockers.cfg")
static var layout_path: String = scratch_dir.path_join("docker_layout.cfg")

var _registry: SaUIRegistry = null
var _library: SaComposedDockers = null
var _root: Node = null
var _host: Control = null
var _store: DockerLayoutStore = null
var _provided: Array = []
var _detached: Array[Window] = []
var _saved_state := ConfigFile.new()


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    SaSettings.register_layout_category(CATEGORY, "Elements Fixture", ["Drag Handle", "Resizer", FIRST, SECOND, LATE])
    SaSettings.register_layout_element(CATEGORY, FIRST, FIRST, false, "", _build_view.bind("ProbeFirst"))
    SaSettings.register_layout_element(CATEGORY, SECOND, SECOND, false, "", _build_view.bind("ProbeSecond"))
    _registry = SaUIRegistry.new()
    _library = SaComposedDockers.new(_registry, library_path)
    _provided = []
    _detached.clear()


func after_each() -> void:
    if _store != null:
        _store.presets().apply(_saved_state)
        _store.free()
        _store = null
    for window: Window in _detached:
        if is_instance_valid(window):
            window.free()
    _detached.clear()
    if is_instance_valid(_root):
        _root.free()
    _root = null
    for docker: Dictionary in _library.list():
        SaSettings.unregister_layout_category(String(docker["id"]))
    for element: String in [FIRST, SECOND, LATE]:
        SaSettings.unregister_layout_element(CATEGORY, element)
    SaSettings.unregister_layout_category(CATEGORY)
    _library = null
    _registry = null
    ScratchFolder.clear(scratch_dir)


func _build_view(view_name: String) -> Control:
    var view := Label.new()
    view.name = view_name
    view.text = view_name
    return view


func _two() -> Array:
    return [{"category": CATEGORY, "element": FIRST}, {"category": CATEGORY, "element": SECOND}]


## The window the registry's factory builds, kept detached as a suite that
## never runs `_ready` keeps a docker.
func _built(docker_id: StringName) -> ComposedDocker:
    var factory: Callable = _registry.get_docker_entry(docker_id).get("factory", Callable())
    var window: ComposedDocker = factory.call()
    _detached.append(window)
    return window


## The window built as `MainDockers` builds it: named, in the tree of an
## embedding host, recorded in the registry and given its settings category.
func _placed(docker_id: StringName) -> ComposedDocker:
    _root = Node.new()
    _root.name = "ComposedHost"
    EventBus.add_child(_root)
    var viewport := SubViewport.new()
    viewport.size = HOST
    viewport.gui_embed_subwindows = true
    _root.add_child(viewport)
    _host = Control.new()
    _host.name = "Host"
    _host.set_anchors_preset(Control.PRESET_FULL_RECT)
    viewport.add_child(_host)
    var window: ComposedDocker = _registry.get_docker_entry(docker_id)["factory"].call()
    window.name = String(docker_id)
    _host.add_child(window)
    _registry.set_docker_node(docker_id, window)
    SaSettings.register_layout_category(window.settings_category(), DOCKER_NAME, window.layout_elements())
    return window


func _view_names(window: ComposedDocker) -> Array:
    var out: Array = []
    for view: Control in window.views():
        out.append(String(view.name) if view != null else "")
    return out


func _stored() -> ConfigFile:
    var config := ConfigFile.new()
    config.load(library_path)
    return config


func test_a_made_docker_is_in_the_file_and_registered_holding_its_two_views() -> void:
    var docker_id := _library.make(DOCKER_NAME, _two())
    assert_true(SaComposedDockers.is_composed(docker_id), "A made docker takes a composed id, %s" % docker_id)

    var stored := _stored()
    assert_true(stored.has_section(String(docker_id)), "The library file holds it")
    assert_eq(stored.get_value(String(docker_id), "name", ""), DOCKER_NAME, "under its name")
    var elements: Array = stored.get_value(String(docker_id), "elements", [])
    assert_eq(elements.map(func(entry: Dictionary) -> String: return entry["element"]), [FIRST, SECOND], "and the two in order")
    assert_eq(elements.map(func(entry: Dictionary) -> bool: return entry["visible"]), [true, true], "each with its switch")

    assert_true(_registry.has_docker(docker_id), "It is registered as a docker")
    assert_eq(_registry.get_docker_entry(docker_id)["title"], DOCKER_NAME, "under its name")
    var window := _built(docker_id)
    assert_true(window is DockerWindow, "Its window is a docker's")
    assert_eq(_view_names(window), ["ProbeFirst", "ProbeSecond"], "and holds the two views in order")

    var read_again := SaComposedDockers.new(SaUIRegistry.new(), library_path)
    assert_eq(read_again.list().size(), 1, "A library read from the file again has it")
    assert_eq(read_again.elements_of(docker_id), _library.elements_of(docker_id), "holding the same two")


func test_a_layout_keeps_its_place_and_shown_flag_and_none_of_its_elements() -> void:
    var docker_id := _library.make(DOCKER_NAME, _two())
    var window := _placed(docker_id)
    _store = DockerLayoutStore.new()
    _store.path = layout_path
    _store.dockers_provider = func() -> Array: return _provided
    _store.save_allowed = func() -> bool: return true
    _store.presets().capture(_saved_state)
    assert_true(_store.save_preset("Probe Bare"), "A layout saved before the docker was among the windows")

    _provided = [{"id": String(docker_id), "name": DOCKER_NAME, "node": window}]
    window.position = Vector2i(300, 120)
    window.show()
    assert_true(_store.save_preset("Probe Layout"), "and one saved with it open")

    var layout := ConfigFile.new()
    assert_eq(layout.load(_store.presets().read_path("Probe Layout")), OK, "The saved layout parses")
    var section := String(docker_id)
    assert_true(layout.has_section(section), "It names the composed docker")
    assert_eq(layout.get_value(section, "visible", false), true, "as shown")
    assert_true(layout.has_section_key(section, "position"), "and where")
    for key: String in layout.get_section_keys(SaDockerLayoutPresets.VISIBILITY_SECTION):
        assert_false(key.begins_with(section + "/"), "No switch of its elements is in it, %s" % key)
    assert_false(layout.has_section_key(SaDockerLayoutPresets.ORDER_SECTION, section), "and no order of them")
    for key: String in layout.get_section_keys(section):
        assert_true(["position", "size", "visible"].has(key), "Its section holds its place and flag alone, %s" % key)

    assert_true(_store.load_preset("Probe Bare"), "The layout that never named it loads")
    assert_false(window.visible, "and the docker is closed")
    assert_true(_library.has(docker_id), "still in the library")
    assert_true(_registry.has_docker(docker_id), "and still registered")

    window.position = Vector2i(40, 40)
    assert_true(_store.load_preset("Probe Layout"), "The layout that named it loads again")
    assert_true(window.visible, "and opens it")
    assert_eq(window.position, Vector2i(300, 120), "where it was")


func test_an_element_whose_view_registers_late_joins_the_built_window() -> void:
    var docker_id := _library.make(DOCKER_NAME, [{"category": CATEGORY, "element": LATE}])
    var window := _built(docker_id)
    assert_eq(_view_names(window), [""], "Built before its view, the element waits in an empty holder")

    SaSettings.register_layout_element(CATEGORY, LATE, LATE, false, "", _build_view.bind("ProbeLate"))
    assert_eq(_view_names(window), ["ProbeLate"], "and the view joins the window once it registers")


func test_a_change_reaches_the_file_and_the_window() -> void:
    var docker_id := _library.make(DOCKER_NAME, _two())
    var window := _placed(docker_id)
    var turned := [{"category": CATEGORY, "element": SECOND}, {"category": CATEGORY, "element": FIRST, "visible": false}]
    assert_true(_library.change(docker_id, turned), "The library changes a docker it has")
    var elements: Array = _stored().get_value(String(docker_id), "elements", [])
    var names := elements.map(func(entry: Dictionary) -> String: return entry["element"])
    assert_eq(names, [SECOND, FIRST], "The file has the new order")
    assert_eq(_view_names(window), ["ProbeSecond", "ProbeFirst"], "and so has the built window")
    var views: Array[Control] = window.views()
    assert_false(views[1].get_parent().visible, "with the switched off element hidden")


func test_a_delete_leaves_the_registry_the_file_and_the_tree_without_it() -> void:
    var kept := _library.make("Kept", _two())
    var docker_id := _library.make(DOCKER_NAME, _two())
    var window := _placed(docker_id)
    assert_true(_host.has_node(String(docker_id)), "The window is in the tree before the delete")

    assert_true(_library.delete(docker_id), "The library deletes a docker it has")
    assert_false(_registry.has_docker(docker_id), "The registry no longer has it")
    assert_true(_registry.has_docker(kept), "and still has the other")
    var stored := _stored()
    assert_false(stored.has_section(String(docker_id)), "The library file no longer holds it")
    var order: Array = stored.get_value(SaComposedDockers.LIBRARY_SECTION, "order", [])
    assert_false(order.has(String(docker_id)), "nor lists it")
    var read_again := SaComposedDockers.new(SaUIRegistry.new(), library_path)
    assert_false(read_again.has(docker_id), "and a library read again has no such docker")
    assert_false(_host.has_node(String(docker_id)), "The tree no longer holds its window")
    assert_true(window.is_queued_for_deletion(), "which is on its way to being freed")
    var pages := SaSettings.reorderable_categories().map(func(category: Dictionary) -> String: return category["id"])
    assert_false(pages.has(String(docker_id)), "and Preferences has no page for it")

    var next := _library.make("After", [])
    assert_false(next == docker_id, "A docker made after the delete never takes its id")


## The app's library is a static, and a static outlives the
## engine's servers, so the registry it holds was freed after them and every
## capture aborted on a corrupt heap. The boot's register ties its release to
## the root leaving the tree, and the release lets it go.
func test_the_app_s_library_is_let_go_when_the_root_leaves_the_tree() -> void:
    var before: SaComposedDockers = SaComposedDockers.app
    var root := (Engine.get_main_loop() as SceneTree).root
    SaComposedDockers.register(_registry)
    assert_true(SaComposedDockers.app != null, "The boot's register keeps the app's library")
    assert_true(root.tree_exiting.is_connected(SaComposedDockers.release), "and lets it go when the root leaves the tree")
    SaComposedDockers.release()
    assert_null(SaComposedDockers.app, "The release lets go of it")
    if before != null:
        SaComposedDockers.register(before._ui)
