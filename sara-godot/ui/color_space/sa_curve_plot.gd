## The highlight roll-off, drawn.
##
## The Display page had a Knee slider and a Desaturation slider and no way to
## see what either did short of painting something above 1.0 and looking at the
## canvas. This is that picture: stored value along the bottom, and how much of
## a colour's chroma the operator leaves up the side.
##
## **Chroma up the side, and not displayed magnitude, is the whole of this
## plot.** The operator makes the magnitude `min(x, 1)`, a straight ramp to
## white and a flat line after it, identical at every knee, so a plot of it
## would have the Knee slider move a dashed mark along a shape that never
## changes and the Desaturation slider change only the line's colour, which
## reads as a graph that has stopped working.
##
## What survives the roll-off is the chroma, so the chroma is what is plotted.
## It is flat at 1 up to the knee, leaves it without a corner, and falls faster the further
## Desaturation is pushed, which is both sliders moving the line rather than the
## furniture around it. The magnitude is still on the picture as a dimmed
## ceiling, labelled, because "white stays white" is a claim worth stating
## rather than leaving implied by an axis nobody drew.
##
## The line is drawn from a transcription of `highlight_rolloff` in
## `shaders/canvas/tonemap.gdshader`, which is the fourth copy of nothing:
## GDScript cannot include a `.gdshader`. `ui/color_space/tests/test_display_curve.gd` samples
## this against the measured table in that shader's own header, so a change to
## either that the other did not follow fails the run.
class_name SaCurvePlot
extends Control

## How far up the x axis goes. A painter stacking passes reaches about 3.0, and
## the shader's own tuning table stops there, so 4.0 leaves a little room past
## the last number anyone measured.
const STORED_MAX := 4.0

## Points along the curve. Enough that the bend at the knee reads as a bend
## rather than as a corner, at any width the Preferences window has.
const SAMPLES := 96

const BASE_HEIGHT := 96.0
const BASE_WIDTH := 240.0
const PADDING := 6.0

const COLOR_FRAME := Color(1.0, 1.0, 1.0, 0.18)
const COLOR_GRID := Color(1.0, 1.0, 1.0, 0.08)
const COLOR_KNEE := Color(1.0, 1.0, 1.0, 0.45)

## The magnitude line, which never moves and must not compete with the one that
## does.
const COLOR_CEILING := Color(1.0, 1.0, 1.0, 0.22)

## What the curve is drawn in before the roll-off touches it. Red because that
## is the highlight a painter notices going white, and because the desaturation
## has the most to say about it.
const COLOR_START := Color(0.95, 0.15, 0.15)

## The width of Khronos PBR Neutral's shoulder, the shader's `KHRONOS_SHOULDER`,
## which the chroma loss is measured by. The shader's header says why.
const KHRONOS_SHOULDER := 0.24

## The shader's slack on the gamut test, `GAMUT_EPSILON`.
const GAMUT_EPSILON := 1e-5

## The shader's F16 slack on the gamut test, `GAMUT_ROUNDING`, a share of the
## colour's largest channel.
const GAMUT_ROUNDING := 2e-3

## The rows of the LMS to linear sRGB matrix, one a channel, as the shader
## writes them.
const _LMS_TO_SRGB_ROWS: Array[Vector3] = [
    Vector3(4.0767416621, -3.3077115913, 0.2309699292),
    Vector3(-1.2684380046, 2.6097574011, -0.3413193965),
    Vector3(-0.0041960863, -0.7034186147, 1.7076147010),
]

var knee: float = 1.0
var desaturation: float = 0.15


func _init() -> void:
    custom_minimum_size = Vector2(SaUI.pxf(BASE_WIDTH), SaUI.pxf(BASE_HEIGHT))
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    mouse_filter = Control.MOUSE_FILTER_PASS


## Both sliders call this, so the picture follows the drag rather than the
## dialog being closed and opened again.
func configure(new_knee: float, new_desaturation: float) -> void:
    knee = new_knee
    desaturation = new_desaturation
    queue_redraw()


