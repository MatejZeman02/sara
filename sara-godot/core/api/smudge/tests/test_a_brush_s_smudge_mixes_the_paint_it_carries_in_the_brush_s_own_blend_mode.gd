## A brush's smudge mixes the paint it carries in the brush's own blend mode:
## a Normal smear lays what it always laid, and a smear in another mode mixes
## the carry the way that mode composites, in the stamp and the noise brush
## alike.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Red into blue.** The layer is red in its first chunk and blue in its
## second, and each stroke drags the red over the seam with a light pickup and no
## colour rate, so the smear past the seam is the carry
## alone. The pixels are read back here, which a test may do and a brush never
## does.
##
## **The fixture mode** is the built-in Darken kernel registered under an id of
## its own, so its mix is known: a carry darkened by min against the paint it
## picks up. Red's carry has no blue, and the blue it meets past the seam can
## only keep it at none, where the straight line takes the blue in. A white
## brush colour keeps the carry's meeting with the brush out of the reading,
## since white's min with any colour is that colour.
##
## **What the base laid.** The Normal rows below are what the same strokes
## laid with the code before the mix existed, read on the reference GPU. Normal records no mix, so they hold to float rounding.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const CANVAS := Vector2i(512, 256)
const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
const WHITE := Color(1.0, 1.0, 1.0, 1.0)

## The gradient map's ramp, two greens with no red in them, so a meeting of
## the red carry with the ramp in the fixture mode keeps the red at none,
## where the straight line takes the carry's red in.
const LIGHT_GREEN := Color(0.0, 1.0, 0.0, 1.0)
const DARK_GREEN := Color(0.0, 0.4, 0.0, 1.0)
const YELLOW := Color(1.0, 1.0, 0.0, 1.0)

## The colour rate of the gradient map's strokes, so the carry's share of each
## dab is a half and the ramp shows through the other half.
const RAMPED_RATE: float = 0.5

## The gradient map tip's picture, a black to white run across its side, so
## the ramp's colour changes across every dab. Never anything a painter owns.
static var picture_path: String = SaDataRoot.path("test_ramp_tip.png")
const PICTURE_SIDE: int = 32

## The row the strokes run along and how far each runs either side of the
## seam.
const ROW: float = 40.0
const RUN: float = 40.0
const STEPS: int = 20

## How much of the paint under a dab the carry takes, low enough that the red
## lasts a while into the blue.
const PICKUP: float = 0.2

## The pixels read along the smear, from the seam out, every few pixels.
const READ_FROM: int = 2
const READ_STEP: int = 3
const READS: int = 12

## The fixture mode, Darken's kernel under an id no module uses.
const DARKER: StringName = &"smudge_fixture_darker"

## What the base laid at the reads, red then blue, for each engine.
const BASE_STAMP: Array = [
    0.512,
    0.488,
    0.262343,
    0.737657,
    0.135099,
    0.864901,
    0.070332,
    0.929668,
    0.04398,
    0.95602,
    0.022518,
    0.977482,
    0.011563,
    0.988437,
    0.005981,
    0.994019,
    0.003778,
    0.996222,
    0.001934,
    0.998066,
    0.000991,
    0.999009,
    0.00051,
    0.99949,
]
const BASE_NOISE: Array = [
    0.459776,
    0.540224,
    0.367821,
    0.632179,
    0.294257,
    0.705743,
    0.294257,
    0.705743,
    0.235405,
    0.764595,
    0.188324,
    0.811676,
    0.150659,
    0.849341,
    0.150659,
    0.849341,
    0.120528,
    0.879472,
    0.096422,
    0.903578,
    0.096422,
    0.903578,
    0.096422,
    0.903578,
]

## What the base laid at the reads of a gradient map stroke in Normal, red,
## green and blue, over blue at the colour rate [constant RAMPED_RATE].
const BASE_RAMPED: Array = [
    0.256003,
    0.466386,
    0.243999,
    0.131076,
    0.479229,
    0.368928,
    0.067114,
    0.472524,
    0.43289,
    0.034363,
    0.481897,
    0.465639,
    0.021993,
    0.421268,
    0.478009,
    0.011262,
    0.472798,
    0.48874,
    0.005768,
    0.485635,
    0.494234,
    0.002955,
    0.478938,
    0.497047,
    0.001892,
    0.4165,
    0.49811,
    0.00097,
    0.466386,
    0.499032,
    0.000499,
    0.479189,
    0.499504,
    0.000259,
    0.472511,
    0.499746,
]

