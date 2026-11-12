## The Edit menu's Undo is lit
## over an open liquify or transform session.
##
## The chord, the row and the docker commit an open session
## before the history moves, so the row asks the history and the tool machine
## whether there is a step. On a document whose only change is a push or a move
## left open, the row must not stand dimmed and take no press.
##
## Every document here is fresh, with paint laid outside the history, so the
## open session is the only change there is and nothing else could light the row.
extends "res://tests/test_framework.gd"

## Chunks are real textures, and the menus act on a document, so this needs a
## RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const CANVAS := Vector2i(512, 256)
const RED := Color(0.9, 0.1, 0.1, 1.0)
## A stripe across the first chunk, which the liquify pushes right.
const STRIPE := Vector2i(100, 140)
const ROW: int = 128
## Inside the stripe, and inside where the transform's move takes it but not
## the stripe.
const PAINTED := Vector2i(120, ROW)
const MOVED_TO := Vector2i(370, ROW)

var _surface: SaSurface = null
var _machine: ToolMachine = null
## The bar, the canvas and the shortcut table behind it, freed after each.
var _bar: TopMenuBar = null
var _canvas: SaCanvas = null
var _table: SaShortcutCommands = null


func after_each() -> void:
    if _bar != null:
        _bar.free()
    _bar = null
    if _canvas != null:
        _canvas.easel = null
        _canvas.free()
    _canvas = null
    _table = null
    if _surface != null:
        Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## A fresh document whose active layer holds the red stripe and no step, a
## machine bound to it, and a menu bar bound the way main binds it: the shortcut
## table's Undo and Redo on the canvas's document, asking that machine.
func _open() -> SaLayer:
    _surface = Fixtures.make_surface(CANVAS)
    _machine = Fixtures.make_bound_machine(_surface)
    var doc := _surface.get_document()
    var layer := SaLayerOps.new(doc).add(&"", null, 1.0)
    doc.active_layer = layer
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    var texture := chunk.albedo()
    var image := Image.create_empty(SaChunk.SIZE, SaChunk.SIZE, false, _image_format(texture))
    image.fill_rect(Rect2i(STRIPE.x, 0, STRIPE.y - STRIPE.x, SaChunk.SIZE), RED)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    layer.mark_unresolved(Vector2i.ZERO)
    doc.invalidate_chunks(layer.chunks.keys())
    doc.undo_redo.clear_history()

    _canvas = SaCanvas.new()
    _canvas.easel = _surface.easel
    var registries := Fixtures.make_registries(_surface)
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    _table = SaShortcutCommands.new(func() -> ToolMachine: return _machine, func() -> SaCanvas: return _canvas, Callable(), null)
    _table.register_into(registries.commands)
    _bar = TopMenuBar.new()
    _bar._ready()
    _bar.bind_commands(registries.commands)
    return layer


## The Edit menu opened afresh, the way a press on its title opens it.
func _edit() -> SaMenu:
    var menu := _bar.menu("Edit")
    menu.populate()
    return menu


func _lit(menu: SaMenu, id: int) -> bool:
    return not menu.popup.is_disabled(SaMenu.key(id))


## The whole layer, one colour a texel of every chunk the canvas spans, a chunk
## with no texture read as transparent, so paint a session moved into a chunk
## of its own is in the picture too.
func _picture(layer: SaLayer) -> Array:
    var out: Array = []
    for gy in ceili(float(CANVAS.y) / SaChunk.SIZE):
        for gx in ceili(float(CANVAS.x) / SaChunk.SIZE):
            var texture := layer.get_field(Vector2i(gx, gy))
            if texture == null:
                for i in SaChunk.SIZE * SaChunk.SIZE:
                    out.append(Color(0, 0, 0, 0))
                continue
            var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
            var texels := Image.create_from_data(SaChunk.SIZE, SaChunk.SIZE, false, _image_format(texture), bytes)
            for y in SaChunk.SIZE:
                for x in SaChunk.SIZE:
                    out.append(texels.get_pixel(x, y))
    return out


## The largest difference between two pictures of the layer.
static func _farthest(a: Array, b: Array) -> float:
    if a.size() != b.size():
        return INF
    var most := 0.0
    for i in a.size():
        var gap: Color = a[i] - b[i]
        most = maxf(most, maxf(maxf(absf(gap.r), absf(gap.g)), maxf(absf(gap.b), absf(gap.a))))
    return most


func _alpha_at(layer: SaLayer, at: Vector2i) -> float:
    var grid := Vector2i(floori(float(at.x) / SaChunk.SIZE), floori(float(at.y) / SaChunk.SIZE))
    var texture := layer.get_field(grid)
    if texture == null:
        return 0.0
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local := at - grid * SaChunk.SIZE
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * texture.size.x + local.x).a


