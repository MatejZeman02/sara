## A press on the canvas after a preset pick that changes the tool begins a
## stroke.
##
## A brush preset of another engine changes the tool while the left button is
## still down on the docker, because the name area of a tile picks on the press.
## A pen whose tip lifts in the frame it leaves range does the same, as Godot's
## Wayland driver drops that release. The machine read `Input`'s button, blocked
## the brush until a release it never heard, and the whole first stroke on the
## canvas laid nothing while the second painted. It now blocks only a drag it
## heard begin, and a press it hears lifts the block.
##
## Each case holds the button through `Input` as the docker's press does, which
## the machine never hears, or through the machine as the canvas hands it on,
## changes the tool, and reads the layer's texels and the history.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Where the docker's press lands, which the canvas never hears.
const ON_THE_DOCKER := Vector2(250.0, 10.0)
## The stroke after the pick.
const FROM := Vector2(40.0, 120.0)
const TO := Vector2(120.0, 120.0)

var _surface: SaSurface = null
var _doc: SaDocument = null
var _machine: ToolMachine = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _doc = _surface.easel.document
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"eraser")
    SaUnpaintedPress.last_line = ""


func after_each() -> void:
    _hold_on_the_docker(false)
    SaStrokeNote.say("")
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _doc = null
    _machine = null


## The left button pressed or let go where the machine does not hear it, so only
## `Input` knows, as a press on a docker's tile.
func _hold_on_the_docker(pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = ON_THE_DOCKER
    event.global_position = ON_THE_DOCKER
    Input.parse_input_event(event)
    Input.flush_buffered_events()


## The brush in hand, its preset's size and a mouse's, as a pick of the stamp engine leaves it.
func _pick_the_brush() -> void:
    _machine.set_active_tool(&"brush")
    _machine.active_tool.is_tablet = false
    _machine.active_tool.settings.radius = 4.0 / 256.0


func _button(at: Vector2, pressed: bool, shift: bool = false) -> void:
    _surface.view.mouse_position = at
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.shift_pressed = shift
    event.position = at
    event.global_position = at
    _machine.handle_input(event)


func _move(at: Vector2) -> void:
    _surface.view.mouse_position = at
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    _machine.handle_input(event)


func _stroke(from: Vector2, to: Vector2) -> void:
    _button(from, true)
    for i in range(1, 5):
        _move(from.lerp(to, i / 4.0))
    _button(to, false)


func _steps() -> int:
    return _doc.undo_redo.get_history_count()


static func _alpha(layer: SaLayer, at: Vector2) -> float:
    var pixel := Vector2i(at)
    var grid := Vector2i(floori(float(pixel.x) / layer.CHUNK_SIZE), floori(float(pixel.y) / layer.CHUNK_SIZE))
    var chunk: SaChunk = layer.chunks.get(grid)
    if chunk == null:
        return 0.0
    var texture := chunk.albedo()
    @warning_ignore("integer_division")
    var local := (pixel - grid * layer.CHUNK_SIZE) * chunk.pixel_size() / layer.CHUNK_SIZE
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * texture.size.x + local.x).a


## The check the row is done on: a pick on the press, while the button is still
## down on the docker, leaves the first press on the canvas free to paint.
func test_a_pick_while_the_button_is_down_on_the_docker_leaves_the_first_press_free() -> void:
    _hold_on_the_docker(true)
    assert_true(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "Input reads the docker's press as held")
    _pick_the_brush()
    assert_false(_machine.block_brush_until_release, "and the pick sets no block for a drag the canvas never had")
    _hold_on_the_docker(false)
    var before := _steps()
    _stroke(FROM, TO)
    assert_eq(_steps(), before + 1, "The first stroke after the pick is a step")
    var middle := _alpha(_doc.active_layer, FROM.lerp(TO, 0.5))
    assert_true(middle > 0.5, "and paints from its press on, %f" % middle)
    assert_true(_alpha(_doc.active_layer, FROM) > 0.5, "the press point itself")
    assert_eq(SaUnpaintedPress.last_line, "", "and no press was said to begin nothing")


## A pen whose release Godot lost leaves the machine thinking the tip is down.
## The pick blocks for that drag, and the next press on the canvas lifts the
## block and paints from its first event.
func test_a_press_after_a_lost_release_lifts_the_block_and_paints() -> void:
    _button(Vector2(200.0, 40.0), true)
    _pick_the_brush()
    assert_true(_machine.block_brush_until_release, "A tool change in a drag the machine heard begin blocks")
    var before := _steps()
    _stroke(FROM, TO)
    assert_false(_machine.block_brush_until_release, "The next press lifts the block")
    assert_eq(_steps(), before + 1, "and its stroke is a step")
    assert_true(_alpha(_doc.active_layer, FROM) > 0.5, "that reaches its press point")


## The block keeps what it is for: a tool changed by a key in the middle of a
## canvas drag does not paint the rest of that drag with the new tool.
func test_a_tool_changed_in_a_canvas_drag_still_paints_nothing_of_that_drag() -> void:
    _button(Vector2(200.0, 40.0), true)
    _pick_the_brush()
    var before := _steps()
    _move(Vector2(200.0, 80.0))
    _move(Vector2(200.0, 120.0))
    assert_eq(_alpha(_doc.active_layer, Vector2(200.0, 100.0)), 0.0, "The rest of the drag lays nothing")
    _button(Vector2(200.0, 120.0), false)
    assert_false(_machine.block_brush_until_release, "and its release lifts the block")
    assert_eq(_steps(), before, "with no step")


## A press of a painting tool that begins no stroke says why in the log, the line
## a painter can read the next time a first dab goes missing.
func test_a_press_that_begins_no_stroke_says_why() -> void:
    _pick_the_brush()
    _button(Vector2(200.0, 200.0), true, true)
    _button(Vector2(200.0, 200.0), false, true)
    var line := SaUnpaintedPress.last_line
    assert_true(line.begins_with(SaUnpaintedPress.PREFIX), "A line is said: %s" % line)
    assert_true(line.contains("Shift"), "and it names what took the press")
