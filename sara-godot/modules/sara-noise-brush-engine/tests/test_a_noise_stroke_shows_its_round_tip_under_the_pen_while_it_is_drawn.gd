## A noise stroke shows its round tip under the pen while it is drawn.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Before the change each update painted the body up to its newest point and stopped in
## a straight cut across the stroke, a whole radius and up to a step behind the
## pen, and only the lift painted the round end. Now every update lays that end
## as a front and the next puts it back first.
##
## **The round end.** Grain Round dragged straight at pressure 1.0, where its
## cut fills solid, is read back off the stroke buffer after every sample and
## before the lift: the texel 0.8 of the tip's radius in front of the point the
## front ends on is painted and the one 1.2 radii in front is not. The layer's
## height is read at the same moments, and the front lays it in front of the
## newest point the body reached as well, so the round end under the pen
## stands in relief rather than as a flat block until the lift.
##
## **The pressure now, and the harder press kept.** A pen held at one spot
## within 0.8 pixels shows a front whose ink share is a tap's at 0.3 while it
## presses at 0.3, a press alone included. Pressed at 1.0 the front keeps the
## size the press had, since Grain Round's radius follows the pressure and a
## front that grew under a pen at rest showed a dab the stroke had not laid
## (`test_a_ribbon_pen_s_dab_does_not_grow_with_the_pressure_before_the_stroke_is_committed`),
## so its share stays near the light tap's while its cut reads the harder
## press. After the lift the spot holds what a tap at 1.0 leaves, within the
## 0.03 of `test_a_light_stroke_keeps_its_holes_under_a_pen_that_wobbles_or_rests`.
##
## **A pen exactly still.** The curve folds a sample where the pen has not
## moved into the one before, so a pen held exactly still on its press, as a
## driver that reports whole pixels holds it, is laid as a point at the press,
## and the same three readings hold. A pen exactly still after a run shows the
## half of the front ahead of its end at the pressure it has now, sparser at
## 0.3 than at 1.0.
##
## **Every image of the symmetry.** Under a horizontal mirror the mirrored
## image shows the same round end in front of the mirrored point, and the
## mirrored stroke is put back exactly too.
##
## **Put back exactly.** A stroke that runs, rests while it presses harder and
## turns, and a press whose front reaches a chunk its tap never does, paint the
## same colour and height texel for texel, on the same chunks, as with a list
## that lays no front.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const NoiseStretchScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_stretch.gd")
const NoiseDabListScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_dab_list.gd")

const CANVAS := Vector2i(512, 256)
## The preset's radius as a share of the canvas's smaller side, 25.6 pixels.
const RADIUS := 0.1
## The drag, a sample every three pixels along y = 128, which takes a point
## every other sample and holds the one between, so the front ends on both.
const FROM := Vector2(64.0, 128.0)
const STEP := 3.0
const SAMPLES := 60
## The mirrored drag stops short enough that the stroke's own image never
## reaches where the mirror's round end is read.
const MIRRORED_SAMPLES := 40
## Where the round end is read, in tip radii in front of the point it ends on.
const PAINTED := 0.8
const BARE := 1.2
## The held pen: its spot, how far a sample strays, how many samples at each
## pressure, and how far apart two ink shares may be.
const SPOT := Vector2(192.0, 128.0)
const WOBBLE := 0.8
const HELD := 20
const LIGHT := 0.3
const HARD := 1.0
const WITHIN := 0.03
## How much more ink than a light tap's the front of a harder press on the spot
## may show, its kept size filled more fully by the harder cut.
const KEPT := 0.1
const INSET := 3.0
const SEEDS: Array[int] = [11, 12, 13]


## A dab list that lays no front, the stroke as it was painted before the change.
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


func before_each() -> void:
    _brush = _fresh_brush()


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null


func test_the_round_end_shows_in_front_of_the_point_the_front_ends_on() -> void:
    var r := _radius()
    var ends := {"held": 0, "taken": 0}
    _brush.begin_stroke(FROM, HARD)
    for i in range(1, SAMPLES + 1):
        _brush.add_sample(FROM + Vector2(STEP * i, 0.0), HARD)
        if i < 4:
            continue
        var end := _brush.dab_list.front.end_at
        var line := _brush.dab_list.stretch.front_line(HARD)
        @warning_ignore("integer_division")
        ends["held" if line.size() / NoiseStretchScript.FLOATS == 3 else "taken"] += 1
        var buffer := _document().stroke_layer
        var near := _alpha(buffer, Vector2i((end + Vector2(PAINTED * r, 0.0)).floor()))
        var far := _alpha(buffer, Vector2i((end + Vector2(BARE * r, 0.0)).floor()))
        assert_true(near > 0.0, "sample %d: the texel %.1f radii in front of %s is painted, %.3f" % [i, PAINTED, end, near])
        assert_eq(far, 0.0, "sample %d: and the one %.1f radii in front is not" % [i, BARE])
    _brush.end_stroke()
    assert_true(ends["held"] > 0 and ends["taken"] > 0, "the front ended on a held point and on a taken one, %s" % ends)


