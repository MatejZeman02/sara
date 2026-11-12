## Select All means everything on the layer, not the rectangle
## of the canvas. While the selection is the one Select All made and nothing has
## changed it since, Layer via Copy duplicates the layer, and Copy and Cut take
## its whole painted bounds, the paint past the canvas edge included. Any other
## selection clips to itself as before.
##
## The layer reaches 200 pixels past the right edge and the top of a 512 by 512
## canvas, every texel a colour of its own, so a copy cut at the edge or laid
## one texel off reads wrong rather than plausibly right. Chunks are compared
## byte for byte with the source's.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const CANVAS := Vector2i(512, 512)

## What the layer holds: the canvas and 200 pixels past its right edge and top.
const PAINTED := Rect2i(0, -200, 712, 712)

## Points inside the canvas and past its edges, all painted.
const POINTS: Array[Vector2i] = [Vector2i(711, -200), Vector2i(600, 100), Vector2i(100, -150), Vector2i(5, 5)]

var _surfaces: Array[SaSurface] = []
var _registries: SaRegistries = null
var _doc: SaDocument = null
var _source: SaLayer = null


func before_each() -> void:
    var surface := Fixtures.make_surface(CANVAS)
    surface.easel.document.reset_to_default(CANVAS, SaColorSpace.srgb())
    _surfaces.append(surface)
    _registries = Fixtures.make_registries(surface)
    _doc = surface.easel.document
    _source = _doc.active_layer
    _paint(_source)


func after_each() -> void:
    for surface: SaSurface in _surfaces:
        if surface != null and surface.easel != null and is_instance_valid(surface.easel):
            Fixtures.teardown(surface)
    _surfaces.clear()
    _registries = null
    _doc = null
    _source = null


## The colour painted at *at*, its own for every texel inside `PAINTED`, and
## nothing outside it.
static func _painted(at: Vector2i) -> Color:
    if not PAINTED.has_point(at):
        return Color(0.0, 0.0, 0.0, 0.0)
    return Color(float(at.x + 200) / 1024.0, float(at.y + 256) / 1024.0, 0.35, 1.0)


