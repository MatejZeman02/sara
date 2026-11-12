## One block of the sweeping game: a gamma 3 gradient under a glitter coat that
## the pen scratches off, and later paints over.
##
## **Under the coat lies the target, not the reading.** The gradient is fixed,
## linear in Oklab lightness from black at the start dot to white at the far
## end, which is a gamma 3 ramp of light, Oklab's lightness being close to a
## cube root of luminance. The first pass only reveals it: the pen erases the
## coat with a hard round tip, and pressure does not change how much comes off.
## What the pen pressed is recorded by the dialog against where it was along
## the block, and the gradient is what the painter aims their hand at.
##
## **Try It paints the reading.** With the coat back, the same tip lays dabs
## over it, each the lightness of the pressure the new correction sends, so a
## sweep the correction fits paints the gradient the first pass revealed.
##
## The tip is a little wider than the block is thick, so a wobbling hand still
## clears the block's whole height, and every pen event is joined to the last
## by the round tip swept along the segment between them, the shape a canvas
## stroke's dabs fill in to at any spacing, so a flick leaves no gap. Each
## shape is convex and filled a row span at a time, so a long flick costs a
## fill a row rather than one a pixel. The coat
## and the paint are two images the size of the block, so nothing outside it
## is ever touched.
##
## The block always runs left to right in its own space, whatever angle the
## slot turned it to, and a pen event reaches `_gui_input` already in that
## space, which is why there is one case here rather than one per direction.
@tool
class_name SaTabletSweepStrip
extends Control

## The pen moved on the block, pressed, at *at* in the block's own space.
signal moved(at: Vector2, raw_pressure: float)
signal released

const COAT_EDGE := Color(0.45, 0.46, 0.5, 1.0)
const MARK := Color(0.98, 0.95, 0.85, 0.95)

## Loaded where the material wants it rather than preloaded, the reason
## `grey_veil.gd` gives for its own shader.
const COAT_SHADER_PATH := "res://ui/settings/input/tablet_sweep_coat.gdshader"

## The tip's width over the block's thickness. Half as wide again, so a pen
## that strays up to a quarter of the thickness off the block's middle still
## clears its whole height, the tip reaching half the thickness past the pen
## either way and a quarter more.
const TIP_SHARE := 1.5

## The longest piece a painted segment is cut into, in pixels, so the pressure
## between two pen events is laid as it changes rather than as one colour.
const PAINT_PIECE := 4.0

## Entries in the gradient texture.
const GRADIENT_STEPS := 256

## Corners on half a tip's round, enough that a tip seventy pixels wide is
## round to the pixel.
const TIP_STEPS := 16

## Sparks risen from the coat a second.
const SPARK_RATE := 5.0

## Where on the block the pen last was in this stroke, or NAN before it lands.
var _last: Vector2 = Vector2(NAN, NAN)
## The lightness of that event, read between it and the next when painting.
var _last_lightness: float = 0.0
## Which way the pen last moved, so a still pen's round end stays ahead of it.
var _heading: Vector2 = Vector2.ZERO

## How much coat is off each pixel, 0 to 1, in an L8 image the block's size.
var _scratch: Image = null
var _scratch_texture: ImageTexture = null
## What Try It painted, an RGBA8 image the block's size.
var _paint: Image = null
var _paint_texture: ImageTexture = null
var _gradient_texture: ImageTexture = null

## Whether the coat is whole, which is when the start mark shows.
var untouched: bool = true

var _coat: Coat = null
var _sparks: Sparks = null


func _init() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    _gradient_texture = ImageTexture.create_from_image(_gradient_image())
    _coat = Coat.new()
    add_child(_coat)
    _sparks = Sparks.new()
    add_child(_sparks)
    resized.connect(_fit_images)


## The coat back whole and the paint gone, which is what a new sweep, Start
## Again and Try It all mean.
func clear() -> void:
    untouched = true
    lift()
    _fit_images()


