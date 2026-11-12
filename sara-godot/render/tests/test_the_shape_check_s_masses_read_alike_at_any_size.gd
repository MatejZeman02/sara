## The Shape Check gets a method that keeps the shapes, beside
## Blocks, with its options in Preferences. It was asked for as "It
## should check that the shapes holds. So posterization? It should be
## resolution independent", then "make its options editable in the
## preferences. Don't throw away the current method".
##
## One picture, a dark mass beside a light one with a hard edge between them,
## both striped finer than the reach and shaded top to bottom, is drawn at two
## sizes through the canvas's own material under Masses and read back. The
## larger, brought down to the smaller's size, agrees with it within the bounds
## below, the stripes are gone, and the edge is within two texels of where it was
## at both sizes. A profile that held the old Shape check row of Blocks, Levels
## or Both opens on the view it showed, and Blocks still draws the flat squares
## it drew. The Display page's rows are `test_display_page.gd`'s, because a
## suite under `render` names nothing of `ui`.
extends "res://tests/test_framework.gd"

## The picture is composited, drawn through the canvas material and read back.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const AUTOLOAD := "res://core/settings/sa_settings.gd"

## The mode the shader branches on for the Shape Check.
const SHAPE_VIEW_MODE := 5

## The two widths the picture is drawn at, the second twice the first, and the
## height a share of the width, so both sizes are the same picture.
const SMALL := 256
const LARGE := 512
const HEIGHT_SHARE := 0.75

## Where the hard edge stands, a share of the width, and the two masses either
## side of it as the 8-bit sRGB numbers an import stores.
const EDGE := 0.4
const DARK := Color(0.2, 0.25, 0.4)
const LIGHT := Color(0.85, 0.75, 0.6)

## The detail Masses has to take away: vertical stripes, this many across the
## width and this far either side of the mass's own colour, and a shade from
## top to bottom that it has to keep.
const STRIPES := 32.0
const STRIPE_DEPTH := 0.08
const SHADE := 0.1

## The reach the case sets, three per cent of the long side, which is about the
## stripes' width and so reaches across one of them at either size.
const REACH := 0.03

## The bounds the two sizes are held to, on values from nought to one. The mean
## difference over every texel and channel under a hundredth, two and a half
## steps of an 8-bit channel, and all but one in a hundred within four
## hundredths. The one in a hundred is the column the edge falls in, where the
## larger picture brought down by two by two blends the two masses and the
## smaller one does not.
const MEAN_BOUND := 0.01
const MOST_BOUND := 0.04
const MOST_SHARE := 0.99

## How far the edge may move, in texels of the size it is read at.
const EDGE_TEXELS := 2.0

## How much of the stripes' swing may survive, as a share of the picture's own.
const STRIPES_LEFT := 0.5

var _registries: SaRegistries = null
var _easels: Array[SaEasel] = []
var _canvases: Array[SaCanvas] = []
var _kept := {}
static var scratch_path: String = SaDataRoot.path("test_an_old_shape_check_row.cfg")


func before_each() -> void:
    for key: String in SaSettings.shape_check_uniforms():
        _kept[key] = SaSettings.get(key)
    _kept["tonemap_highlights"] = SaSettings.tonemap_highlights
    SaSettings.tonemap_highlights = false
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


## The picture at *width*, every texel worked out from where it sits as a share
## of the picture, so the two sizes are one picture sampled twice.
static func _picture(width: int) -> Image:
    var height := roundi(width * HEIGHT_SHARE)
    var image := Image.create_empty(width, height, false, Image.FORMAT_RGB8)
    for y in height:
        for x in width:
            var u := (x + 0.5) / width
            var v := (y + 0.5) / height
            var mass := DARK if u < EDGE else LIGHT
            var stripe := STRIPE_DEPTH if fmod(u * STRIPES, 1.0) < 0.5 else -STRIPE_DEPTH
            var lift := stripe + SHADE * (v - 0.5)
            image.set_pixel(x, y, Color(mass.r + lift, mass.g + lift, mass.b + lift))
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


