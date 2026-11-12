## A layer's picture is drawn over a checker, and a mask's is not.
##
## The finding: eleven layers whose pictures were too dark to tell apart, and
## most of the rest an empty box. The picture was the layer's paint over nothing,
## so the row's dark ground showed through wherever the layer was transparent and
## dark paint had nothing to stand against.
##
## The texture is read back here with the harness's own read, the way the suite
## beside this one does, because a picture of a row cannot say which of two greys
## a texel is. The rule against CPU-GPU ping-pong is about the stroke, and the row itself reads nothing.
extends "res://tests/test_framework.gd"

## The thumbnail is a compute dispatch over the layer's chunks.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Three chunks wide and one tall, which is a picture 32 texels by 11, so each
## chunk owns a third of the columns and the checker's squares are four across.
const CANVAS := Vector2i(768, 256)

## Half floats are what the picture is kept in, and a grey near 0.86 is stored to
## about a thousandth.
const EPSILON := 0.004

const BLACK := Color(0.0, 0.0, 0.0, 1.0)
const DARK_BLUE := Color(0.04, 0.08, 0.4, 1.0)
const WHITE := Color(1.0, 1.0, 1.0, 1.0)

## Columns that sit well inside each chunk's third of the picture, so a texel on a
## seam, which one chunk owns and the other only touches, is never asked about.
const FIRST_CHUNK_COLUMNS := [1, 2, 3, 4, 5, 6, 7, 8]
const MIDDLE_CHUNK_COLUMNS := [13, 14, 15, 16, 17, 18, 19]
const LAST_CHUNK_COLUMNS := [24, 25, 26, 27, 28, 29, 30]


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(CANVAS)
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


## Half floats, because that is what a thumbnail is kept in.
func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var at := (y * texture.size.x + x) * 8
    return Color(data.decode_half(at), data.decode_half(at + 2), data.decode_half(at + 4), data.decode_half(at + 6))


## The picture of the layer with *first* in its first chunk and *last* in its
## last, and nothing in the middle one.
func _picture(easel: SaEasel, thumb: SaLayerThumbnail, first: Color, last: Color) -> SaTexture:
    var doc := easel.document
    var layer := doc.active_layer
    layer.get_or_create_chunk(Vector2i(0, 0)).clear(first)
    layer.get_or_create_chunk(Vector2i(2, 0)).clear(last)
    doc.invalidate_chunks([Vector2i(0, 0), Vector2i(2, 0)])
    thumb.bind_layer(layer, doc)
    thumb.refresh()
    return thumb._texture


## How bright a colour reads, enough for "darker than" between two greys and a
## blue.
func _luma(colour: Color) -> float:
    return colour.r * 0.2126 + colour.g * 0.7152 + colour.b * 0.0722


## Whether *colour* is one of the checker's two greys, at full opacity.
func _is_checker(colour: Color) -> bool:
    var grey := colour.r
    var is_grey := absf(colour.g - grey) <= EPSILON and absf(colour.b - grey) <= EPSILON
    var is_tone := absf(grey - SaLayerThumbnail.CHECKER_LIGHT) <= EPSILON or absf(grey - SaLayerThumbnail.CHECKER_DARK) <= EPSILON
    return is_grey and is_tone and absf(colour.a - 1.0) <= EPSILON


## The four squares a painter must be able to count in a 32 by 22 box. The fit is
## arithmetic, so it is asserted for the sizes a document turns into.
func test_the_checker_shows_at_least_four_squares_across_the_box() -> void:
    for size: Vector2i in [Vector2i(32, 18), Vector2i(32, 32), Vector2i(18, 32), Vector2i(32, 11), Vector2i(16, 9)]:
        var side := SaLayerThumbnail.checker_side(size)
        assert_true(side >= 1, "a square is at least a texel at %s" % size)
        assert_true(float(maxi(size.x, size.y)) / float(side) >= 4.0, "and four of them fit along the longer edge at %s" % size)
    assert_eq(SaLayerThumbnail.checker_side(Vector2i(32, 18)), 4, "squares four texels across on a full picture")
    assert_eq(SaLayerThumbnail.checker_side(Vector2i(1, 1)), 1, "and a one texel picture does not divide to nothing")


