## Pointed Mark's lightest touch lays a hair, and its opacity stays off the
## pressure.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Pointed Mark as it first shipped laid nothing at
## all at pressures of 0.02 to 0.06 at radius 21.5, a trace at 0.08 and a line
## 1 px wide at 0.1, and its opacity followed the pen as well as its size, so a
## taper's end went pale before it went thin. The preset now ships with its
## opacity off the pen and its size along a curve whose foot is a fifth of the
## full width.
##
## Each line is laid as the preset ships, at its 4.5 px on the 1080 of a
## default document, through the brush tool's own input path: a press, a
## motion every [constant STEP] pixels at one pressure, and the release, in
## black on a clear layer. The columns through its middle are read back off
## the layer's chunk. A line's width is the mean of its columns' alpha summed,
## the cover in rows a probe reads off black on white, and its darkness is the
## CIE L* of its darkest texel over white paper, composited in the sRGB the
## layer holds, the mean of its columns. The pressures are a door stroke's,
## read through the table every door session reads a stroke step through, and
## a fresh profile's, read along the diagonal.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The proof is paint in a chunk, so this needs a real RenderingDevice.
const REQUIRES_GPU := true

## The row's three pressures, and the full one each is held against.
const PRESSURES: Array[float] = [0.02, 0.05, 0.1]
const FULL: float = 1.0

## The default document's shorter side, which the recipe's radius is a share
## of, so the line is the 4.5 px the preset ships at.
const SIDE: int = 1080

## The row the line runs along, and how far below its centre, the Painter's
## probe's 0.3 that a painter's dashes are read at.
const ROW: int = 100
const BELOW_CENTRE: float = 0.3

## Where in a texel a line may fall, which the darkness is read at as well.
const HEIGHTS: Array[float] = [0.0, 0.3, 0.5, 0.75]

## The line's two ends, one motion every STEP pixels, and the columns read,
## a whole full width clear of either end.
const FROM_X: float = 40.0
const TO_X: float = 216.0
const STEP: float = 4.0
const READ_FROM: int = 64
const READ_TO: int = 192

## The row's two numbers: the lightest line's width in pixels and how far its
## darkness may stand from the full-pressure line's, in CIE L*.
const LEAST_WIDTH: float = 1.0
const MOST_PALER: float = 10.0

## The table every door session reads a stroke step's pressure through, one
## number a line, read here as data so the suite names no harness class.
const DOOR_TABLE := "res://harness/drivers/pen_pressure_curve.txt"

var _max_pressure: float = 1.0
var _foreground := Color.BLACK


func before_each() -> void:
    _max_pressure = SaSettings.tablet_max_pressure
    SaSettings.tablet_max_pressure = SaTablet.DEFAULT_MAX_PRESSURE
    _foreground = SaColors.foreground
    SaColors.foreground = Color.BLACK


func after_each() -> void:
    SaSettings.tablet_max_pressure = _max_pressure
    SaColors.foreground = _foreground


## A line at each of the three
## pressures, the lightest at least 1 px wide, and each within 10 L* of the
## full-pressure line's darkness.
func test_a_door_stroke_lays_a_hair_at_each_light_pressure() -> void:
    _assert_hairs(_door_table(), "a door stroke")


## The same on a fresh profile's pen, whose reading is the pressure itself.
func test_a_fresh_profiles_pen_lays_a_hair_at_each_light_pressure() -> void:
    _assert_hairs(_diagonal(), "a fresh profile's pen")


## The width grows with the pressure, from the
## lightest through the full, on both tables.
func test_the_width_grows_with_the_pressure() -> void:
    for table: PackedFloat32Array in [_door_table(), _diagonal()]:
        var how := "a door stroke" if table.size() > 2 else "a fresh profile's pen"
        var widths := PackedFloat32Array()
        var said := PackedStringArray()
        for pressure: float in PRESSURES + [FULL]:
            var width := _width(_line(_recipe(table), pressure, BELOW_CENTRE))
            widths.append(width)
            said.append("%.2f: %.3f px" % [pressure, width])
        print("  Widths on %s, %s" % [how, ", ".join(said)])
        for i in range(1, widths.size()):
            assert_true(widths[i] > widths[i - 1], "On %s the width grows with the pressure, %s" % [how, ", ".join(said)])


