## Bristle strands differ in width, softness and tone, as the hairs of a loaded
## brush do, and the colour's hue stays the painter's.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Bristle Flat as it ships less its radius taper, so the body is one width,
## paints one level stroke at each press of [constant PRESSURES] in a mid
## brown. Every [constant STEP] pixels along the body a column is read across
## it, inside [constant BODY] of the half-width, and each run of texels painted
## at least [constant PAINTED] is a strand, or strands that merged. Its width is
## the run's length, its softness the texels its alpha takes to fall from three
## quarters of the run's peak to a quarter, read on each side and between
## texels, and its tone the mean luminance of its painted texels. The same
## strand is found again [constant ALONG] pixels on, as the run there that
## holds this one's middle, so its width and tone can be read at two places.
##
## **The bounds were set after the figures were read**, on the field before
## the strands drew their own looks and after. Before, at 0.8 and 0.4, the
## widths' spread was 0.733 and 0.384 of their mean, the softness's 0.106 and
## 0.063 with 0.028 and 0.154 of the edges off a tenth of the mean, 0.304 and
## none of the strands changed width along [constant ALONG] pixels, and every
## strand had the colour's own tone. After, the widths' spread is 0.964 and
## 0.526, the softness's 0.292 and 0.568 with 0.756 and 0.933 of the edges off
## a tenth, 0.396 and 0.128 of the strands change width along, and the tone
## parts strands by 0.028 and 0.044 of its mean across a column and 0.015 and
## 0.018 along one, with the hue unmoved to a thousandth of a degree.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

const PRESET := "Bristle Flat"
## The presses each stroke is played at, a firm one and a light one.
const PRESSURES: Array[float] = [0.8, 0.4]
## The canvas, the tip's radius, the stroke's ends, the gap between two samples
## in pixels and in milliseconds, and the stroke's seed.
const CANVAS := Vector2i(1024, 256)
const RADIUS := 30.0
const FROM := Vector2(60.0, 128.0)
const TO := Vector2(964.0, 128.0)
const SPACING := 4.0
const SAMPLE_MS := 8.0
const SEED := 7
## How many radii from each end the body is read from, the share of the
## half-width read across it, the gap between two columns, how far along a
## strand is found again, and the alpha a texel holds to be painted.
const END_MARGIN := 2.0
const BODY := 0.8
const STEP := 6
const ALONG := 120
const PAINTED := 0.5
## A mid brown, so a lighter and a darker strand both show and its hue reads.
const COLOUR := Color(0.55, 0.32, 0.18, 1.0)
## The least share of the widths further than a tenth from their mean, and the
## least spread of them as a share of the mean.
const WIDTHS_OFF := 0.5
const WIDTH_SPREAD := 0.45
## The least share of the edges further than a tenth from their mean
## softness, and the least spread of them as a share of the mean.
const SOFT_OFF := 0.4
const SOFT_SPREAD := 0.2
## The least share of the strands whose width changes along [constant ALONG].
const WIDTH_MOVES := 0.08
## The least mean spread of the tone across a column, and of its change along
## a strand, each as a share of the stroke's mean tone.
const TONE_ACROSS := 0.01
const TONE_ALONG := 0.008
## The most a painted texel's hue may lie from the colour's, in degrees.
const HUE := 0.5

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
var _albedo: Dictionary = {}


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)


func after_each() -> void:
    _brush = null
    _albedo.clear()
    Fixtures.teardown(_surface)
    _surface = null


func test_a_strand_differs_from_its_neighbours_in_width_and_softness_and_along_itself_in_width() -> void:
    for pressure: float in PRESSURES:
        var read := _measure(pressure)
        assert_true(
            read["widths_off"] >= WIDTHS_OFF,
            (
                "At %.1f %.3f of the strands' widths lie off a tenth of their mean, at least %.2f"
                % [pressure, read["widths_off"], WIDTHS_OFF]
            )
        )
        assert_true(
            read["width_spread"] >= WIDTH_SPREAD,
            "At %.1f the widths spread by %.3f of their mean, at least %.2f" % [pressure, read["width_spread"], WIDTH_SPREAD]
        )
        assert_true(
            read["soft_off"] >= SOFT_OFF,
            (
                "At %.1f %.3f of the edges' softness lies off a tenth of its mean, at least %.2f"
                % [pressure, read["soft_off"], SOFT_OFF]
            )
        )
        assert_true(
            read["soft_spread"] >= SOFT_SPREAD,
            "At %.1f the softness spreads by %.3f of its mean, at least %.2f" % [pressure, read["soft_spread"], SOFT_SPREAD]
        )
        assert_true(
            read["width_moves"] >= WIDTH_MOVES,
            (
                "At %.1f %.3f of the strands change width along %d pixels, at least %.2f"
                % [pressure, read["width_moves"], ALONG, WIDTH_MOVES]
            )
        )


