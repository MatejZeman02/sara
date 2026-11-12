## A transform the painter flattens still hands the kernel a map with an inverse.
##
## A typed scale of nought and a side handle pulled onto the opposite side both
## reached `preview_matrix` flat, and `SaHomography.kernel_rows` called
## `affine_inverse` on it, which prints an engine error and hands the forward
## map back, so the preview and the commit resampled through the wrong map. Each flat map here is handed
## to the pass, the kernel's rows are
## read off what the pass kept, and the preview and the commit run under a
## logger that counts every engine error.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)
const BOX := Rect2i(256, 256, 256, 256)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _pass: SaTransform = null
var _errors: SaErrorCatcher = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(1024, 1024))
    _doc = _easel.document
    _pass = SaTransform.new(_doc)
    _doc.active_layer.fill(RED)
    _doc.selection.select_rect(BOX)
    _pass.lift(_doc.active_layer, BOX)
    _errors = SaErrorCatcher.new()
    OS.add_logger(_errors)


func after_each() -> void:
    OS.remove_logger(_errors)
    _errors = null
    _pass = null
    _easel.free()
    _easel = null
    _doc = null


## The map the typed rows build, as `_write_rows` in `state_transform.gd` builds
## it, about the box's centre.
func _typed(scale: Vector2) -> Transform2D:
    var centre := Vector2(BOX.position) + Vector2(BOX.size) * 0.5
    var basis := Transform2D(0.0, scale, 0.0, Vector2.ZERO)
    return Transform2D(basis.x, basis.y, centre - basis.basis_xform(centre))


## Hands *flat* to the pass, then checks the map it kept, the kernel's rows of
## it, a preview and a commit, with no engine error along the way.
func _lands_with_an_inverse(flat: Transform2D, what: String) -> void:
    assert_almost_eq(flat.determinant(), 0.0, 1e-6, "%s arrives flat" % what)
    _pass.preview_matrix(flat)
    var kept := _pass.matrix
    assert_true(absf(kept.determinant()) > 0.0, "%s is kept with an inverse" % what)
    var rows := SaHomography.kernel_rows(PackedFloat32Array(), kept, Vector2.ZERO)
    var back := Transform2D(Vector2(rows[0].x, rows[1].x), Vector2(rows[0].y, rows[1].y), rows[2])
    var round_trip := back * kept
    var off := (round_trip.x - Vector2.RIGHT).length() + (round_trip.y - Vector2.DOWN).length() + round_trip.origin.length()
    assert_almost_eq(off, 0.0, 1e-2, "and the kernel's rows are its inverse, not the map handed back")
    var centre := Vector2(BOX.get_center())
    assert_true((kept * centre).is_equal_approx(flat * centre), "and the box's centre lands where the flat map put it")
    _pass.tick()
    assert_true(_pass.commit(), "%s commits" % what)
    var caught := _errors.described([SaErrorCatcher.ERROR])
    assert_eq(caught, PackedStringArray(), "with no engine error on the way: %s" % "; ".join(caught))


func test_a_typed_scale_of_nought_across_keeps_an_inverse() -> void:
    _lands_with_an_inverse(_typed(Vector2(0.0, 1.0)), "A scale of nought across")


func test_a_typed_scale_of_nought_down_keeps_an_inverse() -> void:
    _lands_with_an_inverse(_typed(Vector2(1.0, 0.0)), "A scale of nought down")


func test_a_typed_scale_of_nought_on_both_axes_keeps_an_inverse() -> void:
    _lands_with_an_inverse(_typed(Vector2.ZERO), "A scale of nought both ways")


func test_a_side_handle_pulled_onto_the_opposite_side_keeps_an_inverse() -> void:
    # The right side's handle dragged onto the left side, which the pull holds
    # still, is the drag that flattened the picture to a line.
    var left := Vector2(BOX.position.x, BOX.get_center().y)
    var flat := SaTransformHandles.pull(BOX, Vector2i(1, 0), Transform2D.IDENTITY, left)
    _lands_with_an_inverse(flat, "A pull onto the opposite side")


func test_two_axes_on_one_line_keep_an_inverse() -> void:
    var flat := Transform2D(Vector2(1.0, 0.5), Vector2(2.0, 1.0), Vector2(10.0, 20.0))
    _lands_with_an_inverse(flat, "Two axes on one line")


func test_a_map_with_an_inverse_is_kept_as_it_came() -> void:
    var mirror := Transform2D(Vector2(-1.0, 0.0), Vector2(0.3, 0.8), Vector2(700.0, 5.0))
    _pass.preview_matrix(mirror)
    assert_eq(_pass.matrix, mirror, "A mirror with a shear has an inverse and is not touched")
