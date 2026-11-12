## A layer's picture frames the paint on the layer, not the canvas.
##
## On a wide document, rows whose layer held one small
## mark on a wide canvas showed bare checker or a speck, because the picture
## mapped the whole canvas into 32 texels. The picture now frames the box round
## the paint, found on the card, widened to the document's proportions.
##
## The dabs are written into the chunks by hand with `texture_update`, the way
## the `measure` suite writes its colours, because a disc of known size at a
## known place is what the frame is measured against, and a stroke would bring a
## brush's spacing and falloff into it. The picture is read back with the
## harness's own read, as the checker suite beside this one does. The row itself
## reads nothing back.
extends "res://tests/test_framework.gd"

## The thumbnail and the box round the paint are compute dispatches.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Eight chunks by four and sixty-four times the box's width, a picture 32
## texels by 16 in which a texel is 64 document pixels when the whole canvas
## shows.
const CANVAS := Vector2i(2048, 1024)

## Small against the canvas, a twenty-fifth of its width, and a little more
## than one texel of the picture of the whole canvas.
const RADIUS := 40.0

## Near the top left corner, on the centre of the whole canvas's second texel
## along each edge, and inside the first chunk without filling it, so a frame
## made of whole chunks would show it at less than a third of the picture.
const NEAR := Vector2(96.0, 96.0)

## Near the bottom right corner, on the centre of a texel of the whole canvas
## the same way, so its colour reads where both dabs share one picture.
const FAR := Vector2(1952.0, 928.0)

const RED := Color(0.9, 0.05, 0.05, 1.0)
const BLUE := Color(0.05, 0.1, 0.9, 1.0)


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(CANVAS)
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


## Writes a disc of *colour* of *radius*, [constant RADIUS] unless said, at
## *centre*, in document pixels, into the chunk that holds it, and leaves the
## rest of that chunk transparent.
func _dab(doc: SaDocument, centre: Vector2, colour: Color, radius: float = RADIUS) -> void:
    var layer := doc.active_layer
    var grid_pos := Vector2i(floori(centre.x / SaChunk.SIZE), floori(centre.y / SaChunk.SIZE))
    var chunk := layer.get_or_create_chunk(grid_pos)
    var texture := chunk.albedo()
    assert_not_null(texture, "the chunk at %s holds an albedo field" % grid_pos)
    if texture == null:
        return
    var pixel := chunk.pixel_size()
    var per_pixel := float(pixel) / float(SaChunk.SIZE)
    var local := (centre - Vector2(grid_pos * SaChunk.SIZE)) * per_pixel
    var wide := SaFieldSpec.BYTES_PER_TEXEL.get(texture.format, 16) as int
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var bytes := PackedByteArray()
    bytes.resize(pixel * pixel * wide)
    for y in pixel:
        for x in pixel:
            if (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(local) > radius * per_pixel:
                continue
            var at := (y * pixel + x) * wide
            for channel in 4:
                var stored := [colour.r, colour.g, colour.b, colour.a][channel] as float
                if half:
                    bytes.encode_half(at + channel * 2, stored)
                else:
                    bytes.encode_float(at + channel * 4, stored)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)
    layer.mark_unresolved(grid_pos)
    doc.invalidate_chunks([grid_pos])


## Every texel of *texture*, row by row, read back once. Half floats, because
## that is what a thumbnail is kept in.
func _texels(texture: SaTexture) -> Array[Color]:
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var shown: Array[Color] = []
    for at in range(0, texture.size.x * texture.size.y * 8, 8):
        shown.append(Color(data.decode_half(at), data.decode_half(at + 2), data.decode_half(at + 4), data.decode_half(at + 6)))
    return shown


## Whether *shown* reads as *dab* rather than as a checker grey or the other
## dab: the channel the dab is strong in stands well clear of the other two,
## which no grey and no mix mostly of grey does.
func _reads_as(shown: Color, dab: Color) -> bool:
    if dab.r > dab.b:
        return shown.r > shown.g + 0.4 and shown.r > shown.b + 0.4
    return shown.b > shown.r + 0.4 and shown.b > shown.g + 0.4


## The texels of *picture* that read as *dab*.
func _texels_of(picture: SaTexture, dab: Color) -> Array[Vector2i]:
    var shown := _texels(picture)
    var found: Array[Vector2i] = []
    for y in picture.size.y:
        for x in picture.size.x:
            if _reads_as(shown[y * picture.size.x + x], dab):
                found.append(Vector2i(x, y))
    return found