## Where the start dot sits and where the far end is, along the block's middle.
## The gradient and [method along_of] both run between the two.
func start_point() -> Vector2:
    return Vector2(_inset(), size.y * 0.5)


func end_point() -> Vector2:
    return Vector2(maxf(size.x - _inset(), _inset() + 1.0), size.y * 0.5)


## *at*'s projection on the block's axis, 0 at the dot and 1 at the far end,
## clamped, which is what a sweep is recorded against.
func along_of(at: Vector2) -> float:
    var from := start_point()
    var to := end_point()
    return clampf((at.x - from.x) / (to.x - from.x), 0.0, 1.0)


## The point *along* the axis and *across* pixels off its middle.
func point_at(along: float, across: float = 0.0) -> Vector2:
    return start_point().lerp(end_point(), along) + Vector2(0.0, across)


## The tip's radius, in the block's pixels.
func tip_radius() -> float:
    return size.y * TIP_SHARE * 0.5


## The coat scratched off along the pen's path from the last event to *at*.
## The pen's first event in a stroke is a dab of its own.
func scratch_to(at: Vector2) -> void:
    if _scratch == null:
        return
    var from := at if is_nan(_last.x) else _last
    var white := Color(1.0, 1.0, 1.0, 1.0)
    var radius := tip_radius()
    var heading := Vector2.RIGHT if from == at else (at - from).normalized()
    SaTabletSweepStrip.fill_convex(_scratch, SaTabletSweepStrip.round_end(from, -heading, radius), white)
    SaTabletSweepStrip.fill_convex(_scratch, SaTabletSweepStrip.slab(from, at, radius), white)
    SaTabletSweepStrip.fill_convex(_scratch, SaTabletSweepStrip.round_end(at, heading, radius), white)
    _last = at
    untouched = false
    _scratch_texture.update(_scratch)
    _coat.queue_redraw()
    _redraw_sparks()


## A Try It stroke painted from the last event to *at*, at the gamma 3
## lightness *lightness*, the pressure between the two read as it changes.
##
## Each pixel shows the pressure where the pen was level with it, the way the
## gradient under the coat shows a lightness per place, and not the pressure a
## tip's width further on, which is what a later dab laid over an earlier one
## would leave. So a segment is laid as slabs of the tip's width, each the
## lightness at its own place, and the round of the tip only ahead of the pen,
## where the next slab will lay over it, and behind where the stroke began.
func paint_to(at: Vector2, lightness: float) -> void:
    if _paint == null:
        return
    var radius := tip_radius()
    if is_nan(_last.x):
        SaTabletSweepStrip.fill_convex(_paint, SaTabletSweepStrip.round_end(at, -_heading, radius), ramp_color(lightness))
        _last = at
        _last_lightness = lightness
    var path := at - _last
    if path.length() > 0.0:
        _heading = path.normalized()
    var pieces := maxi(1, ceili(path.length() / PAINT_PIECE))
    for piece in range(pieces):
        var low := _last.lerp(at, float(piece) / float(pieces))
        var high := _last.lerp(at, float(piece + 1) / float(pieces))
        var color := ramp_color(lerpf(_last_lightness, lightness, float(piece + 1) / float(pieces)))
        SaTabletSweepStrip.fill_convex(_paint, SaTabletSweepStrip.slab(low, high, radius), color)
    SaTabletSweepStrip.fill_convex(_paint, SaTabletSweepStrip.round_end(at, _heading, radius), ramp_color(lightness))
    _last = at
    _last_lightness = lightness
    untouched = false
    _paint_texture.update(_paint)
    _coat.queue_redraw()
    _redraw_sparks()


## The paint taken off again with the coat left as it is, so the dialog can lay
## the Try It strokes once more through a dragged curve.
func clear_paint() -> void:
    if _paint == null:
        return
    _paint.fill(Color(0.0, 0.0, 0.0, 0.0))
    _paint_texture.update(_paint)
    lift()
    _coat.queue_redraw()


