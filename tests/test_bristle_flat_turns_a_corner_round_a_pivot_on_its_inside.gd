## Bristle Flat turns a corner round a pivot on its inside.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A sharp turn and a hairpin are drawn the way a flat brush's hairs swing round its inside corner.
## Each streak keeps its distance from a pivot on the inside of the turn, so
## none meets another at a mitre or crosses the first leg in a wedge.
##
## **The right angle.** Bristle Flat at 90 pixels and a pressure of 0.35 runs
## along a level leg and turns up through 90 degrees, a sample every
## [constant SPACING] pixels with the joint one of them. The painted runs read
## outwards from the inside corner, the point a half width in from both legs,
## along the bisector a half width towards the joint, match the runs read
## across the first leg at that corner, from its inside edge out to its middle,
## run for run within a pixel. The outer half is read no further, because the
## turn's outside reaches out to the pen's turning point, a spur whose own
## middle streak runs out along that bisector.
## The layer is read after the lift, which holds the stroke buffer laid in
## black at full opacity. Before the pivot the bisector crossed each streak at
## its mitre, so it found the leg's runs about 1.35 times as far out and as
## long.
##
## **The hairpin.** The same stroke turns through 160 degrees instead, with
## no front laid, so the stroke buffer holds what the body painted alone, and
## the second leg is drawn in red. The buffer is read on lines across the
## first leg within a half width of the joint when the pen reaches the joint
## and after every sample of the second leg, since the body paints the half
## width before the joint only once the turn is known. A texel that held the
## first leg's black at any of those reads and holds red at the last is one
## the second leg painted over the first. Each run of such texels on a line is
## a run of the second leg crossing the first leg's band, and none is left.
## Before the pivot the second leg's first segments were nearest the texels on
## the inside of the turn, which the first leg had painted already, and four
## runs crossed. The first leg paints a fiftieth of the texels read at least,
## and the second a two hundredth, since the spur out to the turning point is
## painted in the joint's black, so a count of nought is not one of a corner
## left bare.
##
## A run is where the alpha read between the texels' centres is
## [constant PAINTED] or more, so a run read along the bisector, whose texels
## lie 1.4 pixels apart, ends to within a pixel as one read along an axis
## does.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

## The tip's radius and the pressure, the gap between two samples in pixels
## and in milliseconds, and the stroke's seed.
const RADIUS := 90.0
const PRESSURE := 0.35
const SPACING := 4.0
const SAMPLE_MS := 8.0
const SEED := 7
## The right angle's canvas and path: a level leg to the joint, then up.
const TURN_CANVAS := Vector2i(768, 768)
const TURN_PATH: Array[Vector2] = [Vector2(100.0, 560.0), Vector2(560.0, 560.0), Vector2(560.0, 100.0)]
## The hairpin's canvas, its level leg, and its second leg's turn and length.
const HAIRPIN_CANVAS := Vector2i(1024, 768)
const HAIRPIN_FROM := Vector2(140.0, 560.0)
const HAIRPIN_JOINT := Vector2(840.0, 560.0)
const HAIRPIN_TURN := 160.0
const HAIRPIN_LEG := 500.0
## The colour the second leg is drawn in, and how much red a texel holds to
## count as painted over by it.
const SECOND_LEG := Color(1.0, 0.0, 0.0, 1.0)
const RED := 0.05
## The gap between two lines read across the first leg, in pixels.
const LINE_STEP := 6
## The alpha a texel holds to be painted, the step a line is read at, and how
## far apart two matching runs' ends may be, in pixels but the first.
const PAINTED := 0.5
const READ_STEP := 0.25
const WITHIN := 1.0


## A dab list that lays no front, so the stroke buffer holds the body alone.
class NoFrontList:
    extends "res://modules/sara-noise-brush-engine/dab_list/noise_dab_list.gd"

    func lay_front(
        _doc: SaDocument,
        _compute: SaCompute,
        _values: Dictionary,
        _carry: SaTexture,
        _pressure: float,
        _heights: SaStrokeHeights = null
    ) -> void:
        pass


var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
var _albedo: Dictionary = {}


func before_each() -> void:
    _surface = Fixtures.make_surface(TURN_CANVAS)


func after_each() -> void:
    _brush = null
    _albedo.clear()
    Fixtures.teardown(_surface)
    _surface = null


