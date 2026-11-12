## Every preset tile shows its own stroke, and the engine only where it differs.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Three sweeps read the Brush Presets grid as one glyph repeated, as blank
## tiles over "Stamp", and as strokes too small to read at 72 by 36. The strokes
## were the presets' own all along, rendered at 128 by 64 and drawn at about
## half of it. So a fresh profile draws the cells 56 wide since the release
## evening made the default small, the slider reaches
## the 128 they are rendered at. The engine is in each tile's tooltip and no
## tile carries a line of it, the brush editor names it at its top.
##
## Built the way the app builds it: the three modules registered through the
## door, a machine bound to their registry, and the real bar and docker over a
## store of a stamp preset, a noise preset and a stamp eraser. A tool switch is
## the machine's own, so the docker hears it on the bus and marks the cells it
## keeps, which is the path that moves the dim in the running app.
##
## The shots are `scenarios/every-preset-tile-shows-its-own-stroke-and-the-engine-only-where-it-differs.json`.
extends "res://tests/test_framework.gd"

## The machine builds every tool, which needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const NoiseSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")

## The width a fresh profile draws a cell at, the spec's, and the height of
## its stroke picture, which is rendered two to one. A tip is square, so a
## fresh profile, which opens on the tips, draws the picture 56 by 56 and a
## painter who picks Strokes sees 56 by 28.
const FRESH_ICON: int = 56
const FRESH_HEIGHT: int = 28

## The tooltip line an eraser's empty tile carries.
const ERASER_LINE: String = "An eraser draws nothing on a thumbnail"

static var scratch_dir: String = SaDataRoot.path("test_n26_preset_tiles")

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _host: Node = null
var _bar: ToolOptionsBar = null
var _saved_icon_size: int = 0
var _saved_thumb_tip: bool = true


func before_each() -> void:
    _saved_icon_size = SaSettings.preset_icon_size
    _saved_thumb_tip = SaSettings.preset_thumb_tip
    # The strokes, because every test below the two that measure a cell reads a
    # tile's stroke picture and the profile a painter starts on shows a tip.
    SaSettings.preset_thumb_tip = false
    _clear()
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    # The stamp first, as the app loads it, so a fresh machine starts on the
    # Brush rather than on the fill.
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
    SaSettings.preset_icon_size = _saved_icon_size
    SaSettings.preset_thumb_tip = _saved_thumb_tip
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
    _clear()


## The bar and the Brush Presets docker in the tree, over a store of a stamp
## preset, a noise preset and a stamp eraser.
func _shelf() -> BrushPresetsDocker:
    _host = Node.new()
    _host.name = "N26PresetTilesHost"
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
    var rub: Resource = StampSettingsScript.new()
    rub.blend_mode = SaLayer.BLEND_MODE.ERASE
    _bar.preset_store.save_preset("Rub", rub)
    _bar._ready()
    var docker := BrushPresetsDocker.new()
    _host.add_child(docker)
    docker.rebind()
    return docker


## The cells that hold a node of the engine line, by preset. The engine is named
## at the top of the brush editor and in each tooltip, so this is empty.
func _lines(docker: BrushPresetsDocker) -> Array[String]:
    var held: Array[String] = []
    docker.after_pick.settle_all()
    for cell: Node in docker.chooser.grid.get_children():
        if cell.get_node_or_null("Engine") != null:
            held.append(String(cell.name))
    return held


func _tooltip(docker: BrushPresetsDocker, preset_name: String) -> String:
    docker.after_pick.settle_all()
    var cells: Dictionary = docker.engine_marks.report()["cells"]
    return String((cells.get(preset_name, {}) as Dictionary).get("tooltip", ""))


## No tile carries an engine line, under the stamp, under the noise engine, or
## dimmed under the eraser, so a switch moves no cell.
func test_no_tile_carries_an_engine_line_under_either_engine() -> void:
    _machine.set_active_tool(NoiseModuleScript.TOOL_ID)
    var docker := _shelf()
    _machine.set_active_tool(&"brush")
    assert_eq(
        docker.tool_engines(),
        [&"stamp", &"liquify", &"noise"] as Array[StringName],
        "The Brush on the stamp takes the stamp first"
    )
    assert_eq(_lines(docker), [] as Array[String], "No tile carries an engine line under the stamp")
    _machine.set_active_tool(NoiseModuleScript.TOOL_ID)
    assert_eq(_lines(docker), [] as Array[String], "nor under the noise engine")
    _machine.set_active_tool(&"eraser")
    docker.after_pick.settle_all()
    var cells: Dictionary = docker.engine_marks.report()["cells"]
    assert_true(bool((cells["Grain"] as Dictionary)["dimmed"]), "The noise tile is dimmed under the eraser")
    assert_eq(_lines(docker), [] as Array[String], "and still carries no line")


## "The tooltip keeps naming the engine on every tile."
func test_every_tile_names_its_engine_in_its_tooltip() -> void:
    _machine.set_active_tool(&"brush")
    var docker := _shelf()
    _machine.set_active_tool(NoiseModuleScript.TOOL_ID)
    _machine.set_active_tool(&"brush")
    assert_true(_tooltip(docker, "Ink").begins_with("Ink, a Stamp preset"), "The stamp tile's tooltip names its engine")
    assert_true(_tooltip(docker, "Grain").begins_with("Grain, a Noise preset"), "and so does the noise tile's")
    assert_true(_tooltip(docker, "Rub").begins_with("Rub, a Stamp preset"), "and the eraser's")


