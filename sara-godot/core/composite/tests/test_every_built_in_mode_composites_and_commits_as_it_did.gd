## Each built-in blend mode's kernel and its commit twin are
## made from its formula in `libs/composite_blend_modes.gmacs` rather than
## written by hand beside it, and this suite holds that the change moved no
## value: one fixed backdrop and source composited in every mode of the
## skeleton's table, and the same pair committed in each with a stroke's seed
## into a half precision layer, against the values recorded from the
## integration tip before the change, in `recorded_blends.json` beside it.
##
## Rewrite the recording with
##
##     SARA_WRITE_U297=1 SARA_TEST_OFFSCREEN=1 ./run_tests.sh probe
##
## which is a deliberate act with a reason in the commit message, the way the
## SPIR-V manifest is rewritten.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

## Every value is a texel the GPU wrote and the suite read back.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const SkeletonBlendModes = preload("res://core/loader/skeleton_blend_modes.gd")

## The recording, beside this file.
const RECORDING := "res://core/composite/tests/recorded_blends.json"
## Asking for the recording to be written rather than compared.
const WRITE_ENV := "SARA_WRITE_U297"

const SIDE := 8
## Translucent on both sides, so Porter-Duff, the formula and the alpha all
## reach the answer, and every channel apart, so no mode can swap two unseen.
const BACKDROP := Color(0.62, 0.35, 0.18, 0.8)
const SOURCE := Color(0.25, 0.7, 0.9, 0.6)
const OPACITY := 0.75
## The commit's seed. A fixed seed draws the same rounding every run.
const SEED := 297
## How far a recorded value may lie from the one read now. The kernels run the
## same formulas, so anything past a float's last place is a change.
const TOLERANCE := 1e-6

var _registries: SaRegistries = Fixtures.make_registries()


## Every built-in mode composites the fixed pair to the value recorded before
## its kernel came to be made from its formula.
func test_every_built_in_mode_composites_as_it_did() -> void:
    _against_recording("composite", _composited)


## Every built-in mode commits the fixed pair into a half precision layer, with
## the stroke's rounding, to the texels recorded before its commit twin came to
## be made from its formula.
func test_every_built_in_mode_commits_as_it_did() -> void:
    _against_recording("commit", _committed)


func _against_recording(part: String, read: Callable) -> void:
    var now: Dictionary = {}
    for row: Array in SkeletonBlendModes.BLEND_MODES:
        now[String(row[0])] = read.call(StringName(row[0]))
    if OS.get_environment(WRITE_ENV) == "1":
        _write(part, now)
        return
    var recorded: Dictionary = _recorded().get(part, {})
    assert_eq(now.keys().size(), recorded.keys().size(), "Every built-in mode of the table was recorded for %s" % part)
    for mode: String in now:
        var was: Array = recorded.get(mode, [])
        var is_now: Array = now[mode]
        assert_eq(is_now.size(), was.size(), "%s was recorded for %s" % [mode, part])
        if is_now.size() != was.size():
            continue
        var furthest := 0.0
        for i in is_now.size():
            furthest = maxf(furthest, absf(float(is_now[i]) - float(was[i])))
        assert_true(furthest <= TOLERANCE, "%s %ss as it did, %s from the recording" % [mode, part, furthest])


## The pair composited in *mode* at full precision, the texel's four channels.
func _composited(mode: StringName) -> Array:
    var format := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    var destination := _filled(BACKDROP, format)
    _compositor().composite_chunk_pairs([[destination, _filled(SOURCE, format)]], mode, OPACITY)
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(destination.rid, 0)
    return [data.decode_float(0), data.decode_float(4), data.decode_float(8), data.decode_float(12)]


## The pair committed in *mode* into a half precision layer with the stroke's
## seed, every channel of every texel, since the rounding draws per texel.
func _committed(mode: StringName) -> Array:
    var format := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var destination := _filled(BACKDROP, format)
    _compositor().composite_chunk_pairs([[destination, _filled(SOURCE, format)]], mode, OPACITY, null, 1.0, SEED)
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(destination.rid, 0)
    var out: Array = []
    for at in range(0, data.size(), 2):
        out.append(data.decode_half(at))
    return out


func _compositor() -> SaCompositor:
    var compositor := SaCompositor.new()
    compositor.set_registry(_registries.blend_modes)
    return compositor


func _filled(colour: Color, format: int) -> SaTexture:
    var texture := SaTexture.new(Vector2i(SIDE, SIDE), format)
    GlobalShaderCompiler.get_rd().texture_clear(texture.rid, colour, 0, 1, 0, 1)
    return texture


func _recorded() -> Dictionary:
    if not FileAccess.file_exists(RECORDING):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECORDING))
    return parsed if parsed is Dictionary else {}


func _write(part: String, values: Dictionary) -> void:
    var all := _recorded()
    all[part] = values
    # A mode to a line, so a rewrite's diff names the modes it moved.
    var parts := PackedStringArray()
    for each: String in ["commit", "composite"]:
        var modes := PackedStringArray()
        var held: Dictionary = all.get(each, {})
        var names: Array = held.keys()
        names.sort()
        for mode: String in names:
            modes.append('  "%s": %s' % [mode, JSON.stringify(held[mode], "", false, true)])
        parts.append(' "%s": {\n%s\n }' % [each, ",\n".join(modes)])
    var file := FileAccess.open(ProjectSettings.globalize_path(RECORDING), FileAccess.WRITE)
    file.store_string("{\n%s\n}\n" % ",\n".join(parts))
    file.close()
    assert_true(true, "The recording of %s was written" % part)
