## A `path` step with `"antialias": false` over one pixel's
## square, or a square three pixels wide, lays the colour asked on every pixel
## inside and leaves every pixel outside as it was, to the bit. A single-pixel
## speck at the default soft edge laid 12 to 29 percent of the colour, so a
## hard fill is asked for.
##
## The squares sit on a ground of paint laid first, so "unchanged" is read
## against something to change: the whole of every chunk the square reaches is
## read before and after, and only the texels inside may differ. One square
## sits inside a chunk and one across the corner where four chunks meet, since
## a square there is filled through four masks.
##
## Everything goes through `SaScenarioPath.fill`, the door the step itself
## calls once it has found the main canvas, so the suite needs a document and
## no window.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const ScenarioPath = preload("res://harness/scenario/sa_scenario_path.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The grey asked for where the speck was 51.
const MARK := Color(128.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0, 1.0)
## An opaque ground, the 51 a speck sat in.
const GROUND := Color(51.0 / 255.0, 51.0 / 255.0, 51.0 / 255.0, 1.0)
## A ground that is not opaque, whose colour a fill takes apart and puts back
## by its alpha, so a pixel left out could still move by a rounding.
const GLAZE := Color(0.2, 0.4, 0.6, 0.6)

## The ground covers the four chunks that meet at the corner `SaChunk.SIZE`
## pixels in on each axis.
const GROUND_FROM: int = 100
const GROUND_TO: int = 420

var _surface: SaSurface = null
var _doc: SaDocument = null
var _kept_foreground: Color


## Three by three chunks, so the corner at (256, 256) has a chunk on every side.
func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(768, 768))
    _doc = _surface.get_document()
    _kept_foreground = SaColors.foreground


func after_each() -> void:
    SaColors.foreground = _kept_foreground
    _doc.free()
    _surface.easel.free()
    _surface = null
    _doc = null


## The polygon of the square *width* pixels wide whose top left pixel is *at*,
## its corners on pixel lines, which is how a painter names a pixel's square.
func _square(at: Vector2i, width: int) -> Array:
    return [[at.x, at.y], [at.x + width, at.y], [at.x + width, at.y + width], [at.x, at.y + width]]


## Lays *colour* hard over the ground's square, so the squares that follow
## land on paint.
func _lay_ground(colour: Color) -> void:
    SaColors.foreground = colour
    var side := GROUND_TO - GROUND_FROM
    ScenarioPath.fill(_doc, {"polygon": _square(Vector2i(GROUND_FROM, GROUND_FROM), side), "antialias": false})


## The layer's texels, `{grid_pos: PackedByteArray}`, for every chunk it holds.
func _chunk_bytes() -> Dictionary:
    var out: Dictionary = {}
    var layer := _doc.active_layer
    for grid_pos: Vector2i in layer.chunks:
        var texture: SaTexture = (layer.chunks[grid_pos] as SaChunk).field(SaFieldSpec.ALBEDO)
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return out


## The texel at document pixel *pixel* in *bytes*, the chunk at *grid_pos*.
func _texel_in(bytes: PackedByteArray, grid_pos: Vector2i, pixel: Vector2i) -> Color:
    var chunk := _doc.active_layer.chunks[grid_pos] as SaChunk
    var side := chunk.pixel_size()
    var local := pixel - grid_pos * SaChunk.SIZE
    var at := (local.y * side + local.x) * 16
    return Color(bytes.decode_float(at), bytes.decode_float(at + 4), bytes.decode_float(at + 8), bytes.decode_float(at + 12))


## Blanks the texels of *bytes* inside *square*, so what is left compares
## outside it alone.
func _blank_inside(bytes: PackedByteArray, grid_pos: Vector2i, square: Rect2i) -> PackedByteArray:
    var out := bytes.duplicate()
    var side := (_doc.active_layer.chunks[grid_pos] as SaChunk).pixel_size()
    var chunk_rect := Rect2i(grid_pos * SaChunk.SIZE, Vector2i(side, side))
    var inside := square.intersection(chunk_rect)
    for y in range(inside.position.y, inside.end.y):
        for x in range(inside.position.x, inside.end.x):
            var local := Vector2i(x, y) - grid_pos * SaChunk.SIZE
            var at := (local.y * side + local.x) * 16
            for i in 16:
                out[at + i] = 0
    return out


