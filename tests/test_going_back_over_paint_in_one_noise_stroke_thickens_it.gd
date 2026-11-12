## Going back over paint in one noise stroke thickens it, and a stroke that
## never comes back paints what it painted before.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter who scrubs a patch back and forth in one stroke, as one does with a
## bristly brush to fill an area, has to end with more paint there than one
## pass leaves. Grain Round and Bristle Flat, each as it ships less the radius
## taper, scrub [constant PATCH] three times over and back at
## [constant PRESSURE], and paint one pass over a patch of the same size, and
## the share of the patch's texels at full alpha is read off the layer for
## each. The patch is the stretch every leg crosses whole, [constant MARGIN]
## radii in from where the legs turn, and [constant BODY] of the half-width
## either side of the path.
##
## A straight stroke and one that turns through 90 degrees never come back over
## their own paint by more than the turn's own overlap, so each is compared
## texel for texel with a recording of the same stroke taken from the engine
## before the build-up was added, kept beside the suite in
## [constant RECORDINGS]. Setting `SARA_RECORD` writes them again.
## Grain Round's turn was taken again when a Grain came to be read at a
## texel's place on the canvas, since round a turn that place is not the
## stroke coordinates, and its straight stroke still reads its first recording.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

const PRESETS: Array[String] = ["Grain Round", "Bristle Flat"]
const PRESSURE := 0.5
const CANVAS := Vector2i(512, 384)
const RADIUS := 30.0
const SPACING := 4.0
const SAMPLE_MS := 8.0
const SEED := 7
## The patch, 120 pixels along the path, and the row its legs run on.
const PATCH := 120.0
const ROW := 192.0
const MIDDLE := 256.0
## How far past the patch each leg runs before it turns, in radii, so the
## patch is crossed by the body alone and never by a turn or a cap.
const MARGIN := 2.0
const BODY := 0.6
## The legs of the scrub: over and back three times.
const LEGS := 6
## The alpha a texel holds to count as at full alpha.
const FULL := 0.999
## How much more of the patch the scrub has to hold at full alpha than one
## pass, as a share of the patch. On this seed on the reference card
## one pass holds 0.673 with Grain Round and 0.243 with Bristle Flat, and the
## scrub 0.998 and 0.432. Under a wash alone, where each leg reads the field at
## its own along and the strongest leg is kept, the scrub held 0.993 and 0.378,
## so Bristle Flat, whose streaks run along the path and lie where they lay at
## every leg, misses this margin by the wash alone.
## A Grain is read at its place on the canvas, which cuts its holes in the same
## places at every leg, and a return reads it shifted so a scrub still fills
## them: Grain Round's one pass holds 0.663 and its scrub 0.912, where without
## the shift the scrub held 0.808.
const THICKER := 0.15
## The largest difference in any channel a stroke that never comes back may
## show against its recording. Nought on the card that recorded them, and room
## for another card's last bits.
const TOLERANCE := 1.0e-3
const RECORDINGS := "res://modules/sara-noise-brush-engine/tests/fixtures/going_back_over_paint/"

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
var _albedo: Dictionary = {}


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)


func after_each() -> void:
    _brush = null
    _albedo.clear()
    Fixtures.teardown(_surface)
    _surface = null


## The scrub holds more of the patch at full alpha than one pass, by
## [constant THICKER], and still not all of it.
func test_a_scrub_holds_more_of_its_patch_at_full_alpha_than_one_pass() -> void:
    for preset: String in PRESETS:
        var once := _full_share(preset, _pass())
        var scrubbed := _full_share(preset, _scrub())
        print(
            (
                "Build-up: %s holds %.3f of its patch at full alpha after one pass and %.3f after the scrub"
                % [preset, once, scrubbed]
            )
        )
        assert_true(
            scrubbed - once >= THICKER,
            "%s scrubbed holds %.3f, at least %.2f more than %.3f after one pass" % [preset, scrubbed, THICKER, once]
        )
        assert_true(scrubbed < 1.0, "%s scrubbed holds %.3f, below all of the patch" % [preset, scrubbed])


## A straight stroke and a stroke that turns through 90 degrees paint their
## recordings texel for texel.
func test_a_stroke_that_never_comes_back_paints_what_it_did_before() -> void:
    var record := OS.has_environment("SARA_RECORD")
    var strokes := {"straight": _straight(), "turn": _turn()}
    for preset: String in PRESETS:
        for stroke: String in strokes:
            _fresh(preset)
            _paint(strokes[stroke])
            var painted := _layer()
            var path := RECORDINGS + "%s_%s.bin" % [preset.to_snake_case(), stroke]
            if record:
                _save(path, painted)
                continue
            var kept := _load(path)
            assert_true(
                kept.size() == painted.size(), "%s %s has a recording of the canvas's size at %s" % [preset, stroke, path]
            )
            if kept.size() != painted.size():
                continue
            var worst := 0.0
            var differing := 0
            for at in painted.size():
                var gap := absf(painted[at] - kept[at])
                worst = maxf(worst, gap)
                if gap > TOLERANCE:
                    differing += 1
            print("Build-up: %s %s differs from its recording by at most %s" % [preset, stroke, worst])
            assert_eq(
                differing,
                0,
                "%s %s differs from its recording by more than %s in %d channels" % [preset, stroke, TOLERANCE, differing]
            )


