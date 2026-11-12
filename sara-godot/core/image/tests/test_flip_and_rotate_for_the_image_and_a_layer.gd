## Image > Flip and Rotate and Layer > Flip, as numbers.
##
## Two layers carry one picture, a plain one and one at twice the resolution,
## every pixel holding its own coordinates in red and green, which a half float
## holds exactly. A flip or a turn read with the nearest filter copies texels,
## so where a pixel went is read back as a number, and two flips are compared
## with the picture they started from byte for byte. The canvas is 600 by 300,
## which no chunk edge divides, so every flip moves texels between chunks as
## well as inside them.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const SIZE := Vector2i(600, 300)
const RED := Color(1.0, 0.0, 0.0, 1.0)
## Pixels at both ends of both axes and either side of a chunk edge.
const POINTS: Array[Vector2i] = [
    Vector2i(0, 0),
    Vector2i(599, 0),
    Vector2i(0, 299),
    Vector2i(599, 299),
    Vector2i(255, 256),
    Vector2i(256, 255),
    Vector2i(300, 150),
    Vector2i(17, 283),
]

var _easel: SaEasel = null
var _doc: SaDocument = null
var _plain: SaLayer = null
var _double: SaLayer = null


func before_each() -> void:
    _easel = SaEasel.create_default(SIZE)
    _doc = _easel.document
    var ops := SaLayerOps.new(_doc)
    _plain = ops.add()
    _double = ops.add(&"", null, 2.0)
    _paint()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _plain = null
    _double = null


## Every pixel's own coordinates into both layers, the double one holding the
## pixel's value in each of the four texels over it.
func _paint() -> void:
    for layer: SaLayer in [_plain, _double]:
        var scale := int(layer.resolution_scale)
        for grid_pos: Vector2i in SaLayer.grid_positions(_doc.canvas_size):
            var chunk := layer.get_or_create_chunk(grid_pos)
            var texture: SaTexture = chunk.fields[SaFieldSpec.ALBEDO]
            var edge := chunk.pixel_size()
            var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
            var image := Image.create_empty(edge, edge, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
            var origin := grid_pos * SaLayer.CHUNK_SIZE
            for y in edge:
                for x in edge:
                    @warning_ignore("integer_division")
                    var pixel := origin + Vector2i(x / scale, y / scale)
                    image.set_pixel(x, y, Color(pixel.x, pixel.y, 0.5, 1.0))
            GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


## What *layer* holds at its own texel *at*, transparent where it holds no chunk.
func _texel(layer: SaLayer, at: Vector2i) -> Color:
    var edge := SaLayer.CHUNK_SIZE * int(layer.resolution_scale)
    var grid := Vector2i(floori(float(at.x) / edge), floori(float(at.y) / edge))
    var texture := layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    return Bench.texel(texture, at - grid * edge)


## The coordinates *layer* holds at document pixel *at*, read from every one of
## the texels over it, or a note of the first texel that disagrees.
func _holds(layer: SaLayer, at: Vector2i) -> Variant:
    var scale := int(layer.resolution_scale)
    var first := _texel(layer, at * scale)
    for dy in scale:
        for dx in scale:
            if _texel(layer, at * scale + Vector2i(dx, dy)) != first:
                return "a block that disagrees with itself at %s" % at
    return Vector2i(roundi(first.r), roundi(first.g))


## Every texel of *layer* inside the canvas as bytes, a chunk it does not hold
## read as zeros, so a flip that allocated a chunk of nothing compares equal to
## a picture that never had it.
func _picture(layer: SaLayer) -> PackedByteArray:
    var scale := int(layer.resolution_scale)
    var canvas := _doc.canvas_size * scale
    var edge := SaLayer.CHUNK_SIZE * scale
    var out := PackedByteArray()
    for grid_pos: Vector2i in SaLayer.grid_positions(_doc.canvas_size):
        var texture := layer.get_field(grid_pos)
        var data := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0) if texture != null else PackedByteArray()
        var width: int = SaFieldSpec.BYTES_PER_TEXEL.get(texture.format if texture != null else _format(layer), 0)
        var inside := (canvas - grid_pos * edge).min(Vector2i(edge, edge))
        var blank := PackedByteArray()
        blank.resize(inside.x * width)
        for y in inside.y:
            out.append_array(blank if data.is_empty() else data.slice(y * edge * width, (y * edge + inside.x) * width))
    return out


