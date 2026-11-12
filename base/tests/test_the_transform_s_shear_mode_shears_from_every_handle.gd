## The Transform's Shear mode shears from every handle.
##
## A corner under Shear must not scale the box as Normal does, or the mode adds
## nothing of its own beyond its edges. Every handle leans: an edge along itself as
## before, and a corner the edge it sits on along the drag's longer axis. The
## box stays a parallelogram of its area, which is what tells Shear from
## Perspective, whose corner drag makes any four sided shape.
##
## The picture is the scenario named after this suite,
## `the-transform-s-shear-mode-shears-from-every-handle`, whose `look`
## after a corner drag shows the painted picture leaned.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

## The selection the box stands on, so a drag lifts it.
const BOX := Rect2i(400, 384, 500, 400)

## How far every drag goes, in document pixels.
const TRAVEL: float = 60.0

## The area a shear has to keep, as a share of the box's own. A shear's
## determinant is exactly one, so the bound is the float arithmetic of the
## matrix and the quad, and a scale of the same drags misses it by 12 to 15
## in a hundred.
const AREA_BOUND: float = 1e-4

## How far apart the two diagonals' middles may stand and still be one point,
## which is what a parallelogram is, in document pixels.
const PARALLEL_BOUND: float = 0.01


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


## Where handle *grabbed* stands on the box before any drag.
static func _handle_at(grabbed: Vector2i) -> Vector2:
    var half := Vector2(BOX.size) * 0.5
    return Vector2(BOX.position) + half + Vector2(grabbed) * half


## A fresh Transform over the box under *mode*, handle *grabbed* pressed and
## dragged by *by*, and the quad, the skew and the scale it left, read before
## the release.
func _drag(mode: int, grabbed: Vector2i, by: Vector2) -> Dictionary:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var machine := Fixtures.make_bound_machine(surface)
    var document := surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i(1, 1))
    document.selection.select_rect(BOX)
    machine.set_active_tool(&"transform")
    var tool: StateTransformScript = machine.active_tool
    tool.transform_mode = mode
    var from := _handle_at(grabbed)
    surface.view.mouse_position = from
    tool.handle_input(_button(true))
    # Two motions, the first a pixel off the press, so the axis a corner picks
    # is the one the whole drag ends on and not the first step's.
    surface.view.mouse_position = from + by.normalized()
    tool.handle_input(InputEventMouseMotion.new())
    surface.view.mouse_position = from + by
    tool.handle_input(InputEventMouseMotion.new())
    var out := {"quad": tool.pending_quad(), "skew": tool.move_skew(), "moving": tool.is_moving()}
    tool.handle_input(_button(false))
    Fixtures.teardown(surface, machine)
    return out


## The area a quad in `QUAD_CORNERS` order encloses, by the shoelace.
static func _area(quad: PackedVector2Array) -> float:
    var twice := 0.0
    for i in quad.size():
        twice += quad[i].cross(quad[(i + 1) % quad.size()])
    return absf(twice) * 0.5


## How far a quad is from a parallelogram: the distance between its two
## diagonals' middles, nought for a parallelogram and nothing else.
static func _off_parallel(quad: PackedVector2Array) -> float:
    return ((quad[0] + quad[2]) - (quad[1] + quad[3])).length() * 0.5


## The quad's corners that moved, by index, of the box as it was.
static func _moved(quad: PackedVector2Array) -> Array[int]:
    var before := SaHomography.corners_of(BOX)
    var out: Array[int] = []
    for i in 4:
        if (quad[i] - before[i]).length() > 0.5:
            out.append(i)
    return out