## Wherever the lightest line falls in a texel it keeps one whole, so its
## darkness is the stroke's own at every height and not only at the probe's.
func test_wherever_the_lightest_line_falls_it_is_as_dark_as_the_full_one() -> void:
    var table := _door_table()
    var full := _darkness(_line(_recipe(table), FULL, BELOW_CENTRE))
    var said := PackedStringArray()
    for height: float in HEIGHTS:
        var lightest := _darkness(_line(_recipe(table), PRESSURES[0], height))
        said.append("%.2f: L* %.1f" % [height, lightest])
        assert_true(
            lightest - full <= MOST_PALER,
            "At height %.2f the lightest line is L* %.1f against the full line's %.1f" % [height, lightest, full]
        )
    print("  The lightest line's darkness at heights %s, the full one's L* %.1f" % [", ".join(said), full])


## The preset's two switches as the row names them: the size on the pen's
## pressure and the opacity off it.
func test_only_the_size_follows_the_pen() -> void:
    var settings := _recipe(_diagonal())
    assert_true(settings.size_option.enabled, "Pointed Mark's size follows the pen")
    assert_true(settings.size_option.sensors.has(int(SaSensor.Id.PRESSURE)), "through the pressure sensor")
    assert_false(settings.opacity_option.enabled, "and its opacity does not")
    assert_false(settings.opacity_by_pressure, "as the bar's switch shows")


## The cause, measured: the recipe as it first shipped, its size on the switch's
## curve and its opacity on the pen, laid nothing at the lightest pressure of
## a door stroke and a paler line than its full one at the heaviest of the
## three, so the cases above fail on that first recipe.
func test_as_k3_shipped_it_the_lightest_touch_laid_nothing() -> void:
    var table := _door_table()
    var before := _recipe(table)
    before.size_option.sensors.clear()
    before.size_by_pressure = false
    before.size_by_pressure = true
    before.opacity_by_pressure = true
    var lightest := _width(_line(before, PRESSURES[0], BELOW_CENTRE))
    assert_almost_eq(lightest, 0.0, 1e-3, "As first shipped, a door stroke at %.2f laid %.3f px" % [PRESSURES[0], lightest])
    var full := _darkness(_line(before, FULL, BELOW_CENTRE))
    var heaviest := _darkness(_line(before, PRESSURES[2], BELOW_CENTRE))
    print("  As first shipped, %.2f laid L* %.1f against the full line's %.1f" % [PRESSURES[2], heaviest, full])
    assert_true(
        heaviest - full > MOST_PALER, "and %.2f laid L* %.1f against the full line's %.1f" % [PRESSURES[2], heaviest, full]
    )


func _assert_hairs(table: PackedFloat32Array, how: String) -> void:
    var full := _darkness(_line(_recipe(table), FULL, BELOW_CENTRE))
    for pressure: float in PRESSURES:
        var line := _line(_recipe(table), pressure, BELOW_CENTRE)
        var width := _width(line)
        var darkness := _darkness(line)
        print("  On %s at %.2f, a line %.3f px wide at L* %.1f, the full one L* %.1f" % [how, pressure, width, darkness, full])
        assert_true(width >= LEAST_WIDTH, "On %s at %.2f the line is %.3f px wide" % [how, pressure, width])
        assert_true(
            darkness - full <= MOST_PALER,
            "On %s at %.2f the line is L* %.1f against the full line's %.1f" % [how, pressure, darkness, full]
        )


