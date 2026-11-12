## A stamp preset converted to the noise brush and back reads Saved once it is
## loaded and painted with.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A converted preset once read Unsaved changes in the brush editor after one
## stroke. The one difference was the tip's `diameter`, 42 in the file and 39.96
## on the brush, because the stamp brush copies the dab's size onto the tip at
## every dab, so the conversion is not at fault and a shipped preset painted
## once reads the same. The comparison skips the tip's `STROKE_WRITTEN_KEYS`,
## and the stroke writes on a copy of the tip, so the dab leaves the stored tip
## alone and the skipped keys are the second guard. Here the shipped
## `Charcoal` goes through the stamp module's two converters, lands on the
## machine's stamp brush, paints a dab and is asked whether it changed.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The dab goes through the stamp kernel.
const REQUIRES_GPU := true

## Never the real `user://brush_presets`, for `test_brush_presets.gd`'s reason.
static var scratch_dir: String = SaDataRoot.path("test_d5_converted_loads_saved")

## The shipped preset the round trip walks.
const SHIPPED: String = "Charcoal"

var _registries: SaRegistries = null
var _stamp: SaModule = null
var _noise: SaModule = null
var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _registries = Fixtures.make_registries()
    _noise = NoiseModuleScript.new()
    _noise.register(_registries.context.for_module(_noise.get_id()))
    _stamp = StampModuleScript.new()
    _stamp.register(_registries.context.for_module(_stamp.get_id()))
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    for module: SaModule in [_stamp, _noise]:
        module.unregister(_registries.context)
    _registries.context.for_module(_stamp.get_id()).remove_all_registrations()
    _registries.context.for_module(_noise.get_id()).remove_all_registrations()
    _stamp = null
    _noise = null
    _registries = null
    ScratchFolder.clear(scratch_dir)


## The claim itself: the round trip applied to a stamp brush reads clean, and
## still does after a dab, which paints on the stroke's copy of the tip and
## leaves the stored one as it was, and a moved size still reads.
func test_the_round_trip_reads_saved_after_a_dab() -> void:
    var brush: Object = _machine.active_tool
    var live: Resource = brush.get("settings")
    var store := _store(live)
    var noise_name := store.convert_preset(SHIPPED, &"noise", _registries.context.converters)
    assert_eq(noise_name, "%s (Noise)" % SHIPPED, "The shipped preset converts to noise")
    var round_trip := store.convert_preset(noise_name, &"stamp", _registries.context.converters)
    assert_eq(round_trip, "%s (Noise) (Stamp)" % SHIPPED, "and back to the stamp brush")

    assert_true(store.apply_preset(round_trip, live), "The round trip loads on the stamp brush")
    var session := SaBrushEditorSession.new(live, store, round_trip)
    assert_false(session.is_dirty(), "Loaded with nothing moved it reads Saved")

    var stored_diameter := float(store.load_preset(round_trip).get("tip").get("diameter"))
    _dab(brush)
    var painted := float(live.get("tip").get("diameter"))
    var kept := "The dab left the stored tip's diameter alone, %f from %f" % [painted, stored_diameter]
    assert_almost_eq(painted, stored_diameter, 1e-4, kept)
    assert_false(session.is_dirty(), "and a painted brush still reads Saved")

    live.set("radius", float(live.get("radius")) * 2.0)
    assert_true(session.is_dirty(), "until the size is moved")


## The plain shipped preset, which reads Saved straight after the load and has
## to still read Saved after a dab.
func test_the_shipped_preset_reads_saved_after_a_dab() -> void:
    var brush: Object = _machine.active_tool
    var live: Resource = brush.get("settings")
    var store := _store(live)
    assert_true(store.apply_preset(SHIPPED, live), "The shipped preset loads")
    var session := SaBrushEditorSession.new(live, store, SHIPPED)
    _dab(brush)
    assert_false(session.is_dirty(), "A painted shipped preset reads Saved")


## What the tip names, and that a field outside the list is still compared.
func test_only_the_stroke_written_fields_are_skipped() -> void:
    assert_eq(
        SaBrushTipScript.STROKE_WRITTEN_KEYS,
        ["diameter", "horizontal_fade", "vertical_fade", "spacing"] as Array[String],
        "The four fields a dab writes"
    )
    var a: Resource = SaBrushTipScript.new()
    var b: Resource = SaBrushTipScript.new()
    b.set("diameter", 7.0)
    b.set("horizontal_fade", 0.2)
    b.set("vertical_fade", 0.3)
    b.set("spacing", 0.9)
    assert_true(SaBrushEditorSession.settings_match(a, b), "The stroke's writes are not a change")
    b.set("ratio", 0.5)
    assert_false(SaBrushEditorSession.settings_match(a, b), "and the ratio still is")


## One left press, the dab, and its release, as `test_first_dab.gd` paints.
func _dab(brush: Object) -> void:
    _surface.view.mouse_position = Vector2(128, 128)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    brush.handle_input(press)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    brush.handle_input(release)


## A scratch store holding the stamp brush's shipped set, written from the
## brush's own settings script as the app writes it.
func _store(template: Resource) -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped((template.get_script() as Script).new(), ShippedPresetsScript)
    assert_true(store.has_preset(SHIPPED), "The shipped %s is installed" % SHIPPED)
    return store
