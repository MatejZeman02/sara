## The wand's sweep, a chunk settled as bits by the threads of one workgroup,
## held to a flood the CPU works out texel by texel.
##
## A row is filled a word of 32 texels at a time with the carry passed from
## word to word, and a column of words in pieces chained through workgroup
## memory. A carry that went wrong at a word's edge, at a chunk
## seam or at the canvas's edge would leave a texel of the region unselected or
## select one it cannot reach, and a region shaped like a corridor that doubles
## back through every chunk is where both would show. The maze here is walls
## on a transparent layer, so the answer is a flood over a grid of booleans.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const WALL := Color(0.0, 0.0, 1.0, 1.0)

## Neither side a whole number of chunks, so the right and bottom chunks are
## part canvas and a line is shorter than the chunk.
const CANVAS := Vector2i(600, 300)

## Where the flood starts, in the corridor above the first wall.
const START := Vector2i(5, 5)

var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _easel = SaEasel.create_default(CANVAS)
    _doc = _easel.document
    SaCompute.reset_counters()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


## Seven walls across the canvas, each open at one end and the next at the
## other, so the corridor between them runs back and forth through all six
## chunks. Posts stand in every corridor on both chunk seams and on span edges
## either side of them, and a closed box sits in the second corridor with
## nothing of the flood's colour able to reach its inside.
func _walls() -> Array[Rect2i]:
    var walls: Array[Rect2i] = []
    for i in 7:
        var y := 30 + 40 * i
        walls.append(Rect2i(0, y, 590, 4) if i % 2 == 0 else Rect2i(10, y, 590, 4))
        for x: int in [127, 253, 256, 259, 511, 516]:
            walls.append(Rect2i(x, y + 4 + (i % 3) * 6, 2, 20))
    walls.append_array([Rect2i(300, 40, 20, 2), Rect2i(300, 58, 20, 2), Rect2i(300, 40, 2, 20), Rect2i(318, 40, 2, 20)])
    return walls


func _paint(walls: Array[Rect2i]) -> void:
    for wall in walls:
        _doc.selection.select_rect(wall)
        _doc.fill_layer(WALL, _doc.active_layer)
        _doc.selection.deselect()


## Every texel four-connected to *start* through texels no wall covers, one
## byte a texel, row by row.
static func _reference(walls: Array[Rect2i], start: Vector2i) -> PackedByteArray:
    var blocked := PackedByteArray()
    blocked.resize(CANVAS.x * CANVAS.y)
    for wall in walls:
        for y in range(wall.position.y, mini(wall.end.y, CANVAS.y)):
            for x in range(wall.position.x, mini(wall.end.x, CANVAS.x)):
                blocked[y * CANVAS.x + x] = 1
    var reached := PackedByteArray()
    reached.resize(CANVAS.x * CANVAS.y)
    var queue := PackedInt32Array([start.y * CANVAS.x + start.x])
    reached[queue[0]] = 1
    var head := 0
    while head < queue.size():
        var at := queue[head]
        head += 1
        var x := at % CANVAS.x
        @warning_ignore("integer_division")
        var y := at / CANVAS.x
        for step: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
            var nx := x + step.x
            var ny := y + step.y
            if nx < 0 or ny < 0 or nx >= CANVAS.x or ny >= CANVAS.y:
                continue
            var next := ny * CANVAS.x + nx
            if blocked[next] == 1 or reached[next] == 1:
                continue
            reached[next] = 1
            queue.append(next)
    return reached


## The texels of the canvas whose mask and *expected* disagree.
func _mismatches(expected: PackedByteArray) -> int:
    var rd := GlobalShaderCompiler.get_rd()
    var wrong := 0
    for gy in ceili(float(CANVAS.y) / SaChunk.SIZE):
        for gx in ceili(float(CANVAS.x) / SaChunk.SIZE):
            var chunk: SaChunk = _doc.selection.chunks.get(Vector2i(gx, gy), null)
            var texture: SaTexture = chunk.field(SaSelection.FIELD) if chunk != null else null
            var bytes := rd.texture_get_data(texture.rid, 0) if texture != null else PackedByteArray()
            for ly in SaChunk.SIZE:
                var y := gy * SaChunk.SIZE + ly
                if y >= CANVAS.y:
                    break
                for lx in SaChunk.SIZE:
                    var x := gx * SaChunk.SIZE + lx
                    if x >= CANVAS.x:
                        break
                    var selected := not bytes.is_empty() and bytes.decode_float((ly * texture.size.x + lx) * 4) >= 0.5
                    if selected != (expected[y * CANVAS.x + x] == 1):
                        wrong += 1
    return wrong


func test_a_corridor_through_every_chunk_is_selected_texel_for_texel() -> void:
    var walls := _walls()
    _paint(walls)
    var reached := SaWand.new().flood(_doc, START, 0.05, SaSelection.Mode.REPLACE, null, _doc.active_layer)
    assert_eq(reached, 6, "The corridor runs through all six chunks")
    var expected := _reference(walls, START)
    assert_eq(expected[45 * CANVAS.x + 310], 0, "The box's inside is out of the corridor's reach")
    assert_eq(_mismatches(expected), 0, "and the mask is the CPU's flood to the texel, box and posts included")


func test_a_round_records_one_list_a_direction() -> void:
    _paint(_walls())
    SaCompute.reset_counters()
    SaWand.new().flood(_doc, START, 0.05, SaSelection.Mode.REPLACE, null, _doc.active_layer)
    var rows: Dictionary = SaCompute.kernel_counters().get("wand/sweep_rows", {})
    var columns: Dictionary = SaCompute.kernel_counters().get("wand/sweep_columns", {})
    assert_true(int(rows.get("lists", 0)) > 0, "The flood swept the rows")
    assert_eq(int(rows.get("lists", 0)), int(columns.get("lists", 0)), "and the columns in as many lists, one a round each")
    assert_true(
        int(rows.get("dispatches", 0)) > int(rows.get("lists", 0)),
        "and a list holds every chunk of its round rather than one, so there is no barrier between two chunks"
    )
