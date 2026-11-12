## A stroke on a hidden layer is refused at the pen's touch.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter, 2026-10-26: "bug: I am still able to paint on hidden layer, it
## only shows warning and then the stroke disappears after commit. It should not
## even show there." These hide a layer that holds paint, press each paint tool
## on it, the brush, the eraser, smudge, the fill and the gradient, and read the
## layer's texels unchanged, the undo history unchanged, no stroke open and the
## stroke buffer empty while the pen is down, and the line said once, at the
## press. The same under a hidden group, and for a stroke through the door's
## step table, whose line says the stroke was refused and why.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const StepTable := preload("res://harness/sa_step_table.gd")

const FROM := Vector2(100, 200)
const TO := Vector2(400, 220)

## The title a door stroke's line opens with.
const VERDICT := "SaCapture: stroke"

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _doc: SaDocument = null
var _heard: Array[String] = []
## What the stroke buffer and the tool held while the pen was down.
var _mid: Dictionary = {}


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(512, 512))
    _machine = Fixtures.make_bound_machine(_surface)
    _doc = _surface.get_document()
    _heard.clear()
    _mid = {}
    EventBus.paint_refused.connect(_hear)


func after_each() -> void:
    EventBus.paint_refused.disconnect(_hear)
    SaStrokeNote.say("")
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null


func _hear(line: String) -> void:
    _heard.append(line)


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


## A press at [constant FROM], a drag to [constant TO] and a release with the
## tool *tool*, keeping in [member _mid] what stood while the pen was down.
func _drag(tool: StringName, smudge: bool = false) -> void:
    _machine.set_active_tool(tool)
    var state := _machine.active_tool
    state.set(&"eraser_toggled", false)
    var settings: Variant = state.get(&"settings")
    if settings != null and settings.get(&"smudge_pickup_option") != null:
        settings.smudge_pickup_option.enabled = smudge
    var view := _surface.view as Fixtures.FakeView
    view.mouse_position = FROM
    state.handle_input(_button(true))
    for step in range(1, 9):
        view.mouse_position = FROM.lerp(TO, step / 8.0)
        var motion := InputEventMouseMotion.new()
        motion.pressure = 1.0
        state.handle_input(motion)
    if state.has_method(&"tick"):
        state.tick(0.016)
    _mid = {
        "drawing": bool(state.get(&"is_drawing")) if state.get(&"is_drawing") != null else false,
        "buffer": _doc.stroke_layer.chunks.size() if _doc.stroke_layer != null else 0,
    }
    state.handle_input(_button(false))
    if settings != null and settings.get(&"smudge_pickup_option") != null:
        settings.smudge_pickup_option.enabled = false


## A paint layer named *name*, painted with one stroke while it shows, then
## hidden, or left showing inside *group* when one is given, which is hidden.
func _painted_layer(name: String, group: SaLayer = null) -> SaLayer:
    var layer := SaLayer.new()
    layer.name = name
    _doc.add_child(layer)
    _doc.set_active_layer(layer)
    _drag(&"brush")
    assert_false(layer.chunks.is_empty(), "'%s' holds paint before it is hidden" % name)
    if group != null:
        layer.group = group
        group.visible = false
    else:
        layer.visible = false
    _heard.clear()
    return layer


## Every chunk of *layer*'s paint, read back.
static func _texels(layer: SaLayer) -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in layer.chunks:
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(layer.chunks[grid_pos].albedo().rid, 0)
    return out


## Drags *tool* over *layer*, hidden, and holds that nothing landed and one
## line, *gesture*'s, was said.
func _refused(layer: SaLayer, tool: StringName, gesture: String, smudge: bool = false) -> void:
    var texels := _texels(layer)
    var steps := _doc.undo_redo.get_history_count()
    _drag(tool, smudge)
    var what := "%s%s" % [tool, " with smudge" if smudge else ""]
    assert_false(_mid["drawing"], "The %s opened no stroke while the pen was down" % what)
    assert_eq(_mid["buffer"], 0, "and drew nothing under the pen")
    assert_eq(_texels(layer), texels, "The %s left '%s' as it was" % [what, layer.name])
    assert_eq(_doc.undo_redo.get_history_count(), steps, "and made no undo step")
    assert_eq(_heard, [SaContext.hidden_layer_line(layer, gesture)] as Array[String], "and said its line once")
    assert_true(_heard.size() == 1 and _heard[0].contains("was not made"), "saying the %s was not made" % gesture)
    _heard.clear()


