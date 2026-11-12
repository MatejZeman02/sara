## The Tip Image list is a grid of pictures filtered by folder.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Tip Image list is a grid of the tips' pictures with tags, as the brush
## presets are chosen, and not a list of names. The claim: the Tool Options
## docker, opened on the stamp brush and then on the noise brush on an image tip,
## draws one cell a tip, each with a picture, a folder chosen in the filter shows
## only its tips, and a press makes its tip the brush's.
##
## The docker is a Window, so it is built detached under a plain Node and its
## `_ready` never runs, which is what `test_tool_options_docker.gd` does and why.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const NoiseFieldsScript = preload("res://modules/sara-noise-brush-engine/noise_fields.gd")

## A surface builds an easel and a tip load uploads the picture.
const REQUIRES_GPU := true

const TIP_ROW: StringName = &"tip_image_path"
const NOISE_ID: StringName = &"d12_noise"
const TREE := "res://tips/tree.png"
const CORNER := "res://tips/corner.png"
## The picture a painter loads from a folder of their own, a copy of a shipped
## tip under a name no tip folder holds.
const LOADED_FILE := "scratch-corner.png"

static var scratch_dir: String = SaDataRoot.path("test_d12_tips")

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _host: Node = null
var _docker: ToolOptionsDocker = null
var _advanced: bool = false


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var file := FileAccess.open(_loaded(), FileAccess.WRITE)
    file.store_buffer(FileAccess.get_file_as_bytes(CORNER))
    file.close()
    SaBrushTipMask.forget_loaded_elsewhere()
    _advanced = SaSettings.advanced_options
    SaSettings.advanced_options = true
    _surface = Fixtures.make_surface()
    _machine = _bound_machine()
    _host = Node.new()
    _docker = ToolOptionsDocker.new()
    _host.add_child(_docker)
    _docker.target_tool_machine = _machine


func after_each() -> void:
    var stamp := _machine.get_tool("brush")
    if stamp != null:
        stamp.load_tip("")
    _host.free()
    Fixtures.teardown(_surface, _machine)
    SaSettings.advanced_options = _advanced
    SaBrushTipMask.forget_loaded_elsewhere()
    ScratchFolder.clear(scratch_dir)


func _loaded() -> String:
    return scratch_dir.path_join(LOADED_FILE)


## The fixture's machine with the noise brush registered as a tool of its own,
## because the fixture's registry carries the stamp and the base module and no
## engine.
func _bound_machine() -> ToolMachine:
    var fields: RefCounted = NoiseFieldsScript.new()
    fields.register_shipped(SaPatternStore.new([SaPatternStore.SHIPPED_DIR]))
    var descriptor := SaToolDescriptor.create(NOISE_ID, StateNoiseBrushScript)
    descriptor.options = NoiseModuleScript.options(fields)
    var registry := Fixtures.make_tool_registry()
    assert_true(registry.register(descriptor), "The noise brush registers as a tool")
    var machine := ToolMachine.new()
    machine.name = "ToolMachine"
    machine._ready()
    machine.bind(_surface, registry)
    return machine


## Shows *tool_id* in the docker holding *tip*, and answers the grid it draws.
func _open_on(tool_id: StringName, tip: String) -> SaTipGrid:
    _machine.set_active_tool(tool_id)
    assert_true(_machine.get_tool(tool_id).load_tip(tip), "%s loads %s" % [tool_id, tip])
    _docker.sync_from_tool()
    assert_true(_docker.shown_keys().has(TIP_ROW), "The docker draws the Tip Image row for %s" % tool_id)
    return _docker.options.control(TIP_ROW) as SaTipGrid


## The paths of the tips the door lists while the brush holds *held*.
func _listed(held: String) -> Array[String]:
    var out: Array[String] = []
    for entry: Dictionary in SaTipChoices.listing(held):
        out.append(String(entry["path"]))
    return out


