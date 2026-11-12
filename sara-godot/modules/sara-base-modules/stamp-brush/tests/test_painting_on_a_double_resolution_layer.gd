## A stroke on a double resolution layer lands at twice the density: the same size and in the same place
## in document pixels as on any other
## layer, drawn in four times the texels, with the selection, erase, alpha lock,
## smudge and undo behaving as they do at 1.0.
##
## Painted through the real brush on the real GPU and read back off the layer's
## own chunks, texel for texel.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

const REQUIRES_GPU := true

## Two chunks side by side, so a stroke can cross a seam.
const CANVAS := Vector2i(512, 256)

## What counts as paint, as in `test_dab_dirty_rect.gd`.
const PAINTED: float = 1.0 / 512.0

## What a texel of the tip's edge counts as, above the fringe the antialiased
## edge fades out by, one document pixel wide at either density.
const VISIBLE: float = 0.05

const RED := Color(0.9, 0.1, 0.1, 1.0)
const BLUE := Color(0.1, 0.2, 0.9, 1.0)

var _surface: SaSurface = null


func after_each() -> void:
    _close()


func _close() -> void:
    if _surface != null:
        _surface.get_document().free()
        _surface.easel.free()
    _surface = null


## A fresh document whose active layer is a new one at *scale*.
##
## The compositor is handed the built-in blend modes, as `main.gd` hands it
## them. Without the registry every mode resolves to Normal, and a wash erase
## or an alpha-locked stroke, which gather in the stroke buffer and land under
## the buffer's own rule at the commit, would composite as an ordinary stroke:
## the layer would read as if nothing happened. The erase and alpha-lock cases
## of this suite take that path since wash became the brush's default, so
## the suite wires what the application wires.
func _open(scale: float) -> SaLayer:
    _close()
    _surface = Fixtures.make_surface(CANVAS)
    _surface.easel.compositor.set_registry(Fixtures.make_registries(_surface).blend_modes)
    return SaLayerOps.new(_surface.get_document()).add(&"", null, scale)


## A hard round brush *diameter* document pixels across, painting *color*.
func _brush(diameter: float, color: Color) -> ToolState:
    var brush := StateBrushScript.new()
    brush.surface = _surface
    brush.settings.color = color
    brush.settings.radius = diameter * 0.5 / float(mini(CANVAS.x, CANVAS.y))
    brush.settings.hardness = GammaFloat.new(1.0, 1.0)
    brush.settings.opacity_by_pressure = false
    brush.settings.spacing = 0.1
    return brush


## A press at *from*, *steps* motions to *to* at full pressure and the release.
func _stroke(brush: ToolState, from: Vector2, to: Vector2, steps: int = 40) -> void:
    var was := SaColors.foreground
    SaColors.foreground = brush.settings.color
    var view := _surface.view
    view.mouse_position = from
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = from
    brush.handle_input(press)
    for i in range(1, steps + 1):
        view.mouse_position = from.lerp(to, float(i) / float(steps))
        var motion := InputEventMouseMotion.new()
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.position = view.mouse_position
        motion.pressure = 1.0
        brush.handle_input(motion)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    brush.handle_input(release)
    SaColors.foreground = was


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## The chunk at *grid_pos* of *layer* as an image of its own texels, or null.
func _texels(layer: SaLayer, grid_pos: Vector2i) -> Image:
    var chunk: SaChunk = layer.chunks.get(grid_pos, null)
    if chunk == null:
        return null
    var texture := chunk.albedo()
    var edge := chunk.pixel_size()
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return Image.create_from_data(edge, edge, false, _image_format(texture), bytes)


## Every chunk of *layer* as its raw bytes, for an undo to be held to.
func _bytes(layer: SaLayer) -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in layer.chunks:
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data((layer.chunks[grid_pos] as SaChunk).albedo().rid, 0)
    return out


## Whether *layer* holds exactly *before*, a chunk the layer has since made
## counting as the same when it holds no paint.
func _same(layer: SaLayer, before: Dictionary) -> bool:
    var now := _bytes(layer)
    for grid_pos: Vector2i in now:
        if before.has(grid_pos):
            if now[grid_pos] != before[grid_pos]:
                return false
        elif _painted(_texels(layer, grid_pos)) > 0:
            return false
    for grid_pos: Vector2i in before:
        if not now.has(grid_pos):
            return false
    return true


static func _painted(image: Image) -> int:
    var count := 0
    if image == null:
        return count
    for y in image.get_height():
        for x in image.get_width():
            if image.get_pixel(x, y).a > PAINTED:
                count += 1
    return count


