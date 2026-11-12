## Grain takes a Monochrome or Colour choice.
##
## The film grain noise filter has a toggle for chromatic or monochrome. A flat grey under Monochrome
## keeps its Oklab a
## and b at nought and under Colour spreads them, with the lightness spread
## under both. Colour reads the same Size and Seed, weighs its grain towards the
## midtones, leaves a value past white and an unpainted texel alone, and works
## on an Oklab document. A record saved before the choice, which has no Type,
## loads and draws the texels Film grain under Monochrome draws.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const RoundTrip = preload("res://modules/sara-base-modules/base/tests/attached_round_trip.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

## Real dispatches into real chunks.
const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const MODULE_DIR := "res://modules/sara-base-modules/base"
## A mid grey in light, whose Oklab lightness is a little past a half.
const GREY := Color(0.18, 0.18, 0.18, 1.0)
const GRIDS: Array[Vector2i] = [Vector2i(0, 0)]
const SEED := 5.0
const MONOCHROME := {"kind": "film_grain", "monochrome": true, "amount": 60.0, "size": 4.0, "seed": SEED}
const COLOUR := {"kind": "film_grain", "monochrome": false, "amount": 60.0, "size": 4.0, "seed": SEED}

## The record an attached grain was saved as before the choice: no Type.
const BEFORE_THE_CHOICE := {"amount": 60.0, "size": 4.0, "seed": 5.0}
## Where [const BEFORE_THE_CHOICE] was read, over the round-trip bench's four
## chunks in four colours, and what the composite reads there under Film
## grain's Monochrome, whose lattice corners are hashed as integers.
const BEFORE_AT: Array[Vector2i] = [
    Vector2i(128, 128),
    Vector2i(131, 129),
    Vector2i(134, 130),
    Vector2i(137, 131),
    Vector2i(384, 128),
    Vector2i(387, 129),
    Vector2i(390, 130),
    Vector2i(393, 131),
    Vector2i(128, 384),
    Vector2i(131, 385),
    Vector2i(134, 386),
    Vector2i(137, 387),
    Vector2i(384, 384),
    Vector2i(387, 385),
    Vector2i(390, 386),
    Vector2i(393, 387),
]
const BEFORE_READ: Array[Color] = [
    Color(0.7009757, 0.2052815, 0.1050516),
    Color(0.8610888, 0.3560545, 0.2539462),
    Color(0.7806742, 0.2820034, 0.1824977),
    Color(0.7806154, 0.2819485, 0.1824442),
    Color(0.2374628, 0.6311529, 0.9333847),
    Color(0.1336232, 0.5512195, 0.8476408),
    Color(0.0365745, 0.5033061, 0.7961150),
    Color(0.0090771, 0.4942484, 0.7863644),
    Color(0.3437928, 0.3437926, 0.3437927),
    Color(0.3540469, 0.3540466, 0.3540467),
    Color(0.2796468, 0.2796465, 0.2796466),
    Color(0.4619551, 0.4619550, 0.4619551),
    Color(0.9835621, 0.8836604, 0.1755210),
    Color(0.9031689, 0.8030064, -0.0937999),
    Color(0.8911069, 0.7908974, -0.1201140),
    Color(0.9110858, 0.8109518, -0.0711102),
]
## How far a read may sit from the numbers above, in the document's encoded
## numbers. The grain moves these texels by tenths, and another GPU, whose float
## maths after the integer hash may round otherwise, by about a ten-thousandth.
const BEFORE_BOUND := 1e-3

var _easel: SaEasel = null
var _document: SaDocument = null
var _layer: SaLayer = null
var _filter: SaAddNoiseFilter = null


func before_each() -> void:
    if not ModuleLoader.module_dirs.has(OWNER):
        ModuleLoader.module_dirs[OWNER] = MODULE_DIR
    _make_easel(SaColorSpace.linear_srgb())


func after_each() -> void:
    _release()


func _release() -> void:
    _layer = null
    _document = null
    _filter = null
    if _easel != null:
        _easel.free()
    _easel = null


## A document of one chunk stored in *space*, its "Layer 1" holding the chunk
## in the grey.
func _make_easel(space: SaColorSpace) -> void:
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE, SaChunk.SIZE), null, space)
    _filter = SaAddNoiseFilter.new()
    _document = _easel.document
    _document.color_space = space
    _layer = _document.get_node("Layer 1") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    _fill(GREY)


func _fill(colour: Color) -> void:
    for grid_pos in GRIDS:
        _layer.get_or_create_chunk(grid_pos).clear(colour)


## Runs Grain one-shot with *values* over the whole layer, as Apply does.
func _apply(values: Dictionary) -> bool:
    _filter.set_parameters(values)
    var ctx := SaFilterContext.new(_document, _layer, OWNER, _filter.title())
    if not SaFilterApply.call_run(_filter, ctx):
        return false
    return SaFilterApply.apply(ctx, _filter.title())


