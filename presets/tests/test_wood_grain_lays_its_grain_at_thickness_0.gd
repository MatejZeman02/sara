## Wood Grain lays its grain at thickness 0.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter found Wood Grain laying a plain band at the
## press a scripted stroke sends, its L* varying by 0.13 to 0.18 across it, so
## its streaks came only with a thickness. A thickness is a relief the canvas
## lays over every layer above, and the grain showed across the hair and face
## painted over it. The preset now keeps its grain at a full press, as paint.
##
## Each stroke is laid through the tool's own calls on a real surface of the
## 1080 pixels the preset's radius is a fraction of, on a layer of its own over
## the document's grey ground, in a dark oak, and read off the composite
## as the painter sees it. Pressed at one, as a scripted stroke is, and at 0.9,
## a pen's firm press. Under about 0.85 the preset lays broken streaks over the
## bare ground, as it always did, and which bristles show there is the field's
## seed's, so a light touch is not held to a count of streaks.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

const PRESET := "Wood Grain"
## The canvas's side, the 1080 of a default document.
const SIDE := 1080
## The stroke runs along [constant ROW] from [constant FROM] to [constant TO],
## a sample every [constant STEP] pixels, and is read between [constant READ_FROM]
## and [constant READ_TO], clear of both ends.
const ROW := 540.0
const FROM := 100.0
const TO := 980.0
const STEP := 4.0
const READ_FROM := 300
const READ_TO := 780
## Where the two halves of what is read meet, for whether a streak runs along.
const READ_MIDDLE := 540
## How far either side of the path the rows are read.
const REACH := 60
## A dark oak.
const OAK := Color("#46392c")
## The share of the band's width left off each side, where Hardness thins the
## grain towards the rim, so the rows read are the stroke's body.
const RIM := 0.15
## What the ask holds the streaks to, apart across the stroke.
const APART := 5.0
## A row whose mean is this far from the ground took paint.
const TOOK_PAINT := 0.5
## How far one row's mean over the stroke's first half may stand from its mean
## over the second, for a streak that runs along the stroke.
const ALONG := 1.0
## The share of the band's width left off each side for that reading. The
## stroke's outline wanders along it on purpose, in by as much as 0.6 of the
## half-width at a nick where a few hairs ran dry, so a row near the edge
## that a nick takes in one half and not in the other is the edge's wander and
## not a streak that turns.
const ALONG_RIM := 0.3

## The presses and the seeds the grain is read at, a press in x and a seed in
## y: one, as a scripted stroke presses, and 0.9, a pen's firm press, each over
## three fields, since which bristles a field lays is its seed's.
const LAID: Array[Vector2] = [
    Vector2(1.0, 7), Vector2(1.0, 1), Vector2(1.0, 2), Vector2(0.9, 7), Vector2(0.9, 1), Vector2(0.9, 2)
]

## The cover the second case lays over the grain, a light skin tone.
const COVER := Color("#d9b49a")

static var scratch_png_path: String = SaDataRoot.path("d4-wood-grain-covered.png")

var _surface: SaSurface = null


func before_each() -> void:
    SaSettings.show_relief = true
    SaSettings.relief_light_angle = 315.0
    SaSettings.relief_strength = 4.0


func after_each() -> void:
    if _surface != null:
        Fixtures.teardown(_surface)
        _surface = null
    if FileAccess.file_exists(scratch_png_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_png_path))
    SaSettings.show_relief = true
    SaSettings.relief_light_angle = 315.0
    SaSettings.relief_strength = 4.0


func _entry() -> Dictionary:
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == PRESET:
            return entry
    return {}


## CIE L* of *colour*, an sRGB colour as a file stores it.
static func _l_star(colour: Color) -> float:
    var y := 0.2126 * _linear(colour.r) + 0.7152 * _linear(colour.g) + 0.0722 * _linear(colour.b)
    var f := pow(y, 1.0 / 3.0) if y > 216.0 / 24389.0 else (24389.0 / 27.0 * y + 16.0) / 116.0
    return 116.0 * f - 16.0


static func _linear(channel: float) -> float:
    return channel / 12.92 if channel <= 0.04045 else pow((channel + 0.055) / 1.055, 2.4)


