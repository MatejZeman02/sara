## With the infinite canvas on, the page grows by whole chunks as a stroke
## nears an edge, one undo takes back a stroke and its growth together, and
## with it off the fixed-page rule stands.
##
## The strokes go through the brush tool on a suite's surface as
## `test_a_stroke_off_the_canvas_stores_no_chunk_past_its_edge.gd` draws its
## own, so the grow is met where a painter meets it, from the paint context's
## first target. The fake view reads its pointer in the document's pixels as
## they are now, so a pointer that keeps still on screen while the page grows
## at the top reads further down, which the walk up adds back the way a real
## view does by itself.
extends "res://tests/test_framework.gd"

## The strokes dispatch real dabs and the context allocates real chunks.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## The scenario's page, four by four chunks.
const CANVAS := Vector2i(1024, 1024)
const CENTRE := Vector2(512.0, 512.0)
## How far past an edge each stroke goes, the note's 600 pixels.
const PAST := 600.0
const STEP := 20.0
const RADIUS := 16.0

var _surface: SaSurface
var _machine: ToolMachine
var _doc: SaDocument
var _brush: Object


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    _machine = Fixtures.make_bound_machine(_surface)
    _doc = _surface.easel.document
    _machine.set_active_tool(&"brush")
    _brush = _machine.active_tool
    _brush.is_tablet = false
    _brush.settings.stabilizer_amount = 0.0
    _brush.settings.radius = RADIUS / CANVAS.y


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null
    _brush = null


