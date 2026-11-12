## The picture in a layer row, on a document that does not store red, green and
## blue.
##
## In an Oklab document the preview of the layers got red no matter which colours
## were on the layer. The thumbnail is shown
## through a plain `Texture2DRD`, and Godot's 2D pipeline writes a canvas colour
## to the screen with no encode of its own, so whatever the kernel leaves in that
## texture is what the row shows. It left the document's stored numbers, so an
## Oklab document's L, a and b reached the screen as red, green and blue, and a
## near-neutral Oklab colour is a large first channel beside two small ones.
##
## The suite is written against three colours rather than one, because a single
## colour cannot tell a fixed conversion apart from a lucky one.
extends "res://tests/test_framework.gd"

## The thumbnail is a compute dispatch over the layer's chunks.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Three chunks wide and one tall, so each of the three colours owns a chunk and
## a column of the picture.
const CANVAS := Vector2i(768, 256)

## Loose enough for a cube root and its inverse in float32 on the GPU and for the
## half floats the picture is kept in, tight enough that an 8-bit display step
## (about 0.004) is five times smaller.
const EPSILON := 0.02

const RED := Color(0.8, 0.15, 0.1, 1.0)
const GREEN := Color(0.15, 0.7, 0.2, 1.0)
const BLUE := Color(0.2, 0.25, 0.85, 1.0)


func _easel(space: SaColorSpace) -> SaEasel:
    var easel := SaEasel.create_default(CANVAS)
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    easel.document.color_space = space
    return easel


## Half floats, because that is what a thumbnail is kept in.
func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var at := (y * texture.size.x + x) * 8
    return Color(data.decode_half(at), data.decode_half(at + 2), data.decode_half(at + 4), data.decode_half(at + 6))


## Paints the three colours into the three chunks and answers the picture. The
## colours go in through `from_display`, which is the door the brush uses, so
## what lands in the chunks is whatever that document actually stores.
func _picture(easel: SaEasel, thumb: SaLayerThumbnail) -> SaTexture:
    var doc := easel.document
    var space := doc.color_space
    var layer := doc.active_layer
    var positions: Array = []
    for i in 3:
        var grid_pos := Vector2i(i, 0)
        layer.get_or_create_chunk(grid_pos).clear(space.from_display([RED, GREEN, BLUE][i]))
        positions.append(grid_pos)
    doc.invalidate_chunks(positions)

    thumb.bind_layer(layer, doc)
    thumb.refresh()
    return thumb._texture


## The middle of each of the three columns, in the picture's own texels.
func _columns(picture: SaTexture) -> Array[Color]:
    var row := roundi(picture.size.y * 0.5)
    var out: Array[Color] = []
    for i in 3:
        out.append(_texel(picture, roundi((i * 2 + 1) * picture.size.x / 6.0), row))
    return out


func test_an_oklab_document_shows_the_colours_that_were_painted() -> void:
    var easel := _easel(SaColorSpace.oklab())
    var thumb := SaLayerThumbnail.new()
    var picture := _picture(easel, thumb)

    assert_not_null(picture, "the thumbnail allocated a texture")
    if picture != null:
        var columns := _columns(picture)
        var wanted: Array[Color] = [RED, GREEN, BLUE]
        for i in 3:
            assert_almost_eq(columns[i].r, wanted[i].r, EPSILON, "column %d is the red that was painted" % i)
            assert_almost_eq(columns[i].g, wanted[i].g, EPSILON, "column %d is the green that was painted" % i)
            assert_almost_eq(columns[i].b, wanted[i].b, EPSILON, "column %d is the blue that was painted" % i)
            assert_almost_eq(columns[i].a, 1.0, EPSILON, "column %d is opaque" % i)
    thumb.free()
    easel.free()


## The bug: every column read as red, whatever was painted.
## Asserted as an inequality rather than as three colours, because what the wrong
## picture held is not worth pinning down and the right one is asserted above.
func test_an_oklab_document_does_not_show_three_reds() -> void:
    var easel := _easel(SaColorSpace.oklab())
    var thumb := SaLayerThumbnail.new()
    var picture := _picture(easel, thumb)

    if picture != null:
        var columns := _columns(picture)
        assert_true(columns[1].g > columns[1].r, "the green column is greener than it is red")
        assert_true(columns[2].b > columns[2].r, "and the blue column bluer")
    thumb.free()
    easel.free()


