## A selection made of one-pixel strips selects every strip.
## A painter added thin rectangles together, the selection came out empty and
## the brush then painted the whole layer.
##
## Ten strips one pixel wide, five upright and five lying, two of them on the
## seam between chunks, are selected three ways: as rectangles added together,
## as polygons added together, and as a colour range over a layer that holds
## the strips in a colour of their own. Then an opaque layer is cleared under
## the selection and every texel of the canvas is read back from VRAM: the
## strips cleared and every other texel as it was.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Two by two chunks, so the strips cross both seams.
const SIZE := Vector2i(512, 512)
const GROUND := Color(0.2, 0.5, 0.9, 1.0)
const STRIPE := Color(0.9, 0.1, 0.1, 1.0)

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _doc: SaDocument = null
var _feather_was: float = 0.0


func before_each() -> void:
    _surface = Fixtures.make_surface(SIZE)
    _machine = Fixtures.make_bound_machine(_surface)
    _doc = _surface.get_document()
    _feather_was = SaSettings.selection_feather
    SaSettings.selection_feather = 0.0
    _doc.fill_layer(GROUND)


func after_each() -> void:
    SaSettings.selection_feather = _feather_was
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null


func test_strips_added_as_rectangles_select_every_strip() -> void:
    var first := true
    for strip: Rect2i in _strips():
        _doc.selection.select_rect(strip, SaSelection.Mode.REPLACE if first else SaSelection.Mode.ADD)
        first = false
    _clear_and_check("rectangles")


func test_strips_added_as_polygons_select_every_strip() -> void:
    var first := true
    for strip: Rect2i in _strips():
        _doc.selection.select_polygon(_corners(strip), SaSelection.Mode.REPLACE if first else SaSelection.Mode.ADD)
        first = false
    _clear_and_check("polygons")


func test_strips_added_as_anti_aliased_polygons_select_every_strip() -> void:
    var first := true
    for strip: Rect2i in _strips():
        _doc.selection.select_polygon(_corners(strip), SaSelection.Mode.REPLACE if first else SaSelection.Mode.ADD, true)
        first = false
    _clear_and_check("anti-aliased polygons")


func test_one_strip_alone_selects_its_pixels() -> void:
    for strip: Rect2i in _strips():
        _doc.selection.select_rect(strip)
        _clear_and_check("a rectangle alone at %s" % strip, [strip])
        _doc.fill_layer(GROUND)
        _doc.selection.select_polygon(_corners(strip))
        _clear_and_check("a polygon alone at %s" % strip, [strip])
        _doc.fill_layer(GROUND)


func test_strips_chosen_by_a_colour_range_select_every_strip() -> void:
    for strip: Rect2i in _strips():
        _doc.selection.select_rect(strip)
        _doc.fill_layer(STRIPE)
    _doc.selection.deselect()
    SaColorRange.new(_doc).select(STRIPE, 10.0, SaSelection.Mode.REPLACE, null, _doc.active_layer)
    _clear_and_check("a colour range")


## Ten strips one pixel across: five upright and five lying, one of each on
## a chunk seam's either side.
static func _strips() -> Array[Rect2i]:
    var out: Array[Rect2i] = []
    for x: int in [17, 101, 255, 256, 433]:
        out.append(Rect2i(x, 9, 1, 490))
    for y: int in [23, 140, 255, 256, 470]:
        out.append(Rect2i(30, y, 460, 1))
    return out


## Clears the layer under the selection, and reads every texel of *strips*
## cleared and every other texel still opaque.
func _clear_and_check(what: String, strips: Array[Rect2i] = _strips()) -> void:
    assert_true(_doc.selection.active, "%s: a selection is active" % what)
    _doc.clear_layer()
    var alpha := _alpha()
    var spilt := 0
    var missed := 0
    var first := ""
    for y in SIZE.y:
        for x in SIZE.x:
            var in_strip := false
            for strip: Rect2i in strips:
                if strip.has_point(Vector2i(x, y)):
                    in_strip = true
                    break
            var a := alpha[y * SIZE.x + x]
            if in_strip and a != 0.0:
                missed += 1
                if first.is_empty():
                    first = "(%d, %d) in a strip reads %.3f" % [x, y, a]
            elif not in_strip and a != 1.0:
                spilt += 1
                if first.is_empty():
                    first = "(%d, %d) outside every strip reads %.3f" % [x, y, a]
    assert_eq(missed, 0, "%s: every texel of every strip is cleared. %s" % [what, first])
    assert_eq(spilt, 0, "%s: no texel outside the strips is cleared. %s" % [what, first])


## The layer's alpha at every texel, row by row, each chunk read back once.
func _alpha() -> PackedFloat32Array:
    var out := PackedFloat32Array()
    out.resize(SIZE.x * SIZE.y)
    var layer := _doc.active_layer
    for grid_pos: Vector2i in layer.chunks:
        var texture := layer.get_field(grid_pos)
        var size := texture.size
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var origin := grid_pos * size
        var width: int = SaFieldSpec.BYTES_PER_TEXEL[texture.format]
        var wide := width == 16
        for y in mini(size.y, SIZE.y - origin.y):
            for x in mini(size.x, SIZE.x - origin.x):
                var at := (y * size.x + x) * width + (width >> 2) * 3
                out[(origin.y + y) * SIZE.x + origin.x + x] = bytes.decode_float(at) if wide else bytes.decode_half(at)
    return out


static func _corners(rect: Rect2i) -> PackedVector2Array:
    return PackedVector2Array(
        [Vector2(rect.position), Vector2(rect.end.x, rect.position.y), Vector2(rect.end), Vector2(rect.position.x, rect.end.y)]
    )