func _format(layer: SaLayer) -> int:
    for grid_pos: Vector2i in layer.chunks:
        return layer.get_field(grid_pos).format
    return RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT


# --- The maps, which are arithmetic and need no GPU ------------------------------


func test_every_map_sends_a_texel_centre_to_a_texel_centre() -> void:
    var flip := SaOrient.flip_map(SIZE, true)
    assert_eq(flip * Vector2(0.5, 0.5), Vector2(599.5, 0.5), "A horizontal flip sends the first column to the last")
    assert_eq(SaOrient.flip_map(SIZE, false) * Vector2(0.5, 0.5), Vector2(0.5, 299.5), "and a vertical one the first row")
    var turn := SaOrient.turn_map(SIZE, 1)
    assert_eq(turn * Vector2(0.0, 0.0), Vector2(300.0, 0.0), "Clockwise, the top left lands at the top right")
    assert_eq(turn * Vector2(600.0, 300.0), Vector2(0.0, 600.0), "and the bottom right at the bottom left")
    assert_eq(SaOrient.turn_map(SIZE, -1), SaOrient.turn_map(SIZE, 3), "A quarter back is three forward")
    assert_eq(SaOrient.turn_map(SIZE, 3) * Vector2(0.0, 0.0), Vector2(0.0, 600.0), "which puts the top left at the bottom left")
    assert_eq(SaOrient.turn_map(SIZE, 2) * Vector2(0.5, 0.5), Vector2(599.5, 299.5), "and a half turn sends it to the far corner")


# --- The image -------------------------------------------------------------------


func test_a_quarter_turn_swaps_the_sides_and_carries_every_pixel() -> void:
    assert_true(SaOrient.new(_doc).rotate_image(1), "The turn ran")
    assert_eq(_doc.canvas_size, Vector2i(300, 600), "The canvas is turned on its side")
    for at: Vector2i in POINTS:
        # Clockwise, the pixel at (x, y) lands at (H - 1 - y, x).
        var landed := Vector2i(SIZE.y - 1 - at.y, at.x)
        assert_eq(_holds(_plain, landed), at, "The plain layer's %s is at %s" % [at, landed])
        assert_eq(_holds(_double, landed), at, "and the double layer's too, at its own density")


func test_an_anticlockwise_turn_carries_the_other_way() -> void:
    assert_true(SaOrient.new(_doc).rotate_image(-1), "The turn ran")
    assert_eq(_doc.canvas_size, Vector2i(300, 600), "The canvas is on its side")
    for at: Vector2i in POINTS:
        var landed := Vector2i(at.y, SIZE.x - 1 - at.x)
        assert_eq(_holds(_plain, landed), at, "The pixel at %s is at %s" % [at, landed])


func test_a_half_turn_keeps_the_size_and_puts_every_pixel_opposite() -> void:
    assert_true(SaOrient.new(_doc).rotate_image(2), "The turn ran")
    assert_eq(_doc.canvas_size, SIZE, "A half turn keeps the canvas")
    for at: Vector2i in POINTS:
        assert_eq(_holds(_plain, SIZE - Vector2i.ONE - at), at, "The pixel at %s is opposite" % at)
    assert_false(SaOrient.new(_doc).rotate_image(4), "and a whole turn is refused, since it changes nothing")


