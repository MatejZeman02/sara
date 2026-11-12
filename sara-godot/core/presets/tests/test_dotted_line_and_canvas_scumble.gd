## Dotted Line draws a row of round dots and Canvas Scumble lays broken colour
## with open hollows.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The `paint` sweep's F8 found Dotted Line stamping a ragged row of dashes
## turned along the stroke, a train of scratchy marks, and Canvas Scumble
## painting a square mesh through Canvas Weave, a pattern that never reaches
## nought. Each preset is built here from its own recipe, its picture is read
## the way the brush reads it, and each paints on a document of a default
## document's 1080 pixel height, so the recipe's radius is the size a painter
## gets. In the skeleton's tests rather than a module's, since it names both
## brush modules and neither module names the other.
extends "res://tests/test_framework.gd"

## The pattern is a dispatch and both strokes are painted.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const DrawnScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_drawn_tip_presets.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const NoiseSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")

const DOTTED: String = "Dotted Line"
const SCUMBLE: String = "Canvas Scumble"
const DOT_PICTURE: String = "res://tips/dotted-line.png"

## Square at a default document's height, since both recipes' radius is a share
## of the smaller side, with room across it for the line the row asks for.
const CANVAS := Vector2i(1080, 1080)
## The 650 pixel line the case draws, along one row.
const LINE_FROM := Vector2(59.0, 128.0)
const LINE_TO := Vector2(709.0, 128.0)
## How far above and below the line a dot is looked for.
const LINE_REACH: int = 40

## The wave Canvas Scumble is drawn along: its middle row, its height either
## side and how many crests and troughs fit in its 650 pixels.
const WAVE_ROW: float = 500.0
const WAVE_HEIGHT: float = 80.0
const WAVE_TURNS: float = 1.5
## How far either side of the wave's path a texel counts as the stroke's core,
## well inside the recipe's radius of 0.035 of 1080, about 38 pixels.
const WAVE_CORE: int = 14

## Half coverage, where the dab kernel puts a mask's edge, counts as painted.
const PAINTED: float = 0.5
## Under a twentieth is open, in a stroke and in a pattern alike.
const OPEN: float = 0.05

## One plain weave repeat of the pattern at its defaults, two threads of a 256
## texel tile that 64 cross, and one thread's cell.
const WEAVE_REPEAT: int = 8
const THREAD_CELL: int = 4

var _surface: SaSurface = null


func after_each() -> void:
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = null


# --- Dotted Line ------------------------------------------------------------


## The recipe spaces a dot a gap from the next, leaves it unturned and lets
## the pen size it.
func test_dotted_line_spaces_a_dot_and_lets_the_pen_size_it() -> void:
    var settings := _dotted()
    assert_not_null(settings, "Dotted Line builds on the stamp's settings")
    if settings == null:
        return
    assert_almost_eq(settings.spacing, 1.4, 1e-6, "A step of 1.4 tips leaves a gap as wide as a dot seven tenths of the tip")
    assert_false(settings.rotation_option.enabled, "A dot has no direction, so nothing turns it")
    assert_true(settings.size_option.enabled, "Size follows the pen")
    var pressure := settings.size_option.sensor_for(SaSensor.Id.PRESSURE)
    assert_true(pressure != null and pressure.active, "through its pressure")
    assert_almost_eq(settings.size_option.common_curve[0].y, 0.5, 1e-6, "and the lightest touch is half a dot, not none")
    assert_false(settings.opacity_option.enabled, "A dot is as dark at any press")
    assert_true(settings.size_by_pressure, "and Tool Options' two switches say both")
    assert_false(settings.opacity_by_pressure, "the second off")
    var tip := SaTipImage.load_from(DOT_PICTURE)
    assert_almost_eq(tip.spacing, settings.spacing, 1e-6, "The picture carries the spacing its recipe paints at")
    assert_eq(tip.tip_name, DOTTED, "and the name")


