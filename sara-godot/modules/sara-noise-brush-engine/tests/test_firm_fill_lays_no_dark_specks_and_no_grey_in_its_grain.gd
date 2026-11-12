## Firm Fill lays no dark specks and no grey in its grain, and a round blob of
## it has no notch in its rim.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Firm Fill paints in blue over an empty layer at one seed: a large blob laid
## as a scribble of strokes going back and forth over each other, as a painter
## blocks in a shape, single strokes, and a round blob, one short stroke twice
## round a small circle about its centre. Colour and height are read back from
## the layer.
##
## **What is held.** No painted texel, alpha at least [constant PAINTED], is
## darker than [constant DARKEST] of the colour's lightness, since Texture Tone
## at the preset's 0.6 may move the lightness by at most 30 percent. No painted
## texel inside the large blob's body, laid over a mid grey paper, keeps less
## than [constant GREYEST] of the colour's chroma. The view's relief light,
## worked out from the layer's height with the constants of
## [constant RELIEF_LIGHT] and the defaults of [constant GROUND_RELIEF], never
## shades a texel of a single stroke's body under [constant DARKEST], so the
## relief darkens no more than the tone may, and over the scribble no more than
## [constant SCRIBBLE_DARK] of its texels. And the round blob's rim, the painted
## radius read along every degree from its centre, never stands more than
## [constant NOTCH] texels inside the rim a few degrees either side of it.
##
## **Why these.** Texture Tone alone keeps the colour at 0.7 of its lightness
## or more, so a dark speck in the view is the relief: a height that follows
## the grain texel by texel has steps of the finest octave, and the light
## shades their far walls nearly black. A notch is the edge's nick, which a
## firm rim takes none of.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

const CANVAS := Vector2i(1024, 1024)
const PRESET := "Firm Fill"
const SEED := 11
const COLOUR := Color(0.12, 0.3, 0.85, 1.0)
const PAPER := Color(0.5, 0.5, 0.5, 1.0)
const SPACING := 1.5
const SAMPLE_MS := 8.0
## The large blob's centre and the half size of the square it is scribbled
## over, in pixels, the round blob's centre and the radius its stroke circles
## at, and the length of a single stroke.
const BLOB := Vector2(380.0, 380.0)
const BLOB_HALF := 150.0
const ROUND := Vector2(800.0, 800.0)
const ROUND_CIRCLE := 12.0
const SINGLE := 400.0
## The alpha a texel counts as painted at, the darkest share of the colour's
## lightness a painted texel may have, the least share of its chroma one inside
## the body may have, and the deepest a notch in the rim may be, in texels. A
## ray is read every quarter texel and rounded to the texel it falls in, so a
## rim of whole texels reads up to half a texel either way at one angle, and a
## notch of one texel reads up to one and a half.
const PAINTED := 0.5
const DARKEST := 0.7
const GREYEST := 0.5
const NOTCH := 1.5
## The share of a single stroke's half width either side of the path that is
## its body, and the share of the scribble's texels its relief may light under
## [constant DARKEST], where one stroke's rim lies over another's paint and the
## two heights meet in a step the width of the rim's band.
const BODY := 0.7
const SCRIBBLE_DARK := 0.005
## Where the view's light is written, read here so the suite lights the height
## as the view does.
const RELIEF_LIGHT := "res://shaders/canvas/relief_light.gdshaderinc"
const GROUND_RELIEF := "res://shaders/canvas/ground_relief.gdshaderinc"

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
## Chunk images already read back, by grid position.
var _images: Dictionary = {}
## The view's light: the steepest slope, the lift and the shade, the light's
## direction and the strength, read off the shader's files.
var _light: Dictionary = {}


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    _images.clear()


func after_each() -> void:
    _brush = null
    _images.clear()
    Fixtures.teardown(_surface)
    _surface = null


