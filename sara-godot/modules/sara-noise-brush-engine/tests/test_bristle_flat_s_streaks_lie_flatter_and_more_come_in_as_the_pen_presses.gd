## Bristle Flat's streaks lie flatter and more of them come in as the pen
## presses.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Bristle Flat over grain must not lay strong noodle-like strands, and more
## bristles come in when the pen presses harder. The streaks were ridges
## of the field's own round profile, so the relief lit each one as a strand,
## and a streak's middle needed no pressure at all, so every pressure short of
## the full one laid the same streaks.
##
## Every stroke here is straight, 90 pixels in radius, on one seed, and read
## over columns more than a radius in from either end. The height is read off
## the layer: across each column a streak's middle is a top of the profile and
## the gap beside it a foot, and the step is the mean drop from one to the
## next, the tallest the highest texel. Both are held to half of what the tree
## before the change read at the same pressure, on the same card.
##
## The streaks are counted by the bristle's own cells: the stroke's width is
## cut into as many cells as the brush has bristles, and a cell counts in a
## column when a texel of its inner part is painted more than half. The count
## is the mean over the columns of a stroke two and a half runs of a bristle
## long, since one stretch shows only the bristles whose runs are on there. At
## a full press the gaps fill, so every cell counts. The tree before the change read
## 8.26, 9.21, 10.53, 11.00 and 18.00 at 0.2 to 1.0, which rise, and whose
## lightest is just under half the full press only because the gaps fill
## there. So the lightest is held to half the firm press's as well, at 0.8,
## where the gaps are still open, which the tree before read at three quarters.
##
## The eraser runs the same cut as the brush, and at a full press the old cut
## and the new both lay the whole tip, so an erase at 1.0 across a filled layer
## must leave every texel as the tree before the change left it. The fixture beside
## `paint.json` holds its SHA-256 and the adapter it was taken on, and
## another adapter skips the comparison and says so.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

const CANVAS := Vector2i(512, 512)
## The tip's radius in pixels, the stroke, the gap between two samples in
## pixels and in milliseconds, and the seed.
const RADIUS := 90.0
const FROM := Vector2(80.0, 256.0)
const TO := Vector2(432.0, 256.0)
const SPACING := 4.0
const SAMPLE_MS := 8.0
const SEED := 7
## The columns read, each more than a radius in from either end.
const FIRST_COLUMN := 200
const COLUMNS := 112
## The share of the half width either side of the path the step is read over,
## clear of the tip's rim.
const BODY := 0.8
## How close two heights side by side are to read as one flat top or foot.
const FLAT := 0.001
## The alpha a texel is painted at to count, and the share of a cell left out
## at either side, so a streak cut at its cell's edge is not read in the next.
const PAINTED := 0.5
const CELL_MARGIN := 0.15
## The long canvas the streaks are counted on, and its stroke, which runs over
## two and a half periods of a bristle's run, so the counts are the stroke's and
## not those of the few bristles one stretch of it shows.
const LONG_CANVAS := Vector2i(2048, 512)
const LONG_FROM := Vector2(80.0, 256.0)
const LONG_TO := Vector2(1968.0, 256.0)
const HEIGHT_PRESSURES: Array[float] = [0.3, 0.6, 1.0]
const COUNT_PRESSURES: Array[float] = [0.2, 0.4, 0.6, 0.8, 1.0]
## The step and the tallest height the tree before the change read at each of
## [constant HEIGHT_PRESSURES], on the reference card.
const STEP_BEFORE: Array[float] = [0.0947, 0.1599, 0.1926]
const TALLEST_BEFORE: Array[float] = [0.1165, 0.2329, 0.6606]
## The erase's fixture, and the variable that writes it from this run instead
## of reading it.
const ERASE_FIXTURE: String = "res://modules/sara-noise-brush-engine/tests/fixtures/erase.json"
const WRITE_ENV: String = "SARA_WRITE_D9_ERASE"

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
## Chunk pictures and height bytes already read back, by grid position.
var _albedo: Dictionary = {}
var _heights: Dictionary = {}


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)


func after_each() -> void:
    _brush = null
    _forget()
    Fixtures.teardown(_surface)
    _surface = null


func test_the_streaks_stand_lower_than_before_at_every_pressure() -> void:
    for at in HEIGHT_PRESSURES.size():
        var pressure := HEIGHT_PRESSURES[at]
        _fresh()
        _stroke(pressure)
        var step := _step()
        var tallest := _tallest()
        print("at %.1f the step is %.4f and the tallest %.4f" % [pressure, step, tallest])
        assert_true(step > 0.0 and tallest > 0.0, "At %.1f the stroke lays a height" % pressure)
        assert_true(
            step <= 0.5 * STEP_BEFORE[at],
            "At %.1f the step is %.4f, at most half of the %.4f before" % [pressure, step, STEP_BEFORE[at]]
        )
        assert_true(
            tallest <= 0.5 * TALLEST_BEFORE[at],
            "At %.1f the tallest is %.4f, at most half of the %.4f before" % [pressure, tallest, TALLEST_BEFORE[at]]
        )


