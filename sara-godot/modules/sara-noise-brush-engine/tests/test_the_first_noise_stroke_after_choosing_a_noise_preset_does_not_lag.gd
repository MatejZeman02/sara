## The first noise stroke after a noise preset is chosen does not lag.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Selecting a noise brush engine must not make the first dab lag. Sara opens on Oklab P3 at 16-bit float, a kernel is built
## once per storage format on the first request for that format, and the noise
## brush asked for `noise_dab` at F16 inside its first stroke. The stamp brush
## cured the same stall with its `warm`, and the noise brush warms the same way
## now, for the document's depth and for a preset chosen.
##
## A stroke is held to what it may not do: build a variant of a kernel the noise
## brush dispatches, read a tip or a pattern, or ask the pattern store for a
## pattern. The compiler's own variants say the first, `SaTipCache` and
## `SaPatternKernel` say the second, and a store the suite puts in counts the
## asks. **The compiler's two global counters are not used**, because a stroke
## in a process that has drawn nothing yet builds the variants of kernels no
## brush owns, `blank` and the relief's at the height's depth and the
## compositor's at F16, which the app has built before its first stroke.
##
## **A build, once made, is the compiler's for the rest of the session**, and
## every surface the fixtures make opens at F16, so a suite that ran earlier may
## have made `noise_dab` at both depths already. What this holds without
## depending on the order is the brush's own `compute`, which is pointed at the
## document's depth by the choice and not by the stroke, and which a lift leaves
## at it.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

const F16 := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
const F32 := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT

## The shelf's presets the suite chooses: the plain one, the one that lays
## height and the one whose texture is a picture.
const PLAIN: String = "Grain Round"
const HEIGHT: String = "Thick Impasto"
const PICTURE: String = "Canvas Scumble"

## The kernels the noise brush dispatches, whose variants a stroke may not build.
const KERNELS: Array[String] = ["noise_dab", "noise_height_carry", "smudge_pickup"]

## The name a stamp preset has on the bus. The noise brush hears every preset
## chosen, whichever engine paints it.
const STAMP: String = "Airbrush"


## A store that counts what it is asked for, the stand-in the suite puts in to
## say a stroke asked for no pattern.
class CountingStore:
    extends SaPatternStore

    var asked: int = 0

    func pattern(pattern_name: String) -> SaPattern:
        asked += 1
        return super(pattern_name)


## The easels the brushes paint on, freed after each test because an easel is a
## node that no tree owns here.
var _easels: Array[SaEasel] = []


func after_each() -> void:
    for easel: SaEasel in _easels:
        easel.free()
    _easels.clear()


## A noise brush on a document at *depth*, the way the machine binds one: built
## first, handed its surface after, with a counting store behind its settings.
func _brush_on(depth: SaColorSpace.Depth) -> StateNoiseBrushScript:
    var easel := SaEasel.create_default(Vector2i(256, 256), null, SaColorSpace.srgb().with_depth(depth))
    _easels.append(easel)
    var brush := StateNoiseBrushScript.new()
    brush.surface = SaSurface.create(&"test", easel, Fixtures.FakeView.new())
    brush.settings.pattern_store = CountingStore.new()
    brush.stroke_seed = 7
    return brush


## Chooses the shelf's preset called *preset_name* the way the presets docker
## does: its settings are copied onto the brush's and the bus announces it.
func _choose(brush: StateNoiseBrushScript, preset_name: String) -> void:
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] != preset_name:
            continue
        var built := NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
        assert_not_null(built, "%s builds" % preset_name)
        SaPresetStore.copy_settings(built, brush.settings)
        EventBus.preset_loaded.emit(preset_name)
        return
    assert_true(false, "the shelf has no preset called %s" % preset_name)


## How many variants the compiler holds of *shader*, one for each storage
## format and binding format it was asked at.
func _variants_of(shader: String) -> int:
    var held: Dictionary = GlobalShaderCompiler._format_variants.get(GlobalShaderCompiler.resolve_shader_name(shader), {})
    return held.size()


## Whether the compiler holds *shader* built at *format*.
func _built(shader: String, format: int) -> bool:
    var variants: Dictionary = GlobalShaderCompiler._format_variants.get(GlobalShaderCompiler.resolve_shader_name(shader), {})
    var made: Array = variants.get(GlobalShaderCompiler.source.variant_key(format), [])
    return not made.is_empty() and (made[0] as RID).is_valid()


## What a stroke may not move, by name.
func _counters(brush: StateNoiseBrushScript) -> Dictionary[String, int]:
    var store: CountingStore = brush.settings.pattern_store
    var counted: Dictionary[String, int] = {
        "tip files read": SaTipCache.shared().reads,
        "pattern pictures read": SaPatternKernel.reads,
        "patterns asked of the store": store.asked,
    }
    for shader: String in KERNELS:
        counted["variants of %s built" % shader] = _variants_of(shader)
    return counted


