## The noise brush deposits height: the field's lightness is the bump, and it
## goes into the layer's height through the door's deposition library, never
## into the colour. The surface under the stroke moves towards
## the brush's own height rather than building on what is there, and the layer
## keeps the difference from the surface beneath it, signed (design 3 of the
## impasto rework, which took the ceiling away).
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A stroke with Thickness up leaves a height that follows the field's
## lightness, read against the probe kernel's reading of the same field, and a
## stroke at a Thickness of nought leaves the layer without a height field.
## Over relief already there, the stroke levels a lower layer's bump without
## touching that layer, overlays the paper's fibres, and mixes with its own
## paint where it crosses itself at a Build Up of nought, since a return at
## one above it stands higher (`noise_built_up_height`). Every height is read off the layer, and every
## surface off the relief the view sums, so each is what the card holds.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")

const RADIUS := 14.0
## The stroke, a straight line along y = 60 far enough from the chunk's edges
## that the window below is crossed by the whole tip every time.
const FROM := Vector2(20.0, 60.0)
const TO := Vector2(100.0, 60.0)
## Texels near the line and away from its ends, each covered whole by the tip.
const WINDOW := Rect2i(44, 56, 32, 9)
## How far from a texel the ring of readings its height is the mean of lies,
## `NOISE_RELIEF_REACH`, and the margin the field is probed with to hold it.
const REACH := 3.0
const RING := 4
## How far over that mean a texel may stand, in millimetres. The ring's readings
## fall between texels, where the kernel reads the grain itself and the suite a
## bilinear blend of the four texels round it, which differ by up to a hundredth
## of the grain's range.
const OVER := 0.02
## Virtual millimetres at full.
const THICKNESS := 1.0
## The bump a lower layer holds, in virtual millimetres.
const BUMP := 2.0
## A stroke that crosses its own first arm: right along y = 60, down, back
## left, and up through the first arm at 60, 60.
const CROSS_PATH: Array[Vector2] = [
    Vector2(20.0, 60.0), Vector2(110.0, 60.0), Vector2(110.0, 110.0), Vector2(60.0, 110.0), Vector2(60.0, 20.0)
]
## Where the last leg crosses the first, and a stretch of each arm away from
## the crossing and from every turn, all inside the tip's full width.
const CROSSING := Rect2i(55, 55, 11, 11)
const FIRST_ARM := Rect2i(80, 55, 11, 11)
const LAST_ARM := Rect2i(55, 26, 11, 11)

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7
    _brush.settings.color = Color(0.2, 0.4, 0.8, 1.0)
    _brush.settings.opacity = 1.0
    _brush.settings.hardness = 1.0
    # No shift, so a full press paints every texel the tip reaches at full
    # alpha, and the height is the lightness's alone and not the holes'.
    _brush.settings.strength = 0.0
    _brush.settings.strength_option.enabled = false
    _brush.settings.radius = RADIUS / 256.0
    # Two channels, so the lightness is a reading of its own and a height that
    # followed the coverage instead would be told apart.
    _brush.settings.texture_field = "grain"
    _brush.settings.texture_channels = 2
    _brush.settings.texture_relief = 1.0
    _brush.settings.thickness = THICKNESS


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null


## The row is on the General page after Strength with a randomise row under
## it, half a millimetre by default, and its curve option starts on pressure.
func test_the_thickness_row_sits_after_strength_at_half_a_millimetre() -> void:
    var keys: Array[String] = []
    var row: SaOptionSpec = null
    for spec: SaOptionSpec in NoiseModuleScript.options():
        if spec.page == NoiseModuleScript.PAGE:
            keys.append(String(spec.key))
        if spec.key == &"thickness":
            row = spec
    assert_not_null(row, "The page has a Thickness row")
    assert_eq(
        keys.find("thickness"), keys.find("strength_random") + 1, "right after Strength and its randomise row, %s" % str(keys)
    )
    assert_eq(keys[keys.find("thickness") + 1], "thickness_random", "with its own randomise row under it")
    assert_eq(row.suffix, "mm", "in virtual millimetres")
    var fresh := NoiseBrushSettingsScript.new()
    assert_almost_eq(fresh.thickness, 0.5, 0.00001, "Half a millimetre at full by default")
    var option: SaCurveOption = fresh.thickness_option
    assert_true(option.enabled, "The Thickness option is on")
    assert_true(option.sensor_for(SaSensor.Id.PRESSURE).active, "on pressure, beside tilt and speed")


