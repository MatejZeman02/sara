## A thin stroke lays the same width on a double resolution layer as on a plain
## one.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Inked Pen at radius 1.2 must not lay lines about twice as heavy on a
## layer at Double Resolution as on a plain one. Each case here is one shallow
## stroke through the real brush and the real GPU, on a plain layer and on a
## layer at 2.0, read back off the layer's chunk. The alpha of every texel is
## summed as the share of a document pixel it is, so a texel of a double layer
## counts a quarter, and the ink in each document column times the cosine of the
## slope is the line's width in document pixels. The width the brush asks is the
## diameter of its dabs, which the tool keeps on its last dab.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The proof is paint in a chunk, so this needs a real RenderingDevice.
const REQUIRES_GPU := true

const PRESETS: Array[String] = ["Inked Pen", "Pencil", "Paint"]
const RADII: Array[float] = [0.8, 1.2, 2.0, 4.0]
const PRESSURES: Array[float] = [0.7, 1.0]

## How far the two layers' widths, and a pen's from its own shape, may stray
## from each other, as a share.
const TOLERANCE: float = 0.1
## Pencil at radius 0.8 and pressure 0.7 is the one case allowed more between
## the layers. Its antialiasing ramp lies a document pixel inside the rim, and a
## double layer's ramp is half as wide, so the plain layer loses more of a line
## this thin. Moving the ramp would redraw every stamp preset, so this suite
## accepts the difference.
const PENCIL_THINNEST_TOLERANCE: float = 0.12
## How far the two layers' grain sizes may stray from each other, as a share.
## A double layer's finer edges shorten a grain of half a pixel by a few
## hundredths of one, which is most of this.
const GRAIN_TOLERANCE: float = 0.2

## The stroke, a shallow one, starting off the texel grid.
const FROM := Vector2(30.3, 100.3)
const LENGTH: float = 190.0
const DEGREES: float = 6.0
## One motion every STEP pixels along it.
const STEP: float = 3.0
## The document columns read, clear of both ends.
const FIRST_COLUMN: int = 70
const LAST_COLUMN: int = 180


## Every case lays the same width on both layers, but for the pen's pixel mode
## on a plain layer, where a dab under PIXEL_MODE_DIAMETER is one whole texel
## by design. Inked Pen also lays the width of its own line six times wider,
## divided by six, on a double layer always and on a plain one outside the
## pixel mode, so the finer layer meets the pen's shape. The antialiased
## presets print that width beside theirs, and lay about a pixel less than
## their diameter on both layers alike.
func test_a_thin_line_is_as_wide_on_a_double_layer_as_on_a_plain_one() -> void:
    for preset_name: String in PRESETS:
        var settings := _recipe(preset_name)
        for pressure: float in PRESSURES:
            for radius: float in RADII:
                var plain := _line(preset_name, radius, pressure, 1.0)
                var double := _line(preset_name, radius, pressure, 2.0)
                var wide := float(_line(preset_name, radius * 6.0, pressure, 1.0)["width"]) / 6.0
                var label := "%s at radius %.1f and pressure %.1f" % [preset_name, radius, pressure]
                var row := "  %s: asked %.3f, wide/6 %.3f, plain %.3f, double %.3f"
                print(row % [label, plain["asked"], wide, plain["width"], double["width"]])
                var pixel_mode := SaSmallDab.enters_mode(settings) and float(plain["asked"]) < SaDabGeometry.PIXEL_MODE_DIAMETER
                var between := TOLERANCE
                if preset_name == "Pencil" and is_equal_approx(radius, 0.8) and is_equal_approx(pressure, 0.7):
                    between = PENCIL_THINNEST_TOLERANCE
                if not pixel_mode:
                    assert_true(
                        absf(float(double["width"]) / float(plain["width"]) - 1.0) <= between,
                        "%s lays %.3f on a double layer and %.3f on a plain one" % [label, double["width"], plain["width"]]
                    )
                if not SaSmallDab.enters_mode(settings):
                    continue
                assert_true(
                    absf(float(double["width"]) / wide - 1.0) <= TOLERANCE,
                    "%s lays %.3f on a double layer, its own line at six times the size %.3f" % [label, double["width"], wide]
                )
                if not pixel_mode:
                    assert_true(
                        absf(float(plain["width"]) / wide - 1.0) <= TOLERANCE,
                        "%s lays %.3f on a plain layer, its own line at six times the size %.3f" % [label, plain["width"], wide]
                    )