## One stroke of a dozen samples, the way a pen makes one, and the lift.
func _stroke(brush: StateNoiseBrushScript, from: Vector2) -> void:
    var steps := 12
    brush.begin_stroke(from, 0.8, Vector2.ZERO, 0.0)
    for step in range(1, steps + 1):
        brush.add_sample(from + Vector2(float(step) * 14.0, float(step) * 4.0), 0.8, Vector2.ZERO, float(step) * 16.0)
    brush.end_stroke()


## Chooses *preset_name*, holds the brush to the document's depth before the
## stroke, and paints one stroke that moves none of the counters.
func _chosen_stroke_is_quiet(brush: StateNoiseBrushScript, preset_name: String, format: int, label: String) -> void:
    _choose(brush, preset_name)
    assert_eq(brush.compute.pipelines.storage_format, format, "%s: the choice points the kernel at the document's depth" % label)
    assert_true(_built("noise_dab", format), "%s: and the compiler holds `noise_dab` built at it" % label)
    assert_true(_built("smudge_pickup", format), "%s: and the smudge pickup" % label)
    var before := _counters(brush)
    _stroke(brush, Vector2(24.0, 40.0))
    assert_eq(_counters(brush), before, "%s: the stroke built no variant and read nothing" % label)
    assert_eq(brush.compute.pipelines.storage_format, format, "%s: and the lift leaves the kernel at the depth" % label)


func test_the_first_stroke_after_a_choice_is_quiet_at_both_depths() -> void:
    for depth: SaColorSpace.Depth in [SaColorSpace.Depth.F32, SaColorSpace.Depth.F16]:
        var format := F16 if depth == SaColorSpace.Depth.F16 else F32
        var word := SaColorSpace.depth_name(depth)
        var brush := _brush_on(depth)
        assert_eq(
            brush.compute.pipelines.storage_format,
            F32,
            "%s: a brush is built at the default depth, before it has a document" % word
        )
        _chosen_stroke_is_quiet(brush, PLAIN, format, "%s %s" % [word, PLAIN])
        _chosen_stroke_is_quiet(brush, HEIGHT, format, "%s %s" % [word, HEIGHT])
        _chosen_stroke_is_quiet(brush, PICTURE, format, "%s %s" % [word, PICTURE])


## The stamp's own choice, and the noise one again: the next noise stroke is as
## quiet as the first was.
func test_a_stamp_preset_and_the_noise_one_again_leave_the_next_stroke_quiet() -> void:
    for depth: SaColorSpace.Depth in [SaColorSpace.Depth.F32, SaColorSpace.Depth.F16]:
        var format := F16 if depth == SaColorSpace.Depth.F16 else F32
        var word := SaColorSpace.depth_name(depth)
        var brush := _brush_on(depth)
        _chosen_stroke_is_quiet(brush, HEIGHT, format, "%s %s" % [word, HEIGHT])
        EventBus.preset_loaded.emit(STAMP)
        assert_eq(brush.compute.pipelines.storage_format, format, "%s: a stamp preset leaves the noise brush where it was" % word)
        _chosen_stroke_is_quiet(brush, HEIGHT, format, "%s %s again" % [word, HEIGHT])


## The counting store is a real stand-in and the choice is where the pattern is
## read: choosing the Picture preset moves the counters a stroke may not move.
func test_the_picture_is_read_when_the_preset_is_chosen_and_not_in_the_stroke() -> void:
    var brush := _brush_on(SaColorSpace.Depth.F16)
    var before := _counters(brush)
    _choose(brush, PICTURE)
    var chosen := _counters(brush)
    assert_true(
        chosen["patterns asked of the store"] > before["patterns asked of the store"],
        "Choosing the Picture preset asks the store for its pattern"
    )
    _stroke(brush, Vector2(24.0, 40.0))
    assert_eq(_counters(brush), chosen, "and the stroke asks for nothing more")


## A brush that heard no choice and no depth is warmed by the first of them, and
## the warm is kept: a second choice builds nothing it built.
func test_a_warm_brush_is_not_built_twice() -> void:
    var brush := _brush_on(SaColorSpace.Depth.F16)
    brush.warm()
    var compute := brush.compute
    brush.warm()
    assert_true(brush.compute == compute, "A second warm for the same depth leaves the kernel the first made")
    assert_eq(compute.pipelines.storage_format, F16, "at the document's depth")


func test_a_brush_with_no_document_builds_nothing() -> void:
    var brush := StateNoiseBrushScript.new()
    brush.warm()
    EventBus.preset_loaded.emit(PLAIN)
    assert_eq(brush.compute.pipelines.storage_format, F32, "A brush built alone stays at the default depth")
