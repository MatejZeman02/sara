## A stroke on a group says
## the group holds no paint and not that it is locked.
##
## A group answers `is_locked` whatever was set, and `paint_refusal_line`
## asked for the lock first, so a stroke on a group told the painter to unlock
## a layer that has no padlock. Each test strokes the stamp brush across the
## canvas and hears the line `SaContext.refuse_paint` says on the bus.
extends "res://tests/test_framework.gd"

## Chunks are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _heard: PackedStringArray = PackedStringArray()


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _machine = Fixtures.make_bound_machine(_surface)
    _heard = PackedStringArray()
    EventBus.paint_refused.connect(_hear)


func after_each() -> void:
    EventBus.paint_refused.disconnect(_hear)
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func _hear(line: String) -> void:
    _heard.append(line)


func _doc() -> SaDocument:
    return _surface.get_document()


func _button(pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    _machine.active_tool.handle_input(event)


## One stroke of the brush tool, whose engine is the stamp brush.
func _stroke() -> void:
    _machine.set_active_tool(&"brush")
    _surface.view.mouse_position = Vector2(40, 40)
    _button(true)
    var motion := InputEventMouseMotion.new()
    motion.pressure = 0.6
    _surface.view.mouse_position = Vector2(150, 110)
    _machine.active_tool.handle_input(motion)
    _button(false)


func test_a_stroke_on_a_group_names_the_group_and_not_a_lock() -> void:
    var ops := SaLayerOps.new(_doc())
    var inside := ops.add()
    _doc().active_layer = inside
    var group := ops.group_active()
    assert_true(group != null and group.is_group, "The fixture wraps the layer in a group")
    _doc().active_layer = group
    _stroke()
    assert_eq(_heard.size(), 1, "A stroke on a group says one line")
    var line := _heard[0] if _heard.size() > 0 else ""
    assert_true(line.contains("group holds no paint"), "which names the group: %s" % line)
    assert_false(line.contains("locked"), "and not a lock")
    assert_eq(line, SaContext.paint_refusal_line(group, "stroke"), "and is the door's sentence for the stroke")


func test_a_locked_group_still_names_the_group() -> void:
    var ops := SaLayerOps.new(_doc())
    _doc().active_layer = ops.add()
    var group := ops.group_active()
    group.is_locked = true
    _doc().active_layer = group
    _stroke()
    var line := _heard[0] if _heard.size() > 0 else ""
    assert_true(line.contains("group holds no paint"), "A locked group is still a group to the painter: %s" % line)


func test_a_stroke_on_a_locked_layer_says_it_is_locked_as_before() -> void:
    var layer := SaLayerOps.new(_doc()).add()
    layer.is_locked = true
    _doc().active_layer = layer
    _stroke()
    assert_eq(_heard.size(), 1, "A stroke on a locked layer says one line")
    var line := _heard[0] if _heard.size() > 0 else ""
    var locked := TranslationServer.translate("This layer is locked, so the %s did nothing. Unlock it in the Layers docker.")
    assert_eq(line, locked % "stroke", "which is the locked line as before")
