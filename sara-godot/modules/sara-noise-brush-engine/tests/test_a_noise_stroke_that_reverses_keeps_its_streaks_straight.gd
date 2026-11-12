## A noise stroke that reverses keeps its streaks straight.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A bristle brush scrubbed to and fro must not bend its strands round a circle
## when it moves forward and backward. Bristle Flat at
## [constant RADIUS] pixels and a pressure of [constant PRESSURE] runs along a
## level leg in black and comes back in red, once along the same line, a turn
## of 180 degrees, and once 15 degrees off it, a turn of 165.
##
## **A strand is a run of painted texels along its leg.** The layer is read
## after the lift on lines across each leg, [constant STATION] pixels apart,
## the first leg's black texels on its lines and the second's red ones on its
## own, so a strand of one leg is never followed onto the other's where the two
## cross. A run on a line whose middle lies within [constant LINK] pixels of a
## strand's on the line before carries that strand on, and any other starts
## one. A strand that comes in beside another and joins its run moves the
## run's middle by about 3 pixels from one line to the next, which is a join
## and not a turn, so [constant LINK] sits under it. A strand's direction at a line is the way from its middle there to its
## middle [constant BASE] lines on, and how far it turns is the most of those
## directions less the least.
##
## **The standard is the straight leg's.** The same stroke's first leg alone,
## played and lifted first in each test, sets the bound: no strand of a
## reversal turns through more than [constant MARGIN] times what the straight
## leg's most turning strand does, plus the turn one pixel makes over the
## [constant BASE] lines a direction is read across, which a slanted leg's
## stair of texels reads as. A 165 degree turn drawn as an arc round a pivot
## swings its strands through a half circle and reads tens of degrees.
##
## **Out and back on the same lines.** The straight leg's strands, read over
## its whole length, are the lines the first leg lays, and the second leg's
## runs are read off the layer after the lift at their distance across their
## own leg, counted on the side the first leg's are. At least
## [constant MATCHED] of them lie within their own half width of one of those
## lines. Strands mirrored about the path match about as many as chance gives,
## and the suite prints that share beside the one it holds. A strand starts and
## stops at its own length, so one the first leg never lays can show on the way
## back on no line of the first leg's, which [constant MATCHED] leaves room for.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const NoiseStretchScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_stretch.gd")

## The tip's radius and the pressure, the gap between two samples in pixels
## and in milliseconds, and the stroke's seed.
const RADIUS := 90.0
const PRESSURE := 0.35
const SPACING := 4.0
const SAMPLE_MS := 8.0
const SEED := 7
## The canvas, the first leg, and the second leg's length.
const CANVAS := Vector2i(1024, 768)
const FROM := Vector2(140.0, 520.0)
const JOINT := Vector2(760.0, 520.0)
const BACK := 620.0
## The colour the second leg is drawn in, and how much red a texel holds to
## be the second leg's.
const SECOND_LEG := Color(1.0, 0.0, 0.0, 1.0)
const RED := 0.05
## The alpha a texel holds to be painted and the step a line across is read
## at, the gap between two lines, how far a strand's middle may move from one
## line to the next, how many lines on a direction is read over, and the fewest
## lines a strand is measured on.
const PAINTED := 0.5
const READ_STEP := 0.25
const STATION := 4.0
const LINK := 2.5
const BASE := 8
const FEWEST := BASE + 3
## How far past a run's end the other leg's paint is looked for, in pixels.
const CUT := 1.0
## How far past the straight leg's most turning strand a reversal's may turn,
## as a share, and the share of the second leg's runs that lie on the first's.
const MARGIN := 1.5
const MATCHED := 0.85
## How far from the pen's turning point a leg is read from: two and a half
## steps between two points the stretch takes, since the pen turns up to a step
## past the point taken there and the kernel paints the chord between that
## point and the next.
var near := 2.5 * sqrt(2.0 * RADIUS * NoiseStretchScript.WOBBLE)

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null


func test_a_stroke_that_comes_back_along_its_line_keeps_each_strand_on_its_line() -> void:
    _reversal(180.0)


func test_a_stroke_that_comes_back_15_degrees_off_its_line_keeps_each_strand_straight() -> void:
    _reversal(165.0)


