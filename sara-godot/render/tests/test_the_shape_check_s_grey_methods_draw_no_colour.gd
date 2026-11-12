## The Shape Check gets methods whose output is grey, asked for as "also add
## some methods that have monochrome output".
##
## One picture of twelve flat bands, each a hue of its own and each lighter than
## the one before, finely striped, is drawn through the canvas's own material
## under Grey masses and Notan and read back. Every texel of both has a and b
## of Oklab at nought, Grey masses lands on the painter's count of levels, and
## Notan on exactly as many values as it was set to, cut where its thresholds
## say. Both read the masses method's reach, so the picture at twice the size, brought down,
## agrees with it. A profile from before the grey methods opens on the view it
## showed. The Display page's rows are `test_display_page.gd`'s, because a
## suite under `render` names nothing of `ui`.
extends "res://tests/test_framework.gd"

## The picture is composited, drawn through the canvas material and read back.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const AUTOLOAD := "res://core/settings/sa_settings.gd"

## The mode the shader branches on for the Shape Check.
const SHAPE_VIEW_MODE := 5

## The two widths the picture is drawn at, the second twice the first, and the
## height a share of the width.
const SMALL := 256
const LARGE := 512
const HEIGHT_SHARE := 0.5

## The bands: how many across, the chroma each carries in Oklab and how far its
## hue turns from one to the next, in degrees.
const BANDS := 12
const CHROMA := 0.1
const HUE_STEP := 30.0

## The detail the methods have to take away: vertical stripes, this many across
## the width and this far either side of the band's own colour.
const STRIPES := 64.0
const STRIPE_DEPTH := 0.02

## How far an Oklab a or b may stand from nought and still read as grey: what
## an 8-bit grey read back comes to through the float conversion, which is
## under a millionth, with room to spare.
const GREY_BOUND := 1e-4

## How much chroma the same picture keeps under the colour Masses, so the grey
## methods are seen taking something away.
const COLOUR_FLOOR := 0.03

## How far a value read back may stand from the one the thresholds predict, a
## level of an 8-bit channel.
const LEVEL := 1.0 / 255.0

## The bounds the two sizes are held to, on values from nought to one: the mean
## difference over every texel's largest channel under a hundredth, two and a
## half steps of an 8-bit channel, and the share of texels that differ by more
## than a quarter no more than the eleven edges between the bands' own columns
## at the smaller size, where the halving blends a pair that straddles an edge
## and the smaller picture has a texel of one band.
const MEAN_BOUND := 0.01
const SPLIT_SHARE := (BANDS - 1.0) / SMALL

## How much of the stripes' swing may survive under Grey masses, as a share of
## the picture's own.
const STRIPES_LEFT := 0.5

## The band the swing is read inside, a light one, where an 8-bit step of the
## stripes is a small step of lightness and the smoothing is read on its own.
const SWING_BAND := 8

var _registries: SaRegistries = null
var _easels: Array[SaEasel] = []
var _canvases: Array[SaCanvas] = []
var _kept := {}
static var scratch_path: String = SaDataRoot.path("test_a_profile_before_the_grey_methods.cfg")


func before_each() -> void:
    for key: String in SaSettings.shape_check_uniforms():
        _kept[key] = SaSettings.get(key)
    _kept["tonemap_highlights"] = SaSettings.tonemap_highlights
    SaSettings.tonemap_highlights = false
    SaSettings.shape_check_reach = 0.015
    _registries = Fixtures.make_registries()


func after_each() -> void:
    for canvas: SaCanvas in _canvases:
        canvas.free()
    _canvases.clear()
    for easel: SaEasel in _easels:
        easel.free()
    _easels.clear()
    _registries = null
    for key: String in _kept:
        SaSettings.set(key, _kept[key])
    _kept.clear()
    var scratch := ProjectSettings.globalize_path(scratch_path)
    for suffix: String in ["", SaSettingsFile.BACKUP_SUFFIX]:
        DirAccess.remove_absolute(scratch + suffix)


## Band *k*'s colour as the 8-bit sRGB an import stores: Oklab lightness from
## dark to light across the bands, a hue of its own, held inside the cube.
static func _band(k: int) -> Color:
    var hue := deg_to_rad(k * HUE_STEP)
    var lab := Vector3((k + 0.5) / BANDS, CHROMA * cos(hue), CHROMA * sin(hue))
    var linear := SaOklab.to_linear_srgb(lab).clamp(Vector3.ZERO, Vector3.ONE)
    var color := Color(linear.x, linear.y, linear.z).linear_to_srgb()
    return Color8(color.r8, color.g8, color.b8)


## The Oklab lightness band *k* holds as stored, which is what a threshold cuts.
static func _band_lightness(k: int) -> float:
    var color := _band(k).srgb_to_linear()
    return SaOklab.from_linear_srgb(Vector3(color.r, color.g, color.b)).x


