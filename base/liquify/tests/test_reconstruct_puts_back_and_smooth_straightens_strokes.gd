## Liquify's Reconstruct puts the
## picture back, and Smooth straightens wobbly strokes as a stabiliser would.
##
## Every case paints chunk (0, 0) and holds the tool over it for a second of
## frames, through the tool the way a held button does. Reconstruct is read
## texel by texel against black and white stripes as they were before a push.
## Smooth is read column by column over a dark stroke 6 pixels wide whose path
## wobbles 8 pixels either side of a straight line over a period of 40: where
## its middle is, how wide it is across its own direction, and how dark its
## darkest texel is, which a blur would lighten.
extends "res://tests/test_framework.gd"

## Chunks are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateScript = preload("res://modules/sara-base-modules/base/liquify/state_liquify.gd")

const CANVAS := Vector2i(1024, 512)
## How wide a stripe is, in texels, black then white.
const STRIPE: int = 4
const CENTRE := Vector2(128.0, 128.0)
## A second of frames, which is what the row's Done line holds for.
const FRAMES: int = 60
## The push the reconstruct takes back, along the row through the centre.
const PUSH_FROM := Vector2(118.0, 128.0)
const PUSH_TO := Vector2(128.0, 128.0)
const PUSH_SIZE: float = 60.0
## Wide enough that everything the push or the smooth moved lies in its flat
## core.
const RECONSTRUCT_SIZE: float = 240.0
## After a second at full strength a push keeps `exp(-RECONSTRUCT_RATE)` of its
## offset, a fiftieth, so a ten texel push is left at a fifth of a texel, and a
## texel at a stripe's edge reads that share of the step between black and
## white.
const PUT_BACK: float = 0.25

## The wobbly stroke: its half width, how far its path swings either side of
## the row through the centre and over what period, and the columns it runs
## between, far enough past the brush that its ends never move.
const HALF_WIDTH: float = 3.0
const SWING: float = 8.0
const PERIOD: float = 40.0
const STROKE_FROM: float = 16.0
const STROKE_TO: float = 240.0
const INK := Color(0.12, 0.09, 0.07, 1.0)
## Oklab's lightness of the stroke and of the ground under it, for the case
## painted on an opaque ground.
const INK_LIGHTNESS: float = 0.3
const GROUND_LIGHTNESS: float = 0.95
## The smooth's brush, and the columns read, one period inside its flat core.
const SMOOTH_SIZE: float = 96.0
const READ_HALF: int = 20
## How far the stroke's width may move, as a share of what it was, and how far
## its darkest texel may be from the ink, which a blur would lift towards the
## ground.
const WIDTH_SHARE: float = 0.15
const DARKEST: float = 0.02
## How far a flat colour may move under a smooth.
const FLAT: float = 0.0001

var _surface: SaSurface = null
var _machine: ToolMachine = null


func after_each() -> void:
    if _surface != null:
        Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## A fresh document in *space* whose active layer holds chunk (0, 0) painted
## with *paint*, a callable of a texel answering its stored colour, and the
## liquify tool in hand at full strength.
func _open(space: SaColorSpace, paint: Callable) -> Variant:
    _surface = Fixtures.make_surface(CANVAS)
    _machine = Fixtures.make_bound_machine(_surface)
    var doc := _surface.get_document()
    doc.color_space = space
    var layer := SaLayerOps.new(doc).add(&"", null, 1.0)
    doc.active_layer = layer
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    var edge := chunk.pixel_size()
    var texture := chunk.albedo()
    var image := Image.create_empty(edge, edge, false, _image_format(texture))
    for y in edge:
        for x in edge:
            image.set_pixel(x, y, paint.call(Vector2i(x, y)))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    layer.mark_unresolved(Vector2i.ZERO)
    doc.invalidate_chunks([Vector2i.ZERO])
    _machine.set_active_tool(&"liquify")
    var tool: Variant = _machine.active_tool
    tool.settings.strength = 1.0
    return tool


## Vertical stripes, black then white, as sRGB stores them.
func _stripes() -> Variant:
    var white := Color(1.0, 1.0, 1.0, 1.0)
    return _open(
        SaColorSpace.srgb(),
        func(at: Vector2i) -> Color: return Color(0.0, 0.0, 0.0, 1.0) if posmod(floori(float(at.x) / STRIPE), 2) == 0 else white
    )


