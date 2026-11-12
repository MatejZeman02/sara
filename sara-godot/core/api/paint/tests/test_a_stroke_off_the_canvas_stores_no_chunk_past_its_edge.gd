## A stroke that leaves the canvas allocates no chunk wholly outside it.
##
## `SaPaintContext._build_targets` walked every grid position a dab's region
## covered, and with no selection every one of them was a target, so a stroke
## out of the canvas and back left chunks past the edge that nothing composites.
## A chunk the edge crosses stays a target and keeps its overhang, the way a
## crop keeps it, and a chunk wholly past the edge is skipped. The stroke's walk
## still measures the path, which the brush's own suite holds from its
## side and this one holds beside the count.
extends "res://tests/test_framework.gd"

## The stroke dispatches real dabs and the context allocates real chunks.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Two by two chunks, so the grid past the right edge starts at column two.
const CANVAS := Vector2i(512, 512)
const ROW := 128.0
const START_X := 100.0
## Three chunks past the right edge, as far as the scenario's probe reached.
const TURN_X := 1300.0
const STEP := 20.0


func _button(brush: Object, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    brush.handle_input(event)


func _move(surface: Object, brush: Object, x: float) -> void:
    surface.view.mouse_position = Vector2(x, ROW)
    var event := InputEventMouseMotion.new()
    event.pressure = 1.0
    brush.handle_input(event)


## Every grid position `layer` stores that lies wholly outside the canvas.
func _outside(layer: SaLayer) -> Array[Vector2i]:
    var canvas := Rect2(Vector2.ZERO, Vector2(CANVAS))
    var size := float(layer.CHUNK_SIZE)
    var found: Array[Vector2i] = []
    for grid_pos: Vector2i in layer.chunks:
        if not canvas.intersects(Rect2(Vector2(grid_pos) * size, Vector2(size, size))):
            found.append(grid_pos)
    return found


## Out along one row past the right edge and back, then the release, which
## commits the stroke buffer into the layer. The walk is read with the pen still
## down, because the release resets it.
func test_a_stroke_out_of_the_canvas_and_back_stores_only_the_canvas() -> void:
    var surface := Fixtures.make_surface(CANVAS)
    var machine := Fixtures.make_bound_machine(surface)
    var doc: SaDocument = surface.easel.document
    var layer := doc.active_layer
    machine.set_active_tool(&"brush")
    var brush: Object = machine.active_tool
    brush.is_tablet = false
    brush.settings.stabilizer_amount = 0.0
    brush.settings.radius = 16.0 / CANVAS.y

    surface.view.mouse_position = Vector2(START_X, ROW)
    _button(brush, true)
    var told := 0.0
    var previous := START_X
    var x := START_X
    while x < TURN_X:
        x += STEP
        _move(surface, brush, x)
        told += absf(x - previous)
        previous = x
    while x > START_X + STEP:
        x -= STEP
        _move(surface, brush, x)
        told += absf(x - previous)
        previous = x
    var walk: SaStrokeDistance = brush.stroke_distance
    var walked := walk.total_distance
    var slack := walk.spacing.distance.x + 2.0 * STEP
    var buffered := _outside(doc.stroke_layer)
    _button(brush, false)

    assert_eq(buffered, [] as Array[Vector2i], "The stroke buffer stored nothing past the edge")
    assert_eq(_outside(layer), [] as Array[Vector2i], "and the layer stored nothing past it after the commit")
    assert_true(layer.chunks.has(Vector2i(1, 0)), "The chunk the edge crosses was painted and kept")
    assert_true(
        absf(walked - told) <= slack,
        "The walk measured %.1f pixels of a %.1f pixel path, the path and not a chord" % [walked, told]
    )
    Fixtures.teardown(surface, machine)


## The context itself: a region across the edge answers the chunks the canvas
## reaches, one wholly past it answers none, and the left and top edges are
## edges too.
func test_the_context_answers_only_chunks_the_canvas_reaches() -> void:
    var easel := SaEasel.create_default(CANVAS)
    var doc := easel.document
    var across := SaPaintContext.for_region(doc, Rect2(500.0, 100.0, 40.0, 40.0), true)
    var grids: Array[Vector2i] = []
    for target in across.targets:
        grids.append(target.grid_pos)
    assert_eq(grids, [Vector2i(1, 0)] as Array[Vector2i], "A dab across the right edge targets the chunk inside only")
    assert_eq(SaPaintContext.for_region(doc, Rect2(700.0, 100.0, 40.0, 40.0), true).targets.size(), 0, "one past it none")
    assert_eq(SaPaintContext.for_region(doc, Rect2(-300.0, -300.0, 40.0, 40.0), true).targets.size(), 0, "nor above the left")
    var corner := SaPaintContext.for_region(doc, Rect2(-20.0, -20.0, 40.0, 40.0), true)
    assert_eq(corner.targets.size(), 1, "and a dab across the top left corner targets the one chunk it reaches")
    assert_eq(_outside(doc.active_layer), [] as Array[Vector2i], "The layer stored nothing outside")
    easel.free()
