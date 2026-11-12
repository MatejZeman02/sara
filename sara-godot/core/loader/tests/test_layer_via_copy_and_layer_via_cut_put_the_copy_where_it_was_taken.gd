## Layer via Copy and Layer via
## Cut put the copy exactly where it was taken, every texel at its own
## coordinates, whatever the selection's bounds. A selection crossing an edge of
## the canvas centres the copy, Paste's rule for a copy from another
## painting, and Paste keeps that rule.
##
## Every painted texel is a colour of its own, red across and green down, so a
## copy one texel off reads wrong rather than plausibly right. The canvas is no
## whole number of chunks, so a selection past its right or bottom edge still
## lies over chunks the layer holds.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(600, 400)

## Half precision moves texels and never mixes them, so this is the rounding
## of the gradient's own value.
const EXACT := 1.0e-3

## One region crossing each edge of the canvas in turn, and one inside it.
const REGIONS := {
    "left": Rect2i(-40, 120, 130, 90),
    "right": Rect2i(530, 150, 140, 80),
    "top": Rect2i(200, -50, 110, 120),
    "bottom": Rect2i(300, 340, 150, 120),
    "inside": Rect2i(210, 130, 170, 110),
}

var _surfaces: Array[SaSurface] = []
var _registries: SaRegistries = null
var _doc: SaDocument = null
var _source: SaLayer = null


func before_each() -> void:
    var surface := Fixtures.make_surface(SIZE)
    _surfaces.append(surface)
    _registries = Fixtures.make_registries(surface)
    _doc = surface.easel.document
    _source = _doc.active_layer
    _paint(_doc)


func after_each() -> void:
    for surface: SaSurface in _surfaces:
        if surface != null and surface.easel != null and is_instance_valid(surface.easel):
            Fixtures.teardown(surface)
    _surfaces.clear()
    _registries = null
    _doc = null
    _source = null


## The colour painted at *at*.
static func _painted(at: Vector2i) -> Color:
    return Color(float(at.x) / SIZE.x, float(at.y) / SIZE.y, 0.35, 1.0)


## The active layer of *document* painted edge to edge, every texel its own.
func _paint(document: SaDocument) -> void:
    var layer := document.active_layer
    layer.fill(Color(0.0, 0.0, 0.0, 1.0))
    var rd := GlobalShaderCompiler.get_rd()
    var half := document.color_space.depth == SaColorSpace.Depth.F16
    for grid_pos: Vector2i in layer.chunks:
        var texture := layer.get_field(grid_pos)
        var side := (layer.chunks[grid_pos] as SaChunk).pixel_size()
        var picture := Image.create_empty(side, side, false, Image.FORMAT_RGBAF)
        for y in side:
            for x in side:
                picture.set_pixel(x, y, _painted(grid_pos * side + Vector2i(x, y)))
        picture.convert(Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
        rd.texture_update(texture.rid, 0, picture.get_data())


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


static func _off(got: Color, want: Color) -> float:
    var off := 0.0
    for i in 4:
        off = maxf(off, absf(got[i] - want[i]))
    return off


## The texels of *region* on the canvas, every 7th and the corners, each read
## from *layer* against what the source held there.
func _wrong_in(layer: SaLayer, region: Rect2i, taken: bool) -> Array[String]:
    var on_canvas := region.intersection(Rect2i(Vector2i.ZERO, SIZE))
    var wrong: Array[String] = []
    var xs: Array[int] = []
    for x in range(on_canvas.position.x, on_canvas.end.x, 7):
        xs.append(x)
    xs.append(on_canvas.end.x - 1)
    var ys: Array[int] = []
    for y in range(on_canvas.position.y, on_canvas.end.y, 7):
        ys.append(y)
    ys.append(on_canvas.end.y - 1)
    for y: int in ys:
        for x: int in xs:
            var at := Vector2i(x, y)
            var got := _texel(layer, at)
            var want := _painted(at) if taken else Color(0.0, 0.0, 0.0, 0.0)
            if (taken and _off(got, want) > EXACT) or (not taken and got.a > EXACT):
                wrong.append("%s: %s" % [at, got])
    return wrong


## The texels just outside *region* on the canvas, which the new layer must
## leave empty.
func _spilled(layer: SaLayer, region: Rect2i) -> Array[String]:
    var spilled: Array[String] = []
    var middle := region.get_center()
    var around: Array[Vector2i] = [
        Vector2i(region.position.x - 1, middle.y),
        Vector2i(region.end.x, middle.y),
        Vector2i(middle.x, region.position.y - 1),
        Vector2i(middle.x, region.end.y),
    ]
    for at: Vector2i in around:
        if Rect2i(Vector2i.ZERO, SIZE).has_point(at) and _texel(layer, at).a > EXACT:
            spilled.append(str(at))
    return spilled


## Runs *command* over *region* of *source* and answers the layer it made.
func _lift(command: StringName, region: Rect2i, source: SaLayer) -> SaLayer:
    _doc.set_active_layer(source)
    _doc.selection.select_rect(region)
    var before := SaLayerOps.new(_doc).layers()
    _registries.commands.execute(command)
    for layer: SaLayer in SaLayerOps.new(_doc).layers():
        if not before.has(layer):
            return layer
    return null


func _held_in_place(command: StringName, name: String) -> void:
    var region: Rect2i = REGIONS[name]
    var source := _source
    var made := _lift(command, region, source)
    assert_not_null(made, "%s over the %s region makes a layer" % [command, name])
    if made == null:
        return
    var wrong := _wrong_in(made, region, true)
    assert_true(wrong.is_empty(), "%s, %s: texels not where they were taken, %s" % [command, name, wrong.slice(0, 4)])
    var spilled := _spilled(made, region)
    assert_true(spilled.is_empty(), "%s, %s: paint outside the region at %s" % [command, name, spilled])
    if command == &"layer_via_cut":
        var left := _wrong_in(source, region, false)
        assert_true(left.is_empty(), "Layer via Cut, %s: the source still holds %s" % [name, left.slice(0, 4)])


func test_layer_via_copy_keeps_every_texel_in_place_across_each_edge_and_inside() -> void:
    for name: String in REGIONS:
        _held_in_place(&"layer_via_copy", name)


func test_layer_via_cut_keeps_every_texel_in_place_across_each_edge_and_inside() -> void:
    for name: String in REGIONS:
        _held_in_place(&"layer_via_cut", name)


## the rule stands for Paste: the same region crossing the bottom edge,
## copied and pasted into a document of another size, is centred.
func test_paste_into_a_document_of_another_size_still_centres() -> void:
    var region: Rect2i = REGIONS["bottom"]
    _doc.selection.select_rect(region)
    var clipboard := SaClipboard.new()
    assert_true(clipboard.copy(_doc, _doc.active_layer) > 0, "The region is copied")
    var other_surface := Fixtures.make_surface(Vector2i(800, 500))
    _surfaces.append(other_surface)
    var other := other_surface.easel.document
    var shift := SaCrop.offset_for(clipboard.bounds.size, other.canvas_size, Vector2i(1, 1)) - clipboard.bounds.position
    assert_true(shift != Vector2i.ZERO, "The centring moves the copy")
    assert_eq(clipboard.offset_in(other), shift, "Paste into another size centres the copy")
    var pasted := clipboard.paste(other)
    assert_not_null(pasted, "The paste makes a layer")
    if pasted == null:
        return
    var at := Vector2i(region.position.x + 20, region.position.y + 20)
    assert_true(_off(_texel(pasted, at + shift), _painted(at)) <= EXACT, "A texel of the copy lands centred")
