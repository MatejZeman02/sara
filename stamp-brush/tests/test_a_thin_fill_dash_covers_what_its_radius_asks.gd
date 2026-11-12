## A thin Fill dash covers what its radius asks.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Fill in the pixel mode lays one row at every radius from 0.5 to 1.25,
## then 2.75 rows at 1.5, so a dash 2 px tall could not be asked of it. The one
## row is the pixel mode, which paints whole texels and which only a pen enters.
## Fill stays out of it through its recipe's
## `pixel_mode_when_small`, and `SaSmallDab` draws its thin dab an eighth of a
## pixel wider than asked, which is the share the hard edge's antialiasing ramp
## takes from inside the rim.
##
## Every dash runs the way the Painter's probe 3 ran it, through the real brush
## and the real GPU: a horizontal stroke 160 px long at full pressure with the
## stabilizer off, its line 0.3 of a texel below a row's centre. The column
## through its middle is read back off the layer's chunk and its alpha summed,
## which is the cover in rows the probe read off black on white.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The proof is paint in a chunk, so this needs a real RenderingDevice.
const REQUIRES_GPU := true

## The radii the row's Done when names, in document pixels.
const RADII: Array[float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 5.0]

## The radii the fix is for, a dash 1, 1.5, 2, 2.5 and 3 px tall.
const THIN_RADII: Array[float] = [0.5, 0.75, 1.0, 1.25, 1.5]

## The radii the row asks to paint as they did, from the first one past the
## growth's fall.
const LARGER_RADII: Array[float] = [2.0, 3.0, 5.0]

## How far a dash's cover may stray from twice its radius, as a share of it.
const TOLERANCE: float = 0.1

## The row the dashes run along, and how far below its centre, probe 3's 0.3.
const ROW: int = 100
const BELOW_CENTRE: float = 0.3

## Where in a texel a dash's line may fall, the probe's and three more.
const HEIGHTS: Array[float] = [0.0, 0.3, 0.5, 0.75]

## The dash's two ends and the column read through its middle.
const FROM_X: float = 40.0
const TO_X: float = 200.0
const COLUMN: int = 120

## One motion every STEP pixels, so the walk lays the dabs between them.
const STEP: float = 20.0


## A Fill dash at each of its radii covers within ten
## percent of twice the radius down a column through its middle.
func test_a_fill_dash_covers_twice_its_radius() -> void:
    for radius: float in RADII:
        var cover := _sum(_column(_dash("Fill", radius, BELOW_CENTRE)))
        print("  Fill at radius %.2f covers %.3f rows, %.3f of twice its radius" % [radius, cover, cover / (2.0 * radius)])
        assert_true(
            absf(cover - 2.0 * radius) <= 2.0 * radius * TOLERANCE,
            "Fill at radius %.2f covers %.3f rows against the %.2f asked" % [radius, cover, 2.0 * radius]
        )


## A painter's dash falls anywhere in a texel, so the thin radii are laid at four
## heights and their mean is held to the same ten percent. The single heights
## are printed, the worst of them a dash at radius 0.5 centred on a row.
func test_wherever_it_falls_in_a_texel_a_thin_dash_covers_twice_its_radius() -> void:
    for radius: float in THIN_RADII:
        var line := "  radius %.2f at heights" % radius
        var total := 0.0
        for height: float in HEIGHTS:
            var cover := _sum(_column(_dash("Fill", radius, height)))
            line += " %.2f:%.3f" % [height, cover / (2.0 * radius)]
            total += cover
        var mean := total / float(HEIGHTS.size())
        print(line)
        assert_true(
            absf(mean - 2.0 * radius) <= 2.0 * radius * TOLERANCE,
            "Fill at radius %.2f covers %.3f rows on the mean of four heights against %.2f" % [radius, mean, 2.0 * radius]
        )


## The row's "anti-aliased in proportion below one pixel": a dash 1.5 px tall
## leaves a row partly covered, which the pixel mode never does.
func test_a_thin_dash_shares_a_row_in_proportion() -> void:
    var column := _column(_dash("Fill", 0.75, BELOW_CENTRE))
    var partial := 0
    for alpha: float in column:
        if alpha > 0.1 and alpha < 0.9:
            partial += 1
    assert_true(partial > 0, "A Fill dash 1.5 px tall shares a row with the ground")


## The row's "Larger radii paint as they do now": from radius 2 up the dash is
## the same texels with the switch on as off, the switch on being the brush as
## it was before the switch.
func test_larger_radii_lay_the_texels_they_did() -> void:
    for radius: float in LARGER_RADII:
        var now := _dash("Fill", radius, BELOW_CENTRE)
        var before := _dash("Fill", radius, BELOW_CENTRE, true)
        assert_true(now == before, "Fill at radius %.2f lays the texels it laid" % radius)


## The cause, measured: Fill in the pixel mode lays one row at every thin radius,
## the friction's number, so the first test fails on the recipe it was written
## against.
func test_in_the_pixel_mode_fill_laid_one_row() -> void:
    for radius: float in [0.5, 0.75, 1.0, 1.25]:
        var cover := _sum(_column(_dash("Fill", radius, BELOW_CENTRE, true, true)))
        assert_almost_eq(cover, 1.0, 1e-3, "In the pixel mode Fill at radius %.2f laid one row" % radius)


