## The door clears an area of a layer and selects a polygon.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The painting session of 2026-10-11 erased part of a layer by reading its
## pixels, zeroing them and writing them back, and kept strokes inside a shape
## by clipping each against masks it built, because the door's `select` read as
## a rectangle only. These select through the step's own call, a triangle by
## polygon and a rectangle, then paint a stroke across the triangle with the
## brush on the tool machine and clear through the `clear` step's call, and
## read the layer's texels back.
extends "res://tests/test_framework.gd"

## The selection, the layer and the brush are chunks on the GPU.
const REQUIRES_GPU := true

const MainCanvasScript = preload("res://render/main_canvas.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const CanvasDriver := preload("res://harness/drivers/sa_canvas_driver.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## A triangle pointing up, inside the first chunk, its base on row 200.
const TRIANGLE: Array = [[60, 200], [200, 200], [130, 60]]

## The row the stroke runs along, across the triangle and well past both sides.
const ROW := 170

## The rectangle the clear empties, and two points well outside it.
const RECT: Array = [40, 40, 80, 60]

## What counts as paint on a texel: anything a reader could see.
const SEEN := 0.002

var _host: Node = null
var _canvas: Node = null
var _driver: CanvasDriver = null
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _kept_foreground: Color
## The suite's canvas, held as the document in front, which is where a step
## looks.
var _front: Fixtures.FrontDocuments = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "ClearTestHost"
    EventBus.add_child(_host)
    _canvas = MainCanvasScript.new()
    _host.add_child(_canvas)
    _front = Fixtures.FrontDocuments.over(_canvas.canvas)
    _driver = CanvasDriver.new(CaptureRun.new())
    _kept_foreground = SaColors.foreground
    SaColors.foreground = Color(0.8, 0.2, 0.1, 1.0)


func after_each() -> void:
    SaColors.foreground = _kept_foreground
    if _machine != null:
        _machine.registered_tools.clear()
        _machine.active_tool = null
        _machine.surface = null
        _machine.registry = null
        _machine.free()
    _machine = null
    # The easel is the canvas's, freed with the host, so the surface over it
    # is only let go of here.
    _surface = null
    _driver = null
    if _front != null:
        _front.put_back()
        _front = null
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    _canvas = null


## A triangle selected by polygon holds a stroke across it: paint inside the
## triangle, none to either side of it on the stroke's row or above its apex.
func test_a_stroke_across_a_polygon_lands_inside_it_only() -> void:
    var document := _document()
    _driver.select({"polygon": TRIANGLE})
    assert_true(document.selection.active, "The polygon made a selection")
    _stroke(Vector2(10, ROW), Vector2(240, ROW))
    assert_true(_alpha(130, ROW) > 0.5, "The stroke painted the triangle's middle")
    assert_true(_alpha(130, 120) < SEEN, "and nothing above the row, inside the triangle but off the stroke")
    for x: int in [20, 60, 72, 188, 200, 235]:
        assert_true(_alpha(x, ROW) < SEEN, "Left of x 75 and right of x 185 the row is outside it and bare, at x %d" % x)
    for x: int in [80, 130, 180]:
        assert_true(_alpha(x, ROW) > 0.5, "inside it the row is painted, at x %d" % x)


## A filled layer with a rectangle selected, cleared through the door: the
## rectangle is empty, the rest as it was, and one undo fills it again.
func test_a_clear_empties_the_selected_rectangle_as_one_undo_step() -> void:
    var document := _document()
    _driver.fill([0.3, 0.5, 0.7])
    assert_almost_eq(_alpha(60, 60), 1.0, 0.001, "The fill covered the layer")
    _driver.select(RECT)
    var before := document.history.position()
    _driver.clear()
    assert_eq(document.history.position(), before + 1, "The clear is one undo step")
    assert_almost_eq(_alpha(41, 41), 0.0, 0.001, "Inside the rectangle, at its first corner, the layer is empty")
    assert_almost_eq(_alpha(80, 70), 0.0, 0.001, "and at its middle")
    assert_almost_eq(_alpha(119, 99), 0.0, 0.001, "and at its last corner")
    for point: Vector2i in [Vector2i(39, 70), Vector2i(120, 70), Vector2i(80, 39), Vector2i(80, 100), Vector2i(220, 220)]:
        assert_almost_eq(_alpha(point.x, point.y), 1.0, 0.001, "Outside it, at %s, the fill is as it was" % point)
    assert_true(document.undo(), "One Ctrl+Z")
    assert_almost_eq(_alpha(80, 70), 1.0, 0.001, "fills the rectangle again")
    assert_almost_eq(_alpha(41, 41), 1.0, 0.001, "to its corner")


## A locked layer refuses the clear and records nothing.
func test_a_locked_layer_refuses_the_clear() -> void:
    var document := _document()
    _driver.fill([0.3, 0.5, 0.7])
    document.active_layer.is_locked = true
    var before := document.history.position()
    _driver.clear()
    assert_eq(document.history.position(), before, "No step is recorded")
    assert_almost_eq(_alpha(60, 60), 1.0, 0.001, "and the fill stands")
    document.active_layer.is_locked = false


func _document() -> SaDocument:
    var canvas: SaCanvas = _canvas.canvas
    assert_eq(CanvasDriver.main_canvas(), canvas, "The step finds this suite's canvas")
    return canvas.document


## The brush's stroke from *from* to *to* in document pixels, on a machine over
## the main canvas's own easel.
func _stroke(from: Vector2, to: Vector2) -> void:
    if _machine == null:
        var view := Fixtures.FakeView.new()
        _surface = SaSurface.create(&"probe", _canvas.canvas.easel, view)
        _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _surface.view.mouse_position = from
    _button(true)
    var steps := 24
    for i in range(1, steps + 1):
        var motion := InputEventMouseMotion.new()
        motion.pressure = 1.0
        _surface.view.mouse_position = from.lerp(to, float(i) / steps)
        _machine.active_tool.handle_input(motion)
    _button(false)


func _button(pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    _machine.active_tool.handle_input(event)


## The active layer's alpha at (*x*, *y*), read back from its chunk.
func _alpha(x: int, y: int) -> float:
    var layer := _document().active_layer
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var chunk: SaChunk = layer.chunks.get(grid, null)
    if chunk == null:
        return 0.0
    var texture: SaTexture = chunk.field(SaFieldSpec.ALBEDO)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var texel := (y % SaChunk.SIZE) * texture.size.x + x % SaChunk.SIZE
    if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
        return bytes.decode_half(texel * 8 + 6)
    return bytes.decode_float(texel * 16 + 12)
