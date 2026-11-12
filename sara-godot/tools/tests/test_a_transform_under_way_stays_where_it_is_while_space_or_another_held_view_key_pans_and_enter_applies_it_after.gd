## A transform under way stays where it is while Space or
## another held view key pans, and Enter applies it after.
##
## A painter asked: "when in transform mode (I have a layer that I
## currently move into a desired place), I ofthen use the pan tool (hold space)
## to move, because I am zoomed in. But when I press the space, the moved stuff
## jumps back because I 'switched' a tool. I need it to stay to be able to tune
## it and then" "press enter after I am happy with the finetuned position."
##
## `SaToolMachine._switch_tool` reset whatever tool it left, a held pan
## included, and the transform's `reset` puts a lift back, which is the jump the
## painter met. The suite drives the machine itself with real key and mouse
## events through `handle_input`, so the switching it tests is the switching the
## painter did, and it reads the transform's own matrix, box and preview rather
## than a picture of them.
##
## `scenarios/a-transform-under-way-stays-where-it-is.json` is the same
## claim against the running app.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const CANVAS := Vector2i(1024, 1024)
const PAINT := Color(0.8, 0.3, 0.1, 1.0)
const STROKE := Rect2i(300, 300, 200, 160)
## The body drags either side of the held pan, in document pixels. Enter must
## land the paint at their sum, clear of where it was painted, so the old place
## and the new one cannot be confused for one another.
const MOVE := Vector2(400.0, -140.0)
const AFTER := Vector2(-100.0, -60.0)
const TOTAL := Vector2i(300, -200)
## What the pan drag travels, which moves the view and not the picture.
const PAN := Vector2(40.0, 25.0)


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## *rect*, in document pixels, painted on the active layer through an upload,
## since the brush is not what this suite is about.
static func _paint(document: SaDocument, rect: Rect2i) -> void:
    var layer := document.active_layer
    var device := GlobalShaderCompiler.get_rd()
    for grid_pos: Vector2i in SaChunkWalk.positions_in(rect):
        var chunk := layer.get_or_create_chunk(grid_pos)
        var texture := chunk.albedo()
        var edge := chunk.pixel_size()
        var image := Image.create_from_data(edge, edge, false, _image_format(texture), device.texture_get_data(texture.rid, 0))
        image.fill_rect(SaChunkWalk.local_rect(grid_pos, rect, edge), PAINT)
        device.texture_update(texture.rid, 0, image.get_data())
        layer.mark_unresolved(grid_pos)
    document.invalidate_chunks(layer.chunks.keys())


## Every chunk's colour bytes, by grid position.
static func _texels(layer: SaLayer) -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in layer.chunks:
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(layer.chunks[grid_pos].albedo().rid, 0)
    return out


## The alpha of the layer's own texel at *at*, zero where it has no chunk.
static func _alpha_at(layer: SaLayer, at: Vector2i) -> float:
    var texel := Rect2i(at, Vector2i.ONE)
    for grid_pos: Vector2i in SaChunkWalk.positions_in(texel):
        if not layer.chunks.has(grid_pos):
            return 0.0
        var texture: SaTexture = layer.chunks[grid_pos].albedo()
        var edge: int = layer.chunks[grid_pos].pixel_size()
        var data := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var image := Image.create_from_data(edge, edge, false, _image_format(texture), data)
        return image.get_pixelv(SaChunkWalk.local_rect(grid_pos, texel, edge).position).a
    return 0.0


## What the overlay draws for *tool*: the box, the map the ants follow and
## whether the handles are on. A painter reads the jump back off the picture,
## which a suite cannot, so the three the picture is made of are read instead.
static func _preview(tool: StateTransformScript) -> Dictionary:
    var shape := tool.preview_shape()
    return {
        "quad": shape.get("quad", PackedVector2Array()),
        "ants": shape.get("ants", null),
        "handles": shape.get("handles", false),
    }


## The pointer at *at*, in document pixels, which every tool here reads rather
## than the event's own position.
static func _point(surface: SaSurface, at: Vector2) -> void:
    surface.view.mouse_position = at


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


static func _motion(relative: Vector2) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    event.relative = relative
    return event


## A key press or release as the machine hears it. It is handed to the machine
## alone and never to `Input`, so nothing resyncs a modifier behind the suite's
## back: the machine's own resync asks `Input` about the three modifiers only.
static func _key(machine: ToolMachine, keycode: Key, pressed: bool, ctrl: bool = false) -> void:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.pressed = pressed
    event.ctrl_pressed = ctrl or (pressed and keycode == KEY_CTRL)
    machine.handle_input(event)


## A press at *from*, a motion to *to* and a release, then the frame's tick.
static func _drag(surface: SaSurface, machine: ToolMachine, from: Vector2, to: Vector2) -> void:
    _point(surface, from)
    machine.handle_input(_button(true))
    _point(surface, to)
    machine.handle_input(_motion(Vector2.ZERO))
    machine.handle_input(_button(false))
    machine._process(1.0 / 60.0)


## The pan's own drag: a press, a motion that travels *by*, and a release, with
## the view left where the travel put it.
static func _pan_drag(machine: ToolMachine, by: Vector2) -> void:
    machine.handle_input(_button(true))
    machine.handle_input(_motion(by))
    machine.handle_input(_button(false))


## A surface, the machine over it and the transform tool in the hand, over a
## layer painted across `STROKE`. The machine is built for a mouse: the suite
## hands it its own events and wants each one passed straight through, rather
## than read as a pen's barrel under a Wayland-named server.
## Returns `[surface, machine, document, layer, tool]`.
func _rig() -> Array:
    var surface := Fixtures.make_surface(CANVAS)
    var machine := Fixtures.make_bound_machine(surface, false)
    var document := surface.get_document()
    _paint(document, STROKE)
    machine.set_active_tool(&"transform")
    return [surface, machine, document, document.active_layer, machine.get_tool(&"transform")]


