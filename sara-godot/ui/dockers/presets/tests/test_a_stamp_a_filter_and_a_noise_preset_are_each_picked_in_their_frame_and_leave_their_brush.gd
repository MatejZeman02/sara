## A stamp, a filter and a noise preset are each picked in their frame and leave
## their brush.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A frame of 104 to 150 ms was read for every preset picked,
## 78 to 113 ms of it the pick, and the filter and noise presets cost the most.
## The pick rebuilt the docker's whole grid to move the mark, every kept cell
## entering the grid again, then dimmed every cell again for the engine the pick
## switched to and wrote Recent Presets with its pictures. A pick now builds the
## two cells the mark leaves and reaches, and leaves the redim and Recent Presets
## for the frame after, through `PresetPickAfter`.
##
## Built as the app builds it: the four modules registered through the door, a
## machine bound to their registry, and the real bar, Brush Presets docker and
## Recent Presets docker in the tree. Each preset is picked through the docker's
## `apply_preset`, the call the grid and the door's `pick_preset` end in. A suite
## has no frame to wait for (an `await` here would drop the assertions after it),
## so the frame after is run by `settle_all`, as the tree's next frame runs it.
extends "res://tests/test_framework.gd"

## The machine builds every tool, which needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const FilterModuleScript = preload("res://modules/sara-base-modules/filter-brush/module.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const NoiseSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const FilterSettingsScript = preload("res://modules/sara-base-modules/filter-brush/filter_brush_settings.gd")
const HistoryScript = preload("res://ui/dockers/presets/history_docker.gd")
const PresetEngineMarksScript = preload("res://ui/dockers/presets/preset_engine_marks.gd")
const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")

const STAMP: String = "Ink Pick"
const FILTER: String = "Soften Pick"
const NOISE: String = "Cloud Pick"

## Radii nothing starts at, so each pick is seen on the brush it leaves.
const STAMP_RADIUS: float = 0.031
const FILTER_RADIUS: float = 0.052
const NOISE_RADIUS: float = 0.073

static var scratch_dir: String = SaDataRoot.path("test_pick_preset_pick")
static var scratch_list: String = SaDataRoot.path("test_pick_preset_history.cfg")

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _host: Node = null
var _bar: ToolOptionsBar = null
var _docker: BrushPresetsDocker = null
var _history: HistoryDocker = null

## The cells that entered the grid since the count was last cleared.
var _entered: Array[String] = []


func before_each() -> void:
    _clear()
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    # The stamp first, as the app loads it, so a fresh machine starts on the
    # Brush, and the filter brush after it, which it depends on.
    _modules.clear()
    for script: GDScript in [StampModuleScript, BaseModuleScript, NoiseModuleScript, FilterModuleScript]:
        var module: SaModule = script.new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)
    _machine.set_active_tool(&"brush")
    _shelf()


func after_each() -> void:
    if _host != null:
        EventBus.remove_child(_host)
        _host.free()
        _host = null
    _bar = null
    _docker = null
    _history = null
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    for module: SaModule in _modules:
        module.unregister(_registries.context)
        _registries.context.for_module(module.get_id()).remove_all_registrations()
    _modules.clear()
    _registries = null
    _clear()


func test_a_stamp_preset_leaves_the_stamp_brush_at_its_size() -> void:
    _pick(STAMP)
    var settings := _in_hand()
    assert_eq(settings.get_script(), StampSettingsScript, "The stamp preset leaves the stamp's settings in the hand")
    assert_almost_eq(float(settings.get("radius")), STAMP_RADIUS, 1e-6, "at its own size")
    _assert_picked(STAMP)


func test_a_filter_preset_leaves_the_filter_brush_at_its_size() -> void:
    _pick(FILTER)
    var settings := _in_hand()
    assert_eq(_machine.active_tool_name, FilterModuleScript.TOOL_ID, "The filter preset puts the filter brush in the hand")
    assert_eq(settings.get_script(), FilterSettingsScript, "with the filter brush's settings")
    assert_almost_eq(float(settings.get("radius")), FILTER_RADIUS, 1e-6, "at its own size")
    _assert_picked(FILTER)


func test_a_noise_preset_leaves_the_noise_engine_at_its_size() -> void:
    _pick(NOISE)
    var settings := _in_hand()
    assert_eq(settings.get_script(), NoiseSettingsScript, "The noise preset leaves the noise engine's settings in the hand")
    assert_almost_eq(float(settings.get("radius")), NOISE_RADIUS, 1e-6, "at its own size")
    _assert_picked(NOISE)


## The three in a row, each back to the one before, so the mark moves from a
## cell of one engine to a cell of another every time.
func test_three_picks_in_a_row_each_build_two_cells_at_most() -> void:
    for stored_name: String in [STAMP, FILTER, NOISE, STAMP]:
        _pick(stored_name)
        _assert_picked(stored_name)
    assert_almost_eq(float(_in_hand().get("radius")), STAMP_RADIUS, 1e-6, "and the last pick is the brush in the hand")