## The share of the patch's texels *preset* holds at full alpha after it paints
## *path* on a fresh canvas.
func _full_share(preset: String, path: PackedVector2Array) -> float:
    _fresh(preset)
    _paint(path)
    var reach := int(RADIUS * BODY)
    var full := 0
    var count := 0
    for x in range(int(MIDDLE - PATCH / 2.0), int(MIDDLE + PATCH / 2.0)):
        for y in range(int(ROW) - reach, int(ROW) + reach + 1):
            count += 1
            if _texel(Vector2i(x, y)).a >= FULL:
                full += 1
    return float(full) / count


## One pass over the patch, from [constant MARGIN] radii before it to as far
## past it.
func _pass() -> PackedVector2Array:
    var ends := _ends()
    return PackedVector2Array([ends[0], ends[1]])


## Over the patch and back [constant LEGS] times, turning [constant MARGIN]
## radii past it each time.
func _scrub() -> PackedVector2Array:
    var ends := _ends()
    var out := PackedVector2Array([ends[0]])
    for leg in LEGS:
        out.append(ends[(leg + 1) % 2])
    return out


func _ends() -> PackedVector2Array:
    var half := PATCH / 2.0 + MARGIN * RADIUS
    return PackedVector2Array([Vector2(MIDDLE - half, ROW), Vector2(MIDDLE + half, ROW)])


func _straight() -> PackedVector2Array:
    return PackedVector2Array([Vector2(60.0, ROW), Vector2(452.0, ROW)])


func _turn() -> PackedVector2Array:
    return PackedVector2Array([Vector2(60.0, 96.0), Vector2(300.0, 96.0), Vector2(300.0, 336.0)])


## A fresh canvas and *preset* as it ships without its radius taper, at
## [constant RADIUS] and [constant SEED], in black.
func _fresh(preset: String) -> void:
    _albedo.clear()
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = SEED
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == preset:
            var untapered := entry.duplicate(true)
            (untapered["pressure"] as Dictionary).erase("radius")
            _brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, untapered)
    _brush.settings.color = Color(0.0, 0.0, 0.0, 1.0)
    _brush.settings.radius = RADIUS / mini(CANVAS.x, CANVAS.y)


## One stroke through the corners of *path* at [constant PRESSURE], a sample
## every [constant SPACING] pixels.
func _paint(path: PackedVector2Array) -> void:
    var clock := 1000.0
    _brush.begin_stroke(path[0], PRESSURE, Vector2.ZERO, clock)
    for leg in range(1, path.size()):
        var from := path[leg - 1]
        var steps := ceili(from.distance_to(path[leg]) / SPACING)
        for i in range(1, steps + 1):
            clock += SAMPLE_MS
            _brush.add_sample(from.lerp(path[leg], float(i) / steps), PRESSURE, Vector2.ZERO, clock)
    _brush.end_stroke()


## Every channel of the active layer over the canvas, row by row.
func _layer() -> PackedFloat32Array:
    var out := PackedFloat32Array()
    out.resize(CANVAS.x * CANVAS.y * 4)
    for y in CANVAS.y:
        for x in CANVAS.x:
            var texel := _texel(Vector2i(x, y))
            var at := (y * CANVAS.x + x) * 4
            out[at] = texel.r
            out[at + 1] = texel.g
            out[at + 2] = texel.b
            out[at + 3] = texel.a
    return out


func _save(path: String, values: PackedFloat32Array) -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RECORDINGS))
    var file := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
    file.store_buffer(values.to_byte_array())
    file.close()


func _load(path: String) -> PackedFloat32Array:
    var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
    if file == null:
        return PackedFloat32Array()
    var bytes := file.get_buffer(CANVAS.x * CANVAS.y * 16)
    file.close()
    return bytes.to_float32_array()


## The active layer's texel at *pixel*.
func _texel(pixel: Vector2i) -> Color:
    var layer := _surface.easel.document.active_layer
    for grid: Vector2i in layer.chunks:
        var side := (layer.chunks[grid] as SaChunk).pixel_size()
        var here := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
        if not layer.chunks.has(here):
            return Color.TRANSPARENT
        if not _albedo.has(here):
            @warning_ignore("static_called_on_instance")
            _albedo[here] = SaExport.get_texture_image_float(layer.get_field(here))
        return (_albedo[here] as Image).get_pixelv(pixel - here * side)
    return Color.TRANSPARENT