func test_a_harder_press_lays_more_bristles() -> void:
    var counts: Array[float] = []
    for pressure: float in COUNT_PRESSURES:
        _fresh(LONG_CANVAS)
        _stroke(pressure, LONG_FROM, LONG_TO)
        counts.append(_count(int(LONG_FROM.x + 2.0 * RADIUS), int(LONG_TO.x - 2.0 * RADIUS)))
    print("the counts are %s" % [counts])
    for at in range(1, counts.size()):
        assert_true(
            counts[at] > counts[at - 1],
            (
                "%.2f streaks at %.1f, more than the %.2f at %.1f"
                % [counts[at], COUNT_PRESSURES[at], counts[at - 1], COUNT_PRESSURES[at - 1]]
            )
        )
    var cells := float(_brush.settings.bristle_count)
    assert_almost_eq(counts[-1], cells, 0.001, "A full press lays every one of the %d bristles" % int(cells))
    assert_true(
        counts[0] <= 0.5 * counts[-1],
        "The lightest touch lays %.2f, at most half the %.2f of the full press" % [counts[0], counts[-1]]
    )
    assert_true(
        counts[0] <= 0.5 * counts[-2], "and at most half the %.2f of a firm press, where the gaps are still open" % counts[-2]
    )


func test_an_eraser_at_a_full_press_erases_what_it_erased_before() -> void:
    _surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var layer := _surface.easel.document.active_layer
    var side := layer.get_or_create_chunk(Vector2i.ZERO).pixel_size()
    for gy in ceili(float(CANVAS.y) / side):
        for gx in ceili(float(CANVAS.x) / side):
            layer.get_or_create_chunk(Vector2i(gx, gy)).albedo().clear(Color(1.0, 1.0, 1.0, 1.0))
    _use()
    _brush.settings.blend_mode = SaLayer.BLEND_MODE.ERASE
    # At a Hardness of one, since the grain thins towards the rim below it, which is a separate effect.
    _brush.settings.hardness = 1.0
    _stroke(1.0)
    var erased := _hash()
    if not OS.get_environment(WRITE_ENV).is_empty():
        var file := FileAccess.open(ERASE_FIXTURE, FileAccess.WRITE)
        file.store_string(JSON.stringify({"adapter": _adapter(), "erase": erased}, "  ", true) + "\n")
        file = null
        print("wrote the erase to %s" % ERASE_FIXTURE)
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ERASE_FIXTURE))
    var recorded: Dictionary = parsed if parsed is Dictionary else {}
    assert_false(recorded.is_empty(), "the fixture holds the erase")
    if String(recorded.get("adapter", "")) != _adapter():
        skip("the fixture was taken on %s and this is %s" % [recorded.get("adapter", ""), _adapter()])
        return
    assert_eq(erased, recorded.get("erase", ""), "the erase leaves every texel as it did before the change")


## A fresh surface of *size* with Bristle Flat on it.
func _fresh(size: Vector2i = CANVAS) -> void:
    _forget()
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(size)
    _use()


## Bristle Flat as it ships, at [constant RADIUS] and [constant SEED], in black.
func _use() -> void:
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = SEED
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == "Bristle Flat":
            # Without the radius taper, so the tip is the width the streaks were measured at.
            var untapered := entry.duplicate(true)
            (untapered["pressure"] as Dictionary).erase("radius")
            _brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, untapered)
    # Bristle Flat ships at a thickness of 0, so the test sets 0.2 for the streaks to lay height to read.
    _brush.settings.thickness = 0.2
    _brush.settings.color = Color(0.0, 0.0, 0.0, 1.0)
    _brush.settings.radius = RADIUS / mini(_surface.easel.document.canvas_size.x, _surface.easel.document.canvas_size.y)


## The straight stroke from *from* to *to* at *pressure* all the way, a
## sample every [constant SPACING] pixels.
func _stroke(pressure: float, from: Vector2 = FROM, to: Vector2 = TO) -> void:
    var clock := 1000.0
    _brush.begin_stroke(from, pressure, Vector2.ZERO, clock)
    var steps := ceili(from.distance_to(to) / SPACING)
    for i in range(1, steps + 1):
        clock += SAMPLE_MS
        _brush.add_sample(from.lerp(to, float(i) / steps), pressure, Vector2.ZERO, clock)
    _brush.end_stroke()


