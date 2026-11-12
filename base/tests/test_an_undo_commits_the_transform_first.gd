## The transform's session is built like the liquify's, a lift that holds the
## layer's chunks as they were until Enter. An undo with a move in the air must
## not take back the stroke under it and leave the moved picture standing, so
## the hook that closes a liquify session commits the move as well.
##
## A stroke is one history step, the transform moves it, and the undo has to
## take back the move and leave the stroke where it was painted.
extends "res://tests/test_framework.gd"

## Chunks are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)
## Inside the stroke, and inside where the move takes it but not the stroke.
const PAINTED := Vector2i(50, 50)
const MOVED_TO := Vector2i(300, 50)

var _surface: SaSurface = null
var _machine: ToolMachine = null


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func _texel(layer: SaLayer, at: Vector2i) -> Color:
    var grid := Vector2i(floori(float(at.x) / SaChunk.SIZE), floori(float(at.y) / SaChunk.SIZE))
    var texture := layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local := at - grid * SaChunk.SIZE
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * texture.size.x + local.x)


## A new layer whose first chunk is painted red as one history step, and the
## machine on the transform with the move in the air.
func _stroke_then_move() -> SaLayer:
    _surface = Fixtures.make_surface(Vector2i(1024, 512))
    _machine = Fixtures.make_bound_machine(_surface)
    var doc := _surface.get_document()
    var layer := SaLayerOps.new(doc).add(&"", null, 1.0)
    doc.active_layer = layer
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    chunk.clear(Color.TRANSPARENT)
    var state := {Vector2i.ZERO: SaChunkDelta.capture(chunk, Rect2i(0, 0, SaChunk.SIZE, SaChunk.SIZE))}
    chunk.clear(RED)
    layer.mark_unresolved(Vector2i.ZERO)
    doc.record_pixel_step("Paint", layer, state)
    _machine.set_active_tool(&"transform")
    _machine.active_tool.set(&"move_x", 250.0)
    return layer


func test_an_undo_with_a_move_in_the_air_takes_back_the_move_and_not_the_stroke() -> void:
    var layer := _stroke_then_move()
    var doc := _surface.get_document()
    var stroke_step := doc.undo_redo.get_current_action()
    assert_true(_machine.active_tool.call(&"is_moving"), "The move is in the air")

    assert_true(_machine.close_session(), "The hook commits the move")
    assert_true(doc.undo(), "and the undo has a step to take")
    assert_eq(doc.undo_redo.get_current_action(), stroke_step, "which leaves the stack on the stroke")
    assert_almost_eq(_texel(layer, PAINTED).a, 1.0, 1e-4, "with the stroke where it was painted")
    assert_almost_eq(_texel(layer, MOVED_TO).a, 0.0, 1e-4, "and nothing where the move had taken it")
    assert_false(_machine.active_tool.call(&"is_moving"), "No move is left in the air")


func test_the_undo_history_row_of_the_stroke_takes_back_the_move() -> void:
    var layer := _stroke_then_move()
    var doc := _surface.get_document()
    var stroke_step := doc.undo_redo.get_current_action()
    assert_eq(UndoDocker.walk(doc, _machine, stroke_step), -1, "A press on the stroke's row goes back one step, the move's")
    assert_almost_eq(_texel(layer, PAINTED).a, 1.0, 1e-4, "and leaves the stroke where it was painted")
    assert_almost_eq(_texel(layer, MOVED_TO).a, 0.0, 1e-4, "and nothing where the move had taken it")