## The pen lifted, so the next event starts a stroke of its own.
func lift() -> void:
    _last = Vector2(NAN, NAN)
    _heading = Vector2.ZERO


## How much coat is off the pixel at *at*, 0 to 1, or -1 outside the block.
func scratched_at(at: Vector2) -> float:
    var pixel := Vector2i(floori(at.x), floori(at.y))
    if _scratch == null or pixel.x < 0 or pixel.y < 0 or pixel.x >= _scratch.get_width() or pixel.y >= _scratch.get_height():
        return -1.0
    return _scratch.get_pixelv(pixel).r


## What Try It painted at *at*, transparent where nothing was.
func painted_at(at: Vector2) -> Color:
    var pixel := Vector2i(floori(at.x), floori(at.y))
    if _paint == null or pixel.x < 0 or pixel.y < 0 or pixel.x >= _paint.get_width() or pixel.y >= _paint.get_height():
        return Color(0.0, 0.0, 0.0, 0.0)
    return _paint.get_pixelv(pixel)


## The gradient's colour at *at*, the colour scratching reveals there.
func gradient_at(at: Vector2) -> Color:
    return ramp_color(along_of(at))


## Oklab lightness *t* from black to white, as a colour to draw with.
static func ramp_color(t: float) -> Color:
    var linear := OkhsvConversions.oklab_to_linear_srgb(Vector3(clampf(t, 0.0, 1.0), 0.0, 0.0))
    var clamped := Vector3(clampf(linear.x, 0.0, 1.0), clampf(linear.y, 0.0, 1.0), clampf(linear.z, 0.0, 1.0))
    var encoded := OkhsvConversions.srgb_transfer_function(clamped)
    return Color(encoded.x, encoded.y, encoded.z, 1.0)


## The rectangle a tip of *radius* covers moving from *from* to *to*, without
## its round ends, as a convex polygon. Nothing when the two are one point.
static func slab(from: Vector2, to: Vector2, radius: float) -> PackedVector2Array:
    var path := to - from
    if path.length() <= 0.0:
        return PackedVector2Array()
    var side := Vector2(-path.y, path.x).normalized() * radius
    return PackedVector2Array([from + side, to + side, to - side, from - side])


## The half of a tip of *radius* at *at* that lies towards *heading*, as a
## convex polygon. A heading of nought is the whole tip.
static func round_end(at: Vector2, heading: Vector2, radius: float) -> PackedVector2Array:
    var points := PackedVector2Array()
    var whole := heading.length() <= 0.0
    var start := 0.0 if whole else heading.angle() - PI * 0.5
    var arc := TAU if whole else PI
    var steps := TIP_STEPS * (2 if whole else 1)
    for i in range(steps + (0 if whole else 1)):
        points.append(at + Vector2.from_angle(start + arc * float(i) / float(steps)) * radius)
    return points


## *polygon*, which must be convex, filled into *image* in *color*. Every row
## it crosses is one span, so a long slab costs one fill a row rather than one
## a pixel, and whatever lies outside the image is left out.
static func fill_convex(image: Image, polygon: PackedVector2Array, color: Color) -> void:
    if polygon.size() < 3:
        return
    var width := image.get_width()
    var top := INF
    var bottom := -INF
    for point in polygon:
        top = minf(top, point.y)
        bottom = maxf(bottom, point.y)
    for row in range(maxi(floori(top), 0), mini(ceili(bottom), image.get_height() - 1) + 1):
        var y := float(row) + 0.5
        var left := INF
        var right := -INF
        for i in range(polygon.size()):
            var a := polygon[i]
            var b := polygon[(i + 1) % polygon.size()]
            if (a.y - y) * (b.y - y) > 0.0 or a.y == b.y:
                continue
            var x := lerpf(a.x, b.x, (y - a.y) / (b.y - a.y))
            left = minf(left, x)
            right = maxf(right, x)
        var first := maxi(ceili(left - 0.5), 0)
        var last := mini(floori(right - 0.5), width - 1)
        if last >= first:
            image.fill_rect(Rect2i(first, row, last - first + 1, 1), color)