## The painter's sequence: a body drag into place, Space and a pan while the
## move is in the air, Space let go, a second drag to fine tune it, and Enter.
## The move is in the transform's own hands at every step the pan crosses, and
## the paint lands at the sum of the two drags as one history step.
func test_a_held_space_pans_under_a_transform_that_stays_and_enter_lands_the_summed_move() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var machine: ToolMachine = parts[1]
    var document: SaDocument = parts[2]
    var layer: SaLayer = parts[3]
    var tool: StateTransformScript = parts[4]
    var steps := document.history.step_count()
    var painted := _texels(layer)

    var centre := Vector2(STROKE.get_center())
    _drag(surface, machine, centre, centre + MOVE)
    assert_true(tool.is_moving(), "The body drag has the picture in the air")
    assert_true(tool.holds_session(), "as an open session")
    var drawn: Transform2D = tool.matrix
    var quad := tool.pending_quad()
    var preview := _preview(tool)
    assert_true(not drawn.is_equal_approx(Transform2D.IDENTITY), "the matrix has moved, %s" % [drawn])
    assert_eq(document.history.step_count(), steps, "and writes nothing before Enter")
    var lifted := _texels(layer)

    _key(machine, KEY_SPACE, true)
    assert_eq(machine.active_tool_name, &"pan", "Space puts the pan in the hand")

    var before_pan := surface.view.get_pan()
    _pan_drag(machine, PAN)
    assert_eq(surface.view.get_pan(), before_pan + PAN, "The pan drag moves the view under the tool")

    assert_true(tool.is_moving(), "The picture is still in the air under it")
    assert_true(tool.holds_session(), "with the session open")
    assert_true(tool.matrix.is_equal_approx(drawn), "the matrix as the hand left it, %s" % [tool.matrix])
    assert_eq(tool.pending_quad(), quad, "the box where it was taken")
    assert_eq(_preview(tool), preview, "and the preview the overlay draws")
    assert_eq(_texels(layer), lifted, "and the pixels are not put back")

    _key(machine, KEY_SPACE, false)
    assert_eq(machine.active_tool_name, &"transform", "Letting Space go is the transform again")
    assert_true(tool.holds_session(), "with the move still in hand")

    var again := centre + MOVE
    _drag(surface, machine, again, again + AFTER)
    assert_eq(document.history.step_count(), steps, "The second drag writes nothing either")
    _key(machine, KEY_ENTER, true)
    assert_eq(document.history.step_count(), steps + 1, "and Enter lands both drags as one step")
    var landed := Rect2i(STROKE.position + TOTAL, STROKE.size)
    for at: Vector2i in [landed.position + Vector2i(4, 4), landed.get_center(), landed.end - Vector2i(5, 5)]:
        assert_almost_eq(_alpha_at(layer, at), 1.0, 0.01, "The paint is at the summed offset, %s" % at)
    for at: Vector2i in [STROKE.position + Vector2i(4, 4), STROKE.get_center()]:
        assert_almost_eq(_alpha_at(layer, at), 0.0, 0.01, "and gone from where it was painted, %s" % at)
    assert_true(document.undo(), "One undo")
    assert_eq(_texels(layer), painted, "puts the paint back where it was painted, byte for byte")

    Fixtures.teardown(surface, machine)


## The other two switches the note keeps as they are: the zoom's own quick key
## is a held view key too and leaves the move, and a permanent pick of the
## brush is the reach the transform's reset was written for and puts it back.
func test_the_zoom_s_quick_key_keeps_the_move_and_a_permanent_switch_puts_it_back() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var machine: ToolMachine = parts[1]
    var document: SaDocument = parts[2]
    var layer: SaLayer = parts[3]
    var tool: StateTransformScript = parts[4]
    var steps := document.history.step_count()
    var painted := _texels(layer)
    var box := tool.pending_box()

    var centre := Vector2(STROKE.get_center())
    _drag(surface, machine, centre, centre + MOVE)
    var drawn: Transform2D = tool.matrix
    var quad := tool.pending_quad()

    _key(machine, KEY_CTRL, true, true)
    _key(machine, KEY_SPACE, true, true)
    assert_eq(machine.active_tool_name, &"zoom", "Ctrl and Space put the quick zoom in the hand")
    assert_true(tool.holds_session(), "and the move is still in it")
    assert_true(tool.matrix.is_equal_approx(drawn), "the matrix as the hand left it, %s" % [tool.matrix])
    assert_eq(tool.pending_quad(), quad, "and the box where it was taken")

    _key(machine, KEY_SPACE, false, true)
    _key(machine, KEY_CTRL, false)
    assert_eq(machine.active_tool_name, &"transform", "Letting the zoom go is the transform again")
    assert_true(tool.holds_session(), "with the move still in hand")

    machine.set_active_tool(&"brush")
    assert_eq(machine.active_tool_name, &"brush", "Picking the brush permanently is the switch")
    assert_false(tool.holds_session(), "that puts the move back, as it did")
    assert_true(tool.matrix.is_equal_approx(Transform2D.IDENTITY), "its matrix one again, %s" % [tool.matrix])
    assert_eq(tool.pending_box(), box, "the box where the layer is")
    assert_eq(_texels(layer), painted, "and the paint where it was painted, byte for byte")
    assert_eq(document.history.step_count(), steps, "with nothing written")

    Fixtures.teardown(surface, machine)
