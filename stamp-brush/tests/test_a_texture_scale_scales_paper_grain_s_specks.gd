## A brush's texture scale scales a generated pattern's specks.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A wash swept through Paper Grain at scales of a quarter, a half and
## one must not lay one mottle about five pixels across each time. A dab that
## made the paper again at the tile times the scale, with a kernel counting its
## cells over whatever tile it was handed, eight texels each,
## would carry fewer cells of the same size in a smaller tile. The kernel is told
## the zoom beside the tile and counts its cells over the pattern's own tile.
##
## **The speck is read off the paint**, not off the tile: the same stroke is laid
## through the real brush at each scale, its alpha read inside the stroke where
## the tip covers in full, and the speck's size is how far the grain stays alike,
## the area under the alpha's autocorrelation out to where it first stops being
## positive. A paper drawn at a quarter of its size is the same paper read four
## texels at a time, so that area is a quarter of the area at one.
extends "res://tests/test_framework.gd"

## A stroke and its readback are GPU work.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

const PAPER := "Paper Grain"
const SCALES: Array[float] = [0.25, 0.5, 1.0]

## How far from proportional a speck may be, the clause's own figure.
const PROPORTIONAL := 0.2

## The stroke runs along the middle of the one chunk, wide enough that a band
## of rows either side of its line is covered in full by every dab's disc.
const LINE_Y := 128.0
const FROM_X := 32.0
const TO_X := 224.0
const RADIUS_PX := 40.0

## The window the speck is read in, inside the band the tip covers in full and
## clear of the stroke's two round ends.
const WINDOW := Rect2i(72, 108, 112, 40)

## The longest lag read, in texels. The correlation at one first stops being
## positive near lag ten, so this reaches past it at every scale.
const LAGS := 16

## The side of the small tiles the second case draws, and the paper's cell at a
## zoom of one, in texels, which is Paper Grain's own `scale`.
const SMALL := 64
const CELL := 8

const FRAME := 1.0 / 60.0

var _surface: SaSurface = null


func after_each() -> void:
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = null


## The clause: the same stroke at the three scales lays a speck that grows with
## the scale, each within a fifth of proportional to the speck at one.
func test_the_speck_grows_with_the_scale() -> void:
    var specks: Dictionary[float, float] = {}
    for scale: float in SCALES:
        specks[scale] = _speck(_lay(scale))
    var at_one := specks[1.0]
    assert_true(at_one > 1.0, "At a scale of one the speck is wider than a texel, at %.3f" % at_one)
    for scale: float in SCALES:
        var ratio := specks[scale] / at_one
        var said := "At %.2f the speck is %.3f texels, %.3f of the one at one" % [scale, specks[scale], ratio]
        assert_true(absf(ratio / scale - 1.0) <= PROPORTIONAL, "%s, within a fifth of %.2f" % [said, scale])
    var growing := specks[0.25] < specks[0.5] and specks[0.5] < at_one
    assert_true(growing, "and each scale's speck is smaller than the next's: %s" % specks)


## The kernel's half of it, without a stroke: Paper Grain drawn at a zoom of a
## quarter is its own tile read every fourth texel, to the float, so the
## grain is the same grain a quarter the size and not a fresh one. Drawn at the
## same small size with a zoom of one, which is a chooser's cell, it is the
## tile's own corner cell for cell, as the chooser drew it before the zoom, up
## to the last cell, where the small tile wraps and the large one runs on.
func test_a_quarter_zoom_reads_the_papers_own_tile_every_fourth_texel() -> void:
    var pattern := SaPatternStore.new().pattern(PAPER)
    assert_not_null(pattern, "%s is shipped" % PAPER)
    if pattern == null:
        return
    var own := pattern.texture()
    var quarter := pattern.generate(Vector2i(SMALL, SMALL), float(SMALL) / float(pattern.tile))
    var cell := pattern.generate(Vector2i(SMALL, SMALL))
    assert_true(own != null and quarter != null and cell != null, "The three tiles are made: %s" % pattern.error)
    if own == null or quarter == null or cell == null:
        return
    var whole := _floats(own)
    var small := _floats(quarter)
    var drawn := _floats(cell)
    var side := pattern.tile
    var stride := roundi(float(side) / float(SMALL))
    var apart := 0
    var corner_apart := 0
    for y in SMALL:
        for x in SMALL:
            if absf(small[y * SMALL + x] - whole[(y * stride) * side + x * stride]) > 1e-6:
                apart += 1
            if x < SMALL - CELL and y < SMALL - CELL and absf(drawn[y * SMALL + x] - whole[y * side + x]) > 1e-6:
                corner_apart += 1
    assert_eq(apart, 0, "Every texel at a quarter is the texel four times as far along on the paper's own tile")
    assert_eq(corner_apart, 0, "and a cell drawn small at a zoom of one is the tile's own corner")