func test_no_painted_texel_is_darker_than_texture_tone_allows() -> void:
    _scribble()
    _round()
    var darkest := INF
    var worst := Vector2i.ZERO
    for rect: Rect2i in [_blob_box(), _round_box()]:
        for y in range(rect.position.y, rect.end.y):
            for x in range(rect.position.x, rect.end.x):
                var texel := _texel(Vector2i(x, y))
                if texel.a < PAINTED:
                    continue
                var share := _lightness(texel) / _lightness(COLOUR)
                if share < darkest:
                    darkest = share
                    worst = Vector2i(x, y)
    assert_true(
        darkest >= DARKEST - 1e-3,
        "A painted texel at %s reads %.3f of the colour's lightness, under %.2f" % [worst, darkest, DARKEST]
    )


func test_no_texel_inside_the_blob_is_grey() -> void:
    _scribble()
    var greyest := INF
    var worst := Vector2i.ZERO
    var inner := BLOB_HALF - _radius()
    for y in range(int(BLOB.y - inner), int(BLOB.y + inner)):
        for x in range(int(BLOB.x - inner), int(BLOB.x + inner)):
            var texel := _texel(Vector2i(x, y))
            if texel.a < PAINTED:
                continue
            var over := PAPER.lerp(Color(texel.r, texel.g, texel.b), texel.a)
            var share := _chroma(over) / _chroma(COLOUR)
            if share < greyest:
                greyest = share
                worst = Vector2i(x, y)
    assert_true(
        greyest >= GREYEST,
        (
            "A painted texel at %s inside the blob holds %.3f of the colour's chroma over the paper, under %.2f"
            % [worst, greyest, GREYEST]
        )
    )


func test_the_relief_of_a_single_stroke_lights_no_dark_speck() -> void:
    var from := BLOB - Vector2(SINGLE / 2.0, 0.0)
    var to := BLOB + Vector2(SINGLE / 2.0, 0.0)
    _stroke(PackedVector2Array([from, to]))
    var half := int(_radius() * BODY)
    var body := Rect2i(Vector2i(BLOB) - Vector2i(int(SINGLE / 4.0), half), Vector2i(int(SINGLE / 2.0), 2 * half))
    var lit := _lit(body)
    assert_eq(
        lit.x,
        0.0,
        "Texels of one stroke's body the relief lights under %.2f of the colour, the darkest at %.3f" % [DARKEST, lit.y]
    )
    _stroke(PackedVector2Array([to, from]))
    _images.clear()
    lit = _lit(body)
    assert_eq(
        lit.x,
        0.0,
        "Texels of a stroke gone back over the relief lights under %.2f of the colour, the darkest at %.3f" % [DARKEST, lit.y]
    )


func test_the_relief_of_a_scribbled_blob_lights_few_dark_texels() -> void:
    _scribble()
    var inner := int(BLOB_HALF - _radius())
    var lit := _lit(Rect2i(Vector2i(BLOB) - Vector2i(inner, inner), Vector2i(2 * inner, 2 * inner)))
    assert_true(
        lit.x <= SCRIBBLE_DARK,
        (
            "The relief lights %.2f percent of the blob under %.2f of the colour, the darkest at %.3f"
            % [lit.x * 100.0, DARKEST, lit.y]
        )
    )


func test_a_round_blob_has_no_notch_in_its_rim() -> void:
    _round()
    var reach := ROUND_CIRCLE + 2.0 * _radius()
    var radii := PackedFloat64Array()
    for degree in 360:
        var way := Vector2.from_angle(deg_to_rad(degree))
        var rim := 0.0
        var step := 0.0
        while step < reach:
            if _texel(Vector2i((ROUND + way * step).round())).a >= PAINTED:
                rim = step
            step += 0.25
        radii.append(rim)
    var deepest := 0.0
    var worst := 0
    for degree in 360:
        var before := 0.0
        var after := 0.0
        for apart in range(3, 9):
            before = maxf(before, radii[(degree - apart + 360) % 360])
            after = maxf(after, radii[(degree + apart) % 360])
        var depth := minf(before, after) - radii[degree]
        if depth > deepest:
            deepest = depth
            worst = degree
    assert_true(
        deepest <= NOTCH,
        "The round blob's rim at %d degrees stands %.2f texels inside the rim either side of it" % [worst, deepest]
    )