## *layer* painted over `PAINTED`, past the edge too.
func _paint(layer: SaLayer) -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var half := _doc.color_space.depth == SaColorSpace.Depth.F16
    for grid_pos: Vector2i in SaChunkWalk.positions_in(PAINTED):
        var chunk := layer.get_or_create_chunk(grid_pos)
        var side := chunk.pixel_size()
        var picture := Image.create_empty(side, side, false, Image.FORMAT_RGBAF)
        for y in side:
            for x in side:
                picture.set_pixel(x, y, _painted(grid_pos * side + Vector2i(x, y)))
        picture.convert(Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
        rd.texture_update(layer.get_field(grid_pos).rid, 0, picture.get_data())


## Every chunk's colour bytes, by grid position.
static func _bytes(layer: SaLayer) -> Dictionary:
    var found := {}
    for grid_pos: Vector2i in layer.chunks:
        found[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(layer.get_field(grid_pos).rid, 0)
    return found


## The texel of *layer* at document pixel *at*, transparent where no chunk is.
static func _texel(layer: SaLayer, at: Vector2i) -> Color:
    var side := SaChunk.SIZE
    var grid_pos := Vector2i(floori(float(at.x) / side), floori(float(at.y) / side))
    var texture := layer.get_field(grid_pos)
    if texture == null:
        return Color(0.0, 0.0, 0.0, 0.0)
    var local := at - grid_pos * side
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * side + local.x)


## Runs *command* and answers the layer it made, or null.
func _made_by(command: StringName) -> SaLayer:
    var before := SaLayerOps.new(_doc).layers()
    _registries.commands.execute(command)
    for layer: SaLayer in SaLayerOps.new(_doc).layers():
        if not before.has(layer):
            return layer
    return null


func _assert_same(made: SaLayer, source: Dictionary, what: String) -> void:
    assert_not_null(made, "%s makes a layer" % what)
    if made == null:
        return
    assert_eq(made.chunks.size(), source.size(), "%s: every chunk of the source, %d" % [what, source.size()])
    var got := _bytes(made)
    for grid_pos: Vector2i in source:
        assert_true(got.has(grid_pos), "%s: the chunk at %s is on the new layer" % [what, grid_pos])
        if got.has(grid_pos):
            assert_true(got[grid_pos] == source[grid_pos], "%s: the chunk at %s holds the source's paint" % [what, grid_pos])
    for at: Vector2i in POINTS:
        assert_almost_eq(_texel(made, at).a, 1.0, 1.0e-3, "%s: painted at %s" % [what, at])


func _select_all() -> void:
    _registries.commands.execute(&"select_all")
    assert_true(_doc.selection.selects_everything(), "Select All marks its selection as everything")


func test_layer_via_copy_after_select_all_duplicates_the_whole_layer() -> void:
    var before := _bytes(_source)
    assert_eq(before.size(), 9, "The layer holds nine chunks, five of them past the canvas")
    _select_all()
    _assert_same(_made_by(&"layer_via_copy"), before, "Layer via Copy after Select All")
    assert_true(_doc.selection.active, "and the selection still stands")


func test_copy_then_paste_after_select_all_takes_the_paint_past_the_edge() -> void:
    var before := _bytes(_source)
    _select_all()
    var clipboard := SaClipboard.new()
    assert_eq(clipboard.copy(_doc, _source), 9, "Copy after Select All takes all nine chunks")
    assert_eq(clipboard.bounds, Rect2i(Vector2i.ZERO, CANVAS), "and its frame is the canvas it came from")
    _assert_same(clipboard.paste(_doc), before, "Copy then Paste after Select All")
    _assert_same(_source, before, "The source after Copy")


func test_cut_after_select_all_takes_the_paint_past_the_edge_and_leaves_none() -> void:
    var before := _bytes(_source)
    _select_all()
    var clipboard := SaClipboard.new()
    assert_true(clipboard.cut(_doc, _source), "Cut after Select All takes the layer")
    for at: Vector2i in POINTS:
        assert_almost_eq(_texel(_source, at).a, 0.0, 1.0e-6, "The cut leaves nothing at %s" % at)
    _assert_same(clipboard.paste(_doc), before, "Cut then Paste after Select All")


func test_select_all_with_a_rectangle_taken_off_still_clips_layer_via_copy() -> void:
    _select_all()
    var hole := Rect2i(100, 100, 50, 50)
    _doc.selection.change(SaSelection.RECT_TITLE, _doc.selection.select_rect.bind(hole, SaSelection.Mode.SUBTRACT))
    assert_false(_doc.selection.selects_everything(), "A subtract makes it a shape the painter drew")
    var made := _made_by(&"layer_via_copy")
    assert_not_null(made, "Layer via Copy makes a layer")
    if made == null:
        return
    assert_almost_eq(_texel(made, Vector2i(5, 5)).a, 1.0, 1.0e-3, "The selection comes over")
    assert_almost_eq(_texel(made, Vector2i(120, 120)).a, 0.0, 1.0e-6, "the hole does not")
    for at: Vector2i in [Vector2i(711, -200), Vector2i(600, 100), Vector2i(100, -150)]:
        assert_almost_eq(_texel(made, at).a, 0.0, 1.0e-6, "nor the paint past the edge, at %s" % at)


func test_the_mark_goes_with_any_change_and_comes_back_with_an_undo() -> void:
    _select_all()
    _doc.selection.change(SaSelection.RECT_TITLE, _doc.selection.select_rect.bind(Rect2i(0, 0, 40, 40), SaSelection.Mode.ADD))
    assert_false(_doc.selection.selects_everything(), "An add lets the mark go")
    assert_true(_doc.undo(), "The add undoes")
    assert_true(_doc.selection.selects_everything(), "and the undo puts Select All's selection back, mark and all")
    assert_true(_doc.redo(), "The add redoes")
    assert_false(_doc.selection.selects_everything(), "and the mark goes again")
    _doc.selection.change(SaSelection.RECT_TITLE, _doc.selection.select_rect.bind(Rect2i(0, 0, 40, 40)))
    assert_false(_doc.selection.selects_everything(), "A marquee drawn over it is a shape")
    _select_all()
    _doc.selection.deselect()
    assert_false(_doc.selection.selects_everything(), "Nothing selected is not Select All's selection")
