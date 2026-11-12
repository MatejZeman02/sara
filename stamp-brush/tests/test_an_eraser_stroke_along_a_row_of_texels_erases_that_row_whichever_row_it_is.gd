## An eraser stroke along a row of texels erases that row,
## whichever row it is.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## An Eraser stroke along each row of a layer at y + 0.5, the texel's centre, at
## radius 1.2, takes the whole row, the even rows and the odd ones alike. A dab
## under three pixels across is in the pixel mode, which snaps its centre with a
## floor, the texel the canvas shows under the point. A round would send y + 0.5,
## the tie, to the row below, and a view's last bit of float error on the way to
## the document would turn some of the ties the other way.
##
## Each case fills a layer opaque, strokes one row through the tool machine
## with real input events, at radius 1.2 and full pressure with the stabiliser
## off, and reads the row under the stroke at alpha 0 along its middle, and the
## rows two above and two below untouched. An even row and an odd row, through
## the Eraser tool with the shipped Eraser and through the Brush with the
## Inked Pen and the erase row ticked, and the painter's three heights in a
## texel, y + 0.15, 0.5 and 0.85, each alone on a fresh layer.
##
## Only a pen, Sharpness at one, enters the mode, and every other
## brush draws a thin line antialiased, so the shipped Eraser's strokes here are
## made a pen first. The floor is the mode's, and the mode is what this holds.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

## The proof is paint taken out of a chunk, so this needs a real RenderingDevice.
const REQUIRES_GPU := true

const PAINT := Color(0.1, 0.1, 0.1, 1.0)

## The painter's radius in document pixels, a dab 2.4 across, in the mode.
const RADIUS: float = 1.2

## The rows the strokes run along, one even and one odd.
const EVEN_ROW: int = 100
const ODD_ROW: int = 101

## The stroke's two ends and the stretch of its row read back, clear of the
## ends, where a round dab's cap would read less than the row.
const FROM_X: float = 40.0
const TO_X: float = 200.0
const READ_FROM: int = 60
const READ_TO: int = 180
const READ_MIDDLE: int = 120

## One motion a pixel, so a dab lands on every texel of the row.
const STEP: float = 1.0

var _surface: SaSurface = null
var _doc: SaDocument = null
var _machine: ToolMachine = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    # The blend modes' registry, without which the eraser's mode erases nothing.
    _surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _surface.easel.document
    _machine = Fixtures.make_bound_machine(_surface)
    var layer := SaLayerOps.new(_doc).add(&"")
    _doc.set_active_layer(layer)
    _doc.fill_layer(PAINT, layer)


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _doc = null
    _machine = null


## The Eraser along an even row at its centre takes the row.
func test_the_eraser_along_an_even_row_at_its_centre_takes_that_row() -> void:
    _erase_with_the_eraser(float(EVEN_ROW) + 0.5)
    _assert_the_row_went(EVEN_ROW, "the Eraser at y + 0.5 on an even row")


## And on an odd row, the one the painter's strokes left whole.
func test_the_eraser_along_an_odd_row_at_its_centre_takes_that_row() -> void:
    _erase_with_the_eraser(float(ODD_ROW) + 0.5)
    _assert_the_row_went(ODD_ROW, "the Eraser at y + 0.5 on an odd row")


## The erase row of a painting brush goes the same way, because the fault was
## in where the dab lands and not in the erase.
func test_the_erase_row_of_a_painting_brush_takes_an_odd_row() -> void:
    _machine.set_active_tool(&"brush")
    var brush: Object = _machine.active_tool
    brush.settings = _recipe("Inked Pen")
    brush.toggle_eraser()
    _stroke(float(ODD_ROW) + 0.5)
    _assert_the_row_went(ODD_ROW, "the Inked Pen's erase row at y + 0.5 on an odd row")


## A painter's way round it would be three strokes a row, at y + 0.15, 0.5 and
## 0.85. Each of the three alone takes the row, since the texel under all
## three points is the same one.
func test_anywhere_in_a_texel_the_stroke_takes_that_row() -> void:
    for height: float in [0.15, 0.85]:
        _doc.fill_layer(PAINT, _doc.active_layer)
        _erase_with_the_eraser(float(ODD_ROW) + height)
        _assert_the_row_went(ODD_ROW, "the Eraser at y + %.2f on an odd row" % height)


func _erase_with_the_eraser(y: float) -> void:
    _machine.set_active_tool(&"eraser")
    var settings := _recipe("Eraser")
    settings.sharpness = SaSmallDab.PEN_SHARPNESS
    _machine.active_tool.settings = settings
    _stroke(y)


## The shipped preset *name* at RADIUS with the stabiliser off.
func _recipe(name: String) -> SaStampBrushSettings:
    var side := SaChunk.new().pixel_size()
    for entry: Dictionary in SaShippedPresets.entries():
        if String(entry["name"]) == name:
            var settings := SaShippedPresets.build(StateBrushScript.BrushSettingsScript, entry) as SaStampBrushSettings
            settings.radius = RADIUS / float(side)
            settings.stabilizer_mode = 0
            return settings
    assert_true(false, "%s is a shipped preset" % name)
    return SaStampBrushSettings.new()


## A hover, a press, a motion every STEP pixels at full pressure along *y*
## from FROM_X to TO_X, and the release that commits it.
func _stroke(y: float) -> void:
    var tool: Object = _machine.active_tool
    _move(tool, Vector2(FROM_X, y), 0.0)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = _surface.view.mouse_position
    tool.handle_input(press)
    var x := FROM_X
    while x < TO_X:
        x = minf(TO_X, x + STEP)
        _move(tool, Vector2(x, y), 1.0)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    release.position = _surface.view.mouse_position
    tool.handle_input(release)


func _move(tool: Object, at: Vector2, pressure: float) -> void:
    _surface.view.mouse_position = at
    var motion := InputEventMouseMotion.new()
    motion.position = at
    motion.pressure = pressure
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT if pressure > 0.0 else 0
    tool.handle_input(motion)


## Every texel of *row* from READ_FROM to READ_TO at alpha 0, and the rows two
## away on either side at the paint's own alpha.
func _assert_the_row_went(row: int, what: String) -> void:
    var field: Variant = _doc.active_layer.get_field(Vector2i.ZERO)
    var left := 0
    for x in range(READ_FROM, READ_TO):
        if Bench.texel(field, Vector2i(x, row)).a > 0.0:
            left += 1
    assert_eq(left, 0, "%s: every texel of row %d reads alpha 0, %d do not" % [what, row, left])
    for other: int in [row - 2, row + 2]:
        assert_almost_eq(
            Bench.texel(field, Vector2i(READ_MIDDLE, other)).a, 1.0, 1.0e-3, "%s: row %d keeps its paint" % [what, other]
        )
