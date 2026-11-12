## The door's Eraser answers the size it paints at.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The winter painter set Inked Pen at radius 1 with `brush` steps while the
## Brush was in hand, took up the Eraser and erased at the Eraser's own 15 px,
## and no answer had said so. Here a real `brush` step sets radius 3 on the
## Brush, a real `tool` step takes up the Eraser, and its answer names the
## Eraser's own radius and not 3. Then the `tool` key of a `brush` step sets the
## Eraser's radius, and the next answer reads it.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The canvas and the brush need a RenderingDevice.
const REQUIRES_GPU := true

const CANVAS := Vector2i(256, 256)

var _host: Node = null
var _canvas: SaCanvas = null
var _machine: ToolMachine = null

## The suite's canvas, held as the document in front, where a harness step
## looks.
var _front: Fixtures.FrontDocuments = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "U556EraserHost"
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
    if _machine != null:
        _machine.registered_tools.clear()
        _machine.active_tool = null
        _machine.registry = null
    if _host != null:
        _host.free()
    _host = null
    _canvas = null
    _machine = null


func test_the_tool_answer_names_the_erasers_own_radius_and_not_the_brushs() -> void:
    var answer := SaCaptureLayers.brush(_host.get_tree(), {"radius_px": 3})
    assert_true(answer.contains("radius 3.00 px"), "The Brush takes radius 3: %s" % answer)
    var eraser: Resource = _machine.get_tool(&"eraser").settings
    var own := float(eraser.get("radius")) * _canvas.document.brush_side
    assert_true(absf(own - 3.0) > 0.5, "and the Eraser's own radius is another, %.2f px" % own)
    var taken := SaCaptureLayers.set_tool("eraser")
    assert_eq(String(_machine.active_tool_name), "eraser", "The Eraser is in hand")
    var named := "radius %.2f px" % own
    var own_settings := taken.contains("paints with its own settings") and taken.contains(named)
    assert_true(own_settings, "The tool answer names %s: %s" % [named, taken])
    assert_false(taken.contains("radius 3.00 px"), "and not the Brush's 3: %s" % taken)
    assert_true(taken.contains("blend "), "and the blend: %s" % taken)
    assert_true(taken.contains("preset"), "and the preset: %s" % taken)


func test_the_tool_key_sets_the_erasers_radius_and_the_next_answer_reads_it() -> void:
    SaCaptureLayers.set_tool("eraser")
    var answer := SaCaptureLayers.brush(_host.get_tree(), {"tool": "eraser", "radius_px": 4})
    assert_true(answer.contains("radius 4.00 px"), "The step answers the Eraser's 4: %s" % answer)
    assert_false(answer.contains("wrote the settings of"), "and the settings were the tool in hand's: %s" % answer)
    var again := SaCaptureLayers.set_tool("eraser")
    assert_true(again.contains("radius 4.00 px"), "The next tool answer reads 4: %s" % again)


func test_a_brush_step_with_the_eraser_in_hand_says_it_wrote_the_brushs() -> void:
    SaCaptureLayers.set_tool("eraser")
    var answer := SaCaptureLayers.brush(_host.get_tree(), {"radius_px": 2})
    var said := "wrote the settings of brush and not of eraser, which paints with settings of its own"
    assert_true(answer.contains(said), "The answer names both: %s" % answer)
    assert_true(answer.ends_with(", unset {}"), "and still ends with what it could not set: %s" % answer)