## The alpha of one stroke through the paper at *scale*, read back from the
## chunk it lands in.
func _lay(scale: float) -> Image:
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    var brush := StateBrushScript.new()
    brush.surface = _surface
    brush.stroke_seed = 7
    var settings: SettingsScript = brush.settings
    settings.color = Color.BLACK
    settings.radius = RADIUS_PX / 256.0
    settings.hardness = GammaFloat.new(1.0, 1.0)
    settings.flow = GammaFloat.new(1.0, 1.0)
    settings.opacity = 1.0
    settings.spacing = 0.05
    settings.opacity_by_pressure = false
    settings.painting_mode = SettingsScript.PaintingMode.WASH
    settings.pattern_name = PAPER
    settings.texture_scale = scale
    settings.texture_option.enabled = true
    settings.texture_option.strength = 1.0
    var was := SaColors.foreground
    SaColors.foreground = Color.BLACK
    _stroke(brush)
    SaColors.foreground = was
    var layer := _surface.easel.document.active_layer
    var chunk: SaChunk = layer.chunks[Vector2i(0, 0)]
    var texture := chunk.albedo()
    var format := Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF
    var edge := chunk.pixel_size()
    return Image.create_from_data(edge, edge, false, format, GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0))


func _stroke(brush: StateBrushScript) -> void:
    _move(brush, Vector2(FROM_X, LINE_Y), 0)
    brush.tick(FRAME)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = Vector2(FROM_X, LINE_Y)
    brush.handle_input(press)
    var x := FROM_X
    while x < TO_X:
        x = minf(x + 8.0, TO_X)
        _move(brush, Vector2(x, LINE_Y), MOUSE_BUTTON_MASK_LEFT)
        brush.tick(FRAME)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    release.position = Vector2(TO_X, LINE_Y)
    brush.handle_input(release)
    var frames := 0
    while brush.is_drawing and frames < 600:
        brush.tick(FRAME)
        frames += 1


func _move(brush: StateBrushScript, at: Vector2, mask: int) -> void:
    _surface.view.mouse_position = at
    var motion := InputEventMouseMotion.new()
    motion.position = at
    motion.button_mask = mask
    motion.pressure = 1.0
    brush.handle_input(motion)


## The speck's size in *paint*: the area under the alpha's autocorrelation
## inside [constant WINDOW], read along both axes, from lag nought out to the
## last lag before it first stops being positive, which is the correlation
## length a random field's features are measured by.
func _speck(paint: Image) -> float:
    var mean := 0.0
    for y in range(WINDOW.position.y, WINDOW.end.y):
        for x in range(WINDOW.position.x, WINDOW.end.x):
            mean += paint.get_pixel(x, y).a
    mean /= float(WINDOW.get_area())
    var spread := _covariance(paint, mean, 0)
    # Half of lag nought, because the area is taken by trapezoids and the curve
    # is the same either side of it.
    var area := 0.5
    for lag in range(1, LAGS + 1):
        var alike := _covariance(paint, mean, lag) / spread
        if alike <= 0.0:
            break
        area += alike
    return area


## The mean product of the alpha's difference from *mean* at two texels *lag*
## apart, across and down, over the window.
func _covariance(paint: Image, mean: float, lag: int) -> float:
    var total := 0.0
    var count := 0
    for y in range(WINDOW.position.y, WINDOW.end.y - lag):
        for x in range(WINDOW.position.x, WINDOW.end.x - lag):
            var here := paint.get_pixel(x, y).a - mean
            total += here * (paint.get_pixel(x + lag, y).a - mean)
            total += here * (paint.get_pixel(x, y + lag).a - mean)
            count += 2
    return total / float(count)


func _floats(texture: SaTexture) -> PackedFloat32Array:
    return texture.rd.texture_get_data(texture.rid, 0).to_float32_array()
