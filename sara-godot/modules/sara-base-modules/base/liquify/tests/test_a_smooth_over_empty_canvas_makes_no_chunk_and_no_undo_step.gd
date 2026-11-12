## Liquify's Smooth makes a chunk only where it can carry paint into one, so a
## Smooth over empty canvas leaves the layer with no chunk and the history with
## no step. Smooth is a warp that straightens strokes, so the last case reads a
## wobbly stroke across the edge of a painted chunk straightened on both sides
## of it alike.
extends "res://tests/test_framework.gd"

## Chunks are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const SessionScript = preload("res://modules/sara-base-modules/base/liquify/sa_liquify_session.gd")
const StateScript = preload("res://modules/sara-base-modules/base/liquify/state_liquify.gd")

const CANVAS := Vector2i(1920, 1080)
const RED := Color(0.9, 0.1, 0.1, 1.0)
## The Smooth: size 160 at (400, 300), over two chunk positions.
const AT := Vector2(400.0, 300.0)
const SIZE: float = 160.0
## A frame of a held Smooth at full strength.
const FRAME: float = StateScript.SMOOTH_FLOW / 60.0
## The stroke across the seam: how far its path swings, over what period, its
## half width, and the brush that straightens it, whose flat core holds the
## columns read either side of the seam.
const SWING: float = 8.0
const PERIOD: float = 40.0
const HALF_WIDTH: float = 3.0
const SEAM_SIZE: float = 96.0
const READ_HALF: int = 20

var _surface: SaSurface = null
var _machine: ToolMachine = null


func after_each() -> void:
    if _surface != null:
        Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


func _open() -> SaLayer:
    _surface = Fixtures.make_surface(CANVAS)
    _machine = Fixtures.make_bound_machine(_surface)
    var doc := _surface.get_document()
    var layer := SaLayerOps.new(doc).add(&"", null, 1.0)
    doc.active_layer = layer
    return layer


## Paints chunk (0, 0) of *layer* opaque red whole.
func _paint_first_chunk(layer: SaLayer) -> void:
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    var edge := chunk.pixel_size()
    var texture := chunk.albedo()
    var image := Image.create_empty(edge, edge, false, _image_format(texture))
    image.fill(RED)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    layer.mark_unresolved(Vector2i.ZERO)
    _surface.get_document().invalidate_chunks([Vector2i.ZERO])


static func _read(chunk: SaChunk) -> Image:
    var texture := chunk.albedo()
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return Image.create_from_data(texture.size.x, texture.size.y, false, _image_format(texture), bytes)


func test_a_smooth_over_empty_canvas_makes_no_chunk() -> void:
    var layer := _open()
    var doc := _surface.get_document()
    var before := doc.history.position()
    var session: Variant = SessionScript.new(doc)
    assert_true(session.begin(layer), "A session opens")
    for frame in 30:
        session.smooth(AT, SIZE, 1.0, FRAME)
    assert_eq(layer.chunks.size(), 0, "No chunk is made under the brush")
    assert_false(session.commit(), "The commit has nothing to record")
    assert_eq(layer.chunks.size(), 0, "And the layer still holds none")
    assert_eq(doc.history.position(), before, "The history is where it was")


func test_a_smooth_over_empty_canvas_beside_paint_makes_no_chunk() -> void:
    var layer := _open()
    _paint_first_chunk(layer)
    var doc := _surface.get_document()
    var session: Variant = SessionScript.new(doc)
    assert_true(session.begin(layer), "A session opens")
    # Two chunks right of the painted one, out of the blur's reach of it.
    var edge: int = (layer.chunks[Vector2i.ZERO] as SaChunk).pixel_size()
    session.smooth(Vector2(edge * 2.5, edge * 0.5), SIZE, 1.0, FRAME)
    assert_eq(layer.chunks.keys(), [Vector2i.ZERO], "Only the painted chunk is held")
    assert_false(session.commit(), "The commit has nothing to record")


