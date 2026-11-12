## The highlight roll-off leaves a colour under its knee as the
## display would show it.
##
## The artistic tonemapper must not change a face highlight even when Knee is
## at 4 and desaturation at 0. The knee is now where the
## roll-off starts: between white and the knee a colour moves from the channel by
## channel clip to the held ratios by a smoothstep of the peak. This draws a ramp
## of colours from 0 to 4 in light through the canvas's own material, at a knee
## of 1.0 against the bytes measured before the change, and at a knee of 4
## against the clip and the held ratios, and reads the export's Paper method and
## the plot against the view on every one of them.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const ONE_STEP := 1

## Steps of the ramp a unit of light, so 129 colours a hue from 0 to 4.
const RAMP_STEPS := 32
const RAMP_TOP := 4.0

## The hues of the ramp, in light with the peak at one: a skin tone, a
## red, a green, a blue, a grey, a yellow, a violet and one with a channel below
## zero.
const HUES: Array[Vector3] = [
    Vector3(1.0, 0.559, 0.518),
    Vector3(1.0, 0.1, 0.05),
    Vector3(0.2, 1.0, 0.3),
    Vector3(0.1, 0.2, 1.0),
    Vector3(1.0, 1.0, 1.0),
    Vector3(1.0, 0.9, 0.1),
    Vector3(0.8, 0.1, 1.0),
    Vector3(1.0, -0.05, 0.3),
]

## The md5 of the view's bytes for the whole ramp at a knee of 1.0, a
## desaturation of 0.15 and the gamut mapping at clip, measured at the integration tip `42ba1c6e9` before the
## knee moved where the ratios start being held.
const TODAY_MD5 := "7933f8571b4b46992b2c6ff75997974e"

## A skin tone, its red at 1.28 in light, and the same hue at 4.
const SKIN := Vector3(1.28, 0.716, 0.663)
const HOT_SKIN := Vector3(4.0, 2.236, 2.072)

const VIEW_KEYS: Array[StringName] = [
    &"tonemap_highlights",
    &"tonemap_knee",
    &"tonemap_desaturation",
    &"gamut_mapping",
    &"display_exposure_enabled",
    &"display_exposure_stops",
    &"display_profile",
    &"shape_check",
]

var _saved := {}
var _canvas: SaCanvas = null


func before_each() -> void:
    var fresh := SaSettingsValues.new()
    for key: StringName in VIEW_KEYS:
        _saved[key] = SaSettings.get(key)
        SaSettings.set(key, fresh.get(key))
    fresh.free()
    # A screen clips a colour past white channel by channel, and the
    # clip is where the blend starts.
    SaSettings.gamut_mapping = "clip"
    _canvas = SaCanvas.new()
    _canvas.canvas_size = Vector2i(64, 64)
    _canvas.ensure_easel()
    _canvas.sync_tonemap()


func after_each() -> void:
    if _canvas != null:
        _canvas.free()
    _canvas = null
    for key: StringName in VIEW_KEYS:
        SaSettings.set(key, _saved[key])


func test_at_a_knee_of_1_every_colour_of_the_ramp_reads_as_it_did() -> void:
    var ramp := _ramp()
    var shown := _view(ramp, true, 1.0, 0.15)
    var digest := _digest(shown, ramp.size())
    print("    probe: the ramp at a knee of 1.0 reads md5 %s" % digest)
    assert_eq(digest, TODAY_MD5, "Every colour of the ramp at a knee of 1.0 is the byte it was")


func test_at_a_knee_of_4_a_skin_at_1_28_is_the_clip_and_one_at_4_the_held_ratios() -> void:
    var colours: Array[Color] = [_encoded(SKIN), _encoded(HOT_SKIN)]
    var on := _view(colours, true, 4.0, 0.0)
    var off := _view(colours, false, 4.0, 0.0)
    var clipped := _bytes_of(_encoded(SKIN.clampf(0.0, 1.0)))
    var plain := _bytes(off, 0)
    assert_true(_differ(plain, clipped) <= ONE_STEP, "The roll-off off clips the skin channel by channel, %s" % plain)
    var skin := _bytes(on, 0)
    assert_true(_differ(skin, clipped) <= ONE_STEP, "The skin at 1.28 reads %s, the clip %s" % [skin, clipped])
    var held := _bytes_of(_encoded(HOT_SKIN / HOT_SKIN.x))
    var hot := _bytes(on, 1)
    assert_true(_differ(hot, held) <= ONE_STEP, "The skin at 4 reads %s, its ratios held %s" % [hot, held])
    var before := _view(colours, true, 1.0, 0.0)
    assert_true(_differ(hot, _bytes(before, 1)) <= ONE_STEP, "and what a knee of 1.0 shows it as, %s" % _bytes(before, 1))
    print("    probe: skin at 1.28 off %s on %s, at 4 on %s held %s" % [_bytes(off, 0), skin, hot, held])


