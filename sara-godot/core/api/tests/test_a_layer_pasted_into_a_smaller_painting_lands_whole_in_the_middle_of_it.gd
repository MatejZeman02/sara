## A layer copied out of a larger painting and pasted into a
## smaller one lands whole in the middle of it, as Photoshop places it, rather
## than at its old coordinates cut by the smaller canvas.
##
## Every painted texel is a colour of its own, red across and green down, so a
## paste one texel off reads wrong rather than plausibly right. Both documents
## are sRGB, so nothing is converted and a texel is compared with the one it
## was copied from.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## A painter's photo was a 518 by 1000 document.
const LARGE := Vector2i(1000, 1000)
const SMALL := Vector2i(518, 1000)

## Half precision on both sides of a copy that moves texels and never mixes
## them, so this is the rounding of the gradient's own value.
const EXACT := 1.0e-3

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


func _document(size: Vector2i) -> SaDocument:
    var surface := Fixtures.make_surface(size)
    surface.easel.document.reset_to_default(size, SaColorSpace.srgb())
    _surfaces.append(surface)
    return surface.easel.document


## The colour painted at *at* of a canvas *size* across.
static func _painted(at: Vector2i, size: Vector2i) -> Color:
    return Color(float(at.x) / size.x, float(at.y) / size.y, 0.35, 1.0)