## The sparks drawn again, the start mark with them while the coat is whole.
func _redraw_sparks() -> void:
    _sparks.mark(start_point() if untouched else Vector2(NAN, NAN))


func _inset() -> float:
    return minf(size.y * 0.5, size.x * 0.25)


func _fit_images() -> void:
    var pixels := Vector2i(maxi(ceili(size.x), 1), maxi(ceili(size.y), 1))
    _scratch = Image.create_empty(pixels.x, pixels.y, false, Image.FORMAT_L8)
    _paint = Image.create_empty(pixels.x, pixels.y, false, Image.FORMAT_RGBA8)
    _scratch_texture = ImageTexture.create_from_image(_scratch)
    _paint_texture = ImageTexture.create_from_image(_paint)
    _coat.size = size
    _sparks.size = size
    _coat.bind(_scratch_texture, _paint_texture)
    _sparks.bind(_scratch, _paint)
    queue_redraw()
    _coat.queue_redraw()
    _redraw_sparks()


static func _gradient_image() -> Image:
    var image := Image.create_empty(GRADIENT_STEPS, 1, false, Image.FORMAT_RGBA8)
    for i in range(GRADIENT_STEPS):
        image.set_pixel(i, 0, ramp_color(float(i) / float(GRADIENT_STEPS - 1)))
    return image


## The gradient, black before the dot and white past the far end, under
## everything else.
func _draw() -> void:
    if size.x <= 1.0 or size.y <= 1.0:
        return
    var from := start_point().x
    var to := end_point().x
    draw_rect(Rect2(0.0, 0.0, from, size.y), ramp_color(0.0))
    draw_texture_rect(_gradient_texture, Rect2(from, 0.0, to - from, size.y), false)
    draw_rect(Rect2(to, 0.0, size.x - to, size.y), ramp_color(1.0))


func _gui_input(event: InputEvent) -> void:
    var pressure := SaTablet.pressure_of(event)
    if pressure >= 0.0:
        moved.emit((event as InputEventMouseMotion).position, pressure)
        return
    var button := event as InputEventMouseButton
    if button != null and not button.pressed:
        released.emit()


## The glitter coat, drawn by `tablet_sweep_coat.gdshader` over the gradient
## with the scratches cut out of it and the Try It paint laid over it. A child
## of its own, because a material shades everything its item draws and the
## gradient under it must stay as it is.
class Coat:
    extends Control

    var _scratch: Texture2D = null

    func _init() -> void:
        name = "Coat"
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        var coat := ShaderMaterial.new()
        coat.shader = load(COAT_SHADER_PATH)
        material = coat

    ## The two images the shader reads, again each time the block is resized.
    func bind(scratch: Texture2D, paint: Texture2D) -> void:
        _scratch = scratch
        (material as ShaderMaterial).set_shader_parameter("paint", paint)
        (material as ShaderMaterial).set_shader_parameter("pixels", size)
        queue_redraw()

    func _draw() -> void:
        if _scratch == null or size.x <= 1.0:
            return
        draw_texture_rect(_scratch, Rect2(Vector2.ZERO, size), false)