## The row the stroke's path is on at column *x*, swinging by *swing*.
static func _path(x: float, swing: float) -> float:
    return CENTRE.y + swing * sin(TAU * (x - CENTRE.x) / PERIOD)


## How much of the texel at *at* a round brush `2 * HALF_WIDTH` wide covers,
## drawn along the path swinging by *swing*: its distance to the path, found
## coarse and then fine, against the half width, with a texel of edge.
static func _coverage(at: Vector2i, swing: float) -> float:
    var middle := Vector2(at) + Vector2(0.5, 0.5)
    if absf(middle.y - CENTRE.y) > swing + HALF_WIDTH + 2.0:
        return 0.0
    var best := INF
    var best_x := middle.x
    var x := maxf(STROKE_FROM, middle.x - 12.0)
    while x <= minf(STROKE_TO, middle.x + 12.0):
        var near := middle.distance_to(Vector2(x, _path(x, swing)))
        if near < best:
            best = near
            best_x = x
        x += 0.5
    x = maxf(STROKE_FROM, best_x - 0.5)
    while x <= minf(STROKE_TO, best_x + 0.5):
        best = minf(best, middle.distance_to(Vector2(x, _path(x, swing))))
        x += 0.02
    return clampf(HALF_WIDTH + 0.5 - best, 0.0, 1.0)


## The stroke swinging by *swing* in ink on a clear layer of an sRGB document.
func _stroke(swing: float) -> Variant:
    return _open(
        SaColorSpace.srgb(),
        func(at: Vector2i) -> Color:
            var covered := _coverage(at, swing)
            return Color(INK.r, INK.g, INK.b, covered) if covered > 0.0 else Color(0.0, 0.0, 0.0, 0.0)
    )


## The stroke swinging by *swing* on an opaque light ground of an Oklab
## document, so it is told from the ground by its lightness alone.
func _stroke_on_ground() -> Variant:
    return _open(
        SaColorSpace.oklab(),
        func(at: Vector2i) -> Color: return Color(lerpf(GROUND_LIGHTNESS, INK_LIGHTNESS, _coverage(at, SWING)), 0.0, 0.0, 1.0)
    )


func _read() -> Image:
    var texture := _surface.get_document().active_layer.chunks[Vector2i.ZERO].albedo()
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return Image.create_from_data(texture.size.x, texture.size.y, false, _image_format(texture), bytes)


## How much of the stroke a stored *texel* holds: its coverage on a clear
## layer, or on the ground how far it is from the ground's lightness to the
## ink's.
static func _ink(texel: Color, on_ground: bool) -> float:
    if on_ground:
        return (GROUND_LIGHTNESS - texel.r) / (GROUND_LIGHTNESS - INK_LIGHTNESS)
    return texel.a


## How far a stored *texel* is from the ink at its darkest: on a clear layer
## its colour laid over white against the ink, on the ground its lightness
## against the ink's.
static func _from_ink(texel: Color, on_ground: bool) -> float:
    if on_ground:
        return absf(texel.r - INK_LIGHTNESS)
    var far := 0.0
    for channel in 3:
        far = maxf(far, absf(texel[channel] * texel.a + (1.0 - texel.a) - INK[channel]))
    return far


## Column by column over the read columns, the stroke's middle, its width
## across its own direction, and how far its darkest texel is from the ink.
static func _columns(image: Image, on_ground: bool) -> Dictionary:
    var middles: Array[float] = []
    var sums: Array[float] = []
    var darkest: Array[float] = []
    for x in range(int(CENTRE.x) - READ_HALF - 1, int(CENTRE.x) + READ_HALF + 1):
        var weight := 0.0
        var moment := 0.0
        var most := -INF
        var nearest := INF
        for y in range(int(CENTRE.y) - 24, int(CENTRE.y) + 24):
            var texel := image.get_pixel(x, y)
            var held := _ink(texel, on_ground)
            weight += held
            moment += held * (y + 0.5)
            if held > most:
                most = held
                nearest = _from_ink(texel, on_ground)
        middles.append(moment / weight if weight > 0.0 else -1.0)
        sums.append(weight)
        darkest.append(nearest)
    var widths: Array[float] = []
    for index in range(1, middles.size() - 1):
        # The coverage of a column times the cosine of the stroke's slope there
        # is its width across itself, which a straightening keeps where the
        # column's own count would not.
        var slope := (middles[index + 1] - middles[index - 1]) * 0.5
        widths.append(sums[index] / sqrt(1.0 + slope * slope))
    var mean := 0.0
    for index in range(1, middles.size() - 1):
        mean += middles[index]
    mean /= float(middles.size() - 2)
    var swing := 0.0
    for index in range(1, middles.size() - 1):
        swing = maxf(swing, absf(middles[index] - mean))
    return {
        "middles": middles.slice(1, middles.size() - 1),
        "widths": widths,
        "darkest": darkest.slice(1, darkest.size() - 1),
        "swing": swing
    }