func test_a_flip_carries_every_pixel_across_the_middle() -> void:
    assert_true(SaOrient.new(_doc).flip_image(true), "The flip ran")
    for at: Vector2i in POINTS:
        assert_eq(_holds(_plain, Vector2i(SIZE.x - 1 - at.x, at.y)), at, "Left to right, %s" % at)
        assert_eq(_holds(_double, Vector2i(SIZE.x - 1 - at.x, at.y)), at, "and on the double layer")
    assert_true(SaOrient.new(_doc).flip_image(false), "The other flip ran")
    for at: Vector2i in POINTS:
        assert_eq(_holds(_plain, SIZE - Vector2i.ONE - at), at, "and both together are a half turn, %s" % at)


func test_two_flips_are_the_picture_byte_for_byte() -> void:
    var plain := _picture(_plain)
    var double := _picture(_double)
    var orient := SaOrient.new(_doc)
    for horizontal: bool in [true, false]:
        assert_true(orient.flip_image(horizontal) and orient.flip_image(horizontal), "Two flips ran")
        assert_eq(_picture(_plain), plain, "and the plain layer is its picture byte for byte")
        assert_eq(_picture(_double), double, "and so is the double one")


func test_a_turn_and_its_opposite_are_the_picture_byte_for_byte() -> void:
    var plain := _picture(_plain)
    var orient := SaOrient.new(_doc)
    assert_true(orient.rotate_image(1) and orient.rotate_image(-1), "A quarter and a quarter back ran")
    assert_eq(_doc.canvas_size, SIZE, "The canvas is the way up it was")
    assert_eq(_picture(_plain), plain, "and the picture is itself byte for byte")


func test_undo_puts_the_size_and_the_picture_back_and_redo_turns_again() -> void:
    var plain := _picture(_plain)
    _doc.undo_redo.clear_history()
    assert_true(SaOrient.new(_doc).rotate_image(1), "The turn ran")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Rotate Image 90° Clockwise", "as a step named for it")

    _doc.undo_redo.undo()
    assert_eq(_doc.canvas_size, SIZE, "The undo gives the size back")
    assert_eq(_picture(_plain), plain, "and the picture with it, byte for byte")

    _doc.undo_redo.redo()
    assert_eq(_doc.canvas_size, Vector2i(300, 600), "The redo turns it again")
    assert_eq(_holds(_plain, Vector2i(SIZE.y - 1, 0)), Vector2i.ZERO, "with the top left at the top right")


func test_the_selection_is_dropped_as_a_resize_drops_it() -> void:
    _doc.selection.select_rect(Rect2i(10, 10, 50, 50))
    assert_true(SaOrient.new(_doc).flip_image(true), "The flip ran")
    assert_false(_doc.selection.active, "and the selection, in the coordinates of the picture before, is gone")


## Hard rule 3: a flip allocates a chunk only where the source reaches. A
## canvas four chunks wide maps the grid onto itself, so one chunk of paint is
## one chunk after.
func test_a_flip_allocates_only_where_the_paint_lands() -> void:
    var easel := SaEasel.create_default(Vector2i(1024, 512))
    var layer := SaLayerOps.new(easel.document).add()
    layer.get_or_create_chunk(Vector2i.ZERO).clear(RED)
    assert_true(SaOrient.new(easel.document).flip_image(true), "The flip ran")
    assert_eq(layer.chunks.keys(), [Vector2i(3, 0)], "The one chunk is at the far end and nothing else was made")
    easel.free()


