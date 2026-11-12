## The wand's flood waits on the card once a batch of rounds rather than once
## a round.
##
## A read of the flag buffer is a wait on the card before the CPU knows which
## chunks to sweep next, and on a part that shares the CPU's memory each wait
## was the stall the laptop measured. A batch sweeps what is due and then two
## rings of chunks made ahead of the front, so a flood that crosses the canvas
## reaches it in fewer reads, and a ring it never reached leaves no chunk
## behind in the selection.
##
## The picture is `perf-repeat.json`'s before its `wand-2` click, drawn with
## fills: a canvas of one colour on a 1920 by 1080 document with a band of
## another across it, clicked below the band, so the region wraps round both
## ends and reaches all 40 chunks.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const GROUND := Color(0.8, 0.35, 0.2, 1.0)
const BAND := Color(0.125, 0.314, 0.753, 1.0)
const CANVAS := Vector2i(1920, 1080)
const START := Vector2i(400, 700)

## The reads the click is held under. Before the batches the flood read the
## card once a round, 11 times on this picture and 12 on the scenario's
## `wand-2`, and with them it reads 6 and 5. The bound is one over this
## picture's figure, so a change that takes the batches away fails it while
## a band a step different does not.
const READS_BOUND := 7

var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _easel = SaEasel.create_default(CANVAS)
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


func _paint_rect(rect: Rect2i, color: Color) -> void:
    _doc.selection.select_rect(rect)
    _doc.fill_layer(color, _doc.active_layer)
    _doc.selection.deselect()


## The ground over the whole canvas and the band from (300, 250) to
## (1600, 850) in steps of 50 texels, 80 across, the stroke of the scenario
## drawn as a staircase.
func _paint_picture() -> void:
    _paint_rect(Rect2i(Vector2i.ZERO, CANVAS), GROUND)
    for i in 27:
        var at := Vector2i(300, 250) + Vector2i(roundi(1300.0 * i / 26.0), roundi(600.0 * i / 26.0))
        _paint_rect(Rect2i(at - Vector2i(40, 40), Vector2i(80, 80)), BAND)


func _coverage(at: Vector2i) -> float:
    var grid_pos := Vector2i(floori(at.x / float(SaChunk.SIZE)), floori(at.y / float(SaChunk.SIZE)))
    var chunk: SaChunk = _doc.selection.chunks.get(grid_pos, null)
    if chunk == null:
        return 0.0
    var texture := chunk.field(SaSelection.FIELD)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return bytes.decode_float(((at.y % SaChunk.SIZE) * texture.size.x + at.x % SaChunk.SIZE) * 4)


func test_a_click_that_reaches_the_whole_canvas_reads_the_card_a_handful_of_times() -> void:
    _paint_picture()
    var wand := SaWand.new()
    SaCompute.reset_counters()
    var reached := wand.flood(_doc, START, 0.05, SaSelection.Mode.REPLACE, null, _doc.active_layer)
    var rounds := int((SaCompute.kernel_counters().get("wand/sweep_rows", {}) as Dictionary).get("lists", 0))
    assert_eq(reached, 40, "The region wraps round the band and reaches every chunk of the canvas")
    assert_true(wand.reads <= READS_BOUND, "and the flood waited on the card %d times, at most %d" % [wand.reads, READS_BOUND])
    assert_true(rounds > wand.reads, "over %d rounds, more than one a read" % rounds)
    assert_eq(_coverage(Vector2i(1850, 60)), 1.0, "The far corner beyond the band's top end is selected")
    assert_eq(_coverage(Vector2i(60, 1020)), 1.0, "and the near one below its start")
    assert_eq(_coverage(Vector2i(950, 550)), 0.0, "and the band itself is not")


func test_a_region_inside_one_chunk_reads_twice_and_keeps_one_chunk() -> void:
    _paint_rect(Rect2i(Vector2i.ZERO, CANVAS), GROUND)
    _paint_rect(Rect2i(600, 300, 60, 60), BAND)
    var wand := SaWand.new()
    var reached := wand.flood(_doc, Vector2i(630, 330), 0.05, SaSelection.Mode.REPLACE, null, _doc.active_layer)
    assert_eq(reached, 1, "A square inside one chunk is a region of one chunk")
    assert_eq(_doc.selection.chunks.size(), 1, "and the rings made ahead of it left no chunk in the selection")
    assert_eq(wand.reads, 2, "One read finds the square, and the second finds it settled")
    assert_eq(_coverage(Vector2i(659, 359)), 1.0, "Its far corner is selected")
    assert_eq(_coverage(Vector2i(660, 330)), 0.0, "and the ground beside it is not")


func test_a_ring_the_flood_reached_in_its_batch_joins_the_region() -> void:
    # A strip of the band's colour three chunks long from the seed's chunk
    # rightwards, ground on every side, so the flood reaches the chunks
    # a batch made ahead of it and nothing past them.
    _paint_rect(Rect2i(Vector2i.ZERO, CANVAS), GROUND)
    _paint_rect(Rect2i(0, 260, 760, 240), BAND)
    var wand := SaWand.new()
    var reached := wand.flood(_doc, Vector2i(10, 300), 0.05, SaSelection.Mode.REPLACE, null, _doc.active_layer)
    assert_eq(reached, 3, "The strip is three chunks, the seed's and two made ahead of it")
    assert_eq(_doc.selection.chunks.size(), 3, "and the selection holds those three and nothing the rings touched past them")
    assert_eq(_coverage(Vector2i(759, 499)), 1.0, "The strip's far corner is selected")
    assert_eq(_coverage(Vector2i(760, 300)), 0.0, "and the ground past its end is not")
    assert_eq(wand.reads, 2, "and a strip the rings covered is found in one read and settled in the second")