## A stroke with Thickness up over a bare layer leaves the height following the
## field's lightness, taken as its mean over a small ring as `noise_relief`
## takes it: never above that mean times Thickness, the brush's own height, at
## it wherever the stroke covers, and apart from the coverage where the two
## channels differ.
func test_a_stroke_lays_height_that_follows_the_fields_lightness() -> void:
    _stroke(1.0)
    var layer := _surface.easel.document.active_layer
    assert_true(layer.carries_height(), "The stroke gained the layer its height")
    var heights := _heights(layer)
    var field := _field(RING)
    var above := 0.0
    var short := 0.0
    var apart := 0.0
    var sum_lh := 0.0
    var sum_l := 0.0
    var sum_h := 0.0
    var sum_ll := 0.0
    var sum_hh := 0.0
    var count := 0
    for y in WINDOW.size.y:
        for x in WINDOW.size.x:
            var at := WINDOW.position + Vector2i(x, y)
            var reading := field.get_pixel(x + RING, y + RING)
            var ceiling := _ring_mean(field, Vector2(x + RING, y + RING)) * THICKNESS
            var height: float = heights[at]
            above = maxf(above, height - ceiling)
            short = maxf(short, ceiling - height)
            apart = maxf(apart, absf(reading.r * THICKNESS - height))
            sum_l += ceiling
            sum_h += height
            sum_lh += ceiling * height
            sum_ll += ceiling * ceiling
            sum_hh += height * height
            count += 1
    var covariance := sum_lh / count - (sum_l / count) * (sum_h / count)
    var spread_l := sqrt(maxf(sum_ll / count - pow(sum_l / count, 2.0), 0.0))
    var spread_h := sqrt(maxf(sum_hh / count - pow(sum_h / count, 2.0), 0.0))
    var correlation := covariance / maxf(spread_l * spread_h, 0.000001)
    assert_true(spread_l > 0.05, "The window has light and dark grain to follow, spread %.3f" % spread_l)
    assert_true(above < OVER, "No texel stands above its lightness times Thickness, at most %.4f mm over" % above)
    assert_true(short < 0.03, "and every texel the stroke covers reaches it, at most %.4f mm short" % short)
    assert_true(correlation > 0.99, "so the height follows the lightness, correlation %.4f" % correlation)
    assert_true(apart > 0.1, "and not the coverage, up to %.3f mm from it" % apart)
    var colour := _alpha_at(layer, Vector2i(60, 60))
    assert_true(colour > 0.99, "The colour lands whole, the lightness never in it, alpha %.3f" % colour)


## Pressure multiplies the deposit: the same stroke at half pressure stands
## at half the height, texel for texel. Strength at minus one shifts the whole
## field under any pressure, so half a press paints every texel a full one does
## and the height alone tells the two apart.
func test_half_pressure_lays_half_the_height() -> void:
    _brush.settings.strength = -1.0
    _stroke(1.0)
    var full := _heights(_surface.easel.document.active_layer)
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface()
    _brush.surface = _surface
    _stroke(0.5)
    var half := _heights(_surface.easel.document.active_layer)
    var worst := 0.0
    for at: Vector2i in full:
        worst = maxf(worst, absf(float(half[at]) - 0.5 * float(full[at])))
    assert_true(worst < 0.02, "Half pressure stands at half the height, within %.4f mm" % worst)


## A Thickness of nought writes no height and gains the layer nothing, while
## the stroke paints as before.
func test_a_thickness_of_nought_gains_the_layer_no_height() -> void:
    _brush.settings.thickness = 0.0
    _stroke(1.0)
    var layer := _surface.easel.document.active_layer
    assert_true(_alpha_at(layer, Vector2i(60, 60)) > 0.99, "The stroke painted")
    assert_false(layer.carries_height(), "and the layer carries no height")
    for grid: Vector2i in layer.chunks:
        assert_false((layer.chunks[grid] as SaChunk).has_field(SaFieldSpec.HEIGHT), "nor any chunk of it, %s" % grid)


## An erasing stroke lays none either: the document lowers height under a
## wash eraser as it goes, and a noise eraser adds nothing to it.
func test_an_erasing_stroke_gains_the_layer_no_height() -> void:
    _brush.settings.blend_mode = SaLayer.BLEND_MODE.ERASE
    _stroke(1.0)
    assert_false(_surface.easel.document.active_layer.carries_height(), "An eraser gains the layer no height")


