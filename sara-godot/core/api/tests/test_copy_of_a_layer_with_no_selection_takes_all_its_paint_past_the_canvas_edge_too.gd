## Copy and Cut of a layer with no selection take every chunk
## of it, the paint past the canvas edge included, and Paste puts it back at
## the same document place. With a selection both read the selection's bounds
## as before.
##
## The layer reaches 200 pixels past the right edge and the top of a 512 by
## 512 canvas, every texel a colour of its own, so a copy cut at the edge or
## laid one texel off reads wrong rather than plausibly right. A copy through
## the whole mask moves texels without mixing them, so the pasted chunks are
## compared byte for byte with the source's.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const CANVAS := Vector2i(512, 512)

## What the layer holds: the canvas and 200 pixels past its right edge and top.
const PAINTED := Rect2i(0, -200, 712, 712)

var _surfaces: Array[SaSurface] = []
var _clipboard: SaClipboard = null


func before_each() -> void:
    _clipboard = SaClipboard.new()


func after_each() -> void:
    for surface: SaSurface in _surfaces:
        if surface != null and surface.easel != null and is_instance_valid(surface.easel):
            Fixtures.teardown(surface)
    _surfaces.clear()
    _clipboard = null


func _document() -> SaDocument:
    var surface := Fixtures.make_surface(CANVAS)
    surface.easel.document.reset_to_default(CANVAS, SaColorSpace.srgb())
    _surfaces.append(surface)
    return surface.easel.document


## The colour painted at *at*, its own for every texel inside `PAINTED`, and
## nothing outside it.
static func _painted(at: Vector2i) -> Color:
    if not PAINTED.has_point(at):
        return Color(0.0, 0.0, 0.0, 0.0)
    return Color(float(at.x + 200) / 1024.0, float(at.y + 256) / 1024.0, 0.35, 1.0)


## The active layer of *document* painted over `PAINTED`, past the edge too.
func _paint(document: SaDocument) -> void:
    var layer := document.active_layer
    var rd := GlobalShaderCompiler.get_rd()
    var half := document.color_space.depth == SaColorSpace.Depth.F16
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


func _assert_same(pasted: SaLayer, source: Dictionary, what: String) -> void:
    assert_eq(pasted.chunks.size(), source.size(), "%s: every chunk of the source, %d" % [what, source.size()])
    var got := _bytes(pasted)
    for grid_pos: Vector2i in source:
        assert_true(got.has(grid_pos), "%s: the chunk at %s is on the pasted layer" % [what, grid_pos])
        if got.has(grid_pos):
            assert_true(got[grid_pos] == source[grid_pos], "%s: the chunk at %s holds the source's paint" % [what, grid_pos])


func _assert_edge(pasted: SaLayer, what: String) -> void:
    var points: Array[Vector2i] = [Vector2i(711, -200), Vector2i(600, 100), Vector2i(100, -150), Vector2i(5, 5)]
    for at: Vector2i in points:
        var got := _texel(pasted, at)
        var want := _painted(at)
        var off := 0.0
        for i in 4:
            off = maxf(off, absf(got[i] - want[i]))
        assert_true(off <= 1.0e-3, "%s: %s at %s, wanted %s" % [what, got, at, want])
    assert_almost_eq(_texel(pasted, Vector2i(712, 0)).a, 0.0, 1.0e-6, "%s: nothing right of the paint" % what)
    assert_almost_eq(_texel(pasted, Vector2i(0, -201)).a, 0.0, 1.0e-6, "%s: nothing above it" % what)


func test_a_copy_with_no_selection_pastes_every_chunk_the_part_past_the_edge_included() -> void:
    var document := _document()
    _paint(document)
    var source := document.active_layer
    var before := _bytes(source)
    assert_eq(before.size(), 9, "The layer holds nine chunks, five of them past the canvas")

    assert_eq(_clipboard.copy(document, source), 9, "Copy takes all nine")
    assert_eq(_clipboard.bounds, Rect2i(Vector2i.ZERO, CANVAS), "and its frame is the canvas it came from")
    var pasted := _clipboard.paste(document)
    assert_not_null(pasted, "The paste makes a layer")
    if pasted == null:
        return
    _assert_same(pasted, before, "Copy and Paste")
    _assert_edge(pasted, "Copy and Paste")
    _assert_same(source, before, "The source after Copy")


func test_a_cut_with_no_selection_takes_every_chunk_and_leaves_none_of_the_paint() -> void:
    var document := _document()
    _paint(document)
    var source := document.active_layer
    var before := _bytes(source)

    assert_true(_clipboard.cut(document, source), "Cut takes the layer")
    for at: Vector2i in [Vector2i(711, -200), Vector2i(600, 100), Vector2i(100, -150), Vector2i(5, 5)]:
        assert_almost_eq(_texel(source, at).a, 0.0, 1.0e-6, "The cut leaves nothing at %s" % at)
    var pasted := _clipboard.paste(document)
    assert_not_null(pasted, "The paste makes a layer")
    if pasted == null:
        return
    _assert_same(pasted, before, "Cut and Paste")
    _assert_edge(pasted, "Cut and Paste")

    assert_true(document.undo(), "The paste undoes")
    assert_true(document.undo(), "and so does the cut")
    _assert_same(source, before, "The source after both are undone")


func test_with_a_selection_copy_and_cut_read_only_the_selections_bounds() -> void:
    var document := _document()
    _paint(document)
    var source := document.active_layer
    var region := Rect2i(300, 100, 150, 150)
    document.selection.select_rect(region)

    assert_true(_clipboard.copy(document, source) > 0, "Copy takes the selection")
    assert_eq(_clipboard.bounds, region, "over the selection's box")
    var pasted := _clipboard.paste(document)
    assert_not_null(pasted, "The paste makes a layer")
    if pasted == null:
        return
    var inside := _texel(pasted, Vector2i(320, 120))
    var want := _painted(Vector2i(320, 120))
    assert_almost_eq(inside.r, want.r, 1.0e-3, "Inside the selection the paste holds the source's red")
    assert_almost_eq(inside.g, want.g, 1.0e-3, "and green")
    assert_almost_eq(inside.a, 1.0, 1.0e-3, "and is opaque")
    for at: Vector2i in [Vector2i(299, 120), Vector2i(450, 120), Vector2i(600, 100), Vector2i(100, -150)]:
        assert_almost_eq(_texel(pasted, at).a, 0.0, 1.0e-6, "Nothing outside the selection, at %s" % at)

    assert_true(_clipboard.cut(document, source), "Cut takes the selection")
    assert_almost_eq(_texel(source, Vector2i(320, 120)).a, 0.0, 1.0e-6, "and clears it")
    for at: Vector2i in [Vector2i(299, 120), Vector2i(600, 100), Vector2i(100, -150)]:
        assert_almost_eq(_texel(source, at).a, 1.0, 1.0e-4, "and nothing else, at %s" % at)