var _surface: SaSurface = null
var _registries: SaRegistries = null


func after_each() -> void:
    if FileAccess.file_exists(picture_path):
        DirAccess.remove_absolute(picture_path)
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = null
    _registries = null


## A fresh surface red to the seam and blue past it, composited, with a
## compositor that knows the fixture mode.
func _painted(past: Color = BLUE) -> void:
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    _registries = Fixtures.make_registries(_surface)
    var darker := SaBlendModeDescriptor.create(DARKER, "darken")
    assert_true(_registries.blend_modes.register(darker), "The fixture mode registers")
    _surface.easel.compositor.set_registry(_registries.blend_modes)
    var document := _surface.easel.document
    document.active_layer.get_or_create_chunk(Vector2i(0, 0)).clear(RED)
    document.active_layer.get_or_create_chunk(Vector2i(1, 0)).clear(past)
    document.invalidate_chunks([Vector2i(0, 0), Vector2i(1, 0)])
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()


func _seam() -> float:
    return float(_surface.easel.document.active_layer.get_or_create_chunk(Vector2i.ZERO).pixel_size())


## A stamp stroke over the seam in *mode*, smudging, the reads along it and
## the carry it held before the lift let it go. *ramped* paints it as a
## gradient map through the two greens, with a picture tip whose lightness
## runs across it.
func _stamp(mode: StringName, ramped: bool = false, past: Color = BLUE, rate: float = 0.0) -> Array:
    _painted(past)
    var brush := StateBrushScript.new()
    brush.surface = _surface
    brush.settings.color = WHITE
    if ramped:
        brush.settings.tip_mode = SaStampBrushSettings.TipMode.GRADIENT_MAP
        brush.settings.gradient = SaColorRamp.from_pair(LIGHT_GREEN, DARK_GREEN).to_array()
        brush.settings.tip = _picture_tip()
    brush.settings.blend_mode = mode
    brush.settings.radius = 6.0 / float(CANVAS.x)
    # The numbers the base laid were taken at the spacing a brush had before
    # the default became 0.05, and a closer spacing is a different smear.
    brush.settings.spacing = 0.18
    brush.settings.hardness = GammaFloat.new(1.0, 1.0)
    brush.settings.opacity_by_pressure = false
    brush.settings.smudge_pickup_option.enabled = true
    brush.settings.smudge_pickup_option.strength = PICKUP
    brush.settings.smudge_color_rate_option.enabled = rate > 0.0
    brush.settings.smudge_color_rate_option.strength = rate
    brush.settings.smudge_sample_merged = false
    var view := _surface.view
    for i in range(STEPS + 1):
        view.mouse_position = _along(float(i) / float(STEPS))
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
    var held: SaSmudgeReservoir = brush._smudge.carry
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    brush.handle_input(release)
    return [_reads(), held, _colours()]


## The same stroke with the noise brush, and the reads along it.
func _noise(mode: StringName) -> Array:
    _painted()
    var brush := StateNoiseBrushScript.new()
    brush.surface = _surface
    brush.stroke_seed = 7
    brush.settings.color = WHITE
    brush.settings.blend_mode = mode
    brush.settings.opacity = 1.0
    brush.settings.hardness = 1.0
    brush.settings.strength = 0.0
    brush.settings.radius = 6.0 / 256.0
    brush.settings.smudge_pickup_option.enabled = true
    brush.settings.smudge_pickup_option.strength = PICKUP
    brush.settings.smudge_color_rate_option.enabled = false
    brush.settings.smudge_sample_merged = false
    brush.begin_stroke(_along(0.0), 1.0)
    for step in range(1, STEPS + 1):
        brush.add_sample(_along(step / float(STEPS)), 1.0)
    var held: SaSmudgeReservoir = brush.smudge
    brush.end_stroke()
    return [_reads(), held]