## Paints a stroke across the seam of chunks (0, 0) and (1, 0), its path
## swinging `SWING` either side of row *row* around column *seam*.
func _paint_across_the_seam(layer: SaLayer, seam: int, row: int) -> void:
    for grid_pos: Vector2i in [Vector2i.ZERO, Vector2i(1, 0)]:
        var chunk := layer.get_or_create_chunk(grid_pos)
        var edge := chunk.pixel_size()
        var texture := chunk.albedo()
        var image := Image.create_empty(edge, edge, false, _image_format(texture))
        for y in edge:
            for x in edge:
                var at := Vector2(grid_pos.x * edge + x, y) + Vector2(0.5, 0.5)
                var phase := TAU * (at.x - seam) / PERIOD
                var slope := SWING * TAU / PERIOD * cos(phase)
                # The distance to the path to first order, which is all a seam
                # needs.
                var far := absf(at.y - row - SWING * sin(phase)) / sqrt(1.0 + slope * slope)
                var covered := clampf(HALF_WIDTH + 0.5 - far, 0.0, 1.0) if absf(at.x - seam) < 100.0 else 0.0
                image.set_pixel(x, y, Color(RED.r, RED.g, RED.b, covered))
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
        layer.mark_unresolved(grid_pos)
    _surface.get_document().invalidate_chunks([Vector2i.ZERO, Vector2i(1, 0)])


## The stroke's middle in each column within `READ_HALF` of *seam*, read out
## of whichever chunk holds the column.
static func _middles(layer: SaLayer, seam: int, row: int) -> Array[float]:
    var images := {Vector2i.ZERO: _read(layer.chunks[Vector2i.ZERO]), Vector2i(1, 0): _read(layer.chunks[Vector2i(1, 0)])}
    var middles: Array[float] = []
    for column in range(seam - READ_HALF, seam + READ_HALF):
        var grid_pos := Vector2i(0 if column < seam else 1, 0)
        var image: Image = images[grid_pos]
        var weight := 0.0
        var moment := 0.0
        for y in range(row - 24, row + 24):
            var alpha := image.get_pixel(column - grid_pos.x * seam, y).a
            weight += alpha
            moment += alpha * (y + 0.5)
        middles.append(moment / weight if weight > 0.0 else -1.0)
    return middles


static func _swing(middles: Array[float], row: int) -> float:
    var furthest := 0.0
    for middle: float in middles:
        furthest = maxf(furthest, absf(middle - row))
    return furthest


func test_a_smooth_across_a_chunks_edge_straightens_the_stroke_on_both_sides() -> void:
    var layer := _open()
    var edge: int = layer.get_or_create_chunk(Vector2i.ZERO).pixel_size()
    @warning_ignore("integer_division")
    var row := edge / 2
    _paint_across_the_seam(layer, edge, row)
    var doc := _surface.get_document()
    var before := doc.history.position()
    var was := _middles(layer, edge, row)
    var session: Variant = SessionScript.new(doc)
    assert_true(session.begin(layer), "A session opens")
    for frame in 60:
        session.smooth(Vector2(edge, row), SEAM_SIZE, 1.0, FRAME)
    var now := _middles(layer, edge, row)
    assert_true(
        _swing(now, row) < _swing(was, row) * 0.5, "The stroke straightens: %f from %f" % [_swing(now, row), _swing(was, row)]
    )
    var left := now.slice(0, READ_HALF)
    var right := now.slice(READ_HALF)
    assert_true(_swing(left, row) < _swing(was, row) * 0.5, "Left of the seam as well: %f" % _swing(left, row))
    assert_true(_swing(right, row) < _swing(was, row) * 0.5, "And right of it: %f" % _swing(right, row))
    var step := absf(now[READ_HALF] - now[READ_HALF - 1])
    var stepped := absf(was[READ_HALF] - was[READ_HALF - 1])
    assert_true(step <= stepped + 0.25, "And no step opens at the seam: %f, %f before" % [step, stepped])
    assert_true(session.commit(), "The commit records the smooth")
    assert_true(doc.history.position() != before, "As one step")
