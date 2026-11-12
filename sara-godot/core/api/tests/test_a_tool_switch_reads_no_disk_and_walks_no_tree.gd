## A tool switch lists no folder and searches no tree.
##
## A stall triage found `EventBus.tool_changed` costing 29 ms, and three
## handlers doing the work. The presets group listed the presets folder two or
## three times and searched the whole tree for the docker twice, the docker
## searched it for the group three more times and listed the folder again, and
## the bar read every painting tool's values into its controls. The store keeps
## its listing now, both sides hold what they found, and the bar reads the tool
## switched to.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")

## The bar builds against a tool machine, which needs a RenderingDevice.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_c2_presets")

var _host: Node = null
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _bar: ToolOptionsBar = null
var _docker: BrushPresetsDocker = null


func before_each() -> void:
    ScratchFolder.empty(scratch_dir)


func after_each() -> void:
    if _host != null:
        EventBus.remove_child(_host)
        _host.free()
        _host = null
    if _surface != null or _machine != null:
        Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    ScratchFolder.empty(scratch_dir)


## Twenty switches between the brush and the eraser list the folder once at the
## most, and not at all after the first. The second is waited out before them,
## because a listing taken in the second the folder last changed is read again
## on the next ask, which is the store's guard and not a switch's cost.
func test_twenty_switches_list_the_folder_once() -> void:
    _build()
    OS.delay_msec(1100)
    _machine.set_active_tool(&"eraser")
    var after_first := _bar.preset_store.listings
    for index in 19:
        _machine.set_active_tool(&"brush" if index % 2 == 0 else &"eraser")
    assert_eq(_bar.preset_store.listings, after_first, "Nineteen switches after the first list the folder no more")
    assert_eq(_bar.preset_box._docker, _docker, "The group holds the docker it found")
    assert_eq(_docker._held_presets, _bar.preset_box, "and the docker holds the group it found")


## A preset saved from the bar is in the docker's grid at once, with no switch
## and no show between.
func test_a_preset_saved_from_the_bar_is_in_the_docker_at_once() -> void:
    _build()
    OS.delay_msec(1100)
    _machine.set_active_tool(&"eraser")
    _machine.set_active_tool(&"brush")
    assert_false(_docker.chooser.visible_names().has("Fresh"), "Nothing called Fresh to start with")
    assert_eq(_bar.save_current_as_preset("Fresh"), "Fresh", "The bar saves it")
    assert_true(_docker.chooser.visible_names().has("Fresh"), "and the docker lists it straight away")
    assert_true(_bar.preset_names().has("Fresh"), "as does the bar")


## A preset deleted by a file manager is gone at the next switch, from the bar
## and from the docker, although neither was told.
func test_a_preset_deleted_from_outside_is_gone_at_the_next_switch() -> void:
    _build()
    OS.delay_msec(1100)
    _machine.set_active_tool(&"eraser")
    assert_true(_docker.chooser.visible_names().has("Ink"), "Ink is in the grid")
    assert_eq(DirAccess.remove_absolute(scratch_dir.path_join("Ink.tres")), OK, "The file is removed behind Sara's back")
    _machine.set_active_tool(&"brush")
    assert_false(_bar.preset_names().has("Ink"), "The bar no longer lists it after the switch")
    assert_false(_docker.chooser.visible_names().has("Ink"), "and neither does the docker's grid")


## The store's own guard, with no wait: a listing taken in the second the
## folder changed is not trusted, so a file removed within that second is seen.
func test_a_listing_in_the_second_of_a_change_is_read_again() -> void:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.save_preset("Ink", StampSettingsScript.new())
    store.save_preset("Chalk", StampSettingsScript.new())
    assert_eq(store.list_names(), PackedStringArray(["Chalk", "Ink"]), "Both are listed")
    assert_eq(DirAccess.remove_absolute(scratch_dir.path_join("Ink.tres")), OK, "One goes behind the store's back")
    assert_eq(store.list_names(), PackedStringArray(["Chalk"]), "and the next ask does not list it")
    assert_false(store.has_preset("Ink"), "nor say it is there")


## Once the folder is older than the listing, asking again reads nothing, and a
## change moves the folder's time and is read.
func test_a_settled_listing_is_kept_until_the_folder_moves() -> void:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.save_preset("Ink", StampSettingsScript.new())
    OS.delay_msec(1100)
    store.list_names()
    var listed := store.listings
    for index in 5:
        store.list_names()
        store.has_preset("Ink")
    assert_eq(store.listings, listed, "Five asks on a settled folder list it no more")
    var file := FileAccess.open(scratch_dir.path_join("Wash.tres"), FileAccess.WRITE)
    file.store_string(FileAccess.get_file_as_string(scratch_dir.path_join("Ink.tres")))
    file.close()
    assert_true(store.list_names().has("Wash"), "A file written from outside is listed at the next ask")
    assert_eq(store.listings, listed + 1, "by one listing")


## The shipped recipes are checked once per template script. A second ask with
## the same template builds none and lists nothing.
func test_the_shipped_recipes_are_checked_once_per_template() -> void:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    var written := store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    assert_true(written > 0, "The first ask writes the shipped set")
    OS.delay_msec(1100)
    store.list_names()
    var listed := store.listings
    assert_eq(store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript), 0, "The second writes nothing")
    assert_eq(store.listings, listed, "and lists nothing")


## A switch between two tools that declare the same keys reads the new tool, and
## a switch to a tool that declares none puts the brush's values back, the rule
## `owner_of` names (f19), without reading every painting tool.
func test_a_switch_reads_the_tool_switched_to() -> void:
    _build()
    var brush: ToolState = _machine.get_tool(&"brush")
    var eraser: ToolState = _machine.get_tool(&"eraser")
    brush.settings.radius = 0.05
    eraser.settings.radius = 0.12
    _machine.set_active_tool(&"eraser")
    assert_almost_eq(_bar.control_for(&"radius").value, 0.12, 0.0005, "The eraser's size on the eraser")
    assert_eq(_bar._owners_left_showing(&"brush", &"eraser"), {}, "Brush to eraser reads no tool but the eraser")
    var owners := _bar._owners_left_showing(&"eraser", &"gradient")
    assert_eq(owners, {&"brush": true}, "Eraser to gradient reads the brush back")
    _machine.set_active_tool(&"gradient")
    assert_almost_eq(_bar.control_for(&"radius").value, 0.05, 0.0005, "and the size row shows the brush's, its owner")
    _machine.set_active_tool(&"brush")
    assert_almost_eq(_bar.control_for(&"radius").value, 0.05, 0.0005, "The brush's own on the brush")


## A bar and a docker in the tree over one scratch folder, with the brush shown
## and one preset of the stamp engine saved.
func _build() -> void:
    _host = Node.new()
    # In the tree, because the docker finds the bar's preset group by name from
    # the scene root, as `test_a_tool_switch_builds_the_presets_grid_at_most_once.gd`
    # says.
    EventBus.add_child(_host)
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_dir
    _bar.preset_store.save_preset("Ink", StampSettingsScript.new())
    _bar._ready()
    _docker = BrushPresetsDocker.new()
    _host.add_child(_docker)
    _docker.rebind()
