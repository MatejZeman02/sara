## The `select` step keeps a feather's fraction.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The step handed `int(spec["feather"])` on, so
## feathers of 2.0, 2.5 and 2.9 laid one edge, 3.97 px from 10 to 90 %, and
## 3.0 laid 5.5. The feather now takes its radius with a fraction, so these
## select a rectangle through the step's own call at 2.0, 2.5 and 3.0 and read
## one row of the mask back across its left edge. A feather is a box along each
## axis, so across an upright edge the coverage is one box's ramp, and its 10
## to 90 % width is 0.8 of the box's width, 2r + 1.
extends "res://tests/test_framework.gd"

## The selection is chunks on the GPU, and the window a display.
const REQUIRES_GPU := true

const MainCanvasScript = preload("res://render/main_canvas.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const CanvasDriver := preload("res://harness/drivers/sa_canvas_driver.gd")
const Fixtures := preload("res://tests/fixtures.gd")

## The rectangle selected, inside the first chunk, and the row read across its
## left edge, halfway down so the vertical pass leaves the ramp as it was.
const RECT := [64, 64, 128, 128]
const ROW := 128

## Where the row is read, either side of the edge at x 64.
const FROM_X := 48
const TO_X := 80

## The feathers asked for, a whole one either side of the fraction.
const FEATHERS: Array[float] = [2.0, 2.5, 3.0]

## How far a measured width may sit from the box's, in texels.
const WITHIN := 0.05

var _host: Node = null
var _canvas: Node = null
var _driver: CanvasDriver = null
## The suite's canvas, held as the document in front, which is where a step
## looks.
var _front: Fixtures.FrontDocuments = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "SelectStepTestHost"
    EventBus.add_child(_host)
    _canvas = MainCanvasScript.new()
    _host.add_child(_canvas)
    _front = Fixtures.FrontDocuments.over(_canvas.canvas)
    _driver = CanvasDriver.new(CaptureRun.new())


func after_each() -> void:
    _driver = null
    if _front != null:
        _front.put_back()
        _front = null
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    _canvas = null


## Three feathers, three widths, each the one its box gives, and the selection's
## box grown by the whole texels the fraction's taps reach.
func test_a_feathers_fraction_widens_the_edge() -> void:
    var canvas: SaCanvas = _canvas.canvas
    assert_eq(CanvasDriver.main_canvas(), canvas, "The step finds this suite's canvas")
    var widths: Array[float] = []
    for feather: float in FEATHERS:
        _driver.select({"rect": RECT, "feather": feather})
        var selection := canvas.document.selection
        var width := _ramp_width(_row(selection))
        widths.append(width)
        var expected := 0.8 * (2.0 * feather + 1.0)
        assert_almost_eq(
            width, expected, WITHIN, "A feather of %s ramps over %s texels, measured %s" % [feather, expected, width]
        )
        var reach := ceili(feather)
        assert_eq(
            selection.bounds,
            Rect2i(RECT[0], RECT[1], RECT[2], RECT[3]).grow(reach),
            "and the selection's box grows by %d, the furthest its taps read" % reach
        )
    assert_true(widths[0] < widths[1] and widths[1] < widths[2], "Three feathers lay three widths: %s" % [widths])


## The coverage along [constant ROW] from [constant FROM_X] to [constant TO_X],
## read from the one chunk the rectangle is in.
func _row(selection: SaSelection) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    var chunk: SaChunk = selection.chunks.get(Vector2i.ZERO, null)
    assert_not_null(chunk, "The rectangle's chunk is selected")
    if chunk == null:
        return out
    var texture := chunk.field(SaSelection.FIELD)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var texel: int = SaFieldSpec.BYTES_PER_TEXEL[texture.format]
    for x in range(FROM_X, TO_X):
        out.append(bytes.decode_float((ROW * chunk.pixel_size() + x) * texel))
    return out


## How many texels the ramp in *row* takes to rise from 10 to 90 %, each end
## found between the two texels either side of it.
func _ramp_width(row: PackedFloat32Array) -> float:
    return _crossing(row, 0.9) - _crossing(row, 0.1)


func _crossing(row: PackedFloat32Array, level: float) -> float:
    for i in range(1, row.size()):
        if row[i] >= level and row[i - 1] < level:
            return float(i - 1) + (level - row[i - 1]) / (row[i] - row[i - 1])
    assert_true(false, "The row rises through %s: %s" % [level, row])
    return 0.0