## The ramp at both knees and both desaturations that matter: the export's
## Paper method and the plot within one step of the view on every colour.
func test_the_export_and_the_plot_give_the_views_bytes_at_both_knees() -> void:
    var ramp := _ramp()
    for setting: Vector2 in [Vector2(1.0, 0.15), Vector2(4.0, 0.0), Vector2(4.0, 0.15), Vector2(2.5, 0.5)]:
        var shown := _view(ramp, true, setting.x, setting.y)
        var params := SaExportGamut.tonemap_params(true, setting.x, setting.y, 1.0)
        var exported := SaExportGamut.encoded_byte_image(_texture(ramp), SaColorSpace.srgb(), null, params)
        var export_worst := [0, Color()]
        var plot_worst := [0, Color()]
        for i in ramp.size():
            var view := _bytes(shown, i)
            var place := _place(i, exported.get_width())
            var out := exported.get_pixel(place.x, place.y)
            _note_worst(export_worst, view, Vector3i(out.r8, out.g8, out.b8), ramp[i])
            # The plot decodes a channel below zero by the curve's straight foot
            # rather than mirrored, so it is read on the colours with none.
            if minf(ramp[i].r, minf(ramp[i].g, ramp[i].b)) >= 0.0:
                var plotted := SaCurvePlot.rolled(ramp[i], setting.x, setting.y)
                _note_worst(plot_worst, view, _bytes_of(plotted), ramp[i])
        var at := "at a knee of %s and a desaturation of %s" % [setting.x, setting.y]
        var words := "The %s differs from the view %s by %d levels at %s"
        assert_true(export_worst[0] <= ONE_STEP, words % ["export", at, export_worst[0], export_worst[1]])
        assert_true(plot_worst[0] <= ONE_STEP, words % ["plot", at, plot_worst[0], plot_worst[1]])


## Between white and the knee the shown colour moves from the clip to the held
## ratios without a jump: no step of the walk moves it more than a level past
## the most the clip itself moves, since the clip's green and blue climb with
## the peak.
func test_under_a_knee_of_4_the_skin_walks_from_the_clip_to_the_held_ratios_smoothly() -> void:
    var colours: Array[Color] = []
    for i in RAMP_STEPS * 3 + 1:
        colours.append(_encoded(SKIN / SKIN.x * (1.0 + float(i) / RAMP_STEPS)))
    var shown := _view(colours, true, 4.0, 0.0)
    var clipped := _view(colours, false, 4.0, 0.0)
    var worst := 0
    var worst_clipped := 0
    for i in range(1, colours.size()):
        worst = maxi(worst, _differ(_bytes(shown, i), _bytes(shown, i - 1)))
        worst_clipped = maxi(worst_clipped, _differ(_bytes(clipped, i), _bytes(clipped, i - 1)))
    var words := "One step of the walk from 1 to 4 moves the skin %d levels at the most, the clip %d"
    assert_true(worst <= worst_clipped + ONE_STEP, words % [worst, worst_clipped])


func _ramp() -> Array[Color]:
    var out: Array[Color] = []
    for hue: Vector3 in HUES:
        for i in int(RAMP_TOP) * RAMP_STEPS + 1:
            out.append(_encoded(hue * (float(i) / RAMP_STEPS)))
    return out


## *colours*, stored sRGB numbers, drawn one texel a pixel through the canvas's
## own material into an 8-bit viewport with the roll-off *on* or off at *knee*
## and *desaturation*, and read back.
func _view(colours: Array[Color], on: bool, knee: float, desaturation: float) -> Image:
    SaSettings.tonemap_highlights = on
    SaSettings.tonemap_knee = knee
    SaSettings.tonemap_desaturation = desaturation
    _canvas.sync_tonemap()
    var texture := _texture(colours)
    var viewport := SubViewport.new()
    viewport.size = texture.size
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    EventBus.add_child(viewport)
    var output := Texture2DRD.new()
    output.texture_rd_rid = texture.rid
    var item := RenderingServer.canvas_item_create()
    RenderingServer.canvas_item_set_parent(item, viewport.find_world_2d().canvas)
    RenderingServer.canvas_item_set_material(item, _canvas.material.get_rid())
    RenderingServer.canvas_item_set_default_texture_filter(item, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
    RenderingServer.canvas_item_add_texture_rect(item, Rect2(Vector2.ZERO, Vector2(texture.size)), output.get_rid())
    RenderingServer.force_draw(false, 0.0)
    var image := viewport.get_texture().get_image()
    RenderingServer.free_rid(item)
    viewport.free()
    return image


## *colours* as one texel each in a float texture, 64 a row.
static func _texture(colours: Array[Color]) -> SaTexture:
    var width := mini(colours.size(), 64)
    var height := ceili(float(colours.size()) / width)
    var texture := SaTexture.new(Vector2i(width, height))
    var texels := PackedFloat32Array()
    texels.resize(width * height * 4)
    for i in colours.size():
        texels[i * 4] = colours[i].r
        texels[i * 4 + 1] = colours[i].g
        texels[i * 4 + 2] = colours[i].b
        texels[i * 4 + 3] = 1.0
    texture.rd.texture_update(texture.rid, 0, texels.to_byte_array())
    return texture


## The md5 of the first *count* texels' bytes of *image*, row after row.
static func _digest(image: Image, count: int) -> String:
    var bytes := PackedByteArray()
    for i in count:
        var b := _bytes(image, i)
        bytes.append_array(PackedByteArray([b.x, b.y, b.z]))
    return bytes.hex_encode().md5_text()


static func _bytes(image: Image, index: int) -> Vector3i:
    var place := _place(index, image.get_width())
    return _bytes_of(image.get_pixel(place.x, place.y))


static func _bytes_of(c: Color) -> Vector3i:
    return Vector3i(c.r8, c.g8, c.b8)


static func _place(index: int, width: int) -> Vector2i:
    return Vector2i(index % width, floori(float(index) / width))


static func _differ(a: Vector3i, b: Vector3i) -> int:
    return maxi(absi(a.x - b.x), maxi(absi(a.y - b.y), absi(a.z - b.z)))


static func _note_worst(worst: Array, view: Vector3i, other: Vector3i, at: Color) -> void:
    var differ := _differ(view, other)
    if differ > int(worst[0]):
        worst[0] = differ
        worst[1] = at


## Light as the stored sRGB numbers a document holds, by the mirrored curve.
static func _encoded(light: Vector3) -> Color:
    var curve := SaTransferFunction.srgb()
    return Color(curve.encode(light.x), curve.encode(light.y), curve.encode(light.z))