## The ceiling, on the peak channel, in linear light.
##
## Twin of `highlight_rolloff` in `shaders/canvas/tonemap.gdshader`. The knee is
## not in it: the magnitude is the identity up to white and white above it, at
## every knee, which is what "white stays white" costs and buys. Under a knee
## above white the peak channel clips to white too, so the blend towards the
## clip leaves it there.
static func rolled_peak(peak: float, knee_value: float) -> float:
    if peak <= minf(knee_value, 1.0):
        return peak
    return minf(peak, 1.0)


## How far Khronos PBR Neutral's shoulder, started at *knee_value*, would have
## pulled *peak* down, which is what the chroma loss is measured by: nothing at
## the knee, growing as the square of how far past it the peak stands, and that
## distance less the shoulder's width once the peak is well past it. The
## shader's `pulled`, in light.
static func pulled_by_the_shoulder(peak: float, knee_value: float) -> float:
    if peak <= knee_value:
        return 0.0
    var past := peak - knee_value
    return past * past / (past + KHRONOS_SHOULDER)


## What a stored grey ends up as on screen: decoded to light, rolled off, and
## encoded again, which is the round trip the canvas shader does per pixel.
##
## Sara feeds the operator decoded values, so a stored 2.0 arrives as linear
## 4.95. That is why the knee is read against stored numbers and why this
## function takes one.
static func displayed_for_stored(stored: float, knee_value: float) -> float:
    var linear := OkhsvConversions.channel_srgb_to_rgb(stored)
    return OkhsvConversions.channel_rgb_to_srgb(rolled_peak(linear, knee_value))


## The colour the curve is drawn in at *stored*: the same red, having lost
## exactly the chroma the setting would take from a red highlight of that value.
##
## The brightness is deliberately not the curve's own y. A stroke whose colour
## tracked the stored value would be almost black at the left of the plot, which
## is where the interesting half of the picture is. What moves is the chroma,
## and it moves by the shader's own `g`, so the stroke goes red to white exactly
## where a painted red highlight would.
##
## The shader finishes by mapping the result back into the display cube, and so
## does this, because the lightness the chroma travels with carries a colour on
## the cube's face out of it: left to the encode's clamp, a stored
## (2, 0.25, 0) came out ten levels off the view's green.
static func rolled_color(stored: float, knee_value: float, desat: float) -> Color:
    var peak := OkhsvConversions.channel_srgb_to_rgb(stored)
    if peak <= knee_value:
        return COLOR_START
    var start := OkhsvConversions.srgb_transfer_function_inv(_vec(COLOR_START))
    return _encode(_given_up(start, peak, knee_value, desat))


## What the view shows for a *stored* sRGB colour with the rolloff on: decoded
## to light, rolled off, mapped into the cube and encoded again, the whole of
## `highlight_rolloff` for an sRGB document at a reference white of one. The
## fourth transcription, and the one a suite holds to the view and the export
## colour by colour.
static func rolled(stored: Color, knee_value: float, desat: float) -> Color:
    var c := OkhsvConversions.srgb_transfer_function_inv(_vec(stored))
    var peak := maxf(c.x, maxf(c.y, c.z))
    var low := minf(c.x, minf(c.y, c.z))
    if peak <= minf(knee_value, 1.0) and low >= -GAMUT_EPSILON:
        return Color(stored.r, stored.g, stored.b)
    if peak <= minf(knee_value, 1.0):
        return _encode(_into_the_cube(SaOklab.from_linear_srgb(c)))
    var new_peak := rolled_peak(peak, knee_value)
    var held := _given_up(c * (new_peak / peak), peak, knee_value, desat)
    var share := held_share(peak, knee_value)
    if share >= 1.0:
        return _encode(held)
    var clipped := c.min(Vector3.ONE)
    if low < -GAMUT_EPSILON:
        clipped = _into_the_cube(SaOklab.from_linear_srgb(clipped))
    return _encode(clipped.lerp(held, share))


## How far a colour of *peak*, in light, has gone from the clip the display
## shows with the roll-off off to the channels' ratios held: under a knee above
## white nothing up to white, a smoothstep of the peak from white to the knee
## and all of it past the knee, and all of it at a knee of 1.0 and below. The shader's
## `smoothstep(1.0, k, peak)`.
static func held_share(peak: float, knee_value: float) -> float:
    if knee_value <= 1.0 or peak >= knee_value:
        return 1.0
    if peak <= 1.0:
        return 0.0
    return smoothstep(1.0, knee_value, peak)


