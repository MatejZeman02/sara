## A noise preset stored while Strength was the cut keeps its cut on its load.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The pressure became the cut and Strength a shift against it, so a preset a
## painter stored before paints differently unless its numbers are carried.
## The settings' `migrate`, which the preset store calls on every load, does
## that. A file from before is made here the way one looks: a preset saved now
## with its format's number taken out, since that number is the one key the
## older script did not write. Each is loaded as the store loads it, and the
## shift it carries is read through the brush's own `shift_for` at pressures
## across the range against the shift that paints the old cut's texels.
extends "res://tests/test_framework.gd"

const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")

## The pressures the shift is read at, one every twentieth.
const STEPS := 20
## How far the shift may stray from the old cut's just past a bend, where the
## monotone cubic a sensor reads lays the curve flat.
const BEND_SLACK := 0.005

var _dir: String = SaDataRoot.path("test_s2_the_old_cut")


func before_each() -> void:
    DirAccess.make_dir_recursive_absolute(_dir)


func after_each() -> void:
    if not DirAccess.dir_exists_absolute(_dir):
        return
    for file_name: String in DirAccess.get_files_at(_dir):
        DirAccess.remove_absolute(_dir.path_join(file_name))
    DirAccess.remove_absolute(_dir)


## Under the old default, Strength falling with the pressure, a stored preset
## paints the same texels at every pressure: its shift is p - 1 + S(1 - p)
## exactly, which is nought at the old default of one.
func test_a_preset_on_the_old_falling_line_carries_exactly() -> void:
    for old_strength: float in [1.0, 0.8, 0.3]:
        var loaded := _load_old(old_strength, _falling(PackedVector2Array([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])))
        var label := "Strength %.1f on the falling line" % old_strength
        assert_eq(loaded.format_version, NoiseBrushSettingsScript.FORMAT_VERSION, "%s loads at the format of now" % label)
        assert_almost_eq(loaded.strength, old_strength - 1.0, 0.0001, "%s shifts by the old Strength less one" % label)
        var worst := _worst(loaded, old_strength, _line(Vector2(0.0, 1.0), Vector2(1.0, 0.0)))
        assert_true(worst < 0.002, "%s: the shift is the old cut's at every pressure, %.5f apart at worst" % [label, worst])


## A curve of the preset's own carries on its own side of where its shift
## crosses nought and shifts nothing on the other, within
## [constant BEND_SLACK], since the curve bends just past the crossing.
func test_a_curve_of_its_own_carries_on_its_side_of_nought() -> void:
    var cases := [
        ["Canvas Scumble's line", 1.0, Vector2(0.0, 0.95), Vector2(1.0, 0.35)],
        ["Dry Brush's line", 0.95, Vector2(0.0, 1.0), Vector2(1.0, 0.7)],
        ["a rising line", 0.5, Vector2(0.0, 0.2), Vector2(1.0, 0.9)],
    ]
    for setup: Array in cases:
        var loaded := _load_old(setup[1], _falling(PackedVector2Array([setup[2], setup[3]])))
        var worst := _worst(loaded, setup[1], _line(setup[2], setup[3]))
        assert_true(
            worst < BEND_SLACK, "%s: the shift is the old cut's wherever it can be, %.5f apart at worst" % [setup[0], worst]
        )


## Strength's option off: the old cut was the row alone at every pressure, so
## the shift rises with the pressure from the row less one, until it crosses
## nought.
func test_an_option_that_was_off_carries_the_row_alone() -> void:
    var option := _falling(PackedVector2Array([Vector2(0.0, 1.0), Vector2(1.0, 0.0)]))
    option.enabled = false
    var loaded := _load_old(0.6, option)
    var worst := _worst(loaded, 0.6, _line(Vector2(0.0, 1.0), Vector2(1.0, 1.0)))
    assert_true(worst < BEND_SLACK, "The shift is the row's cut at every pressure, %.5f apart at worst" % worst)


## A picture took paint on its light parts first, so a stored Picture preset
## loads inverted, and a Grain one as it was.
func test_a_stored_picture_reads_inverted() -> void:
    var falling := PackedVector2Array([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])
    var picture := _load_old(1.0, _falling(falling), "picture")
    assert_true(picture.picture_invert, "A stored Picture preset loads inverted")
    var grain := _load_old(1.0, _falling(falling), "grain")
    assert_false(grain.picture_invert, "and a Grain one does not")