## Fills the square *width* pixels wide at *at* hard with MARK, then reads every
## pixel inside at MARK in the document's encoding and every texel outside, in
## every chunk the layer holds, as it was. Answers the number of chunks filled.
func _fills_hard(at: Vector2i, width: int, what: String) -> int:
    var before := _chunk_bytes()
    SaColors.foreground = MARK
    var touched := ScenarioPath.fill(_doc, {"polygon": _square(at, width), "antialias": false})
    var after := _chunk_bytes()
    var space := _doc.color_space
    var asked: Color = space.from_display(MARK) if space != null else MARK
    var square := Rect2i(at, Vector2i(width, width))

    # A chunk the square made is read against the blank one it started as.
    var made: Array[Vector2i] = []
    for grid_pos: Vector2i in after:
        if not before.has(grid_pos):
            made.append(grid_pos)
            var blank := PackedByteArray()
            blank.resize((after[grid_pos] as PackedByteArray).size())
            before[grid_pos] = blank
    for grid_pos: Vector2i in made:
        var chunk_rect := Rect2i(grid_pos * SaChunk.SIZE, Vector2i(SaChunk.SIZE, SaChunk.SIZE))
        assert_true(chunk_rect.intersects(square), "%s made the chunk at %s, which it reaches" % [what, grid_pos])
    var wrong_inside: Array[String] = []
    for y in range(square.position.y, square.end.y):
        for x in range(square.position.x, square.end.x):
            @warning_ignore("integer_division")
            var grid_pos := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
            var got := _texel_in(after[grid_pos], grid_pos, Vector2i(x, y))
            var off := Vector4(got.r - asked.r, got.g - asked.g, got.b - asked.b, got.a - asked.a).abs()
            if maxf(maxf(off.x, off.y), maxf(off.z, off.w)) > 1e-6:
                wrong_inside.append("(%d, %d) %s" % [x, y, got])
    assert_eq(wrong_inside, [] as Array[String], "%s lays the whole colour asked, %s, on every pixel inside" % [what, asked])

    var moved: Array[Vector2i] = []
    for grid_pos: Vector2i in before:
        if _blank_inside(after[grid_pos], grid_pos, square) != _blank_inside(before[grid_pos], grid_pos, square):
            moved.append(grid_pos)
    assert_eq(moved, [] as Array[Vector2i], "%s leaves every pixel outside it as it was, to the bit" % what)
    return touched


func test_one_pixel_inside_a_chunk_takes_the_whole_colour_and_no_neighbour_does() -> void:
    _lay_ground(GROUND)
    var touched := _fills_hard(Vector2i(180, 200), 1, "One pixel's square")
    assert_eq(touched, 1, "and it reached its one chunk")


func test_three_pixels_inside_a_chunk_take_the_whole_colour_and_no_neighbour_does() -> void:
    _lay_ground(GROUND)
    var touched := _fills_hard(Vector2i(180, 200), 3, "A square three pixels wide")
    assert_eq(touched, 1, "and it reached its one chunk")


func test_one_pixel_at_a_chunks_last_texel_takes_the_whole_colour() -> void:
    _lay_ground(GROUND)
    var corner := SaChunk.SIZE - 1
    var touched := _fills_hard(Vector2i(corner, corner), 1, "One pixel at the chunk's last texel")
    assert_eq(touched, 1, "and it reached its one chunk, none of the three beside it")


func test_three_pixels_across_four_chunks_take_the_whole_colour() -> void:
    _lay_ground(GROUND)
    var start := SaChunk.SIZE - 1
    var touched := _fills_hard(Vector2i(start, start), 3, "A square three pixels wide across the corner of four chunks")
    assert_eq(touched, 4, "and it reached all four")


func test_a_ground_that_is_not_opaque_keeps_every_pixel_outside() -> void:
    _lay_ground(GLAZE)
    _fills_hard(Vector2i(180, 200), 1, "One pixel's square on a glaze")
    _fills_hard(Vector2i(300, 320), 3, "A square three pixels wide on a glaze")


func test_one_pixel_on_an_empty_layer_lays_that_pixel_alone() -> void:
    var touched := _fills_hard(Vector2i(500, 500), 1, "One pixel's square on an empty layer")
    assert_eq(touched, 1, "and it allocated the one chunk it is in")
    assert_eq(_doc.active_layer.chunks.size(), 1, "and no other")
