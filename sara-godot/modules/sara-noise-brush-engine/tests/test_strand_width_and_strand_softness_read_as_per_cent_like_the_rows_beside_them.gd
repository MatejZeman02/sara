## Strand Width and Strand Softness read as per cent like the rows beside them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The two rows are multiples of what each strand draws, and shown as "1.00 ×"
## they stood a quarter of the way along a slider whose neighbours all read 0
## to 100%. They now read as a percentage, 100% being the strand's own, with
## both ends named in the tooltip. The brush editor is bound to the noise brush
## with Bristle chosen, walked to the Look page, and each row's slider is read
## at its two ends and at its rest, the text a painter sees.
##
## **Detached, and the window is never shown**, because a `Window` in the tree
## of a headless run maps a real one and blocks, as the editor's own suites say.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseFieldsScript = preload("res://modules/sara-noise-brush-engine/noise_fields.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const NoiseLookRowsScript = preload("res://modules/sara-noise-brush-engine/noise_look_rows.gd")

## The window builds curve controls and a scratchpad with a canvas in it.
const REQUIRES_GPU := true

const TOOL_ID := &"noise"

## Each row's three positions, the stored value and the text it reads as.
const READINGS: Dictionary[StringName, Array] = {
    &"strand_width": [[0.25, "Strand Width: 25 %"], [1.0, "Strand Width: 100 %"], [3.0, "Strand Width: 300 %"]],
    &"strand_softness": [[0.0, "Strand Softness: 0 %"], [0.5, "Strand Softness: 50 %"], [2.0, "Strand Softness: 200 %"]],
}

static var scratch_dir: String = SaDataRoot.path("test_strand_rows")

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _window: SaBrushEditorWindow = null
var _advanced: bool = false


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    _advanced = SaSettings.advanced_options
    SaSettings.advanced_options = true
    _surface = Fixtures.make_surface()
    var fields: RefCounted = NoiseFieldsScript.new()
    fields.register_shipped(SaPatternStore.new([SaPatternStore.SHIPPED_DIR]))
    var descriptor := SaToolDescriptor.create(TOOL_ID, StateNoiseBrushScript)
    descriptor.options = NoiseModuleScript.options(fields)
    var registry := Fixtures.make_tool_registry()
    assert_true(registry.register(descriptor), "The noise brush registers as a tool")
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, registry)
    _machine.set_active_tool(TOOL_ID)
    var tool := _machine.get_tool(TOOL_ID)
    tool.settings.texture_field = NoiseFieldsScript.BRISTLE
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    var specs: Array[SaOptionSpec] = []
    specs.assign(descriptor.options)
    _window = SaBrushEditorWindow.new()
    _window.bind_tool(tool, specs, store, "", 1080.0)
    _window.show_page(_window.pages.index_of(NoiseLookRowsScript.PAGE))


func after_each() -> void:
    if _window != null:
        _window.free()
        _window = null
    Fixtures.teardown(_surface, _machine)
    SaSettings.advanced_options = _advanced
    ScratchFolder.clear(scratch_dir)


func _slider(key: StringName) -> FactorSlider:
    return _window.pages.page_controls.control(key) as FactorSlider


## The claim: at either end and at the strand's own, each row reads its label
## and a whole percentage, as Fill and Strand Taper beside it do.
func test_both_rows_read_their_label_and_a_percentage_at_three_positions() -> void:
    for key: StringName in READINGS:
        var slider := _slider(key)
        assert_not_null(slider, "The Look page draws %s while Bristle is chosen" % key)
        if slider == null:
            continue
        for reading: Array in READINGS[key]:
            slider.value = float(reading[0])
            assert_eq(slider._label.text, String(reading[1]), "%s at %.2f" % [key, reading[0]])


## The neighbours' form, so the two rows are read against the page and not
## against a string this file chose.
func test_the_two_rows_read_as_the_share_rows_beside_them() -> void:
    var taper := _slider(&"strand_taper")
    assert_not_null(taper, "Strand Taper is drawn beside them")
    for key: StringName in READINGS:
        var slider := _slider(key)
        assert_eq(slider.normalized_display, taper.normalized_display, "%s scales its number as Taper does" % key)
        assert_eq(slider.suffix, taper.suffix, "and carries Taper's suffix")
        assert_eq(slider.decimal_places, taper.decimal_places, "and Taper's decimals")
        assert_false(slider._label.text.contains("×"), "and no multiplication sign: %s" % slider._label.text)


## A slider that runs past 100% says where it ends, so 100% is not taken for
## its top.
func test_each_tooltip_names_both_ends() -> void:
    for key: StringName in READINGS:
        var tip := _slider(key).tooltip_text
        var ends: Array = READINGS[key]
        for at: int in [0, 2]:
            var shown := String(ends[at][1]).get_slice(": ", 1).replace(" ", "")
            assert_true(tip.contains(shown), "%s's tooltip names %s: %s" % [key, shown, tip])
