## A stroke pushes the old paint's colour and height ahead of it, far enough to
## see.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A Grain Round band is painted down the document in one colour, with a
## thickness, and a Bristle Flat stroke of another colour is
## dragged across it at a pressure that leaves holes between its streaks. Two
## of the drag's radii past the band's far side, along the stroke, what the
## stroke laid has moved at least a quarter of the way from its own colour
## towards the band's, in Oklab, stands higher than the same drag leaves over
## bare paper, and holds paint in holes the bare drag leaves empty. Five radii
## past, both read as the drag over bare paper. The document holds Oklab, so a
## texel's three channels are the coordinates the way is measured in. A flat
## fill with no height is no body to push, so the drag over it lays its own
## colour untouched past it, which is what keeps a stroke on a filled
## Background its own colour.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

## Big enough that a preset's radius, a share of the smaller side, is a dozen
## pixels, and five of them past the band stay on the canvas.
const SIZE := Vector2i(1024, 512)
## The band, a stroke down x = 300, and the drag, a stroke along the middle row
## that crosses it and runs on well past five radii beyond it.
const BAND_X := 300.0
const BAND_FROM := Vector2(BAND_X, 120.0)
const BAND_TO := Vector2(BAND_X, 392.0)
const ROW := 256.0
const DRAG_FROM := Vector2(120.0, ROW)
const DRAG_TO := Vector2(760.0, ROW)
## The two colours in display terms, the band's an ochre and the drag's a blue.
const BAND_COLOUR := Color(0.69, 0.44, 0.24)
const DRAG_COLOUR := Color(0.24, 0.42, 0.69)
## Below a full press, so the Bristle Flat's cut leaves holes between its
## streaks, where a push laid only under the streaks would land nothing.
const DRAG_PRESSURE := 0.6
## How far across the stroke a window reads, as a share of the drag's radius,
## and how far along it, in pixels either side of its middle.
const ACROSS := 0.8
const ALONG := 2
## The alpha a texel counts as painted at.
const PAINTED := 0.05
## The flat fill's colour, stored without a height.
const FILL := Color(1.0, 0.0, 0.0, 1.0)
## The thicknesses the band and the drag are laid at, the two presets
## ship at none, which lays no height to
## push. What is measured is the push of a body of paint, so each is given the
## body it had.
const BAND_THICKNESS := 0.3
const DRAG_THICKNESS := 0.4

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
## The active layer's chunks read back, by grid position, dropped whenever the
## layer changes.
var _read: Dictionary[Vector2i, Image] = {}


func before_each() -> void:
    _fresh()


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null


## Two radii past the band the drag's colour has moved a quarter of the way
## towards the band's and its surface stands higher than over bare paper, with
## paint in its holes, and five radii past both are the bare drag's.
func test_two_radii_past_the_band_the_drag_carries_its_colour_and_height() -> void:
    _band()
    var band := _colour(Rect2i(int(BAND_X) - 2, int(ROW) - 40, 5, 81))
    var far := _far_side()
    var radius := _radius_of("Bristle Flat")
    var near_window := _window(far + 2.0 * radius, radius)
    var far_window := _window(far + 5.0 * radius, radius)
    _drag()
    var pushed := [_colour(near_window), _summed(near_window), _painted(near_window)]
    var pushed_far := [_colour(far_window), _summed(far_window)]
    _fresh()
    _drag()
    var bare := [_colour(near_window), _summed(near_window), _painted(near_window)]
    var bare_far := [_colour(far_window), _summed(far_window)]

    var moved := _way(bare[0], band, pushed[0])
    print(
        (
            "  band far side %.1f, radius %.1f, way %.3f, height %.2f against %.2f, painted %d against %d"
            % [far, radius, moved, pushed[1], bare[1], pushed[2], bare[2]]
        )
    )
    assert_true(
        moved >= 0.25,
        "Two radii past the band the drag has moved %.3f of the way towards the band's colour, at least a quarter" % moved
    )
    assert_true(pushed[1] > bare[1] * 1.05, "and its surface holds %.2f, over bare paper %.2f" % [pushed[1], bare[1]])
    assert_true(pushed[2] > bare[2], "and paint lands in %d texels where the bare drag's holes leave %d" % [pushed[2], bare[2]])
    var moved_far := _way(bare_far[0], band, pushed_far[0])
    print("  five radii past, way %.4f, height %.3f against %.3f" % [moved_far, pushed_far[1], bare_far[1]])
    assert_true(absf(moved_far) < 0.01, "Five radii past the colour is the bare drag's, %.4f of the way" % moved_far)
    assert_almost_eq(pushed_far[1], bare_far[1], 0.01, "and so is the surface")


## A flat fill with no height is not wet paint with a body, so the drag across
## it and on past it lays its own colour there, as over bare paper.
func test_a_flat_fill_with_no_height_is_not_pushed() -> void:
    var layer := _surface.easel.document.active_layer
    var chunk := layer.get_or_create_chunk(Vector2i(1, 0))
    chunk.clear(FILL)
    _surface.easel.document.invalidate_chunks([Vector2i(1, 0)])
    var edge := 2.0 * float(chunk.pixel_size())
    var radius := _radius_of("Bristle Flat")
    var window := _window(edge + 2.0 * radius, radius)
    _drag()
    var over_fill := _colour(window)
    _fresh()
    _drag()
    var bare := _colour(window)
    assert_true(_distance(over_fill, bare) < 0.001, "Past the fill the drag lays %s, over bare paper %s" % [over_fill, bare])


