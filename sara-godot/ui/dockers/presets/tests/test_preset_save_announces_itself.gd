## A preset saved or deleted from the bar announces itself, so the presets docker
## holds what is on disk without being shown again.
##
## `EventBus.preset_loaded` existed from the day presets did and there was no
## partner for a write. `save_current_as_preset` wrote the file, refreshed the
## bar's own menu and returned, so the presets docker, whose grid is rebuilt when
## it is shown, when the tool changes and when a preset is loaded, was a preset
## short between a save and the next of those. A delete had the same shape from
## the other end and left a cell for a file that is no longer there.
##
## The docker's own capture door carried a `{"refresh": true}` step to work
## around it. That step is gone, because a door that exists to stand in for a
## missing signal is a placeholder for the signal.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar builds against a tool machine, which needs a RenderingDevice.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_f86_presets")


func after_each() -> void:
    var dir := DirAccess.open(scratch_dir)
    if dir == null:
        return
    for file: String in dir.get_files():
        dir.remove(file)


## Every announcement the bus carried while the test ran, in order.
class Heard:
    extends RefCounted

    var rows: Array = []

    func note(preset_name: String, saved: bool) -> void:
        rows.append([preset_name, saved])


func test_a_save_and_a_delete_are_both_announced() -> void:
    var host := Node.new()
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")

    var bar := ToolOptionsBar.new()
    host.add_child(bar)
    bar.target_tool_machine = machine
    bar.preset_store.dir = scratch_dir
    bar._ready()

    var heard := Heard.new()
    EventBus.preset_store_changed.connect(heard.note)

    var settings: Resource = machine.get_tool("brush").settings
    settings.set("radius", 0.4)
    var stored: String = bar.preset_box.save_current_as_preset("Wide Saved")
    assert_false(stored.is_empty(), "The preset is written")
    assert_eq(heard.rows.size(), 1, "and the save says so once")
    assert_eq(String(heard.rows[0][0]), stored, "under the name it was stored as")
    assert_true(bool(heard.rows[0][1]), "and saved is true")

    bar.preset_box.delete_loaded_preset()
    assert_eq(heard.rows.size(), 2, "The delete says so too")
    assert_eq(String(heard.rows[1][0]), stored, "naming the preset that went")
    assert_false(bool(heard.rows[1][1]), "with saved false, so one connection covers both")

    EventBus.preset_store_changed.disconnect(heard.note)
    host.free()
    Fixtures.teardown(surface, machine)


## The other half, and the one the filing is actually about: the docker's grid
## holds the preset without anything showing the docker again.
func test_the_docker_holds_a_preset_saved_while_it_is_open() -> void:
    var host := Node.new()
    # In the tree, because `BrushPresetsDocker._bar` finds the bar by name from
    # the scene root and answers null outside it. The docker reaching its bar
    # through the tree is its existing shape, and the
    # framework is a `RefCounted` with no tree of its own, so the autoload is the
    # handle every other suite here uses to reach one.
    EventBus.add_child(host)
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")

    var bar := ToolOptionsBar.new()
    bar.name = "ToolOptionsBar"
    host.add_child(bar)
    bar.target_tool_machine = machine
    bar.preset_store.dir = scratch_dir
    bar._ready()

    var docker := BrushPresetsDocker.new()
    host.add_child(docker)
    docker.rebind()
    var before := int(docker.capture_state()["chooser"].get("count", 0))

    var settings: Resource = machine.get_tool("brush").settings
    settings.set("radius", 0.4)
    var stored: String = bar.preset_box.save_current_as_preset("Docker Saved")
    assert_false(stored.is_empty(), "The preset is written")

    # Nothing here shows the docker, changes the tool or loads a preset, which
    # are the three things that rebuild the grid.
    var after := int(docker.capture_state()["chooser"].get("count", 0))
    assert_eq(after, before + 1, "and the grid gained a cell without being shown again")

    bar.preset_box.delete_loaded_preset()
    var deleted := int(docker.capture_state()["chooser"].get("count", 0))
    assert_eq(deleted, before, "and lost it again when the preset was deleted")

    EventBus.remove_child(host)
    host.free()
    Fixtures.teardown(surface, machine)


## The door step the signal replaced is gone rather than left answering.
func test_the_refresh_door_step_is_gone() -> void:
    var source := FileAccess.get_file_as_string("res://ui/dockers/presets/brush_presets_docker.gd")
    assert_false(source.is_empty(), "The docker's script is readable")
    assert_false(
        source.contains('get("refresh", false)'),
        "No branch answers a refresh step, because the signal is what a save announces itself with"
    )
