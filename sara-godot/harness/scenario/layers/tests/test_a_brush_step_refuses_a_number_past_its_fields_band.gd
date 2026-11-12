## A brush step refuses a number past the band its field is clamped to.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Strokes at `texture_contrast` 1.5 and 3.0 read alike, because the tone clamps the contrast at one,
## and the brush step had answered both as done. A field the brush clamps now
## declares the clamp as its range hint, and the step reads it off the property
## and refuses past it with nothing set, in a line `shot_problems.py` reports as
## a refusal because it opens with "could not".
##
## The step is called as the table calls it, on a canvas of the suite's own in
## the tree with the stamp module's brush in its machine. No door and no bar,
## because neither is what decides a refusal, and `test_one_brush_step_sets_the_
## preset_the_colour_and_the_size.gd` drives the step through both already.
extends "res://tests/test_framework.gd"

const StampSettingsScript := preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The canvas and the machine need a RenderingDevice.
const REQUIRES_GPU := true

const DOCUMENT := Vector2i(256, 256)

## What a refused step's line opens with, which is one of `shot_problems.py`'s
## REFUSAL_OPENERS, so a capture reports it as a problem.
const REFUSED := "SaCapture: could not set "

const MODULES: Array[String] = [
    "res://modules/sara-base-modules/stamp-brush/module.gd",
    "res://modules/sara-base-modules/base/module.gd",
]

var _host: Node = null
var _canvas: SaCanvas = null
var _machine: ToolMachine = null
var _ctx: SaContext = null
var _modules: Array[SaModule] = []

## The suite's canvas, held as the document in front, which is where a
## harness step and a door line look.
var _front: Fixtures.FrontDocuments = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "D22BrushStepHost"
    EventBus.add_child(_host)
    _canvas = SaCanvas.new()
    _canvas.canvas_size = DOCUMENT
    _host.add_child(_canvas)
    _canvas.size = Vector2(DOCUMENT)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _canvas.add_child(_machine)
    _machine.bind(SaSurface.create(&"main", _canvas.easel, SaCanvasView.for_canvas(_canvas)), _registry())
    _machine.set_active_tool(&"brush")
    _front = Fixtures.FrontDocuments.over(_canvas)


func after_each() -> void:
    if _front != null:
        _front.put_back()
        _front = null
    for module: SaModule in _modules:
        module.unregister(_ctx)
    _modules.clear()
    _ctx = null
    if _machine != null:
        _machine.registered_tools.clear()
        _machine.active_tool = null
        _machine.registry = null
    if _host != null:
        _host.free()
    _host = null
    _canvas = null
    _machine = null


func _registry() -> SaToolRegistry:
    var registry := SaToolRegistry.new()
    _ctx = SaContext.create(
        registry,
        SaBlendModeRegistry.new(),
        SaCommandRegistry.new(),
        SaLayerTypeRegistry.new(),
        SaUIRegistry.new(),
        null,
        Callable(),
        Callable(),
        null,
        SaRoleRegistry.new()
    )
    for path: String in MODULES:
        var module: SaModule = load(path).new()
        module.register(_ctx.for_module(module.get_id()))
        _modules.append(module)
    return registry


func _settings() -> Resource:
    return _machine.get_tool(&"brush").get("settings") as Resource


func _brush(spec: Dictionary) -> String:
    return SaCaptureLayers.brush(_host.get_tree(), spec)


## The clause: a contrast of 3.0 is refused, the line says the band, and the
## contrast the brush holds is the one it held.
func test_a_contrast_of_three_is_refused() -> void:
    var answer := _brush({"texture_contrast": 3.0})
    assert_true(answer.begins_with(REFUSED + "texture_contrast to 3"), "A contrast of three is refused: %s" % answer)
    assert_true(answer.contains("-1.0 to 1.0"), "and the answer names the band the brush clamps it to: %s" % answer)
    assert_almost_eq(float(_settings().get("texture_contrast")), 0.0, 1e-9, "The brush keeps the contrast it had")


## Inside the band the step writes as it did, the two ends included.
func test_a_contrast_inside_its_band_is_set() -> void:
    for contrast: float in [-1.0, 0.5, 1.0]:
        var answer := _brush({"texture_contrast": contrast})
        assert_true(answer.begins_with("SaCapture: brush "), "A contrast of %s is set: %s" % [contrast, answer])
        assert_almost_eq(float(_settings().get("texture_contrast")), contrast, 1e-9, "and the brush holds it")


## A refusal sets nothing at all, not the fields before the one refused nor
## the colour and the size the step also carried.
func test_a_refused_step_sets_nothing_else() -> void:
    var radius := float(_settings().get("radius"))
    var answer := _brush({"opacity": 0.3, "radius_px": 40, "texture_contrast": 1.5})
    assert_true(answer.begins_with(REFUSED + "texture_contrast to 1.5"), "A contrast of 1.5 is refused: %s" % answer)
    assert_true(answer.ends_with("and set nothing"), "and says it set nothing: %s" % answer)
    assert_almost_eq(float(_settings().get("opacity")), 1.0, 1e-9, "The opacity before it was not written")
    assert_almost_eq(float(_settings().get("radius")), radius, 1e-9, "nor the size")


## The other numbers the paper's tone and scale clamp are refused the same
## way, each past its own band, and so is a number on a sub-resource, reached
## by the indexed path the step writes it through.
func test_every_clamped_paper_number_and_a_path_is_refused() -> void:
    var past := {
        "texture_scale": 5.0,
        "texture_brightness": -1.5,
        "texture_neutral": 1.2,
        "texture_cutoff_left": -0.1,
        "texture_cutoff_right": 2.0,
        "hardness:value": 1.5,
    }
    for key: String in past:
        var answer := _brush({key: past[key]})
        assert_true(answer.begins_with(REFUSED + key + " to "), "%s at %s is refused: %s" % [key, past[key], answer])
    assert_almost_eq(float(_settings().get("texture_scale")), 1.0, 1e-9, "and the scale is the one the brush had")


## A field that declares no band is written as it always was, whatever the
## number, because nothing reads a clamp off it.
func test_a_field_with_no_band_is_written_as_asked() -> void:
    var answer := _brush({"stabilizer_amount": 7.0})
    assert_true(answer.begins_with("SaCapture: brush "), "A number on a field with no band is set: %s" % answer)
    assert_almost_eq(float(_settings().get("stabilizer_amount")), 7.0, 1e-9, "as asked")
    assert_true(_settings() is StampSettingsScript, "on the stamp's own settings")
