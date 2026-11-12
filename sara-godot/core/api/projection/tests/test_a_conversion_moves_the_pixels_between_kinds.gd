extends "res://tests/test_framework.gd"
## Image > Projection's Convert moves a document's pixels from one projection to
## another so the picture stays where it is in the view. A horizontal line of a
## polar document is a ring on the flat canvas it converts to and the line again
## converted back, a flat line goes to polar and comes back within a texel, an
## equirectangular panorama turned from Blender's orientation to Godot's puts
## longitude nought where Godot reads it, the conversion is one history step
## that undoes to every texel of every layer, a target chunk no painted chunk
## reaches is never made, and a layer that holds no pixels keeps its record.

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
## A 64 by 64 canvas, and the polar strip it converts to: TAU times its
## inscribed radius of 32 across and the radius down. Each converts to the other.
const FLAT := Vector2i(64, 64)
const POLAR := Vector2i(201, 32)
## Twice as wide as tall, the shape an equirectangular panorama is.
const PANORAMA := Vector2i(64, 32)
## How much alpha reads as painted, and how little as nothing.
const SHOWN := 0.8
const NOTHING := 0.01

var _registries: SaRegistries = null
var _easel: SaEasel = null


func before_each() -> void:
    _registries = Fixtures.make_registries()


func after_each() -> void:
    if _easel != null:
        _easel.free()
        _easel = null


func _kind(kind_id: StringName) -> SaProjection.Kind:
    return _registries.projections.find(kind_id)


## A fresh document of *size*, assigned *projection* where it is not null.
func _open(size: Vector2i, projection: SaProjection = null) -> SaDocument:
    _easel = SaEasel.create_default(size)
    var doc := _easel.document
    if projection != null:
        SaProjection.assign(doc, projection)
    return doc


## Paints *rect* of *layer*, a layer at one texel to the pixel, in *colour*,
## over what its chunks hold, uploaded since the brush is not what this is about.
static func _paint(layer: SaLayer, rect: Rect2i, colour: Color) -> void:
    var side := SaLayer.CHUNK_SIZE
    for grid_pos: Vector2i in SaLayer.grid_positions(rect.end):
        var tile := Rect2i(grid_pos * side, Vector2i(side, side))
        var part := tile.intersection(rect)
        if not part.has_area():
            continue
        var texture := layer.get_or_create_chunk(grid_pos).albedo()
        var image := _image_of(texture)
        image.fill_rect(Rect2i(part.position - tile.position, part.size), colour)
        if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
            image.convert(Image.FORMAT_RGBAH)
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
        layer.mark_unresolved(grid_pos)


## *texture*, a chunk's colour, as an image of floats.
static func _image_of(texture: SaTexture) -> Image:
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var image := Image.create_from_data(
        texture.size.x, texture.size.y, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF, bytes
    )
    image.convert(Image.FORMAT_RGBAF)
    return image


## The colour of every layer chunk of *layer*, one texel to the pixel, laid out
## over a canvas of *size*.
static func _picture(layer: SaLayer, size: Vector2i) -> Image:
    var out := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBAF)
    for grid_pos: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid_pos]
        if chunk == null:
            continue
        var edge := chunk.pixel_size()
        out.blit_rect(_image_of(chunk.albedo()), Rect2i(0, 0, edge, edge), grid_pos * edge)
    return out


## The alpha-weighted middle of *column*'s rows, in pixels from the top edge.
static func _middle_of(picture: Image, column: int) -> float:
    var weight := 0.0
    var sum := 0.0
    for row in picture.get_height():
        var alpha := picture.get_pixel(column, row).a
        weight += alpha
        sum += alpha * (row + 0.5)
    return sum / weight if weight > 0.0 else -1.0


## Every field of every chunk *layer* holds, as bytes by grid position.
static func _texels(layer: SaLayer) -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid_pos]
        var fields := {}
        for field_id: StringName in chunk.fields:
            fields[field_id] = GlobalShaderCompiler.get_rd().texture_get_data(chunk.fields[field_id].rid, 0)
        out[grid_pos] = fields
    return out