func test_a_strand_is_lighter_or_darker_than_its_neighbours_and_along_itself_and_keeps_the_hue() -> void:
    for pressure: float in PRESSURES:
        var read := _measure(pressure)
        assert_true(
            read["tone_across"] >= TONE_ACROSS,
            (
                "At %.1f the tone parts the strands of a column by %.4f of its mean, at least %.3f"
                % [pressure, read["tone_across"], TONE_ACROSS]
            )
        )
        assert_true(
            read["tone_along"] >= TONE_ALONG,
            (
                "At %.1f a strand's tone changes along it by %.4f of the mean, at least %.3f"
                % [pressure, read["tone_along"], TONE_ALONG]
            )
        )
        assert_true(
            read["hue"] <= HUE,
            (
                "At %.1f no painted texel's hue lies more than %.1f degrees off the colour's, the most is %.3f"
                % [pressure, HUE, read["hue"]]
            )
        )


## Plays the stroke at *pressure* on a fresh canvas and reads its figures.
func _measure(pressure: float) -> Dictionary:
    _albedo.clear()
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    _use()
    _stroke(pressure)
    var widths: Array[float] = []
    var softnesses: Array[float] = []
    var width_moves: Array[float] = []
    var tone_moves: Array[float] = []
    var tone_spreads: Array[float] = []
    var mean_tones: Array[float] = []
    var worst_hue := 0.0
    var first := int(FROM.x + END_MARGIN * RADIUS)
    var last := int(TO.x - END_MARGIN * RADIUS) - ALONG
    for x in range(first, last, STEP):
        var runs := _runs(x)
        var later := _runs(x + ALONG)
        var tones: Array[float] = []
        for run: Dictionary in runs:
            widths.append(run["width"])
            softnesses.append_array(run["soft"])
            tones.append(run["tone"])
            mean_tones.append(run["tone"])
            worst_hue = maxf(worst_hue, run["hue"])
            var middle: float = run["middle"]
            for other: Dictionary in later:
                if middle >= other["from"] and middle <= other["to"]:
                    width_moves.append(absf(other["width"] - run["width"]) / maxf(run["width"], 1.0))
                    tone_moves.append(absf(other["tone"] - run["tone"]))
        if tones.size() > 1:
            tone_spreads.append(_spread(tones))
    assert_true(
        widths.size() > 20 and width_moves.size() > 20,
        "At %.1f the body holds %d strands, %d found again along" % [pressure, widths.size(), width_moves.size()]
    )
    var mean_tone := maxf(_mean(mean_tones), 1e-6)
    var read := {
        "widths_off": _off_a_tenth(widths),
        "width_spread": _spread(widths) / maxf(_mean(widths), 1e-6),
        "soft_off": _off_a_tenth(softnesses),
        "soft_spread": _spread(softnesses) / maxf(_mean(softnesses), 1e-6),
        "width_moves": _share_above(width_moves, 0.001),
        "tone_across": _mean(tone_spreads) / mean_tone,
        "tone_along": _mean(tone_moves) / mean_tone,
        "hue": worst_hue,
    }
    print(
        (
            "Strands at %.1f: %d runs, widths mean %.2f spread %.3f, off a tenth %.3f"
            % [pressure, widths.size(), _mean(widths), read["width_spread"], read["widths_off"]]
        )
    )
    print(
        (
            "Strands at %.1f: %d edges, softness mean %.3f spread %.3f, off a tenth %.3f"
            % [pressure, softnesses.size(), _mean(softnesses), read["soft_spread"], read["soft_off"]]
        )
    )
    print(
        (
            "Strands at %.1f: %d pairs along, width moves %.3f, share moved %.3f"
            % [pressure, width_moves.size(), _mean(width_moves), read["width_moves"]]
        )
    )
    print(
        (
            "Strands at %.1f: tone mean %.4f, across %.4f, along %.4f, hue at most %.3f degrees"
            % [pressure, mean_tone, read["tone_across"], read["tone_along"], worst_hue]
        )
    )
    return read