## How many columns and rows *texels* reach across, first to last.
func _span(texels: Array[Vector2i]) -> Vector2i:
    if texels.is_empty():
        return Vector2i.ZERO
    var low := texels[0]
    var high := texels[0]
    for texel: Vector2i in texels:
        low = Vector2i(mini(low.x, texel.x), mini(low.y, texel.y))
        high = Vector2i(maxi(high.x, texel.x), maxi(high.y, texel.y))
    return high - low + Vector2i.ONE


func _picture(easel: SaEasel) -> Dictionary:
    var thumb := SaLayerThumbnail.new()
    thumb.bind_layer(easel.document.active_layer, easel.document)
    thumb.refresh()
    return {"thumb": thumb, "picture": thumb._texture}


## The first requirement: one small dab near a corner of a
## canvas much wider than the box spans at least half of the picture's width or
## its height. Before the frame it was a texel or two of a 32 by 16 picture.
func test_one_small_dab_near_a_corner_spans_half_the_picture() -> void:
    var easel := _easel()
    _dab(easel.document, NEAR, RED)
    var made := _picture(easel)
    var picture: SaTexture = made["picture"]

    assert_not_null(picture, "the thumbnail allocated a texture")
    if picture != null:
        assert_eq(picture.size, Vector2i(32, 16), "the picture keeps the document's proportions")
        var red := _span(_texels_of(picture, RED))
        var across := float(red.x) / float(picture.size.x)
        var down := float(red.y) / float(picture.size.y)
        assert_true(
            across >= 0.5 or down >= 0.5,
            (
                "the dab spans %d of %d columns and %d of %d rows, half of one or the other"
                % [red.x, picture.size.x, red.y, picture.size.y]
            )
        )
        # The frame is the box round the paint and not the chunk the paint is
        # in: a chunk is 256 pixels, three times the dab's 80, and a frame
        # that holds a chunk shows the dab at under a third.
        assert_true(down >= 0.75, "and it is framed tighter than its chunk, %d of %d rows" % [red.y, picture.size.y])
    made["thumb"].free()
    easel.free()


## The second clause: a second dab near the opposite corner, and both dabs'
## colours in the picture, so the frame takes in every mark on the layer.
func test_a_second_dab_at_the_opposite_corner_shows_both() -> void:
    var easel := _easel()
    _dab(easel.document, NEAR, RED)
    _dab(easel.document, FAR, BLUE)
    var made := _picture(easel)
    var picture: SaTexture = made["picture"]

    assert_not_null(picture, "the thumbnail allocated a texture")
    if picture != null:
        var red := _texels_of(picture, RED)
        var blue := _texels_of(picture, BLUE)
        assert_false(red.is_empty(), "the red dab near the top left is in the picture")
        assert_false(blue.is_empty(), "and the blue one near the bottom right is in it too")
        if not red.is_empty() and not blue.is_empty():
            assert_true(red[0].x < blue[0].x and red[0].y < blue[0].y, "the red above and left of the blue, as painted")
    made["thumb"].free()
    easel.free()


## A frame follows the paint when it moves: the far dab is cleared away and a
## near one painted, and the same row redraws through the same buffer onto the
## near one. The box is seeded again on every redraw, or it could only ever
## grow.
func test_the_frame_is_found_again_on_every_redraw() -> void:
    var easel := _easel()
    var doc := easel.document
    _dab(doc, FAR, BLUE)
    var thumb := SaLayerThumbnail.new()
    thumb.bind_layer(doc.active_layer, doc)
    thumb.refresh()
    var picture: SaTexture = thumb._texture
    assert_not_null(picture, "the thumbnail allocated a texture")
    if picture != null:
        assert_true(_span(_texels_of(picture, BLUE)).y * 2 >= picture.size.y, "the blue dab alone fills the picture's height")

    # The far dab cleared away and a near one painted: the frame has to leave
    # the corner it was on rather than keep the old box.
    var far := Vector2i(floori(FAR.x / SaChunk.SIZE), floori(FAR.y / SaChunk.SIZE))
    doc.active_layer.get_or_create_chunk(far).clear(Color(0, 0, 0, 0))
    _dab(doc, NEAR, RED)
    thumb.refresh()
    picture = thumb._texture
    if picture != null:
        assert_true(_texels_of(picture, BLUE).is_empty(), "the cleared dab is gone")
        assert_true(_span(_texels_of(picture, RED)).y * 2 >= picture.size.y, "and the red one fills the height in its place")
    thumb.free()
    easel.free()


