## Soft Eraser takes paint away with the fall-off Paint lays it with.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Soft Eraser, hardness 0 and flow 0.5 like Paint, must not take paint away
## entirely out to about three quarters of its radius, a 10 to 90 percent width
## of 16 px at radius 60, where Paint at the same settings lays a ramp about
## half its radius wide. That came from the preset's spacing. Stamping a dab
## every 0.06 of its diameter where Paint does every 0.18 means a texel beside
## the stroke took three bites where Paint's took one, and three times the bites
## at half flow leave the cube of what Paint's leave. The erase blend was never
## the difference: each erase dab keeps `1 - s` of the alpha under it and each
## build-up dab over a clear buffer keeps `1 - s` of the clear, the same factor
## read from the other end, so the same dabs carve exactly the ramp they would
## lay.
##
## Both brushes run through the
## real brush and the real GPU at radius 60 with the stabilizer off, beside a
## hard edge of opaque paint. Paint runs along the edge and lays its ramp out
## over the clear side, and Soft Eraser runs along the same edge and carves its
## ramp into the paint. One row across the middle of the stroke is read back
## off the layer's chunks and the width is where its alpha crosses 0.9 and 0.1,
## interpolated between texels.
##
## The probe ran the eraser a third of its radius outside the edge, and there
## its width is only the part of the ramp that lands on the paint, 35 px against
## Paint's 47 with the fall-off matched. So that run is compared texel by texel
## rather than by width.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The proof is paint in a chunk, so this needs a real RenderingDevice.
const REQUIRES_GPU := true

## The radius the friction was measured at, in document pixels.
const RADIUS: float = 60.0

## How far apart the two widths may be, as a share of Paint's.
const TOLERANCE: float = 0.15

## The two alphas the width is read between.
const HIGH: float = 0.9
const LOW: float = 0.1

## One motion every STEP pixels, the spacing a pen's events arrive at.
const STEP: float = 4.0

## A spacing much tighter than the shipped 0.05, which the last test paints
## with to show the measurement tells the two apart. Soft Eraser's own 0.06
## from before the row is no longer tighter than a new brush's default.
const OLD_SPACING: float = 0.02

## The narrowest ramp Paint may lay for the width to be a ramp at all. At the
## spacing of 0.18 a new brush had it was over half the radius wide, and at
## today's 0.05 the extra bites at half flow narrow it to about a quarter.
const LEAST_RAMP: float = RADIUS * 0.2

## How far outside the edge the Painter's probe ran the eraser, a third of the
## radius.
const OFFSET: float = RADIUS / 3.0

## How far the stroke stops short of the document's top and bottom.
const MARGIN: float = 32.0


## The 10 to 90 percent widths of Paint and of Soft Eraser, each run along the
## edge, which is the row's Done when. Paint lays its ramp out over the clear
## side and Soft Eraser carves its own into the paint.
func test_soft_eraser_carves_the_ramp_paint_lays() -> void:
    var paint := _width(_row_after("Paint", 0.0))
    var soft := _width(_row_after("Soft Eraser", 0.0))
    print("  Paint lays a 10 to 90 percent width of %.2f px, Soft Eraser carves %.2f px" % [paint, soft])
    assert_true(paint > LEAST_RAMP, "Paint lays a ramp over a fifth of its radius wide, %.2f px" % paint)
    assert_true(
        absf(soft - paint) <= paint * TOLERANCE,
        "Soft Eraser's width %.2f px is within %d percent of Paint's %.2f px" % [soft, int(TOLERANCE * 100.0), paint]
    )


## The Painter's own probe ran Soft Eraser a third of its radius outside the
## edge, where its width is the part of the ramp that lands on the paint and so
## narrower than Paint's. Texel by texel the fall-off is still Paint's: at every
## distance from its line past the edge, the eraser leaves the alpha that Paint
## leaves clear at that distance from its own.
func test_off_the_edge_the_eraser_leaves_what_paint_does_not_lay() -> void:
    var paint := _row_after("Paint", 0.0)
    var soft := _row_after("Soft Eraser", OFFSET)
    var edge := _side()
    var worst := 0.0
    # The texel at x lies x less the line's x from it, as the kernel measures
    # it, so the first texel of the paint is OFFSET plus one from the eraser.
    for k: int in range(int(OFFSET) + 1, int(RADIUS)):
        var laid := paint[edge + k]
        var left := soft[edge + int(OFFSET) - k]
        worst = maxf(worst, absf(left - (1.0 - laid)))
    print("  a third of the radius out, the eraser leaves Paint's clear share within %.4f" % worst)
    assert_true(worst < 0.005, "At every distance the eraser leaves what Paint leaves clear, within %.4f" % worst)


## The settings the comparison is about: the friction's "the same settings" is
## the radius, the hardness and the flow, and the two presets ship the same
## hardness and flow and now the same spacing.
func test_the_two_presets_share_hardness_flow_and_spacing() -> void:
    var paint := _recipe("Paint")
    var soft := _recipe("Soft Eraser")
    assert_almost_eq(soft.hardness.value, paint.hardness.value, 1e-6, "The two share a hardness")
    assert_almost_eq(soft.flow.value, paint.flow.value, 1e-6, "and a flow")
    assert_almost_eq(soft.spacing, paint.spacing, 1e-6, "and a spacing")
    assert_eq(soft.blend_mode, SaLayer.BLEND_MODE.ERASE, "and Soft Eraser erases")


