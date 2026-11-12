## The shipped Blender blends only the layer it paints on: its
## recipe turns Sample merged off, so a stroke over a transparent part of an
## upper layer lays none of the layer below onto it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **What a painter would meet.** A Blender that lays the colours of the layers
## below onto a transparent part of the layer it paints, because the recipe left
## `smudge_sample_merged` at the settings' default, true, and the pickup read the
## composite. The shipped Blender turns it off. The settings' default stays true,
## so every other recipe is read here to keep it.
##
## **No real store.** The presets are installed into a store of the suite's own
## under the run's data root, which the runner keeps away from the painter's,
## and the folder is cleared before and after each test. The stroke is painted
## with the Blender loaded back from that store, as a fresh profile hands it to
## the painter, and the same stroke with Sample merged ticked is read beside it,
## so the measure is seen to fail what the painter saw.
##
## **Read by colour, not by coverage.** A smudge dab moves colour and keeps the
## brush's own coverage (`dab_texel.gmacs`), so the Blender over a transparent
## part lays paint whatever it samples, in the brush's colour where it carried
## none. The brush is blue here, which the lower layer's red is not, so the
## red channel of what the stroke laid says whether the lower layer reached it.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_d38_blender")

const CANVAS := Vector2i(256, 256)
const RED := Color(1.0, 0.0, 0.0, 1.0)
## The stroke runs across the middle of the one cell, well inside it.
const FROM := Vector2(48.0, 128.0)
const TO := Vector2(208.0, 128.0)
const STEPS: int = 40
const RADIUS: float = 30.0
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
## The most red a painted texel of the upper layer may carry, which is none,
## read past the noise of a half float.
const NONE_MOST: float = 0.002
## A texel with less alpha than this is read as unpainted.
const PAINTED_LEAST: float = 0.01


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    ScratchFolder.clear(scratch_dir)


## A store of the suite's own, every shipped recipe written into it.
func _installed() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    var written := store.install_shipped(SettingsScript.new(), ShippedPresetsScript)
    assert_eq(written, ShippedPresetsScript.entries().size(), "Every shipped recipe is written into the fresh store")
    return store


func test_a_fresh_store_holds_a_blender_that_samples_only_its_layer() -> void:
    var store := _installed()
    var blender := store.load_preset("Blender")
    assert_not_null(blender, "The fresh store holds a Blender")
    if blender == null:
        return
    assert_false(blender.smudge_sample_merged, "and the Blender reads only the layer it paints on")
    var default_merged: bool = SettingsScript.new().smudge_sample_merged
    assert_true(default_merged, "The settings' default stays on")
    for entry: Dictionary in ShippedPresetsScript.entries():
        var preset_name := String(entry["name"])
        if preset_name == "Blender":
            continue
        var preset := store.load_preset(preset_name)
        assert_not_null(preset, "%s loads" % preset_name)
        if preset == null:
            continue
        var settings: Dictionary = entry["settings"]
        var expected: bool = settings.get("smudge_sample_merged", default_merged)
        assert_eq(preset.smudge_sample_merged, expected, "and %s samples as it did before" % preset_name)


## A two-layer canvas: red on the lower layer's one cell, the upper layer new and
## empty above it, and the composite drawn, since a merged pickup reads it. The
## lower layer is answered beside it.
func _surface() -> Array:
    var surface := Fixtures.make_surface(CANVAS)
    var document := surface.get_document()
    var lower := document.active_layer
    lower.get_or_create_chunk(Vector2i(0, 0)).clear(RED)
    SaLayerOps.new(document).add()
    document.invalidate_chunks([Vector2i(0, 0)])
    surface.easel.request_full_composite()
    surface.easel.process_pending_composite()
    return [surface, lower]


func _brush(surface: SaSurface, preset: Resource) -> ToolState:
    var brush := StateBrushScript.new()
    brush.surface = surface
    SaPresetStore.copy_settings(preset, brush.settings)
    brush.settings.radius = RADIUS / float(mini(CANVAS.x, CANVAS.y))
    brush.settings.color = BLUE
    return brush


