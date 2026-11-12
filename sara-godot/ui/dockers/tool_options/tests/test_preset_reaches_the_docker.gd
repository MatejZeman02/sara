## Loading a preset moves the Tool Options docker's rows, not only the bar's.
##
## The bar hands its preset group a `Callable` it calls after a load, which
## reaches the bar's own controls and nothing else, so every option that lives
## only in the docker went on showing the value it had before the load. A painter
## who then dragged any row wrote that stale value back over the preset. The
## docker listens to `EventBus.preset_loaded` now, which is the announcement the
## preset group already made for the History docker.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_f49_presets")


func after_each() -> void:
    var dir := DirAccess.open(scratch_dir)
    if dir == null:
        return
    for file: String in dir.get_files():
        dir.remove(file)


func test_a_loaded_preset_moves_the_dockers_rows_too() -> void:
    var host := Node.new()
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")

    var bar := ToolOptionsBar.new()
    host.add_child(bar)
    bar.target_tool_machine = machine
    bar.preset_store.dir = scratch_dir
    bar._ready()

    # Deliberately not `docker.peer_bar = bar`: the two surfaces following each
    # other's writes is the peer link and it is not what a preset travels down. The
    # docker has to hear about the load on its own.
    var docker := ToolOptionsDocker.new()
    host.add_child(docker)
    docker.target_tool_machine = machine

    var settings: Resource = machine.get_tool("brush").settings
    settings.set("radius", 0.4)
    bar.preset_store.save_preset("Reach", settings)

    settings.set("radius", 0.9)
    docker.sync_values_from_tool()
    var row := docker.options.control(&"radius") as FactorSlider
    assert_not_null(row, "The docker has a size row to go stale")
    assert_almost_eq(row.value, 0.9, 0.0001, "and it is showing what was written over the preset")

    assert_true(bar.load_preset("Reach"), "The preset loads")
    assert_almost_eq(settings.get("radius"), 0.4, 0.0001, "and the tool holds what it stored")
    assert_almost_eq(row.value, 0.4, 0.0001, "and the docker's row says so rather than the value it was showing")

    host.free()
    Fixtures.teardown(surface, machine)
