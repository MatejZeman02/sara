## A tool switch builds the presets grid at most once, and a switch that
## changes nothing the grid lists builds no cell at all.
##
## The hand back to the tool before a transform's commit frame must not spend
## 33 ms, as it did when the Brush Presets docker and the
## bar's preset group each rebuilt every cell of one grid on the same
## `tool_changed`. The grid lists the store under a tag and a search, marks the
## loaded preset, and dims the cells of another engine. A switch moves the
## engine and nothing else, so it redims what it holds.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## The bar builds against a tool machine, which needs a RenderingDevice.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_q19_presets")

## The profile's tag filter as it stood, put back after each test, since a press
## on a tag writes it for every chooser after this one.
var _tag_filter_was: Dictionary = {}


func before_each() -> void:
    _tag_filter_was = SaSettings.preset_tag_filter.duplicate()
    SaSettings.preset_tag_filter = {}
    ScratchFolder.empty(scratch_dir)


func after_each() -> void:
    SaSettings.preset_tag_filter = _tag_filter_was
    ScratchFolder.empty(scratch_dir)


## Every cell the grid took in while it was being watched.
class Built:
    extends RefCounted

    var cells: int = 0

    func note(_cell: Node) -> void:
        cells += 1


## Four switches through the real bar and docker, and not one cell built. The
## stamp engine's noise-marked preset is dimmed under the brush, lit under the
## gradient, which takes no presets, and dimmed again under the brush, on the
## cells the grid already held.
func test_a_switch_builds_no_cell_and_redims_the_ones_it_holds() -> void:
    var host := Node.new()
    # In the tree, because the docker finds the bar's preset group by name from
    # the scene root, as `test_preset_save_announces_itself.gd` says.
    EventBus.add_child(host)
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")

    var bar := ToolOptionsBar.new()
    bar.name = "ToolOptionsBar"
    host.add_child(bar)
    bar.target_tool_machine = machine
    bar.preset_store.dir = scratch_dir
    bar.preset_store.save_preset("Ink", StampSettingsScript.new())
    bar.preset_store.save_preset("Grain", StampSettingsScript.new(), PackedStringArray(), {SaPresetMeta.ENGINE_META: &"noise"})
    bar._ready()

    var docker := BrushPresetsDocker.new()
    host.add_child(docker)
    docker.rebind()
    var held := docker.chooser.grid.get_children()
    assert_true(held.size() >= 2, "The grid holds the two presets and whatever ships: %d" % held.size())
    assert_true(_dimmed(docker, "Grain"), "The noise preset is dimmed under the brush")
    assert_false(_dimmed(docker, "Ink"), "and the stamp one is not")

    var built := Built.new()
    docker.chooser.grid.child_entered_tree.connect(built.note)
    machine.set_active_tool(&"eraser")
    assert_eq(built.cells, 0, "A switch between two stamp tools builds no cell, in the docker or in the bar")
    assert_eq(docker.chooser.grid.get_children(), held, "and the grid holds the very cells it held")

    machine.set_active_tool(&"gradient")
    assert_eq(built.cells, 0, "A switch to a tool that takes no presets builds none either")
    # The redim waits for the frame after the switch, and a suite has
    # none to wait for, so it is run here as that frame would run it.
    assert_true(docker.after_pick.waits(&"redim"), "The redim waits for the frame after the switch")
    docker.after_pick.settle_all()
    assert_false(_dimmed(docker, "Grain"), "and the noise preset is lit, since nothing is foreign to no engine")

    machine.set_active_tool(&"brush")
    docker.after_pick.settle_all()
    assert_eq(built.cells, 0, "Back to the brush, still none")
    assert_true(_dimmed(docker, "Grain"), "and the same cell is dimmed again")
    assert_false(_dimmed(docker, "Ink"), "with the stamp one lit")
    assert_eq(docker.chooser.grid.get_children(), held, "on the cells the first build made")

    docker.chooser.grid.child_entered_tree.disconnect(built.note)
    EventBus.remove_child(host)
    host.free()
    Fixtures.teardown(surface, machine)


## `refresh_if_changed` keeps the grid when nothing it lists moved, and rebuilds
## when the store lists another name, when the loaded preset moves and when the
## tag does.
func test_the_grid_is_rebuilt_only_when_what_it_lists_changed() -> void:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.save_preset("Ink", StampSettingsScript.new(), PackedStringArray(["wet"]))
    store.save_preset("Chalk", StampSettingsScript.new())
    var loaded := {"name": ""}
    var chooser := SaBrushPresetsChooser.new()
    chooser.bind_store(
        store, StateBrushScript, func() -> Resource: return StampSettingsScript.new(), func() -> String: return loaded["name"]
    )
    var held := chooser.grid.get_children()
    assert_eq(held.size(), 2, "Two cells to start with")
    assert_false(chooser.refresh_if_changed(), "Nothing moved, so nothing is rebuilt")
    assert_eq(chooser.grid.get_children(), held, "and the cells are the ones it had")

    store.save_preset("Wash", StampSettingsScript.new())
    assert_true(chooser.refresh_if_changed(), "A third preset in the store is a rebuild")
    assert_eq(chooser.visible_names(), ["Chalk", "Ink", "Wash"] as Array[String], "that lists it")

    loaded["name"] = "Ink"
    assert_true(chooser.refresh_if_changed(), "The loaded preset moving is a rebuild")
    assert_eq(String(chooser.chooser_report()["marked"]), "Ink", "that marks it")
    assert_false(chooser.refresh_if_changed(), "and asking again finds nothing to do")

    assert_true(chooser.follow_tag("wet"), "The bar's tag arriving is a rebuild")
    assert_eq(chooser.visible_names(), ["Ink"] as Array[String], "down to what carries it")
    assert_false(chooser.follow_tag("wet"), "and the same tag again is not")
    assert_false(chooser.follow_tag("dry"), "A tag nothing carries leaves the filter where it was")
    assert_eq(chooser.visible_names(), ["Ink"] as Array[String], "on the tag it had")
    chooser.free()


func _dimmed(docker: BrushPresetsDocker, preset_name: String) -> bool:
    var cells: Dictionary = docker.engine_marks.report()["cells"]
    return bool((cells.get(preset_name, {}) as Dictionary).get("dimmed", false))
