## The brush presets are read after the boot's first frame.
##
## The boot holds the bar's preset group before binding it to the tool
## machine, and `MainDockers` releases it a frame after the first frame after
## `ready`. What a suite can prove without frames is the hold itself: a held
## group reads nothing when the bar is bound, a docker shown while it is held
## waits rather than listing the directory, and the scan lists every preset in
## both, marks `presets_scanned` and runs once. The order against the first
## frame is the scenario's, `the-brush-presets-are-read-after-the-first-frame`.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## The bar builds against a tool machine, which needs a RenderingDevice.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_n2_presets_scan")


func before_each() -> void:
    ScratchFolder.empty(scratch_dir)


func after_each() -> void:
    ScratchFolder.empty(scratch_dir)


func test_a_held_group_reads_nothing_until_the_scan_and_the_docker_waits_for_it() -> void:
    var host := Node.new()
    # In the tree, because the docker finds the bar's preset group by name from
    # the scene root.
    EventBus.add_child(host)
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")

    var bar := ToolOptionsBar.new()
    bar.name = "ToolOptionsBar"
    host.add_child(bar)
    var presets := bar.preset_box
    assert_false(presets.scan_held, "A group nobody held lists on its first refresh, as every other suite's does")
    presets.hold_scan()
    bar.preset_store.dir = scratch_dir
    bar.preset_store.save_preset("Ink", StampSettingsScript.new())
    bar.preset_store.save_preset("Chalk", StampSettingsScript.new())
    var listings_before := bar.preset_store.listings
    bar.target_tool_machine = machine
    assert_eq(presets.preset_names().size(), 0, "Bound to the machine while held, the group lists nothing")
    assert_eq(bar.preset_store.listings, listings_before, "and never read the directory")

    var docker := BrushPresetsDocker.new()
    host.add_child(docker)
    assert_true(docker.rebind(), "A docker shown while the scan is held has a bar to wait on")
    assert_true(docker.chooser.store == null, "and binds no store yet")
    assert_eq(docker.chooser.grid.get_child_count(), 0, "so its grid is empty rather than read in a boot frame")
    assert_true(presets.scanned.is_connected(docker.rebind), "It waits on the scan")

    presets.scan()
    assert_false(presets.scan_held, "The scan releases the hold")
    assert_true(SaBootMarks.has_mark(&"presets_scanned"), "and marks the boot table")
    var names := presets.preset_names()
    assert_true(names.has("Ink") and names.has("Chalk"), "The bar lists both presets after it: %s" % [names])
    var listed := docker.chooser.visible_names()
    assert_true(listed.has("Ink") and listed.has("Chalk"), "and so does the docker that waited: %s" % [listed])
    assert_eq(listed.size(), names.size(), "every preset the bar lists")
    assert_false(presets.scanned.is_connected(docker.rebind), "The wait was one shot")

    var mark: float = SaBootMarks.table()["marks"][&"presets_scanned"]
    presets.hold_scan()
    presets.scan()
    assert_eq(SaBootMarks.table()["marks"][&"presets_scanned"], mark, "A second scan keeps the first mark")

    EventBus.remove_child(host)
    host.free()
    Fixtures.teardown(surface, machine)


## A group never held is what a suite's bar and a module's surface are, and
## `scan` has nothing to release there.
func test_a_group_never_held_scans_nothing() -> void:
    var presets := ToolOptionsPresets.new()
    var fired: Array[bool] = [false]
    var on_scanned := func() -> void: fired[0] = true
    presets.scanned.connect(on_scanned)
    presets.scan()
    assert_false(fired[0], "No hold, no scan and no signal")
    presets.free()
