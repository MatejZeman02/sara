## A shot waits for the Brush Presets tiles to draw their pictures.
##
## A scenario runs on a fresh profile, so no preset picture is cached and the
## chooser draws its queue a slice of a frame. How far it had got at a `shot`
## depended on how fast the frames came, and a record of the docker was a coin
## toss. `SaCaptureRun.shoot` now has `SaShotSettle` settle every chooser first,
## along with the layer thumbnails, and the boot's held scan with it. This suite
## holds the drain and the scan. That the picture comes out the same twice is
## the scenario's, `a-shot-waits-for-the-brush-presets-tiles-to-draw-their-pictures`.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## A cell's picture is a rendered stroke through the real paint path.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_p13_a_shot_and_the_presets")
static var shot_dir: String = SaDataRoot.path("test_p13_the_shots")


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    ScratchFolder.clear(shot_dir)


func after_each() -> void:
    ScratchFolder.clear(scratch_dir)
    ScratchFolder.clear(shot_dir)


## A chooser in the tree over the three shipped presets, none of them drawn.
func _chooser_in_the_tree() -> SaBrushPresetsChooser:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript)
    var chooser := SaBrushPresetsChooser.new()
    EventBus.add_child(chooser)
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return BrushSettingsScript.new())
    return chooser


func test_settling_draws_every_picture_a_chooser_still_has_waiting() -> void:
    var chooser := _chooser_in_the_tree()
    chooser._process(0.0)
    assert_true(int(chooser.chooser_report()["pending"]) > 0, "A frame's share leaves a picture waiting")

    var scanned := SaShotSettle.settle(EventBus)
    var report := chooser.chooser_report()
    assert_false(scanned, "A boot that held no scan has none to read")
    assert_eq(int(report["pending"]), 0, "No picture is left waiting")
    assert_eq(int(report["drawn"]), 3, "every cell has its own")
    for cell in chooser.grid.get_children():
        assert_not_null((cell.get_node("Icon") as Button).icon, "%s shows its picture" % cell.name)
    chooser.free()


func test_a_shot_leaves_no_chooser_with_a_picture_waiting() -> void:
    var chooser := _chooser_in_the_tree()
    assert_eq(int(chooser.chooser_report()["pending"]), 3, "Nothing is drawn when the shot is asked for")

    var run := SaCaptureRun.new(shot_dir)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
    run.shoot("tiles")
    assert_eq(int(chooser.chooser_report()["pending"]), 0, "The shot drew the queue before it took the frame")
    assert_true(FileAccess.file_exists(shot_dir.path_join("tiles.png")), "and still wrote its picture")
    assert_eq(run.steps.size(), 0, "A shot with nothing to scan is taken where it stands")
    chooser.free()


## The boot holds the store unread for a few frames, and a shot in them has no
## tile to draw on. The settle reads it, and asks for the shot again a frame
## later, since the cells it built are laid out at the end of this one.
func test_a_shot_in_the_held_boot_reads_the_store_and_is_taken_a_frame_later() -> void:
    var host := Node.new()
    EventBus.add_child(host)
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var bar := ToolOptionsBar.new()
    bar.name = "ToolOptionsBar"
    host.add_child(bar)
    var presets := bar.preset_box
    presets.hold_scan()
    bar.preset_store.dir = scratch_dir
    bar.preset_store.save_preset("Ink", StampSettingsScript.new())
    bar.preset_store.save_preset("Chalk", StampSettingsScript.new())
    bar.target_tool_machine = machine
    var docker := BrushPresetsDocker.new()
    host.add_child(docker)
    docker.rebind()
    assert_eq(docker.chooser.grid.get_child_count(), 0, "Held, the docker has no tile")

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
    var run := SaCaptureRun.new(shot_dir)
    run.shoot("held")
    assert_false(presets.scan_held, "The shot released the hold")
    assert_eq(docker.chooser.grid.get_child_count(), 2, "so the docker has a tile for each preset")
    assert_eq(int(docker.chooser.chooser_report()["pending"]), 0, "each with its picture")
    assert_false(FileAccess.file_exists(shot_dir.path_join("held.png")), "and no picture before the cells are laid out")
    assert_eq(run.steps, [{"wait": 1}, {"shot": "held"}], "The shot is asked for again a frame later")

    EventBus.remove_child(host)
    host.free()
    Fixtures.teardown(surface, machine)