## The active layer of *document* painted edge to edge, every texel its own,
## and nothing past the canvas, where a fill's whole chunks reach and a whole
## layer copy takes them.
func _paint(document: SaDocument) -> void:
    var layer := document.active_layer
    layer.fill(Color(0.0, 0.0, 0.0, 1.0))
    var rd := GlobalShaderCompiler.get_rd()
    var half := document.color_space.depth == SaColorSpace.Depth.F16
    for grid_pos: Vector2i in layer.chunks:
        var side := (layer.chunks[grid_pos] as SaChunk).pixel_size()
        var picture := Image.create_empty(side, side, false, Image.FORMAT_RGBAF)
        for y in side:
            for x in side:
                var at := grid_pos * side + Vector2i(x, y)
                var inside := Rect2i(Vector2i.ZERO, document.canvas_size).has_point(at)
                picture.set_pixel(x, y, _painted(at, document.canvas_size) if inside else Color(0.0, 0.0, 0.0, 0.0))
        picture.convert(Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
        rd.texture_update(layer.get_field(grid_pos).rid, 0, picture.get_data())


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


func _assert_texel(layer: SaLayer, at: Vector2i, want: Color, what: String) -> void:
    var got := _texel(layer, at)
    var off := 0.0
    for i in 4:
        off = maxf(off, absf(got[i] - want[i]))
    assert_true(off <= EXACT, "%s: %s at %s, wanted %s" % [what, got, at, want])


func _assert_empty(layer: SaLayer, at: Vector2i, what: String) -> void:
    assert_almost_eq(_texel(layer, at).a, 0.0, 1.0e-6, "%s: nothing at %s" % [what, at])


## A painter's case: the whole of a 1000 by 1000 layer into a 518 by 1000
## document. Centred, its painted bounds start 241 pixels left of the canvas,
## (518 - 1000) / 2, and every texel of the source is on the layer, the part
## past both edges included.
func test_a_whole_layer_pasted_into_a_narrower_painting_is_centred_and_whole() -> void:
    var source := _document(LARGE)
    _paint(source)
    assert_true(_clipboard.copy(source, source.active_layer) > 0, "The whole layer is copied")
    var target := _document(SMALL)
    var layer := _clipboard.paste(target)
    assert_not_null(layer, "The paste makes a layer")
    if layer == null:
        return
    var shift := Vector2i(-241, 0)
    assert_eq(_clipboard.offset_in(target), shift, "The copy moves to the canvas's middle")
    var corners: Array[Vector2i] = [Vector2i(0, 0), Vector2i(999, 0), Vector2i(0, 999), Vector2i(999, 999), Vector2i(500, 500)]
    for at: Vector2i in corners:
        _assert_texel(layer, at + shift, _painted(at, LARGE), "Source texel %s" % at)
    # Every 37th texel of the source, across every chunk the shift re-tiled.
    for y in range(0, LARGE.y, 37):
        for x in range(0, LARGE.x, 37):
            var at := Vector2i(x, y)
            var got := _texel(layer, at + shift)
            var want := _painted(at, LARGE)
            if absf(got.r - want.r) > EXACT or absf(got.g - want.g) > EXACT or absf(got.a - 1.0) > EXACT:
                assert_true(false, "Source texel %s landed as %s" % [at, got])
                return
    # The painted bounds, read at their edges, are the canvas's middle.
    _assert_empty(layer, Vector2i(-242, 500), "Left of the painted bounds")
    _assert_empty(layer, Vector2i(759, 500), "Right of the painted bounds")
    _assert_empty(layer, Vector2i(259, 1000), "Below the painted bounds")
    var middle := Vector2(Vector2i(-241, 0)) + Vector2(LARGE) / 2.0
    assert_eq(middle, Vector2(SMALL) / 2.0, "The painted bounds' middle is the canvas's")


## A 100 by 100 selection pasted into a larger document lands centred, and
## pasted into its own document lands where it was.
func test_a_selection_pasted_into_a_larger_painting_is_centred_and_into_its_own_in_place() -> void:
    var source := _document(Vector2i(512, 512))
    _paint(source)
    var region := Rect2i(50, 60, 100, 100)
    source.selection.select_rect(region)
    assert_true(_clipboard.copy(source, source.active_layer) > 0, "The selection is copied")
    var target := _document(Vector2i(1024, 1024))
    var layer := _clipboard.paste(target)
    assert_not_null(layer, "The paste makes a layer in the larger document")
    if layer == null:
        return
    var at := Vector2i(462, 462)
    _assert_texel(layer, at, _painted(region.position, source.canvas_size), "The copy's corner is centred")
    _assert_texel(layer, at + Vector2i(99, 99), _painted(region.end - Vector2i.ONE, source.canvas_size), "and its far corner")
    _assert_empty(layer, at - Vector2i(1, 0), "Left of the centred copy")
    _assert_empty(layer, region.position, "Where the copy was in its own document")

    var own := _clipboard.paste(source)
    assert_not_null(own, "The paste makes a layer in its own document")
    if own == null:
        return
    assert_eq(_clipboard.offset_in(source), Vector2i.ZERO, "and does not move it")
    _assert_texel(own, region.position, _painted(region.position, source.canvas_size), "In place in its own document")
    _assert_texel(own, region.end - Vector2i.ONE, _painted(region.end - Vector2i.ONE, source.canvas_size), "to its far corner")
    _assert_empty(own, region.position - Vector2i(1, 1), "and nothing outside it")


## The two other answers the fit choice gives a copy larger than the canvas:
## scaled inside it with its ratio kept, and the canvas grown to hold it, which
## one undo takes back with the layer.
func test_a_copy_larger_than_the_canvas_fits_inside_or_grows_the_canvas() -> void:
    var source := _document(LARGE)
    _paint(source)
    _clipboard.copy(source, source.active_layer)
    var target := _document(SMALL)
    assert_true(_clipboard.overhangs(target), "A 1000 pixel copy overhangs a 518 pixel canvas")
    assert_false(_clipboard.overhangs(source), "and not its own canvas")

    var inside := _clipboard.paste(target, "Inside", SaImageImport.Fit.INSIDE)
    assert_not_null(inside, "Fit inside makes a layer")
    if inside != null:
        # 1000 scaled to 518, so the square sits 241 down the 1000 high canvas.
        var middle := _texel(inside, Vector2i(259, 500))
        assert_almost_eq(middle.r, 0.5, 0.01, "The middle of the copy is the canvas's middle")
        assert_almost_eq(middle.g, 0.5, 0.01, "down as well as across")
        _assert_empty(inside, Vector2i(259, 230), "Above the fitted square")
        _assert_empty(inside, Vector2i(-1, 500), "Left of the canvas")

    var layers_before := target.get_child_count()
    var grown := _clipboard.paste(target, "Grown", SaImageImport.Fit.GROW)
    assert_not_null(grown, "Grow the canvas makes a layer")
    if grown == null:
        return
    assert_eq(target.canvas_size, LARGE, "The canvas grew to hold the copy")
    _assert_texel(grown, Vector2i(0, 0), _painted(Vector2i(0, 0), LARGE), "The copy fills the grown canvas")
    _assert_texel(grown, Vector2i(999, 999), _painted(Vector2i(999, 999), LARGE), "to its far corner")
    assert_true(target.undo(), "One undo")
    assert_eq(target.canvas_size, SMALL, "puts the canvas back")
    assert_eq(target.get_child_count(), layers_before, "and takes the layer away with it")
