## A stroke on the canvas's far edge, or past it with its disc
## still reaching in, paints the texels the disc covers, the way one inside does.
##
## A stroke read along y 1080 of a canvas 1080 rows high paint
## nothing and suspected the brush. The trace found the press past the window's
## own edge, where no control takes it, and the paint path sound: a press the
## tool hears on the edge paints. This suite holds the paint path to that, so a
## later bounds test in the brush or the context cannot drop the edge quietly.
extends "res://tests/test_framework.gd"

## The strokes dispatch real dabs and the suite reads their texels back.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Two chunks across and one and a bit down, so the far edges cross chunks
## rather than falling on the grid.
const CANVAS := Vector2i(512, 300)
## The radius painted at, in document pixels.
const RADIUS := 30.0


func _button(brush: Object, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    brush.handle_input(event)


## One stroke of a mouse from *from* to *to*, in document pixels, released.
func _stroke(surface: SaSurface, brush: Object, from: Vector2, to: Vector2) -> void:
    surface.view.mouse_position = from
    _button(brush, true)
    for i in range(1, 9):
        surface.view.mouse_position = from.lerp(to, float(i) / 8.0)
        var event := InputEventMouseMotion.new()
        event.pressure = 1.0
        brush.handle_input(event)
    _button(brush, false)


## The alpha *layer* holds at document pixel *at*, zero where no chunk is.
func _alpha(layer: SaLayer, at: Vector2i) -> float:
    var grid := Vector2i(floori(float(at.x) / layer.CHUNK_SIZE), floori(float(at.y) / layer.CHUNK_SIZE))
    var chunk: SaChunk = layer.chunks.get(grid)
    if chunk == null:
        return 0.0
    var texture := chunk.albedo()
    @warning_ignore("integer_division")
    var local := (at - grid * layer.CHUNK_SIZE) * chunk.pixel_size() / layer.CHUNK_SIZE
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * texture.size.x + local.x).a


func _brush(machine: ToolMachine) -> Object:
    machine.set_active_tool(&"brush")
    var brush: Object = machine.active_tool
    brush.is_tablet = false
    brush.settings.stabilizer_amount = 0.0
    brush.settings.hardness = GammaFloat.new(1.0, 1.0)
    brush.settings.radius = RADIUS / CANVAS.y
    return brush


## Inside, on the last row's edge, and on the last column's edge: each paints
## the texels its disc covers, as far in as the radius and no further.
func test_a_stroke_on_the_far_edge_paints_like_one_inside() -> void:
    var surface := Fixtures.make_surface(CANVAS)
    var machine := Fixtures.make_bound_machine(surface)
    var layer := surface.easel.document.active_layer
    var brush := _brush(machine)

    _stroke(surface, brush, Vector2(60, 150), Vector2(120, 150))
    _stroke(surface, brush, Vector2(200, 300), Vector2(260, 300))
    _stroke(surface, brush, Vector2(512, 100), Vector2(512, 160))

    assert_true(_alpha(layer, Vector2i(90, 150)) > 0.99, "A stroke inside paints under its path")
    assert_true(_alpha(layer, Vector2i(230, 299)) > 0.99, "A stroke along the bottom edge paints the last row")
    assert_true(_alpha(layer, Vector2i(230, 275)) > 0.99, "and the rows its disc reaches, 25 in")
    assert_eq(_alpha(layer, Vector2i(230, 268)), 0.0, "and none past its radius")
    assert_true(_alpha(layer, Vector2i(511, 130)) > 0.99, "A stroke along the right edge paints the last column")
    assert_true(_alpha(layer, Vector2i(487, 130)) > 0.99, "and the columns its disc reaches, 25 in")
    assert_eq(_alpha(layer, Vector2i(480, 130)), 0.0, "and none past its radius")
    Fixtures.teardown(surface, machine)


## Past the edge, a disc that reaches in paints what it reaches, and one whose
## rim ends on the edge line covers no texel and paints none.
func test_a_stroke_past_the_edge_paints_what_its_disc_reaches() -> void:
    var surface := Fixtures.make_surface(CANVAS)
    var machine := Fixtures.make_bound_machine(surface)
    var layer := surface.easel.document.active_layer
    var brush := _brush(machine)

    _stroke(surface, brush, Vector2(60, 320), Vector2(120, 320))
    _stroke(surface, brush, Vector2(300, 330), Vector2(360, 330))

    assert_true(_alpha(layer, Vector2i(90, 299)) > 0.99, "A disc centred 20 past the edge paints the last row")
    assert_true(_alpha(layer, Vector2i(90, 295)) > 0.99, "and the rows it reaches, five in")
    assert_eq(_alpha(layer, Vector2i(90, 288)), 0.0, "and none past them")
    assert_eq(_alpha(layer, Vector2i(330, 299)), 0.0, "A disc whose rim ends on the edge line paints no texel")
    Fixtures.teardown(surface, machine)