## Every texel of the chunk, row by row.
func _texels() -> Array[Color]:
    var chunk := _layer.chunks[GRIDS[0]] as SaChunk
    var texture := chunk.field(SaFieldSpec.ALBEDO)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out: Array[Color] = []
    for i in texture.size.x * texture.size.y:
        out.append(SaFieldSpec.decode_texel(bytes, texture.format, i))
    return out


## The side of a chunk in texels, asked of the chunk (hard rule 3).
func _side() -> int:
    return (_layer.chunks[GRIDS[0]] as SaChunk).pixel_size()


## The Oklab of every texel, which a linear sRGB document stores in light.
static func _labs(texels: Array[Color]) -> Array[Vector3]:
    var out: Array[Vector3] = []
    for c in texels:
        out.append(SaOklab.from_linear_srgb(Vector3(c.r, c.g, c.b)))
    return out


## The spread of the *axis* component, 0 for L, 1 for a and 2 for b.
static func _spread(labs: Array[Vector3], axis: int) -> float:
    var mean := 0.0
    for lab in labs:
        mean += lab[axis]
    mean /= float(labs.size())
    var sum := 0.0
    for lab in labs:
        sum += (lab[axis] - mean) * (lab[axis] - mean)
    return sqrt(sum / float(labs.size()))


static func _widest(labs: Array[Vector3], axis: int) -> float:
    var widest := 0.0
    for lab in labs:
        widest = maxf(widest, absf(lab[axis]))
    return widest


## The mean distance in Oklab a between each texel and its right and lower
## neighbours, over a chunk of *side* texels.
static func _neighbour_distance(labs: Array[Vector3], side: int) -> float:
    var sum := 0.0
    var count := 0
    for y in side - 1:
        for x in side - 1:
            var here := labs[y * side + x].y
            sum += absf(here - labs[y * side + x + 1].y) + absf(here - labs[(y + 1) * side + x].y)
            count += 2
    return sum / float(count)


func test_the_dialog_offers_a_monochrome_switch_and_a_grain_without_a_type_is_monochrome() -> void:
    var host := VBoxContainer.new()
    var dialog := SaDialog.new(_filter.build)
    dialog.declare_rows()
    dialog.realize(host)
    assert_not_null(dialog.row(&"monochrome"), "The dialog has a Monochrome switch, where Grain's Type was")
    host.free()
    var read := SaAddNoiseFilter.upgraded(SaAddNoiseFilter.GRAIN_ID, BEFORE_THE_CHOICE)
    assert_eq(read.get("kind"), "film_grain", "A Grain record with no Type reads as Film grain")
    assert_eq(read.get("monochrome"), true, "with Monochrome on")


func test_a_grey_under_monochrome_keeps_a_and_b_at_nought() -> void:
    assert_true(_apply(MONOCHROME), "Monochrome applies")
    var labs := _labs(_texels())
    var lightness := _spread(labs, 0)
    assert_true(lightness > 0.02, "The lightness spreads, by %f" % lightness)
    var widest := maxf(_widest(labs, 1), _widest(labs, 2))
    assert_true(widest < 1e-3, "and a and b stay at nought, the widest at %f" % widest)


func test_a_grey_under_colour_spreads_a_and_b_and_the_lightness() -> void:
    assert_true(_apply(COLOUR), "Colour applies")
    var labs := _labs(_texels())
    var lightness := _spread(labs, 0)
    var spreads := [_spread(labs, 1), _spread(labs, 2)]
    assert_true(lightness > 0.015, "The lightness spreads, by %f" % lightness)
    assert_true(spreads[0] > 0.004 and spreads[1] > 0.004, "and so do a and b, by %f and %f" % spreads)
    for c in _texels():
        if c.a != 1.0:
            assert_true(false, "and no alpha is written, %s" % c)
            return


func test_colour_reads_the_seed() -> void:
    _apply(COLOUR)
    var first := _texels()
    _document.undo()
    _apply(COLOUR)
    var again := _texels()
    _document.undo()
    var other := COLOUR.duplicate()
    other["seed"] = SEED + 1.0
    _apply(other)
    var another := _texels()
    assert_true(first == again, "The same seed lays the same colour grain")
    assert_true(first != another, "and another seed lays another")
    _document.undo()
    _apply(MONOCHROME)
    assert_true(first != _texels(), "and Colour is not Monochrome's grain at that seed")


func test_colour_reads_the_size() -> void:
    var side := _side()
    var fine_values := COLOUR.duplicate()
    fine_values["size"] = 1.0
    assert_true(_apply(fine_values), "Colour at Size 1 applies")
    var fine := _labs(_texels())
    _document.undo()
    var coarse_values := COLOUR.duplicate()
    coarse_values["size"] = 6.0
    assert_true(_apply(coarse_values), "Colour at Size 6 applies")
    var coarse := _labs(_texels())
    var steps := [_neighbour_distance(coarse, side), _neighbour_distance(fine, side)]
    assert_true(steps[0] < 0.5 * steps[1], "Neighbours' hues are more alike at Size 6, %f against %f at Size 1" % steps)