func test_a_pick_leaves_the_redim_and_the_recent_rows_for_the_frame_after() -> void:
    _pick(STAMP, false)
    _pick(NOISE, false)
    assert_eq(_history.entries[0], NOISE, "The pick is first in Recent Presets' order in its own frame")
    assert_true(_history.after_pick.waits(&"rows"), "and its rows wait for the frame after")
    assert_null(_history.rows.get_node_or_null("Row_" + NOISE), "so there is no row for it yet")
    _history.after_pick.settle_all()
    assert_not_null(_history.rows.get_node_or_null("Row_" + NOISE), "and the frame after writes it")
    var stored := ConfigFile.new()
    stored.load(_history.path)
    var names: PackedStringArray = stored.get_value(HistoryDocker.SECTION, HistoryDocker.KEY, PackedStringArray())
    assert_eq(names[0] if not names.is_empty() else "", NOISE, "with the list's file")


## The bar's values wait for a frame after the docker's redim rather than the
## same one, so neither holds the frame after the pick alone.
func test_the_bar_shows_a_pick_in_a_frame_after_the_redim() -> void:
    _pick(FILTER, false)
    assert_true(_bar.after.waits(&"values"), "The bar's values wait after the pick")
    var redim_in: int = _docker.after_pick._due_in.get(&"redim", 0)
    var values_in: int = _bar.after._after._due_in.get(&"values", 0)
    assert_true(values_in > redim_in, "in a frame after the redim's: %d against %d" % [values_in, redim_in])
    _bar.after.settle_all()
    assert_almost_eq(_bar.control_for(&"radius").value, FILTER_RADIUS, 1e-6, "and the frame shows the filter's size")


## Hidden, the bar keeps a pick's values until it is shown again.
func test_a_hidden_bar_shows_a_pick_once_it_is_shown() -> void:
    _bar.visible = false
    _pick(NOISE, false)
    assert_true(_bar.after.waits(&"values"), "The hidden bar holds the values")
    assert_false(_bar.after._after.waits(&"values"), "and no frame is asked for them")
    _bar.visible = true
    assert_true(_bar.after._after.waits(&"values"), "Shown, they wait for a frame")
    _bar.after.settle_all()
    assert_almost_eq(_bar.control_for(&"radius").value, NOISE_RADIUS, 1e-6, "which shows the noise brush's size")


## The bar, the Brush Presets docker and Recent Presets in the tree, over a store
## of one preset of each engine.
func _shelf() -> void:
    _host = Node.new()
    _host.name = "PresetPickHost"
    # In the tree, because the docker finds the bar's preset group by name from
    # the scene root.
    EventBus.add_child(_host)
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_dir
    var stamp: Resource = StampSettingsScript.new()
    stamp.radius = STAMP_RADIUS
    _bar.preset_store.save_preset(STAMP, stamp)
    var filter: Resource = FilterSettingsScript.new()
    filter.radius = FILTER_RADIUS
    _bar.preset_store.save_preset(FILTER, filter)
    var noise: Resource = NoiseSettingsScript.new()
    noise.radius = NOISE_RADIUS
    _bar.preset_store.save_preset(NOISE, noise)
    _bar._ready()
    _history = HistoryScript.new()
    _history.path = scratch_list
    _history.store.dir = scratch_dir
    _host.add_child(_history)
    _docker = BrushPresetsDocker.new()
    _host.add_child(_docker)
    _docker.rebind()
    _docker.chooser.grid.child_entered_tree.connect(_note_entered)


## Picks *stored_name* as the grid does, counting the cells the pick builds, and
## with *settled* runs the frame after it.
func _pick(stored_name: String, settled: bool = true) -> void:
    _entered.clear()
    assert_true(_docker.apply_preset(stored_name), "%s is picked" % stored_name)
    var built := _entered.duplicate()
    var said := "Picking %s builds the two cells the mark moves between at most: %s" % [stored_name, built]
    assert_true(built.size() <= 2, said)
    assert_true(built.has(stored_name), "among them its own: %s" % [built])
    if settled:
        _docker.after_pick.settle_all()
        _history.after_pick.settle_all()
        _bar.after.settle_all()


## What the docker shows once a pick of *stored_name* is settled.
func _assert_picked(stored_name: String) -> void:
    assert_eq(_bar.preset_box.selected_preset, stored_name, "The bar holds %s" % stored_name)
    assert_eq(_docker.chooser._marked, stored_name, "and its cell is the one marked")
    var marked := 0
    for cell: Node in _docker.chooser.grid.get_children():
        if cell.name.begins_with("Cell_") and _is_marked(cell):
            marked += 1
    assert_eq(marked, 1, "one cell carries the mark")
    var cells: Dictionary = _docker.engine_marks.report()["cells"]
    for preset_name: String in [STAMP, FILTER, NOISE]:
        var dimmed := bool((cells.get(preset_name, {}) as Dictionary).get("dimmed", false))
        var wanted := PresetEngineMarksScript.is_foreign(_bar.preset_store.engine_for(preset_name), _docker.tool_engines())
        assert_eq(dimmed, wanted, "%s is dimmed exactly when the tool in hand refuses it" % preset_name)


## Whether *cell*'s picture carries the mark `SaBrushPresetsChooser.draw_mark` draws.
func _is_marked(cell: Node) -> bool:
    var button := cell.get_node_or_null("Icon") as Button
    return button != null and button.has_theme_stylebox_override("normal")


func _in_hand() -> Resource:
    return _machine.active_tool.get("settings") as Resource


func _note_entered(node: Node) -> void:
    if node.name.begins_with("Cell_"):
        _entered.append(String(node.get_meta(SaBrushPresetsChooser.PRESET_META, "")))


func _clear() -> void:
    if FileAccess.file_exists(scratch_list):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_list))
    ScratchFolder.clear(scratch_dir)
