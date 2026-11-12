## Flat Brush covers fully at every radius.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A Flat Brush that ends square can still cover only 0.56 at radius 2,
## 0.78 at 3, 0.89 at 4 and 0.95 at 5, so the painter lays each run
## two or three times over. Three things thin it. The rectangle tip can take the
## kernel's pixel ramp on top of its 3×3 or 6×6 samples, which pulls its core
## in by a whole pixel, so a blade under two pixels thick was all ramp and no
## dab of it covered a texel. The walk's half pixel spacing then lays those
## fractions over each other, and fractions composited over never reach one.
## And under radius 1.5 the pixel mode binarises a blade under half a texel to
## nothing, so the dash at radius 1 lays no paint at all. Even with a blade
## that covers a texel wholly, a recipe flow of 0.8 holds the dash at 0.977
## from radius 2 to 4, where two or three dabs are all that cover a texel, so
## the flow is 1.0.
##
## Each dash runs through the real brush and the real GPU with the shipped
## recipe, from (60, 100) to (140, 100) at full pressure, and the layer's
## chunks are read back. The blade stands across the stroke, so the dash is as
## tall as the brush is wide, and its body is every texel wholly inside it,
## columns 61 to 139 and the rows whose texel lies within the radius of the
## stroke's line. The texel at either end is centred on it, the one past it may
## take what the blade's own thickness reaches, and nothing further out may
## take any paint.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The proof is paint in a chunk, so this needs a real RenderingDevice.
const REQUIRES_GPU := true

## The radii the friction named, and radius 1 below them, in document pixels.
const RADII: Array[float] = [1.0, 2.0, 3.0, 4.0, 5.0]

## The dash's ends, on texel centres, which sit at integer coordinates.
const FROM := Vector2(60.0, 100.0)
const TO := Vector2(140.0, 100.0)

## How many motion events the dash takes between its ends.
const MOTIONS: int = 4

## The cover the note asks of the body.
const FULL: float = 0.98


func test_the_dash_covers_its_body_fully_at_every_radius() -> void:
    for radius: float in RADII:
        var alpha := _laid(radius, 0.0)
        var thinnest := _thinnest_in_body(alpha, radius, FROM.y, 0.0)
        assert_true(thinnest >= FULL, "radius %.0f covers its body at least %.2f, read %.3f" % [radius, FULL, thinnest])


func test_the_dash_lays_nothing_beyond_a_pixel_past_either_end() -> void:
    for radius: float in RADII:
        var alpha := _laid(radius, 0.0)
        var stray := _most_past_the_ends(alpha)
        assert_eq(stray, 0.0, "radius %.0f lays nothing two pixels past its ends" % radius)


## A dash between texel rows covers its body just as fully. The pixel mode
## rounds the dash at radius 1 onto one row, which is its pixel line, so that
## radius is the one test above reads. Between rows the blade's tips fall on
## texel edges, and the outermost row then holds the recipe's own hardness
## ramp, 0.978 at radius 4, so the body here stops half a pixel short of the
## tips, the margin a dash on a texel row has of itself.
func test_a_dash_between_texel_rows_covers_its_body_fully() -> void:
    for radius: float in [2.0, 3.0, 4.0, 5.0]:
        var alpha := _laid(radius, 0.5)
        var thinnest := _thinnest_in_body(alpha, radius, FROM.y + 0.5, 0.5)
        assert_true(
            thinnest >= FULL, "radius %.0f half a row down covers its body at least %.2f, read %.3f" % [radius, FULL, thinnest]
        )
        assert_eq(_most_past_the_ends(alpha), 0.0, "radius %.0f half a row down lays nothing two pixels past its ends" % radius)


## The least alpha over the texels wholly inside the dash at *radius* whose
## line runs at *line_y*: inside both ends, and within the radius of the line
## less *margin*.
func _thinnest_in_body(alpha: Dictionary, radius: float, line_y: float, margin: float) -> float:
    var thinnest := 1.0
    var counted := 0
    for x in range(int(FROM.x) + 1, int(TO.x)):
        for y in range(int(line_y - radius) - 1, int(line_y + radius) + 2):
            if absf(float(y) - line_y) + 0.5 + margin > radius:
                continue
            thinnest = minf(thinnest, float(alpha.get(Vector2i(x, y), 0.0)))
            counted += 1
    assert_true(counted >= 79, "radius %.0f has a body to read" % radius)
    return thinnest


## The most alpha laid more than a pixel past either end of the dash.
func _most_past_the_ends(alpha: Dictionary) -> float:
    var most := 0.0
    for texel: Vector2i in alpha:
        if texel.x < int(FROM.x) - 1 or texel.x > int(TO.x) + 1:
            most = maxf(most, float(alpha[texel]))
    return most


func _laid(radius: float, below: float) -> Dictionary:
    var size := Vector2i(256, 256)
    var surface := Fixtures.make_surface(size)
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var brush: Object = machine.active_tool
    var settings := _recipe("Flat Brush")
    settings.radius = radius / float(mini(size.x, size.y))
    brush.settings = settings
    _stroke(surface, brush, FROM + Vector2(0.0, below), TO + Vector2(0.0, below))
    var out := _alpha(surface.easel.document)
    Fixtures.teardown(surface, machine)
    return out


func _recipe(name: String) -> SaStampBrushSettings:
    for entry: Dictionary in SaShippedPresets.entries():
        if String(entry["name"]) == name:
            return SaShippedPresets.build(StateBrushScript.BrushSettingsScript, entry) as SaStampBrushSettings
    assert_true(false, "the shipped presets carry %s" % name)
    return SaStampBrushSettings.new()


func _stroke(surface: SaSurface, brush: Object, from: Vector2, to: Vector2) -> void:
    surface.view.mouse_position = from
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = from
    brush.handle_input(press)
    for i in range(1, MOTIONS + 1):
        var at := from.lerp(to, float(i) / float(MOTIONS))
        surface.view.mouse_position = at
        var motion := InputEventMouseMotion.new()
        motion.position = at
        motion.pressure = 1.0
        brush.handle_input(motion)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    brush.handle_input(release)


## Every texel's alpha in the active layer's chunks, keyed by document texel.
func _alpha(doc: SaDocument) -> Dictionary:
    var out := {}
    var rd := GlobalShaderCompiler.get_rd()
    for grid: Vector2i in doc.active_layer.chunks:
        var chunk: SaChunk = doc.active_layer.chunks[grid]
        var side := chunk.pixel_size()
        var texture: SaTexture = chunk.albedo()
        var wide := texture.format == RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
        var texel_bytes := 16 if wide else 8
        var data: PackedByteArray = rd.texture_get_data(texture.rid, 0)
        for ty in side:
            for tx in side:
                var at := (ty * side + tx) * texel_bytes
                out[grid * side + Vector2i(tx, ty)] = data.decode_float(at + 12) if wide else data.decode_half(at + 6)
    return out