## *c*, its peak already brought to white from *peak*, having lost the chroma
## the setting takes from a highlight of that peak, and mapped into the cube.
## Chroma falls with how far the shoulder would have pulled the peak, and the
## lightness travels to the neutral at the compressed peak, so full
## desaturation lands on white rather than on a grey of the original lightness.
## Only a and b are scaled, so the hue angle never moves.
static func _given_up(c: Vector3, peak: float, knee_value: float, desat: float) -> Vector3:
    var new_peak := rolled_peak(peak, knee_value)
    var lab := SaOklab.from_linear_srgb(c)
    var g := 1.0 - 1.0 / (desat * pulled_by_the_shoulder(peak, knee_value) + 1.0)
    var neutral_l := SaOklab.from_linear_srgb(Vector3(new_peak, new_peak, new_peak)).x
    lab = Vector3(lerpf(lab.x, neutral_l, g), lab.y * (1.0 - g), lab.z * (1.0 - g))
    if minf(c.x, minf(c.y, c.z)) >= -GAMUT_EPSILON:
        lab = _within_half_the_slack(lab)
    return _into_the_cube(lab)


## The shader's `within_half_the_slack`: a colour outside half the gamut test's
## slack has its chroma brought down to where it first leaves the cube widened
## by half the slack, lightness and hue held, so the step to white never carries
## a colour from the cube's face across blue's or yellow's fold. The shader says
## why.
static func _within_half_the_slack(lab: Vector3) -> Vector3:
    var chroma := Vector2(lab.y, lab.z).length()
    if lab.x <= 0.0 or lab.x >= 1.0 or chroma <= 0.0:
        return lab
    var linear := SaOklab.to_linear_srgb(lab)
    var slack := 0.5 * _slack(linear)
    if _inside(linear, slack):
        return lab
    var hue := Vector2(lab.y, lab.z) / chroma
    var k := Vector3(
        0.3963377774 * hue.x + 0.2158037573 * hue.y,
        -0.1055613458 * hue.x - 0.0638541728 * hue.y,
        -0.0894841775 * hue.x - 1.2914855480 * hue.y
    )
    var l3 := lab.x * lab.x * lab.x
    var s := chroma / lab.x
    for row: Vector3 in _LMS_TO_SRGB_ROWS:
        s = minf(s, _widened_exit(row, k, l3, slack))
    var kept := s * lab.x / chroma
    return Vector3(lab.x, lab.y * kept, lab.z * kept)


## The shader's `widened_exit`: the first saturation C / L at which the channel
## of row *w* passes *slack* below black or *slack* above one, along the hue
## whose Oklab to LMS slopes are *k*, at a lightness whose cube is *l3*.
static func _widened_exit(w: Vector3, k: Vector3, l3: float, slack: float) -> float:
    var d2 := 3.0 * w.dot(k)
    var d1 := 3.0 * w.dot(k * k)
    var d0 := w.dot(k * k * k)
    var s := 1e30
    var to_below := _largest_cubic_root(1.0 + slack / l3, d2, d1, d0)
    if to_below > 0.0:
        s = 1.0 / to_below
    var to_above := _largest_cubic_root(minf(1.0 - (1.0 + slack) / l3, -1e-6), d2, d1, d0)
    if to_above > 0.0:
        s = minf(s, 1.0 / to_above)
    return s


## The shader's `largest_cubic_root` of d3 u^3 + d2 u^2 + d1 u + d0: Cardano's
## formula for one real root and the trigonometric form for three, whose first
## is the largest.
static func _largest_cubic_root(d3: float, d2: float, d1: float, d0: float) -> float:
    var a := d2 / d3
    var b := d1 / d3
    var c := d0 / d3
    var p := b - a * a / 3.0
    var q := 2.0 * a * a * a / 27.0 - a * b / 3.0 + c
    var disc := 0.25 * q * q + p * p * p / 27.0
    if disc > 0.0:
        var root := sqrt(disc)
        return _signed_cbrt(-0.5 * q + root) + _signed_cbrt(-0.5 * q - root) - a / 3.0
    if p >= 0.0:
        return -a / 3.0
    var r := sqrt(-p / 3.0)
    var angle := acos(clampf(1.5 * q / (p * r), -1.0, 1.0))
    return 2.0 * r * cos(angle / 3.0) - a / 3.0