## "An eraser preset stays empty, and its tile says so in its tooltip", on the
## line under the engine's, and a brush that paints says nothing of the kind.
func test_an_eraser_tile_says_why_it_is_empty() -> void:
    _machine.set_active_tool(&"brush")
    var docker := _shelf()
    _machine.set_active_tool(NoiseModuleScript.TOOL_ID)
    _machine.set_active_tool(&"brush")
    var lines := _tooltip(docker, "Rub").split("\n")
    assert_true(lines.size() >= 2, "The eraser's tooltip has a line under the engine's: %s" % [lines])
    if lines.size() >= 2:
        assert_eq(lines[1], ERASER_LINE, "which says why its tile is empty")
    assert_false(_tooltip(docker, "Ink").contains(ERASER_LINE), "A stamp brush's tooltip does not")
    assert_false(_tooltip(docker, "Grain").contains(ERASER_LINE), "nor a noise brush's")


## A preset saved over a name it held can turn a brush into an eraser, and the
## tooltip follows it rather than a reading taken before the save.
func test_a_save_that_makes_an_eraser_is_heard() -> void:
    _machine.set_active_tool(&"brush")
    var docker := _shelf()
    _machine.set_active_tool(NoiseModuleScript.TOOL_ID)
    _machine.set_active_tool(&"brush")
    assert_false(_tooltip(docker, "Ink").contains(ERASER_LINE), "Ink paints")
    var rub: Resource = StampSettingsScript.new()
    rub.blend_mode = SaLayer.BLEND_MODE.ERASE
    _bar.preset_store.save_preset("Ink", rub)
    EventBus.preset_store_changed.emit("Ink", true)
    for cell: Node in docker.chooser.grid.get_children():
        docker.engine_marks.mark(cell)
    assert_true(_tooltip(docker, "Ink").contains(ERASER_LINE), "and saved as an eraser its tooltip says so")


## "A fresh profile's cells are 56 wide." The cell the docker builds at the
## size a profile with no key reads, square on the tips it opens on and half as
## tall on the strokes a painter can pick instead.
func test_a_fresh_profiles_cells_are_56_wide() -> void:
    var fresh := SaSettingsValues.new()
    var icon: int = fresh.stored("preset_icon_size")
    var tip: bool = fresh.stored("preset_thumb_tip")
    fresh.free()
    assert_eq(icon, FRESH_ICON, "A profile with no key reads %d" % FRESH_ICON)
    assert_true(tip, "and opens on the tips")
    SaSettings.preset_icon_size = icon
    SaSettings.preset_thumb_tip = true
    _measure_cells(FRESH_ICON)


## And the strokes a painter can pick instead are rendered two to one, which is
## the picture this file's other tests read.
func test_a_cell_on_the_strokes_is_half_as_tall() -> void:
    SaSettings.preset_icon_size = FRESH_ICON
    SaSettings.preset_thumb_tip = false
    _measure_cells(FRESH_HEIGHT)


## Every cell of a fresh shelf is [constant FRESH_ICON] wide and *tall* tall.
func _measure_cells(tall: int) -> void:
    _machine.set_active_tool(&"brush")
    var docker := _shelf()
    var cells := docker.chooser.grid.get_children()
    assert_eq(cells.size(), 3, "The grid holds the three presets")
    for cell: Node in cells:
        var picture := cell.get_node("Icon") as Button
        assert_almost_eq(
            picture.custom_minimum_size.x, float(SaUI.px(FRESH_ICON)), 0.5, "%s is %d wide" % [cell.name, FRESH_ICON]
        )
        assert_almost_eq(picture.custom_minimum_size.y, float(SaUI.px(tall)), 0.5, "and %d tall" % tall)


## "MAX_ICON to 128": the largest cell is the width a stroke is rendered at, and
## the slider and the profile both stop there.
func test_the_largest_cell_is_the_width_a_stroke_is_rendered_at() -> void:
    assert_eq(SaBrushPresetsChooser.MAX_ICON, SaPresetThumbs.SIZE.x, "The ceiling is the rendered width")
    SaSettings.preset_icon_size = 500
    assert_eq(SaSettings.preset_icon_size, SaPresetThumbs.SIZE.x, "and the profile stops at it")
    var chooser := SaBrushPresetsChooser.new()
    assert_eq(int(chooser.size_slider.max_value), SaPresetThumbs.SIZE.x, "and so does the slider")
    chooser.free()


## "A profile that stored its own size keeps it." A load sets each key through
## its setter, so a stored 72, the old default, is read back as 72.
func test_a_stored_size_is_kept() -> void:
    var values := SaSettingsValues.new()
    values.set("preset_icon_size", 72)
    assert_eq(values.preset_icon_size, 72, "A stored 72 is kept")
    values.set("preset_icon_size", 128)
    assert_eq(values.preset_icon_size, 128, "and a stored 128 too")
    values.free()


func _clear() -> void:
    var thumbs := SaPresetThumbs.thumbs_dir(scratch_dir)
    for folder: String in [thumbs, scratch_dir]:
        if not DirAccess.dir_exists_absolute(folder):
            continue
        for file_name: String in DirAccess.get_files_at(folder):
            DirAccess.remove_absolute(folder.path_join(file_name))
        DirAccess.remove_absolute(folder)
