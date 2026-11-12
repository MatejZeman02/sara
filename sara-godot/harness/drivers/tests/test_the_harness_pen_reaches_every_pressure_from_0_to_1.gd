## The harness pen reaches every pressure from 0 to 1.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The harness pen's table turned the presses 1
## and 2 in 255 into 0.26 and 0.27 and 3 in 255 into 0.46, so no size between
## those could be asked, and a stroke whose asked size crossed the gap bulged
## by 5 px. Here the press is stepped from 0 to 1 in 256 steps through
## `SaStrokeInfo.feed`, the call the stamp brush hands every motion to, and
## the pressure it reads is held to no jump wider than [constant MOST_JUMP].
## Then the default brush, its size on the pen's pressure, paints a stroke
## whose asked radius grows from 6 to 56 pixels, through the brush tool's own
## input path as `test_the_harness_pen_widens_a_stroke_with_its_pressure.gd`
## paints, and the width it lays never falls back. A width is the count of
## texels in a column whose alpha reaches [constant VISIBLE], and the stroke's
## is the widest column of each run of [constant RUN], which is longer than
## the gap between two dabs at the largest radius. A column between two dabs
## is up to 2 px narrower than one through a dab, a scallop the brush's
## spacing lays at any pressure, and a run that holds a dab reads past it.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The strokes are paint in chunks, so this needs a real RenderingDevice.
const REQUIRES_GPU := true

## The widest jump between two readings one step in 255 apart, the row's own.
const MOST_JUMP: float = 0.02

## What a press of 0.5 read through the table before the cap, taken again
## when the table was fitted to the merged brush, between its entries 127 and
## 128, and how far from it the reading may now sit. Taken again when Size by
## Pressure's curve was drawn in three points, and again when the default
## spacing fell to 0.05.
const HALF_BEFORE: float = 0.84375
const HALF_DRIFT: float = 0.001

## Three chunks in a row, so the stroke is long enough for its radius to grow
## by a pixel every 14, and the shorter side the brush's radius is a share of.
const CANVAS := Vector2i(768, 256)

## The asked radius at the start and at the end of the stroke, the friction's.
const SMALLEST_PX: float = 6.0
const LARGEST_PX: float = 56.0

## The stroke, left to right in document pixels, a motion every
## [constant STEP] pixels.
const FROM_X: float = 32.0
const TO_X: float = 736.0
const STROKE_Y: float = 128.0
const STEP: float = 4.0
const SEED: int = 32

## The columns read, from just past the stroke's first dab to a whole largest
## radius before its end, where the round cap closes and the width falls as it
## should.
const READ_FROM: int = 40
const READ_TO: int = 672

## The columns one width is the widest of, over the default spacing of 0.18 of
## the diameter, 20 px between two dabs at the largest radius.
const RUN: int = 24

## The alpha a texel has to reach to count as showing the stroke.
const VISIBLE: float = 0.1

var _max_pressure: float = 1.0


func before_each() -> void:
    _max_pressure = SaSettings.tablet_max_pressure
    SaSettings.tablet_max_pressure = SaHarnessPen.CEILING


func after_each() -> void:
    SaSettings.tablet_max_pressure = _max_pressure


func test_every_press_from_0_to_1_reads_within_a_fiftieth_of_the_one_before() -> void:
    var readings := _readings(SaHarnessPen.read_table())
    assert_eq(readings.size(), 256, "Every step of 1 in 255 was read")
    assert_almost_eq(readings[0], 0.0, 1e-6, "No press reads nothing")
    assert_almost_eq(readings[255], 1.0, 1e-6, "and a full press reads full")
    var widest := 0.0
    var at := 0
    var falls := 0
    for i in range(1, readings.size()):
        var jump := readings[i] - readings[i - 1]
        if jump > widest:
            widest = jump
            at = i
        if jump < 0.0:
            falls += 1
    assert_true(widest <= MOST_JUMP, "The widest jump is %.4f, from %d to %d in 255" % [widest, at - 1, at])
    assert_eq(falls, 0, "and the reading never falls as the press rises")