## How many texels of row *y* of *image* show paint.
static func _across(image: Image, y: int) -> int:
    var count := 0
    for x in image.get_width():
        if image.get_pixel(x, y).a > VISIBLE:
            count += 1
    return count


## Writes *color* over the document rectangle *rect* of *layer*, texel for
## texel at the layer's scale, in chunk 0, 0.
func _block(layer: SaLayer, rect: Rect2i, color: Color) -> void:
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    var image := _texels(layer, Vector2i.ZERO)
    var scale := int(chunk.resolution_scale)
    image.fill_rect(Rect2i(rect.position * scale, rect.size * scale), color)
    GlobalShaderCompiler.get_rd().texture_update(chunk.albedo().rid, 0, image.get_data())
    _surface.get_document().invalidate_chunks([Vector2i.ZERO])


## The ask's first clause, and Done when's three pixel round: one dab, three
## document pixels across on either layer, is three texels across at 1.0 and
## six at 2.0, centred on the same document pixel.
func test_a_three_pixel_round_is_six_texels_across() -> void:
    for scale: float in [1.0, 2.0]:
        var layer := _open(scale)
        _stroke(_brush(3.0, RED), Vector2(100, 100), Vector2(100, 100), 0)
        var image := _texels(layer, Vector2i.ZERO)
        assert_not_null(image, "the dab made a chunk at %.1f" % scale)
        if image == null:
            continue
        assert_eq(image.get_width(), int(SaChunk.SIZE * scale), "the chunk is %d texels across" % image.get_width())
        var row := int((100.0 + 0.5) * scale)
        var column := int((100.0 + 0.5) * scale)
        var wide := _across(image, row)
        assert_eq(wide, int(3 * scale), "a three pixel round at %.1f is %d texels across" % [scale, wide])
        var tall := 0
        for y in image.get_height():
            if image.get_pixel(column, y).a > VISIBLE:
                tall += 1
        assert_eq(tall, int(3 * scale), "and %d texels tall" % tall)
        assert_true(image.get_pixel(column, row).a > 0.95, "centred on document pixel 100, 100")


## One line across the seam between two chunks leaves no seam: the last
## texels of the left chunk and the first of the right are the same paint.
func test_a_line_across_a_chunk_seam_leaves_no_seam() -> void:
    var layer := _open(2.0)
    _stroke(_brush(12.0, RED), Vector2(200, 128), Vector2(312, 128))
    var left := _texels(layer, Vector2i(0, 0))
    var right := _texels(layer, Vector2i(1, 0))
    assert_not_null(left, "the line painted the left chunk")
    assert_not_null(right, "and the right one")
    if left == null or right == null:
        return
    var edge := left.get_width()
    for y in range(248, 264):
        var a := [left.get_pixel(edge - 2, y).a, left.get_pixel(edge - 1, y).a, right.get_pixel(0, y).a, right.get_pixel(1, y).a]
        for i in range(1, 4):
            if absf(float(a[i]) - float(a[0])) > 0.02:
                assert_true(false, "row %d across the seam reads %s, not one coverage" % [y, str(a)])
                return
    assert_true(left.get_pixel(edge - 1, 256).a > 0.99, "and the line is solid where it crosses")


## Inside a rectangular selection, nothing lands past its edge, and the edge
## is the document pixel's, twice the texels in from the chunk's origin.
func test_a_stroke_inside_a_selection_stops_at_its_edge() -> void:
    var layer := _open(2.0)
    var box := Rect2i(100, 100, 50, 50)
    _surface.get_document().selection.select_rect(box)
    _stroke(_brush(20.0, RED), Vector2(60, 125), Vector2(200, 125))
    var image := _texels(layer, Vector2i.ZERO)
    assert_not_null(image, "the stroke painted inside the selection")
    if image == null:
        return
    var inside := Rect2i(box.position * 2, box.size * 2)
    var outside := 0
    var within := 0
    for y in image.get_height():
        for x in image.get_width():
            if image.get_pixel(x, y).a <= PAINTED:
                continue
            if inside.has_point(Vector2i(x, y)):
                within += 1
            else:
                outside += 1
    assert_eq(outside, 0, "no texel past the selection's edge holds paint")
    assert_true(image.get_pixel(inside.position.x, 250).a > 0.99, "and the first texel inside it does")
    assert_true(image.get_pixel(inside.end.x - 1, 250).a > 0.99, "and the last")
    assert_true(within > 0, "%d texels painted inside" % within)