static func _signed_cbrt(x: float) -> float:
    return signf(x) * pow(absf(x), 1.0 / 3.0)


## The shader's slack on the gamut test for *linear*, the larger of float's own
## and a share of its largest channel.
static func _slack(linear: Vector3) -> float:
    return maxf(GAMUT_EPSILON, GAMUT_ROUNDING * maxf(absf(linear.x), maxf(absf(linear.y), absf(linear.z))))


## Whether *linear* is inside the cube widened by *slack* on both sides.
static func _inside(linear: Vector3, slack: float) -> bool:
    for i in 3:
        if linear[i] < -slack or linear[i] > 1.0 + slack:
            return false
    return true


## The shader's `gamut_map` by Ottosson's intersection at a fixed lightness:
## chroma down to the most the sRGB cube holds at *lab*'s lightness and hue,
## for a colour the shader's slack does not let through as it is. The shader
## solves the first exit along the chroma axis instead, which is the same place
## everywhere but at blue's fold, and a colour the step to white carried there
## from the cube's face has been brought inside the slack before this.
static func _into_the_cube(lab: Vector3) -> Vector3:
    var linear := SaOklab.to_linear_srgb(lab)
    if _inside(linear, _slack(linear)):
        return linear
    if lab.x <= 0.0:
        return Vector3.ZERO
    var chroma := Vector2(lab.y, lab.z).length()
    if lab.x >= 1.0 or chroma <= 0.0:
        return SaOklab.to_linear_srgb(Vector3(lab.x, 0.0, 0.0))
    var hue := Vector2(lab.y, lab.z) / chroma
    var most := OkhslConversions.gamut_chroma(hue.x, hue.y, lab.x)
    if most >= chroma:
        return linear
    return SaOklab.to_linear_srgb(Vector3(lab.x, hue.x * most, hue.y * most))


## How much of a colour's chroma the roll-off leaves at *stored*, 1 for none
## taken and 0 for a colour driven all the way to neutral.
##
## The third transcription of `highlight_rolloff` and the one the picture is now
## drawn from: `g = 1 - 1 / (desat * pulled + 1)` is the shader's own line, with
## `pulled` how far the shoulder would have pulled the peak, and what is left is
## `1 - g`. At and below the knee nothing is taken, and just past it almost
## nothing, which is why the curve is flat there and leaves the top without a
## corner rather than bending at the origin.
##
## Taking the stored value rather than the linear one for the same reason
## `displayed_for_stored` does: the sliders read against stored numbers because
## that is what a painter types, and the operator sees light.
static func chroma_left(stored: float, knee_value: float, desat: float) -> float:
    var peak := OkhsvConversions.channel_srgb_to_rgb(stored)
    return 1.0 / (desat * pulled_by_the_shoulder(peak, knee_value) + 1.0)


static func _vec(color: Color) -> Vector3:
    return Vector3(color.r, color.g, color.b)


static func _encode(linear: Vector3) -> Color:
    var encoded := OkhsvConversions.srgb_transfer_function(linear.clamp(Vector3.ZERO, Vector3.ONE))
    return Color(encoded.x, encoded.y, encoded.z)


func _draw() -> void:
    var plot := Rect2(Vector2(SaUI.pxf(PADDING), SaUI.pxf(PADDING)), size - Vector2(SaUI.pxf(PADDING), SaUI.pxf(PADDING)) * 2.0)
    if plot.size.x <= 1.0 or plot.size.y <= 1.0:
        return
    _draw_grid(plot)
    _draw_ceiling(plot)
    _draw_knee(plot)
    _draw_held(plot)
    _draw_curve(plot)


## The frame, and a line at each whole stored value, so the bend can be read
## against a number rather than only against the line beside it.
func _draw_grid(plot: Rect2) -> void:
    draw_rect(plot, COLOR_FRAME, false, 1.0)
    for step in range(1, int(STORED_MAX)):
        var x := plot.position.x + plot.size.x * (float(step) / STORED_MAX)
        draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), COLOR_GRID, 1.0)


