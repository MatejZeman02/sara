## The wand's sweep works on bits and never on colours: a chunk joining the
## flood is tested against the seed once, by `classify`, and every sweep after
## reads the passable bits it left and settles the chunk in one workgroup.
##
## A sweep that read the colours itself read each texel several times in every
## dispatch, and the laptop's Intel part spent most of a click there. So the
## counters are what this holds: one `classify` a chunk however often the chunk
## is swept, one workgroup a chunk a sweep, and one `unpack` a chunk of the
## region at the end. A maze inside one chunk, whose corridor doubles back
## many times, is where a settle that stopped early or a seam carried wrong
## would leave the far end unselected.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const GROUND := Color(0.8, 0.35, 0.2, 1.0)
const BAND := Color(0.125, 0.314, 0.753, 1.0)
const WALL := Color(0.0, 0.0, 1.0, 1.0)
const CANVAS := Vector2i(1920, 1080)
const START := Vector2i(400, 700)

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


## The ground and the band of `perf-repeat.json`'s `wand-2`, drawn as a
## staircase of squares.
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


func _counter(kernel: String, key: String) -> int:
    return int((SaCompute.kernel_counters().get("wand/" + kernel, {}) as Dictionary).get(key, 0))


func test_a_chunk_is_classified_once_however_often_it_is_swept() -> void:
    _paint_picture()
    SaCompute.reset_counters()
    var reached := SaWand.new().flood(_doc, START, 0.05, SaSelection.Mode.REPLACE, null, _doc.active_layer)
    assert_eq(reached, 40, "The ground wraps round the band and reaches every chunk of the canvas")
    assert_eq(_counter("classify", "dispatches"), 40, "and each of the 40 is classified once")
    assert_true(
        _counter("sweep_rows", "dispatches") > 2 * 40,
        "while the sweeps visit them %d times, each chunk more than twice" % _counter("sweep_rows", "dispatches")
    )
    assert_eq(_counter("sweep_rows", "workgroups"), _counter("sweep_rows", "dispatches"), "A sweep is one workgroup a chunk")
    assert_eq(_counter("unpack", "dispatches"), 40, "and the region is unpacked into its masks once at the end")
    assert_eq(_coverage(Vector2i(1850, 60)), 1.0, "The far corner beyond the band's top end is selected")
    assert_eq(_coverage(Vector2i(950, 550)), 0.0, "and the band itself is not")


## Walls across one chunk, each open at alternate ends, so the corridor runs
## right, down, left, down and so on. A row pass alone crosses one leg, and the
## settle has to alternate rows and columns once a leg to reach the far end.
func test_a_maze_inside_one_chunk_settles_in_its_own_sweep() -> void:
    _paint_rect(Rect2i(Vector2i.ZERO, CANVAS), GROUND)
    for leg in 15:
        var y := 16 * leg + 15
        var gap_left := leg % 2 == 1
        _paint_rect(Rect2i(Vector2i(4 if gap_left else 0, y), Vector2i(251, 1)), WALL)
    _paint_rect(Rect2i(Vector2i(255, 0), Vector2i(1, 256)), WALL)
    _paint_rect(Rect2i(Vector2i(0, 255), Vector2i(256, 1)), WALL)
    var wand := SaWand.new()
    SaCompute.reset_counters()
    var reached := wand.flood(_doc, Vector2i(2, 2), 0.05, SaSelection.Mode.REPLACE, null, _doc.active_layer)
    assert_eq(reached, 1, "The maze is walled into its chunk")
    assert_eq(wand.reads, 2, "One read finds it settled after the seed's round, and the second finds nothing due")
    assert_eq(_coverage(Vector2i(250, 250)), 1.0, "The corridor's far end is selected")
    assert_eq(_coverage(Vector2i(128, 15)), 0.0, "and a wall is not")