## Plays the straight leg alone for the bound, then the leg and back through
## *turn* degrees, and holds the reversal's strands to the bound and to the
## first leg's lines.
func _reversal(turn: float) -> void:
    var lines: Array[Vector2] = []
    var bound := MARGIN * _straight(lines) + rad_to_deg(atan(1.0 / (BASE * STATION)))
    var away := Vector2.RIGHT.rotated(deg_to_rad(-turn))
    var end := JOINT + BACK * away
    _fresh()
    var clock := _leg(FROM, JOINT, 1000.0, true)
    _brush.settings.color = SECOND_LEG
    _leg(JOINT, end, clock, false)
    _brush.end_stroke()
    var layer := _image(_surface.easel.document.active_layer)
    var out_leg := _strands(layer, FROM + RADIUS * Vector2.RIGHT, JOINT - near * Vector2.RIGHT, false, false)
    var back_leg := _strands(layer, JOINT + near * away, end - RADIUS * away, true, true)
    var out_most := _most_turn(out_leg)
    var back_most := _most_turn(back_leg)
    print(
        (
            "%.0f: the first leg's %d strands turn %.2f degrees at most, the second's %d %.2f, the bound %.2f"
            % [turn, out_leg.size(), out_most, back_leg.size(), back_most, bound]
        )
    )
    assert_true(
        out_leg.size() > 3 and back_leg.size() > 3,
        "Both legs carry strands to read, %d and %d" % [out_leg.size(), back_leg.size()]
    )
    assert_true(out_most <= bound, "No strand of the first leg turns past %.2f degrees, the most turns %.2f" % [bound, out_most])
    assert_true(
        back_most <= bound, "No strand of the second leg turns past %.2f degrees, the most turns %.2f" % [bound, back_most]
    )
    var back := _crossings(layer, JOINT + RADIUS * away, end - RADIUS * away, true, true)
    var on := _share_on(back, lines, 1.0)
    var mirrored := _share_on(back, lines, -1.0)
    print(
        (
            "%.0f: of the second leg's %d runs %.3f lie on the first leg's lines and %.3f on their mirror"
            % [turn, back.size(), on, mirrored]
        )
    )
    assert_true(back.size() > 20, "The second leg is read in %d runs" % back.size())
    assert_true(on >= MATCHED, "%.3f of the second leg's runs lie on the first leg's lines, at least %.2f" % [on, MATCHED])


## The most a strand of the first leg turns, played alone and lifted, with
## every run on its lines added to *lines*.
func _straight(lines: Array[Vector2]) -> float:
    _fresh()
    _leg(FROM, JOINT, 1000.0, true)
    _brush.end_stroke()
    var layer := _image(_surface.easel.document.active_layer)
    var strands := _strands(layer, FROM + RADIUS * Vector2.RIGHT, JOINT - near * Vector2.RIGHT, false, false)
    lines.append_array(_crossings(layer, FROM + RADIUS * Vector2.RIGHT, JOINT - near * Vector2.RIGHT, false, false))
    var most := _most_turn(strands)
    print("the straight leg's %d strands turn %.2f degrees at most" % [strands.size(), most])
    assert_true(strands.size() > 3, "The straight leg carries %d strands to read" % strands.size())
    return most


func _fresh() -> void:
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = SEED
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == "Bristle Flat":
            # Without the radius taper, so the tip is one width all along.
            var untapered := entry.duplicate(true)
            (untapered["pressure"] as Dictionary).erase("radius")
            _brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, untapered)
    _brush.settings.color = Color(0.0, 0.0, 0.0, 1.0)
    _brush.settings.radius = RADIUS / mini(CANVAS.x, CANVAS.y)


## Samples from *from* to *to* a [constant SPACING] apart or a little less,
## pressing first when *press*, from *clock* on, and answers the clock after.
func _leg(from: Vector2, to: Vector2, clock: float, press: bool) -> float:
    if press:
        _brush.begin_stroke(from, PRESSURE, Vector2.ZERO, clock)
    var steps := ceili(from.distance_to(to) / SPACING)
    for i in range(1, steps + 1):
        clock += SAMPLE_MS
        _brush.add_sample(from.lerp(to, float(i) / steps), PRESSURE, Vector2.ZERO, clock)
    return clock


## The strands on the lines across the leg from *from* to *to*, each the
## middles of its runs line by line, red texels or black ones by *red*, the
## distance across counted on the other side of the leg when *flip*.
func _strands(image: Dictionary, from: Vector2, to: Vector2, red: bool, flip: bool) -> Array[PackedFloat32Array]:
    var done: Array[PackedFloat32Array] = []
    var live: Array[PackedFloat32Array] = []
    var heading := (to - from).normalized()
    var across := _across(heading, flip)
    var count := floori(from.distance_to(to) / STATION)
    for at in count + 1:
        var middles := _middles(_runs(image, from + at * STATION * heading, across, red))
        var going: Array[PackedFloat32Array] = []
        var taken: Dictionary[int, bool] = {}
        for strand: PackedFloat32Array in live:
            var best := -1
            for index in middles.size():
                if taken.has(index) or absf(middles[index] - strand[-1]) > LINK:
                    continue
                if best < 0 or absf(middles[index] - strand[-1]) < absf(middles[best] - strand[-1]):
                    best = index
            if best < 0:
                done.append(strand)
                continue
            taken[best] = true
            strand.append(middles[best])
            going.append(strand)
        for index in middles.size():
            if not taken.has(index):
                going.append(PackedFloat32Array([middles[index]]))
        live = going
    done.append_array(live)
    var out: Array[PackedFloat32Array] = []
    for strand: PackedFloat32Array in done:
        if strand.size() >= FEWEST:
            out.append(strand)
    return out