func test_the_front_lays_height_in_front_of_the_body() -> void:
    var r := _radius()
    var behind_most := 0.0
    var ahead_most := 0.0
    var looked := 0
    _brush.begin_stroke(FROM, HARD)
    for i in range(1, SAMPLES + 1):
        _brush.add_sample(FROM + Vector2(STEP * i, 0.0), HARD)
        var stretch := _brush.dab_list.stretch
        if stretch.front_first_laid() != NoiseStretchScript.FIRST_SEGMENT:
            continue
        var line := stretch.front_line(HARD)
        var body := Vector2(
            line[NoiseStretchScript.FLOATS + NoiseStretchScript.AT], line[NoiseStretchScript.FLOATS + NoiseStretchScript.AT + 1]
        )
        var layer := _document().active_layer
        var heights := _heights(layer, Rect2i(Vector2i(body) + Vector2i(1, -int(r)), Vector2i(int(r), 2 * int(r) + 1)))
        for at: Vector2i in heights:
            ahead_most = maxf(ahead_most, heights[at])
        var back := _heights(layer, Rect2i(Vector2i(body) - Vector2i(int(r), 2), Vector2i(int(r) - 2, 5)))
        for at: Vector2i in back:
            behind_most = maxf(behind_most, back[at])
        looked += 1
    _brush.end_stroke()
    assert_true(2 * looked > SAMPLES, "the body was read at %d updates" % looked)
    assert_true(behind_most > 0.0, "and laid height behind its newest point, %.4f" % behind_most)
    assert_true(ahead_most > 0.0, "and the front laid height in front of it, %.4f" % ahead_most)


func test_a_pen_at_rest_shows_the_pressure_it_has_and_keeps_the_harder_press() -> void:
    var light := _tap(LIGHT)
    var hard := _tap(HARD)
    assert_true(light < hard - 0.1, "a tap at %.1f leaves holes a tap at %.1f fills, %.4f and %.4f" % [LIGHT, HARD, light, hard])
    for rng_seed: int in SEEDS:
        var rng := RandomNumberGenerator.new()
        rng.seed = rng_seed
        _brush = _fresh_brush()
        _brush.begin_stroke(SPOT, LIGHT)
        var pressed := _disc(_document().stroke_layer)
        assert_true(
            absf(pressed - light) <= WITHIN,
            "seed %d: the press shows %.4f against a light tap's %.4f" % [rng_seed, pressed, light]
        )
        for i in HELD:
            _brush.add_sample(SPOT + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, WOBBLE), LIGHT)
        var soft := _disc(_document().stroke_layer)
        assert_true(
            absf(soft - light) <= WITHIN,
            "seed %d: the front at %.1f shows %.4f against the tap's %.4f" % [rng_seed, LIGHT, soft, light]
        )
        for i in HELD:
            _brush.add_sample(SPOT + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, WOBBLE), HARD)
        var firm := _disc(_document().stroke_layer)
        assert_true(
            firm >= soft - WITHIN and firm <= light + KEPT,
            "seed %d: the front at %.1f keeps the press's size, %.4f against a light tap's %.4f" % [rng_seed, HARD, firm, light]
        )
        _brush.end_stroke()
        var left := _disc(_document().active_layer)
        assert_true(
            absf(left - hard) <= WITHIN, "seed %d: the lift leaves %.4f against a hard tap's %.4f" % [rng_seed, left, hard]
        )


func test_a_pen_exactly_still_shows_the_pressure_it_has_and_keeps_the_harder_press() -> void:
    var light := _tap(LIGHT)
    var hard := _tap(HARD)
    _brush = _fresh_brush()
    _brush.begin_stroke(SPOT, LIGHT)
    for i in HELD:
        _brush.add_sample(SPOT, LIGHT)
    var soft := _disc(_document().stroke_layer, SPOT)
    assert_true(
        absf(soft - light) <= WITHIN, "on the press the front at %.1f shows %.4f against the tap's %.4f" % [LIGHT, soft, light]
    )
    for i in HELD:
        _brush.add_sample(SPOT, HARD)
    var firm := _disc(_document().stroke_layer, SPOT)
    assert_true(
        firm >= soft - WITHIN and firm <= light + KEPT,
        "on the press the front at %.1f keeps the press's size, %.4f against a light tap's %.4f" % [HARD, firm, light]
    )
    _brush.end_stroke()
    var left := _disc(_document().active_layer, SPOT)
    assert_true(absf(left - hard) <= WITHIN, "and the lift leaves %.4f against a hard tap's %.4f" % [left, hard])

    _brush = _fresh_brush()
    _brush.begin_stroke(FROM, HARD)
    for i in range(1, 31):
        _brush.add_sample(FROM + Vector2(STEP * i, 0.0), HARD)
    var still := FROM + Vector2(STEP * 30, 0.0)
    var shares := {}
    for pressure: float in [LIGHT, HARD]:
        for i in HELD:
            _brush.add_sample(still, pressure)
        shares[pressure] = _disc(_document().stroke_layer, _brush.dab_list.front.end_at, true)
    _brush.end_stroke()
    assert_true(
        shares[LIGHT] < shares[HARD] - 0.1,
        "after a run the front ahead shows %.4f at %.1f and %.4f at %.1f" % [shares[LIGHT], LIGHT, shares[HARD], HARD]
    )
    assert_true(absf(shares[HARD] - hard) <= WITHIN, "and at %.1f a hard tap's %.4f" % [HARD, hard])


