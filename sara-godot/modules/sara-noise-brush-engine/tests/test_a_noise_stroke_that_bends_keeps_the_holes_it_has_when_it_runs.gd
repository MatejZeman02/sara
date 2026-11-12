## A noise stroke that bends keeps the holes it has when it runs straight.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Thick Impasto and Grain Round at one light pressure each paint a straight
## stroke and arcs of 600 and 150 pixels radius, all 520 pixels long with a
## sample every 1.5 pixels, under a pen leaning the way a typical pen does. Each
## arc's body covers what the straight stroke's does, within 0.05.
##
## **Why the pen leans.** The lean stretches the round tip into an ellipse, and
## a tip that is not round carries a trail: every update reads the texels a
## tip's reach behind the pen again and paints one where it gives more than is
## laid. Before the change the texels behind the trail's first point, once the trail
## had moved on from the stroke's start, were read as an end cap, along the
## straight line the heading carries on. On a straight stroke that is the
## reading they had, and on a bend it is another, so every update the trail
## moved past them read them somewhere else in the field and the wash kept the
## most. Thick Impasto's streaks thickened and ran together along a bend, and
## Grain Round's grain filled. A pen upright keeps a round tip round and paints
## no trail, which is why a scripted stroke never showed it.
##
## **Why the straight stroke runs at a slant.** Along a row of pixels a
## bristle's thin streak lands on whole rows or misses them, so its share is
## one sample of the streak's width rather than the width, and a level stroke
## read 0.05 off its own slanted twin. A slant near the heading the arcs have
## at their tops crosses the rows.
##
## **Every field and tip.** The Picture field on Paper Grain under the lean, a
## flat tip and an image tip with the pen upright are held the same way, but
## against straight strokes at three slants rather than one. A tip that is not
## turned with the path, or one the lean stretches across it, covers a share
## that moves with the heading, and an arc sweeps through headings, so each arc
## is held within 0.02 of the range the straight strokes span. Before the change the
## Picture field's arc of 150 read 0.047 above its range and the flat tip's
## 0.146. The image tip's fill was smaller than how far its share moves with
## the heading, so its arcs sit in the range either way.
##
## **The Picture field's range is over several seeds.** A Picture is read at a
## texel's place on the canvas, so an arc reads another stretch of the pattern
## than a straight stroke from the same start does, and Paper Grain's lattice
## covers one stretch more than another. Its straight strokes are painted at
## each seed of [constant PICTURE_SEEDS] as well as each slant, each seed's
## offset another stretch, and on the card the suite was written on they span
## 0.454 to 0.540, with both arcs at 0.502.
##
## Coverage is the mean alpha read back off the layer over the body, the texels
## within 0.7 of the tip's radius of the path and a radius in from either end.
## The seed is held, so the straight stroke and the arcs read one field, and
## the straight stroke is held to leave holes, so a stroke painted solid every
## way cannot pass.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

const CANVAS := Vector2i(1024, 1024)
## The light pressure every stroke is painted at, the lean of the pen, in
## degrees on each axis, and the stroke's seed.
const PRESSURE := 0.3
const LEAN := Vector2(35.0, 20.0)
const SEED := 7
## Each stroke's length and the gap between two samples, in pixels, and how far
## apart in time two samples are, in milliseconds.
const LENGTH := 520.0
const SPACING := 1.5
const SAMPLE_MS := 8.0
## The straight stroke's start and its slant in radians, and the top of every
## arc, where its heading is level. A straight stroke at another slant shares
## its middle with this one.
const FROM := Vector2(250.0, 540.0)
const SLANT := 0.17
const TOP := Vector2(512.0, 300.0)
const ARCS: Array[float] = [600.0, 150.0]
## The slants a tip whose share moves with the heading is read at.
const SLANTS: Array[float] = [0.17, 0.65, 1.2]
## The share of the tip's radius either side of the path a coverage is read
## over, how far apart two coverages may be, and how far outside the straight
## strokes' range an arc may read.
const BODY := 0.7
const WITHIN := 0.05
const NEAR := 0.02
## The seeds the Picture field's straight strokes are painted at, each one's
## offset another stretch of the pattern.
const PICTURE_SEEDS: Array[int] = [7, 11, 19, 23, 31, 43]
## The image tip, the pattern the Picture field reads, and the flat tip's
## height over its width.
const IMAGE_TIP := "res://tips/cloud-puff.png"
const PATTERN := "Paper Grain"
const FLAT := 0.5

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
## The pressure and the lean the strokes under way are painted at.
var _pressure := PRESSURE
var _lean := LEAN
## Chunk images already read back, by grid position.
var _images: Dictionary = {}


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    _images.clear()
    _pressure = PRESSURE
    _lean = LEAN