## Fill and the presets made of it refuse the mode through their switch and
## every other shipped preset leaves it on. Pointed Mark is Fill with its size
## on the pen's pressure, and Paper Wash is Fill in
## wash mode, which keeps Fill's switch with the rest of
## Fill. The switch lets a pen in and no other brush, so
## Inked Pen at radius 1 touches one row and Paint, at Sharpness nought, draws
## its thin line antialiased across the rows either side.
func test_only_a_pen_enters_the_pixel_mode() -> void:
    for entry: Dictionary in SaShippedPresets.entries():
        var name := String(entry["name"])
        var settings := SaShippedPresets.build(StateBrushScript.BrushSettingsScript, entry) as SaStampBrushSettings
        if settings == null:
            continue
        var fill := name in ["Fill", "Pointed Mark", "Paper Wash"]
        assert_eq(settings.pixel_mode_when_small, not fill, "%s leaves the mode's switch on unless it is Fill or of it" % name)
        var pen := settings.sharpness >= SaSmallDab.PEN_SHARPNESS and not fill
        assert_eq(SaSmallDab.enters_mode(settings), pen, "%s enters the pixel mode only as a pen" % name)
    assert_eq(_rows_touched(_dash("Inked Pen", 1.0, BELOW_CENTRE)), 1, "Inked Pen at radius 1 touches one row")
    assert_true(_rows_touched(_dash("Paint", 1.0, BELOW_CENTRE)) > 1, "Paint at radius 1 is antialiased across more than one row")


func _rows_touched(column_of: PackedFloat32Array) -> int:
    var touched := 0
    for alpha: float in _column(column_of):
        if alpha > 0.0:
            touched += 1
    return touched


## The thumbnails are drawn at the preset's own radius, 47 px on the stroke and
## more on the tip, so Fill's two pictures are the ones they were and none is
## retaken.
func test_fills_thumbnails_are_the_ones_they_were() -> void:
    var now := _recipe("Fill")
    var before := _recipe("Fill")
    before.pixel_mode_when_small = true
    assert_true(
        SaPresetThumbs.render(StateBrushScript, now).get_data() == SaPresetThumbs.render(StateBrushScript, before).get_data(),
        "Fill's stroke thumbnail is the one it was"
    )
    var tip_now := SaPresetThumbs.render_tip(StateBrushScript, now).get_data()
    assert_true(tip_now == SaPresetThumbs.render_tip(StateBrushScript, before).get_data(), "and so is its tip")


func _recipe(name: String) -> SaStampBrushSettings:
    for entry: Dictionary in SaShippedPresets.entries():
        if String(entry["name"]) == name:
            return SaShippedPresets.build(StateBrushScript.BrushSettingsScript, entry) as SaStampBrushSettings
    assert_true(false, "%s is a shipped preset" % name)
    return SaStampBrushSettings.new()


## The alpha of the chunk one dash of *preset_name* leaves, its line *height* of a
## texel below ROW's centre, with the pixel mode's switch on when *switch_on*,
## and made a pen, which the switch lets into the mode, when *pen*.
func _dash(preset_name: String, radius: float, height: float, switch_on: bool = false, pen: bool = false) -> PackedFloat32Array:
    var side := SaChunk.new().pixel_size()
    var surface := Fixtures.make_surface(Vector2i(side, side))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var brush: Object = machine.active_tool
    var settings := _recipe(preset_name)
    settings.radius = radius / float(side)
    settings.stabilizer_mode = 0
    # The dash was measured in build-up, where each dab lays its own alpha.
    # Wash is the shipped Fill's mode, and a wash stroke keeps the larger of
    # two dabs rather than adding them, so a dash thinner than a texel shows its
    # partial dab at its own alpha there.
    settings.painting_mode = SaStampBrushSettings.PaintingMode.BUILD_UP
    if switch_on:
        settings.pixel_mode_when_small = true
    if pen:
        settings.sharpness = SaSmallDab.PEN_SHARPNESS
    brush.settings = settings
    _stroke(surface, brush, float(ROW) + height)
    var alpha := _alpha(surface.easel.document, side)
    Fixtures.teardown(surface, machine)
    return alpha


## One stroke along *y* from FROM_X to TO_X, a press, a motion every STEP pixels
## at full pressure, and the release that commits it.
func _stroke(surface: SaSurface, brush: Object, y: float) -> void:
    surface.view.mouse_position = Vector2(FROM_X, y)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = surface.view.mouse_position
    brush.handle_input(press)
    var x := FROM_X
    while x < TO_X:
        x = minf(TO_X, x + STEP)
        surface.view.mouse_position = Vector2(x, y)
        var motion := InputEventMouseMotion.new()
        motion.position = surface.view.mouse_position
        motion.pressure = 1.0
        brush.handle_input(motion)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    brush.handle_input(release)


## The active layer's alpha over its first chunk, row by row, *side* texels a
## side. A layer that holds no chunk there is clear.
func _alpha(doc: SaDocument, side: int) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    out.resize(side * side)
    var chunk: SaChunk = doc.active_layer.chunks.get(Vector2i.ZERO)
    if chunk == null:
        return out
    var texture: SaTexture = chunk.albedo()
    var wide := texture.format == RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    var texel_bytes := 16 if wide else 8
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    for at in side * side:
        out[at] = data.decode_float(at * texel_bytes + 12) if wide else data.decode_half(at * texel_bytes + 6)
    return out


## The column COLUMN of a chunk's *alpha*, top to bottom.
func _column(alpha: PackedFloat32Array) -> PackedFloat32Array:
    var side := int(sqrt(float(alpha.size())))
    var out := PackedFloat32Array()
    for y in side:
        out.append(alpha[y * side + COLUMN])
    return out


func _sum(values: PackedFloat32Array) -> float:
    var total := 0.0
    for value: float in values:
        total += value
    return total