## The picture is one round blob with nothing on its border.
func test_the_dot_is_one_round_blob_inside_a_clear_border() -> void:
    var tip := SaTipImage.load_from(DOT_PICTURE)
    assert_eq(tip.error, "", "The dot loads")
    if not tip.error.is_empty():
        return
    var border := 0.0
    for i in tip.size.x:
        border = maxf(border, maxf(tip.at(i, 0), tip.at(i, tip.size.y - 1)))
    for j in tip.size.y:
        border = maxf(border, maxf(tip.at(0, j), tip.at(tip.size.x - 1, j)))
    assert_true(border < 0.01, "Nothing on the border, %.3f at most" % border)
    var blobs := _blobs(tip.mask, tip.size)
    assert_eq(blobs.size(), 1, "One connected blob, %s" % str(blobs))
    if blobs.size() != 1:
        return
    var blob: Rect2i = blobs[0][0]
    var area := int(blobs[0][1])
    var share := float(blob.size.x) / float(tip.size.x)
    assert_true(share > 0.6 and share < 0.8, "About seven tenths of the picture across, %.2f" % share)
    assert_true(absi(blob.size.x - blob.size.y) <= 2, "As tall as it is wide, %s" % str(blob.size))
    var roundness := float(area) / (PI * 0.25 * blob.size.x * blob.size.y)
    assert_true(absf(roundness - 1.0) < 0.05, "and as full as a disc of that size, %.3f" % roundness)


## At a full press 650 pixels of line are a row of round dots with clear gaps,
## and at half the press the dots are smaller and still there.
func test_dotted_line_draws_round_dots_smaller_at_half_the_press() -> void:
    var firm := _dots_at(1.0)
    var half := _dots_at(0.5)
    assert_true(firm.size() >= 8, "A row of dots at a full press, %d of them" % firm.size())
    assert_true(half.size() >= 8, "and at half the press, %d" % half.size())
    if firm.size() < 8 or half.size() < 8:
        return
    for i in firm.size():
        var dot: Vector2i = firm[i]
        var round_enough := absf(float(dot.x) / float(dot.y) - 1.0) < 0.2
        assert_true(round_enough, "Dot %d is round, %d wide and %d tall" % [i, dot.x, dot.y])
    var gaps := _gaps_at(1.0)
    var firm_width := _mean_width(firm)
    for gap: int in gaps:
        assert_true(gap > 0.6 * firm_width, "A clear gap between two dots, %d pixels at a dot of %.1f" % [gap, firm_width])
    var half_width := _mean_width(half)
    assert_true(half_width < 0.9 * firm_width, "Half the press paints smaller dots, %.1f against %.1f" % [half_width, firm_width])
    assert_true(half_width > 0.5 * firm_width, "rather than losing them, %.1f" % half_width)


# --- Canvas Scumble ---------------------------------------------------------


## The recipe paints through its own pattern at twice its size.
func test_canvas_scumble_paints_through_its_own_pattern() -> void:
    var settings := _scumble()
    assert_not_null(settings, "Canvas Scumble builds on the noise brush's settings")
    if settings == null:
        return
    assert_eq(settings.texture_field, "picture", "On the Picture field")
    assert_eq(settings.picture_name, SCUMBLE, "through the pattern made for it rather than Canvas Weave")
    assert_almost_eq(settings.picture_scale, 2.0, 1e-6, "at twice its tile")
    assert_true(SaPatternStore.new([SaPatternStore.SHIPPED_DIR]).has(SCUMBLE), "which ships")


## The pattern reaches nought in its hollows and one on its highest tops,
## its tops are uneven, and one weave repeat along is not the same tile again.
func test_the_scumble_pattern_has_open_hollows_uneven_tops_and_no_grid() -> void:
    var pattern := SaPatternStore.new([SaPatternStore.SHIPPED_DIR]).pattern(SCUMBLE)
    assert_not_null(pattern, "The store lists it")
    if pattern == null:
        return
    var image := pattern.image_at(SaPattern.DEFAULT_TILE)
    assert_not_null(image, "and it runs: %s" % pattern.error)
    if image == null:
        return
    var side := image.get_width()
    var lowest := 1.0
    var highest := 0.0
    var open := 0
    var total := 0.0
    var values := PackedFloat32Array()
    values.resize(side * side)
    for y in side:
        for x in side:
            var value := image.get_pixel(x, y).r
            values[y * side + x] = value
            lowest = minf(lowest, value)
            highest = maxf(highest, value)
            open += 1 if value < OPEN else 0
            total += value
    var open_share := float(open) / float(side * side)
    assert_true(lowest < OPEN, "The hollows reach nought, %.3f at the lowest" % lowest)
    assert_true(open_share > 0.05 and open_share < 0.4, "over a share of the tile and not most of it, %.3f" % open_share)
    assert_true(highest > 0.95, "and the highest tops reach one, %.3f" % highest)
    var mean := total / float(side * side)
    var spread := 0.0
    var moved := 0.0
    for y in side:
        for x in side:
            var value := values[y * side + x]
            spread += absf(value - mean)
            moved += absf(value - values[y * side + (x + WEAVE_REPEAT) % side])
    var unlike := moved / maxf(spread, 0.0001)
    assert_true(unlike > 0.4, "One weave repeat along is another tile, not the same grid, %.2f of its spread" % unlike)
    var tops := PackedFloat32Array()
    for cy in range(0, side, THREAD_CELL):
        for cx in range(0, side, THREAD_CELL):
            var top := 0.0
            for y in THREAD_CELL:
                for x in THREAD_CELL:
                    top = maxf(top, values[(cy + y) * side + cx + x])
            tops.append(top)
    assert_true(_deviation(tops) > 0.1, "The thread tops stand at heights of their own, %.3f apart" % _deviation(tops))