func _stroke(surface: SaSurface, brush: ToolState) -> void:
    var view := surface.view
    for i in range(STEPS + 1):
        view.mouse_position = FROM.lerp(TO, float(i) / float(STEPS))
        var event: InputEvent
        if i == 0:
            var press := InputEventMouseButton.new()
            press.button_index = MOUSE_BUTTON_LEFT
            press.pressed = true
            event = press
        else:
            var motion := InputEventMouseMotion.new()
            motion.button_mask = MOUSE_BUTTON_MASK_LEFT
            motion.pressure = 1.0
            event = motion
        brush.handle_input(event)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    brush.handle_input(release)
    surface.get_document().commit_stroke()


## Every texel of *layer*'s one cell as a float colour, or nothing when the
## layer holds no chunk there, which is a cell with no paint.
func _texels(layer: SaLayer) -> Array[Color]:
    var out: Array[Color] = []
    var chunk: SaChunk = layer.chunks.get(Vector2i(0, 0))
    if chunk == null:
        return out
    var texture := chunk.albedo()
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var step := 2 if half else 4
    var size := step * 4
    for at in range(0, bytes.size(), size):
        var channels: Array[float] = []
        for channel in range(4):
            var offset: int = at + channel * step
            channels.append(bytes.decode_half(offset) if half else bytes.decode_float(offset))
        out.append(Color(channels[0], channels[1], channels[2], channels[3]))
    return out


## How many texels of *texels* carry paint, and the most red any of them does.
func _painted(texels: Array[Color]) -> Vector2:
    var painted := Vector2.ZERO
    for texel: Color in texels:
        if texel.a >= PAINTED_LEAST:
            painted = Vector2(painted.x + 1.0, maxf(painted.y, texel.r))
    return painted


## Strokes *preset* across the empty upper layer and answers how many texels it
## painted there and the most red any of them took, after reading the lower
## layer unchanged.
func _stroke_over_the_hole(preset: Resource) -> Vector2:
    var made := _surface()
    var surface: SaSurface = made[0]
    var lower: SaLayer = made[1]
    var document := surface.get_document()
    var upper := document.active_layer
    assert_true(upper != lower, "The stroke paints the upper layer")
    _stroke(surface, _brush(surface, preset))
    var below := _texels(lower)
    assert_eq(below.size(), CANVAS.x * CANVAS.y, "The lower layer still holds its cell")
    var changed := 0
    for texel: Color in below:
        if not texel.is_equal_approx(RED):
            changed += 1
    assert_eq(changed, 0, "and every texel of it is the red it was")
    var painted := _painted(_texels(upper))
    document.free()
    surface.easel.free()
    return painted


func test_the_fresh_blender_lays_none_of_the_lower_layer_onto_the_upper() -> void:
    var store := _installed()
    var blender := store.load_preset("Blender")
    assert_not_null(blender, "The fresh store holds a Blender")
    if blender == null:
        return
    var painted := _stroke_over_the_hole(blender)
    # Nothing at all: a Blender over an empty layer lays no blots of the
    # swatch's blue there, which this line would count as reaching it.
    assert_eq(int(painted.x), 0, "The stroke laid nothing on the empty upper layer")
    assert_true(painted.y <= NONE_MOST, "and none of the lower layer's red there, at most %f" % painted.y)


## The same stroke with Sample merged ticked, which is what the painter met:
## the pickup reads the composite and lays the red onto the empty layer.
func test_the_blender_with_sample_merged_ticked_lays_the_red_there() -> void:
    var store := _installed()
    var blender := store.load_preset("Blender")
    assert_not_null(blender, "The fresh store holds a Blender")
    if blender == null:
        return
    blender.smudge_sample_merged = true
    var painted := _stroke_over_the_hole(blender)
    assert_true(painted.x > 0.0, "The stroke reached the upper layer, %d texels" % int(painted.x))
    assert_true(painted.y > 0.5, "and ticked, it laid the lower layer's red there, %f" % painted.y)
