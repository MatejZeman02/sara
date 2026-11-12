## Texture Tone and Strand Softness, two rows of the Look page, each make a
## change a painter can see between the ends of its range.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Texture Tone: Firm Fill as it ships less its radius taper paints one level
## stroke at [constant PRESSURE] at a Texture Tone of nought and of one, and the
## spread of the Oklab lightness over the painted texels of its body is read
## the way the door's `measure` step reads it, every texel with paint counted
## once. Strand Softness: Bristle Flat paints the same stroke at a Strand
## Softness of [constant SHARP] and of [constant SOFT], every column across the
## body is cut into strands, each a run of texels painted at least
## [constant PAINTED], and each strand's edge is the texels its alpha takes to
## fall from nine tenths of its peak to a tenth, the mean edge as a share of
## the strands' mean width, under a tenth at the sharp end and at least a third
## at the soft end, on a larger stroke where a strand is wide enough in texels
## for a tenth of it to read. The painted share and the lightness spread of the
## body are read at both ends as well. The five presets that lay a tone keep
## the lightness spread they laid before the range was widened, and a brush
## stored at format five is carried onto the new ranges.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

## The press every stroke is played at.
const PRESSURE := 0.5
## The canvas, the tip's radius, the stroke's ends, the gap between two samples
## in pixels and in milliseconds, and the stroke's seed.
const CANVAS := Vector2i(1024, 256)
const RADIUS := 30.0
const FROM := Vector2(60.0, 128.0)
const TO := Vector2(964.0, 128.0)
const SPACING := 4.0
const SAMPLE_MS := 8.0
const SEED := 7
## Strand Softness is read on a canvas twice as tall at twice the radius, so a
## strand is about ten texels wide and an edge as sharp as a texel can read
## under a tenth of it. At 30 pixels a strand is under five texels wide and a
## one texel step already reads as 0.17 of it.
const STRAND_CANVAS := Vector2i(1280, 512)
const STRAND_RADIUS := 60.0
const STRAND_FROM := Vector2(60.0, 256.0)
const STRAND_TO := Vector2(1220.0, 256.0)
## How many radii from each end the body is read from, the share of the
## half-width read across it, the gap between two columns read, and the share
## of a run's peak a texel holds to be in the run.
const END_MARGIN := 2.0
const BODY := 0.8
const STEP := 6
const PAINTED := 0.5
## A mid brown, so a lighter and a darker texel both show.
const COLOUR := Color(0.55, 0.32, 0.18, 1.0)
## Texture Tone's two ends and the lightness spread each must reach or stay
## under.
const TONE_FULL_SPREAD := 0.12
const TONE_NONE_SPREAD := 0.02
## Strand Softness's two ends, how many times wider the soft end's edge must be
## as a share of its strand's width, and the least relative change of the
## painted share and of the spread between them.
const SHARP := 0.01
const SOFT := 1.99
const EDGE_RATIO := 3.0
const SOFT_CHANGE := 0.05
## The edge as a share of its strand's width, at most at the sharp end and at
## least at the soft end.
const SHARP_EDGE := 0.1
const SOFT_EDGE := 1.0 / 3.0
## The lightness spread each preset with a Texture Tone laid at its own tone
## before the row's range was widened, read by this suite on the tree before,
## and how far it may move. Graphite Pencil's moved the most, 0.0017.
const BEFORE: Dictionary[String, float] = {
    "Firm Fill": 0.0406,
    "Smeary Flat": 0.0229,
    "Sea Sponge": 0.0604,
    "Ribbon Pen": 0.0288,
    "Graphite Pencil": 0.0347,
}
const KEPT := 0.003

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
var _albedo: Dictionary = {}
var _canvas := CANVAS
var _radius := RADIUS
var _from := FROM
var _to := TO


func before_each() -> void:
    _canvas = CANVAS
    _radius = RADIUS
    _from = FROM
    _to = TO
    _surface = Fixtures.make_surface(CANVAS)


func after_each() -> void:
    _brush = null
    _albedo.clear()
    Fixtures.teardown(_surface)
    _surface = null


func test_firm_fill_at_full_texture_tone_spreads_its_lightness_and_at_none_keeps_it_flat() -> void:
    var none := _body("Firm Fill", &"texture_tone", 0.0)
    var full := _body("Firm Fill", &"texture_tone", 1.0)
    print(
        (
            "Texture Tone 0: painted %.3f, spread %.4f, Texture Tone 1: painted %.3f, spread %.4f"
            % [none["painted"], none["spread"], full["painted"], full["spread"]]
        )
    )
    assert_true(
        full["spread"] >= TONE_FULL_SPREAD,
        "At Texture Tone 1 the lightness spreads by %.4f, at least %.2f" % [full["spread"], TONE_FULL_SPREAD]
    )
    assert_true(
        none["spread"] <= TONE_NONE_SPREAD,
        "At Texture Tone 0 the lightness spreads by %.4f, at most %.2f" % [none["spread"], TONE_NONE_SPREAD]
    )


