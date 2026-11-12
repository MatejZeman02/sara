## The Blender leaves a gradient across an edge in one pass: one stroke of the shipped Blender at radius 40
## along an edge between greys 221 and 127 lays a ramp across it that rises
## from one grey to the other with no step at either end and no flat band.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **As the painter meets it.** A Blender that smeared would lay, along the
## edge, a band of the two greys' mean 75 pixels wide with an edge
## of its own on each side. It blurs ([SaSmudgeBlur]) instead, and this suite reads
## the profile across the edge on three rows of the stroke's middle, the way a
## colour picker dragged across it would. The same stroke at the old rate is
## read beside it, so the measure is seen to fail what a painter would see.
## The picture is `scenarios/blender-leaves-a-gradient-across-an-edge-in-one-pass.json`.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## Two chunks across, so the edge is the seam between them and the stroke's
## dabs paint into both.
const CANVAS := Vector2i(512, 256)
const CHUNK: int = 256
const EDGE: int = 256
## The two greys of the friction, as eight bit codes.
const LIGHT: int = 221
const DARK: int = 127
## The dab's radius in document pixels, the painter's own.
const RADIUS: float = 40.0
## The stroke runs down the edge, well inside the canvas at both ends.
const FROM := Vector2(256.0, 24.0)
const TO := Vector2(256.0, 232.0)
const STEPS: int = 52
## The rows the profile is read on, the middle of the stroke, where the dabs
## at its ends do not reach.
const ROWS: Array[int] = [96, 128, 160]

## The clauses of the row's Done when line.
const STEP_MOST: int = 5
const FLAT_MOST: int = 10


func _grey(code: int) -> Color:
    var value := float(code) / 255.0
    return Color(value, value, value, 1.0)


## A canvas whose active layer is light left of [constant EDGE] and dark right
## of it, a new layer at *scale* when one is asked for.
func _surface(scale: float = 0.0) -> SaSurface:
    var surface := Fixtures.make_surface(CANVAS)
    var document := surface.get_document()
    if scale > 0.0:
        SaLayerOps.new(document).add(&"", null, scale)
    document.active_layer.get_or_create_chunk(Vector2i(0, 0)).clear(_grey(LIGHT))
    document.active_layer.get_or_create_chunk(Vector2i(1, 0)).clear(_grey(DARK))
    # Composited before the stroke, because the pickup reads the composite and
    # a composite never drawn is bare canvas to it.
    document.invalidate_chunks([Vector2i(0, 0), Vector2i(1, 0)])
    surface.easel.request_full_composite()
    surface.easel.process_pending_composite()
    return surface


## The shipped Blender at the painter's radius, at *mode* when one is given.
func _blender(surface: SaSurface, mode: int = -1) -> ToolState:
    var recipe: Resource = null
    for entry: Dictionary in SaShippedPresets.entries():
        if entry["name"] == "Blender":
            recipe = SaShippedPresets.build(SettingsScript, entry)
    assert_true(recipe != null, "The Blender is a shipped preset")
    var brush := StateBrushScript.new()
    brush.surface = surface
    SaPresetStore.copy_settings(recipe, brush.settings)
    brush.settings.radius = RADIUS / float(mini(CANVAS.x, CANVAS.y))
    # The ramp was tuned in build-up, where dabs add up. Wash keeps the larger of two.
    brush.settings.painting_mode = SettingsScript.PaintingMode.BUILD_UP
    if mode >= 0:
        brush.settings.smudge_mode = mode as SettingsScript.SmudgeMode
    return brush


## One stroke from *from* to *to* at full pressure, down the edge from
## [constant FROM] to [constant TO] unless told otherwise.
func _stroke(surface: SaSurface, brush: ToolState, from: Vector2 = FROM, to: Vector2 = TO) -> void:
    var view := surface.view
    for i in range(STEPS + 1):
        view.mouse_position = from.lerp(to, float(i) / float(STEPS))
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


## The red of every texel on document row *y*, left to right, as an eight bit
## code, at the active layer's own density, so a layer at 2.0 gives two texels
## a pixel.
func _profile(document: SaDocument, y: int) -> PackedInt32Array:
    var out := PackedInt32Array()
    for cx in range(int(CANVAS.x / float(CHUNK))):
        var chunk: SaChunk = document.active_layer.chunks.get(Vector2i(cx, 0))
        var texture := chunk.albedo()
        var side := int(CHUNK * chunk.resolution_scale)
        var row := int((float(y) + 0.5) * chunk.resolution_scale)
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
        for x in range(side):
            var at := row * side + x
            var red := bytes.decode_half(at * 8) if half else bytes.decode_float(at * 16)
            out.append(roundi(red * 255.0))
    return out


## The widest step between two neighbouring texels of *profile*.
func _widest_step(profile: PackedInt32Array) -> int:
    var widest := 0
    for x in range(1, profile.size()):
        widest = maxi(widest, absi(profile[x] - profile[x - 1]))
    return widest


## The texels where *profile* rises left to right, against a ramp that falls
## from the light grey to the dark.
func _rises(profile: PackedInt32Array) -> int:
    var count := 0
    for x in range(1, profile.size()):
        if profile[x] > profile[x - 1]:
            count += 1
    return count