## A fresh surface with Wood Grain as it ships laid along [constant ROW] at
## *pressure* with the stroke's field rolled from *stroke_seed*, on a layer
## added over the ground, with *thickness* written over the recipe's own when
## it is not negative. Answers the layer.
func _lay(pressure: float, thickness: float = -1.0, stroke_seed: int = 7) -> SaLayer:
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(Vector2i(SIDE, SIDE))
    var grain := SaLayerOps.new(_surface.easel.document).add()
    var settings := NoisePresetsScript.build(NoiseBrushSettingsScript, _entry())
    settings.color = OAK
    if thickness >= 0.0:
        settings.thickness = thickness
    var brush := StateNoiseBrushScript.new()
    brush.surface = _surface
    brush.stroke_seed = stroke_seed
    brush.settings = settings
    brush.begin_stroke(Vector2(FROM, ROW), pressure)
    for index in range(1, int((TO - FROM) / STEP) + 1):
        brush.add_sample(Vector2(FROM + STEP * index, ROW), pressure)
    brush.end_stroke()
    _surface.easel.document.commit_stroke()
    return grain


## The picture a painter sees, composited and in sRGB.
func _picture() -> Image:
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()
    return SaExport.get_preview_image(_surface.easel)


## The mean L* of each row from [constant REACH] above the path to as far
## below it, over the columns from *from* to *to*.
static func _rows(picture: Image, from: int, to: int) -> PackedFloat32Array:
    var rows := PackedFloat32Array()
    for y in range(int(ROW) - REACH, int(ROW) + REACH + 1):
        var total := 0.0
        for x in range(from, to):
            total += _l_star(picture.get_pixel(x, y))
        rows.append(total / float(to - from))
    return rows


## The indices of *rows* the stroke's body covers: those that took paint
## against *ground*, less *rim* of the band off each side.
static func _body(rows: PackedFloat32Array, ground: float, rim: float = RIM) -> Vector2i:
    var first := -1
    var last := -1
    for index in rows.size():
        if absf(rows[index] - ground) > TOOK_PAINT:
            if first < 0:
                first = index
            last = index
    if first < 0:
        return Vector2i(0, -1)
    var trim := int(float(last - first + 1) * rim)
    return Vector2i(first + trim, last - trim)


## How many runs of rows within *body* stand at least [constant APART] darker
## than the lightest row there, each a streak.
static func _streaks(rows: PackedFloat32Array, body: Vector2i) -> int:
    var lightest := -INF
    for index in range(body.x, body.y + 1):
        lightest = maxf(lightest, rows[index])
    var count := 0
    var inside := false
    for index in range(body.x, body.y + 1):
        var dark := rows[index] <= lightest - APART
        if dark and not inside:
            count += 1
        inside = dark
    return count


static func _spread(rows: PackedFloat32Array, body: Vector2i) -> Vector2:
    var lowest := INF
    var highest := -INF
    for index in range(body.x, body.y + 1):
        lowest = minf(lowest, rows[index])
        highest = maxf(highest, rows[index])
    return Vector2(lowest, highest)


func test_wood_grain_ships_at_thickness_0_and_its_line_names_the_relief() -> void:
    var entry := _entry()
    assert_false(entry.is_empty(), "Wood Grain is on the noise shelf")
    var settings := NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
    assert_not_null(settings, "and builds")
    if settings == null:
        return
    assert_eq(settings.thickness, 0.0, "It ships at thickness 0, so it lays no height")
    var about := String(entry["about"])
    assert_true(
        about.contains("relief") and about.contains("every layer above"),
        "Its line says a thickness adds a relief seen through the layers above: %s" % about
    )
    assert_false(about.contains("plain band"), "and no longer that a hard press closes it into a plain band")