## The four corners and the four edges, each dragged both ways along each axis
## it can lean on, and every one a parallelogram of the box's area with a lean.
## The corners are the case that could fall back to scaling.
func test_every_handle_leans_the_box_and_keeps_its_area() -> void:
    var area := float(BOX.size.x * BOX.size.y)
    var shear := StateTransformScript.Mode.SHEAR
    for grabbed: Vector2i in SaTransformHandles.HANDLE_CORNERS:
        var ways: Array[Vector2] = []
        if grabbed.y != 0:
            ways.append_array([Vector2(TRAVEL, 0.0), Vector2(-TRAVEL, 0.0)])
        if grabbed.x != 0:
            ways.append_array([Vector2(0.0, TRAVEL), Vector2(0.0, -TRAVEL)])
        for by: Vector2 in ways:
            var got := _drag(shear, grabbed, by)
            var quad: PackedVector2Array = got["quad"]
            var name := "handle %s dragged by %s" % [grabbed, by]
            assert_true(got["moving"], "%s lifted the picture" % name)
            assert_eq(quad.size(), 4, "%s leaves a quad" % name)
            assert_true(_off_parallel(quad) < PARALLEL_BOUND, "%s leaves a parallelogram, %s" % [name, quad])
            assert_true(
                absf(_area(quad) / area - 1.0) < AREA_BOUND, "%s keeps the area, %.2f of %.0f" % [name, _area(quad), area]
            )
            assert_true(absf(float(got["skew"])) > 0.05, "%s leans the box, %.4f" % [name, float(got["skew"])])


## A corner leans the one edge it sits on and holds the edge across from it:
## the top left corner dragged sideways moves the top two corners by the drag
## and dragged down moves the left two, the other two still each time.
func test_a_corner_leans_the_edge_along_the_drags_longer_axis() -> void:
    var shear := StateTransformScript.Mode.SHEAR
    var sideways := _drag(shear, Vector2i(-1, -1), Vector2(-TRAVEL, 12.0))
    var across: PackedVector2Array = sideways["quad"]
    assert_eq(_moved(across), [0, 1] as Array[int], "Sideways leans the top edge, %s" % across)
    var top_left := Vector2(BOX.position) + Vector2(-TRAVEL, 0.0)
    assert_true((across[0] - top_left).length() < 0.01, "and the corner follows the drag along it, %s" % across[0])

    var down := _drag(shear, Vector2i(-1, -1), Vector2(-12.0, TRAVEL))
    var side: PackedVector2Array = down["quad"]
    assert_eq(_moved(side), [0, 3] as Array[int], "Down leans the left side, %s" % side)
    assert_true((side[0] - (Vector2(BOX.position) + Vector2(0.0, TRAVEL))).length() < 0.01, "and the corner follows it down")

    var far := _drag(shear, Vector2i(1, 1), Vector2(TRAVEL, -12.0))
    assert_eq(_moved(far["quad"]), [2, 3] as Array[int], "The bottom right dragged sideways leans the bottom edge")


## An edge leans along itself and a drag across it does nothing, as it did
## before the corners leaned.
func test_a_drag_across_an_edge_still_does_nothing() -> void:
    var shear := StateTransformScript.Mode.SHEAR
    for pair: Array in [[Vector2i(0, -1), Vector2(0.0, -TRAVEL)], [Vector2i(1, 0), Vector2(TRAVEL, 0.0)]]:
        var got := _drag(shear, pair[0], pair[1])
        assert_eq(_moved(got["quad"]), [] as Array[int], "Handle %s dragged across moves no corner" % pair[0])
        assert_almost_eq(float(got["skew"]), 0.0, 1e-4, "and leans nothing")


## The same corner drag under Normal still scales, and under Perspective still
## moves the one corner into a shape that is no parallelogram, so Shear is now
## a mode of its own rather than the one beside it.
func test_shear_is_neither_normal_nor_perspective_at_a_corner() -> void:
    var area := float(BOX.size.x * BOX.size.y)
    var by := Vector2(-TRAVEL, 12.0)
    var normal := _drag(StateTransformScript.Mode.NORMAL, Vector2i(-1, -1), by)
    assert_true(absf(_area(normal["quad"]) / area - 1.0) > 0.05, "Normal's corner scales the box")
    assert_almost_eq(float(normal["skew"]), 0.0, 1e-4, "and leans nothing")
    var perspective := _drag(StateTransformScript.Mode.PERSPECTIVE, Vector2i(-1, -1), by)
    assert_true(_off_parallel(perspective["quad"]) > 1.0, "Perspective's corner leaves no parallelogram")
    var shear := _drag(StateTransformScript.Mode.SHEAR, Vector2i(-1, -1), by)
    assert_true(_off_parallel(shear["quad"]) < PARALLEL_BOUND, "and Shear's does")