## The paint load is a settings key a preset sets and not a row on the page,
## fully loaded by default, and a brush loaded by half closes half the gap to
## its own height in the one pass a stroke makes over bare paper.
func test_the_paint_load_is_a_key_with_no_row_and_closes_its_share_of_the_gap() -> void:
    var keys: Array[String] = []
    for spec: SaOptionSpec in NoiseModuleScript.options():
        keys.append(String(spec.key))
    assert_false(keys.has("paint_load"), "The page has no row for the paint load")
    assert_almost_eq(NoiseBrushSettingsScript.new().paint_load, 1.0, 0.00001, "A brush is fully loaded by default")
    _flat_brush(2.0)
    _brush.settings.paint_load = 0.5
    _stroke(1.0)
    var worst := 0.0
    for height: float in _heights(_surface.easel.document.active_layer).values():
        worst = maxf(worst, absf(height - 0.5))
    assert_true(worst < 0.002, "Half loaded, a 1 mm brush brings bare paper to 0.5 mm, within %.4f mm" % worst)


## Paints over a bump a lower layer holds with a stroke whose height is below
## the bump's. The lower layer keeps its own height, the stroke's layer holds
## the difference, negative, and the sum the view shows is lowered. Hiding the
## stroke's layer gives the bump back.
func test_a_stroke_below_a_lower_layers_bump_lowers_the_sum_and_hiding_it_gives_the_bump_back() -> void:
    var doc := _surface.easel.document
    var below := doc.active_layer
    _raise(below, Vector2i.ZERO, BUMP)
    var upper := SaLayerOps.new(doc).add()
    # A 0.5 mm brush over the 2 mm bump moves it by a quarter of the gap, the
    # brush's height over the bump's, so the sum stands at 1.625.
    _flat_brush(1.0)
    _stroke(1.0)
    var lowered := _relief(WINDOW)
    var own := _heights(below)
    var stored := _heights(upper)
    var kept := 0.0
    var off_sum := 0.0
    var off_stored := 0.0
    for at: Vector2i in own:
        kept = maxf(kept, absf(float(own[at]) - BUMP))
        off_sum = maxf(off_sum, absf(float(lowered.get(at, BUMP)) - 1.625))
        off_stored = maxf(off_stored, absf(float(stored[at]) + 0.375))
    assert_eq(kept, 0.0, "The lower layer keeps its own 2 mm at every texel")
    assert_true(off_sum < 0.004, "The sum under the stroke is lowered to 1.625 mm, within %.4f mm" % off_sum)
    assert_true(off_stored < 0.004, "and the stroke's layer holds the -0.375 it took off, within %.4f mm" % off_stored)
    upper.visible = false
    var back := 0.0
    for height: float in _relief(WINDOW).values():
        back = maxf(back, absf(height - BUMP))
    assert_true(back < 0.002, "Hiding the stroke's layer gives the 2 mm bump back, within %.4f mm" % back)


## A full strength stroke over the paper's tooth brings the surface to within
## a tenth of the brush's height wherever it covers, so the fibres are
## overlaid: the surface the stroke sees, the paper's tooth beneath its layer
## plus the layer's own height, stands at the brush's height where it stood at
## the tooth before, and the layer holds the brush's height less the tooth.
## The view's relief adds the tooth whole under the layer's height and shows
## the same flat surface, since the stroke and not the view fills the tooth.
func test_a_full_stroke_over_the_papers_tooth_brings_the_surface_to_the_brushs_height() -> void:
    var doc := _surface.easel.document
    var painted := doc.active_layer
    var registries := Fixtures.make_registries(_surface)
    SaLayerOps.new(doc).add(&"paper", registries.layer_types)
    doc.set_active_layer(painted)
    var fibres := _span(_relief(WINDOW).values())
    assert_true(
        fibres.y - fibres.x > 0.05, "The paper's tooth stands from %.4f to %.4f mm before the stroke" % [fibres.x, fibres.y]
    )
    # A brush of 1 mm, the field's lightness of a half times 2 mm.
    _flat_brush(2.0)
    _stroke(1.0)
    var own := _heights(painted)
    var beneath := _read_chunk(SaStrokeHeights.new(doc, painted).beneath(Vector2i.ZERO))
    var surface := PackedFloat32Array()
    for at: Vector2i in own:
        surface.append(float(own[at]) + beneath[at.y * SaChunk.SIZE + at.x])
    var stands := _span(Array(surface))
    var held := _span(own.values())
    assert_true(
        stands.x > 0.9 and stands.y < 1.1, "The surface stands from %.4f to %.4f mm under a 1 mm brush" % [stands.x, stands.y]
    )
    assert_true(
        stands.y - stands.x < (fibres.y - fibres.x) * 0.1,
        "flat where the tooth spanned %.4f mm, %.4f mm" % [fibres.y - fibres.x, stands.y - stands.x]
    )
    assert_true(
        held.x < 1.0 - fibres.y + 0.01 and held.y > 1.0 - fibres.x - 0.01,
        "The layer holds the brush's height less the tooth, from %.4f to %.4f mm" % [held.x, held.y]
    )
    var shown := _span(_relief(WINDOW).values())
    assert_true(
        shown.x > 0.9 and shown.y < 1.1 and shown.y - shown.x < (fibres.y - fibres.x) * 0.1,
        "and the view's relief stands from %.4f to %.4f mm, the fibres overlaid" % [shown.x, shown.y]
    )


