## Smeary Flat opens its stroke as evenly as the rest of it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A noise stroke shows its round end under the pen, laid each update and put
## back by the next, and the composite shows it until the next frame. The
## smudge stage reads a snapshot of the composite that grows as the pickup
## moves, so a growth copied that front, the brush's own colour, and the carry
## started from it: over a white ground Smeary Flat opened on a dark blot and
## lightened a step an update as the pickup mixed it out. On the reference card its
## first window over white read 0.621 in lightness where the body read 0.770,
## and the same stroke with the stage off opened as its body did. The brush now
## takes the front's box into the snapshot before it lays the front, and makes
## the carry before the stroke's first front.
##
## The suite composites after every sample, as the app does every frame, since
## a stroke that is never composited mid-way never shows the fault.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

const CANVAS := Vector2i(768, 256)
const FROM := Vector2(80.0, 128.0)
const TO := Vector2(680.0, 128.0)
## The distance between the samples, which is the distance between dabs.
const SPACING := 4.0
const SAMPLE_MS := 8.0
const SEED := 7
const PRESSURE := 0.4
const PAINT := Color(0.55, 0.25, 0.15, 1.0)
## How far the first fifth's mean lightness may stand from the rest's.
const OPENING := 0.05
## How far two neighbouring dabs' mean lightness may stand apart.
const NEIGHBOURS := 0.03

var _surface: SaSurface = null
var _albedo: Dictionary = {}


func after_each() -> void:
    _albedo.clear()
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = null


## Over a white ground, on an empty layer, the first fifth of the stroke reads
## as light as the rest, and no dab steps from the one before it.
func test_smeary_flat_opens_as_evenly_as_the_rest_of_it() -> void:
    _holds_level(_dabs(true), "Smeary Flat")


## The same stroke with the smudge off opens evenly too, so what the first test
## holds is the smudge's and not the preset's Texture Tone.
func test_with_the_smudge_off_it_opens_as_evenly() -> void:
    _holds_level(_dabs(false), "Smeary Flat with the smudge off")


func _holds_level(dabs: Array[float], name: String) -> void:
    var fifth := maxi(1, floori(dabs.size() / 5.0))
    var opening := _mean(dabs.slice(0, fifth))
    var rest := _mean(dabs.slice(fifth))
    var step := 0.0
    for at in range(1, dabs.size()):
        step = maxf(step, absf(dabs[at] - dabs[at - 1]))
    print("%s opens at %.4f, its rest %.4f, its largest step between dabs %.4f" % [name, opening, rest, step])
    assert_true(
        absf(opening - rest) <= OPENING,
        "%s's first fifth reads %.4f, within %.2f of the rest's %.4f" % [name, opening, OPENING, rest]
    )
    assert_true(step <= NEIGHBOURS, "%s's neighbouring dabs differ by at most %.4f, no more than %.2f" % [name, step, NEIGHBOURS])


static func _mean(values: Array[float]) -> float:
    var sum := 0.0
    for value in values:
        sum += value
    return sum / maxi(1, values.size())


func _entry(smudge: bool) -> Dictionary:
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == "Smeary Flat":
            var copy := entry.duplicate(true)
            if not smudge:
                copy["settings"]["smudge_pickup_option:enabled"] = false
                copy["settings"]["smudge_length_option:enabled"] = false
            return copy
    return {}


## The mean lightness, over white, of each dab of the stroke the preset paints
## at [constant PRESSURE] on an empty layer above a white ground, a window of
## [constant SPACING] pixels along it and half the tip's radius either side of
## its line, from the press to a radius before its end. *smudge* off clears the
## preset's pickup and smear length.
func _dabs(smudge: bool) -> Array[float]:
    _albedo.clear()
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    var document := _surface.easel.document
    var ground := document.active_layer
    var cells: Array[Vector2i] = []
    var side := ground.get_or_create_chunk(Vector2i.ZERO).pixel_size()
    for gy in ceili(float(CANVAS.y) / side):
        for gx in ceili(float(CANVAS.x) / side):
            ground.get_or_create_chunk(Vector2i(gx, gy)).clear(Color.WHITE)
            cells.append(Vector2i(gx, gy))
    document.invalidate_chunks(cells)
    SaLayerOps.new(document).add()
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()
    var brush := StateNoiseBrushScript.new()
    brush.surface = _surface
    brush.stroke_seed = SEED
    brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, _entry(smudge))
    brush.settings.color = PAINT
    var clock := 1000.0
    var steps := ceili(FROM.distance_to(TO) / SPACING)
    brush.begin_stroke(FROM, 0.0, Vector2.ZERO, clock, true)
    for i in steps:
        clock += SAMPLE_MS
        brush.add_sample(FROM.lerp(TO, float(i + 1) / steps), PRESSURE, Vector2.ZERO, clock)
        _surface.easel.request_full_composite()
        _surface.easel.process_pending_composite()
    brush.end_stroke()
    var radius := ceili(brush.get_cursor_radius())
    var half := floori(radius * 0.5)
    var out: Array[float] = []
    var x := int(FROM.x)
    while x + int(SPACING) <= int(TO.x) - radius:
        var sum := 0.0
        var count := 0
        for column in range(x, x + int(SPACING)):
            for y in range(int(FROM.y) - half, int(FROM.y) + half + 1):
                var c := _texel(Vector2i(column, y))
                var over := Color(1, 1, 1).lerp(Color(c.r, c.g, c.b), c.a)
                sum += over.get_luminance()
                count += 1
        out.append(sum / count)
        x += int(SPACING)
    return out


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