func test_a_full_press_lays_streaks_along_the_stroke_at_least_5_l_apart() -> void:
    for laid: Vector2 in LAID:
        var pressure := laid.x
        _lay(pressure, -1.0, int(laid.y))
        var picture := _picture()
        var ground := _l_star(picture.get_pixel(10, 10))
        var rows := _rows(picture, READ_FROM, READ_TO)
        var body := _body(rows, ground)
        var at := "At %.2f with seed %d" % [pressure, int(laid.y)]
        assert_true(body.y - body.x >= 10, "%s the stroke's body is %d rows across" % [at, body.y - body.x + 1])
        var spread := _spread(rows, body)
        assert_true(
            spread.y - spread.x >= APART,
            "%s its rows stand %.1f L* apart across it, at least %.0f" % [at, spread.y - spread.x, APART]
        )
        var streaks := _streaks(rows, body)
        assert_true(streaks >= 3, "and %d streaks stand %.0f L* darker than the lightest row" % [streaks, APART])
        var first_half := _rows(picture, READ_FROM, READ_MIDDLE)
        var second_half := _rows(picture, READ_MIDDLE, READ_TO)
        var furthest := 0.0
        var inner := _body(rows, ground, ALONG_RIM)
        for index in range(inner.x, inner.y + 1):
            furthest = maxf(furthest, absf(first_half[index] - second_half[index]))
        assert_true(furthest <= ALONG, "and each runs along the stroke, a row's two halves %.2f L* apart at most" % furthest)


## The grain is paint: at a full press every row of the body takes some, the
## lighter rows between the streaks among them, rather than the ground showing
## between lines. A firmer press fills them more, so at 0.9 they are only
## begun, and this holds the full press alone.
func test_a_full_press_lays_paint_across_the_whole_body() -> void:
    for laid: Vector2 in LAID:
        if laid.x < 1.0:
            continue
        _lay(laid.x, -1.0, int(laid.y))
        var picture := _picture()
        var ground := _l_star(picture.get_pixel(10, 10))
        var rows := _rows(picture, READ_FROM, READ_TO)
        var body := _body(rows, ground)
        var palest := _spread(rows, body).y
        assert_true(
            ground - palest >= 2.0,
            (
                "At %.2f with seed %d the palest row of the body is %.1f L* under the ground's %.1f"
                % [laid.x, int(laid.y), palest, ground]
            )
        )


func test_a_layer_laid_over_the_stroke_covers_the_grain_wholly() -> void:
    _lay(1.0)
    var document := _surface.easel.document
    var over := SaLayerOps.new(document).add()
    document.fill_layer(COVER, over)
    assert_false(SaRelief.shows_height(document), "A stroke at thickness 0 leaves no layer carrying height")
    var spread := _covered_spread()
    assert_true(spread.y - spread.x <= 0.5, "Over the stroke the cover is one value, %.2f to %.2f L*" % [spread.x, spread.y])
    assert_almost_eq(spread.x, _l_star(COVER), 0.5, "and it is the cover's own")


## The ask's other half, held so the suite above can see a relief: the same
## stroke at a thickness above nought shows through the same cover.
func test_a_thickness_still_shows_its_relief_through_the_layer_above() -> void:
    _lay(1.0, 0.5)
    var document := _surface.easel.document
    var over := SaLayerOps.new(document).add()
    document.fill_layer(COVER, over)
    assert_true(SaRelief.shows_height(document), "At thickness 0.5 the grain's layer carries height")
    var spread := _covered_spread()
    assert_true(spread.y - spread.x >= 2.0, "and its relief shows through the cover, %.2f to %.2f L*" % [spread.x, spread.y])


## The lowest and highest L* over the stroke in a flat export with the relief
## baked, as Export writes it by default, which lights the relief as the view
## does.
func _covered_spread() -> Vector2:
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()
    assert_eq(
        SaExport.export_png(_surface.easel, scratch_png_path, 8, false, SaGamutMapping.CLIP, true),
        OK,
        "The covered picture exports"
    )
    var picture := Image.new()
    picture.load_png_from_buffer(FileAccess.get_file_as_bytes(scratch_png_path))
    var lowest := INF
    var highest := -INF
    for y in range(int(ROW) - 40, int(ROW) + 41):
        for x in range(READ_FROM, READ_TO, 3):
            var l := _l_star(picture.get_pixel(x, y))
            lowest = minf(lowest, l)
            highest = maxf(highest, l)
    return Vector2(lowest, highest)