## An sRGB document is the passthrough branch, so its picture is exactly what the
## chunks hold and not a round trip that only rounds back to it.
func test_an_srgb_document_is_left_alone() -> void:
    var easel := _easel(SaColorSpace.srgb())
    var thumb := SaLayerThumbnail.new()
    var picture := _picture(easel, thumb)

    assert_not_null(picture, "the thumbnail allocated a texture")
    if picture != null:
        var columns := _columns(picture)
        var wanted: Array[Color] = [RED, GREEN, BLUE]
        for i in 3:
            assert_almost_eq(columns[i].r, wanted[i].r, EPSILON, "column %d keeps its red" % i)
            assert_almost_eq(columns[i].g, wanted[i].g, EPSILON, "column %d keeps its green" % i)
            assert_almost_eq(columns[i].b, wanted[i].b, EPSILON, "column %d keeps its blue" % i)
    thumb.free()
    easel.free()


## A Linear sRGB document stores light rather than encoded values, and showing
## those verbatim is the same class of bug as the Oklab one: mid grey would reach
## the row as 0.214. The note only named Oklab, and the fix is the document's
## own transfer curve rather than a special case for one coordinate system.
func test_a_linear_document_is_encoded_for_the_screen() -> void:
    var easel := _easel(SaColorSpace.linear_srgb())
    var thumb := SaLayerThumbnail.new()
    var picture := _picture(easel, thumb)

    assert_not_null(picture, "the thumbnail allocated a texture")
    if picture != null:
        var columns := _columns(picture)
        var wanted: Array[Color] = [RED, GREEN, BLUE]
        for i in 3:
            assert_almost_eq(columns[i].r, wanted[i].r, EPSILON, "column %d is the red a screen wants" % i)
            assert_almost_eq(columns[i].g, wanted[i].g, EPSILON, "column %d is the green a screen wants" % i)
            assert_almost_eq(columns[i].b, wanted[i].b, EPSILON, "column %d is the blue a screen wants" % i)
    thumb.free()
    easel.free()


## The block the two kernels read is 24 floats, and `thumbnail.gmacs` declares 96
## bytes. A mismatch is reported by RenderingDevice as the push constant being
## absent, which sends you looking for a binding bug, so it is asserted here.
func test_the_push_constant_is_the_size_the_kernel_declares() -> void:
    var tail := SaLayerThumbnail._display_tail(SaColorSpace.oklab())
    assert_eq(tail.size(), SaLayerThumbnail.DISPLAY_TAIL_FLOATS, "the colour tail is eighteen floats")
    var block := SaLayerThumbnail._params(Vector2(768, 256), Vector2.ZERO, Vector2.ONE, tail)
    assert_eq(block.size() * 4, 96, "and the whole block is the 96 bytes the GLSL declares")


## The passthrough flag is what keeps an sRGB document bit-identical, and it is
## the only document that gets it: a curve, a gamut or a coordinate system away
## from sRGB all need the conversion.
func test_only_an_srgb_document_takes_the_passthrough() -> void:
    assert_eq(SaLayerThumbnail._display_tail(SaColorSpace.srgb())[0], 1.0, "sRGB passes straight through")
    assert_eq(SaLayerThumbnail._display_tail(SaColorSpace.oklab())[0], 0.0, "Oklab does not")
    assert_eq(SaLayerThumbnail._display_tail(SaColorSpace.linear_srgb())[0], 0.0, "nor does a linear document")
    assert_eq(SaLayerThumbnail._display_tail(SaColorSpace.display_p3())[0], 0.0, "nor a wider gamut")


## A null descriptor is read as sRGB, which is what a document that was never
## told renders as, so a caller with no space in hand cannot break the picture.
func test_a_document_with_no_descriptor_is_read_as_srgb() -> void:
    var tail := SaLayerThumbnail._display_tail(null)
    assert_eq(tail.size(), SaLayerThumbnail.DISPLAY_TAIL_FLOATS, "the tail is still the right size")
    assert_eq(tail[0], 1.0, "and it passes straight through")