func test_a_stroke_with_its_fronts_paints_what_it_paints_without_them() -> void:
    var shown := _bent_stroke(false)
    var plain := _bent_stroke(true)
    _compare(shown, plain, "the stroke that runs, rests and turns")
    var r := _radius()
    # A press whose held point lies just under half a step on, so the front's
    # box crosses into the next chunk and the tap at the lift does not.
    var side := 256.0
    var press := Vector2(side - r - 6.0, 128.0)
    var reached := _press_by_a_border(press, false)
    assert_true(reached, "the front reached the chunk past the border while the pen was down")
    var with_front := _texels()
    _press_by_a_border(press, true)
    _compare(with_front, _texels(), "the press by a chunk's border")


## With a horizontal mirror about the canvas's middle the mirrored image shows
## its round end in front of the mirrored point the front ends on, and the
## mirrored stroke paints with its fronts what it paints without them.
func test_every_image_of_the_symmetry_shows_its_front() -> void:
    _mirror()
    var r := _radius()
    _brush.begin_stroke(FROM, HARD)
    for i in range(1, MIRRORED_SAMPLES + 1):
        _brush.add_sample(FROM + Vector2(STEP * i, 0.0), HARD)
        if i < 4:
            continue
        var end := _mirrored(_brush.dab_list.front.end_at)
        var buffer := _document().stroke_layer
        var near := _alpha(buffer, Vector2i((end - Vector2(PAINTED * r, 0.0)).floor()))
        var far := _alpha(buffer, Vector2i((end - Vector2(BARE * r, 0.0)).floor()))
        assert_true(
            near > 0.0, "sample %d: the mirror's texel %.1f radii in front of %s is painted, %.3f" % [i, PAINTED, end, near]
        )
        assert_eq(far, 0.0, "sample %d: and the mirror's one %.1f radii in front is not" % [i, BARE])
    _brush.end_stroke()
    _compare(_bent_stroke(false, true), _bent_stroke(true, true), "the mirrored stroke that runs, rests and turns")


## Mirrors the document's strokes across the vertical line through the
## canvas's middle.
func _mirror() -> void:
    var symmetry := _document().symmetry
    symmetry.center = Vector2(CANVAS) / 2.0
    symmetry.mirror_horizontal = true


## *at* reflected across the mirror [method _mirror] sets.
func _mirrored(at: Vector2) -> Vector2:
    return Vector2(CANVAS.x - at.x, at.y)


## The stroke that runs, rests while pressing harder and turns, and the active
## layer's texels after it, *plain* painting it with no front and *mirrored*
## under [method _mirror].
func _bent_stroke(plain: bool, mirrored: bool = false) -> Dictionary:
    _brush = _fresh_brush(plain)
    if mirrored:
        _mirror()
    var rng := RandomNumberGenerator.new()
    rng.seed = 5
    var at := FROM
    _brush.begin_stroke(at, 0.5)
    for i in 30:
        at += Vector2(STEP, 0.0)
        _brush.add_sample(at, 0.5 + 0.015 * i)
    for i in HELD:
        _brush.add_sample(at + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, WOBBLE), 0.4 + 0.03 * i)
    for i in 30:
        at += Vector2(0.5, STEP)
        _brush.add_sample(at, 1.0 - 0.02 * i)
    _brush.end_stroke()
    return _texels()


## A press near a chunk's border held just under half a step on, answering
## whether the stroke buffer held the chunk past the border before the lift.
func _press_by_a_border(press: Vector2, plain: bool) -> bool:
    _brush = _fresh_brush(plain)
    _brush.begin_stroke(press, HARD)
    var past := false
    for i in 6:
        _brush.add_sample(press + Vector2(3.2, 0.3 * (i % 2)), HARD)
        past = past or _document().stroke_layer.chunks.has(Vector2i(1, 0))
    _brush.end_stroke()
    return past