## The largest difference between *a* and *b* in any channel of the colour
## premultiplied, or in alpha, which is what the picture shows. The layer
## stores colour straight, so a texel an edge moves a thousandth into holds the
## whole of the ink's colour and would read as moved by all of it. In light,
## decoded by the sRGB curve every painting here is in, because the draw blends
## in light: a texel a fifth of a texel's offset reaches holds a fifth of the
## step's light, which the curve stores as nearly half of it.
static func _largest_difference(a: Image, b: Image) -> float:
    var largest := 0.0
    for y in a.get_height():
        for x in a.get_width():
            var one := a.get_pixel(x, y)
            var other := b.get_pixel(x, y)
            for channel in 3:
                largest = maxf(largest, absf(_light(one[channel]) * one.a - _light(other[channel]) * other.a))
            largest = maxf(largest, absf(one.a - other.a))
    return largest


## *stored*, an sRGB encoded channel, as linear light.
static func _light(stored: float) -> float:
    return stored / 12.92 if stored < 0.04045 else pow((stored + 0.055) / 1.055, 2.4)


## The tool held at *at* for a second of frames, the way `tick` holds it.
static func _hold(tool: Variant, at: Vector2) -> void:
    tool.press(at)
    for frame in FRAMES:
        tool.hold(1.0 / FRAMES)
    tool.release()


func test_a_held_reconstruct_puts_pushed_stripes_back() -> void:
    var tool: Variant = _stripes()
    var before := _read()
    tool.settings.mode = StateScript.PUSH
    tool.settings.size = PUSH_SIZE
    tool.press(PUSH_FROM)
    tool.drag_to(PUSH_TO)
    tool.release()
    var pushed := _largest_difference(before, _read())
    assert_true(pushed > 0.9, "The push moved the stripes, black where white was: %f" % pushed)

    tool.settings.mode = StateScript.RECONSTRUCT
    tool.settings.size = RECONSTRUCT_SIZE
    _hold(tool, (PUSH_FROM + PUSH_TO) * 0.5)
    var left := _largest_difference(before, _read())
    assert_true(left < PUT_BACK, "A second of Reconstruct puts every texel back within %f: %f" % [PUT_BACK, left])
    assert_true(tool.commit_session(), "The push and the reconstruct are one session")


func test_a_reconstruct_takes_back_a_push_of_one_offset() -> void:
    # Every texel of the brush's core pushed by the same ten: the push the old
    # reconstruct, a relaxing towards the neighbours' mean, left as it was.
    var tool: Variant = _stripes()
    var before := _read()
    tool.settings.mode = StateScript.PUSH
    tool.settings.size = RECONSTRUCT_SIZE
    tool.press(PUSH_FROM)
    tool.drag_to(PUSH_TO)
    tool.release()
    var texel := Vector2i(CENTRE)
    var pushed := before.get_pixelv(texel).r != _read().get_pixelv(texel).r
    assert_true(pushed, "The push moved the stripe under the centre")
    tool.settings.mode = StateScript.RECONSTRUCT
    _hold(tool, CENTRE)
    var core_left := 0.0
    var after := _read()
    for y in range(int(CENTRE.y) - 20, int(CENTRE.y) + 20):
        for x in range(int(CENTRE.x) - 20, int(CENTRE.x) + 20):
            core_left = maxf(core_left, absf(_light(after.get_pixel(x, y).r) - _light(before.get_pixel(x, y).r)))
    assert_true(core_left < PUT_BACK, "The core reads the stripes again within %f: %f" % [PUT_BACK, core_left])


