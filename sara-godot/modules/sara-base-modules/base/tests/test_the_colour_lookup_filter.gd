## The palette registers through the door as the colour lookup, and the
## adjustments leave the skeleton.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## What the move must not have cost a painter: the command id a profile may
## have rebound, `filter_palette`, and the row in the Filter menu, which reads
## "Colour Lookup" under the base module's name, which is Colour Lookup
## and not Palette. And what it must have cost the skeleton:
## the engine, the kernels, the signal and the dialog. The pass is
## `test_palette_filter.gd` and `test_palette_chip_bands.gd` beside
## this, and the chips `test_palette_chip_editor.gd` and
## `test_palette_add_chip.gd`.
extends "res://tests/test_framework.gd"

const MODULE_ID := &"sara-base-modules"
const ACTION := &"filter_palette"

const RED := Color(0.9, 0.15, 0.1, 1.0)
const BLUE := Color(0.1, 0.2, 0.85, 1.0)


## The skeleton's own commands and the seven filters, registered in the order
## the base module registers them.
func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var ctx := registries.context.for_module(MODULE_ID)
    assert_true(ctx.register_filter_section(&"tone", "Tone", 100), "the Tone section registers")
    assert_true(ctx.register_filter_section(&"color", "Colour", 200), "the Colour section registers")
    assert_true(ctx.register_filter(SaBrightnessContrastFilter.new()), "Brightness/Contrast registers")
    assert_true(ctx.register_filter(SaExposureFilter.new()), "Exposure registers")
    assert_true(ctx.register_filter(SaHueSaturationLightnessFilter.new()), "Hue/Saturation/Lightness registers")
    assert_true(ctx.register_filter(SaColorBalanceFilter.new()), "Colour Balance registers")
    assert_true(ctx.register_filter(SaLevelsFilter.new()), "Levels registers")
    assert_true(ctx.register_filter(SaCurvesFilter.new()), "Curves registers")
    assert_true(ctx.register_filter(SaColorLookupFilter.new()), "Colour Lookup registers")
    return registries


## The id is what the `palette` step and a module that replaces the filter find
## it by, and the command is what a rebound chord is written against.
func test_the_lookup_keeps_the_id_and_the_command_the_palette_had() -> void:
    var registries := _registries()
    assert_true(registries.filters.has(StringName("%s.palette" % MODULE_ID)), "the filter is keyed by the kind it always was")
    assert_true(registries.commands.has(ACTION), "%s is registered" % ACTION)
    var command := registries.commands.get_descriptor(ACTION)
    assert_eq(command.owner_module, MODULE_ID, "and the module owns it now")
    assert_eq(command.title, "Colour Lookup", "under its name")
    assert_eq(registries.commands.chord_text(ACTION), "", "with no chord of its own, as it shipped")
    for kind: StringName in SaPointAdjust.KINDS:
        assert_true(registries.filters.has(StringName("%s.%s" % [MODULE_ID, kind])), "%s is a filter keyed by its kind" % kind)


## The skeleton registered nothing for the six, so the module's registration
## is the only one and is not refused for a name already taken.
##
## Read against the commands the module's filters answer to rather than every
## id that begins with `filter_`, because the skeleton's Filter > Apply Again
## is `filter_apply_again`, Krita's name for it, and is
## no adjustment.
func test_the_skeleton_registers_no_adjustment_of_its_own() -> void:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    assert_true(registries.filters.list_keys().is_empty(), "The skeleton registers no filter")
    var module := _registries().filters
    for key: StringName in module.list_keys():
        var command_id := SaFilterRegistry.command_for(key, module.get_filter(key))
        assert_false(registries.commands.has(command_id), "%s is not the skeleton's to register" % command_id)


## A rebind is written onto the InputMap action by the command's id, so the id
## the filter declares is the whole of what keeps it.
func test_a_profile_that_bound_the_palette_keeps_its_chord() -> void:
    var registries := _registries()
    var shipped := SaShortcutStore.chords_for(ACTION)
    SaShortcutStore.set_chords(ACTION, ["Ctrl+Alt+P"])
    assert_eq(registries.commands.chord_text(ACTION), "Ctrl+Alt+P", "The rebind lands on the filter's command")
    var again := _registries()
    assert_eq(again.commands.chord_text(ACTION), "Ctrl+Alt+P", "and a second registration leaves it alone")
    SaShortcutStore.set_chords(ACTION, shipped)
    assert_eq(again.commands.chord_text(ACTION), "", "Put back, for the suites after this one")