func test_a_fresh_document_with_no_session_dims_undo() -> void:
    _open()
    var doc := _surface.get_document()
    _machine.set_active_tool(&"liquify")
    assert_false(doc.undo_redo.has_undo(), "A fresh document has no history")
    assert_false(_machine.holds_session(), "and the liquify picked holds no session yet")
    var edit := _edit()
    assert_false(_lit(edit, SaEditMenu.ID_UNDO), "so Undo is dimmed")
    assert_false(_lit(edit, SaEditMenu.ID_REDO), "and Redo with it")
    assert_false(edit.popup.press_row(SaMenu.key(SaEditMenu.ID_UNDO)), "and the dimmed row takes no press")


func test_a_liquify_push_left_open_lights_undo_and_the_press_takes_it_back() -> void:
    var layer := _open()
    var doc := _surface.get_document()
    var before := _picture(layer)
    _machine.set_active_tool(&"liquify")
    _machine.active_tool.settings.set(&"strength", 1.0)
    var tool: ToolState = _machine.active_tool
    tool.call(&"press", Vector2(STRIPE.y - 10, ROW))
    tool.call(&"drag_to", Vector2(STRIPE.y + 30, ROW))
    tool.call(&"release")
    assert_true(_farthest(_picture(layer), before) > 0.5, "The push moved the stripe")
    assert_false(doc.undo_redo.has_undo(), "and the history holds nothing yet, the session is open")
    assert_true(_machine.holds_session(), "The machine says it holds a session")

    var edit := _edit()
    assert_true(_lit(edit, SaEditMenu.ID_UNDO), "Undo is lit over the open session")
    assert_false(_lit(edit, SaEditMenu.ID_REDO), "Redo is not: writing the session would clear the redo list")
    assert_true(edit.popup.press_row(SaMenu.key(SaEditMenu.ID_UNDO)), "The row takes the press")
    assert_almost_eq(_farthest(_picture(layer), before), 0.0, 0.001, "and every chunk of the layer is as it was before the push")
    assert_true(doc.undo_redo.has_redo(), "with the push standing as a redo")
    assert_false(_machine.holds_session(), "and no session left open")
    edit = _edit()
    assert_false(_lit(edit, SaEditMenu.ID_UNDO), "Undo dims again, there is nothing under the push")
    assert_true(_lit(edit, SaEditMenu.ID_REDO), "and Redo is lit")


## A press that dabbed nothing opens a session with no originals, whose commit
## writes no step, so the row stays dimmed rather than lit for a press that
## would do nothing.
func test_a_liquify_press_that_moved_nothing_leaves_undo_dimmed() -> void:
    _open()
    _machine.set_active_tool(&"liquify")
    var tool: ToolState = _machine.active_tool
    tool.call(&"press", Vector2(400, ROW))
    tool.call(&"release")
    assert_false(_machine.holds_session(), "Nothing pushed, nothing held")
    assert_false(_lit(_edit(), SaEditMenu.ID_UNDO), "and Undo stays dimmed")


func test_a_transform_move_in_the_air_lights_undo_and_the_press_takes_it_back() -> void:
    var layer := _open()
    var doc := _surface.get_document()
    var before := _picture(layer)
    _machine.set_active_tool(&"transform")
    _machine.active_tool.set(&"move_x", 250.0)
    assert_true(_machine.active_tool.call(&"is_moving"), "The move is in the air")
    assert_false(doc.undo_redo.has_undo(), "and the history holds nothing yet")
    assert_true(_machine.holds_session(), "The machine says it holds a session")

    var edit := _edit()
    assert_true(_lit(edit, SaEditMenu.ID_UNDO), "Undo is lit over the move")
    assert_false(_lit(edit, SaEditMenu.ID_REDO), "Redo is not")
    assert_true(edit.popup.press_row(SaMenu.key(SaEditMenu.ID_UNDO)), "The row takes the press")
    assert_almost_eq(_farthest(_picture(layer), before), 0.0, 0.001, "and every chunk of the layer is as it was before the move")
    assert_almost_eq(_alpha_at(layer, PAINTED), 1.0, 1e-4, "with the stripe where it was painted")
    assert_almost_eq(_alpha_at(layer, MOVED_TO), 0.0, 1e-4, "with nothing where the move had taken it")
    assert_true(doc.undo_redo.has_redo(), "The move stands as a redo")
    assert_false(_machine.active_tool.call(&"is_moving"), "and nothing is left in the air")
    assert_true(_lit(_edit(), SaEditMenu.ID_REDO), "so Redo is lit")


## A lift whose map is back where it started is put down with no step, as the
## pass's commit says, so it lights nothing.
func test_a_lift_moved_back_to_where_it_was_leaves_undo_dimmed() -> void:
    _open()
    _machine.set_active_tool(&"transform")
    _machine.active_tool.set(&"move_x", 250.0)
    _machine.active_tool.set(&"move_x", 0.0)
    assert_true(_machine.active_tool.call(&"is_moving"), "The lift is still live")
    assert_false(_machine.holds_session(), "but it holds no move")
    assert_false(_lit(_edit(), SaEditMenu.ID_UNDO), "and Undo stays dimmed")
    _machine.active_tool.call(&"cancel_move")