## The picture at *width*, every texel worked out from where it sits as a share
## of the picture, so the two sizes are one picture sampled twice.
static func _picture(width: int) -> Image:
    var height := roundi(width * HEIGHT_SHARE)
    var image := Image.create_empty(width, height, false, Image.FORMAT_RGB8)
    for x in width:
        var u := (x + 0.5) / width
        var color := _band(mini(floori(u * BANDS), BANDS - 1))
        var stripe := STRIPE_DEPTH if fmod(u * STRIPES, 1.0) < 0.5 else -STRIPE_DEPTH
        var striped := Color(color.r + stripe, color.g + stripe, color.b + stripe)
        for y in height:
            image.set_pixel(x, y, striped)
    return image


## An sRGB easel holding *image* put down the way an import puts a picture
## down, composited, and a canvas over it with its material built.
func _canvas_over(image: Image) -> SaCanvas:
    var easel := SaEasel.create_default(image.get_size(), null, SaColorSpace.srgb())
    easel.compositor.set_registry(_registries.blend_modes)
    _easels.append(easel)
    var layer := SaImageImport.place(easel.document, image, "probe", SaColorSpace.srgb(), SaImageImport.Fit.ORIGIN)
    assert_not_null(layer, "The picture is put down as a layer")
    easel.request_full_composite()
    easel.process_pending_composite()
    var canvas := SaCanvas.new()
    canvas.canvas_size = easel.document.canvas_size
    canvas.easel = easel
    canvas.sync_tonemap()
    _canvases.append(canvas)
    return canvas


