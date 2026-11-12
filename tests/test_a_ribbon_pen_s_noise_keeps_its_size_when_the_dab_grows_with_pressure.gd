## A ribbon pen's noise keeps its size when the dab grows with pressure.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Ribbon Pen's radius follows the pressure, and its stripes were cells of the
## dab's own width, so a harder press drew the same ten stripes wider. Now a
## strand is a cell of the brush's width at its Size row, the width a full
## press lays, in pixels, and a narrower dab holds fewer of them.
##
## **Ribbon Pen.** A level stroke at [constant LIGHT] and one at
## [constant HARD], each on a fresh canvas under each of [constant SEEDS], as
## the preset ships in a mid brown. Ribbon Pen paints its body whole and its
## stripes are the strands' tones, so every [constant STEP] pixels along the
## body a column is read across it, inside [constant BODY] of its painted half
## width, and a stripe is a run of texels whose lightness steps less than
## [constant STRIPE_STEP] from one to the next. The stripe width is the texels
## read over the stripes, and the count the painted width over the stripe
## width. Before the change the stripes were 3.10 pixels wide at 0.3 and 4.75
## at 0.9, 53 percent apart, and after they are 5.12 and 5.65, 10 percent
## apart, 15.4 and 31.2 of them across. The reading leans on the step: at half
## of it the two widths after are 3.86 and 4.46, 15.4 percent apart, and at
## twice it 9.95 and 10.11.
##
## **Bristle Flat.** A level stroke at a full press, the press a scripted
## stroke sends and the one the Size row is the width of, as the preset ships,
## read the same way, lays [constant BRISTLE_BEFORE] stripes across, the count
## the tree before the change gave, within [constant BRISTLE_OFF]. A dab at the
## Size row lays its strands where it laid them before to the last bit, so the
## count after is the same 16.65.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

## The canvas, the tip's radius at a full press, the stroke's ends, the gap
## between two samples in pixels and in milliseconds, and the stroke's seed.
const CANVAS := Vector2i(1280, 512)
const RADIUS := 120.0
const FROM := Vector2(100.0, 256.0)
const TO := Vector2(1180.0, 256.0)
const SPACING := 4.0
const SAMPLE_MS := 8.0
const SEEDS: Array[int] = [7, 8, 9]
const LIGHT := 0.3
const HARD := 0.9
const FULL := 1.0
## A mid brown, so a lighter and a darker strand both show.
const COLOUR := Color(0.55, 0.32, 0.18, 1.0)
## How many full radii from each end the body is read from, the share of the
## painted half width read across it, the gap between two columns, and the
## alpha a texel holds to be painted.
const END_MARGIN := 2.0
const BODY := 0.8
const STEP := 4
const PAINTED := 0.5
## The least step in lightness between two texels that parts two stripes, a
## tenth of the strands' tone in the mid brown.
const STRIPE_STEP := 0.004
## The most the two stripe widths may differ, as a share of the smaller.
const WIDTH_MATCH := 0.15
## The mean runs of paint a column of Bristle Flat held at a full press
## before the change, and how far from it a count may lie.
const BRISTLE_BEFORE := 16.65
const BRISTLE_OFF := 1.0

var _surface: SaSurface = null
var _albedo: Dictionary = {}


func after_each() -> void:
    _albedo.clear()
    Fixtures.teardown(_surface)
    _surface = null


func test_a_harder_press_lays_more_ribbon_stripes_of_the_same_width() -> void:
    var light := _stripes("Ribbon Pen", LIGHT)
    var hard := _stripes("Ribbon Pen", HARD)
    var off := absf(hard["width"] - light["width"]) / maxf(minf(hard["width"], light["width"]), 1e-6)
    assert_true(
        off <= WIDTH_MATCH,
        (
            "the stripes are %.2f pixels wide at %.1f and %.2f at %.1f, %.3f apart, at most %.2f"
            % [light["width"], LIGHT, hard["width"], HARD, off, WIDTH_MATCH]
        )
    )
    assert_true(
        hard["count"] > light["count"],
        "and %.1f stripes cross the dab at %.1f against %.1f at %.1f" % [hard["count"], HARD, light["count"], LIGHT]
    )