## The most any of *strands* turns, in degrees: the greatest direction over
## [constant BASE] lines less the least, along each.
func _most_turn(strands: Array[PackedFloat32Array]) -> float:
    var most := 0.0
    for strand in strands:
        var low := INF
        var high := -INF
        for at in strand.size() - BASE:
            var direction := rad_to_deg(atan2(strand[at + BASE] - strand[at], BASE * STATION))
            low = minf(low, direction)
            high = maxf(high, direction)
        most = maxf(most, high - low)
    return most


## Every run on the lines across the leg from *from* to *to*, its middle in x
## and its width in y, read as [method _strands] reads them.
func _crossings(image: Dictionary, from: Vector2, to: Vector2, red: bool, flip: bool) -> Array[Vector2]:
    var out: Array[Vector2] = []
    var heading := (to - from).normalized()
    var across := _across(heading, flip)
    for at in floori(from.distance_to(to) / STATION) + 1:
        for run in _runs(image, from + at * STATION * heading, across, red):
            out.append(Vector2(0.5 * (run.x + run.y), run.y - run.x))
    return out


## The share of *runs* whose middle, times *side*, lies within its own half
## width of the middle of one of *lines*.
func _share_on(runs: Array[Vector2], lines: Array[Vector2], side: float) -> float:
    if runs.is_empty():
        return 0.0
    var on := 0
    for run in runs:
        for line in lines:
            if absf(side * run.x - line.x) <= 0.5 * run.y:
                on += 1
                break
    return float(on) / runs.size()


## The way across a leg heading along *heading*, turned over when *flip*.
func _across(heading: Vector2, flip: bool) -> Vector2:
    var across := Vector2(-heading.y, heading.x)
    return -across if flip else across


## The middles of *runs*.
func _middles(runs: Array[Vector2]) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    for run in runs:
        out.append(0.5 * (run.x + run.y))
    return out


## The painted runs on the line through *centre* along *across*, from a tip's
## radius one side to a tip's radius the other, each its start and end in
## pixels from *centre*, of red texels or black ones by *red*.
func _runs(image: Dictionary, centre: Vector2, across: Vector2, red: bool) -> Array[Vector2]:
    var out: Array[Vector2] = []
    var t := -RADIUS
    var before := _alpha(image, centre + t * across, red) - PAINTED
    var start := t if before >= 0.0 else INF
    while t < RADIUS:
        var next := minf(t + READ_STEP, RADIUS)
        var now := _alpha(image, centre + next * across, red) - PAINTED
        if (before < 0.0) != (now < 0.0):
            var cross := t + (next - t) * before / (before - now)
            if now >= 0.0:
                start = cross
            else:
                if start != INF and start > -RADIUS and not _cut(image, centre, across, Vector2(start, cross), red):
                    out.append(Vector2(start, cross))
                start = INF
        before = now
        t = next
    return out


## Whether *run* on the line through *centre* along *across* meets the other
## leg's paint at either end, so that leg's strand crossing over it cut it and
## its middle is not its own strand's.
func _cut(image: Dictionary, centre: Vector2, across: Vector2, run: Vector2, red: bool) -> bool:
    for at: float in [run.x - CUT, run.y + CUT]:
        if _alpha(image, centre + at * across, not red) >= PAINTED:
            return true
    return false


## The alpha at *at* of *image*'s texels of the leg *red* names, read between
## the four whose centres lie round it, a texel of the other leg counting as
## bare.
func _alpha(image: Dictionary, at: Vector2, red: bool) -> float:
    var corner := at - Vector2(0.5, 0.5)
    var texel := Vector2i(corner.floor())
    var share := corner - Vector2(texel)
    var top := lerpf(_leg_alpha(image, texel, red), _leg_alpha(image, texel + Vector2i(1, 0), red), share.x)
    var bottom := lerpf(_leg_alpha(image, texel + Vector2i(0, 1), red), _leg_alpha(image, texel + Vector2i(1, 1), red), share.x)
    return lerpf(top, bottom, share.y)


func _leg_alpha(image: Dictionary, pixel: Vector2i, red: bool) -> float:
    var texel := _texel_of(image, pixel)
    return texel.a if (texel.r >= RED) == red else 0.0


## Every chunk of *layer*, read back, by grid position, with the chunks' side
## under the key `side`.
func _image(layer: SaLayer) -> Dictionary:
    var out := {"side": 0}
    for grid: Vector2i in layer.chunks:
        out["side"] = (layer.chunks[grid] as SaChunk).pixel_size()
        @warning_ignore("static_called_on_instance")
        out[grid] = SaExport.get_texture_image_float(layer.get_field(grid))
    return out


## The texel at *pixel* of *image*, read by [method _image].
func _texel_of(image: Dictionary, pixel: Vector2i) -> Color:
    var side: int = image["side"]
    if side == 0:
        return Color.TRANSPARENT
    var grid := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
    if not image.has(grid):
        return Color.TRANSPARENT
    return (image[grid] as Image).get_pixelv(pixel - grid * side)
