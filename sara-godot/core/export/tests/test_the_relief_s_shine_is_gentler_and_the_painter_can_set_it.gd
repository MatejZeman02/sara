## The relief's shine is gentler and the painter can set it.
##
## The relief's white highlight was 0.12 at its peak, which read as wet plastic
## rather than oil on a ridge of thick paint, and nothing turned it down but
## the strength, which flattens the relief too. The peak is now Preferences'
## Gloss, `SaSettings.relief_gloss`, and its default is the one that halves
## the rise a flat-tip-style stroke's brightest ridge makes over its body.
##
## The suite paints a stroke with each flat-tip-style preset of the noise brush
## that lays height, since the note names a "Detail" brush no preset of the
## tree carries and any of them is the stroke it means. It reads the view's own
## frame of each at the default, at the old 0.12 and at 0, holds the rise to
## at most 55 percent of the old, finds no texel at 0 brighter than the shade
## alone lights it, and exports each stroke to a 16-bit PNG that has to be the
## view's frame within one step of 255 at the default and at 0.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

## The noise brush's flat-tip-style shelf that lays height. Ribbon Pen and
## Graphite Pencil are at a thickness of 0 and lay none, so no relief shines on
## them whatever the gloss.
const FLAT_TIP_STYLE: Array[String] = ["Firm Fill", "Smeary Flat", "Sea Sponge"]

const SIZE := Vector2i(512, 256)
const RADIUS := 40.0
const FROM := Vector2(70.0, 128.0)
const TO := Vector2(442.0, 128.0)
const PRESSURE := 0.8
const SPACING := 4.0
const SAMPLE_MS := 8.0
const SEED := 7
## A middle brown, the oil a ridge of which the shine was too strong on.
const COLOUR := Color(0.55, 0.32, 0.18, 1.0)
## The old peak, which the default's rise is held against.
const OLD_GLOSS := 0.12
## The note's bound, the default's rise at most this share of the old one's.
const HALF := 0.55
## How far the 16-bit file may stand from the view's eight-bit frame, the
## note's one step of 255.
const VIEW_STEPS := 1.0
## How far the view may stand above the shade worked out here, the eight-bit
## frame's rounding and the display's dither.
const SHADE_STEPS := 1.5

static var scratch_png_path: String = SaDataRoot.path("gloss.png")

var _registries: SaRegistries = null
var _surface: SaSurface = null
var _canvas: SaCanvas = null
var _kept: Dictionary = {}


func before_all() -> void:
    for key: String in ["show_relief", "relief_strength", "relief_light_angle", "relief_gloss", "tonemap_highlights"]:
        _kept[key] = SaSettings.get(key)


func before_each() -> void:
    SaSettings.show_relief = true
    SaSettings.relief_strength = 2.0
    SaSettings.relief_light_angle = 315.0
    SaSettings.tonemap_highlights = false
    SaSettings.relief_gloss = SaSettingsKeys.SETTINGS["relief_gloss"][2]
    _registries = Fixtures.make_picture_registries()


func after_each() -> void:
    _drop()
    _registries = null
    if FileAccess.file_exists(scratch_png_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_png_path))
    for key: String in _kept:
        SaSettings.set(key, _kept[key])


func _drop() -> void:
    if _canvas != null:
        Teardown.free_nodes([_canvas])
    _canvas = null
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = null


## A fresh document with one stroke of *preset* across it, composited, and a
## canvas over it whose relief is bound.
func _paint(preset: String) -> void:
    _drop()
    _surface = Fixtures.make_surface(SIZE)
    var easel := _surface.easel
    easel.compositor.set_registry(_registries.blend_modes)
    var brush := StateNoiseBrushScript.new()
    brush.surface = _surface
    brush.stroke_seed = SEED
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == preset:
            brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
    brush.settings.color = COLOUR
    brush.settings.radius = RADIUS / mini(SIZE.x, SIZE.y)
    var clock := 1000.0
    brush.begin_stroke(FROM, PRESSURE, Vector2.ZERO, clock)
    var steps := ceili(FROM.distance_to(TO) / SPACING)
    for i in range(1, steps + 1):
        clock += SAMPLE_MS
        brush.add_sample(FROM.lerp(TO, float(i) / steps), PRESSURE, Vector2.ZERO, clock)
    brush.end_stroke()
    easel.process_pending_composite()
    _canvas = SaCanvas.new()
    _canvas.canvas_size = SIZE
    _canvas.easel = easel
    _canvas.sync_tonemap()
    _canvas.view_changed()


