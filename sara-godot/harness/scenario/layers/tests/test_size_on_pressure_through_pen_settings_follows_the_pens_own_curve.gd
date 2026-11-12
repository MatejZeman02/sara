## Size on pressure through `pen_settings` follows the pen's own curve.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## With `size_by_pressure` true, Fill at radius 40 laid
## 1, 7, 39 and 79 px at pressures 0.01, 0.1, 0.5 and 1, and ticked through
## `pen_settings` the same strokes laid 29, 47, 69 and 79. The harness pen's
## table, `SaHarnessPen`, is fitted to the curve the bar's switch draws, and the
## tick read the option's straight line. Here Fill is set twice by a real
## `brush` step on a canvas of the suite's own, once each way at a radius of 40
## pixels, and each setting paints a stroke at every pressure through the
## harness's table, through the brush tool's own input path, as
## `test_the_harness_pen_widens_a_stroke_with_its_pressure.gd` paints. A width is
## the count of texels in one column across the stroke whose alpha reaches
## [constant VISIBLE], which is what a shot shows.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## The canvas, the brush and the widths need a RenderingDevice.
const REQUIRES_GPU := true

## One chunk, so a column of the stroke is one readback, and the shorter side
## the step turns `radius_px` against.
const CANVAS := Vector2i(256, 256)

## The reported radius in the pixels the bar shows.
const RADIUS_PX: int = 40

## The reported four pressures.
const PRESSURES: Array[float] = [0.01, 0.1, 0.5, 1.0]

## How far apart the two widths may be at one pressure, the row's own 2 px.
const TOLERANCE: int = 2

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

## The tick that was reported, and the switch it is held against.
const TICK := {"size": {"enabled": true, "sensors": ["pressure"]}}
const SWITCH := {"size_by_pressure": true}

## The straight line a fresh option reads.
const STRAIGHT: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 1.0)]

## Fifty pixels at no pressure and full at full, a curve of a painter's own.
const OWN: Array[Vector2] = [Vector2(0.0, 0.5), Vector2(1.0, 1.0)]

## The two as the option holds them.
static var straight_line := PackedVector2Array(STRAIGHT)
static var own_line := PackedVector2Array(OWN)

var _host: Node = null
var _canvas: SaCanvas = null
var _machine: ToolMachine = null
var _max_pressure: float = 1.0

## The suite's canvas, held as the document in front, which is where a
## harness step and a door line look.
var _front: Fixtures.FrontDocuments = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _max_pressure = SaSettings.tablet_max_pressure
    SaSettings.tablet_max_pressure = SaHarnessPen.CEILING
    _host = Node.new()
    _host.name = "R8PenSettingsHost"
    EventBus.add_child(_host)
    _canvas = SaCanvas.new()
    _canvas.canvas_size = CANVAS
    _host.add_child(_canvas)
    _canvas.size = Vector2(CANVAS)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _canvas.add_child(_machine)
    _machine.bind(SaSurface.create(&"main", _canvas.easel, SaCanvasView.for_canvas(_canvas)), Fixtures.make_tool_registry())
    _machine.set_active_tool(&"brush")
    _front = Fixtures.FrontDocuments.over(_canvas)


func after_each() -> void:
    if _front != null:
        _front.put_back()
        _front = null
    SaSettings.tablet_max_pressure = _max_pressure
    if _machine != null:
        _machine.registered_tools.clear()
        _machine.active_tool = null
        _machine.registry = null
    if _host != null:
        _host.free()
    _host = null
    _canvas = null
    _machine = null


func test_fill_at_radius_40_lays_the_same_width_by_the_switch_and_by_pen_settings() -> void:
    var by_switch := _fill_set_by_the_step(SWITCH)
    var by_tick := _fill_set_by_the_step({"pen_settings": TICK})
    var table := SaHarnessPen.read_table()
    assert_true(table.size() >= 2, "The harness's table is there to read, %d entries" % table.size())
    var said := PackedStringArray()
    for pressure in PRESSURES:
        var switched := _width(by_switch, pressure, table)
        var ticked := _width(by_tick, pressure, table)
        said.append("%.2f: %d and %d" % [pressure, switched, ticked])
        assert_true(
            absi(switched - ticked) <= TOLERANCE,
            "At %.2f the switch laid %d px and pen_settings %d, within %d" % [pressure, switched, ticked, TOLERANCE]
        )
    var full := _width(by_switch, 1.0, table)
    assert_true(absi(full - 2 * RADIUS_PX) <= 3, "A full press lays the whole 80 px, %d. Widths %s" % [full, ", ".join(said)])


## The straight line the tick read before, which the shipped recipes still ask
## for, lays far wider than the switch at a press of 0.1, so the case above
## passes because of the curve and not because the widths cannot differ. At
## the reported 0.01 both now lay a texel or none, since the harness
## table's foot is capped.
func test_the_straight_line_a_recipe_keeps_lays_wider_than_the_switch() -> void:
    var by_switch := _fill_set_by_the_step(SWITCH)
    var straight := _fill()
    straight.apply_pen_settings(TICK, true)
    straight.radius = by_switch.radius
    assert_eq(straight.size_option.common_curve, straight_line, "The tick a recipe makes reads the straight line")
    var table := SaHarnessPen.read_table()
    var switched := _width(by_switch, 0.1, table)
    var on_the_line := _width(straight, 0.1, table)
    assert_true(
        on_the_line - switched > 4 * TOLERANCE,
        "At 0.1 the straight line laid %d px against the switch's %d" % [on_the_line, switched]
    )