func test_bristle_flat_at_its_softest_strands_fades_their_edges_over_three_times_the_width() -> void:
    _canvas = STRAND_CANVAS
    _radius = STRAND_RADIUS
    _from = STRAND_FROM
    _to = STRAND_TO
    var sharp := _body("Bristle Flat", &"strand_softness", SHARP)
    var sharp_edge := _edges()
    var soft := _body("Bristle Flat", &"strand_softness", SOFT)
    var soft_edge := _edges()
    print(
        (
            "Strand Softness %.2f: painted %.3f, spread %.4f, edge %.3f of %d strands"
            % [SHARP, sharp["painted"], sharp["spread"], sharp_edge["edge"], sharp_edge["strands"]]
        )
    )
    print(
        (
            "Strand Softness %.2f: painted %.3f, spread %.4f, edge %.3f of %d strands"
            % [SOFT, soft["painted"], soft["spread"], soft_edge["edge"], soft_edge["strands"]]
        )
    )
    assert_true(
        sharp_edge["strands"] > 20 and soft_edge["strands"] > 20,
        "The body holds %d and %d strands" % [sharp_edge["strands"], soft_edge["strands"]]
    )
    assert_true(
        sharp_edge["edge"] < SHARP_EDGE,
        "The sharpest strands' edge is %.3f of their width, under %.2f" % [sharp_edge["edge"], SHARP_EDGE]
    )
    assert_true(
        soft_edge["edge"] >= SOFT_EDGE,
        "The softest strands' edge is %.3f of their width, at least %.3f" % [soft_edge["edge"], SOFT_EDGE]
    )
    assert_true(
        soft_edge["edge"] >= EDGE_RATIO * sharp_edge["edge"],
        (
            "The softest strands' edge is %.3f of their width against %.3f, at least %.1f times"
            % [soft_edge["edge"], sharp_edge["edge"], EDGE_RATIO]
        )
    )
    var painted := absf(soft["painted"] - sharp["painted"]) / maxf(sharp["painted"], 1e-6)
    var spread := absf(soft["spread"] - sharp["spread"]) / maxf(sharp["spread"], 1e-6)
    assert_true(
        painted >= SOFT_CHANGE,
        "The painted share moves by %.3f of itself between the ends, at least %.2f" % [painted, SOFT_CHANGE]
    )
    assert_true(
        spread >= SOFT_CHANGE,
        "The lightness spread moves by %.3f of itself between the ends, at least %.2f" % [spread, SOFT_CHANGE]
    )


func test_each_flat_tip_style_preset_keeps_the_lightness_spread_its_tone_laid_before_the_wider_range() -> void:
    for preset: String in BEFORE:
        _use(preset)
        var tone: float = _brush.settings.texture_tone
        var read := _body(preset, &"texture_tone", tone)
        print("%s at Texture Tone %.3f spreads by %.4f, %.4f before" % [preset, tone, read["spread"], BEFORE[preset]])
        assert_true(
            absf(read["spread"] - BEFORE[preset]) <= KEPT,
            "%s spreads by %.4f, within %.3f of the %.4f it spread by before" % [preset, read["spread"], KEPT, BEFORE[preset]]
        )


func test_a_brush_stored_at_format_five_carries_its_tone_and_softness_onto_the_wider_ranges() -> void:
    var stored := NoiseBrushSettingsScript.new()
    stored.format_version = 5
    stored.texture_field = "grain"
    stored.texture_channels = 2
    stored.grain_contrast = 1.5
    stored.texture_relief = 1.0
    stored.texture_tone = 0.6
    stored.strand_softness = 1.6
    assert_true(stored.migrate(), "A brush of format five is carried")
    assert_almost_eq(
        stored.texture_tone, 0.2424, 0.001, "Firm Fill's tone of 0.6 is carried to the one that spreads its lightness as far"
    )
    assert_almost_eq(stored.strand_softness, 0.8, 1e-6, "A softness of 1.6 is the same draws at 0.8")
    var rest := NoiseBrushSettingsScript.new()
    rest.format_version = 5
    assert_true(rest.migrate(), "A brush of format five that kept the rest is carried")
    assert_almost_eq(rest.strand_softness, 0.5, 1e-6, "and the rest it held, which its file never wrote, is the rest of now")
    assert_almost_eq(rest.texture_tone, 0.0, 1e-6, "with no tone still none")