## Along a wave at a full press the stroke is broken colour with open hollows,
## and a half press lays less of it.
func test_canvas_scumble_along_a_wave_leaves_broken_colour() -> void:
    var firm := _scumble_core(1.0)
    var half := _scumble_core(0.5)
    assert_true(firm.x > 0.2 and firm.x < 0.85, "A full press paints some of the core and not all, %.3f" % firm.x)
    assert_true(firm.y > 0.1, "and leaves hollows open in it, %.3f" % firm.y)
    assert_true(half.x < firm.x, "Half the press paints less, %.3f against %.3f" % [half.x, firm.x])
    assert_true(half.x > 0.02, "and still paints, %.3f" % half.x)


# --- Helpers ----------------------------------------------------------------


func _entry(entries: Array[Dictionary], preset_name: String) -> Dictionary:
    for entry: Dictionary in entries:
        if String(entry["name"]) == preset_name:
            return entry
    return {}


func _dotted() -> SaStampBrushSettings:
    var entry := _entry(DrawnScript.ENTRIES, DOTTED)
    if entry.is_empty():
        return null
    return ShippedPresetsScript.build(StampSettingsScript, entry) as SaStampBrushSettings


func _scumble() -> Resource:
    var entry := _entry(NoisePresetsScript.entries(), SCUMBLE)
    if entry.is_empty():
        return null
    return NoisePresetsScript.build(NoiseSettingsScript, entry)


## Every four-connected blob of *mask* at [constant PAINTED] or over, as its
## bounding box and its texel count.
func _blobs(mask: PackedFloat32Array, size: Vector2i) -> Array[Array]:
    var seen := PackedByteArray()
    seen.resize(size.x * size.y)
    var out: Array[Array] = []
    for start in mask.size():
        if seen[start] != 0 or mask[start] < PAINTED:
            continue
        var low := Vector2i(start % size.x, floori(float(start) / size.x))
        var high := low
        var count := 0
        var queue := PackedInt32Array([start])
        seen[start] = 1
        while not queue.is_empty():
            var at := queue[queue.size() - 1]
            queue.remove_at(queue.size() - 1)
            count += 1
            var here := Vector2i(at % size.x, floori(float(at) / size.x))
            low = low.min(here)
            high = high.max(here)
            for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
                var next := here + step
                if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y:
                    continue
                var index := next.y * size.x + next.x
                if seen[index] == 0 and mask[index] >= PAINTED:
                    seen[index] = 1
                    queue.append(index)
        out.append([Rect2i(low, high - low + Vector2i.ONE), count])
    return out


## Dotted Line drawn along the line at *pressure* on a fresh document.
func _draw_line(pressure: float) -> SaLayer:
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    var brush := StateBrushScript.new()
    brush.surface = _surface
    brush.stroke_seed = 7
    SaPresetStore.copy_settings(_dotted(), brush.settings)
    var was := SaColors.foreground
    SaColors.foreground = Color(0.1, 0.1, 0.1, 1.0)
    var view := _surface.view
    view.mouse_position = LINE_FROM
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = LINE_FROM
    brush.handle_input(press)
    var steps := 130
    for i in range(1, steps + 1):
        view.mouse_position = LINE_FROM.lerp(LINE_TO, float(i) / float(steps))
        var motion := InputEventMouseMotion.new()
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.position = view.mouse_position
        motion.pressure = pressure
        brush.handle_input(motion)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    brush.handle_input(release)
    SaColors.foreground = was
    return _surface.easel.document.active_layer