func test_bristle_flat_at_a_full_press_lays_the_strands_it_did() -> void:
    var full := _stripes("Bristle Flat", FULL)
    assert_true(
        absf(full["count"] - BRISTLE_BEFORE) <= BRISTLE_OFF,
        (
            "Bristle Flat at %.1f lays %.2f strands across, %.2f before, within %.1f"
            % [FULL, full["count"], BRISTLE_BEFORE, BRISTLE_OFF]
        )
    )


## The stripe width and count of *preset*'s stroke at *pressure*.
func _stripes(preset: String, pressure: float) -> Dictionary:
    var columns: Array[PackedFloat32Array] = []
    var widths: Array[float] = []
    for stroke_seed: int in SEEDS:
        _read_columns(preset, pressure, stroke_seed, columns, widths)
    var width := _run_width(columns)
    var painted := _mean(widths)
    print(
        (
            "%s at %.1f: painted %.1f pixels, stripes %.2f pixels, %.1f across"
            % [preset, pressure, painted, width, painted / maxf(width, 1e-6)]
        )
    )
    return {"width": width, "count": painted / maxf(width, 1e-6)}


## Paints *preset*'s stroke at *pressure* under *stroke_seed* and adds the
## lightness of each column's body to *columns* and its painted width to
## *widths*.
func _read_columns(
    preset: String, pressure: float, stroke_seed: int, columns: Array[PackedFloat32Array], widths: Array[float]
) -> void:
    _paint(preset, pressure, stroke_seed)
    for x in _columns():
        var span := _painted_span(x)
        if span.y <= span.x:
            continue
        widths.append(span.y - span.x + 1.0)
        var middle := 0.5 * (span.x + span.y)
        var reach := int(0.5 * (span.y - span.x) * BODY)
        var lightness := PackedFloat32Array()
        for y in range(int(middle) - reach, int(middle) + reach + 1):
            var texel := _texel(Vector2i(x, y))
            lightness.append(0.2126 * texel.r + 0.7152 * texel.g + 0.0722 * texel.b)
        columns.append(lightness)


## The mean width in pixels of the stripes in *columns*: a stripe is a run of
## texels whose lightness steps less than [constant STRIPE_STEP] from one to
## the next, and the width is the texels read over the runs counted.
func _run_width(columns: Array[PackedFloat32Array]) -> float:
    var texels := 0
    var runs := 0
    for column: PackedFloat32Array in columns:
        texels += column.size()
        runs += 1
        for i in column.size() - 1:
            if absf(column[i + 1] - column[i]) >= STRIPE_STEP:
                runs += 1
    return float(texels) / maxi(runs, 1)


func _columns() -> Array[int]:
    var out: Array[int] = []
    for x in range(int(FROM.x + END_MARGIN * RADIUS), int(TO.x - END_MARGIN * RADIUS), STEP):
        out.append(x)
    return out


## The first and last painted row at column *x*, the first above the last when
## none is painted.
func _painted_span(x: int) -> Vector2:
    var first := -1
    var last := -2
    for y in range(int(FROM.y - RADIUS) - 2, int(FROM.y + RADIUS) + 3):
        if _texel(Vector2i(x, y)).a >= PAINTED:
            if first < 0:
                first = y
            last = y
    return Vector2(first, last)


## A level stroke of *preset* as it ships at *pressure* all the way, on a
## fresh canvas, under *stroke_seed*.
func _paint(preset: String, pressure: float, stroke_seed: int) -> void:
    _albedo.clear()
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    var brush := StateNoiseBrushScript.new()
    brush.surface = _surface
    brush.stroke_seed = stroke_seed
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == preset:
            brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
    brush.settings.color = COLOUR
    brush.settings.radius = RADIUS / mini(CANVAS.x, CANVAS.y)
    var clock := 1000.0
    brush.begin_stroke(FROM, pressure, Vector2.ZERO, clock)
    var steps := ceili(FROM.distance_to(TO) / SPACING)
    for i in range(1, steps + 1):
        clock += SAMPLE_MS
        brush.add_sample(FROM.lerp(TO, float(i) / steps), pressure, Vector2.ZERO, clock)
    brush.end_stroke()


func _mean(values: Array[float]) -> float:
    if values.is_empty():
        return 0.0
    var total := 0.0
    for value: float in values:
        total += value
    return total / values.size()


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
