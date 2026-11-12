## Pencil, Wash and Oil Smudge fill their ring at full pressure, and
## pressure takes the share the table below names off below that. Airbrush fills it at every pressure.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A size strength below one would shrink the dab at full pressure, because
## `size_like` multiplies the reading by the strength. Oil Smudge's dab would be
## 24% of its ring at pressure 0.8 and a stroke would lay four times the dabs its
## size promises. The recipes carry a size curve from one less the share to one, with the
## strength at one. Every number below is worked by hand from the table, never
## read back off the recipe, so a curve written wrong cannot agree with itself.
##
## The dab size is what `SaDynamics.evaluate` answers, which is the number the
## stroke spaces its dabs by. No GPU. The picture is
## `scenarios/a-shipped-presets-dab-fills-its-ring-at-full-pressure.json`.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const SaShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")

## Never the real `user://brush_presets`, for the reason `test_brush_presets.gd`
## gives.
static var scratch_dir: String = SaDataRoot.path("test_d18_shipped_ring")

## The share pressure takes off the size, and the radius each recipe names.
## Airbrush is not in the table, because its size is one the pen never moves.
const SHARES: Dictionary = {
    "Pencil": {"share": 0.3, "radius": 0.0037},
    "Wash": {"share": 0.6, "radius": 0.06},
    "Oil Smudge": {"share": 0.3, "radius": 0.028},
}

## Any ring will do, since the dab is a share of it.
const RING: float = 100.0


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    ScratchFolder.clear(scratch_dir)


func test_full_pressure_paints_the_whole_ring() -> void:
    for name: String in SHARES:
        var dab := SaDynamics.new(_recipe(name)).evaluate(_sample(1.0), RING)
        assert_almost_eq(dab.size, RING, 1e-3, "%s fills its ring at pressure 1.0" % name)


func test_pressure_0_8_takes_a_fifth_of_the_share_off() -> void:
    for name: String in SHARES:
        var share: float = SHARES[name]["share"]
        var dab := SaDynamics.new(_recipe(name)).evaluate(_sample(0.8), RING)
        assert_almost_eq(dab.size, RING * (1.0 - share * 0.2), 1e-3, "%s at pressure 0.8" % name)


## The bottom of the curve: a touch paints the ring less the whole share, so the
## share is what pressure takes off and not what is left.
func test_the_lightest_touch_takes_the_whole_share_off() -> void:
    for name: String in SHARES:
        var share: float = SHARES[name]["share"]
        var dab := SaDynamics.new(_recipe(name)).evaluate(_sample(0.0), RING)
        assert_almost_eq(dab.size, RING * (1.0 - share), 1e-3, "%s at pressure 0" % name)


func test_the_strength_is_one_and_the_radius_stays() -> void:
    for name: String in SHARES:
        var settings := _recipe(name)
        assert_almost_eq(settings.size_option.strength, 1.0, 1e-6, "%s leaves the strength at one" % name)
        assert_true(settings.size_option.use_same_curve, "%s reads the shared curve it carries" % name)
        assert_almost_eq(settings.radius, float(SHARES[name]["radius"]), 1e-6, "%s keeps its radius" % name)


## The Airbrush switches its size off the pen, so every pressure paints
## the whole ring.
func test_the_stock_airbrush_fills_its_ring_at_any_pressure() -> void:
    var airbrush := _recipe("Airbrush")
    assert_false(airbrush.size_option.enabled, "Airbrush's size is off the pen")
    for pressure: float in [0.0, 0.5, 1.0]:
        var dab := SaDynamics.new(airbrush).evaluate(_sample(pressure), RING)
        assert_almost_eq(dab.size, RING, 1e-3, "Airbrush fills its ring at pressure %.1f" % pressure)


## A painter's own copy under a shipped name is theirs, so the install that
## brings the new recipes leaves it sizing as it did.
func test_a_painters_saved_copy_is_not_changed() -> void:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    var own := _recipe("Oil Smudge")
    own.size_option.strength = 0.3
    own.size_option.common_curve = PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 1.0)])
    store.save_preset("Oil Smudge", own)

    store.install_shipped(SaStampBrushSettings.new(), SaShippedPresetsScript)

    var kept := store.load_preset("Oil Smudge") as SaStampBrushSettings
    assert_not_null(kept, "The painter's Oil Smudge loads")
    var dab := SaDynamics.new(kept).evaluate(_sample(0.8), RING)
    assert_almost_eq(dab.size, RING * 0.24, 1e-3, "and still paints 0.3 of 0.8 of its ring")


func _recipe(name: String) -> SaStampBrushSettings:
    for entry: Dictionary in SaShippedPresetsScript.entries():
        if String(entry["name"]) == name:
            return SaShippedPresetsScript.build(SaStampBrushSettings, entry) as SaStampBrushSettings
    assert_true(false, "%s is a shipped recipe" % name)
    return SaStampBrushSettings.new()


func _sample(pressure: float) -> SaStrokeInfo:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 4242)
    info.hovering = false
    info.position = Vector2.ZERO
    info.pressure = pressure
    return info