## A chunk the layer still holds with nothing in it, the way an eraser or a
## clear leaves one, is no paint: the frame is the box round the texels that
## hold some, found on the card, and not the chunks the CPU knows about. An
## empty chunk at the far corner leaves the near dab filling the picture.
func test_a_chunk_that_holds_nothing_does_not_widen_the_frame() -> void:
    var easel := _easel()
    var doc := easel.document
    var far := Vector2i(floori(FAR.x / SaChunk.SIZE), floori(FAR.y / SaChunk.SIZE))
    doc.active_layer.get_or_create_chunk(far).clear(Color(0.05, 0.1, 0.9, 0.0))
    doc.invalidate_chunks([far])
    _dab(doc, NEAR, RED)
    var made := _picture(easel)
    var picture: SaTexture = made["picture"]

    assert_not_null(picture, "the thumbnail allocated a texture")
    if picture != null:
        var red := _span(_texels_of(picture, RED))
        var said := "the dab fills %d of %d rows with an empty chunk across the canvas" % [red.y, picture.size.y]
        assert_true(red.y * 4 >= picture.size.y * 3, said)
    made["thumb"].free()
    easel.free()


## A layer whose only chunk holds nothing has no box at all, and its picture is
## the checker and nothing over it, rather than whatever a frame of no size
## would sample.
func test_a_layer_whose_chunks_hold_nothing_shows_the_checker() -> void:
    var easel := _easel()
    var doc := easel.document
    doc.active_layer.get_or_create_chunk(Vector2i(3, 1)).clear(Color(0, 0, 0, 0))
    doc.invalidate_chunks([Vector2i(3, 1)])
    var made := _picture(easel)
    var picture: SaTexture = made["picture"]

    assert_not_null(picture, "a layer with a chunk has a picture")
    if picture != null:
        var light := 0
        var dark := 0
        for shown: Color in _texels(picture):
            if absf(shown.r - SaLayerThumbnail.CHECKER_LIGHT) < 0.004:
                light += 1
            elif absf(shown.r - SaLayerThumbnail.CHECKER_DARK) < 0.004:
                dark += 1
        assert_eq(light + dark, picture.size.x * picture.size.y, "every texel is a checker grey")
        # Eight squares along the picture's 32 texels, four texels a side, so
        # the light ones are half of all of them.
        assert_eq(light, dark, "light and dark squares alike")
    made["thumb"].free()
    easel.free()


## A layer of a hundred chunks, more than a batch of the bounds kernel twelve
## times over, with every chunk cleared to nothing but one holding a dab. Every
## chunk is read, so the frame is the dab's and not the grid's, and the dab
## spans half the picture as it does on a layer of one chunk. A frame found from
## the rim of the grid alone would stay as wide as the grid here.
func test_one_small_dab_in_a_large_layer_spans_half_the_picture() -> void:
    var easel := _large_easel()
    _dab(easel.document, Vector2(1100.0, 1100.0), RED)
    var made := _picture(easel)
    var picture: SaTexture = made["picture"]

    assert_not_null(picture, "the thumbnail allocated a texture")
    if picture != null:
        var red := _span(_texels_of(picture, RED))
        assert_true(
            red.x * 2 >= picture.size.x and red.y * 2 >= picture.size.y,
            "the dab spans %d of %d columns and %d of %d rows" % [red.x, picture.size.x, red.y, picture.size.y]
        )
    made["thumb"].free()
    easel.free()


## Two dabs a thousand pixels apart on the same large layer land in chunks of
## different batches whichever way the grid is walked, so the box is the union
## over every dispatch and both colours are in the picture.
func test_dabs_in_a_large_layer_are_framed_together() -> void:
    var easel := _large_easel()
    _dab(easel.document, Vector2(128.0, 128.0), BLUE, 100.0)
    _dab(easel.document, Vector2(1100.0, 1100.0), RED, 100.0)
    var made := _picture(easel)
    var picture: SaTexture = made["picture"]

    assert_not_null(picture, "the thumbnail allocated a texture")
    if picture != null:
        assert_false(_texels_of(picture, RED).is_empty(), "the dab near the middle is in the picture")
        assert_false(_texels_of(picture, BLUE).is_empty(), "and so is the one in the corner")
        var both := _span(_texels_of(picture, RED) + _texels_of(picture, BLUE))
        assert_true(both.x * 4 >= picture.size.x * 3, "and the frame is theirs, %d of %d columns" % [both.x, picture.size.x])
    made["thumb"].free()
    easel.free()


## A 2560 pixel square whose active layer holds ten by ten chunks, all cleared.
func _large_easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(2560, 2560))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := easel.document
    var cleared: Array[Vector2i] = []
    for y in 10:
        for x in 10:
            doc.active_layer.get_or_create_chunk(Vector2i(x, y)).clear(Color(0, 0, 0, 0))
            cleared.append(Vector2i(x, y))
    doc.invalidate_chunks(cleared)
    assert_eq(doc.active_layer.chunks.size(), 100, "the layer holds a hundred chunks")
    return easel