func _button(pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    _brush.handle_input(event)


## Puts the pointer at *at*, in the press's frame, where the document's pixels
## are now, as a pointer held still on screen reads after a grow at the top.
func _point(at: Vector2) -> void:
    _surface.view.mouse_position = at + Vector2(_doc.infinite_canvas.shift)


func _move(at: Vector2) -> void:
    _point(at)
    var event := InputEventMouseMotion.new()
    event.pressure = 1.0
    _brush.handle_input(event)


## One stroke from the centre to *to*, in steps of `STEP`, and its release.
func _stroke(to: Vector2) -> void:
    _point(CENTRE)
    _button(true)
    var steps := ceili(CENTRE.distance_to(to) / STEP)
    for index in range(1, steps + 1):
        _move(CENTRE.lerp(to, float(index) / float(steps)))
    _button(false)


## Every grid position *layer* stores wholly outside the page.
func _outside(layer: SaLayer) -> Array[Vector2i]:
    var page := Rect2(Vector2.ZERO, Vector2(_doc.canvas_size))
    var size := float(SaLayer.CHUNK_SIZE)
    var found: Array[Vector2i] = []
    for grid_pos: Vector2i in layer.chunks:
        if not page.intersects(Rect2(Vector2(grid_pos) * size, Vector2(size, size))):
            found.append(grid_pos)
    return found


## The grid positions *layer* stores, sorted.
static func _keys(layer: SaLayer) -> Array[Vector2i]:
    var keys: Array[Vector2i] = []
    for grid_pos: Vector2i in layer.chunks:
        keys.append(grid_pos)
    keys.sort()
    return keys


## The grid position under *point*, in document pixels.
static func _grid(point: Vector2) -> Vector2i:
    return Vector2i((point / float(SaLayer.CHUNK_SIZE)).floor())


func test_a_stroke_past_the_right_edge_then_one_past_the_top_grow_the_page_by_whole_chunks() -> void:
    _doc.infinite_canvas.on = true
    var layer := _doc.active_layer
    var edge := SaLayer.CHUNK_SIZE

    _stroke(CENTRE + Vector2(CANVAS.x / 2.0 + PAST, 0.0))
    var after_right := _doc.canvas_size
    assert_eq(after_right.y, CANVAS.y, "A stroke to the right leaves the height")
    assert_eq(after_right.x % edge, 0, "and grows the width by whole chunks")
    assert_true(after_right.x >= CANVAS.x + PAST + RADIUS + edge, "to a chunk past the stroke's far end, %d" % after_right.x)
    assert_eq(_doc.infinite_canvas.shift, Vector2i.ZERO, "A grow on the right moves no origin")
    var right_end := Vector2(CANVAS.x + PAST, CENTRE.y)
    assert_true(layer.chunks.has(_grid(right_end)), "The layer holds the chunk under the right stroke's far end")
    var first_keys := _keys(layer)

    _stroke(CENTRE - Vector2(0.0, CANVAS.y / 2.0 + PAST))
    var grown := _doc.canvas_size
    var rows := floori((grown.y - CANVAS.y) / float(edge))
    assert_eq(grown.x, after_right.x, "A stroke up leaves the width")
    assert_eq((grown.y - CANVAS.y) % edge, 0, "and grows the height by whole chunks")
    assert_true(grown.y - CANVAS.y >= PAST + RADIUS + edge, "to a chunk above the stroke's far end, %d" % grown.y)
    assert_eq(_doc.infinite_canvas.shift, Vector2i.ZERO, "and the shift is spent with the stroke")
    var moved := Vector2(0.0, rows * edge)
    assert_true(layer.chunks.has(_grid(right_end + moved)), "The first stroke's far end moved down by the rows added")
    assert_true(layer.chunks.has(_grid(Vector2(CENTRE.x, -PAST) + moved)), "and the top stroke's far end is on the page")
    assert_eq(_outside(layer), [] as Array[Vector2i], "Nothing is stored past the grown page")
    var column := _grid(CENTRE + moved).x
    var missing: Array[int] = []
    for row in range(_grid(Vector2(CENTRE.x, -PAST) + moved).y, _grid(CENTRE + moved).y + 1):
        if not layer.chunks.has(Vector2i(column, row)):
            missing.append(row)
    assert_eq(missing, [] as Array[int], "and the top stroke is whole, painted before each grow as after it")

    assert_true(_doc.undo(), "One undo")
    assert_eq(_doc.canvas_size, after_right, "gives back the second stroke's growth")
    assert_eq(_keys(layer), first_keys, "and the layer holds the first stroke's chunks at their keys and nothing more")
    assert_true(_doc.undo(), "A second undo")
    assert_eq(_doc.canvas_size, CANVAS, "gives back the first")
    assert_eq(_outside(layer), [] as Array[Vector2i], "and nothing is stored past the page it gave back")

    assert_true(_doc.redo(), "A redo")
    assert_eq(_doc.canvas_size, after_right, "puts the first growth back")
    assert_true(layer.chunks.has(_grid(right_end)), "with the stroke on it")
    assert_true(_doc.redo(), "and a second redo")
    assert_eq(_doc.canvas_size, grown, "the second")
    assert_true(layer.chunks.has(_grid(right_end + moved)), "with the first stroke moved down again")


## The switch off is Sara as before: the page keeps its size and a stroke past
## the edge stores no chunk wholly outside it.
func test_with_the_switch_off_the_page_keeps_its_size_and_d2_stands() -> void:
    assert_false(_doc.infinite_canvas.on, "A new document has the switch off")
    _stroke(CENTRE + Vector2(CANVAS.x / 2.0 + PAST, 0.0))
    _stroke(CENTRE - Vector2(0.0, CANVAS.y / 2.0 + PAST))
    assert_eq(_doc.canvas_size, CANVAS, "The page keeps its size")
    assert_eq(_doc.infinite_canvas.grows, 0, "and never grew")
    assert_eq(_outside(_doc.active_layer), [] as Array[Vector2i], "No chunk is stored wholly outside it")
    assert_true(_doc.active_layer.chunks.has(Vector2i(3, 2)), "and the chunk the edge crosses was painted")


## A stroke that stays a chunk inside every edge grows nothing.
func test_a_stroke_inside_the_page_grows_nothing() -> void:
    _doc.infinite_canvas.on = true
    _stroke(CENTRE + Vector2(200.0, 0.0))
    assert_eq(_doc.canvas_size, CANVAS, "The page keeps its size")
    assert_eq(_doc.infinite_canvas.grows, 0, "and never grew")


## A region asked about with no stroke open, a hover's or a filter's, grows
## nothing even with the switch on.
func test_no_grow_without_a_stroke() -> void:
    _doc.infinite_canvas.on = true
    var regions: Array[Rect2] = [Rect2(1000.0, 500.0, 40.0, 40.0)]
    assert_eq(SaInfiniteCanvas.reach(_doc, regions), Vector2i.ZERO, "No origin moves")
    assert_eq(_doc.canvas_size, CANVAS, "and the page keeps its size")
