## A perspective commit carries the selection with the pixels.
##
## A commit takes the marching ants with the picture, so a painter who commits
## and drags again picks up what they were looking at. Perspective needs its own carry: a homography is
## not a `Transform2D`, and
## `SaHomography.affine_part` reads one off it that is exact only where the map
## is itself affine. So a carry skipped under a perspective map would leave the
## mask on the box the lift covered while the picture landed on a quad.
##
## **The claim these cases pin is a texel, not a bounds.** A bounds that grew
## would pass while the mask inside it was still square, which is precisely the
## failure: `landed_bounds()` is the quad's bounding box and it moves under a
## perspective map whether the mask is carried or not. So each case reads the
## mask back off the GPU at a document position and asks whether that position is
## covered, which only the resample can answer.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## The lifted box. Inside one chunk, so the arithmetic below stays readable.
const BOX := Rect2i(64, 64, 128, 128)

## Where the bottom right corner is dragged to, outward. Well outside the box,
## and the other three corners stay, which is what makes the affine part the
## identity.
const PULLED_OUT := Vector2(448.0, 448.0)

## And inward, for the half of the claim that needs a point the quad misses. A
## corner pulled out makes a quad that contains the whole old box, so nothing is
## left behind by it and the deselect half needs its own gesture. This one is
## still convex: (150, 150) is past the box's other diagonal, `x + y = 256`.
const PULLED_IN := Vector2(150.0, 150.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _pass: SaTransform = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document
    _pass = SaTransform.new(_doc)


func after_each() -> void:
    _pass = null
    _easel.free()
    _easel = null
    _doc = null


## How much of the mask covers the document position *at*, read off the GPU.
##
## Zero when no chunk holds that position at all, which is the same answer a
## chunk of zeroes gives and is the right one either way: nothing is selected
## there.
func _covered(at: Vector2i) -> float:
    var grid := Vector2i(floori(float(at.x) / SaChunk.SIZE), floori(float(at.y) / SaChunk.SIZE))
    var texture := _doc.selection.texture_for(grid)
    if texture == null or not texture.rid.is_valid():
        return 0.0
    var local := at - grid * SaChunk.SIZE
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * texture.size.x + local.x).r


## Lifts BOX with the selection on it and drags its bottom right corner to *to*.
func _pull_a_corner(to: Vector2) -> void:
    _doc.active_layer.fill(Color(1.0, 0.0, 0.0, 1.0))
    _doc.selection.select_rect(BOX)
    assert_true(_pass.lift(_doc.active_layer, BOX), "There is a square to lift")
    var corners := SaHomography.corners_of(BOX)
    corners[2] = to
    _pass.preview_homography(SaHomography.corners_to_quad(BOX, corners))
    assert_true(_pass.is_perspective(), "The pass is under a homography")


## The case the filing asked for: a texel inside the landed quad and outside the
## old box is selected after the commit.
##
## `(300, 300)` is the point. It is 108 past BOX's far edge, so no square mask on
## the old box can cover it, and it is well inside the quad whose fourth corner
## went to (448, 448), which the assertion below proves rather than assumes.
func test_a_texel_inside_the_landed_quad_and_outside_the_old_box_is_selected() -> void:
    _pull_a_corner(PULLED_OUT)
    var reach := Vector2i(300, 300)
    assert_false(BOX.has_point(reach), "The point this reads is outside the box the lift covered")
    assert_almost_eq(_covered(reach), 0.0, 1e-3, "and nothing is selected there before the commit")

    var quad := _pass.landed_quad()
    assert_true(_inside(quad, Vector2(reach)), "while the quad the picture is about to land on holds it")

    assert_true(_pass.commit(), "Enter commits the perspective map")
    assert_almost_eq(_covered(reach), 1.0, 1e-2, "and the mask followed the picture onto the quad")


## The other half of the same claim: a texel the mask covered before, which the
## quad does not reach, is not selected.
##
## This one drags the corner **inward**, because a corner pulled out makes a quad
## that contains the whole box it came from, so nothing is ever left behind by
## it. The first run of this case asserted otherwise and failed on its own
## premise rather than on the fix.
func test_a_texel_the_old_box_covered_and_the_quad_misses_is_deselected() -> void:
    _pull_a_corner(PULLED_IN)
    var left_behind := Vector2i(185, 185)
    assert_true(BOX.has_point(left_behind), "The point this reads is inside the box the lift covered")
    assert_almost_eq(_covered(left_behind), 1.0, 1e-2, "and is selected before the commit")

    var quad := _pass.landed_quad()
    assert_false(_inside(quad, Vector2(left_behind)), "while the quad the picture lands on misses it")

    assert_true(_pass.commit(), "Enter commits the perspective map")
    assert_almost_eq(_covered(left_behind), 0.0, 1e-2, "and the mask left with the picture")


## An affine commit is untouched by the change, which is the regression the new
## argument could most easily have caused: `kernel_rows` answers a third row of
## (0, 0, 1) for an empty homography, so the arithmetic is what it was.
func test_an_affine_commit_still_carries_the_selection() -> void:
    _doc.active_layer.fill(Color(1.0, 0.0, 0.0, 1.0))
    _doc.selection.select_rect(BOX)
    assert_true(_pass.lift(_doc.active_layer, BOX), "There is a square to lift")
    _pass.preview_affine(Vector2i(128, 0), Vector2.ONE, 0.0)
    assert_false(_pass.is_perspective(), "A move is not a homography")

    assert_true(_pass.commit(), "Enter commits the move")
    assert_almost_eq(_covered(Vector2i(240, 128)), 1.0, 1e-2, "The mask moved with the picture")
    assert_almost_eq(_covered(Vector2i(80, 128)), 0.0, 1e-2, "and left where it was")


## A commit under a map that does nothing leaves the selection alone, which the
## new identity guard has to keep answering. It is the affine half of the guard
## that survived: an empty homography and an identity matrix is still a no-op.
func test_an_identity_affine_commit_leaves_the_mask_where_it_is() -> void:
    _doc.active_layer.fill(Color(1.0, 0.0, 0.0, 1.0))
    _doc.selection.select_rect(BOX)
    assert_true(_pass.lift(_doc.active_layer, BOX), "There is a square to lift")
    assert_false(_pass.is_perspective(), "No homography is in force")

    assert_true(
        (
            SaTransformSelection.carry(
                _doc.selection, PackedFloat32Array(), Transform2D.IDENTITY, BOX, BOX, SaResampleKernel.Filter.BILINEAR
            )
            == false
        ),
        "An identity affine map is nothing to carry through"
    )
    _pass.cancel()


## Whether *at* is inside the convex quad *quad*, by the sign of the cross
## product against each edge in turn.
##
## Written here rather than reached for, because `Geometry2D` answers this for a
## polygon and the answer these cases need is about four points in the order
## `landed_quad` builds them.
func _inside(quad: PackedVector2Array, at: Vector2) -> bool:
    if quad.size() != 4:
        return false
    var sign_seen := 0.0
    for i in 4:
        var edge: Vector2 = quad[(i + 1) % 4] - quad[i]
        var to_point: Vector2 = at - quad[i]
        var cross := edge.x * to_point.y - edge.y * to_point.x
        if is_zero_approx(cross):
            continue
        if sign_seen == 0.0:
            sign_seen = signf(cross)
        elif signf(cross) != sign_seen:
            return false
    return true
