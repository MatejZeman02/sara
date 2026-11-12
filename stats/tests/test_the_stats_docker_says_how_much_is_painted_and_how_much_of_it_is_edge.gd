## The Stats docker says how much is painted and how much of it is edge.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The row's Done lines: a fresh document reads nothing painted and a layer
## painted over a quarter of the canvas a quarter, within one per cent, and a
## flat fill reads no edge, a hard edged square more than the same square
## blurred, and a square whose edge lies along a chunk border the same as one
## whose edge lies inside a chunk, within one per cent. So the suite paints on a
## real easel of two chunks by two, and the part's reduction runs through a
## service of its own when a real idle clock fires, read back at once so an
## assertion can follow it. Then the fold that reads a chunk's neighbours
## again, the background each kind of document is told against, and the rows.
extends "res://tests/test_framework.gd"

## Real composites and the real kernel over them.
const REQUIRES_GPU := true

const Coverage := preload("../coverage_and_edges.gd")

## Two chunks by two, so a quarter of the canvas is one chunk.
const SIZE := Vector2i(512, 512)

## A square of 128 texels a side, inside the first chunk, with its right and
## bottom edges along that chunk's borders, and with its left and top edges
## along the last chunk's.
const INSIDE := Rect2i(64, 64, 128, 128)
const ENDING_ON_A_BORDER := Rect2i(128, 128, 128, 128)
const STARTING_ON_A_BORDER := Rect2i(256, 256, 128, 128)

var _easel: SaEasel = null
var _clock: SaIdleClock = null
var _service: SaReductionService = null
var _part: Coverage = null


func before_each() -> void:
    _easel = SaEasel.create_default(SIZE, null, SaColorSpace.srgb())
    _easel.process_pending_composite()
    _clock = SaIdleClock.new()
    _clock.follow_settings = false
    _clock.follow_main = false
    _clock.idle_seconds = 1.0
    _clock.attach(_easel.document)
    _service = SaReductionService.new()
    _service.watch(_easel)
    _service.listen(_clock)
    _part = Coverage.new()
    _numbers().read_at_once = true


func after_each() -> void:
    _numbers().let_go()
    _part = null
    _service.free()
    _clock.free()
    _easel.free()


func _numbers() -> SaReductionService.OverDocument:
    return _part.reduction as SaReductionService.OverDocument


## The document becomes a transparent one of the same size, holding no chunk.
func _transparent() -> void:
    var background := SaDocumentBackground.default_choice()
    background[SaDocumentBackground.KIND] = SaDocumentBackground.TRANSPARENT
    _easel.document.reset_to_default(SIZE, SaColorSpace.srgb(), SaDocument.DEFAULT_DPI, background)
    assert_not_null(_easel.resize_output(SIZE), "the output is the canvas's size")
    assert_true(_easel.document.active_layer.chunks.is_empty(), "The transparent document holds no chunk")


## Paints the chunk at *grid_pos* of the paint layer one colour and tells the
## document, the way a dab inside one chunk does.
func _paint_chunk(grid_pos: Vector2i, colour: Color) -> void:
    var document := _easel.document
    document.active_layer.get_or_create_chunk(grid_pos).clear(colour)
    document.invalidate_chunk_regions({grid_pos: Rect2i(Vector2i.ZERO, Vector2i.ONE * SaLayer.CHUNK_SIZE)})