func test_a_right_angle_s_streaks_keep_their_distance_from_the_inside_corner() -> void:
    _fresh(TURN_CANVAS)
    _path(TURN_PATH)
    var joint := TURN_PATH[1]
    var inner := joint + RADIUS * Vector2(-1.0, -1.0)
    var leg := _runs(inner, Vector2(0.0, 1.0), RADIUS)
    var bisector := _runs(inner, Vector2(1.0, 1.0).normalized(), RADIUS)
    print("across the leg %s" % [leg])
    print("along the bisector %s" % [bisector])
    print("the bisector's runs are %.3f times the leg's" % _stretch(leg, bisector))
    assert_true(leg.size() > 2, "The leg crosses %d streaks, enough to read a turn by" % leg.size())
    assert_eq(bisector.size(), leg.size(), "The bisector crosses as many streaks as the leg does")
    for at in mini(leg.size(), bisector.size()):
        var near := absf(bisector[at].x - leg[at].x) <= WITHIN and absf(bisector[at].y - leg[at].y) <= WITHIN
        assert_true(
            near,
            (
                "Run %d lies from %.1f to %.1f on the bisector and from %.1f to %.1f across the leg"
                % [at, bisector[at].x, bisector[at].y, leg[at].x, leg[at].y]
            )
        )


func test_a_hairpin_s_second_leg_crosses_no_streak_of_the_first_by_the_joint() -> void:
    _fresh(HAIRPIN_CANVAS)
    _brush.dab_list = NoFrontList.new(StateNoiseBrushScript.KERNEL)
    var reach := int(RADIUS)
    var joint := Vector2i(HAIRPIN_JOINT)
    var area := Rect2i(joint - Vector2i(reach, reach), Vector2i(reach + 1, 2 * reach + 1))
    var heading := Vector2.RIGHT.rotated(deg_to_rad(-HAIRPIN_TURN))
    var clock := 1000.0
    _brush.begin_stroke(HAIRPIN_FROM, PRESSURE, Vector2.ZERO, clock)
    var steps := ceili(HAIRPIN_FROM.distance_to(HAIRPIN_JOINT) / SPACING)
    for i in range(1, steps + 1):
        clock += SAMPLE_MS
        _brush.add_sample(HAIRPIN_FROM.lerp(HAIRPIN_JOINT, float(i) / steps), PRESSURE, Vector2.ZERO, clock)
    var black: Dictionary[Vector2i, bool] = {}
    _note_black(black, area)
    _brush.settings.color = SECOND_LEG
    var end := HAIRPIN_JOINT + HAIRPIN_LEG * heading
    steps = ceili(HAIRPIN_LEG / SPACING)
    for i in range(1, steps + 1):
        clock += SAMPLE_MS
        _brush.add_sample(HAIRPIN_JOINT.lerp(end, float(i) / steps), PRESSURE, Vector2.ZERO, clock)
        _note_black(black, area)
    var last := _stroke_images(area)
    _brush.end_stroke()
    var crossings := 0
    var red := 0
    var read := 0
    for dx in range(-reach, 1, LINE_STEP):
        var inside := false
        for dy in range(-reach, reach + 1):
            if Vector2(dx, dy).length() > RADIUS:
                inside = false
                continue
            var pixel := joint + Vector2i(dx, dy)
            var now := _texel_of(last, pixel)
            var crossed := black.has(pixel) and now.r >= RED
            if crossed and not inside:
                crossings += 1
            inside = crossed
            read += 1
            if now.a >= PAINTED and now.r >= RED:
                red += 1
    print(
        (
            # gdlint:ignore=max-line-length
            "the second leg crosses the first in %d runs by the joint, of %d texels read %d the first leg painted and %d the second"
            % [crossings, read, black.size(), red]
        )
    )
    assert_true(black.size() * 50 > read, "The first leg paints its band by the joint, %d of %d texels" % [black.size(), read])
    assert_true(red * 200 > read, "The second leg paints by the joint as well, %d of %d texels" % [red, read])
    assert_eq(crossings, 0, "No run of the second leg crosses the first leg's band within a half width of the joint")


## Notes in *black* every texel on the lines the hairpin reads, within *area*
## and a half width of the joint, that the stroke buffer holds painted in the
## first leg's black now.
func _note_black(black: Dictionary[Vector2i, bool], area: Rect2i) -> void:
    var images := _stroke_images(area)
    var reach := int(RADIUS)
    for dx in range(-reach, 1, LINE_STEP):
        for dy in range(-reach, reach + 1):
            if Vector2(dx, dy).length() > RADIUS:
                continue
            var pixel := Vector2i(HAIRPIN_JOINT) + Vector2i(dx, dy)
            var texel := _texel_of(images, pixel)
            if texel.a >= PAINTED and texel.r < RED:
                black[pixel] = true