## A fresh document holding Oklab, with no ground, so the relief is the active
## layer's own height, and a noise brush on it.
func _fresh() -> void:
    _read.clear()
    if _surface != null:
        Fixtures.teardown(_surface)
    var space := SaColorSpace.oklab().with_depth(SaColorSpace.Depth.F16)
    _surface = SaSurface.create(&"test", SaEasel.create_default(SIZE, null, space), Fixtures.FakeView.new())
    assert_eq(_surface.easel.document.color_space.coordinates, SaColorSpace.Coordinates.OKLAB, "The document stores Oklab")
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7


## The settings of the preset called *name* on the brush, in *colour* and at
## *thickness*, at the whole width whatever the pressure. Both presets taper
## with the pen, and the windows here are read at the preset's whole radius, so
## the taper is turned off: what is measured is the push, not the width.
func _preset(name: String, colour: Color, thickness: float) -> void:
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == name:
            _brush.settings = NoisePresetsScript.build(NoiseSettingsScript, entry)
    _brush.settings.color = colour
    _brush.settings.thickness = thickness
    _brush.settings.size_option.enabled = false


## The tip radius of the preset called *name* on this document, in pixels.
func _radius_of(name: String) -> float:
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == name:
            return float(entry["settings"]["radius"]) * mini(SIZE.x, SIZE.y)
    return 0.0


func _band() -> void:
    _preset("Grain Round", BAND_COLOUR, BAND_THICKNESS)
    _stroke(BAND_FROM, BAND_TO, 1.0)


func _drag() -> void:
    _preset("Bristle Flat", DRAG_COLOUR, DRAG_THICKNESS)
    _stroke(DRAG_FROM, DRAG_TO, DRAG_PRESSURE)


## A stroke from *from* to *to* at *pressure*, sample by sample four pixels
## apart, as a pen would lay it.
func _stroke(from: Vector2, to: Vector2, pressure: float) -> void:
    _brush.begin_stroke(from, pressure)
    var steps := ceili(from.distance_to(to) / 4.0)
    for i in range(1, steps + 1):
        _brush.add_sample(from.lerp(to, float(i) / steps), pressure)
    _brush.end_stroke()
    _read.clear()


## The window a reading takes at *x* along the drag's row: a few pixels along
## and most of the stroke's width across, for a tip of *radius*.
func _window(x: float, radius: float) -> Rect2i:
    var half := int(radius * ACROSS)
    return Rect2i(int(x) - ALONG, int(ROW) - half, 2 * ALONG + 1, 2 * half + 1)


## How far right of the band's middle its paint reaches, near the drag's row.
func _far_side() -> float:
    var far := BAND_X
    for y in range(int(ROW) - 4, int(ROW) + 5):
        for x in range(int(BAND_X), int(BAND_X) + 64):
            if _texel(Vector2i(x, y)).a >= PAINTED:
                far = maxf(far, float(x))
    return far


## The colour the active layer holds over *rect*, each texel's weighed by its
## alpha.
func _colour(rect: Rect2i) -> Vector3:
    var sum := Vector3.ZERO
    var weight := 0.0
    for y in rect.size.y:
        for x in rect.size.x:
            var texel := _texel(rect.position + Vector2i(x, y))
            sum += Vector3(texel.r, texel.g, texel.b) * texel.a
            weight += texel.a
    return sum / weight if weight > 0.0 else Vector3.ZERO


## How many texels of *rect* the active layer holds paint in.
func _painted(rect: Rect2i) -> int:
    var count := 0
    for y in rect.size.y:
        for x in rect.size.x:
            if _texel(rect.position + Vector2i(x, y)).a >= PAINTED:
                count += 1
    return count


## How far *reading* has moved from *own* towards *towards*, along the line
## between them, nought at *own* and one at *towards*.
static func _way(own: Vector3, towards: Vector3, reading: Vector3) -> float:
    var line := towards - own
    return (reading - own).dot(line) / line.length_squared()


static func _distance(one: Vector3, other: Vector3) -> float:
    return (one - other).length()


## The active layer's texel at *pixel*, transparent where it holds no chunk.
func _texel(pixel: Vector2i) -> Color:
    var layer := _surface.easel.document.active_layer
    for grid: Vector2i in layer.chunks:
        var chunk := layer.chunks[grid] as SaChunk
        var side := chunk.pixel_size()
        if Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side)) != grid:
            continue
        if not _read.has(grid):
            @warning_ignore("static_called_on_instance")
            _read[grid] = SaExport.get_texture_image_float(layer.get_field(grid))
        return _read[grid].get_pixelv(pixel - grid * side)
    return Color.TRANSPARENT


## The surface the view sums over *rect*, added up texel by texel, in virtual
## millimetres, read off the relief after a full composite.
func _summed(rect: Rect2i) -> float:
    var easel := _surface.easel
    easel.request_full_composite()
    easel.process_pending_composite()
    var heights := easel.relief.heights
    if heights == null:
        return 0.0
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(heights.rid, 0)
    var sum := 0.0
    for y in rect.size.y:
        for x in rect.size.x:
            var at := rect.position + Vector2i(x, y)
            sum += bytes.decode_half((at.y * heights.size.x + at.x) * 2)
    return sum