## The fit the table is made from, without the cap, jumps as the friction
## found, so the case above passes because of the cap and not because the
## widths fit no jump.
func test_the_bare_fit_of_the_same_widths_jumps_where_the_friction_found() -> void:
    var bare := _bare_fit()
    assert_eq(bare.size(), 256, "The bare fit is the table's length")
    var readings := _readings(bare)
    # With the switch's curve drawn in three points and a thin line drawn
    # antialiased rather than in whole texels, the jumps are 0 to 0.21 and 0.22
    # to 0.33, each still five times MOST_JUMP and more.
    assert_true(readings[1] - readings[0] > 0.1, "Its first step jumps from 0 to %.2f" % readings[1])
    assert_true(readings[3] - readings[2] > 0.1, "and its third from %.2f to %.2f" % [readings[2], readings[3]])


## Only the table's foot moves. Every entry the cap leaves is the bare fit's,
## and a press of 0.5 reads what it read before.
func test_a_press_of_a_half_reads_what_it_read_before() -> void:
    var table := SaHarnessPen.read_table()
    var bare := _bare_fit()
    var first_kept := -1
    var moved_after := 0
    for i in range(mini(table.size(), bare.size())):
        var kept := absf(table[i] - bare[i]) <= 1e-5
        if kept and first_kept < 0 and i > 0:
            first_kept = i
        elif not kept and first_kept >= 0:
            moved_after += 1
    assert_true(first_kept > 0, "The cap leaves the fit's own entries from %d in 255" % first_kept)
    assert_true(first_kept <= 40, "which is from a press of %.3f, under 0.16" % (float(first_kept) / 255.0))
    assert_eq(moved_after, 0, "and moves none above it")
    var half := SaTablet.correct(0.5, table)
    assert_almost_eq(half, HALF_BEFORE, HALF_DRIFT, "A press of 0.5 reads %.5f, as it read %.5f" % [half, HALF_BEFORE])


## The default brush's switch, its size along the reading to the power 4.8,
## asked each radius as the share of the largest the harness pen promises.
func test_a_stroke_asked_from_radius_6_to_56_by_the_switch_never_narrows() -> void:
    var settings := _brush()
    settings.size_by_pressure = true
    var widths := _widths(_stroke(settings, _shares()))
    _assert_never_narrows(widths, "by the switch")


## The straight line a recipe keeps, which the friction's own stroke read, asked
## each radius the way the friction check asked it: the least press on the grid of 1
## in 255 the table reads as the radius's share or more.
func test_a_stroke_asked_from_radius_6_to_56_on_the_straight_line_never_narrows() -> void:
    var table := SaHarnessPen.read_table()
    var settings := _brush()
    settings.apply_pen_settings({"size": {"enabled": true, "sensors": ["pressure"]}}, true)
    var asked := PackedFloat32Array()
    var worst := 0.0
    for share in _shares():
        var press := _least_press(table, share)
        asked.append(press)
        worst = maxf(worst, SaTablet.correct(press, table) - share)
    assert_true(worst <= MOST_JUMP, "Each share is asked within %.4f of itself on the grid" % worst)
    var widths := _widths(_stroke(settings, asked))
    _assert_never_narrows(widths, "on the straight line")


func _assert_never_narrows(widths: PackedInt32Array, how: String) -> void:
    assert_eq(widths.size(), range(READ_FROM, READ_TO, RUN).size(), "Every run of columns %s was read" % how)
    var falls := PackedStringArray()
    var each := PackedStringArray()
    for i in range(widths.size()):
        each.append(str(widths[i]))
        if i > 0 and widths[i] < widths[i - 1]:
            falls.append("x %d: %d after %d" % [READ_FROM + i * RUN, widths[i], widths[i - 1]])
    var said := "Widths %s: %s" % [how, ", ".join(each)]
    assert_true(widths[0] > 0, "The stroke shows at its start, %d px. %s" % [widths[0], said])
    assert_true(widths[widths.size() - 1] > 4 * widths[0], "and ends far wider. %s" % said)
    assert_true(falls.is_empty(), "and never narrows on the way, %s. %s" % [", ".join(falls), said])


## The reading at every press from 0 to 1 in steps of 1 in 255, through the
## call the stamp brush feeds each motion to, with *table* as the brush's.
func _readings(table: PackedFloat32Array) -> PackedFloat32Array:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO)
    var out := PackedFloat32Array()
    for i in range(256):
        info.feed(Vector2(float(i), 0.0), float(i) / 255.0, Vector2.ZERO, 0.0, float(i), table)
        out.append(info.pressure)
    return out