## Where the knee stands, dashed, from the bottom of the plot to the line. The
## height of the line says nothing about the knee, so without this mark the
## slider moves and the picture holds still.
func _draw_knee(plot: Rect2) -> void:
    var stored := OkhsvConversions.channel_rgb_to_srgb(knee)
    _draw_dashed(_point(plot, stored, 0.0), _point(plot, stored, 1.0))


## The magnitude, dimmed and behind everything: a ramp to white and flat after
## it, at every knee. It is on the picture because "white stays white" is the
## property the operator was rewritten for, and a claim nobody draws is a claim
## the next reader has to take on trust. It is dim because it never moves, and a
## line that never moves competing with one that does is what made the old
## picture unreadable.
func _draw_ceiling(plot: Rect2) -> void:
    var points := PackedVector2Array()
    for i in SAMPLES + 1:
        var stored := STORED_MAX * float(i) / float(SAMPLES)
        points.append(_point(plot, stored, displayed_for_stored(stored, knee)))
    draw_polyline(points, COLOR_CEILING, 1.0, true)


## How much of the channels' ratios the roll-off holds, from none at white to
## all of them at the knee, drawn in the knee's colour and only under a knee
## above white: there the colour starts at the clip the display shows with the
## roll-off off and reaches the held ratios at the knee. Under a knee of 1.0 and
## below it would be a step at white that says nothing the dashed mark does not.
func _draw_held(plot: Rect2) -> void:
    if knee <= 1.0:
        return
    var points := PackedVector2Array()
    for i in SAMPLES + 1:
        var stored := STORED_MAX * float(i) / float(SAMPLES)
        points.append(_point(plot, stored, held_share(OkhsvConversions.channel_srgb_to_rgb(stored), knee)))
    draw_polyline(points, COLOR_KNEE, 1.0, true)


## The chroma that survives, in the colour a red highlight of that value comes
## out as. Both sliders move this line: the Knee moves where it leaves the top
## and Desaturation moves how steeply it falls after that.
func _draw_curve(plot: Rect2) -> void:
    var points := PackedVector2Array()
    var colors := PackedColorArray()
    for i in SAMPLES + 1:
        var stored := STORED_MAX * float(i) / float(SAMPLES)
        points.append(_point(plot, stored, chroma_left(stored, knee, desaturation)))
        colors.append(rolled_color(stored, knee, desaturation))
    draw_polyline_colors(points, colors, 2.0, true)


## The sampled line, for a state dump: what a capture reads instead of counting
## pixels in a screenshot of a graph.
func curve_report() -> Dictionary:
    var samples: Array = []
    for stored: float in [0.0, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0]:
        (
            samples
            . append(
                {
                    "stored": stored,
                    "chroma_left": snappedf(chroma_left(stored, knee, desaturation), 0.0001),
                    "displayed": snappedf(displayed_for_stored(stored, knee), 0.0001),
                    "held": snappedf(held_share(OkhsvConversions.channel_srgb_to_rgb(stored), knee), 0.0001),
                }
            )
        )
    return {
        "knee": snappedf(knee, 0.0001),
        "desaturation": snappedf(desaturation, 0.0001),
        "knee_at_stored": snappedf(OkhsvConversions.channel_rgb_to_srgb(knee), 0.0001),
        "samples": samples,
    }


## Stored value along the bottom and a fraction up the side, to a pixel inside
## the plot. Both axes run 0 to 1 up the side: the chroma left is a fraction by
## construction and the displayed magnitude cannot pass white.
func _point(plot: Rect2, stored: float, fraction: float) -> Vector2:
    var x := plot.position.x + plot.size.x * clampf(stored / STORED_MAX, 0.0, 1.0)
    var y := plot.end.y - plot.size.y * clampf(fraction, 0.0, 1.0)
    return Vector2(x, y)


func _draw_dashed(from: Vector2, to: Vector2) -> void:
    draw_dashed_line(from, to, COLOR_KNEE, 1.0, SaUI.pxf(4.0))