## Paints *square* in black on the paint layer, hard edged, or blurred by a
## Gaussian of *sigma* texels as a blur filter would leave it, into every chunk
## it reaches and nowhere else.
func _paint_square(square: Rect2i, sigma: float = 0.0) -> void:
    var document := _easel.document
    var side := SaLayer.CHUNK_SIZE
    var spread := ceili(sigma * 3.0)
    var across_x := _blurred(square.position.x, square.end.x, sigma)
    var across_y := _blurred(square.position.y, square.end.y, sigma)
    var regions: Dictionary[Vector2i, Rect2i] = {}
    for grid_pos: Vector2i in SaLayer.grid_positions(SIZE):
        var chunk_rect := Rect2i(grid_pos * side, Vector2i.ONE * side)
        if not chunk_rect.intersects(square.grow(spread)):
            continue
        var texture := document.active_layer.get_or_create_chunk(grid_pos).albedo()
        var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
        var image := Image.create_empty(side, side, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
        image.fill(Color(0, 0, 0, 0))
        for y in side:
            for x in side:
                var alpha := across_x[chunk_rect.position.x + x] * across_y[chunk_rect.position.y + y]
                if alpha > 0.0:
                    image.set_pixel(x, y, Color(0, 0, 0, alpha))
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
        regions[grid_pos] = Rect2i(Vector2i.ZERO, Vector2i.ONE * side)
    document.invalidate_chunk_regions(regions)


## How much of each texel across the canvas a span from *from* to *to* covers
## once a Gaussian of *sigma* texels has blurred it, wholly inside and not at
## all outside for none. A blur is separable, so a square is two of these.
static func _blurred(from: int, to: int, sigma: float) -> PackedFloat64Array:
    var out := PackedFloat64Array()
    out.resize(SIZE.x)
    var spread := ceili(sigma * 3.0)
    var weights := PackedFloat64Array()
    var whole := 0.0
    for tap in range(-spread, spread + 1):
        var weight := exp(-tap * tap / (2.0 * sigma * sigma)) if sigma > 0.0 else 1.0
        weights.append(weight)
        whole += weight
    for at in SIZE.x:
        var sum := 0.0
        for tap in range(-spread, spread + 1):
            var from_texel := at + tap
            if from_texel >= from and from_texel < to:
                sum += weights[tap + spread]
        out[at] = sum / whole
    return out


## The painter stops, and the service runs what is registered.
func _stop() -> bool:
    _clock.note_edit()
    return _clock.tick(_clock.idle_seconds)


## Runs the part once and answers the reduction's total.
func _total() -> PackedInt64Array:
    _service.add(_part.reduction)
    assert_true(_stop(), "The clock fires")
    return _numbers().total


func _painted() -> float:
    return Coverage.painted_share(_total(), SIZE.x * SIZE.y)


func _edge() -> float:
    return Coverage.edge_share(_total())


## The edge share of *square* painted alone on a fresh document, grey or
## transparent, hard edged or blurred by a Gaussian of *sigma* texels.
func _edge_of(square: Rect2i, sigma: float = 0.0, transparent: bool = false) -> float:
    after_each()
    before_each()
    if transparent:
        _transparent()
    _paint_square(square, sigma)
    return _edge()


func test_a_fresh_document_reads_nothing_painted() -> void:
    assert_true(_easel.document.active_layer.chunks.is_empty(), "A fresh document's paint layer is empty")
    assert_eq(_painted(), 0.0, "A fresh document on its grey reads nothing painted")
    assert_eq(_numbers().dispatched.size(), 4, "though the Background holds and is read over every chunk")
    assert_eq(Coverage.edge_share(_numbers().total), 0.0, "and no edge")
    after_each()
    before_each()
    _transparent()
    assert_eq(_painted(), 0.0, "A fresh transparent document reads nothing painted")
    assert_true(_numbers().dispatched.is_empty(), "and nothing is dispatched over a canvas no layer holds")


func test_a_layer_painted_over_a_quarter_of_the_canvas_reads_a_quarter() -> void:
    _paint_chunk(Vector2i(1, 0), Color(0.8, 0.2, 0.1))
    var share := _painted()
    assert_true(absf(share - 0.25) <= 0.01, "A quarter painted on the grey reads 25 per cent, read %.4f" % share)
    after_each()
    before_each()
    _transparent()
    _paint_chunk(Vector2i(0, 1), Color(0.5, 0.5, 0.5, 0.4))
    share = _painted()
    assert_true(absf(share - 0.25) <= 0.01, "and a quarter of see-through grey on a transparent one, read %.4f" % share)
    assert_eq(_numbers().dispatched, [Vector2i(0, 1)] as Array[Vector2i], "read over the one chunk painted")


func test_a_flat_fill_reads_no_edge() -> void:
    _easel.document.fill_layer(Color(0.3, 0.6, 0.2))
    assert_true(is_equal_approx(_painted(), 1.0), "A flat fill paints the whole canvas")
    assert_eq(Coverage.edge_share(_numbers().total), 0.0, "and holds no edge, its chunk borders and the canvas's none")


func test_a_hard_edged_square_reads_more_edge_than_the_same_square_blurred() -> void:
    for transparent: bool in [false, true]:
        var on := "a transparent document" if transparent else "the grey"
        var hard := _edge_of(INSIDE, 0.0, transparent)
        var blurred := _edge_of(INSIDE, 3.0, transparent)
        var painted := Coverage.painted_share(_numbers().total, SIZE.x * SIZE.y)
        assert_true(hard > 0.0, "On %s a hard edged square has edge, read %.4f" % [on, hard])
        assert_true(blurred > 0.0, "and so does the same square blurred, read %.4f" % blurred)
        assert_true(hard > blurred * 2.0, "but the hard one well more, read %.4f and %.4f" % [hard, blurred])
        var square := float(INSIDE.size.x * INSIDE.size.y) / float(SIZE.x * SIZE.y)
        assert_true(painted > square, "The blurred one paints past the square, read %.4f" % painted)


func test_a_square_along_a_chunk_border_reads_as_one_inside_a_chunk() -> void:
    for transparent: bool in [false, true]:
        var on := "a transparent document" if transparent else "the grey"
        var inside := _edge_of(INSIDE, 0, transparent)
        var ending := _edge_of(ENDING_ON_A_BORDER, 0, transparent)
        var starting := _edge_of(STARTING_ON_A_BORDER, 0, transparent)
        var painted := Coverage.painted_share(_numbers().total, SIZE.x * SIZE.y)
        assert_true(inside > 0.0, "On %s the square inside a chunk has edge, read %.4f" % [on, inside])
        var said := "On %s, ending on a chunk border reads %.5f against %.5f inside" % [on, ending, inside]
        assert_true(absf(ending - inside) <= inside * 0.01, said)
        said = "and starting on one reads %.5f against %.5f" % [starting, inside]
        assert_true(absf(starting - inside) <= inside * 0.01, said)
        var square := float(INSIDE.size.x * INSIDE.size.y) / float(SIZE.x * SIZE.y)
        assert_true(is_equal_approx(painted, square), "with the square's own share painted, read %.5f" % painted)


## The square ends on the first chunk's right border. Black painted over the
## whole chunk beside it takes that edge away, and the first chunk's tally,
## whose border texels read into the second, is read again.
func test_painting_beside_a_chunk_reads_that_chunk_again() -> void:
    _transparent()
    _paint_square(ENDING_ON_A_BORDER)
    var alone := _total().duplicate()
    assert_eq(_numbers().dispatched, [Vector2i(0, 0)] as Array[Vector2i], "The square's chunk is read")
    _paint_chunk(Vector2i(1, 0), Color.BLACK)
    var folded := _total().duplicate()
    var read := _numbers().dispatched.duplicate()
    read.sort()
    assert_eq(read, [Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i], "The painted chunk and the one beside it are read")
    var fresh := Coverage.new()
    var numbers := fresh.reduction as SaReductionService.OverDocument
    numbers.read_at_once = true
    _service.add(numbers)
    assert_true(_stop(), "The clock fires again")
    assert_eq(folded, numbers.total, "The fold equals a reduction over every painted chunk afresh")
    numbers.let_go()
    var painted := alone[Coverage.CELL_PAINTED] + SaLayer.CHUNK_SIZE * SaLayer.CHUNK_SIZE
    assert_eq(folded[Coverage.CELL_PAINTED], painted, "The square and the chunk beside it are painted")
    assert_true(Coverage.edge_share(folded) > 0.0, "and black beside the square still meets the canvas")


func test_the_background_is_what_the_bottom_of_the_stack_shows() -> void:
    var document := _easel.document
    var laid := Coverage.Background.new(document)
    assert_true(laid.laid, "A document laid on grey is laid")
    assert_eq(laid.first, document.background_fill(), "on the colour it was laid in")
    assert_eq(laid.second, laid.first, "and a plain colour has no second")
    (document.get_child(0) as SaLayer).visible = false
    assert_false(Coverage.Background.new(document).laid, "With the Background hidden the canvas shows through")
    _transparent()
    assert_false(Coverage.Background.new(_easel.document).laid, "A transparent document is laid on nothing")


func test_the_rows_show_the_painted_share_and_the_edge_as_percentages() -> void:
    var page := SaPage.new(_part.declare)
    page.declare_rows()
    var box := VBoxContainer.new()
    page.realize(box)
    var painted := page.row(&"painted")
    var edge := page.row(&"edge_density")
    assert_eq(painted.value, 0.0, "Before a run nothing is painted")
    assert_eq((painted.control as Label).text, "0.0 %", "and it says so")
    _paint_square(INSIDE)
    _service.add(_part.reduction)
    assert_true(_stop(), "The clock fires")
    _part.follow(_easel.document)
    assert_eq(painted.value, 6.25, "The painted row reads the square's 6.25 per cent")
    assert_eq((painted.control as Label).text, "6.3 %", "and shows it to a place")
    assert_true(float(edge.value) > 0.0, "The edge row reads above nought, read %s" % str(edge.value))
    assert_false((painted.control as Label).tooltip_text.is_empty(), "How painted is told is on hover")
    assert_false((edge.control as Label).tooltip_text.is_empty(), "and what counts as edge")
    box.free()


func test_the_rows_ask_for_frames_while_the_tally_is_on_its_way() -> void:
    var page := SaPage.new(_part.declare)
    page.declare_rows()
    var box := VBoxContainer.new()
    page.realize(box)
    var painted := page.row(&"painted")
    var words := painted.control as Coverage.Readout
    _numbers().read_at_once = false
    _paint_chunk(Vector2i(0, 0), Color.BLACK)
    _service.add(_part.reduction)
    assert_true(_stop(), "The clock fires")
    assert_true(_numbers().waiting > 0, "The run asked the device for its tally")
    _part.follow(_easel.document)
    assert_eq(painted.value, 0.0, "The rows wait for the answer")
    assert_true(words.is_processing(), "and their words ask for a frame each frame meanwhile")
    for frame in 8:
        if _numbers().waiting == 0:
            break
        words.notification(Node.NOTIFICATION_PROCESS)
        RenderingServer.force_draw(false, 0.0)
    assert_eq(_numbers().waiting, 0, "The device answered within a few frames")
    words.notification(Node.NOTIFICATION_PROCESS)
    assert_false(words.is_processing(), "and the asking stops once it is in")
    _part.follow(_easel.document)
    assert_eq(painted.value, 25.0, "Then the rows show what came back")
    box.free()