## The same rule with two chunks in opposite corners. The box round them is the
## whole canvas, and a chunk of the new grid that reads only the gap between
## them is not made.
func test_a_flip_makes_nothing_between_two_far_chunks() -> void:
    var easel := SaEasel.create_default(Vector2i(1024, 512))
    var layer := SaLayerOps.new(easel.document).add()
    layer.get_or_create_chunk(Vector2i(0, 0)).clear(RED)
    layer.get_or_create_chunk(Vector2i(3, 1)).clear(RED)
    assert_true(SaOrient.new(easel.document).flip_image(true), "The flip ran")
    var kept := layer.chunks.keys()
    kept.sort()
    assert_eq(kept, [Vector2i(0, 1), Vector2i(3, 0)], "Two chunks in, two out, each where its own paint went")
    assert_true(SaOrient.new(easel.document).rotate_image(1), "and a quarter turn")
    kept = layer.chunks.keys()
    kept.sort()
    assert_eq(kept, [Vector2i(0, 0), Vector2i(1, 3)], "keeps to the two as well")
    easel.free()


func test_a_group_mask_and_a_filter_mask_turn_with_the_picture() -> void:
    var easel: SaEasel = Bench.easel(Vector2i(1024, 512))
    var doc := easel.document
    var layers := SaLayerOps.new(doc)
    var group := layers.group_active()
    var painted := layers.add()
    doc.fill_layer(Color(0, 0, 1, 1), painted)
    var record := SaFilterOps.new(doc).attach(painted, Bench.INVERT)
    var masks := SaMaskOps.new(doc)
    doc.selection.select_rect(Rect2i(600, 100, 100, 50))
    assert_true(masks.add_from_selection(group), "The group is masked from a patch")
    assert_true(masks.add_from_selection(record), "and so is the filter")
    doc.selection.deselect()

    assert_true(SaOrient.new(doc).rotate_image(1), "The turn ran")
    for mask: SaMask in [group.mask, record.mask]:
        # The patch's pixel (650, 120) lands at (511 - 120, 650).
        assert_almost_eq(_mask_reads(mask, Vector2i(391, 650)), 1.0, 0.01, "The mask turned with the picture")
        assert_almost_eq(_mask_reads(mask, Vector2i(120, 650)), 0.0, 0.01, "and hides where the patch is not")
    doc.undo_redo.undo()
    for mask: SaMask in [group.mask, record.mask]:
        assert_almost_eq(_mask_reads(mask, Vector2i(650, 120)), 1.0, 0.01, "Undone, the mask is where it was drawn")
    easel.free()


func _mask_reads(mask: SaMask, at: Vector2i) -> float:
    var edge := SaLayer.CHUNK_SIZE
    var grid_pos := Vector2i(floori(float(at.x) / edge), floori(float(at.y) / edge))
    var texture := mask.texture_for(grid_pos)
    if texture == null:
        return mask.rest
    return Bench.texel(texture, at - grid_pos * edge).r


# --- A layer ---------------------------------------------------------------------


func test_the_layer_flip_moves_the_active_layer_and_nothing_else() -> void:
    var double := _picture(_double)
    _doc.undo_redo.clear_history()
    assert_true(SaOrient.new(_doc).flip_layer(_plain, true), "The layer flip ran")
    assert_eq(_doc.undo_redo.get_current_action_name(), SaOrient.FLIP_LAYER_HORIZONTALLY, "as a step of its own name")
    for at: Vector2i in POINTS:
        assert_eq(_holds(_plain, Vector2i(SIZE.x - 1 - at.x, at.y)), at, "The layer is mirrored about the canvas, %s" % at)
    assert_eq(_picture(_double), double, "and the layer beside it is untouched")
    assert_eq(_doc.canvas_size, SIZE, "with the canvas as it was")

    _doc.undo_redo.undo()
    assert_eq(_holds(_plain, Vector2i(0, 0)), Vector2i(0, 0), "The undo puts it back")


func test_a_layer_flip_agrees_with_the_image_flip() -> void:
    var orient := SaOrient.new(_doc)
    assert_true(orient.flip_layer(_plain, false) and orient.flip_layer(_double, false), "Both layers flipped one at a time")
    var plain := _picture(_plain)
    var double := _picture(_double)
    _doc.undo_redo.undo()
    _doc.undo_redo.undo()
    assert_true(orient.flip_image(false), "and the image flipped instead")
    assert_eq(_picture(_plain), plain, "lands on the same plain layer byte for byte")
    assert_eq(_picture(_double), double, "and the same double one")