## The runs of painted texels across the body at column *x*, each with its
## first and last row, its middle, width, softness on each side it falls, tone
## and its worst hue against [constant COLOUR], in degrees.
func _runs(x: int) -> Array[Dictionary]:
    var reach := int(RADIUS * BODY)
    var top := int(FROM.y) - reach
    var bottom := int(FROM.y) + reach
    var alphas: Array[float] = []
    var texels: Array[Color] = []
    for y in range(top, bottom + 1):
        var texel := _texel(Vector2i(x, y))
        texels.append(texel)
        alphas.append(texel.a)
    var runs: Array[Dictionary] = []
    var at := 0
    while at < alphas.size():
        if alphas[at] < PAINTED:
            at += 1
            continue
        var start := at
        while at < alphas.size() and alphas[at] >= PAINTED:
            at += 1
        var end := at - 1
        if start == 0 or at >= alphas.size():
            continue
        var peak := 0.0
        var luminance := 0.0
        var hue := 0.0
        for i in range(start, end + 1):
            peak = maxf(peak, alphas[i])
            var texel: Color = texels[i]
            luminance += 0.2126 * texel.r + 0.7152 * texel.g + 0.0722 * texel.b
            hue = maxf(hue, _hue_off(texel))
        var soft: Array[float] = []
        for side: int in [-1, 1]:
            var edge := _softness(alphas, start if side < 0 else end, side, peak)
            if edge >= 0.0:
                soft.append(edge)
        (
            runs
            . append(
                {
                    "from": float(top + start),
                    "to": float(top + end),
                    "middle": top + (start + end) * 0.5,
                    "width": float(end - start + 1),
                    "soft": soft,
                    "tone": luminance / (end - start + 1),
                    "hue": hue,
                }
            )
        )
    return runs


## The texels the alpha takes to fall from three quarters of *peak* to a
## quarter, going out of a run from its *edge* row in the direction *side*,
## read between texels. Less than nought when it rises again first or the
## column ends.
func _softness(alphas: Array[float], edge: int, side: int, peak: float) -> float:
    var high := 0.75 * peak
    var low := 0.25 * peak
    var inner := edge
    while inner - side >= 0 and inner - side < alphas.size() and alphas[inner] < high and alphas[inner - side] > alphas[inner]:
        inner -= side
    if alphas[inner] < high:
        return -1.0
    var crossed_high := -1.0
    var at := inner
    while at + side >= 0 and at + side < alphas.size():
        var here := alphas[at]
        var there := alphas[at + side]
        if there > here + 0.02:
            return -1.0
        if crossed_high < 0.0 and there < high:
            crossed_high = absf(at - inner) + (here - high) / maxf(here - there, 1e-6)
        if there < low:
            var crossed_low := absf(at - inner) + (here - low) / maxf(here - there, 1e-6)
            return crossed_low - crossed_high
        at += side
    return -1.0


## How far *texel*'s hue lies from [constant COLOUR]'s, in degrees.
func _hue_off(texel: Color) -> float:
    var own := Color(texel.r, texel.g, texel.b)
    var off := absf(own.h - COLOUR.h) * 360.0
    return minf(off, 360.0 - off)


func _mean(values: Array[float]) -> float:
    if values.is_empty():
        return 0.0
    var total := 0.0
    for value: float in values:
        total += value
    return total / values.size()


func _spread(values: Array[float]) -> float:
    var mean := _mean(values)
    var total := 0.0
    for value: float in values:
        total += (value - mean) * (value - mean)
    return sqrt(total / maxi(values.size(), 1))


## The share of *values* further than a tenth of their mean from it.
func _off_a_tenth(values: Array[float]) -> float:
    var mean := _mean(values)
    return _share_above(values.map(func(value: float) -> float: return absf(value - mean) / mean), 0.1)


func _share_above(values: Array, bound: float) -> float:
    if values.is_empty():
        return 0.0
    var count := 0
    for value: float in values:
        if value > bound:
            count += 1
    return float(count) / values.size()


## [constant PRESET] as it ships without its radius taper, at
## [constant RADIUS] and [constant SEED], in [constant COLOUR].
func _use() -> void:
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = SEED
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == PRESET:
            var untapered := entry.duplicate(true)
            (untapered["pressure"] as Dictionary).erase("radius")
            _brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, untapered)
    _brush.settings.color = COLOUR
    _brush.settings.radius = RADIUS / mini(CANVAS.x, CANVAS.y)


## The level stroke at *pressure* all the way.
func _stroke(pressure: float) -> void:
    var clock := 1000.0
    _brush.begin_stroke(FROM, pressure, Vector2.ZERO, clock)
    var steps := ceili(FROM.distance_to(TO) / SPACING)
    for i in range(1, steps + 1):
        clock += SAMPLE_MS
        _brush.add_sample(FROM.lerp(TO, float(i) / steps), pressure, Vector2.ZERO, clock)
    _brush.end_stroke()


## The active layer's texel at *pixel*.
func _texel(pixel: Vector2i) -> Color:
    var layer := _surface.easel.document.active_layer
    for grid: Vector2i in layer.chunks:
        var side := (layer.chunks[grid] as SaChunk).pixel_size()
        var here := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
        if not layer.chunks.has(here):
            return Color.TRANSPARENT
        if not _albedo.has(here):
            @warning_ignore("static_called_on_instance")
            _albedo[here] = SaExport.get_texture_image_float(layer.get_field(here))
        return (_albedo[here] as Image).get_pixelv(pixel - here * side)
    return Color.TRANSPARENT