## *canvas*'s picture drawn one texel a pixel through its own material on the
## Shape Check and read back, the frame a painter sees. A canvas with no
## registry holds the ordinary view, so the mode is handed to the material
## here, after the sync that would put it back.
func _frame(canvas: SaCanvas) -> Image:
    canvas.sync_tonemap()
    var material := canvas.material as ShaderMaterial
    material.set_shader_parameter("view_mode", SHAPE_VIEW_MODE)
    var easel := canvas.easel
    var size := easel.document.canvas_size
    var viewport := SubViewport.new()
    viewport.size = size
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    EventBus.add_child(viewport)
    var output := Texture2DRD.new()
    output.texture_rd_rid = easel.output.rid
    var item := RenderingServer.canvas_item_create()
    RenderingServer.canvas_item_set_parent(item, viewport.find_world_2d().canvas)
    RenderingServer.canvas_item_set_material(item, material.get_rid())
    RenderingServer.canvas_item_set_default_texture_filter(item, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
    RenderingServer.canvas_item_add_texture_rect(item, Rect2(Vector2.ZERO, Vector2(size)), output.get_rid())
    RenderingServer.force_draw(false, 0.0)
    var image := viewport.get_texture().get_image()
    RenderingServer.free_rid(item)
    viewport.free()
    image.convert(Image.FORMAT_RGBF)
    return image


## The picture at the small size under the settings as they stand.
func _small_frame() -> Image:
    return _frame(_canvas_over(_picture(SMALL)))


## A texel read back as Oklab, out of the sRGB the frame holds.
static func _oklab(color: Color) -> Vector3:
    var linear := color.srgb_to_linear()
    return SaOklab.from_linear_srgb(Vector3(linear.r, linear.g, linear.b))


## The furthest any texel of *image* stands from the grey axis, the larger of
## its a and b.
static func _farthest_from_grey(image: Image) -> float:
    var farthest := 0.0
    for y in image.get_height():
        for x in image.get_width():
            var lab := _oklab(image.get_pixel(x, y))
            farthest = maxf(farthest, maxf(absf(lab.y), absf(lab.z)))
    return farthest


## The values *image* holds, each texel as its three 8-bit channels.
static func _values(image: Image) -> Dictionary:
    var seen := {}
    for y in image.get_height():
        for x in image.get_width():
            var color := image.get_pixel(x, y)
            seen[Vector3i(color.r8, color.g8, color.b8)] = true
    return seen


## The value band *k* is read as, at its middle, half way down.
static func _read_band(image: Image, k: int) -> float:
    var x := floori((k + 0.5) * image.get_width() / BANDS)
    return image.get_pixel(x, image.get_height() >> 1).r


## The value a notan draws a lightness of *lightness* as, out of the thresholds
## as they stand, in the sRGB the frame holds: black, the middle of the
## lightness scale, or white.
static func _notan_value(lightness: float) -> float:
    var cut := 0.0
    if SaSettings.shape_check_notan_values == 2:
        cut = 0.0 if lightness < SaSettings.shape_check_notan_threshold else 1.0
    elif lightness < SaSettings.shape_check_notan_dark:
        cut = 0.0
    else:
        cut = 0.5 if lightness < SaSettings.shape_check_notan_light else 1.0
    var linear := cut * cut * cut
    return Color(linear, linear, linear).linear_to_srgb().r


## The ask itself: every texel of each grey method's output reads with a and b
## of Oklab at nought, while the same picture under the colour Masses keeps its
## hues, so the grey is the method's doing and not the picture's.
func test_every_texel_of_each_grey_method_has_no_a_or_b() -> void:
    SaSettings.shape_check_method = SaSettings.SHAPE_MASSES
    SaSettings.shape_check_levels = true
    var colour := _farthest_from_grey(_small_frame())
    assert_true(colour > COLOUR_FLOOR, "The picture under Masses keeps its colour, a or b to %.3f" % colour)

    var cases := [
        [SaSettings.SHAPE_GREY_MASSES, true, 2],
        [SaSettings.SHAPE_GREY_MASSES, false, 2],
        [SaSettings.SHAPE_NOTAN, true, 2],
        [SaSettings.SHAPE_NOTAN, true, 3],
    ]
    for case: Array in cases:
        SaSettings.shape_check_method = case[0]
        SaSettings.shape_check_levels = case[1]
        SaSettings.shape_check_notan_values = case[2]
        var name := "%s, posterise %s, %d values" % case
        var farthest := _farthest_from_grey(_small_frame())
        assert_true(
            farthest < GREY_BOUND,
            "%s: every texel's a and b within %.4f of nought, the worst %.7f" % [name, GREY_BOUND, farthest]
        )


## Grey masses is "the masses in grey at the painter's count of levels":
## with the posterise on, the frame holds exactly that many greys.
func test_grey_masses_land_on_the_painters_count_of_levels() -> void:
    SaSettings.shape_check_method = SaSettings.SHAPE_GREY_MASSES
    SaSettings.shape_check_levels = true
    for count: int in [3, 5]:
        SaSettings.shape_check_level_count = count
        var held := _values(_small_frame()).size()
        assert_eq(held, count, "%d levels: the frame holds %d greys" % [count, held])


## Notan is "the lightness thresholded to two or three values, its thresholds
## set on the same page with the middle as the default": as many values as it
## was set to over every texel, and each band on the side of each threshold its
## own lightness puts it, at the default thresholds and at moved ones.
func test_a_notan_has_as_many_values_as_it_was_set_to_cut_where_its_thresholds_say() -> void:
    var fresh: Node = load(AUTOLOAD).new()
    assert_almost_eq(fresh.shape_check_notan_threshold, 0.5, 1e-6, "Two values cut at the middle by default")
    assert_almost_eq(fresh.shape_check_notan_dark, 1.0 / 3.0, 1e-6, "and three at a third")
    assert_almost_eq(fresh.shape_check_notan_light, 2.0 / 3.0, 1e-6, "and two thirds, the middle value on the middle")
    fresh.free()
    SaSettings.shape_check_method = SaSettings.SHAPE_NOTAN
    var thresholds := [
        [2, 0.5, 1.0 / 3.0, 2.0 / 3.0],
        [3, 0.5, 1.0 / 3.0, 2.0 / 3.0],
        [2, 0.25, 1.0 / 3.0, 2.0 / 3.0],
        [3, 0.5, 1.0 / 6.0, 5.0 / 6.0],
    ]
    for case: Array in thresholds:
        SaSettings.shape_check_notan_values = case[0]
        SaSettings.shape_check_notan_threshold = case[1]
        SaSettings.shape_check_notan_dark = case[2]
        SaSettings.shape_check_notan_light = case[3]
        var name := "%d values at %.2f, %.2f and %.2f" % case
        var frame := _small_frame()
        var held := _values(frame).size()
        assert_eq(held, case[0], "%s: the frame holds %d values" % [name, held])
        var wrong: Array[String] = []
        for k in BANDS:
            var want := _notan_value(_band_lightness(k))
            var have := _read_band(frame, k)
            if absf(have - want) > LEVEL:
                wrong.append("band %d at lightness %.3f read %.3f for %.3f" % [k, _band_lightness(k), have, want])
        assert_true(wrong.is_empty(), "%s: every band on its side of the thresholds: %s" % [name, "; ".join(wrong)])


## *image* brought to half its size, each texel the mean of the two by two it
## covers.
static func _halved(image: Image) -> Image:
    var half := Image.create_empty(image.get_width() >> 1, image.get_height() >> 1, false, Image.FORMAT_RGBF)
    for y in half.get_height():
        for x in half.get_width():
            var sum := Color(0, 0, 0, 0)
            for dy in 2:
                for dx in 2:
                    sum += image.get_pixel(x * 2 + dx, y * 2 + dy)
            half.set_pixel(x, y, sum / 4.0)
    return half


## How far the lightness swings along the middle row inside band *k*, the
## spread of its values, which is the stripes and nothing else there.
static func _swing(image: Image, k: int) -> float:
    var y := image.get_height() >> 1
    var values: Array[float] = []
    var width := float(image.get_width()) / BANDS
    for x in range(roundi((k + 0.25) * width), roundi((k + 0.75) * width)):
        values.append(_oklab(image.get_pixel(x, y)).x)
    var mean := 0.0
    for value: float in values:
        mean += value
    mean /= values.size()
    var spread := 0.0
    for value: float in values:
        spread += (value - mean) * (value - mean)
    return sqrt(spread / values.size())


## "They read the masses method's reach, so they hold at any canvas size": the picture at
## twice the size, brought down, agrees with the smaller under each grey method,
## and under Grey masses the stripes finer than the reach are gone at both.
func test_the_grey_methods_read_alike_at_two_sizes() -> void:
    SaSettings.shape_check_reach = 0.03
    var cases := [
        [SaSettings.SHAPE_GREY_MASSES, false, 2],
        [SaSettings.SHAPE_NOTAN, true, 2],
        [SaSettings.SHAPE_NOTAN, true, 3],
    ]
    for case: Array in cases:
        SaSettings.shape_check_method = case[0]
        SaSettings.shape_check_levels = case[1]
        SaSettings.shape_check_notan_values = case[2]
        var name := "%s, posterise %s, %d values" % case
        var small := _small_frame()
        var large := _frame(_canvas_over(_picture(LARGE)))
        var brought := _halved(large)
        var total := 0.0
        var split := 0
        for y in small.get_height():
            for x in small.get_width():
                var a := small.get_pixel(x, y)
                var b := brought.get_pixel(x, y)
                var difference := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
                total += difference
                if difference > 0.25:
                    split += 1
        var texels := small.get_width() * small.get_height()
        var mean := total / texels
        var share := float(split) / texels
        assert_true(mean < MEAN_BOUND, "%s: the two sizes agree on the mean, %.4f under %.2f" % [name, mean, MEAN_BOUND])
        assert_true(share <= SPLIT_SHARE, "%s: and %.4f of the texels split, at most %.4f" % [name, share, SPLIT_SHARE])
        if case[0] == SaSettings.SHAPE_GREY_MASSES:
            var picture := _picture(SMALL)
            picture.convert(Image.FORMAT_RGBF)
            var before := _swing(picture, SWING_BAND)
            for frame: Image in [small, large]:
                var after := _swing(frame, SWING_BAND)
                var shown := (
                    "%s at %d wide: the stripes swing by %.4f of the picture's %.4f" % [name, frame.get_width(), after, before]
                )
                assert_true(after < before * STRIPES_LEFT, shown)


## A profile from before the grey methods holds one of the three methods the masses
## method stored and no key of Notan. It opens on that method, each at the number the
## shader branched on before, with Notan's options at their defaults, and the
## material carries the method and the switch.
func test_a_profile_from_before_opens_on_the_view_it_showed() -> void:
    var numbers := {SaSettings.SHAPE_BLOCKS: 0, SaSettings.SHAPE_MASSES: 1, SaSettings.SHAPE_NONE: 2}
    var scratch := ProjectSettings.globalize_path(scratch_path)
    for method: String in numbers:
        var profile := ConfigFile.new()
        profile.set_value("meta", "version", SaSettings.SETTINGS_VERSION)
        profile.set_value("ui", "shape_check_method", method)
        profile.set_value("ui", "shape_check_levels", false)
        profile.set_value("ui", "shape_check_level_count", 4)
        assert_eq(profile.save(scratch), OK, "%s: the profile is on disk" % method)
        var settings: Node = load(AUTOLOAD).new()
        settings.settings_path = scratch
        settings.load_settings()
        assert_eq(settings.shape_check_method, method, "%s opens on its method" % method)
        assert_false(settings.shape_check_levels, "%s keeps its posterise off" % method)
        assert_eq(settings.shape_check_level_count, 4, "%s keeps its count of levels" % method)
        assert_eq(settings.shape_check_notan_values, 2, "%s: Notan's count of values at its default" % method)
        assert_almost_eq(settings.shape_check_notan_threshold, 0.5, 1e-6, "%s: and its threshold at the middle" % method)
        var uniforms: Dictionary = settings.shape_check_uniforms()
        settings.free()
        assert_eq(uniforms["shape_check_method"], numbers[method], "%s: the shader's number for it is the one before" % method)

        SaSettings.shape_check_method = method
        SaSettings.shape_check_levels = false
        var material := _canvas_over(_picture(SMALL)).material as ShaderMaterial
        assert_eq(material.get_shader_parameter("shape_check_method"), numbers[method], "%s: the material holds it" % method)
        assert_false(material.get_shader_parameter("shape_check_levels"), "%s: and its posterise switch" % method)