func after_each() -> void:
    _brush = null
    _images.clear()
    Fixtures.teardown(_surface)
    _surface = null


func test_thick_impasto_reads_the_same_holes_along_a_bend() -> void:
    _holds_the_straight_stroke("Thick Impasto")


func test_grain_round_reads_the_same_holes_along_a_bend() -> void:
    _holds_the_straight_stroke("Grain Round")


func test_the_picture_field_reads_the_same_holes_along_a_bend() -> void:
    _pressure = 0.5
    _holds_the_straight_range("The Picture field", "", _picture_field, PICTURE_SEEDS)


func test_a_flat_tip_reads_the_same_holes_along_a_bend() -> void:
    _pressure = 0.35
    _lean = Vector2.ZERO
    _holds_the_straight_range("A flat tip", "Thick Impasto", _flat_tip)


func test_an_image_tip_reads_the_same_holes_along_a_bend() -> void:
    _pressure = 0.3
    _lean = Vector2.ZERO
    _holds_the_straight_range("An image tip", "Grain Round", _image_tip)


## Paints *preset*'s straight stroke and each arc on a fresh surface and holds
## every arc's coverage to the straight stroke's.
func _holds_the_straight_stroke(preset: String) -> void:
    _use(preset)
    var straight := _stroke(0.0)
    assert_true(straight > 0.1 and straight < 0.8, "%s's straight stroke leaves holes, %.4f" % [preset, straight])
    for bend: float in ARCS:
        _clear()
        _use(preset)
        var arc := _stroke(bend)
        assert_true(
            absf(arc - straight) <= WITHIN,
            "%s's arc of radius %d covers %.4f against the straight stroke's %.4f" % [preset, int(bend), arc, straight]
        )


## Paints the straight stroke at every slant of [constant SLANTS] and each arc
## on a fresh surface, with *preset* dressed by *dress*, and holds every arc's
## coverage within [constant NEAR] of the range the straight strokes span.
func _holds_the_straight_range(label: String, preset: String, dress: Callable, seeds: Array[int] = [SEED]) -> void:
    var low := INF
    var high := -INF
    for at_seed: int in seeds:
        for slant: float in SLANTS:
            _clear()
            _use(preset, dress, at_seed)
            var straight := _stroke(0.0, slant)
            low = minf(low, straight)
            high = maxf(high, straight)
    print("%s: straight %.4f to %.4f" % [label, low, high])
    assert_true(low > 0.1 and high < 0.8, "%s's straight strokes leave holes, %.4f to %.4f" % [label, low, high])
    for bend: float in ARCS:
        _clear()
        _use(preset, dress)
        var arc := _stroke(bend, SLANT)
        assert_true(
            arc >= low - NEAR and arc <= high + NEAR,
            "%s's arc of radius %d covers %.4f against the straight strokes' %.4f to %.4f" % [label, int(bend), arc, low, high]
        )


## A brush of *preset*, or of the brush's own settings for no name, in black,
## on the surface under way, and then dressed by *dress* when one is given.
func _use(preset: String, dress: Callable = Callable(), at_seed: int = SEED) -> void:
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = at_seed
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == preset:
            _brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
    _brush.settings.color = Color(0.0, 0.0, 0.0, 1.0)
    # Grain Round tapers with the pen, and the
    # body is read at the preset's whole radius, so the taper is turned off:
    # what is held is the field along a bend, not the width.
    _brush.settings.size_option.enabled = false
    if dress.is_valid():
        dress.call()