## The reported taper asked from 0.2 landed at about 0.6 of the width on the
## straight line. Through `pen_settings` it now lands near a fifth, as the
## switch's does, and the straight line still lays over half.
func test_a_taper_from_a_fifth_lands_near_a_fifth_of_the_width() -> void:
    var by_tick := _fill_set_by_the_step({"pen_settings": TICK})
    var straight := _fill()
    straight.apply_pen_settings(TICK, true)
    straight.radius = by_tick.radius
    var table := SaHarnessPen.read_table()
    var full := float(_width(by_tick, 1.0, table))
    var ticked := _width(by_tick, 0.2, table) / full
    var on_the_line := _width(straight, 0.2, table) / full
    assert_true(absf(ticked - 0.2) <= 0.05, "At 0.2 pen_settings laid %.2f of the width" % ticked)
    assert_true(on_the_line > 0.5, "At 0.2 the straight line laid %.2f of the width" % on_the_line)


func test_the_tick_draws_the_switchs_own_curve_on_size_and_on_opacity() -> void:
    var switched := _fill()
    switched.size_by_pressure = true
    var ticked := _fill()
    ticked.apply_pen_settings(TICK)
    assert_eq(ticked.size_option.common_curve, switched.size_option.common_curve, "Size reads the switch's curve")
    assert_eq(ticked.size_option.common_curve, StampSettingsScript.pressure_curve(2.0), "which is the power 4.8")
    assert_true(ticked.size_option.sensor_for(SaSensor.Id.PRESSURE) != null, "and pressure is ticked")
    var bare := _fill()
    bare.opacity_option.sensors.clear()
    bare.opacity_option.common_curve = straight_line
    bare.apply_pen_settings({"opacity": {"enabled": true, "sensors": ["pressure"]}})
    assert_eq(bare.opacity_option.common_curve, StampSettingsScript.pressure_curve(0.5), "Opacity reads its switch's 1.2")


func test_a_curve_of_its_own_is_kept() -> void:
    var painted := _fill()
    painted.size_by_pressure = true
    painted.size_option.common_curve = own_line
    painted.apply_pen_settings(TICK)
    assert_eq(painted.size_option.common_curve, own_line, "A size already reading a sensor keeps its curve")
    for asked: Dictionary in [
        {"common_curve": OWN, "sensors": ["pressure"]},
        {"sensors": ["pressure"], "common_curve": OWN},
    ]:
        var named := _fill()
        named.apply_pen_settings({"size": asked})
        assert_eq(named.size_option.common_curve, own_line, "A common_curve beside the tick is kept, %s" % [asked.keys()])
    var on_the_sensor := _fill()
    on_the_sensor.apply_pen_settings({"size": {"sensors": [{"id": "pressure", "curve": OWN}]}})
    assert_eq(on_the_sensor.size_option.common_curve, straight_line, "A pressure entry with a curve draws none")
    var flow := _fill()
    flow.apply_pen_settings({"flow": {"enabled": true, "sensors": ["pressure"]}})
    assert_eq(flow.flow_option.common_curve, straight_line, "Flow has no switch, so it keeps the straight line")
    var tilted := _fill()
    tilted.apply_pen_settings({"size": {"enabled": true, "sensors": ["tilt_elevation"]}})
    assert_eq(tilted.size_option.common_curve, straight_line, "A tick of anything but pressure draws nothing")


## Inked Pen, the Eraser and Grainy Pencil tick Size on pressure with no curve,
## and their recipes were written and recorded on the straight line.
func test_the_shipped_recipes_that_tick_size_keep_the_straight_line() -> void:
    var seen := 0
    for entry: Dictionary in SaShippedPresets.entries():
        var pen: Dictionary = entry.get("pen_settings", {})
        var size: Dictionary = pen.get("size", {})
        var ticked: Array = size.get("sensors", [])
        if not ticked.has("pressure") or size.has("common_curve"):
            continue
        var built := SaShippedPresets.build(StampSettingsScript, entry) as SaStampBrushSettings
        assert_eq(built.size_option.common_curve, straight_line, "%s keeps the straight line" % entry["name"])
        seen += 1
    assert_true(seen >= 3, "Every such recipe was read, %d" % seen)


## Fill as it ships, put in the canvas machine's hand and set by a `brush` step
## of *spec* with the reported radius, answered as the settings it left.
func _fill_set_by_the_step(spec: Dictionary) -> SaStampBrushSettings:
    var brush: Object = _machine.get_tool("brush")
    brush.settings = _fill()
    var step := spec.duplicate(true)
    step["radius_px"] = RADIUS_PX
    var answer := SaCaptureLayers.brush(Engine.get_main_loop() as SceneTree, step)
    assert_true(answer.begins_with("SaCapture: brush ") and answer.ends_with(", unset {}"), "The step set it all: %s" % answer)
    return brush.settings as SaStampBrushSettings


static func _fill() -> SaStampBrushSettings:
    for entry: Dictionary in SaShippedPresets.entries():
        if entry["name"] == "Fill":
            return SaShippedPresets.build(StampSettingsScript, entry) as SaStampBrushSettings
    return null


## How many texels across a stroke of *settings* at *pressure* through *table*
## show it.
func _width(settings: SaStampBrushSettings, pressure: float, table: PackedFloat32Array) -> int:
    var count := 0
    for alpha in _paint(settings, pressure, table):
        if alpha >= VISIBLE:
            count += 1
    return count


## One stroke of *settings* at *pressure* on a fresh document, read through
## *table* as the app reads a brush made after the harness's file was read,
## answered as the alpha of column [constant READ_X] from top to bottom.
func _paint(settings: SaStampBrushSettings, pressure: float, table: PackedFloat32Array) -> PackedFloat32Array:
    var surface := Fixtures.make_surface(CANVAS)
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var brush: Object = machine.active_tool
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