## The grain of Bush and Dry Strokes, picture tips, and of the noise engine's
## Dry Brush is as coarse on a double layer as on a plain one, in document
## pixels.
func test_grain_is_as_coarse_on_a_double_layer_as_on_a_plain_one() -> void:
    for preset_name: String in ["Bush", "Dry Strokes"]:
        var plain := _stamp_grain(preset_name, 1.0)
        var double := _stamp_grain(preset_name, 2.0)
        print("  %s grain: plain %.3f, double %.3f" % [preset_name, plain, double])
        var said := "%s grain %.3f on a plain layer, %.3f on a double one" % [preset_name, plain, double]
        assert_true(absf(double / plain - 1.0) <= GRAIN_TOLERANCE, said)
    var noise_plain := _noise_grain("Dry Brush", 1.0)
    var noise_double := _noise_grain("Dry Brush", 2.0)
    print("  Dry Brush grain: plain %.3f, double %.3f" % [noise_plain, noise_double])
    var noise_said := "Dry Brush grain %.3f on a plain layer, %.3f on a double one" % [noise_plain, noise_double]
    assert_true(absf(noise_double / noise_plain - 1.0) <= GRAIN_TOLERANCE, noise_said)


func _stamp_grain(preset_name: String, scale: float) -> float:
    var surface := Fixtures.make_surface(Vector2i(256, 256))
    var document := surface.get_document()
    if scale > 1.0:
        SaLayerOps.new(document).add(&"", null, scale)
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var brush: Object = machine.active_tool
    var settings := _recipe(preset_name)
    settings.radius = 24.0 / float(document.brush_side)
    settings.stabilizer_mode = 0
    brush.settings = settings
    brush.stroke_seed = 1
    var hover := InputEventMouseMotion.new()
    hover.position = Vector2(40.0, 128.0)
    hover.pressure = 1.0
    brush.handle_input(hover)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = hover.position
    surface.view.mouse_position = hover.position
    brush.handle_input(press)
    for i in 60:
        var motion := InputEventMouseMotion.new()
        motion.position = Vector2(40.0 + 3.0 * (i + 1), 128.0)
        motion.pressure = 1.0
        surface.view.mouse_position = motion.position
        brush.handle_input(motion)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    brush.handle_input(release)
    var grain := _grain(document)
    Fixtures.teardown(surface, machine)
    return grain


func _noise_grain(preset_name: String, scale: float) -> float:
    var surface := Fixtures.make_surface(Vector2i(256, 256))
    var document := surface.get_document()
    if scale > 1.0:
        SaLayerOps.new(document).add(&"", null, scale)
    var entry: Dictionary = {}
    for one: Dictionary in NoisePresetsScript.entries():
        if String(one["name"]) == preset_name:
            entry = one
    var brush := StateNoiseBrushScript.new()
    brush.surface = surface
    brush.stroke_seed = 1
    var settings: Resource = NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
    settings.color = Color(0.1, 0.1, 0.1, 1.0)
    settings.radius = 24.0 / float(document.brush_side)
    brush.settings = settings
    brush.begin_stroke(Vector2(40.0, 128.0), 0.0, Vector2.ZERO, 0.0, true)
    for i in 40:
        brush.add_sample(Vector2(40.0 + 4.5 * (i + 1), 128.0), 0.8, Vector2.ZERO, (i + 1) * 16.0)
    brush.end_stroke()
    var grain := _grain(document)
    Fixtures.teardown(surface)
    return grain