## Pointed Mark built as the store builds it, stamped with *table* as the app
## stamps a brush made after reading its table.
func _recipe(table: PackedFloat32Array) -> SaStampBrushSettings:
    for entry: Dictionary in SaShippedPresets.entries():
        if String(entry["name"]) == "Pointed Mark":
            var settings := SaShippedPresets.build(StateBrushScript.BrushSettingsScript, entry) as SaStampBrushSettings
            settings.maker_pressure_curve = table
            return settings
    assert_true(false, "Pointed Mark is a shipped preset")
    return SaStampBrushSettings.new()


## The diagonal, which a fresh profile's brush is stamped with.
static func _diagonal() -> PackedFloat32Array:
    return PackedFloat32Array([0.0, 1.0])


func _door_table() -> PackedFloat32Array:
    var table := PackedFloat32Array()
    for line in FileAccess.get_file_as_string(DOOR_TABLE).split("\n", false):
        table.append(line.to_float())
    assert_eq(table.size(), 256, "The door's table is read whole")
    return table


## The alpha of the chunk one line of *settings* at *pressure* leaves, its
## line *height* of a texel below ROW's centre.
func _line(settings: SaStampBrushSettings, pressure: float, height: float) -> PackedFloat32Array:
    var surface := Fixtures.make_surface(Vector2i(SIDE, SIDE))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var brush: Object = machine.active_tool
    brush.settings = settings
    var y := float(ROW) + height
    _send(brush, surface, _button(true), Vector2(FROM_X, y))
    var x := FROM_X
    while x < TO_X:
        x = minf(TO_X, x + STEP)
        var motion := InputEventMouseMotion.new()
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.pressure = pressure
        _send(brush, surface, motion, Vector2(x, y))
    _send(brush, surface, _button(false), Vector2(TO_X, y))
    var alpha := _alpha(surface.easel.document)
    Fixtures.teardown(surface, machine)
    return alpha


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


static func _send(brush: Object, surface: SaSurface, event: InputEventMouse, at: Vector2) -> void:
    surface.view.mouse_position = at
    event.position = at
    brush.handle_input(event)


## The mean over the read columns of each column's alpha summed.
static func _width(alpha: PackedFloat32Array) -> float:
    var side := int(sqrt(float(alpha.size())))
    var total := 0.0
    for x in range(READ_FROM, READ_TO):
        for y in side:
            total += alpha[y * side + x]
    return total / float(READ_TO - READ_FROM)


## The mean over the read columns of the CIE L* of each column's darkest
## texel, black at its alpha over white in the sRGB the layer holds.
static func _darkness(alpha: PackedFloat32Array) -> float:
    var side := int(sqrt(float(alpha.size())))
    var total := 0.0
    for x in range(READ_FROM, READ_TO):
        var most := 0.0
        for y in side:
            most = maxf(most, alpha[y * side + x])
        total += _l_star(1.0 - clampf(most, 0.0, 1.0))
    return total / float(READ_TO - READ_FROM)


## The CIE L* of a grey whose sRGB value is *encoded*.
static func _l_star(encoded: float) -> float:
    var linear := SaTransferFunction.srgb().decode(encoded)
    if linear <= 216.0 / 24389.0:
        return linear * 24389.0 / 27.0
    return 116.0 * pow(linear, 1.0 / 3.0) - 16.0


## The active layer's alpha over its first chunk, row by row. A layer that
## holds no chunk there is clear.
static func _alpha(doc: SaDocument) -> PackedFloat32Array:
    var chunk: SaChunk = doc.active_layer.chunks.get(Vector2i.ZERO)
    var side := chunk.pixel_size() if chunk != null else SaChunk.new().pixel_size()
    var out := PackedFloat32Array()
    out.resize(side * side)
    if chunk == null:
        return out
    var texture: SaTexture = chunk.albedo()
    var wide := texture.format == RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    var texel_bytes := 16 if wide else 8
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    for at in side * side:
        out[at] = data.decode_float(at * texel_bytes + 12) if wide else data.decode_half(at * texel_bytes + 6)
    return out