## The start mark and the sparks that rise off the coat, the way a game shows
## that something can be touched. Each spark rises up the screen whatever way
## the block is turned, wobbles a little to the sides and fades past the
## block's edge, and none rises from coat the pen has taken off.
class Sparks:
    extends Control

    ## How long a spark lives, in seconds.
    const LIFE := 1.6

    ## The block's scratch and paint images, read for where a spark may rise.
    var _scratch: Image = null
    var _paint: Image = null
    ## Where the start dot sits, or NAN once the coat has been touched.
    var _mark: Vector2 = Vector2(NAN, NAN)
    var _rng := RandomNumberGenerator.new()
    var _owed: float = 0.0
    ## Each spark as `[where it rose, seconds old, wobble phase, size]`.
    var sparks: Array = []

    func _init() -> void:
        name = "Sparks"
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        _rng.seed = 723

    ## The two images the sparks avoid, again each time the block is resized.
    func bind(scratch: Image, paint: Image) -> void:
        _scratch = scratch
        _paint = paint
        queue_redraw()

    ## The start mark at *at*, or none when *at* is NAN.
    func mark(at: Vector2) -> void:
        _mark = at
        queue_redraw()

    func _coated_at(at: Vector2) -> bool:
        var pixel := Vector2i(floori(at.x), floori(at.y))
        if _scratch == null or not Rect2i(Vector2i.ZERO, _scratch.get_size()).has_point(pixel):
            return false
        return _scratch.get_pixelv(pixel).r < 0.5 and _paint.get_pixelv(pixel).a < 0.5

    func _process(delta: float) -> void:
        if not is_visible_in_tree():
            return
        for spark: Array in sparks:
            spark[1] = float(spark[1]) + delta
        sparks = sparks.filter(func(spark: Array) -> bool: return float(spark[1]) < LIFE)
        _owed += delta * SPARK_RATE * maxf(size.x / maxf(size.y, 1.0), 1.0) * 0.25
        while _owed >= 1.0:
            _owed -= 1.0
            var at := Vector2(_rng.randf() * size.x, _rng.randf() * size.y)
            if _coated_at(at):
                sparks.append([at, 0.0, _rng.randf() * TAU, _rng.randf_range(2.0, 4.5)])
        queue_redraw()

    func _draw() -> void:
        # The block's edge here and not on the coat, whose material would shade
        # it as coat.
        draw_rect(Rect2(Vector2.ZERO, size), COAT_EDGE, false, 1.0)
        var up := _screen_up()
        var aside := Vector2(-up.y, up.x)
        var unit := SaUI.pxf(1.0)
        for spark: Array in sparks:
            var age := float(spark[1])
            var share := age / LIFE
            var at: Vector2 = spark[0] + up * age * SaUI.pxf(26.0) + aside * sin(age * 5.0 + float(spark[2])) * SaUI.pxf(3.0)
            var glow := sin(share * PI)
            var arm := float(spark[3]) * unit * (0.6 + 0.4 * glow)
            var color := Color(MARK, glow)
            draw_line(at - up * arm, at + up * arm, color, maxf(unit, 1.0))
            draw_line(at - aside * arm, at + aside * arm, color, maxf(unit, 1.0))
            draw_circle(at, arm * 0.3, color)
        if not is_nan(_mark.x):
            _draw_start_mark()

    ## A dot at the start and an arrow to the far end. A turned block does not
    ## say by itself which of its two ends is the beginning.
    func _draw_start_mark() -> void:
        var from := _mark
        var radius := minf(SaUI.pxf(5.0), size.y * 0.18)
        draw_circle(from, radius, MARK)
        var tail := from + Vector2(radius * 2.5, 0.0)
        var head := tail + Vector2(minf(SaUI.pxf(34.0), size.x * 0.25), 0.0)
        var width := maxf(SaUI.pxf(2.0), 1.0)
        draw_line(tail, head, MARK, width)
        var barb := radius * 1.4
        draw_line(head, head + Vector2(-barb, -barb * 0.8), MARK, width)
        draw_line(head, head + Vector2(-barb, barb * 0.8), MARK, width)

    func _screen_up() -> Vector2:
        var turned := get_global_transform().affine_inverse().basis_xform(Vector2.UP)
        return turned.normalized() if turned.length() > 0.0 else Vector2.UP