## Settings made now and a preset saved now are left as they are, on a load
## and on a second call.
func test_settings_of_now_are_left_alone() -> void:
    var fresh := NoiseBrushSettingsScript.new()
    assert_false(fresh.migrate(), "Settings made now have nothing to carry")
    fresh.strength = 0.3
    var path := _dir.path_join("now.tres")
    assert_eq(ResourceSaver.save(fresh, path), OK, "and save")
    var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as NoiseBrushSettingsScript
    assert_false(loaded.migrate(), "A preset saved now is not carried again on its load")
    assert_almost_eq(loaded.strength, 0.3, 0.0001, "and keeps its shift")
    assert_null(loaded.strength_option.sensor_for(SaSensor.Id.PRESSURE), "and binds no pressure it did not have")
    var old := _load_old(0.8, _falling(PackedVector2Array([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])))
    assert_false(old.migrate(), "and a preset carried once is not carried twice")


## The store calls the migration on its own load, the door every preset of a
## profile comes through.
func test_the_store_carries_a_stored_preset_on_its_load() -> void:
    var store := SaPresetStore.new()
    store.dir = _dir
    _write_old(
        0.8, _falling(PackedVector2Array([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])), "grain", _dir.path_join("Old Grain.tres")
    )
    var loaded := store.load_preset("Old Grain")
    assert_not_null(loaded, "The store loads the preset")
    assert_almost_eq(float(loaded.get("strength")), -0.2, 0.0001, "carried to a shift of the old Strength less one")


## The old cut read back from the carried shift is the cut it came from, which
## is what the stamp's converter hands its Texture option.
func test_the_old_cut_reads_back_from_the_shift() -> void:
    var loaded := _load_old(0.8, _falling(PackedVector2Array([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])))
    var cut: SaCurveOption = loaded.old_cut()
    assert_almost_eq(cut.strength, 0.8, 0.001, "The old Strength comes back")
    assert_eq(cut.common_curve, PackedVector2Array([Vector2(0.0, 1.0), Vector2(1.0, 0.0)]), "along the falling line")
    var fresh := NoiseBrushSettingsScript.new()
    assert_almost_eq(fresh.old_cut().strength, 1.0, 0.001, "and a fresh brush reads as the old default, one")


## An old curve option on the pressure along *curve*, on as the old default was.
func _falling(curve: PackedVector2Array) -> SaCurveOption:
    var option := SaCurveOption.create_default()
    option.enabled = true
    option.common_curve = curve.duplicate()
    option.sensor_for(SaSensor.Id.PRESSURE).curve = curve.duplicate()
    return option


## A straight line through *from* and *to*, as a callable of the pressure.
func _line(from: Vector2, to: Vector2) -> Callable:
    return func(pressure: float) -> float: return lerpf(from.y, to.y, (pressure - from.x) / (to.x - from.x))


## Writes a preset as one stored before the change looks, Strength at
## *old_strength* along *option*, at *path*.
func _write_old(old_strength: float, option: SaCurveOption, field: String, path: String) -> void:
    var settings := NoiseBrushSettingsScript.new()
    settings.texture_field = field
    settings.strength_option = option
    # The old default of one was never written, and nought is the new one,
    # which is not written either, so the file lacks the key as an old one did.
    settings.strength = 0.0 if is_equal_approx(old_strength, 1.0) else old_strength
    assert_eq(ResourceSaver.save(settings, path), OK, "the preset saves")
    var lines := FileAccess.get_file_as_string(path).split("\n")
    var kept := PackedStringArray()
    for line: String in lines:
        if not line.begins_with("format_version = "):
            kept.append(line)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string("\n".join(kept))
    file = null


## A preset stored before the change, loaded as the store loads it.
func _load_old(old_strength: float, option: SaCurveOption, field: String = "grain") -> NoiseBrushSettingsScript:
    var path := _dir.path_join("old.tres")
    _write_old(old_strength, option, field, path)
    var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as NoiseBrushSettingsScript
    assert_true(loaded.migrate(), "A preset stored before the change is carried")
    return loaded


## How far the shift *loaded* lays at each pressure stands from the one that
## paints the old cut *old_strength* times *falls*, p - 1 + S f(p), where that
## shift has the carried Strength's sign. Where it has the other the curve
## reads nought, which is held as well.
func _worst(loaded: NoiseBrushSettingsScript, old_strength: float, falls: Callable) -> float:
    var brush := StateNoiseBrushScript.new()
    brush.settings = loaded
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 7)
    var worst := 0.0
    for step in STEPS + 1:
        var pressure := float(step) / STEPS
        info.feed(Vector2(float(step), 0.0), pressure, Vector2.ZERO, 0.0, float(step))
        var wanted := pressure - 1.0 + old_strength * clampf(falls.call(pressure), 0.0, 1.0)
        var got := brush.shift_for(info)
        if wanted * loaded.strength < 0.0:
            wanted = 0.0
        worst = maxf(worst, absf(got - wanted))
    return worst