## The view's frame at *gloss*: the easel's output drawn through the canvas's
## material one texel a pixel, which is the export suite's frame.
func _frame(gloss: float) -> Image:
    SaSettings.relief_gloss = gloss
    _canvas.sync_tonemap()
    var viewport := SubViewport.new()
    viewport.size = SIZE
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    EventBus.add_child(viewport)
    var output := Texture2DRD.new()
    output.texture_rd_rid = _surface.easel.output.rid
    var item := RenderingServer.canvas_item_create()
    RenderingServer.canvas_item_set_parent(item, viewport.find_world_2d().canvas)
    RenderingServer.canvas_item_set_material(item, _canvas.material.get_rid())
    RenderingServer.canvas_item_set_default_texture_filter(item, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
    RenderingServer.canvas_item_add_texture_rect(item, Rect2(Vector2.ZERO, Vector2(SIZE)), output.get_rid())
    RenderingServer.force_draw(false, 0.0)
    var image := viewport.get_texture().get_image()
    RenderingServer.free_rid(item)
    viewport.free()
    return image


## The texels of the stroke's body, away from its ends, whose surface the
## relief tilts.
func _sloped() -> Array[Vector2i]:
    var relief := _surface.easel.relief.texture
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(relief.rid, 0)
    var found: Array[Vector2i] = []
    for y in range(int(FROM.y - RADIUS), int(FROM.y + RADIUS) + 1):
        for x in range(int(FROM.x + 2.0 * RADIUS), int(TO.x - 2.0 * RADIUS)):
            var normal := SaFieldSpec.decode_texel(bytes, relief.format, y * SIZE.x + x)
            if normal.r != 0.0 or normal.g != 0.0:
                found.append(Vector2i(x, y))
    return found


## The brightest ridge, the sloped texel the old gloss lights brightest.
static func _brightest(frame: Image, texels: Array[Vector2i]) -> Vector2i:
    var best := texels[0]
    for at: Vector2i in texels:
        if frame.get_pixelv(at).get_luminance() > frame.get_pixelv(best).get_luminance():
            best = at
    return best


## How far *frame* lights the ridge *at* above the paint under it, *flat*, the
## same texel with no shine, as eight-bit luminance.
static func _rise(frame: Image, flat: Image, at: Vector2i) -> float:
    return frame.get_pixelv(at).get_luminance() - flat.get_pixelv(at).get_luminance()


## How far the brightest texel of *frame* stands above the stroke's body, its
## median, over *texels*, the shade's lift and the shine together.
static func _over_body(frame: Image, texels: Array[Vector2i]) -> float:
    var values: Array[float] = []
    for at: Vector2i in texels:
        values.append(frame.get_pixelv(at).get_luminance())
    values.sort()
    @warning_ignore("integer_division")
    return values[values.size() - 1] - values[values.size() / 2]


## The case that matters: at the default the brightest ridge rises at most 55
## percent of what it rises at 0.12, for every flat-tip-style preset.
func test_the_default_shine_rises_at_most_55_percent_of_the_old() -> void:
    var default_gloss: float = SaSettingsKeys.SETTINGS["relief_gloss"][2]
    assert_true(default_gloss < OLD_GLOSS, "The default %.3f is gentler than the old %.2f" % [default_gloss, OLD_GLOSS])
    for preset: String in FLAT_TIP_STYLE:
        _paint(preset)
        var texels := _sloped()
        assert_true(texels.size() > 500, "%s lays a relief, %d sloped texels of its body" % [preset, texels.size()])
        var old_frame := _frame(OLD_GLOSS)
        var now_frame := _frame(default_gloss)
        var flat := _frame(0.0)
        var ridge := _brightest(old_frame, texels)
        var old := _rise(old_frame, flat, ridge)
        var now := _rise(now_frame, flat, ridge)
        print(
            (
                "probe: %s ridge %s %.4f at 0, rises %.4f at 0.12 and %.4f at %.3f, over the body %.4f, %.4f and %.4f"
                % [
                    preset,
                    ridge,
                    flat.get_pixelv(ridge).get_luminance(),
                    old,
                    now,
                    default_gloss,
                    _over_body(old_frame, texels),
                    _over_body(now_frame, texels),
                    _over_body(flat, texels)
                ]
            )
        )
        assert_true(old > 0.0, "%s's ridge shines at the old gloss, %.4f over the paint under it" % [preset, old])
        assert_true(now <= HALF * old, "%s rises %.4f at the default, at most %.2f of %.4f" % [preset, now, HALF, old])


## The case that matters: at 0 no texel of the view is brighter than the shade
## alone lights it, the shade worked out here from the stored colour and the
## relief's normal by the view's own formula with no gloss in it.
func test_a_gloss_of_0_shines_nowhere() -> void:
    for preset: String in FLAT_TIP_STYLE:
        _paint(preset)
        var stored := SaExport.get_texture_image_float(_surface.easel.output)
        var relief := _surface.easel.relief.texture
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(relief.rid, 0)
        var doc := _surface.easel.document
        var light := doc.relief_light.toward()
        var strength := doc.relief_light.strength
        var none := _frame(0.0)
        var old := _frame(OLD_GLOSS)
        var worst := -1.0
        var shone := 0
        for at: Vector2i in _sloped():
            var normal := SaFieldSpec.decode_texel(bytes, relief.format, at.y * SIZE.x + at.x)
            var shade := _shade(stored.get_pixelv(at), Vector3(normal.r, normal.g, normal.b), light, strength)
            var shown := none.get_pixelv(at)
            worst = maxf(worst, maxf(shown.r - shade.r, maxf(shown.g - shade.g, shown.b - shade.b)))
            if old.get_pixelv(at).get_luminance() > shade.get_luminance() + SHADE_STEPS / 255.0:
                shone += 1
        print(
            "probe: %s at 0 stands %.2f steps above the shade at most, %d texels shine at 0.12" % [preset, worst * 255.0, shone]
        )
        assert_true(worst * 255.0 <= SHADE_STEPS, "%s at 0 is at most the shade alone, %.2f steps over" % [preset, worst * 255.0])
        assert_true(shone > 0, "and at 0.12 the same view shines on %d texels, so the reading can tell" % shone)


## The case that matters: the export's bake is the view's light within one
## step of 255, at the default and at 0.
func test_the_export_bakes_the_view_s_shine_at_the_default_and_at_0() -> void:
    var default_gloss: float = SaSettingsKeys.SETTINGS["relief_gloss"][2]
    for preset: String in FLAT_TIP_STYLE:
        _paint(preset)
        for gloss: float in [default_gloss, 0.0]:
            var frame := _frame(gloss)
            var wrote := SaExport.export_png(_surface.easel, scratch_png_path, 16, false, SaGamutMapping.CLIP, true)
            assert_eq(wrote, OK, "%s exports at %.3f" % [preset, gloss])
            var pixels := _png16(FileAccess.get_file_as_bytes(scratch_png_path))
            var worst := 0.0
            var worst_at := Vector2i.ZERO
            for y in SIZE.y:
                for x in SIZE.x:
                    var shown := frame.get_pixel(x, y)
                    var written := pixels[y * SIZE.x + x]
                    var gap := maxf(absf(shown.r - written.r), maxf(absf(shown.g - written.g), absf(shown.b - written.b)))
                    if gap > worst:
                        worst = gap
                        worst_at = Vector2i(x, y)
            print("probe: %s at %.3f, the file stands %.2f steps from the view at most" % [preset, gloss, worst * 255.0])
            var said := "%s at %.3f, the file is the view within %.0f step" % [preset, gloss, VIEW_STEPS]
            assert_true(worst * 255.0 <= VIEW_STEPS, "%s, the worst %.2f at %s" % [said, worst * 255.0, worst_at])


## The slider sits under Relief strength on the Display page and writes the
## setting, and the setting reaches the canvas's material.
func test_the_slider_sets_the_gloss_the_view_reads() -> void:
    _paint(FLAT_TIP_STYLE[0])
    SaSettings.relief_gloss = 0.03
    _canvas.sync_tonemap()
    var read: float = (_canvas.material as ShaderMaterial).get_shader_parameter("relief_gloss")
    assert_almost_eq(read, 0.03, 0.0001, "The canvas's material reads the setting")
    SaSettings.relief_gloss = 1.0
    assert_almost_eq(SaSettings.relief_gloss, OLD_GLOSS, 0.0001, "and the setting stops at the old peak")


## Linear light from a stored sRGB number, the curve the view decodes by.
static func _decode(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


static func _encode(c: float) -> float:
    return c * 12.92 if c <= 0.0031308 else 1.055 * pow(c, 1.0 / 2.4) - 0.055


## `sa_relief_shade` with no gloss, on the stored sRGB *colour*, answered as
## the display's sRGB.
static func _shade(colour: Color, normal: Vector3, light: Vector3, strength: float) -> Color:
    var slope := Vector2(normal.x, normal.y) / maxf(normal.z, 1e-3) * strength
    var steep := slope.length() / 1.5
    slope /= sqrt(1.0 + steep * steep)
    var n := Vector3(slope.x, slope.y, 1.0).normalized()
    var l := light.normalized()
    var gained := n.dot(l) - l.z
    var shade := maxf(1.0 + gained * (0.35 if gained > 0.0 else 0.8), 0.0)
    return Color(
        _encode(_decode(colour.r) * shade), _encode(_decode(colour.g) * shade), _encode(_decode(colour.b) * shade), colour.a
    )


## The samples of the 16-bit RGBA PNG *bytes* as fractions of 65535, one Color
## a pixel. The writer writes every scanline unfiltered.
static func _png16(bytes: PackedByteArray) -> Array[Color]:
    var data := PackedByteArray()
    var at := 8
    while at + 12 <= bytes.size():
        var length := (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]
        if bytes.slice(at + 4, at + 8).get_string_from_ascii() == "IDAT":
            data.append_array(bytes.slice(at + 8, at + 8 + length))
        at += 12 + length
    var raw := data.decompress_dynamic(1 << 23, FileAccess.COMPRESSION_DEFLATE)
    var stride := 1 + SIZE.x * 8
    var pixels: Array[Color] = []
    for y in SIZE.y:
        for x in SIZE.x:
            var i := y * stride + 1 + x * 8
            var c := PackedFloat32Array()
            for channel in 4:
                c.append(float((raw[i + channel * 2] << 8) | raw[i + channel * 2 + 1]) / 65535.0)
            pixels.append(Color(c[0], c[1], c[2], c[3]))
    return pixels