## Plays *preset* with *key* at *value* and reads the body's painted share, the
## share of its texels with paint at all, and the spread of their lightness.
func _body(preset: String, key: StringName, value: float) -> Dictionary:
    _albedo.clear()
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(_canvas)
    _use(preset)
    _brush.settings.set(key, value)
    _stroke()
    var space := SaColorSpace.srgb()
    var lightness: Array[float] = []
    var texels := 0
    var reach := int(_radius * BODY)
    for x in range(int(_from.x + END_MARGIN * _radius), int(_to.x - END_MARGIN * _radius), STEP):
        for y in range(int(_from.y) - reach, int(_from.y) + reach + 1):
            texels += 1
            var texel := _texel(Vector2i(x, y))
            if texel.a <= 0.0:
                continue
            var linear := Vector3(space.transfer.decode(texel.r), space.transfer.decode(texel.g), space.transfer.decode(texel.b))
            lightness.append(SaOklab.from_linear_srgb(linear).x)
    var mean := 0.0
    for l: float in lightness:
        mean += l
    mean /= maxi(lightness.size(), 1)
    var deviation := 0.0
    for l: float in lightness:
        deviation += (l - mean) * (l - mean)
    return {"painted": float(lightness.size()) / maxi(texels, 1), "spread": sqrt(deviation / maxi(lightness.size(), 1))}


## The strands' edges in the stroke just painted, all of them together over
## all their widths, so a run of one texel, whose edge is near a texel whatever
## the softness, weighs no more than its width, and how many strands it was
## read over.
func _edges() -> Dictionary:
    var edges := 0.0
    var sides := 0
    var widths := 0.0
    var strands := 0
    var reach := int(_radius * BODY)
    for x in range(int(_from.x + END_MARGIN * _radius), int(_to.x - END_MARGIN * _radius), STEP):
        var alphas: Array[float] = []
        for y in range(int(_from.y) - reach, int(_from.y) + reach + 1):
            alphas.append(_texel(Vector2i(x, y)).a)
        for run: Vector2i in _runs(alphas):
            var peak := 0.0
            for i in range(run.x, run.y + 1):
                peak = maxf(peak, alphas[i])
            var read := 0
            for side: int in [-1, 1]:
                var edge := _fall(alphas, run.x if side < 0 else run.y, side, peak)
                if edge >= 0.0:
                    edges += edge
                    read += 1
            if read == 0:
                continue
            sides += read
            strands += 1
            widths += float(run.y - run.x + 1)
    return {"edge": (edges / maxi(sides, 1)) / maxf(widths / maxi(strands, 1), 1e-6), "strands": strands}


## The runs of *alphas* holding an alpha of at least [constant PAINTED],
## each from its first index to its last, leaving out one the column's ends cut.
func _runs(alphas: Array[float]) -> Array[Vector2i]:
    var runs: Array[Vector2i] = []
    var at := 0
    while at < alphas.size():
        if alphas[at] < PAINTED:
            at += 1
            continue
        var start := at
        while at < alphas.size() and alphas[at] >= PAINTED:
            at += 1
        if start > 0 and at < alphas.size():
            runs.append(Vector2i(start, at - 1))
    return runs


## The texels the alpha takes to fall from nine tenths of *peak* to a tenth,
## out of a run from its *edge* row in the direction *side*, read between
## texels from the run's own peak inwards. Less than nought when it rises again
## first or the column ends.
func _fall(alphas: Array[float], edge: int, side: int, peak: float) -> float:
    var high := 0.9 * peak
    var low := 0.1 * peak
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


## *preset* as it ships without its radius taper, at the radius in hand and
## [constant SEED], in [constant COLOUR].
func _use(preset: String) -> void:
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = SEED
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == preset:
            var untapered := entry.duplicate(true)
            (untapered["pressure"] as Dictionary).erase("radius")
            _brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, untapered)
    _brush.settings.color = COLOUR
    _brush.settings.radius = _radius / mini(_canvas.x, _canvas.y)


## The level stroke at [constant PRESSURE] all the way.
func _stroke() -> void:
    var clock := 1000.0
    _brush.begin_stroke(_from, PRESSURE, Vector2.ZERO, clock)
    var steps := ceili(_from.distance_to(_to) / SPACING)
    for i in range(1, steps + 1):
        clock += SAMPLE_MS
        _brush.add_sample(_from.lerp(_to, float(i) / steps), PRESSURE, Vector2.ZERO, clock)
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