## The brush's own settings at a radius of 0.02 through the Picture field on
## [constant PATTERN], with a hard edge to its holes and no Strength.
func _picture_field() -> void:
    _brush.settings.radius = 0.02
    _brush.settings.texture_field = "picture"
    _brush.settings.picture_name = PATTERN
    _brush.settings.hardness = 1.0
    _brush.settings.strength = 0.0


## A rectangle tip [constant FLAT] as high as it is wide.
func _flat_tip() -> void:
    _brush.settings.tip.shape = SaBrushTipScript.Shape.RECTANGLE
    _brush.settings.tip.ratio = FLAT


## [constant IMAGE_TIP] as the tip.
func _image_tip() -> void:
    assert_true(_brush.load_tip(IMAGE_TIP), "The image tip loads")


## A fresh surface.
func _clear() -> void:
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    _images.clear()


func _radius() -> float:
    return _brush.settings.radius * mini(CANVAS.x, CANVAS.y)


## The point *travelled* pixels along the straight stroke at *slant*, or along
## the arc of radius *bend*, which runs through [constant TOP] at its middle.
func _at(bend: float, travelled: float, slant: float) -> Vector2:
    if bend <= 0.0:
        return _from(slant) + Vector2.from_angle(slant) * travelled
    var angle := -PI * 0.5 + (travelled - LENGTH * 0.5) / bend
    return TOP + Vector2(0.0, bend) + Vector2.from_angle(angle) * bend


## The straight stroke's start at *slant*: [constant FROM] at [constant SLANT],
## and at any other slant the start that keeps the two strokes' middles
## together.
func _from(slant: float) -> Vector2:
    if slant == SLANT:
        return FROM
    return FROM + (Vector2.from_angle(SLANT) - Vector2.from_angle(slant)) * LENGTH * 0.5


## The stroke of radius *bend*, or straight at *slant* for nought, painted at
## the pressure and the lean under way, and the coverage of its body.
func _stroke(bend: float, slant: float = SLANT) -> float:
    var clock := 1000.0
    _brush.begin_stroke(_at(bend, 0.0, slant), _pressure, _lean, clock)
    var travelled := SPACING
    while travelled <= LENGTH:
        clock += SAMPLE_MS
        _brush.add_sample(_at(bend, travelled, slant), _pressure, _lean, clock)
        travelled += SPACING
    _brush.end_stroke()
    var r := _radius()
    var box := Rect2(_at(bend, 0.0, slant), Vector2.ZERO)
    for step in range(1, 53):
        box = box.expand(_at(bend, LENGTH * step / 52.0, slant))
    box = box.grow(r)
    var total := 0.0
    var count := 0
    for y in range(int(box.position.y), int(box.end.y)):
        for x in range(int(box.position.x), int(box.end.x)):
            var place := _place(bend, Vector2(x, y), slant)
            if place.x < r or place.x > LENGTH - r or absf(place.y) > r * BODY:
                continue
            total += _texel(Vector2i(x, y)).a
            count += 1
    return total / count


## Where *p* lies against the stroke of radius *bend*, or the straight one at
## *slant*: how far along it in x and how far out from its path in y.
func _place(bend: float, p: Vector2, slant: float) -> Vector2:
    if bend <= 0.0:
        var heading := Vector2.from_angle(slant)
        var from := _from(slant)
        return Vector2((p - from).dot(heading), (p - from).dot(heading.orthogonal()))
    var offset := p - (TOP + Vector2(0.0, bend))
    return Vector2(wrapf(offset.angle() + PI * 0.5, -PI, PI) * bend + LENGTH * 0.5, offset.length() - bend)


## The active layer's texel at *pixel*.
func _texel(pixel: Vector2i) -> Color:
    var layer := _surface.easel.document.active_layer
    var side := 0
    for grid: Vector2i in layer.chunks:
        side = (layer.chunks[grid] as SaChunk).pixel_size()
        break
    if side == 0:
        return Color.TRANSPARENT
    var grid := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
    if not layer.chunks.has(grid):
        return Color.TRANSPARENT
    if not _images.has(grid):
        @warning_ignore("static_called_on_instance")
        _images[grid] = SaExport.get_texture_image_float(layer.get_field(grid))
    return (_images[grid] as Image).get_pixelv(pixel - grid * side)