func _compare(shown: Dictionary, plain: Dictionary, what: String) -> void:
    assert_eq(
        shown.keys().size(),
        plain.keys().size(),
        "%s paints the same chunks with its fronts as without, %s" % [what, shown.keys()]
    )
    var differ := PackedStringArray()
    for key: String in plain:
        if shown.get(key, PackedByteArray()) != plain[key]:
            differ.append(key)
    assert_eq(differ, PackedStringArray(), "%s paints the same texels with its fronts as without" % what)


## A brush of Grain Round at the suite's radius on a fresh surface, with a list
## that lays no front when *plain*.
func _fresh_brush(plain: bool = false) -> StateNoiseBrushScript:
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    var brush := StateNoiseBrushScript.new()
    brush.surface = _surface
    brush.stroke_seed = 7
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == "Grain Round":
            brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
    brush.settings.radius = RADIUS
    # Grain Round ships at a thickness of 0, so the test sets 0.3 and the front has height to read.
    brush.settings.thickness = 0.3
    brush.settings.color = Color(0.0, 0.0, 0.0, 1.0)
    if plain:
        brush.dab_list = NoFrontList.new(StateNoiseBrushScript.KERNEL)
    return brush


## The ink share a tap at *pressure* leaves on the layer at the spot.
func _tap(pressure: float) -> float:
    _brush = _fresh_brush()
    _brush.begin_stroke(SPOT, pressure)
    _brush.end_stroke()
    return _disc(_document().active_layer)


func _document() -> SaDocument:
    return _surface.easel.document


func _radius() -> float:
    return RADIUS * mini(CANVAS.x, CANVAS.y)


## The mean alpha of *layer* over the disc a tap at *centre* paints, three
## pixels in from its rim, or over its half in front of *centre* along x when
## *ahead*, three pixels on.
func _disc(layer: SaLayer, centre: Vector2 = SPOT, ahead: bool = false) -> float:
    var inside := _radius() - INSET
    var images := {}
    var total := 0.0
    var count := 0
    for y in range(int(centre.y - inside), int(centre.y + inside) + 1):
        for x in range(int(centre.x - inside), int(centre.x + inside) + 1):
            if Vector2(x, y).distance_to(centre) > inside:
                continue
            if ahead and x < centre.x + INSET:
                continue
            total += _alpha(layer, Vector2i(x, y), images)
            count += 1
    return total / count


## The alpha of *layer* at *pixel*, read back, *images* holding the chunks
## already read.
func _alpha(layer: SaLayer, pixel: Vector2i, images: Dictionary = {}) -> float:
    var side := _side(layer)
    if side == 0:
        return 0.0
    var grid := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
    if not layer.chunks.has(grid):
        return 0.0
    if not images.has(grid):
        @warning_ignore("static_called_on_instance")
        images[grid] = SaExport.get_texture_image_float(layer.get_field(grid))
    return (images[grid] as Image).get_pixelv(pixel - grid * side).a


## The height of *layer* over *rect*, by pixel, nought where it has none.
func _heights(layer: SaLayer, rect: Rect2i) -> Dictionary:
    var out := {}
    var rd := GlobalShaderCompiler.get_rd()
    var read := {}
    var side := _side(layer)
    for y in rect.size.y:
        for x in rect.size.x:
            var at := rect.position + Vector2i(x, y)
            out[at] = 0.0
            if side == 0:
                continue
            var grid := Vector2i(floori(float(at.x) / side), floori(float(at.y) / side))
            var texture := layer.get_field(grid, SaFieldSpec.HEIGHT)
            if texture == null:
                continue
            if not read.has(grid):
                read[grid] = rd.texture_get_data(texture.rid, 0)
            var local := at - grid * side
            out[at] = (read[grid] as PackedByteArray).decode_half((local.y * texture.size.x + local.x) * 2)
    return out


## Every chunk's colour and height on the active layer, as the bytes the card
## holds, by grid position and field.
func _texels() -> Dictionary:
    var layer := _document().active_layer
    var rd := GlobalShaderCompiler.get_rd()
    var out := {}
    for grid: Vector2i in layer.chunks:
        var chunk := layer.chunks[grid] as SaChunk
        out["%s albedo" % grid] = rd.texture_get_data(chunk.albedo().rid, 0)
        if chunk.has_field(SaFieldSpec.HEIGHT):
            out["%s height" % grid] = rd.texture_get_data(chunk.field(SaFieldSpec.HEIGHT).rid, 0)
    return out


## The side of *layer*'s chunks in pixels, asked of a chunk rather than
## assumed, by hard rule 3 (sparse chunks), and nought while it holds none.
func _side(layer: SaLayer) -> int:
    for grid: Vector2i in layer.chunks:
        return (layer.chunks[grid] as SaChunk).pixel_size()
    return 0