static func _bare_fit() -> PackedFloat32Array:
    var widths := SaHarnessPen.read_widths()
    var full := widths[widths.size() - 1].y
    var sweep := PackedVector2Array()
    for pair in widths:
        sweep.append(Vector2(pair.x, pair.y / full))
    return SaTabletSweep.fit([sweep])


## The least press on the grid of 1 in 255 that *table* reads as *share* or
## more, which is how the friction check turned a radius into a press.
static func _least_press(table: PackedFloat32Array, share: float) -> float:
    for i in range(256):
        var press := float(i) / 255.0
        if SaTablet.correct(press, table) >= share:
            return press
    return 1.0


## The asked radius over the largest at every motion of the stroke, growing
## evenly from [constant SMALLEST_PX] to [constant LARGEST_PX].
static func _shares() -> PackedFloat32Array:
    var out := PackedFloat32Array()
    var x := FROM_X
    while x < TO_X:
        x = minf(TO_X, x + STEP)
        var along := (x - FROM_X) / (TO_X - FROM_X)
        out.append(lerpf(SMALLEST_PX, LARGEST_PX, along) / LARGEST_PX)
    return out


## The default brush at the largest radius, its opacity off the pen as the
## friction check set it, so the width is the size alone, stamped with the
## harness's table as the app stamps a brush made after reading it.
static func _brush() -> SaStampBrushSettings:
    var settings := SaStampBrushSettings.new()
    settings.radius = LARGEST_PX / float(mini(CANVAS.x, CANVAS.y))
    settings.apply_pen_settings({"opacity": {"enabled": false}})
    settings.maker_pressure_curve = SaHarnessPen.read_table()
    return settings


## One stroke of *settings* along [constant STROKE_Y], each motion at the press
## of the same index in *presses*, on a fresh document, answered as the
## document's layer images by chunk.
func _stroke(settings: SaStampBrushSettings, presses: PackedFloat32Array) -> Dictionary:
    var surface := Fixtures.make_surface(CANVAS)
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var brush: Object = machine.active_tool
    brush.settings = settings
    brush.stroke_seed = SEED
    var was := SaColors.foreground
    SaColors.foreground = Color(0.0, 0.0, 0.0, 1.0)
    _send(brush, surface, _button(true), Vector2(FROM_X, STROKE_Y))
    var x := FROM_X
    var index := 0
    while x < TO_X:
        x = minf(TO_X, x + STEP)
        var motion := InputEventMouseMotion.new()
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.pressure = presses[mini(index, presses.size() - 1)]
        _send(brush, surface, motion, Vector2(x, STROKE_Y))
        index += 1
    _send(brush, surface, _button(false), Vector2(TO_X, STROKE_Y))
    SaColors.foreground = was
    var images := _images(surface.easel.document.active_layer)
    Fixtures.teardown(surface, machine)
    return images


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


static func _send(brush: Object, surface: SaSurface, event: InputEventMouse, at: Vector2) -> void:
    surface.view.mouse_position = at
    event.position = at
    brush.handle_input(event)


## Every chunk of *layer* as an image, by its chunk coordinate, with the edge
## its pixels span under `"edge"`.
static func _images(layer: SaLayer) -> Dictionary:
    var out := {}
    for key: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[key]
        var texture := chunk.albedo()
        var edge := chunk.pixel_size()
        out["edge"] = edge
        var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
        out[key] = Image.create_from_data(
            edge,
            edge,
            false,
            Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF,
            GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        )
    return out


## The stroke's width along it: for each run of [constant RUN] columns from
## [constant READ_FROM] to [constant READ_TO], how many texels of its widest
## column show the stroke.
static func _widths(images: Dictionary) -> PackedInt32Array:
    var out := PackedInt32Array()
    for start in range(READ_FROM, READ_TO, RUN):
        var widest := 0
        for x in range(start, mini(start + RUN, READ_TO)):
            widest = maxi(widest, _column_width(images, x))
        out.append(widest)
    return out


## How many texels of column *x* show the stroke.
static func _column_width(images: Dictionary, x: int) -> int:
    var edge := int(images.get("edge", 0))
    var count := 0
    if edge <= 0:
        return count
    for y in range(CANVAS.y):
        var key := Vector2i(floori(float(x) / edge), floori(float(y) / edge))
        var image: Image = images.get(key, null)
        if image != null and image.get_pixelv(Vector2i(x, y) - key * edge).a >= VISIBLE:
            count += 1
    return count