## Eraser keeps its hard cut, which the row asks for in as many words.
func test_the_eraser_keeps_its_hard_cut() -> void:
    var soft := _width(_row_after("Soft Eraser", 0.0))
    var hard := _width(_row_after("Eraser", 0.0))
    print("  Eraser carves a 10 to 90 percent width of %.2f px" % hard)
    assert_true(hard < soft * 0.25, "Eraser cuts at %.2f px, under a quarter of Soft Eraser's %.2f px" % [hard, soft])


## The cause, measured: the same Soft Eraser at the old, tighter spacing carves
## a ramp well under Paint's, so the comparison above fails on that recipe.
func test_the_old_spacing_cut_hard() -> void:
    var paint := _width(_row_after("Paint", 0.0))
    var old := _width(_row_after("Soft Eraser", 0.0, OLD_SPACING))
    print("  Soft Eraser at spacing %.2f carved %.2f px" % [OLD_SPACING, old])
    var said := "At spacing %.2f it carved %.2f px against Paint's %.2f px" % [OLD_SPACING, old, paint]
    assert_true(old < paint * (1.0 - TOLERANCE), said)


## The chunk's own side, which is where the edge sits.
func _side() -> int:
    return SaChunk.new().pixel_size()


## The alpha one stroke of *preset_name* leaves along a row across the edge, its
## line *offset* pixels outside it, at *spacing* when one is given and at the
## preset's own otherwise.
##
## The document is three chunks wide and two high, the first column of chunks
## opaque and the rest clear, so the edge sits on that column's far side. The
## stroke runs the document's height less a margin and the row read is a
## quarter chunk above the middle, so it is far from both of the stroke's ends.
func _row_after(preset_name: String, offset: float, spacing: float = -1.0) -> PackedFloat32Array:
    var side := _side()
    var size := Vector2i(side * 3, side * 2)
    var surface := Fixtures.make_surface(size)
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var brush: Object = machine.active_tool
    var settings := _recipe(preset_name)
    settings.radius = RADIUS / float(mini(size.x, size.y))
    settings.stabilizer_mode = 0
    if spacing > 0.0:
        settings.spacing = spacing
    brush.settings = settings
    var doc := surface.easel.document
    for row: int in 2:
        doc.active_layer.get_or_create_chunk(Vector2i(0, row)).albedo().clear(Color(0.2, 0.16, 0.17, 1.0))

    _stroke(surface, brush, float(side) + offset, MARGIN, float(size.y) - MARGIN)
    var alpha := _row(doc, side - floori(side / 4.0), size.x)
    Fixtures.teardown(surface, machine)
    return alpha


## The 10 to 90 percent width of *alpha*, between where it first falls below
## HIGH and where it first falls below LOW.
func _width(alpha: PackedFloat32Array) -> float:
    return _crossing(alpha, LOW) - _crossing(alpha, HIGH)


func _recipe(name: String) -> SaStampBrushSettings:
    for entry: Dictionary in SaShippedPresets.entries():
        if String(entry["name"]) == name:
            var built := SaShippedPresets.build(StateBrushScript.BrushSettingsScript, entry) as SaStampBrushSettings
            # The row's fall-off was tuned in build-up, where dabs add up. Wash keeps the larger of two.
            built.painting_mode = SaStampBrushSettings.PaintingMode.BUILD_UP
            return built
    assert_true(false, "%s is a shipped preset" % name)
    return SaStampBrushSettings.new()


## One stroke down *x* from *from_y* to *to_y*, a press, a motion every STEP
## pixels at full pressure, and the release that commits it.
func _stroke(surface: SaSurface, brush: Object, x: float, from_y: float, to_y: float) -> void:
    surface.view.mouse_position = Vector2(x, from_y)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = surface.view.mouse_position
    brush.handle_input(press)
    var y := from_y
    while y < to_y:
        y = minf(to_y, y + STEP)
        surface.view.mouse_position = Vector2(x, y)
        var motion := InputEventMouseMotion.new()
        motion.position = surface.view.mouse_position
        motion.pressure = 1.0
        brush.handle_input(motion)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    brush.handle_input(release)


## The active layer's alpha along document row *y*, *width* texels, read off each
## chunk the row crosses at the chunk's own pixel size. A chunk the layer does
## not hold is clear.
func _row(doc: SaDocument, y: int, width: int) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    out.resize(width)
    var rd := GlobalShaderCompiler.get_rd()
    for grid: Vector2i in doc.active_layer.chunks:
        var chunk: SaChunk = doc.active_layer.chunks[grid]
        var side := chunk.pixel_size()
        if y < grid.y * side or y >= (grid.y + 1) * side:
            continue
        var texture: SaTexture = chunk.albedo()
        var wide := texture.format == RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
        var texel_bytes := 16 if wide else 8
        var data: PackedByteArray = rd.texture_get_data(texture.rid, 0)
        var ty := y - grid.y * side
        for tx in side:
            var x := grid.x * side + tx
            if x < 0 or x >= width:
                continue
            var at := (ty * side + tx) * texel_bytes
            out[x] = data.decode_float(at + 12) if wide else data.decode_half(at + 6)
    return out


## Where the alpha first falls below *level* reading left to right, between the
## two texels it falls between. Both strokes leave a row that is opaque at its
## left end and clear past the stroke, so the first fall is the ramp's.
func _crossing(alpha: PackedFloat32Array, level: float) -> float:
    for x in range(1, alpha.size()):
        if alpha[x] < level and alpha[x - 1] >= level:
            return float(x - 1) + (alpha[x - 1] - level) / (alpha[x - 1] - alpha[x])
    assert_true(false, "The row's alpha falls below %.1f somewhere" % level)
    return 0.0