## The dots of a line at *pressure*, left to right, each as its width along the
## line and its height across it through its middle.
func _dots_at(pressure: float) -> Array[Vector2i]:
    var layer := _draw_line(pressure)
    var images := {}
    var row := int(LINE_FROM.y)
    var out: Array[Vector2i] = []
    for run: Vector2i in _runs_along(layer, row, images):
        var middle := floori((run.x + run.y) / 2.0)
        var top := row
        while top > row - LINE_REACH and _alpha(layer, Vector2i(middle, top - 1), images) >= PAINTED:
            top -= 1
        var bottom := row
        while bottom < row + LINE_REACH and _alpha(layer, Vector2i(middle, bottom + 1), images) >= PAINTED:
            bottom += 1
        out.append(Vector2i(run.y - run.x + 1, bottom - top + 1))
    return out


## The open pixels between each two dots of a line at *pressure*.
func _gaps_at(pressure: float) -> Array[int]:
    var layer := _draw_line(pressure)
    var runs := _runs_along(layer, int(LINE_FROM.y), {})
    var out: Array[int] = []
    for i in range(1, runs.size()):
        out.append(runs[i].x - runs[i - 1].y - 1)
    return out


## Each painted run along *row*, as its first and last column.
func _runs_along(layer: SaLayer, row: int, images: Dictionary) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    var start := -1
    for x in CANVAS.x:
        var painted := _alpha(layer, Vector2i(x, row), images) >= PAINTED
        if painted and start < 0:
            start = x
        elif not painted and start >= 0:
            out.append(Vector2i(start, x - 1))
            start = -1
    if start >= 0:
        out.append(Vector2i(start, CANVAS.x - 1))
    return out


func _mean_width(dots: Array[Vector2i]) -> float:
    var total := 0.0
    for dot: Vector2i in dots:
        total += dot.x
    return total / maxf(dots.size(), 1.0)


func _wave_at(x: float) -> float:
    return WAVE_ROW + WAVE_HEIGHT * sin(TAU * WAVE_TURNS * (x - LINE_FROM.x) / (LINE_TO.x - LINE_FROM.x))


## Canvas Scumble drawn along the wave at *pressure*, and the share of the
## stroke's core it painted and the share it left open, as x and y.
func _scumble_core(pressure: float) -> Vector2:
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    var brush := StateNoiseBrushScript.new()
    brush.surface = _surface
    brush.stroke_seed = 7
    SaPresetStore.copy_settings(_scumble(), brush.settings)
    brush.settings.color = Color(0.1, 0.1, 0.1, 1.0)
    var steps := 160
    var from := Vector2(LINE_FROM.x, _wave_at(LINE_FROM.x))
    brush.begin_stroke(from, pressure)
    for i in range(1, steps + 1):
        var x := lerpf(LINE_FROM.x, LINE_TO.x, float(i) / float(steps))
        brush.add_sample(Vector2(x, _wave_at(x)), pressure)
    brush.end_stroke()
    var layer := _surface.easel.document.active_layer
    var images := {}
    var painted := 0
    var open := 0
    var count := 0
    for x in range(int(LINE_FROM.x) + 80, int(LINE_TO.x) - 80):
        var middle := roundi(_wave_at(float(x)))
        for dy in range(-WAVE_CORE, WAVE_CORE + 1):
            var alpha := _alpha(layer, Vector2i(x, middle + dy), images)
            painted += 1 if alpha >= PAINTED else 0
            open += 1 if alpha < OPEN else 0
            count += 1
    return Vector2(float(painted) / count, float(open) / count)


## The alpha of *layer* at *pixel*, reading each chunk back once into *images*.
func _alpha(layer: SaLayer, pixel: Vector2i, images: Dictionary) -> float:
    for grid: Vector2i in layer.chunks:
        var side := (layer.chunks[grid] as SaChunk).pixel_size()
        var here := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
        if not layer.chunks.has(here):
            return 0.0
        if not images.has(here):
            images[here] = SaExport.get_texture_image_float(layer.get_field(here))
        return (images[here] as Image).get_pixelv(pixel - here * side).a
    return 0.0


func _deviation(values: PackedFloat32Array) -> float:
    var mean := 0.0
    for value in values:
        mean += value
    mean /= maxf(values.size(), 1.0)
    var total := 0.0
    for value in values:
        total += (value - mean) * (value - mean)
    return sqrt(total / maxf(values.size(), 1.0))
