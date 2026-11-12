## The engine's name shows at the top of the preset editor and not under the
## preset cells.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The engine type does not show and disappear after selecting, it shows inside
## the preset editor at the top instead. A cell carried a muted line naming its
## engine only where that engine was not the one in hand, so a pick that moved the
## Brush to the other engine moved the line from one set of cells to the other,
## and a cell that gained it grew.
##
## The docker half is built the way the app builds it, the three modules through
## the door and the real bar and docker over a store of a stamp preset and a
## noise preset. A pick goes through the chooser's own `preset_chosen`, which is
## what a press on a cell sends, and a hover through the tile's own
## `mouse_entered`. The editor half binds a detached window, because a `Window`
## added to the tree in a headless run hangs.
##
## The shots are `scenarios/the-engine-s-name-shows-at-the-top-of-the-preset-editor-and-not-under-the-preset-cells.json`.
extends "res://tests/test_framework.gd"

## The machine builds every tool and the window a scratchpad, which need a
## RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const NoiseSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")

static var scratch_dir: String = SaDataRoot.path("test_engine_name")


## A tool that holds whichever settings it is handed, so the window can be
## bound to either engine without the module's tool.
class HeldTool:
    extends ToolState

    var settings: Resource = null

    func _init(with_settings: Resource = null) -> void:
        settings = with_settings


var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _host: Node = null
var _bar: ToolOptionsBar = null


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    _modules.clear()
    for script: GDScript in [StampModuleScript, BaseModuleScript, NoiseModuleScript]:
        var module: SaModule = script.new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)


func after_each() -> void:
    if _host != null:
        EventBus.remove_child(_host)
        _host.free()
        _host = null
        _bar = null
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    for module: SaModule in _modules:
        module.unregister(_registries.context)
        _registries.context.for_module(module.get_id()).remove_all_registrations()
    _modules.clear()
    _registries = null
    ScratchFolder.clear(scratch_dir)


## The bar and the Brush Presets docker in the tree, over a stamp preset and a
## noise preset.
func _shelf() -> BrushPresetsDocker:
    _host = Node.new()
    _host.name = "EngineNameHost"
    # In the tree, because the docker finds the bar's preset group by name from
    # the scene root.
    EventBus.add_child(_host)
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_dir
    _bar.preset_store.save_preset("Ink", StampSettingsScript.new())
    _bar.preset_store.save_preset("Grain", NoiseSettingsScript.new())
    _bar._ready()
    var docker := BrushPresetsDocker.new()
    _host.add_child(docker)
    docker.rebind()
    return docker


## The cells holding any node of the engine line, by name.
func _lines(docker: BrushPresetsDocker) -> Array[String]:
    var held: Array[String] = []
    docker.after_pick.settle_all()
    for cell: Node in docker.chooser.grid.get_children():
        if cell.get_node_or_null("Engine") != null:
            held.append(String(cell.name))
    return held


## Each cell's child count and the height it asks for, so a label that came and
## went would show as a change.
func _shapes(docker: BrushPresetsDocker) -> Dictionary:
    var shapes := {}
    for cell: Node in docker.chooser.grid.get_children():
        var name_label := cell.get_node("Name") as Label
        shapes[name_label.text] = [cell.get_child_count(), (cell as Control).get_combined_minimum_size().y]
    return shapes


func _cell(docker: BrushPresetsDocker, preset_name: String) -> Control:
    for cell: Node in docker.chooser.grid.get_children():
        if (cell.get_node("Name") as Label).text == preset_name:
            return cell as Control
    return null


## "Hide it": a pick of each engine's preset and a hover over each cell leave no
## node of the engine line under any cell, and no cell changes shape.
func test_no_cell_carries_the_engine_line_after_a_pick_or_a_hover() -> void:
    _machine.set_active_tool(&"brush")
    var docker := _shelf()
    assert_eq(_lines(docker), [] as Array[String], "A fresh grid carries no engine line")
    var before := _shapes(docker)
    for preset_name: String in ["Grain", "Ink", "Grain"]:
        docker.chooser.preset_chosen.emit(preset_name)
        assert_eq(_lines(docker), [] as Array[String], "No cell carries one after %s is picked" % preset_name)
        for hovered: String in ["Ink", "Grain"]:
            var cell := _cell(docker, hovered)
            assert_not_null(cell, "%s has a cell" % hovered)
            if cell == null:
                continue
            cell.mouse_entered.emit()
            assert_eq(_lines(docker), [] as Array[String], "nor while %s is hovered" % hovered)
            cell.mouse_exited.emit()
    assert_eq(_machine.active_tool_name, NoiseModuleScript.TOOL_ID, "The last pick put the Brush on the noise engine")
    assert_eq(_shapes(docker), before, "and every cell has the children and the height it started with")


## "The cell's tooltip may still name the engine."
func test_the_tooltip_still_names_the_engine() -> void:
    _machine.set_active_tool(&"brush")
    var docker := _shelf()
    docker.after_pick.settle_all()
    var cells: Dictionary = docker.engine_marks.report()["cells"]
    assert_true(String((cells["Ink"] as Dictionary)["tooltip"]).begins_with("Ink, a Stamp preset"), "Ink's tooltip names it")
    assert_true(String((cells["Grain"] as Dictionary)["tooltip"]).begins_with("Grain, a Noise preset"), "and Grain's")


## "Show it inside the preset editor at the top": the editor opened on a noise
## preset and on a stamp preset names the engine beside the preset's name.
func test_the_editor_names_the_engine_beside_the_preset_at_its_top() -> void:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    var noise: Resource = NoiseSettingsScript.new()
    var stamp: Resource = StampSettingsScript.new()
    var noise_name := store.save_preset("Grain", noise)
    var stamp_name := store.save_preset("Ink", stamp)
    var cases := [[noise, noise_name, "Noise"], [stamp, stamp_name, "Stamp"]]
    for case: Array in cases:
        var window := SaBrushEditorWindow.new()
        window.bind_tool(HeldTool.new(case[0] as Resource), [], store, String(case[1]))
        var bar := window.preset_bar
        assert_eq(bar.preset_label.text, String(case[1]), "The editor is on %s" % case[1])
        assert_eq(bar.engine_label.text, String(case[2]), "and names its engine, %s" % case[2])
        assert_true(bar.engine_label.visible, "which shows")
        assert_eq(bar.engine_label.get_parent(), bar.preset_label.get_parent(), "on the preset name's own row")
        assert_true(bar.engine_label.get_index() > bar.preset_label.get_index(), "after the name, so it reads beside it")
        var dump := window.editor_report()
        assert_eq(String(dump.get("engine", "")), String(case[2]), "and the editor's dump says the same")
        window.free()
