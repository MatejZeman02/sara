## The harness's pen: strokes at 0.1 to 1.0 through its table, on the default
## brush with Size by Pressure on, come out wider at every step, and the one at
## 0.5 between a third and two thirds as wide as the one at 1.0.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The strokes are painted, not evaluated. Each goes through the brush tool's
## own input path on a GPU document, the path a stroke step reaches through
## `Input.parse_input_event`, and is read back as the alpha of one column of
## texels across it. A width is how many texels of that column show the stroke
## at [constant VISIBLE], so what is measured is what a shot shows, the tip's
## soft edge and Opacity by Pressure included. The painting session that
## first measured the curve read its widths off a shot, and a thin stroke's
## soft edge was most of what it missed.
##
## **The fit is held to what the brush paints today.** The widths beside the
## table are measured again on the diagonal and read against the file, so a
## change to the default brush that moves them fails here rather than leaving
## the harness pressing with a curve fitted to another brush. The message
## prints the widths measured. `SARA_FIT_HARNESS_PEN=1` in the environment of
## a run of this suite writes them and the table fitted from them over the two
## files instead, which is how the fit is taken again.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The widths are paint in a chunk, so this needs a real RenderingDevice.
const REQUIRES_GPU := true

## One chunk, so a column of the stroke is one readback.
const CANVAS := Vector2i(256, 256)

## The brush's radius as the fraction of the canvas the setting is: 128 pixels
## across at full pressure here, wide enough that the fit's low end, where the
## diagonal paints a stroke of a texel or two, is still read in whole texels.
const RADIUS: float = 64.0 / 256.0

## The stroke, left to right in document pixels, and the column read across it,
## far enough from both ends that the pressure has settled.
const FROM_X: float = 24.0
const TO_X: float = 232.0
const STROKE_Y: float = 128.0
const STEP: float = 4.0
const READ_X: int = 128
const SEED: int = 32

## The alpha a texel has to reach to count as showing the stroke.
const VISIBLE: float = 0.1

## How many pressures the fit is measured at, 0 to 1 in fortieths, so the steep
## part of the diagonal's response is read at more than two points.
const PRESSURES: int = 41

## How far a width measured today may sit from the one in the file, in texels,
## before the fit counts as taken on another brush.
const DRIFT: float = 1.0

## The environment variable that asks for the fit to be taken again.
const FIT_AGAIN: String = "SARA_FIT_HARNESS_PEN"

var _max_pressure: float = 1.0


func before_each() -> void:
    _max_pressure = SaSettings.tablet_max_pressure
    SaSettings.tablet_max_pressure = SaHarnessPen.CEILING


func after_each() -> void:
    SaSettings.tablet_max_pressure = _max_pressure


func test_a_stroke_through_the_harness_table_widens_with_its_pressure() -> void:
    var table := SaHarnessPen.read_table()
    assert_true(table.size() >= 2, "The harness's table is there to read, %d entries" % table.size())
    var widths: Array[int] = []
    for i in range(1, 11):
        widths.append(_width(float(i) / 10.0, table))
    for i in range(1, widths.size()):
        assert_true(
            widths[i] > widths[i - 1],
            (
                "The stroke at %.1f is wider than the one at %.1f, %d texels against %d"
                % [(i + 1) / 10.0, i / 10.0, widths[i], widths[i - 1]]
            )
        )
    var half := float(widths[4]) / float(widths[9])
    assert_true(half >= 1.0 / 3.0, "The stroke at 0.5 is at least a third of the one at 1.0, %d of %d" % [widths[4], widths[9]])
    assert_true(half <= 2.0 / 3.0, "and at most two thirds, %d of %d" % [widths[4], widths[9]])


## The diagonal, the table a fresh profile read before the harness had one,
## fails the same measure, so the one above passes because of the table and
## not the brush.
func test_the_diagonal_leaves_the_stroke_at_a_half_under_a_third() -> void:
    var at_half := _width(0.5, SaTabletSweep.identity(2))
    var at_full := _width(1.0, SaTabletSweep.identity(2))
    assert_true(at_full > 0, "The full stroke painted, %d texels" % at_full)
    assert_true(
        float(at_half) < float(at_full) / 3.0, "On the diagonal the stroke at 0.5 is %d of %d texels" % [at_half, at_full]
    )


func test_the_table_is_the_fit_of_the_widths_beside_it() -> void:
    var fitted := SaHarnessPen.fit(SaHarnessPen.read_widths())
    var table := SaHarnessPen.read_table()
    assert_eq(table.size(), SaTabletSweep.SAMPLES, "The table is the sweep calibration's length")
    assert_eq(fitted.size(), table.size(), "and the fit of the widths is one too")
    var worst := 0.0
    for i in range(mini(fitted.size(), table.size())):
        worst = maxf(worst, absf(fitted[i] - table[i]))
    assert_true(worst <= 1e-5, "The table is the widths' fit to its six decimals, worst %f" % worst)