## A stroke, then an eraser across it, and undo takes each back to the
## texels it found.
func test_a_stroke_and_an_eraser_undo_to_the_texels_before() -> void:
    var layer := _open(2.0)
    var doc := _surface.get_document()
    var empty := _bytes(layer)
    _stroke(_brush(16.0, RED), Vector2(40, 60), Vector2(220, 60))
    var painted := _bytes(layer)
    var image := _texels(layer, Vector2i.ZERO)
    assert_true(image.get_pixel(260, 120).a > 0.99, "the stroke painted document pixel 130, 60")
    var eraser := _brush(24.0, RED)
    eraser.eraser_toggled = true
    _stroke(eraser, Vector2(130, 20), Vector2(130, 100))
    image = _texels(layer, Vector2i.ZERO)
    assert_true(image.get_pixel(260, 120).a < 0.01, "the eraser took it out, at twice the density")
    assert_true(image.get_pixel(160, 120).a > 0.99, "and left the stroke where it did not pass")
    assert_true(doc.undo(), "the erase undoes")
    assert_true(_same(layer, painted), "back to the stroke's texels, every chunk")
    assert_true(doc.undo(), "the stroke undoes")
    assert_true(_same(layer, empty), "back to nothing")


## With alpha lock on, the stroke recolours what is there and adds no alpha.
func test_alpha_lock_keeps_the_layers_coverage() -> void:
    var layer := _open(2.0)
    var doc := _surface.get_document()
    _block(layer, Rect2i(80, 80, 40, 40), RED)
    var before := _bytes(layer)
    layer.alpha_locked = true
    _stroke(_brush(16.0, BLUE), Vector2(40, 100), Vector2(160, 100))
    var image := _texels(layer, Vector2i.ZERO)
    var inside := image.get_pixel(200, 200)
    assert_true(inside.b > 0.5 and inside.r < 0.5, "inside the block the stroke painted blue, %s" % str(inside))
    assert_true(absf(inside.a - 1.0) < 0.01, "at the alpha it found")
    assert_true(image.get_pixel(120, 200).a < PAINTED, "and outside the block it painted nothing")
    assert_true(image.get_pixel(159, 200).a < PAINTED, "not even on the texel beside the block's edge")
    assert_true(doc.undo(), "the stroke undoes")
    assert_true(_same(layer, before), "back to the block's texels")


## A smudge with Sample Merged off drags the layer's own paint out past it,
## which is the pickup read from a snapshot at the layer's density. The carry
## it lays past the block, read along the stroke, is the one a plain layer's
## smudge lays, within a hundredth.
func test_a_smudge_on_the_layer_alone_picks_up_its_paint() -> void:
    var plain := PackedFloat32Array()
    for scale: float in [1.0, 2.0]:
        var layer := _open(scale)
        var doc := _surface.get_document()
        _block(layer, Rect2i(60, 90, 40, 20), RED)
        var before := _bytes(layer)
        var brush := _brush(10.0, BLUE)
        brush.settings.smudge_pickup_option.enabled = true
        brush.settings.smudge_color_rate_option.enabled = true
        brush.settings.smudge_color_rate_option.strength = 0.2
        brush.settings.smudge_length_option.enabled = true
        brush.settings.smudge_sample_merged = false
        _stroke(brush, Vector2(70, 100), Vector2(180, 100), 60)
        var image := _texels(layer, Vector2i.ZERO)
        var carried := PackedFloat32Array()
        for x in range(100, 130, 3):
            carried.append(image.get_pixel(int(x * scale), int(100 * scale)).r)
        assert_true(carried[2] > BLUE.r + 0.15, "at %.1f the stroke carried the block's red past it, %.3f" % [scale, carried[2]])
        if plain.is_empty():
            plain = carried
        else:
            for i in carried.size():
                var note := "and fades as it does at 1.0, %.3f against %.3f" % [carried[i], plain[i]]
                assert_true(absf(carried[i] - plain[i]) < 0.01, note)
        assert_true(doc.undo(), "the smudge undoes")
        assert_true(_same(layer, before), "back to the block's texels")


## The stroke buffer takes the active layer's scale when the stroke begins, and
## a plain layer's stroke after it is made at 1.0 again.
func test_the_stroke_buffer_follows_the_active_layer() -> void:
    _open(2.0)
    var doc := _surface.get_document()
    doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    assert_eq(doc.stroke_layer.resolution_scale, 2.0, "the buffer is at 2.0 under a double resolution layer")
    doc.stroke_transaction.reset()
    SaLayerOps.new(doc).add(&"", null, 1.0)
    doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    assert_eq(doc.stroke_layer.resolution_scale, 1.0, "and at 1.0 under a plain one")
    doc.stroke_transaction.reset()