## The claim, read the same way for either brush: one cell a tip, each with
## a picture, a folder chosen shows only its tips, and a press is the brush's tip.
func _read_the_grid(tool_id: StringName, grid: SaTipGrid, held: String) -> void:
    assert_not_null(grid, "The Tip Image row of %s is the door's grid" % tool_id)
    var report := grid.tip_grid_report()
    var listed := _listed(held)
    assert_eq(grid.cells.get_child_count(), listed.size(), "One cell a tip, %d of them" % listed.size())
    assert_eq(report["tips"], listed, "every tip the door lists shown under All")
    assert_eq(int(report["pictures"]), listed.size(), "and each cell carries a picture")
    assert_true(listed.has(TREE) and listed.has(_loaded()), "Sara's tips and the loaded one are among them")
    assert_eq(report["pressed"], [held] as Array[String], "The cell of what the brush holds is pressed, and no other")

    assert_true(grid.capture_option_edit({"folder": "Sara"}).contains("folder res://tips"), "The filter takes Sara")
    var shipped := grid.shown_paths()
    assert_true(shipped.has(TREE), "Sara's folder shows the tree")
    assert_false(shipped.has(_loaded()), "and not the picture loaded from elsewhere")
    for path: String in shipped:
        assert_eq(path.get_base_dir(), SaBrushTipMask.SHIPPED_DIR, "%s sits in Sara's folder" % path)
    assert_eq(grid.filter.text, "Folder: Sara", "The closed filter says which folder it shows")

    grid.capture_option_edit({"folder": scratch_dir.get_file()})
    assert_eq(grid.shown_paths(), [_loaded()] as Array[String], "The loaded picture's folder shows it alone")

    grid.capture_option_edit({"folder": "All"})
    assert_eq(grid.shown_paths(), listed, "and All shows every tip again")
    assert_true(grid.pick(TREE), "A press on the tree's cell")
    var settings: Resource = _machine.get_tool(tool_id).settings
    assert_eq(String(settings.tip.image_path), TREE, "makes the tree %s's tip" % tool_id)
    assert_eq(grid.tip_grid_report()["pressed"], [TREE] as Array[String], "and the tree's cell is the one pressed")
    assert_eq(ToolOptionsDocker.row_value(_docker.options.control(TIP_ROW)), TREE, "which the docker's row reports")
    _docker.sync_from_tool()
    assert_eq(grid.tip_grid_report()["pressed"], [TREE] as Array[String], "and still once the docker syncs again")


## The stamp brush, then the noise brush on an image tip, in the one docker.
func test_the_docker_draws_both_brushes_tip_image_as_a_grid() -> void:
    var stamp := _open_on(&"brush", _loaded())
    _read_the_grid(&"brush", stamp, _loaded())

    var noise := _open_on(NOISE_ID, _loaded())
    _read_the_grid(NOISE_ID, noise, _loaded())


## A tip loaded with Load Tip joins the grid under its folder, the filter
## growing a row for it, and stays once the brush moves to another tip.
func test_a_loaded_tip_joins_the_grid_under_its_folder() -> void:
    var grid := _open_on(&"brush", TREE)
    assert_false(grid.shown_paths().has(_loaded()), "Before the load the grid does not offer the picture")
    var builds := grid.builds
    var answer := grid.capture_option_edit({"load_tip": _loaded()})
    assert_true(answer.contains("loaded"), "The grid's Load Tip door loads through the tool: %s" % answer)
    assert_eq(grid.builds, builds + 1, "and the grid lists again around it")
    assert_true(grid.shown_paths().has(_loaded()), "which now offers it")
    assert_eq(grid.chosen, _loaded(), "pressed, because the brush holds it")
    var folders: Array = grid.tip_grid_report()["folders"]
    assert_eq(folders.front(), "All", "The filter starts on All")
    assert_eq(folders.back(), scratch_dir.get_file(), "and names the picture's folder last")

    assert_true(grid.pick(CORNER), "A press on another tip")
    assert_true(grid.shown_paths().has(_loaded()), "keeps the loaded picture in the grid")


## A sync that changes nothing builds nothing, so a docker syncing on every
## write does not read every tip's picture again.
func test_a_sync_that_changes_nothing_builds_no_cells() -> void:
    var grid := _open_on(&"brush", TREE)
    var builds := grid.builds
    _docker.sync_from_tool()
    _docker.sync_values_from_tool()
    assert_eq(grid.builds, builds, "Two syncs later the cells are the ones built")
