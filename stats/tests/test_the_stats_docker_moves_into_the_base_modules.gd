## The Stats docker moves into the base modules.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Stats docker is this module's, registered through `SaContext.register_docker`, and its
## numbers still come from `SaReductions`, whose service moved behind the door
## to `core/api/reduction` so the Graph docker and this one share it as before.
##
## With the skeleton's own registrations alone the built-in dockers hold the
## Graph and no Stats, and the service is alive. With the module registered
## through a scoped context the docker is there under the id it had as a
## built-in, built by the module's factory, and it goes with the module.
## Last, the Default layout's closed Info docker stops above the Stats, the
## room it was given, which the Info's suite read until the move.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const StatsModule := preload("../module.gd")
const Docker := preload("../stats_docker.gd")

## The size Default gives the closed Info docker, so the Stats under it has
## its room, which `test_info_docker.gd` holds the files to.
const INFO_UNDER_DEFAULT := Vector2i(500, 290)

var _registries: SaRegistries = null
var _dockers: MainDockers = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _dockers = MainDockers.new(_registries.ui)
    _dockers.register_builtin_dockers()


func after_each() -> void:
    _dockers.free()
    _dockers = null
    _registries = null


func _ids() -> Array[StringName]:
    var ids: Array[StringName] = []
    for entry: Dictionary in _registries.ui.list_dockers():
        ids.append(entry["id"])
    return ids


func test_the_skeleton_alone_offers_the_graph_and_no_stats() -> void:
    var ids := _ids()
    assert_true(ids.has(SaDockerIds.GRAPH), "The Graph docker is a built-in still")
    assert_false(ids.has(Docker.DOCKER_ID), "and no Stats docker is registered without the module: %s" % [ids])
    assert_false(SaDockerIds.ALL.has(Docker.DOCKER_ID), "nor is its id one of the skeleton's")
    assert_true(SaReductionService.shared() != null, "The one service, the autoload SaReductions, is alive")
    assert_eq(
        (SaReductionService.shared().get_script() as Script).resource_path,
        "res://core/api/reduction/sa_reduction_service.gd",
        "from its place behind the door"
    )


func test_the_module_registers_the_docker_under_its_old_id() -> void:
    var module: SaModule = StatsModule.new()
    module.register(_registries.context.for_module(module.get_id()))
    assert_true(_registries.ui.has_docker(Docker.DOCKER_ID), "With the module loaded the docker is registered")
    assert_eq(String(Docker.DOCKER_ID), "StatsDocker", "under the id the built-in had, which the layouts name")
    var entry: Dictionary = _registries.ui.get_docker_entry(Docker.DOCKER_ID)
    assert_eq(entry["title"], "Stats", "titled Stats")
    assert_eq(entry["module"], module.get_id(), "as the module's own")
    assert_eq(entry["sentence"], Docker.SENTENCE, "with the sentence its Window menu row says")
    var ids := _ids()
    assert_true(ids.find(SaDockerIds.GRAPH) < ids.find(Docker.DOCKER_ID), "and listed after the built-ins")
    var window: Window = (entry["factory"] as Callable).call()
    assert_eq(window.get_script(), Docker, "Its factory builds the docker")
    assert_eq(String(window.name), String(Docker.DOCKER_ID), "named by its id")
    window.free()
    _registries.ui.unregister_module(module.get_id())
    assert_false(_registries.ui.has_docker(Docker.DOCKER_ID), "and it goes with the module")


func test_the_default_layouts_infos_foot_stops_above_the_stats() -> void:
    for path: String in ["res://docker_layout_default.cfg", "res://layouts/default.cfg"]:
        var cfg := ConfigFile.new()
        assert_eq(cfg.load(path), OK, "%s reads" % path)
        assert_eq(cfg.get_value("InfoDocker", "size", Vector2i.ZERO), INFO_UNDER_DEFAULT, "%s gives the Info its room" % path)
        var info_at: Vector2i = cfg.get_value("InfoDocker", "position", Vector2i.ZERO)
        var stats_at: Vector2i = cfg.get_value(String(Docker.DOCKER_ID), "position", Vector2i.ZERO)
        assert_true(info_at.y + INFO_UNDER_DEFAULT.y <= stats_at.y, "and %s puts the Info's foot above the Stats" % path)


## Full names the Stats docker open. Loaded through the layout store with the
## skeleton's dockers alone, it loads, opens the built-ins it names and draws
## nothing for the Stats, because the store places only the dockers it is
## handed and nothing in the skeleton hands it one.
func test_a_layout_naming_the_stats_draws_nothing_for_it_without_the_module() -> void:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load("res://layouts/full.cfg"), OK, "Full reads")
    assert_true(bool(cfg.get_value(String(Docker.DOCKER_ID), "visible", false)), "and names the Stats docker open")

    var root := Node.new()
    EventBus.add_child(root)
    var viewport := SubViewport.new()
    viewport.size = Vector2i(1920, 1080)
    viewport.gui_embed_subwindows = true
    root.add_child(viewport)
    var parent := Control.new()
    parent.set_anchors_preset(Control.PRESET_FULL_RECT)
    viewport.add_child(parent)
    var configs: Array = []
    for id in _ids():
        var probe := Window.new()
        probe.name = String(id)
        probe.size = Vector2i(200, 150)
        probe.visible = false
        parent.add_child(probe)
        configs.append({"id": String(id), "name": String(id), "node": probe})
    var saved := ConfigFile.new()
    var store := DockerLayoutStore.new()
    store.path = SaDataRoot.path("test_docker_layout.cfg")
    store.dockers_provider = func() -> Array: return configs
    store.save_allowed = func() -> bool: return false
    store.presets().capture(saved)
    root.add_child(store)

    assert_true(store.load_preset("full"), "Full loads with no Stats docker registered")
    var opened: Array[String] = []
    for config: Dictionary in configs:
        if (config["node"] as Window).visible:
            opened.append(config["id"])
    assert_true(opened.has(String(SaDockerIds.GRAPH)), "and opens the Graph it names: %s" % [opened])
    assert_false(opened.has(String(Docker.DOCKER_ID)), "and no Stats")
    assert_null(parent.find_child(String(Docker.DOCKER_ID), true, false), "nor a window of that name anywhere under the host")

    store.presets().apply(saved)
    SaFocusMode.active = false
    root.free()