## The grain's size in document pixels: the lag along a row at which the
## alpha's correlation with itself falls to a half, over the middle of the
## stroke, read texel by texel and divided by the layer's density. Averaging a
## double layer's texels into document pixels first would smooth its finer
## edges away and read its grain coarser than it is.
func _grain(document: SaDocument) -> float:
    var chunk: SaChunk = document.active_layer.chunks.get(Vector2i.ZERO)
    if chunk == null:
        return -1.0
    var side := chunk.pixel_size()
    var density := float(side) / SaChunk.SIZE
    var texture: SaTexture = chunk.albedo()
    var wide := texture.format == RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    var texel_bytes := 16 if wide else 8
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var rows := []
    for y in range(120 * density, 136 * density):
        var row := PackedFloat32Array()
        for x in range(80 * density, 180 * density):
            var at := (y * side + x) * texel_bytes
            row.append(data.decode_float(at + 12) if wide else data.decode_half(at + 6))
        rows.append(row)
    var mean := 0.0
    var count := 0
    for row: PackedFloat32Array in rows:
        for v: float in row:
            mean += v
            count += 1
    mean /= float(count)
    var variance := _lagged(rows, mean, 0)
    if variance <= 1e-9:
        return 0.0
    var before := 1.0
    for lag in range(1, 16 * density):
        var now := _lagged(rows, mean, lag) / variance
        if now <= 0.5:
            return (float(lag - 1) + (before - 0.5) / maxf(before - now, 1e-6)) / float(density)
        before = now
    return 16.0


func _lagged(rows: Array, mean: float, lag: int) -> float:
    var total := 0.0
    var count := 0
    for row: PackedFloat32Array in rows:
        for x in row.size() - lag:
            total += (row[x] - mean) * (row[x + lag] - mean)
            count += 1
    return total / float(maxi(count, 1))


func _recipe(name: String) -> SaStampBrushSettings:
    for entry: Dictionary in SaShippedPresets.entries():
        if String(entry["name"]) == name:
            return SaShippedPresets.build(StateBrushScript.BrushSettingsScript, entry) as SaStampBrushSettings
    assert_true(false, "%s is a shipped preset" % name)
    return SaStampBrushSettings.new()


## One stroke of *preset_name* at *radius* and *pressure* on a fresh layer at
## *scale*, answered as the width asked and the width laid, in document pixels.
func _line(preset_name: String, radius: float, pressure: float, scale: float) -> Dictionary:
    var surface := Fixtures.make_surface(Vector2i(256, 256))
    var document := surface.get_document()
    if scale > 1.0:
        SaLayerOps.new(document).add(&"", null, scale)
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var brush: Object = machine.active_tool
    var settings := _recipe(preset_name)
    settings.radius = radius / float(document.brush_side)
    settings.stabilizer_mode = 0
    brush.settings = settings
    var asked := _stroke(surface, brush, pressure)
    var width := _width(document)
    Fixtures.teardown(surface, machine)
    return {"asked": asked, "width": width}


## Strokes from FROM at DEGREES for LENGTH, a pen hovering in at *pressure*, and
## answers the mean diameter of the dabs it laid.
func _stroke(surface: SaSurface, brush: Object, pressure: float) -> float:
    var direction := Vector2.from_angle(deg_to_rad(DEGREES))
    var hover := InputEventMouseMotion.new()
    hover.position = FROM
    hover.pressure = pressure
    surface.view.mouse_position = FROM
    brush.handle_input(hover)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = FROM
    brush.handle_input(press)
    var sizes := 0.0
    var count := 0
    var along := 0.0
    while along < LENGTH:
        along = minf(LENGTH, along + STEP)
        var at := FROM + direction * along
        surface.view.mouse_position = at
        var motion := InputEventMouseMotion.new()
        motion.position = at
        motion.pressure = pressure
        brush.handle_input(motion)
        if brush.last_dab != null:
            sizes += brush.last_dab.size
            count += 1
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    brush.handle_input(release)
    return sizes / maxf(1.0, float(count))


## The active layer's ink across the columns read, in document pixels of width.
func _width(document: SaDocument) -> float:
    var chunk: SaChunk = document.active_layer.chunks.get(Vector2i.ZERO)
    if chunk == null:
        return 0.0
    var side := chunk.pixel_size()
    var density := float(side) / float(SaChunk.SIZE)
    var texture: SaTexture = chunk.albedo()
    var wide := texture.format == RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    var texel_bytes := 16 if wide else 8
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var total := 0.0
    for y in side:
        for x in range(int(FIRST_COLUMN * density), int(LAST_COLUMN * density)):
            var at := (y * side + x) * texel_bytes
            total += data.decode_float(at + 12) if wide else data.decode_half(at + 6)
    var columns := float(LAST_COLUMN - FIRST_COLUMN)
    return total / (density * density) / columns * cos(deg_to_rad(DEGREES))