static func _lightness(color: Color) -> float:
    return (color.r + color.g + color.b) / 3.0


## The furthest any row's edge stands from where the picture put it, in texels:
## the first texel of each row past the middle of the two masses.
static func _edge_drift(image: Image) -> float:
    var middle := (_lightness(DARK) + _lightness(LIGHT)) / 2.0
    var wanted := EDGE * image.get_width()
    var furthest := 0.0
    for y in image.get_height():
        var x := 0
        while x < image.get_width() - 1 and _lightness(image.get_pixel(x, y)) < middle:
            x += 1
        furthest = maxf(furthest, absf(x - wanted))
    return furthest


## How far the lightness swings along the middle row inside the light mass, the
## spread of its values, which is the stripes and nothing else there.
static func _swing(image: Image) -> float:
    var y := image.get_height() >> 1
    var values: Array[float] = []
    for x in range(roundi(image.get_width() * 0.55), roundi(image.get_width() * 0.95)):
        values.append(_lightness(image.get_pixel(x, y)))
    var mean := 0.0
    for value: float in values:
        mean += value
    mean /= values.size()
    var spread := 0.0
    for value: float in values:
        spread += (value - mean) * (value - mean)
    return sqrt(spread / values.size())


func test_masses_read_alike_at_two_sizes_and_keep_the_edge_where_it_was() -> void:
    SaSettings.shape_check_method = SaSettings.SHAPE_MASSES
    SaSettings.shape_check_levels = false
    SaSettings.shape_check_reach = REACH
    var small_picture := _picture(SMALL)
    var small := _frame(_canvas_over(small_picture))
    var large := _frame(_canvas_over(_picture(LARGE)))
    var brought := _halved(large)
    assert_eq(brought.get_size(), small.get_size(), "The larger picture brought down is the smaller one's size")

    var differences: Array[float] = []
    var total := 0.0
    for y in small.get_height():
        for x in small.get_width():
            var a := small.get_pixel(x, y)
            var b := brought.get_pixel(x, y)
            for difference: float in [absf(a.r - b.r), absf(a.g - b.g), absf(a.b - b.b)]:
                differences.append(difference)
                total += difference
    differences.sort()
    var mean := total / differences.size()
    var most := differences[floori(differences.size() * MOST_SHARE)]
    assert_true(mean < MEAN_BOUND, "The two sizes agree on the mean, %.4f under %.2f" % [mean, MEAN_BOUND])
    assert_true(most < MOST_BOUND, "and all but one in a hundred within %.2f, the worst of them %.4f" % [MOST_BOUND, most])

    var drift_small := _edge_drift(small)
    var drift_large := _edge_drift(large)
    assert_true(drift_small <= EDGE_TEXELS, "The edge stays put at %d wide, off by %.1f texels" % [SMALL, drift_small])
    assert_true(drift_large <= EDGE_TEXELS, "and at %d wide, off by %.1f texels" % [LARGE, drift_large])

    small_picture.convert(Image.FORMAT_RGBF)
    var before := _swing(small_picture)
    var after := _swing(small)
    assert_true(before > STRIPE_DEPTH * 0.9, "The picture's stripes swing by %.3f" % before)
    assert_true(after < before * STRIPES_LEFT, "and Masses takes them away, %.3f of %.3f left" % [after, before])


## The cost the ask set: a fixed count of taps whatever the canvas measures and
## whatever the zoom. The loop's bounds are constants of the shader and the
## reach only spreads them, which is read off the file rather than timed.
func test_masses_take_a_fixed_count_of_taps() -> void:
    var text := FileAccess.get_file_as_string("res://shaders/canvas/tonemap.gdshader")
    var start := text.find("shape_check_method == SHAPE_CHECK_MASSES")
    assert_true(start >= 0, "The shader has a Masses branch")
    var branch := text.substr(start, text.find("} else if (taps > 1)", start) - start)
    assert_eq(branch.count("textureLod(TEXTURE"), 1, "one tap in the loop")
    assert_true(branch.contains("j <= SHAPE_CHECK_MASS_STEPS"), "its rows bounded by a constant")
    assert_true(branch.contains("i <= SHAPE_CHECK_MASS_STEPS"), "and its columns too, so the reach only spreads them")