func _fresh(size: Vector2i) -> void:
    _albedo.clear()
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(size)
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = SEED
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == "Bristle Flat":
            # Without the radius taper, so the tip is the width the turn was measured at.
            var untapered := entry.duplicate(true)
            (untapered["pressure"] as Dictionary).erase("radius")
            _brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, untapered)
    # Bristle Flat ships at a thickness of 0, so the test sets 0.2 for the streaks to lay height to read.
    _brush.settings.thickness = 0.2
    _brush.settings.color = Color(0.0, 0.0, 0.0, 1.0)
    _brush.settings.radius = RADIUS / mini(size.x, size.y)


## The stroke through *corners* at [constant PRESSURE], a sample every
## [constant SPACING] pixels or a little less, each corner a sample.
func _path(corners: Array[Vector2]) -> void:
    var clock := 1000.0
    _brush.begin_stroke(corners[0], PRESSURE, Vector2.ZERO, clock)
    for at in range(1, corners.size()):
        var steps := ceili(corners[at - 1].distance_to(corners[at]) / SPACING)
        for i in range(1, steps + 1):
            clock += SAMPLE_MS
            _brush.add_sample(corners[at - 1].lerp(corners[at], float(i) / steps), PRESSURE, Vector2.ZERO, clock)
    _brush.end_stroke()


## The painted runs on the line from *from* along *heading* for *length*
## pixels, each its start and end in pixels from *from*, where the alpha read
## between the texels' centres crosses [constant PAINTED].
func _runs(from: Vector2, heading: Vector2, length: float) -> Array[Vector2]:
    var out: Array[Vector2] = []
    var before := _alpha(from) - PAINTED
    var start := 0.0 if before >= 0.0 else -1.0
    var t := 0.0
    while t < length:
        var next := minf(t + READ_STEP, length)
        var now := _alpha(from + next * heading) - PAINTED
        if (before < 0.0) != (now < 0.0):
            var cross := t + (next - t) * before / (before - now)
            if now >= 0.0:
                start = cross
            else:
                out.append(Vector2(start, cross))
                start = -1.0
        before = now
        t = next
    if start >= 0.0:
        out.append(Vector2(start, length))
    return out


## The active layer's alpha at *at*, in pixels, read between the four texels
## whose centres lie round it.
func _alpha(at: Vector2) -> float:
    var corner := at - Vector2(0.5, 0.5)
    var texel := Vector2i(corner.floor())
    var share := corner - Vector2(texel)
    var top := lerpf(_texel(texel).a, _texel(texel + Vector2i(1, 0)).a, share.x)
    var bottom := lerpf(_texel(texel + Vector2i(0, 1)).a, _texel(texel + Vector2i(1, 1)).a, share.x)
    return lerpf(top, bottom, share.y)


## How many times as long *bisector*'s runs are as *leg*'s on the mean, run
## for run over the runs both have.
func _stretch(leg: Array[Vector2], bisector: Array[Vector2]) -> float:
    var leg_long := 0.0
    var bisector_long := 0.0
    for at in mini(leg.size(), bisector.size()):
        leg_long += leg[at].y - leg[at].x
        bisector_long += bisector[at].y - bisector[at].x
    return bisector_long / leg_long if leg_long > 0.0 else 0.0


## The side of a chunk of *layer*, nought while it has none.
func _side(layer: SaLayer) -> int:
    for grid: Vector2i in layer.chunks:
        return (layer.chunks[grid] as SaChunk).pixel_size()
    return 0


## Every chunk of the stroke buffer that meets *area*, as it stands, read
## back, by grid position, with the chunks' side under the key `side`.
func _stroke_images(area: Rect2i) -> Dictionary:
    var layer := _surface.easel.document.stroke_layer
    var side := _side(layer)
    var out := {"side": side}
    for grid: Vector2i in layer.chunks:
        if not Rect2i(grid * side, Vector2i(side, side)).intersects(area):
            continue
        @warning_ignore("static_called_on_instance")
        out[grid] = SaExport.get_texture_image_float(layer.get_field(grid))
    return out


## The texel at *pixel* of *images*, read by [method _stroke_images].
func _texel_of(images: Dictionary, pixel: Vector2i) -> Color:
    var side: int = images["side"]
    if side == 0:
        return Color.TRANSPARENT
    var grid := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
    if not images.has(grid):
        return Color.TRANSPARENT
    return (images[grid] as Image).get_pixelv(pixel - grid * side)


## The active layer's texel at *pixel*.
func _texel(pixel: Vector2i) -> Color:
    var layer := _surface.easel.document.active_layer
    var side := _side(layer)
    if side == 0:
        return Color.TRANSPARENT
    var grid := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
    if not layer.chunks.has(grid):
        return Color.TRANSPARENT
    if not _albedo.has(grid):
        @warning_ignore("static_called_on_instance")
        _albedo[grid] = SaExport.get_texture_image_float(layer.get_field(grid))
    return (_albedo[grid] as Image).get_pixelv(pixel - grid * side)