## What a layer with paint in part of it shows where it holds none: the checker,
## both squares of it, where the row's ground showed through before.
func test_where_the_layer_holds_nothing_the_picture_is_the_checker() -> void:
    var easel := _easel()
    var thumb := SaLayerThumbnail.new()
    var picture := _picture(easel, thumb, BLACK, BLACK)

    assert_not_null(picture, "the thumbnail allocated a texture")
    if picture != null:
        assert_false(
            bool(thumb.rim_report()["checker"]), "a layer with paint has a picture, so the row draws no checker of its own"
        )
        var light := 0
        var dark := 0
        for y in picture.size.y:
            for x: int in MIDDLE_CHUNK_COLUMNS:
                var colour := _texel(picture, x, y)
                assert_true(_is_checker(colour), "the empty texel (%d, %d) is a checker grey, not %s" % [x, y, colour])
                if absf(colour.r - SaLayerThumbnail.CHECKER_LIGHT) <= EPSILON:
                    light += 1
                else:
                    dark += 1
        assert_true(light > 0 and dark > 0, "and both squares of it are there, %d light and %d dark" % [light, dark])
    thumb.free()
    easel.free()


## The other half of the finding: black and dark blue, which the row's own ground
## swallowed, are darker than the checker's light squares, so they read against it.
func test_black_and_dark_blue_paint_read_darker_than_the_light_squares() -> void:
    var easel := _easel()
    var thumb := SaLayerThumbnail.new()
    var picture := _picture(easel, thumb, BLACK, DARK_BLUE)

    assert_not_null(picture, "the thumbnail allocated a texture")
    if picture != null:
        var light := SaLayerThumbnail.CHECKER_LIGHT
        var row := floori(picture.size.y * 0.5)
        for x: int in FIRST_CHUNK_COLUMNS:
            var colour := _texel(picture, x, row)
            assert_true(_luma(colour) < light - 0.3, "black at column %d is far darker than a light square, %s" % [x, colour])
            assert_false(_is_checker(colour), "and it is paint, not a checker grey")
        for x: int in LAST_CHUNK_COLUMNS:
            var colour := _texel(picture, x, row)
            assert_true(_luma(colour) < light - 0.3, "dark blue at column %d is far darker than a light square, %s" % [x, colour])
            assert_true(colour.b > colour.r, "and it is still the blue that was painted")
    thumb.free()
    easel.free()


## White is told from nothing by having no squares in it, which is how every
## painting program does it, and the test holds that every texel of it is one
## colour where the empty middle has two.
func test_white_paint_shows_no_squares() -> void:
    var easel := _easel()
    var thumb := SaLayerThumbnail.new()
    var picture := _picture(easel, thumb, WHITE, WHITE)

    assert_not_null(picture, "the thumbnail allocated a texture")
    if picture != null:
        for y in picture.size.y:
            for x: int in FIRST_CHUNK_COLUMNS:
                var colour := _texel(picture, x, y)
                assert_almost_eq(colour.r, 1.0, EPSILON, "white at (%d, %d) is white, not a square" % [x, y])
                assert_almost_eq(colour.b, 1.0, EPSILON, "in blue as well")
    thumb.free()
    easel.free()


## Paint that is half there lets the checker through by half. The kernel sums the
## taps premultiplied, so a transparent texel's stored colour, which is whatever
## was left in it, does not colour the average.
func test_half_transparent_paint_lets_the_checker_through_by_half() -> void:
    var easel := _easel()
    var thumb := SaLayerThumbnail.new()
    var picture := _picture(easel, thumb, Color(0.0, 0.0, 0.0, 0.5), BLACK)

    assert_not_null(picture, "the thumbnail allocated a texture")
    if picture != null:
        var row := floori(picture.size.y * 0.5)
        for x: int in FIRST_CHUNK_COLUMNS:
            var colour := _texel(picture, x, row)
            assert_almost_eq(colour.a, 1.0, EPSILON, "a picture over a checker is opaque at column %d" % x)
            var shows_light := absf(colour.r - SaLayerThumbnail.CHECKER_LIGHT * 0.5) <= EPSILON
            var shows_dark := absf(colour.r - SaLayerThumbnail.CHECKER_DARK * 0.5) <= EPSILON
            assert_true(shows_light or shows_dark, "half black over a square is half that square's grey, not %s" % colour)
    thumb.free()
    easel.free()


## A mask's picture is coverage, white shown and black hidden, and a checker under
## it would read as a pattern in the mask. A mask with no chunk is one white at
## every texel.
func test_a_masks_picture_carries_no_checker() -> void:
    var easel := _easel()
    var doc := easel.document
    var layer := doc.active_layer
    var mask := layer.add_mask()
    var thumb := SaLayerThumbnail.for_mask()
    thumb.bind_mask(mask, doc)
    thumb.refresh()
    var picture: SaTexture = thumb._texture

    assert_not_null(picture, "the mask's picture is drawn even with no chunk in it")
    if picture != null:
        for y in picture.size.y:
            for x in picture.size.x:
                var colour := _texel(picture, x, y)
                assert_almost_eq(colour.r, 1.0, EPSILON, "the empty mask at (%d, %d) is white, not a checker grey" % [x, y])
    thumb.free()
    easel.free()