func _use() -> void:
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = SEED
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == PRESET:
            _brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
    _brush.settings.color = COLOUR
    _brush.settings.size_option.enabled = false


func _radius() -> float:
    if _brush == null:
        _use()
    return _brush.settings.radius * mini(CANVAS.x, CANVAS.y)


## Paints one stroke through *points*, sampled every [constant SPACING]
## pixels, at a pressure that rises and falls as a pen's does, each stroke on
## a seed of its own.
func _stroke(points: PackedVector2Array) -> void:
    var next_seed := SEED if _brush == null else _brush.stroke_seed + 1
    _use()
    _brush.stroke_seed = next_seed
    var samples := PackedVector2Array()
    for i in range(1, points.size()):
        var from := points[i - 1]
        var to := points[i]
        var count := maxi(1, int(from.distance_to(to) / SPACING))
        for k in count:
            samples.append(from.lerp(to, float(k) / count))
    samples.append(points[points.size() - 1])
    var clock := 1000.0
    for i in samples.size():
        var pressure := 0.45 + 0.4 * sin(PI * float(i) / maxf(samples.size() - 1, 1.0))
        if i == 0:
            _brush.begin_stroke(samples[i], pressure, Vector2.ZERO, clock)
        else:
            _brush.add_sample(samples[i], pressure, Vector2.ZERO, clock)
        clock += SAMPLE_MS
    _brush.end_stroke()


## The large blob: zigzags across the square one way, then the other, then
## a diagonal pass, each one stroke, so strokes cross and go back over paint.
func _scribble() -> void:
    var r := _radius()
    var lo := BLOB - Vector2(BLOB_HALF, BLOB_HALF) + Vector2(r, r)
    var hi := BLOB + Vector2(BLOB_HALF, BLOB_HALF) - Vector2(r, r)
    var rows := PackedVector2Array()
    var y := lo.y
    var right := true
    while y <= hi.y:
        rows.append(Vector2(lo.x if right else hi.x, y))
        rows.append(Vector2(hi.x if right else lo.x, y))
        right = not right
        y += r * 1.2
    _stroke(rows)
    var columns := PackedVector2Array()
    var x := lo.x
    var down := true
    while x <= hi.x:
        columns.append(Vector2(x, lo.y if down else hi.y))
        columns.append(Vector2(x, hi.y if down else lo.y))
        down = not down
        x += r * 1.5
    _stroke(columns)
    _stroke(PackedVector2Array([lo, hi, Vector2(lo.x, hi.y), Vector2(hi.x, lo.y)]))


## The round blob: one stroke twice round a small circle about its centre.
func _round() -> void:
    var points := PackedVector2Array()
    for degree in range(0, 721, 10):
        points.append(ROUND + Vector2.from_angle(deg_to_rad(degree)) * ROUND_CIRCLE)
    _stroke(points)


func _blob_box() -> Rect2i:
    return Rect2i(Vector2i(BLOB - Vector2(BLOB_HALF, BLOB_HALF)), Vector2i(2 * BLOB_HALF, 2 * BLOB_HALF))


func _round_box() -> Rect2i:
    var reach := int(ROUND_CIRCLE + 2.0 * _radius())
    return Rect2i(Vector2i(ROUND) - Vector2i(reach, reach), Vector2i(2 * reach, 2 * reach))


## The share of the texels inside *rect* the view's relief shades under
## [constant DARKEST], and the darkest shade, worked out from the layer's
## height by central differences in millimetres, as `relief_normal.gmacs` does,
## at the document's default resolution.
func _lit(rect: Rect2i) -> Vector2:
    var heights := _heights(rect.grow(1))
    var pixel_mm := 25.4 / SaDocument.DEFAULT_DPI
    var dark := 0
    var darkest := INF
    for y in range(rect.position.y, rect.end.y):
        for x in range(rect.position.x, rect.end.x):
            var at := Vector2i(x, y)
            var slope_x: float = (heights[at + Vector2i(1, 0)] - heights[at - Vector2i(1, 0)]) / (2.0 * pixel_mm)
            var slope_y: float = (heights[at + Vector2i(0, 1)] - heights[at - Vector2i(0, 1)]) / (2.0 * pixel_mm)
            var shade := _shade(Vector3(-slope_x, -slope_y, 1.0).normalized())
            darkest = minf(darkest, shade)
            if shade < DARKEST:
                dark += 1
    return Vector2(float(dark) / maxf(rect.get_area(), 1.0), darkest)