## The mean drop from a top of the height across a column to the foot beside
## it, over every column read.
func _step() -> float:
    var total := 0.0
    var drops := 0
    var reach := int(RADIUS * BODY)
    for x in range(FIRST_COLUMN, FIRST_COLUMN + COLUMNS):
        var flats := PackedFloat32Array()
        for y in range(int(FROM.y) - reach, int(FROM.y) + reach + 1):
            var h := _height(Vector2i(x, y))
            if flats.is_empty() or absf(h - flats[flats.size() - 1]) > FLAT:
                flats.append(h)
        var turns := PackedFloat32Array()
        for i in range(1, flats.size() - 1):
            var top := flats[i] > flats[i - 1] and flats[i] > flats[i + 1]
            var foot := flats[i] < flats[i - 1] and flats[i] < flats[i + 1]
            if top or foot:
                turns.append(flats[i])
        for i in range(1, turns.size()):
            total += absf(turns[i] - turns[i - 1])
            drops += 1
    return total / drops if drops > 0 else 0.0


## The highest the stroke stands over the columns read, its whole width.
func _tallest() -> float:
    var out := 0.0
    for x in range(FIRST_COLUMN, FIRST_COLUMN + COLUMNS):
        for y in range(int(FROM.y - RADIUS), int(FROM.y + RADIUS) + 1):
            out = maxf(out, _height(Vector2i(x, y)))
    return out


## The mean count of the bristle cells painted across a column, over the
## columns from *first* up to *last*.
func _count(first: int, last: int) -> float:
    var cells: int = int(_brush.settings.bristle_count)
    var total := 0
    for x in range(first, last):
        for cell in cells:
            var low := FROM.y + RADIUS * ((cell + CELL_MARGIN) * 2.0 / cells - 1.0)
            var high := FROM.y + RADIUS * ((cell + 1.0 - CELL_MARGIN) * 2.0 / cells - 1.0)
            for y in range(ceili(low), floori(high) + 1):
                if _texel(Vector2i(x, y)).a > PAINTED:
                    total += 1
                    break
    return float(total) / (last - first)


## Every chunk's colour and height on the active layer hashed, as the bytes
## the card holds.
func _hash() -> String:
    var layer := _surface.easel.document.active_layer
    var rd := GlobalShaderCompiler.get_rd()
    var keys := layer.chunks.keys()
    keys.sort()
    var context := HashingContext.new()
    context.start(HashingContext.HASH_SHA256)
    for grid: Vector2i in keys:
        var chunk := layer.chunks[grid] as SaChunk
        context.update(("%s albedo" % grid).to_utf8_buffer())
        context.update(rd.texture_get_data(chunk.albedo().rid, 0))
        if chunk.has_field(SaFieldSpec.HEIGHT):
            context.update(("%s height" % grid).to_utf8_buffer())
            context.update(rd.texture_get_data(chunk.field(SaFieldSpec.HEIGHT).rid, 0))
    return context.finish().hex_encode()


func _adapter() -> String:
    return RenderingServer.get_video_adapter_name()


func _forget() -> void:
    _albedo.clear()
    _heights.clear()


## The side of a chunk of the active layer, nought while it has none.
func _side() -> int:
    var layer := _surface.easel.document.active_layer
    for grid: Vector2i in layer.chunks:
        return (layer.chunks[grid] as SaChunk).pixel_size()
    return 0


## The active layer's texel at *pixel*.
func _texel(pixel: Vector2i) -> Color:
    var layer := _surface.easel.document.active_layer
    var side := _side()
    if side == 0:
        return Color.TRANSPARENT
    var grid := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
    if not layer.chunks.has(grid):
        return Color.TRANSPARENT
    if not _albedo.has(grid):
        @warning_ignore("static_called_on_instance")
        _albedo[grid] = SaExport.get_texture_image_float(layer.get_field(grid))
    return (_albedo[grid] as Image).get_pixelv(pixel - grid * side)


## The active layer's height at *pixel*, nought where it holds none.
func _height(pixel: Vector2i) -> float:
    var layer := _surface.easel.document.active_layer
    var side := _side()
    if side == 0:
        return 0.0
    var grid := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
    if not layer.chunks.has(grid) or not (layer.chunks[grid] as SaChunk).has_field(SaFieldSpec.HEIGHT):
        return 0.0
    if not _heights.has(grid):
        var field := (layer.chunks[grid] as SaChunk).field(SaFieldSpec.HEIGHT)
        _heights[grid] = GlobalShaderCompiler.get_rd().texture_get_data(field.rid, 0)
    var at := pixel - grid * side
    return (_heights[grid] as PackedByteArray).decode_half((at.y * side + at.x) * 2)