func test_the_widths_beside_it_are_what_the_default_brush_paints_today() -> void:
    var stored := SaHarnessPen.read_widths()
    var measured := _diagonal_widths()
    if OS.get_environment(FIT_AGAIN) == "1":
        var notes := PackedStringArray(
            [
                "The width in texels a stroke of the default brush paints with Size by Pressure on,",
                (
                    "on the diagonal table and a ceiling of %.2f, a radius of %.4f of a %d pixel canvas,"
                    % [SaHarnessPen.CEILING, RADIUS, CANVAS.y]
                ),
                "read across the stroke at an alpha of %.2f. Written by %s." % [VISIBLE, get_script().resource_path.get_file()],
            ]
        )
        assert_true(SaHarnessPen.write(measured, notes), "The fit was taken again and written")
        return
    assert_eq(stored.size(), measured.size(), "The file holds a width for every pressure measured")
    var lines := PackedStringArray()
    var worst := 0.0
    for i in range(mini(stored.size(), measured.size())):
        worst = maxf(worst, absf(stored[i].y - measured[i].y))
        lines.append("%.3f %.1f" % [measured[i].x, measured[i].y])
    var says := (
        "The widths in the file are what the brush paints today, worst %.1f texels off. Today's:\n%s\n"
        % [worst, "\n".join(lines)]
    )
    assert_true(worst <= DRIFT, says + "Run this suite with %s=1 to take the fit again." % FIT_AGAIN)


## The width at each of [constant PRESSURES] pressures from 0 to 1 on the
## diagonal, as the `Vector2(pressure, width)` pairs the fit reads.
##
## The first pair is written rather than painted. A stroke whose every motion
## reports nothing is a mouse's to `StateBrush`, which paints it at full
## pressure, 123 texels wide on the first measure, and a pen pressing nothing
## paints nothing, which is what the fit needs to start from.
func _diagonal_widths() -> PackedVector2Array:
    var pairs := PackedVector2Array([Vector2.ZERO])
    for i in range(1, PRESSURES):
        var pressure := float(i) / float(PRESSURES - 1)
        pairs.append(Vector2(pressure, float(_width(pressure, SaTabletSweep.identity(2)))))
    return pairs


## How many texels across the stroke at *pressure* through *table* show it.
func _width(pressure: float, table: PackedFloat32Array) -> int:
    var column := _paint(pressure, table)
    var count := 0
    for alpha in column:
        if alpha >= VISIBLE:
            count += 1
    return count


## One stroke of the default brush with Size by Pressure on, at *pressure*
## through *table*, on a fresh document, answered as the alpha of column
## [constant READ_X] from top to bottom.
##
## The table is stamped on the settings as the app stamps a brush made after
## the harness's file was read at startup.
func _paint(pressure: float, table: PackedFloat32Array) -> PackedFloat32Array:
    var surface := Fixtures.make_surface(CANVAS)
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var brush: Object = machine.active_tool
    var settings := SaStampBrushSettings.new()
    settings.size_by_pressure = true
    settings.radius = RADIUS
    settings.maker_pressure_curve = table
    brush.settings = settings
    brush.stroke_seed = SEED
    var was := SaColors.foreground
    SaColors.foreground = Color(0.0, 0.0, 0.0, 1.0)
    _send(brush, surface, _button(true), Vector2(FROM_X, STROKE_Y))
    var x := FROM_X
    while x < TO_X:
        x = minf(TO_X, x + STEP)
        var motion := InputEventMouseMotion.new()
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.pressure = pressure
        _send(brush, surface, motion, Vector2(x, STROKE_Y))
    _send(brush, surface, _button(false), Vector2(TO_X, STROKE_Y))
    SaColors.foreground = was
    var column := _column(surface.easel.document.active_layer)
    Fixtures.teardown(surface, machine)
    return column


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


static func _send(brush: Object, surface: SaSurface, event: InputEventMouse, at: Vector2) -> void:
    surface.view.mouse_position = at
    event.position = at
    brush.handle_input(event)


## The alpha of column [constant READ_X] of chunk 0, 0, or none when nothing
## was painted there.
static func _column(layer: SaLayer) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    var chunk: SaChunk = layer.chunks.get(Vector2i.ZERO, null)
    if chunk == null:
        return out
    var texture := chunk.albedo()
    var edge := chunk.pixel_size()
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var image := Image.create_from_data(
        edge,
        edge,
        false,
        Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF,
        GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    )
    for y in range(edge):
        out.append(image.get_pixel(READ_X, y).a)
    return out