func test_the_brush_is_refused_on_a_hidden_layer() -> void:
    _refused(_painted_layer("Shadow"), &"brush", tr("stroke"))


func test_the_eraser_is_refused_on_a_hidden_layer() -> void:
    _refused(_painted_layer("Shadow"), &"eraser", tr("erase"))


func test_smudge_is_refused_on_a_hidden_layer() -> void:
    _refused(_painted_layer("Shadow"), &"brush", tr("stroke"), true)


func test_the_fill_is_refused_on_a_hidden_layer() -> void:
    _refused(_painted_layer("Shadow"), &"bucket_fill", tr("fill"))


func test_the_gradient_is_refused_on_a_hidden_layer() -> void:
    _refused(_painted_layer("Shadow"), &"gradient", tr("gradient"))


func test_every_tool_is_refused_under_a_hidden_group() -> void:
    var group := SaLayer.new()
    group.name = "Folder"
    group.is_group = true
    _doc.add_child(group)
    var inside := _painted_layer("Inside", group)
    assert_true(inside.visible, "The layer's own eye is open")
    _refused(inside, &"brush", tr("stroke"))
    _refused(inside, &"eraser", tr("erase"))
    _refused(inside, &"brush", tr("stroke"), true)
    _refused(inside, &"bucket_fill", tr("fill"))
    _refused(inside, &"gradient", tr("gradient"))


## The same layer shown again takes the stroke, so the refusal is the eye's.
func test_a_layer_shown_again_takes_the_stroke() -> void:
    var layer := _painted_layer("Shadow")
    layer.visible = true
    _drag(&"brush")
    assert_true(_mid["drawing"], "The press opened a stroke")
    assert_eq(_heard, [] as Array[String], "and nothing was said")


## A stroke through the door's step table, on the tool route the door's
## strokes take under a docker, is refused the same way, and its line says it
## was refused and why, as an error the door's answer carries.
func test_a_door_stroke_is_refused_and_says_why() -> void:
    var host := Node.new()
    host.name = "DoorHost"
    EventBus.add_child(host)
    var main: Node = MainCanvasScript.new()
    host.add_child(main)
    main.bind_tools(Fixtures.make_tool_registry())
    main.notification(Container.NOTIFICATION_SORT_CHILDREN)
    var front := Fixtures.FrontDocuments.over(main.canvas as SaCanvas)
    var doc: SaDocument = (main.canvas as SaCanvas).document
    var layer := SaLayer.new()
    layer.name = "Shadow"
    doc.add_child(layer)
    doc.set_active_layer(layer)
    layer.visible = false
    var steps := doc.undo_redo.get_history_count()
    var run := CaptureRun.new()
    var table := StepTable.new(run)
    var lines := SaErrorCatcher.new()
    OS.add_logger(lines)
    run.steps = [{"stroke": {"route": "tool", "space": "document", "from": [300, 450], "to": [900, 450], "steps": 12}}]
    run.step_index = 0
    while run.step_index < run.steps.size():
        var next: Dictionary = run.steps[run.step_index]
        run.step_index += 1
        table.run(next)
        Input.flush_buffered_events()
    OS.remove_logger(lines)

    assert_true(layer.chunks.is_empty(), "The door's stroke left the hidden layer empty")
    assert_eq(doc.undo_redo.get_history_count(), steps, "and made no undo step")
    assert_eq(_heard, [SaContext.hidden_layer_line(layer, tr("stroke"))] as Array[String], "and said its line once")
    var said := Array(lines.texts(SaErrorCatcher.ERRORS)).filter(func(line: String) -> bool: return line.contains(VERDICT))
    assert_eq(said.size(), 1, "The door's answer carries one error: %s" % [lines.texts(SaErrorCatcher.ERRORS)])
    if said.size() == 1:
        assert_true(said[0].contains("refused by the"), "saying the stroke was refused: %s" % said[0])
        assert_true(said[0].contains("'Shadow' is hidden"), "and why: %s" % said[0])
    front.put_back()
    host.free()