## A second of Smooth over the wobbly stroke *tool* holds, read column by
## column against the stroke before it, in *name*. Answers the columns after.
func _straightens(tool: Variant, on_ground: bool, name: String) -> Dictionary:
    var before := _columns(_read(), on_ground)
    assert_true(before.swing > SWING - 1.0, "In %s the stroke swings %f either side before" % [name, before.swing])
    tool.settings.mode = StateScript.SMOOTH
    tool.settings.size = SMOOTH_SIZE
    _hold(tool, CENTRE)
    var after := _columns(_read(), on_ground)
    assert_true(
        after.swing < before.swing * 0.5,
        (
            "In %s a second of Smooth takes the swing of the stroke's middle under half: %f from %f"
            % [name, after.swing, before.swing]
        )
    )
    var widest := 0.0
    var darkest := 0.0
    for index in (before.widths as Array).size():
        var was: float = before.widths[index]
        widest = maxf(widest, absf(float(after.widths[index]) - was) / was)
        darkest = maxf(darkest, float(after.darkest[index]))
    assert_true(
        widest < WIDTH_SHARE,
        (
            "In %s every column keeps the stroke's width within %d %%: %.1f %% at most"
            % [name, roundi(WIDTH_SHARE * 100.0), widest * 100.0]
        )
    )
    assert_true(
        darkest < DARKEST, "In %s every column's darkest texel is the ink within %f, so no blur: %f" % [name, DARKEST, darkest]
    )
    return after


func test_a_held_smooth_straightens_a_wobbly_stroke() -> void:
    var tool: Variant = _stroke(SWING)
    _straightens(tool, false, "a clear layer")
    assert_true(tool.commit_session(), "The smooth is one session")


func test_a_held_smooth_straightens_a_wobbly_stroke_told_by_lightness_alone() -> void:
    _straightens(_stroke_on_ground(), true, "Oklab on an opaque ground")


func test_a_reconstruct_after_the_smooth_brings_the_wobble_back() -> void:
    var tool: Variant = _stroke(SWING)
    var before := _columns(_read(), false)
    _straightens(tool, false, "a clear layer")
    tool.settings.mode = StateScript.RECONSTRUCT
    tool.settings.size = RECONSTRUCT_SIZE
    _hold(tool, CENTRE)
    var back := _columns(_read(), false)
    var furthest := 0.0
    for index in (before.middles as Array).size():
        furthest = maxf(furthest, absf(float(back.middles[index]) - float(before.middles[index])))
    assert_true(furthest < 0.25, "A second of Reconstruct puts every column's middle back within a quarter texel: %f" % furthest)
    assert_true(tool.commit_session(), "The smooth and the reconstruct are one session")


func test_a_smooth_leaves_a_straight_stroke_where_it_is() -> void:
    var tool: Variant = _stroke(0.0)
    var before := _read()
    tool.settings.mode = StateScript.SMOOTH
    tool.settings.size = SMOOTH_SIZE
    _hold(tool, CENTRE)
    var moved := _largest_difference(before, _read())
    assert_true(moved < 0.01, "A straight stroke under the brush stays as it was within a hundredth: %f" % moved)


## The smooth held over one flat *colour*, stored in *space*, and every texel
## read against it.
func _flat_stays(space: SaColorSpace, colour: Color, name: String) -> void:
    var tool: Variant = _open(space, func(_at: Vector2i) -> Color: return colour)
    var before := _read()
    tool.settings.mode = StateScript.SMOOTH
    tool.settings.size = SMOOTH_SIZE
    _hold(tool, CENTRE)
    var moved := _largest_difference(before, _read())
    assert_true(moved < FLAT, "A flat colour in %s is left as it was within %f: %f" % [name, FLAT, moved])


func test_a_smooth_over_a_flat_colour_changes_nothing() -> void:
    _flat_stays(SaColorSpace.srgb(), Color(0.8, 0.3, 0.2, 1.0), "sRGB")
    after_each()
    _flat_stays(SaColorSpace.oklab(), Color(0.7, 0.1, 0.05, 1.0), "Oklab")
    after_each()
    _flat_stays(SaColorSpace.srgb(), Color(0.8, 0.3, 0.2, 0.5), "sRGB, half covered")