func test_the_filter_menu_lists_it_last_of_its_family() -> void:
    var registries := _registries()
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(registries.commands)
    var menu := bar.menu("Filter") as SaFilterMenu
    menu.filters = registries.filters
    var popup := menu.show_section(menu.section_item(&"color"))
    var labels := Array(popup.row_labels())
    var at := labels.find("Colour Balance")
    assert_true(at >= 0, "Colour Balance is in the Colour list")
    assert_eq(labels[at + 1], "Colour Lookup", "and the colour lookup follows it, last of the colour section")
    assert_false(labels.has("Palette..."), "and the skeleton's own row is gone")
    var hints: Dictionary = {}
    for entry: Dictionary in popup.row_report():
        hints[String(entry.get("label", ""))] = String(entry.get("hint", ""))
    assert_eq(hints.get("Colour Lookup", "?"), "", "with no chord beside it, where the old row printed an unset one")
    bar.free()


## The panel is what the filter reads when it runs: every chip is a colour
## the pass takes, and one `changed` asks for the rerun.
func test_the_panel_is_what_the_filter_reads() -> void:
    var panel := SaPalettePanel.new([RED, BLUE])
    var heard: Array = [0]
    panel.changed.connect(func() -> void: heard[0] += 1)
    var said := panel.capture_option_edit({"chips": [1], "shadows": 100})
    assert_eq(heard[0], 1, "one set is one rerun")
    assert_true(said.begins_with("SaCapture: palette {"), "and the door answers what it left: %s" % said)
    var values := panel.values()
    assert_true(((values["palette"] as Array)[1] as Color).is_equal_approx(BLUE), "both chips are the palette")
    var table := SaPointAdjust.table(values)
    assert_almost_eq(table[SaPointAdjust.PALETTE_BASE], 2.0, 1e-6, "which the pass reads as two colours")
    assert_almost_eq(table[SaPointAdjust.PALETTE_BANDS], 0.0, 1e-6, "the red the step did not name at no shadows")
    assert_almost_eq(table[SaPointAdjust.PALETTE_BANDS + 4], 1.0, 1e-6, "and the named blue's at full")
    var read := panel.capture_option_edit({"read": true})
    assert_eq(heard[0], 1, "and a read moves nothing")
    assert_true(read.contains("#1a33d9"), "while naming the colour as a painter would type it: %s" % read)
    panel.free()


## A filter with no dialog open answers the picture unchanged, so a read before
## the first open is not an error and not a palette left over.
func test_a_filter_nobody_opened_holds_no_palette() -> void:
    var values := SaColorLookupFilter.new().values()
    assert_eq((values["palette"] as Array).size(), 0, "no colour")
    assert_almost_eq(float(values["influence"]), 1.0, 1e-6, "and the bands every colour starts at")


## The engine, the signal and the step's old word
## are gone from the three layers that carried them.
func test_the_skeleton_names_no_adjustment() -> void:
    var gone: Array[String] = [
        "res://core/image/sa_adjustments.gd",
        "res://shaders/compute/adjust.gmacs",
        "res://ui/adjust/palette_dialog.gd",
        "res://ui/widgets/sa_gradient_slider.gd",
        "res://harness/drivers/sa_adjust_driver.gd",
    ]
    for path in gone:
        assert_false(FileAccess.file_exists(path), "%s left the skeleton" % path)
    var hits: Array[String] = []
    for root: String in ["res://core", "res://ui", "res://render"]:
        _grep(root, hits)
    assert_true(hits.is_empty(), "No file of core, ui or render names the engine or its signal: %s" % ", ".join(hits))
    var moved := "res://modules/sara-base-modules/base/shaders/adjust.gmacs"
    assert_true(FileAccess.file_exists(moved), "and the kernels are the module's")


func _grep(dir_path: String, hits: Array[String]) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    for sub in dir.get_directories():
        if sub == "tests":
            continue
        _grep("%s/%s" % [dir_path, sub], hits)
    for file in dir.get_files():
        if not file.ends_with(".gd"):
            continue
        var path := "%s/%s" % [dir_path, file]
        var source := FileAccess.get_file_as_string(path)
        for word: String in ["SaAdjust", "adjustment_requested", '"adjust"']:
            if source.replace("SaAdjustmentCache", "").replace('"adjust": ""', "").contains(word):
                hits.append("%s names %s" % [path, word])