## The factor `sa_relief_shade` lights a colour by at *normal*, with no gloss,
## which only ever adds light.
func _shade(normal: Vector3) -> float:
    if _light.is_empty():
        _light = _read_light()
    var slope := Vector2(normal.x, normal.y) / maxf(normal.z, 1e-3) * float(_light["strength"])
    var steep := slope.length() / float(_light["steepest"])
    slope /= sqrt(1.0 + steep * steep)
    var n := Vector3(slope.x, slope.y, 1.0).normalized()
    var l: Vector3 = (_light["light"] as Vector3).normalized()
    var gained := n.dot(l) - l.z
    return maxf(1.0 + gained * (float(_light["lift"]) if gained > 0.0 else float(_light["shade"])), 0.0)


static func _read_light() -> Dictionary:
    var light := FileAccess.get_file_as_string(RELIEF_LIGHT)
    var ground := FileAccess.get_file_as_string(GROUND_RELIEF)
    var out := {}
    for pair: Array in [["steepest", "RELIEF_STEEPEST"], ["lift", "RELIEF_LIFT"], ["shade", "RELIEF_SHADE"]]:
        out[pair[0]] = _number(light, "const float %s = " % pair[1])
    out["strength"] = _number(ground, "uniform float relief_strength = ")
    var vector := RegEx.create_from_string("uniform vec3 relief_light = vec3\\(([^)]*)\\)").search(ground)
    var parts := vector.get_string(1).split(",")
    out["light"] = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
    return out


static func _number(text: String, before: String) -> float:
    var from := text.find(before) + before.length()
    return float(text.substr(from, text.find(";", from) - from))


## The active layer's height over *rect*, by texel.
func _heights(rect: Rect2i) -> Dictionary:
    var layer := _surface.easel.document.active_layer
    var rd := GlobalShaderCompiler.get_rd()
    var read := {}
    var side := _side()
    var out := {}
    for y in range(rect.position.y, rect.end.y):
        for x in range(rect.position.x, rect.end.x):
            var at := Vector2i(x, y)
            var grid := Vector2i(floori(float(x) / side), floori(float(y) / side))
            var texture := layer.get_field(grid, SaFieldSpec.HEIGHT) if layer.chunks.has(grid) else null
            if texture == null:
                out[at] = 0.0
                continue
            if not read.has(grid):
                read[grid] = rd.texture_get_data(texture.rid, 0)
            var local := at - grid * side
            out[at] = (read[grid] as PackedByteArray).decode_half((local.y * texture.size.x + local.x) * 2)
    return out


func _side() -> int:
    for grid: Vector2i in _surface.easel.document.active_layer.chunks:
        return (_surface.easel.document.active_layer.chunks[grid] as SaChunk).pixel_size()
    return 1


static func _lightness(texel: Color) -> float:
    return 0.2126 * texel.r + 0.7152 * texel.g + 0.0722 * texel.b


static func _chroma(texel: Color) -> float:
    return maxf(texel.r, maxf(texel.g, texel.b)) - minf(texel.r, minf(texel.g, texel.b))


## The active layer's texel at *pixel*.
func _texel(pixel: Vector2i) -> Color:
    var layer := _surface.easel.document.active_layer
    if layer.chunks.is_empty():
        return Color.TRANSPARENT
    var side := _side()
    var grid := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
    if not layer.chunks.has(grid):
        return Color.TRANSPARENT
    if not _images.has(grid):
        @warning_ignore("static_called_on_instance")
        _images[grid] = SaExport.get_texture_image_float(layer.get_field(grid))
    return (_images[grid] as Image).get_pixelv(pixel - grid * side)