## The widest run of one code inside the ramp, in texels, which is where the
## profile has left both greys by more than [constant STEP_MOST], so the ramp's
## own feet, where a smooth ramp meets the grey beside it a code at a time, are
## not read as a band.
func _widest_flat(profile: PackedInt32Array) -> int:
    var widest := 0
    var run := 0
    for x in range(profile.size()):
        var inside := profile[x] < LIGHT - STEP_MOST and profile[x] > DARK + STEP_MOST
        if inside and x > 0 and profile[x] == profile[x - 1]:
            run += 1
        else:
            run = 1 if inside else 0
        widest = maxi(widest, run)
    return widest


func _free(surface: SaSurface) -> void:
    surface.get_document().free()
    surface.easel.free()


## The clauses of the Done when line on every row of [constant ROWS], with
## *scale* texels to a pixel.
func _assert_a_ramp(document: SaDocument, scale: float) -> void:
    for y: int in ROWS:
        var profile := _profile(document, y)
        assert_eq(profile[0], LIGHT, "Row %d still holds the light grey past the stroke" % y)
        assert_eq(profile[profile.size() - 1], DARK, "and the dark grey past it on the other side")
        var light := profile[int(EDGE * scale) - 1]
        var dark := profile[int(EDGE * scale)]
        assert_true(light < LIGHT - 30, "and the stroke moved the light side's last texel, %d" % light)
        assert_true(dark > DARK + 30, "and the dark side's first, %d" % dark)
        assert_eq(_rises(profile), 0, "and falls from one to the other without once turning back")
        var step := _widest_step(profile)
        assert_true(step <= STEP_MOST, "with no step wider than %d codes, at its ends or anywhere, %d" % [STEP_MOST, step])
        var flat := _widest_flat(profile)
        var most := int(FLAT_MOST * scale)
        assert_true(flat <= most, "and no flat band inside it wider than %d pixels, %d texels" % [FLAT_MOST, flat])


func test_one_blender_stroke_along_the_edge_leaves_a_ramp_across_it() -> void:
    var surface := _surface()
    _stroke(surface, _blender(surface))
    _assert_a_ramp(surface.get_document(), 1.0)
    _free(surface)


## The ask's second shape: a short stroke across the edge, a radius each side
## of it, laid a ramp that began with a step of about 20 at each end. Read on
## the stroke's own row and the rows half a radius above and below it.
func test_a_short_stroke_across_the_edge_lays_a_ramp_with_no_step_at_its_ends() -> void:
    var surface := _surface()
    var row := float(ROWS[1])
    _stroke(surface, _blender(surface), Vector2(EDGE - RADIUS, row), Vector2(EDGE + RADIUS, row))
    for y: int in [ROWS[1] - int(RADIUS * 0.5), ROWS[1], ROWS[1] + int(RADIUS * 0.5)]:
        var profile := _profile(surface.get_document(), y)
        assert_true(profile[EDGE - 1] < LIGHT - 20, "Row %d moved on the light side of the edge, %d" % [y, profile[EDGE - 1]])
        assert_eq(_rises(profile), 0, "and falls from one grey to the other without once turning back")
        var step := _widest_step(profile)
        assert_true(step <= STEP_MOST, "with no step wider than %d codes, %d" % [STEP_MOST, step])
    _free(surface)


## A layer at 2.0 read by itself, so the blur's lattice is laid over a snapshot
## of twice the texels and the dab reads it at twice the density.
func test_the_ramp_is_the_same_on_a_double_resolution_layer() -> void:
    var surface := _surface(2.0)
    var brush := _blender(surface)
    brush.settings.smudge_sample_merged = false
    _stroke(surface, brush)
    _assert_a_ramp(surface.get_document(), 2.0)
    _free(surface)


func test_the_same_stroke_at_the_old_rate_lays_the_band_the_painter_saw() -> void:
    var surface := _surface()
    _stroke(surface, _blender(surface, SettingsScript.SmudgeMode.SMEARING))
    var profile := _profile(surface.get_document(), ROWS[1])
    var step := _widest_step(profile)
    var flat := _widest_flat(profile)
    assert_true(
        step > STEP_MOST or flat > FLAT_MOST,
        "The smeared stroke this replaced fails the measure, its widest step %d and its widest band %d" % [step, flat]
    )
    _free(surface)


func test_blurring_is_offered_where_the_dab_reads_it() -> void:
    var labels := func(rows: Array[SaOptionSpec]) -> Array:
        var out: Array = []
        for row: SaOptionSpec in rows:
            if row.key == &"smudge_mode":
                for choice: Dictionary in row.choices:
                    out.append(choice["label"])
        return out
    var stamp: Array = labels.call(SaSmudgePage.rows(true, true))
    assert_eq(stamp, ["Smearing", "Dulling", "Blurring"], "The stamp brush offers the third rate")
    var noise: Array = labels.call(SaSmudgePage.rows(false))
    assert_eq(noise, ["Smearing", "Dulling"], "and an engine whose dab cannot read the lattice does not")