func test_a_layer_flip_takes_its_filters_mask_and_keeps_the_selection() -> void:
    var easel: SaEasel = Bench.easel(Vector2i(1024, 512))
    var doc := easel.document
    var painted := SaLayerOps.new(doc).add()
    doc.fill_layer(Color(0, 0, 1, 1), painted)
    var record := SaFilterOps.new(doc).attach(painted, Bench.INVERT)
    doc.selection.select_rect(Rect2i(100, 100, 50, 50))
    assert_true(SaMaskOps.new(doc).add_from_selection(record), "The filter is masked from a patch")
    assert_true(SaOrient.new(doc).flip_layer(painted, true), "The layer flip ran")
    assert_almost_eq(_mask_reads(record.mask, Vector2i(1024 - 1 - 120, 120)), 1.0, 0.01, "The filter's mask went with it")
    assert_almost_eq(_mask_reads(record.mask, Vector2i(120, 120)), 0.0, 0.01, "and left where it was")
    assert_true(doc.selection.active, "A layer flip changed no size, so the selection stays")
    easel.free()


func test_a_group_flips_every_layer_inside_it() -> void:
    var ops := SaLayerOps.new(_doc)
    _doc.set_active_layer(_plain)
    var group := ops.group_active()
    assert_true(SaOrient.new(_doc).flip_layer(group, true), "The group flipped")
    assert_eq(_holds(_plain, Vector2i(SIZE.x - 1, 0)), Vector2i(0, 0), "and the layer inside it is mirrored")
    assert_eq(_holds(_double, Vector2i(0, 0)), Vector2i(0, 0), "while the one outside it is not")


func test_a_locked_layer_is_not_flipped_and_says_why() -> void:
    var said: Array[String] = []
    var listen := func(line: String) -> void: said.append(line)
    EventBus.paint_refused.connect(listen)
    _plain.is_locked = true
    var steps := _doc.history.step_count()
    assert_false(SaOrient.new(_doc).flip_layer(_plain, true), "A locked layer is not flipped")
    assert_eq(_doc.history.step_count(), steps, "and no step goes on the stack")
    assert_eq(said.size(), 1, "and the corner says why")
    assert_true(not said.is_empty() and said[0].contains("locked"), "naming the lock: %s" % [said])

    _plain.is_locked = false
    var empty := SaLayerOps.new(_doc).add()
    assert_false(SaOrient.new(_doc).flip_layer(empty, true), "A layer holding nothing is not flipped either")
    assert_eq(said.size(), 2, "and says so rather than doing nothing in silence")
    EventBus.paint_refused.disconnect(listen)


## The half of the canvas the paint left is drawn again. Without the old grid
## positions in the redraw, the picture showed in both places until something
## else touched the left half.
func test_the_composite_drops_the_paint_where_it_left() -> void:
    var easel: SaEasel = Bench.easel(Vector2i(1024, 512))
    var doc := easel.document
    var layer := SaLayerOps.new(doc).add()
    layer.get_or_create_chunk(Vector2i.ZERO).clear(RED)
    Bench.composite(easel)
    var ground := Bench.texel(easel.output, Vector2i(600, 100))
    assert_almost_eq(Bench.texel(easel.output, Vector2i(100, 100)).g, 0.0, 0.01, "The paint is on the canvas, red")

    assert_true(SaOrient.new(doc).flip_layer(layer, true), "The layer flipped")
    easel.process_pending_composite()
    assert_true(Bench.texel(easel.output, Vector2i(100, 100)).is_equal_approx(ground), "Where it left is the ground again")
    assert_almost_eq(Bench.texel(easel.output, Vector2i(1000, 100)).r, 1.0, 0.01, "and it is drawn where it went")
    easel.free()
