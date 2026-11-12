## Levels and Curves register through the door.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## What the move must not have cost a painter: Ctrl+L and Ctrl+M, the command
## ids a profile may have rebound, and the two rows in the Filter menu, which
## are under the base module's name now. The passes are `test_levels.gd` and
## `test_curves.gd` beside this, the handles `test_levels_bar.gd`, the
## histogram `test_levels_histogram.gd` and the sentences
## `test_levels_tooltips.gd`.
extends "res://tests/test_framework.gd"

const MODULE_ID := &"sara-base-modules"

## Command id -> the chord it shipped with before the move and ships with now.
const CHORDS := {
    &"filter_levels": "Ctrl+L",
    &"filter_curves": "Ctrl+M",
}


## The skeleton's own commands and the five filters, registered in the order
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
    assert_true(ctx.register_filter(SaHueSaturationLightnessFilter.new()), "Hue/Saturation/Lightness registers")
    assert_true(ctx.register_filter(SaColorBalanceFilter.new()), "Colour Balance registers")
    assert_true(ctx.register_filter(SaLevelsFilter.new()), "Levels registers")
    assert_true(ctx.register_filter(SaCurvesFilter.new()), "Curves registers")
    return registries


func test_the_two_keep_their_command_ids_and_their_chords() -> void:
    var registries := _registries()
    for command_id: StringName in CHORDS:
        assert_true(registries.commands.has(command_id), "%s is registered" % command_id)
        assert_eq(registries.commands.chord_text(command_id), CHORDS[command_id], "%s answers to it" % command_id)
        assert_eq(registries.commands.get_descriptor(command_id).owner_module, MODULE_ID, "and the module owns it now")
    # The five this suite registers. The sixth kind is the colour lookup's,
    # which `test_the_colour_lookup_filter.gd` holds.
    for kind: StringName in SaPointAdjust.KINDS.slice(0, 5):
        assert_true(registries.filters.has(StringName("%s.%s" % [MODULE_ID, kind])), "%s is a filter keyed by its kind" % kind)


func test_no_two_commands_share_a_chord() -> void:
    var registries := _registries()
    var seen: Dictionary = {}
    var clashes: Array[String] = []
    for command_id: StringName in registries.commands.list_ids():
        for chord in registries.commands.chord_text(command_id).split(", ", false):
            if seen.has(chord):
                clashes.append("%s and %s both answer %s" % [seen[chord], command_id, chord])
            seen[chord] = command_id
    assert_true(clashes.is_empty(), ", and ".join(clashes))


## A rebind is written onto the InputMap action by the command's id, so the id
## the filter declares is the whole of what keeps it.
func test_a_profile_that_rebound_levels_keeps_its_chord() -> void:
    var action := &"filter_levels"
    var registries := _registries()
    var shipped := SaShortcutStore.chords_for(action)
    SaShortcutStore.set_chords(action, ["Ctrl+Alt+K"])
    assert_eq(registries.commands.chord_text(action), "Ctrl+Alt+K", "The rebind lands on the filter's command")
    var again := _registries()
    assert_eq(again.commands.chord_text(action), "Ctrl+Alt+K", "and a second registration leaves it alone")
    SaShortcutStore.set_chords(action, shipped)
    assert_eq(again.commands.chord_text(action), CHORDS[action], "Put back, for the suites after this one")


func test_the_filter_menu_lists_the_two_after_brightness() -> void:
    var registries := _registries()
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(registries.commands)
    var menu := bar.menu("Filter") as SaFilterMenu
    menu.filters = registries.filters
    var popup := menu.show_section(menu.section_item(&"tone"))
    var labels := Array(popup.row_labels())
    var at := labels.find("Brightness/Contrast")
    assert_true(at >= 0, "Brightness/Contrast is in the Tone list")
    var said := "and Levels and Curves follow it in the tone section"
    assert_eq(labels.slice(at + 1, at + 3), ["Levels", "Curves"], said)
    assert_false(labels.has("Levels..."), "and the skeleton's own row is gone")
    var hints: Dictionary = {}
    for entry: Dictionary in popup.row_report():
        hints[String(entry.get("label", ""))] = String(entry.get("hint", ""))
    assert_eq(hints.get("Levels", ""), "Ctrl+L", "and a row shows the chord its filter declared")
    assert_eq(hints.get("Curves", ""), "Ctrl+M", "for both")
    bar.free()


## The ask's own grep: the widget's sample count is its own, so the Curves
## filter reads it off the widget and the widget names no engine.
func test_the_curve_editor_names_no_engine() -> void:
    var source := FileAccess.get_file_as_string("res://ui/widgets/curve_option/sa_curve_editor.gd")
    assert_false(source.is_empty(), "the editor is read")
    assert_false(source.contains("SaAdjustments"), "and names no SaAdjustments")
    assert_eq(SaCurveEditor.SAMPLES, 256, "and its count is the 256 adjust.gmacs is built for")


## The Levels panel is what the filter reads when it runs: a handle moved is a
## number the pass takes, and one `changed` asks for the rerun.
func test_the_levels_panel_is_what_the_filter_reads() -> void:
    var panel := SaLevelsPanel.new()
    var heard: Array = [0]
    panel.changed.connect(func() -> void: heard[0] += 1)
    panel.set_values({"in_black": 0.25, "channel": "red"})
    assert_eq(heard[0], 1, "one set is one rerun")
    var values := panel.values()
    assert_almost_eq(float(values["in_black"]), 0.25, 1e-4, "the black point is the one set")
    assert_eq(values["channel"], "red", "and so is the channel")
    var params := SaPointAdjust.params_for(SaPointAdjust.LEVELS, values)
    assert_almost_eq(float(params[5]), 1.0, 1e-6, "which the pass reads as red's index")
    panel.free()


## The Curves panel keeps a curve per channel while it is open, and the filter
## sends every one that was shaped.
func test_the_curves_panel_keeps_a_curve_per_channel() -> void:
    var panel := SaCurvesPanel.new()
    var said := panel.capture_option_edit({"channel": "red", "points": [[0.0, 0.0], [0.5, 0.25], [1.0, 1.0]]})
    assert_true(said.contains("red"), "the door says which channel it shaped: %s" % said)
    panel.show_channel("master")
    panel.set_curve("master", PackedVector2Array([Vector2(0.0, 0.1), Vector2(1.0, 1.0)]))
    var curves: Dictionary = panel.values()["curves"]
    assert_eq(curves.keys().size(), 2, "both shaped channels are sent")
    assert_almost_eq(float((curves["red"] as PackedFloat32Array)[128]), 0.25, 5e-3, "red holds its own point")
    panel.reset()
    assert_true((panel.values()["curves"] as Dictionary).is_empty(), "and Reset puts every channel back")
    panel.free()