## A grey near black and a grey near white take less of the colour than the
## mid grey does, as the lightness grain fades towards both.
func test_colour_is_weighed_towards_the_midtones() -> void:
    var spreads := {}
    for named: String in ["dark", "mid", "light"]:
        var level: float = {"dark": 0.001, "mid": 0.18, "light": 0.85}[named]
        _fill(Color(level, level, level, 1.0))
        assert_true(_apply(COLOUR), "Colour applies over the %s grey" % named)
        var labs := _labs(_texels())
        spreads[named] = Vector2(_spread(labs, 1), _spread(labs, 2)).length()
        _document.undo()
    var against_dark := [spreads["mid"], spreads["dark"]]
    assert_true(
        spreads["mid"] > 2.0 * spreads["dark"], "The mid grey's hue spreads %f, past twice the dark grey's %f" % against_dark
    )
    assert_true(spreads["mid"] > 2.0 * spreads["light"], "and past twice the light grey's %f" % spreads["light"])


func test_colour_leaves_a_value_past_white_and_an_unpainted_texel_alone() -> void:
    _fill(Color(4.0, 4.0, 4.0, 1.0))
    var full := COLOUR.duplicate()
    full["amount"] = 100.0
    assert_true(_apply(full), "Colour applies at its full amount")
    var worst := 0.0
    for c in _texels():
        worst = maxf(worst, maxf(absf(c.r - 4.0), maxf(absf(c.g - 4.0), absf(c.b - 4.0))))
    assert_true(worst < 1e-4, "A value past white keeps its value, off by %f at most" % worst)
    _document.undo()
    _fill(Color(0.0, 0.0, 0.0, 0.0))
    assert_true(_apply(full), "and applies over an unpainted chunk")
    for c in _texels():
        if c != Color(0.0, 0.0, 0.0, 0.0):
            assert_true(false, "An unpainted texel stays empty, and one reads %s" % c)
            return
    assert_true(true, "An unpainted texel stays empty")


func test_colour_spreads_an_oklab_documents_a_and_b() -> void:
    _release()
    _make_easel(SaColorSpace.oklab())
    var stored := Color(0.6, 0.0, 0.0, 1.0)
    _fill(stored)
    assert_true(_apply(COLOUR), "Colour applies over an Oklab document")
    var labs: Array[Vector3] = []
    for c in _texels():
        labs.append(Vector3(c.r, c.g, c.b))
    var spreads := [_spread(labs, 0), _spread(labs, 1), _spread(labs, 2)]
    assert_true(spreads[0] > 0.015, "The stored lightness spreads, by %f" % spreads[0])
    assert_true(spreads[1] > 0.004 and spreads[2] > 0.004, "and the stored a and b, by %f and %f" % spreads.slice(1))


## A grain attached and saved before the choice holds no Type. Saved and
## loaded, it reads as Monochrome and draws what the kernel drew before.
func test_a_grain_saved_before_the_choice_draws_as_it_did() -> void:
    var trip := RoundTrip.new(SaAddNoiseFilter.new(), OWNER)
    var grain_key := SaFilterRegistry.key_of(OWNER, SaAddNoiseFilter.GRAIN_ID)
    trip.record = SaFilterOps.new(trip.easel.document).attach(trip.layer, grain_key, BEFORE_THE_CHOICE)
    assert_eq(trip.record.key, trip.key, "A record under Grain's key is filed as Add Noise")
    assert_true(_worst_from_before(trip) < BEFORE_BOUND, "The grain attached as before draws as it did")
    var loaded := trip.round_trip({"kind": "white", "monochrome": false, "amount": 0.0})
    assert_false(loaded.is_empty(), "The document saves and loads with its grain")
    assert_eq(loaded.get("kind"), "film_grain", "and the loaded record is Film grain")
    assert_eq(loaded.get("monochrome"), true, "with Monochrome on")
    var worst := _worst_from_before(trip)
    assert_true(worst < BEFORE_BOUND, "and loaded, draws as it did, off by %f at most" % worst)
    trip.release()


## A Colour grain keeps its Type through a save, so it comes back in colour.
func test_a_colour_grain_keeps_its_type_through_a_save() -> void:
    var trip := RoundTrip.new(SaAddNoiseFilter.new(), OWNER)
    trip.attach(COLOUR)
    var before := trip.texels()
    var loaded := trip.round_trip(MONOCHROME)
    assert_eq(loaded.get("monochrome"), false, "The loaded record keeps Monochrome off")
    assert_true(RoundTrip.distance(before, trip.texels()) < 1e-5, "and draws as it did before the save")
    trip.release()


## The largest channel distance between the composite at [const BEFORE_AT] and
## [const BEFORE_READ].
func _worst_from_before(trip: RoundTrip) -> float:
    Bench.composite(trip.easel)
    var worst := 0.0
    for index in BEFORE_AT.size():
        var c := Bench.texel(trip.easel.output, BEFORE_AT[index])
        var was := BEFORE_READ[index]
        worst = maxf(worst, maxf(absf(c.r - was.r), maxf(absf(c.g - was.g), absf(c.b - was.b))))
    return worst