## A stroke that crosses itself mixes with its own paint by the same rule and
## stands no higher at the crossing than on either arm. With one height all
## along it, the crossing stands at that height. With the later arm at half
## the pressure, which cuts that arm to the texels it paints whole,
## each texel it paints at the crossing mixes the two and lands between them.
func test_a_stroke_crossing_itself_stands_no_higher_at_the_crossing_than_on_either_arm() -> void:
    _flat_brush(1.0)
    _brush.settings.build_up = 0.0
    _cross(1.0, 1.0)
    var layer := _surface.easel.document.active_layer
    var first := _span(_heights(layer, FIRST_ARM).values())
    var last := _span(_heights(layer, LAST_ARM).values())
    var crossing := _span(_heights(layer, CROSSING).values())
    assert_almost_eq(first.y, 0.5, 0.002, "The first arm stands at the brush's 0.5 mm")
    assert_almost_eq(last.y, 0.5, 0.002, "and so does the arm that crosses it")
    assert_true(
        crossing.y <= minf(first.y, last.y) + 0.001, "The crossing stands no higher than either arm, at most %.4f mm" % crossing.y
    )
    assert_true(crossing.x >= 0.498, "and no lower, at least %.4f mm" % crossing.x)

    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface()
    _brush.surface = _surface
    _brush.settings.thickness_option = SaCurveOption.create_default()
    _brush.settings.thickness_option.enabled = true
    _cross(1.0, 0.5)
    layer = _surface.easel.document.active_layer
    first = _span(_heights(layer, FIRST_ARM).values())
    last = _span(_heights(layer, LAST_ARM).values())
    crossing = _span(_heights(layer, CROSSING).values())
    assert_almost_eq(last.y, 0.25, 0.002, "At half the pressure the crossing arm stands at 0.25 mm where it paints")
    assert_true(crossing.y <= first.y + 0.001, "The crossing stands no higher than the first arm, at most %.4f mm" % crossing.y)
    # The surface at 0.5 gives way to a 0.25 mm brush by a half, to 0.375,
    # wherever the later arm paints, and stays where the cut left it bare.
    var reached := 0
    var off := 0.0
    for height: float in _heights(layer, CROSSING).values():
        if height < first.x - 0.01:
            reached += 1
            off = maxf(off, absf(height - 0.375))
    assert_true(reached > 10, "The later arm paints %d texels of the crossing" % reached)
    assert_true(off < 0.01, "and each stands between the arms at the rule's 0.375, within %.4f mm" % off)


## The stroke from [constant FROM] to [constant TO] at *pressure*, sample by
## sample a few pixels apart, as a pen would lay it.
func _stroke(pressure: float) -> void:
    _brush.begin_stroke(FROM, pressure)
    var steps := 20
    for i in range(1, steps + 1):
        _brush.add_sample(FROM.lerp(TO, float(i) / steps), pressure)
    _brush.end_stroke()


## A brush whose own height is the same everywhere: the field's lightness held
## at a half by a relief of nought, and *thickness* with its sensors off, so
## the brush stands at half of *thickness* wherever it covers.
func _flat_brush(thickness: float) -> void:
    _brush.settings.texture_relief = 0.0
    _brush.settings.thickness = thickness
    _brush.settings.thickness_option.enabled = false


## The stroke along [constant CROSS_PATH], which crosses its own first arm,
## the first two legs at *first* pressure and the last two at *last*.
func _cross(first: float, last: float) -> void:
    _brush.begin_stroke(CROSS_PATH[0], first)
    for leg in CROSS_PATH.size() - 1:
        var pressure := first if leg < 2 else last
        for i in range(1, 11):
            _brush.add_sample(CROSS_PATH[leg].lerp(CROSS_PATH[leg + 1], i / 10.0), pressure)
    _brush.end_stroke()