## A profile from before the masses method held the Shape check row as Blocks, Levels or
## Both. Each opens on the method and the switch that draw what it drew, the
## old key is gone from the file the load saves, and the count across is the
## thirty-two the shader held.
func test_a_profile_holding_the_old_row_opens_on_the_view_it_showed() -> void:
    var cases := {
        "blocks": [SaSettings.SHAPE_BLOCKS, false],
        "levels": [SaSettings.SHAPE_NONE, true],
        "both": [SaSettings.SHAPE_BLOCKS, true],
    }
    var scratch := ProjectSettings.globalize_path(scratch_path)
    for old: String in cases:
        var profile := ConfigFile.new()
        profile.set_value("meta", "version", 20)
        profile.set_value("ui", "shape_check", old)
        assert_eq(profile.save(scratch), OK, "%s: the old profile is on disk" % old)
        var settings: Node = load(AUTOLOAD).new()
        settings.settings_path = scratch
        settings.load_settings()
        var want: Array = cases[old]
        assert_eq(settings.shape_check_method, want[0], "%s opens on the method %s" % [old, want[0]])
        assert_eq(settings.shape_check_levels, want[1], "%s opens with the posterise %s" % [old, "on" if want[1] else "off"])
        assert_eq(settings.shape_check_across, 32, "%s keeps the thirty-two blocks the shader held" % old)
        var method: int = settings.shape_check_uniforms()["shape_check_method"]
        settings.free()
        var written := ConfigFile.new()
        assert_eq(written.load(scratch), OK, "%s: the saved profile parses" % old)
        assert_false(written.has_section_key("ui", "shape_check"), "%s: the old key is gone from the file" % old)

        SaSettings.shape_check_method = want[0]
        SaSettings.shape_check_levels = want[1]
        var canvas := _canvas_over(_picture(SMALL))
        var material := canvas.material as ShaderMaterial
        assert_eq(material.get_shader_parameter("shape_check_method"), method, "%s: the material holds its method" % old)
        assert_eq(material.get_shader_parameter("shape_check_levels"), want[1], "%s: and its posterise switch" % old)
        var blocks: bool = want[0] == SaSettings.SHAPE_BLOCKS
        assert_eq(method == 0, blocks, "%s: Blocks runs where it ran, the shader's first method" % old)

    var bare := ConfigFile.new()
    bare.set_value("meta", "version", 20)
    assert_eq(bare.save(scratch), OK, "a profile with no row at all is on disk")
    var fresh: Node = load(AUTOLOAD).new()
    fresh.settings_path = scratch
    fresh.load_settings()
    assert_eq(fresh.shape_check_method, SaSettings.SHAPE_BLOCKS, "and it opens on Blocks")
    assert_true(fresh.shape_check_levels, "posterised, the Both its missing row read as")
    fresh.free()


## Blocks is the method that keeps the shapes: the long side cut into the
## count across, each block flat, so the frame is squares of the side it was.
func test_blocks_still_draws_flat_squares_of_the_count_across() -> void:
    SaSettings.shape_check_method = SaSettings.SHAPE_BLOCKS
    SaSettings.shape_check_levels = false
    for across: int in [32, 16]:
        SaSettings.shape_check_across = across
        var frame := _frame(_canvas_over(_picture(SMALL)))
        var side := floori(float(SMALL) / across)
        var uneven := 0
        var different := 0
        for y in frame.get_height():
            for x in frame.get_width():
                var corner := frame.get_pixel(x - x % side, y - y % side)
                if not frame.get_pixel(x, y).is_equal_approx(corner):
                    uneven += 1
                if x >= side and not frame.get_pixel(x, y).is_equal_approx(frame.get_pixel(x - side, y)):
                    different += 1
        assert_eq(uneven, 0, "%d across: every block of %d texels is flat" % [across, side])
        assert_true(different > 0, "%d across: and the blocks are not all one colour" % across)