func test_a_polar_documents_horizontal_line_converts_to_a_ring_and_back_to_the_line() -> void:
    var doc := _open(POLAR, SaProjection.new(_kind(SaProjection.POLAR)))
    var layer := doc.active_layer
    # Rows 15 to 17, a radius of 15 to 18 pixels of the disc, its middle 16.5.
    _paint(layer, Rect2i(0, 15, POLAR.x, 3), RED)
    assert_true(SaProjection.reproject(doc, SaProjection.new(_kind(SaProjection.FLAT))), "The polar document converts to flat")
    assert_eq(doc.canvas_size, FLAT, "on the square twice the polar height across")
    assert_eq(doc.projection.kind.id, SaProjection.FLAT, "and reads as flat")
    var flat := _picture(layer, doc.canvas_size)
    var middle := Vector2(FLAT) * 0.5
    for turn in 24:
        var way := Vector2(sin(TAU * turn / 24.0), -cos(TAU * turn / 24.0))
        var on := Vector2i((middle + way * 16.5).floor())
        assert_true(flat.get_pixelv(on).a > SHOWN, "The ring is painted at %s" % on)
        assert_almost_eq(flat.get_pixelv(on).r, 1.0, 0.01, "in the line's red at %s" % on)
        for radius: float in [10.0, 23.0]:
            var off := Vector2i((middle + way * radius).floor())
            assert_true(flat.get_pixelv(off).a < NOTHING, "and nothing lies %s pixels out at %s" % [radius, off])

    assert_true(SaProjection.reproject(doc, SaProjection.new(_kind(SaProjection.POLAR))), "The ring converts back to polar")
    assert_eq(doc.canvas_size, POLAR, "on the strip it came from")
    var back := _picture(layer, doc.canvas_size)
    for column in range(0, POLAR.x, 4):
        assert_almost_eq(_middle_of(back, column), 16.5, 1.0, "Column %d holds the line within one texel" % column)
        assert_true(back.get_pixel(column, 16).a > SHOWN, "painted through at column %d" % column)


func test_a_flat_line_goes_to_polar_and_comes_back_within_one_texel() -> void:
    var doc := _open(FLAT)
    var layer := doc.active_layer
    # Rows 40 to 42 across the lower half of the disc, the middle 41.5.
    _paint(layer, Rect2i(8, 40, 48, 3), RED)
    assert_true(SaProjection.reproject(doc, SaProjection.new(_kind(SaProjection.POLAR))), "The flat document converts to polar")
    assert_eq(doc.canvas_size, POLAR, "on the strip TAU r across and r down")
    var polar := _picture(layer, doc.canvas_size)
    # Straight down from the middle the line is 9.5 pixels out, and toward its
    # ends further, so in polar pixels it is a curve and not a row.
    var nearest := INF
    var furthest := -INF
    for column in POLAR.x:
        var row := _middle_of(polar, column)
        if row >= 0.0:
            nearest = minf(nearest, row)
            furthest = maxf(furthest, row)
    assert_almost_eq(nearest, 10.0, 1.0, "The line's nearest point to the middle is a radius of about 9.5")
    assert_true(furthest - nearest > 10.0, "and in polar pixels it curves away from it")

    assert_true(SaProjection.reproject(doc, SaProjection.new(_kind(SaProjection.FLAT))), "The polar document converts back")
    assert_eq(doc.canvas_size, FLAT, "to the canvas it came from")
    var back := _picture(layer, doc.canvas_size)
    for column in range(12, 53, 4):
        assert_almost_eq(_middle_of(back, column), 41.5, 1.0, "Column %d holds the line within one texel" % column)
        assert_true(back.get_pixel(column, 41).a > SHOWN, "painted through at column %d" % column)


func test_an_equirectangular_panorama_turned_to_godots_orientation_puts_longitude_nought_where_godot_reads_it() -> void:
    var doc := _open(PANORAMA, SaProjection.new(_kind(SaProjection.EQUIRECTANGULAR)))
    var layer := doc.active_layer
    # Straight ahead in Blender's orientation is a quarter of the way across,
    # and its left edge looks to the left.
    _paint(layer, Rect2i(15, 4, 2, 24), RED)
    _paint(layer, Rect2i(0, 4, 1, 24), BLUE)
    _paint(layer, Rect2i(63, 4, 1, 24), BLUE)
    var godot := SaProjection.new(_kind(SaProjection.EQUIRECTANGULAR), SaProjection.Heading.new(SaProjection.Heading.GODOT))
    assert_true(SaProjection.reproject(doc, godot), "Blender's orientation converts to Godot's")
    assert_eq(doc.canvas_size, PANORAMA, "on the canvas it had")
    assert_true(doc.projection.matches(godot), "and the document reads Godot's orientation")
    var ahead := doc.projection.from_view(Vector3(0.0, 0.0, -1.0), Vector2(PANORAMA))
    assert_almost_eq(fposmod(ahead.x + 1.0, float(PANORAMA.x)) - 1.0, 0.0, 0.001, "Godot reads straight ahead at the left edge")
    var turned := _picture(layer, doc.canvas_size)
    for row: int in [8, 16, 24]:
        for column: int in [63, 0]:
            assert_true(turned.get_pixel(column, row).r > SHOWN, "Longitude nought's red lies at column %d" % column)
        for column: int in [47, 48]:
            assert_true(
                turned.get_pixel(column, row).b > SHOWN, "Blender's left edge lies three quarters across, column %d" % column
            )
        for column: int in [15, 16, 32]:
            assert_true(turned.get_pixel(column, row).a < NOTHING, "and nothing is left at column %d" % column)