## Gives *layer* a height of *mm* at every texel of the chunk at *grid_pos*.
func _raise(layer: SaLayer, grid_pos: Vector2i, mm: float) -> void:
    var doc := _surface.easel.document
    SaHeightOps.new(doc).gain(layer)
    var texture := layer.get_or_create_field(grid_pos, SaFieldSpec.HEIGHT)
    var bytes := PackedByteArray()
    bytes.resize(texture.size.x * texture.size.y * 2)
    for i in texture.size.x * texture.size.y:
        bytes.encode_half(i * 2, mm)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)
    doc.invalidate_chunks([grid_pos])


## The surface the view sums over *rect*, by document texel: every layer that
## shows and the grounds' tooth, read off the relief after a full composite.
func _relief(rect: Rect2i) -> Dictionary:
    var easel := _surface.easel
    easel.request_full_composite()
    easel.process_pending_composite()
    var out := {}
    var heights := easel.relief.heights
    if heights == null:
        return out
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(heights.rid, 0)
    for y in rect.size.y:
        for x in rect.size.x:
            var at := rect.position + Vector2i(x, y)
            out[at] = bytes.decode_half((at.y * heights.size.x + at.x) * 2)
    return out


## Every texel of *texture*, a chunk at the document's resolution, row by row.
static func _read_chunk(texture: SaTexture) -> PackedFloat32Array:
    var found := PackedFloat32Array()
    if texture == null:
        return found
    found.resize(texture.size.x * texture.size.y)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    for i in found.size():
        found[i] = bytes.decode_half(i * 2)
    return found


## The lowest and highest of *values*, in x and y.
static func _span(values: Array) -> Vector2:
    var span := Vector2(INF, -INF)
    for value: float in values:
        span = Vector2(minf(span.x, value), maxf(span.y, value))
    return span


## The layer's height over *rect*, [constant WINDOW] by default, by document
## texel, nought where it holds none.
func _heights(layer: SaLayer, rect: Rect2i = WINDOW) -> Dictionary:
    var out := {}
    var rd := GlobalShaderCompiler.get_rd()
    var read := {}
    var side := _side(layer)
    for y in rect.size.y:
        for x in rect.size.x:
            var at := rect.position + Vector2i(x, y)
            var grid := Vector2i(floori(float(at.x) / side), floori(float(at.y) / side))
            var texture := layer.get_field(grid, SaFieldSpec.HEIGHT)
            if texture == null:
                out[at] = 0.0
                continue
            if not read.has(grid):
                read[grid] = rd.texture_get_data(texture.rid, 0)
            var local := at - grid * side
            out[at] = (read[grid] as PackedByteArray).decode_half((local.y * texture.size.x + local.x) * 2)
    return out


## The field the stroke painted through over [constant WINDOW], the pressure
## map in red and lightness in green, read by the probe kernel on the stroke's
## own seed in its own coordinates, along from [constant FROM].
func _field(margin: int = 0) -> Image:
    _brush.lay_field(7)
    @warning_ignore("static_called_on_instance")
    return SaExport.get_texture_image_float(_brush.probe_field(WINDOW.grow(margin), FROM, Vector2(1.0, 0.0), 0.0, RADIUS))


## The lightness the height follows at *at* in *field*: the mean of the reading
## there and of eight on a ring [constant REACH] texels round it, as
## `noise_relief` takes it, each read between texels by a bilinear blend.
func _ring_mean(field: Image, at: Vector2) -> float:
    var sum := field.get_pixelv(Vector2i(at)).g
    for i in 8:
        var there := at + Vector2.from_angle(PI / 4.0 * i) * REACH
        var low := Vector2i(there.floor())
        var part := there - Vector2(low)
        var top := lerpf(field.get_pixelv(low).g, field.get_pixelv(low + Vector2i(1, 0)).g, part.x)
        var bottom := lerpf(field.get_pixelv(low + Vector2i(0, 1)).g, field.get_pixelv(low + Vector2i(1, 1)).g, part.x)
        sum += lerpf(top, bottom, part.y)
    return sum / 9.0


func _alpha_at(layer: SaLayer, pixel: Vector2i) -> float:
    var side := _side(layer)
    var grid := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
    if not layer.chunks.has(grid):
        return 0.0
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(layer.get_field(grid))
    return image.get_pixelv(pixel - grid * side).a


## The side of the layer's chunks in pixels, asked of a chunk rather than
## assumed, by hard rule 3 (sparse chunks).
func _side(layer: SaLayer) -> int:
    for grid: Vector2i in layer.chunks:
        return (layer.chunks[grid] as SaChunk).pixel_size()
    return 1
