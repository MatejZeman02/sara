## A rub or a stroke that changes nothing, because the active
## layer is empty or hidden, says which layer took it.
##
## The newcomer added a layer with the plus, rubbed the eraser over the stroke
## below, and nothing changed and nothing was said. These hold that the rub
## names the empty layer and the one holding the paint, that a stroke on a
## hidden layer names it as hidden, and that a rub over paint says nothing.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _doc: SaDocument = null
var _heard: Array[String] = []


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(512, 512))
    _machine = Fixtures.make_bound_machine(_surface)
    _doc = _surface.get_document()
    _doc.active_layer.name = "Layer 1"
    _heard.clear()
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


## A press at *from*, a motion to *to* and a release with the tool *tool*.
func _rub(tool: StringName, from: Vector2, to: Vector2) -> void:
    _machine.set_active_tool(tool)
    var state := _machine.active_tool
    state.set(&"eraser_toggled", false)
    var view := _surface.view as Fixtures.FakeView
    view.mouse_position = from
    state.handle_input(_button(true))
    for step in range(1, 9):
        view.mouse_position = from.lerp(to, step / 8.0)
        var motion := InputEventMouseMotion.new()
        motion.pressure = 1.0
        state.handle_input(motion)
    state.handle_input(_button(false))


## A paint layer named *name* on top of the stack, made active.
func _add_layer(name: String) -> SaLayer:
    var layer := SaLayer.new()
    layer.name = name
    _doc.add_child(layer)
    _doc.set_active_layer(layer)
    return layer


func test_an_eraser_over_an_empty_layer_names_it_and_the_layer_holding_the_paint() -> void:
    var painted := _doc.active_layer
    _rub(&"brush", Vector2(100, 200), Vector2(400, 200))
    assert_false(painted.chunks.is_empty(), "The stroke lands on Layer 1")
    assert_eq(_heard, [] as Array[String], "and says nothing")
    var empty := _add_layer("Layer 2")
    var steps := _doc.undo_redo.get_history_count()
    _rub(&"eraser", Vector2(100, 200), Vector2(400, 200))
    assert_eq(_heard.size(), 1, "The rub over the empty layer says one line")
    assert_eq(_heard[0], SaContext.empty_erase_line(empty, painted), "naming the empty layer and the one below")
    assert_true(_heard[0].contains("'Layer 2'"), "names " + "'Layer 2'")
    assert_true(_heard[0].contains("'Layer 1'"), "names " + "'Layer 1'")
    assert_eq(_doc.undo_redo.get_history_count(), steps, "and adds no history step")


## The fixture's bottom layer is a stored background, which holds paint an
## eraser takes, so the empty layer is put under it to have nothing below.
func test_an_eraser_over_an_empty_layer_with_nothing_below_names_it_alone() -> void:
    var empty := _add_layer("Layer 2")
    _doc.move_child(empty, 0)
    _rub(&"eraser", Vector2(100, 200), Vector2(400, 200))
    assert_eq(_heard, [SaContext.empty_erase_line(empty, null)] as Array[String], "The rub names the empty layer")


func test_a_stroke_on_a_hidden_layer_names_it_as_hidden() -> void:
    var hidden := _add_layer("Sketch")
    hidden.visible = false
    _rub(&"brush", Vector2(100, 200), Vector2(400, 200))
    assert_eq(_heard.size(), 1, "The stroke says one line")
    assert_eq(_heard[0], SaContext.hidden_layer_line(hidden, tr("stroke")), "naming the layer as hidden")
    assert_true(_heard[0].contains("'Sketch'"), "names " + "'Sketch'")


func test_a_stroke_in_a_hidden_group_names_its_layer_as_hidden() -> void:
    var group := SaLayer.new()
    group.name = "Folder"
    group.is_group = true
    group.visible = false
    _doc.add_child(group)
    var inside := _add_layer("Inside")
    inside.group = group
    _rub(&"brush", Vector2(100, 200), Vector2(400, 200))
    assert_eq(_heard, [SaContext.hidden_layer_line(inside, tr("stroke"))] as Array[String], "A hidden group hides it too")


func test_an_eraser_over_paint_on_the_active_layer_says_nothing() -> void:
    _rub(&"brush", Vector2(100, 200), Vector2(400, 200))
    _rub(&"eraser", Vector2(100, 200), Vector2(400, 200))
    assert_eq(_heard, [] as Array[String], "A rub that takes paint says nothing")


func test_a_preset_picture_s_rub_says_nothing() -> void:
    _add_layer("Layer 2")
    SaStrokeNote.aside(func() -> void: _rub(&"eraser", Vector2(100, 200), Vector2(400, 200)))
    assert_eq(_heard, [] as Array[String], "A stroke set aside says nothing on the message bar")