func test_a_conversion_is_one_step_that_undoes_to_every_texel() -> void:
    var doc := _open(FLAT)
    var line := doc.active_layer
    _paint(line, Rect2i(8, 40, 48, 3), RED)
    line.add_mask(1.0)
    var fine := SaLayerOps.new(doc).add(&"", null, 2.0)
    fine.get_or_create_chunk(Vector2i.ZERO).clear(BLUE)
    var before := {line: _texels(line), fine: _texels(fine)}
    var steps := doc.undo_redo.get_history_count()
    var polar := SaProjection.new(_kind(SaProjection.POLAR))
    assert_true(SaProjection.reproject(doc, polar), "Converted")
    assert_eq(doc.undo_redo.get_history_count(), steps + 1, "as one step")
    assert_true(line.chunks[Vector2i.ZERO].has_field(SaFieldSpec.MASK), "The mask went with the paint")
    assert_eq(fine.chunks[Vector2i.ZERO].pixel_size(), 2 * line.chunks[Vector2i.ZERO].pixel_size(), "at each layer's density")
    doc.undo()
    assert_eq(doc.canvas_size, FLAT, "Undo reads the canvas it had")
    assert_eq(doc.projection.kind.id, SaProjection.FLAT, "and the kind")
    for layer: SaLayer in [line, fine]:
        var now := _texels(layer)
        assert_eq(now.keys(), (before[layer] as Dictionary).keys(), "%s holds the chunks it held" % layer.name)
        assert_eq(now, before[layer], "and every texel of every field as it was, %s" % layer.name)
    doc.redo()
    assert_eq(doc.canvas_size, POLAR, "Redo reads the converted canvas")
    assert_true(doc.projection.matches(polar), "and its projection")
    assert_false(SaProjection.reproject(doc, polar), "Converting to what it is is no step")


func test_a_target_chunk_no_painted_chunk_reaches_is_never_made() -> void:
    var doc := _open(Vector2i(768, 768))
    var layer := doc.active_layer
    # Up and to the left of the middle, all inside the canvas's first chunk.
    _paint(layer, Rect2i(40, 40, 100, 100), RED)
    var target := SaProjection.new(_kind(SaProjection.POLAR))
    assert_true(SaProjection.reproject(doc, target), "Converted")
    assert_eq(doc.canvas_size, Vector2i(2413, 384), "to a strip of ten chunks by two")
    assert_true(layer.chunks.size() < 5, "and only the chunks the painted one reaches are made")
    for grid_pos: Vector2i in layer.chunks:
        assert_true(grid_pos.x < 3, "within the eighth of the turn it lies in, %s" % grid_pos)
    var picture := _picture(layer, doc.canvas_size)
    assert_true(picture.get_pixel(302, 360).a > SHOWN, "The paint lies at an eighth of the turn, near the rim")


func test_a_layer_that_holds_no_pixels_keeps_its_record_and_the_dialog_says_so() -> void:
    var doc := _open(FLAT)
    var paint := doc.active_layer
    _paint(paint, Rect2i(8, 40, 48, 3), RED)
    var ground := SaLayerOps.new(doc).add()
    ground.generator = "background"
    ground.generator_params = {SaGeneratedLayer.PARAM_COLOR: BLUE}
    var target := SaProjection.new(_kind(SaProjection.POLAR))
    var note := SaProjection.reproject_note(doc, target)
    assert_true(note.contains("201 by 32"), "The dialog's sentence names the size: %s" % note)
    assert_true(
        note.contains("1 filter, generated or scene layer holds no pixels and keeps its record"), "and the layer kept: %s" % note
    )
    assert_true(SaProjection.reproject(doc, target), "Converted")
    assert_eq(ground.generator, "background", "The generated layer keeps its generator")
    assert_eq(ground.generator_params, {SaGeneratedLayer.PARAM_COLOR: BLUE}, "and its parameters")
    assert_true(ground.chunks.is_empty(), "and holds no pixels after it either")
    assert_false(paint.chunks.is_empty(), "while the paint moved")
    assert_true(
        SaProjection.reproject_note(doc, target).contains("already"), "Converted, the sentence says there is nothing to move"
    )
