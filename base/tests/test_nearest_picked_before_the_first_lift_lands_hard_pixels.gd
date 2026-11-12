## Nearest chosen on the transform's Filter row before anything is lifted
## lands hard pixels, both on the first lift a tool makes and on the first
## after a Select > Transform Selection has ended. Either lift builds a fresh
## pass, and a pass that did not read the row resampled bilinear while the row
## read Nearest.
##
## The picture is one-pixel columns of red and blue. Scaled by 1.5 through the
## Scale X row, a bilinear landing mixes neighbouring columns, and a nearest
## one copies each texel from a single column, so no landed texel holds both.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")

const CANVAS := Vector2i(256, 256)
const STRIPES := Rect2i(64, 64, 64, 64)
const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)

var _surface: SaSurface
var _machine: ToolMachine


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## A fresh tool on a document whose active layer holds the stripes, the stripes
## selected and the Filter row at Nearest before any pass exists.
func _open() -> ToolState:
    _surface = Fixtures.make_surface(CANVAS)
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"transform")
    var doc := _surface.get_document()
    var layer := doc.active_layer
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    var texture := chunk.albedo()
    var edge := chunk.pixel_size()
    var image := Image.create_empty(edge, edge, false, _image_format(texture))
    for y in range(STRIPES.position.y, STRIPES.end.y):
        for x in range(STRIPES.position.x, STRIPES.end.x):
            image.set_pixel(x, y, RED if x % 2 == 0 else BLUE)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    layer.mark_unresolved(Vector2i.ZERO)
    doc.invalidate_chunks(layer.chunks.keys())
    doc.selection.select_rect(STRIPES)
    var tool: ToolState = _machine.active_tool
    tool.set("filter_mode", SaResampleKernel.Filter.NEAREST)
    return tool


## How many texels of the active layer hold red and blue at once.
func _mixed() -> int:
    var layer := _surface.get_document().active_layer
    var mixed := 0
    for grid_pos: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid_pos]
        var texture := chunk.albedo()
        var edge := chunk.pixel_size()
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var texels := Image.create_from_data(edge, edge, false, _image_format(texture), bytes)
        for y in edge:
            for x in edge:
                var texel := texels.get_pixel(x, y)
                if texel.r > 0.02 and texel.b > 0.02:
                    mixed += 1
    return mixed


## Scales the selection by 1.5 through the row and writes it down, as Enter.
func _scale_and_land(tool: ToolState) -> void:
    tool.set("scale_x", 1.5)
    assert_true(tool.is_moving(), "The Scale X row lifts the selection")
    assert_true(tool.call("commit_move"), "and Apply lands it")


func test_the_first_lift_of_a_fresh_tool_lands_hard_pixels() -> void:
    var tool := _open()

    _scale_and_land(tool)

    assert_eq(_mixed(), 0, "No landed texel holds both colours, because the first pass read Nearest off the row")


func test_the_first_lift_after_a_transform_selection_lands_hard_pixels() -> void:
    var tool := _open()
    assert_true(tool.call("transform_selection"), "Select > Transform Selection opens on the selection")
    tool.call("cancel_move")
    assert_false(tool.is_moving(), "with nothing left in the air")

    _scale_and_land(tool)

    assert_eq(_mixed(), 0, "No landed texel holds both colours, because the pass built after it read Nearest too")