func _along(t: float) -> Vector2:
    return Vector2(_seam() - RUN, ROW).lerp(Vector2(_seam() + RUN, ROW), t)


## Red and blue at each read past the seam, in one flat list.
func _reads() -> Array:
    var layer := _surface.easel.document.active_layer
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(layer.get_field(Vector2i(1, 0)))
    var reads: Array = []
    for i in range(READS):
        var pixel := image.get_pixel(READ_FROM + READ_STEP * i, int(ROW))
        reads.append(snappedf(pixel.r, 1e-6))
        reads.append(snappedf(pixel.b, 1e-6))
    return reads


## Each read past the seam as a colour.
func _colours() -> Array[Color]:
    var layer := _surface.easel.document.active_layer
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(layer.get_field(Vector2i(1, 0)))
    var colours: Array[Color] = []
    for i in range(READS):
        colours.append(image.get_pixel(READ_FROM + READ_STEP * i, int(ROW)))
    return colours


func _same(reads: Array, base: Array, engine: String) -> void:
    print("%s Normal smear %s" % [engine, reads])
    assert_eq(reads.size(), base.size(), "The %s's Normal smear is read where the base was" % engine)
    var worst := 0.0
    for i in range(mini(reads.size(), base.size())):
        worst = maxf(worst, absf(float(reads[i]) - float(base[i])))
    assert_true(worst <= 1e-5, "and lays what the base laid, the largest difference %.7f" % worst)


func test_a_normal_stamp_smear_lays_what_the_base_laid() -> void:
    var painted := _stamp(SaLayer.BLEND_MODE.NORMAL)
    var reservoir := painted[1] as SaSmudgeReservoir
    assert_not_null(reservoir, "The stamp stroke made its carry")
    assert_true(reservoir == null or reservoir.mixed == null, "and in Normal no mix")
    _same(painted[0], BASE_STAMP, "stamp")


func test_a_normal_noise_smear_lays_what_the_base_laid() -> void:
    var painted := _noise(SaLayer.BLEND_MODE.NORMAL)
    var reservoir := painted[1] as SaSmudgeReservoir
    assert_not_null(reservoir, "The noise stroke made its carry")
    assert_true(reservoir == null or reservoir.mixed == null, "and in Normal no mix")
    _same(painted[0], BASE_NOISE, "noise brush")


## Past the seam the straight line takes the blue in and the darker mix
## cannot, so the fixture's smear holds no blue where Normal's holds plenty,
## and its red is no more than Normal's.
func _darker_than_the_line(engine: String, normal: Array, darker: Array) -> void:
    var line_blue := 0.0
    var mode_blue := 0.0
    for i in range(READS):
        line_blue = maxf(line_blue, float(normal[2 * i + 1]))
        mode_blue = maxf(mode_blue, float(darker[2 * i + 1]))
        var redder := float(darker[2 * i]) - float(normal[2 * i])
        assert_true(redder <= 1e-4, "The %s's darker smear has no more red than the line's at read %d" % [engine, i])
    assert_true(line_blue > 0.1, "The %s's straight line takes the blue in, %.3f at most" % [engine, line_blue])
    assert_true(mode_blue < 0.01, "where its darker mix keeps the carry's blue at none, %.4f at most" % mode_blue)
    var red := 0.0
    for i in range(READS):
        red = maxf(red, float(darker[2 * i]))
    assert_true(red < 0.01, "and darkens what it lays onto the blue to black, red %.4f at most" % red)


func test_a_stamp_smear_in_the_fixture_mode_mixes_as_the_mode_does() -> void:
    var normal: Array = _stamp(SaLayer.BLEND_MODE.NORMAL)[0]
    var painted := _stamp(DARKER)
    var reservoir := painted[1] as SaSmudgeReservoir
    assert_true(reservoir != null and reservoir.mixed != null, "The stamp smear in the fixture mode makes its mix")
    _darker_than_the_line("stamp", normal, painted[0])


