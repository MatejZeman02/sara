## The Delete answer takes the preset the question named, or nothing. The delete
## removes whatever is loaded, and the answer loaded the named preset first
## without asking whether that worked, so a preset gone while the question stood
## sent the one loaded before it to the bin.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const DockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")

## A real bar with a store in the tree.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_b3_delete_named")


func before_each() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch_dir))


func after_each() -> void:
    var dir := DirAccess.open(scratch_dir)
    if dir != null:
        for file in dir.get_files():
            dir.remove(file)


func test_a_preset_gone_before_the_answer_takes_no_other() -> void:
    var host := Node.new()
    host.name = "B3DeleteNamedHost"
    EventBus.add_child(host)
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var bar := ToolOptionsBar.new()
    host.add_child(bar)
    bar.target_tool_machine = machine
    bar.preset_store.dir = scratch_dir
    bar._ready()
    bar.save_current_as_preset("Kept")
    bar.save_current_as_preset("Doomed")
    bar.load_preset("Kept")
    var docker := DockerScript.new()
    host.add_child(docker)
    docker.rebind()

    bar.preset_store.delete_preset("Doomed")
    docker._on_delete_answered(BrushPresetsDocker.DELETE_CONFIRM, "Doomed")
    assert_true(bar.preset_names().has("Kept"), "The preset that was loaded is still there")
    assert_eq(bar.selected_preset_name(), "Kept", "and still loaded")

    host.free()
    Fixtures.teardown(surface, machine)