func test_a_noise_smear_in_the_fixture_mode_mixes_as_the_mode_does() -> void:
    var normal: Array = _noise(SaLayer.BLEND_MODE.NORMAL)[0]
    var painted := _noise(DARKER)
    var reservoir := painted[1] as SaSmudgeReservoir
    assert_true(reservoir != null and reservoir.mixed != null, "The noise smear in the fixture mode makes its mix")
    _darker_than_the_line("noise brush", normal, painted[0])


## A picture tip whose lightness runs from black to white across it, hard to
## its edge.
static func _picture_tip() -> Resource:
    var image := Image.create_empty(PICTURE_SIDE, PICTURE_SIDE, false, Image.FORMAT_RGBA8)
    for x in PICTURE_SIDE:
        var v := float(x) / float(PICTURE_SIDE - 1)
        image.fill_rect(Rect2i(x, 0, 1, PICTURE_SIDE), Color(v, v, v, 1.0))
    # One transparent tinted corner, because a picture whose every texel is grey
    # reads as a mask with a mid grey lightness throughout.
    image.set_pixel(0, 0, Color(1.0, 0.0, 0.0, 0.0))
    image.save_png(picture_path)
    var tip: Resource = SaBrushTipScript.new()
    tip.diameter = 12.0
    tip.horizontal_fade = 1.0
    tip.vertical_fade = 1.0
    tip.generator = SaDabGeometry.Generator.IMAGE
    tip.image_path = picture_path
    return tip


func test_a_normal_gradient_map_smear_lays_what_the_base_laid() -> void:
    var painted := _stamp(SaLayer.BLEND_MODE.NORMAL, true, BLUE, RAMPED_RATE)
    var reservoir := painted[1] as SaSmudgeReservoir
    assert_true(reservoir != null and reservoir.mixed == null, "The gradient map's Normal smear makes no mix")
    var reads: Array = []
    for colour: Color in painted[2]:
        reads.append_array([snappedf(colour.r, 1e-6), snappedf(colour.g, 1e-6), snappedf(colour.b, 1e-6)])
    _same(reads, BASE_RAMPED, "gradient map stamp")


## In the fixture mode the red carry meets the green ramp by min, which has no
## red in it, so the smear lays no red, where the straight line lays the
## carry's red at its share. Over yellow, whose min with any of the ramp's
## greens is that green, the layer then shows the paint the dab laid.
func test_a_gradient_map_smear_in_the_fixture_mode_meets_its_ramp_as_the_mode_does() -> void:
    var normal: Array = _stamp(SaLayer.BLEND_MODE.NORMAL, true, YELLOW, RAMPED_RATE)[2]
    var painted := _stamp(DARKER, true, YELLOW, RAMPED_RATE)
    var reservoir := painted[1] as SaSmudgeReservoir
    assert_true(reservoir != null and reservoir.mixed != null, "The gradient map's smear in the fixture mode makes its mix")
    var darker: Array = painted[2]
    print("gradient map Normal smear %s" % [normal])
    print("gradient map fixture smear %s" % [darker])
    var line_red := 0.0
    var mode_red := 0.0
    var greens: Array[float] = []
    for i in range(READS):
        line_red = maxf(line_red, (normal[i] as Color).r)
        mode_red = maxf(mode_red, (darker[i] as Color).r)
        greens.append((darker[i] as Color).g)
    assert_true(line_red > 0.1, "The straight line lays the carry's red at its share, %.3f at most" % line_red)
    assert_true(mode_red < 0.01, "where the mode's meeting with the ramp keeps it at none, %.4f at most" % mode_red)
    # The carry stays red, since red's min with yellow is red, so the mode's
    # meeting lays the ramp's green at the share the carry leaves it and min's
    # nought at the carry's, which is the ramp's darkest green at a half at the
    # least.
    var least := (1.0 - RAMPED_RATE) * DARK_GREEN.g
    assert_true(greens.min() >= least - 0.01, "and lays the ramp's green at its share, %.3f at least" % greens.min())
    assert_true(greens.max() <= LIGHT_GREEN.g + 0.01, "and no more than its lightest, %.3f at most" % greens.max())
    assert_true(greens.max() - greens.min() > 0.02, "and the ramp's green changes across the tip as the map does")
