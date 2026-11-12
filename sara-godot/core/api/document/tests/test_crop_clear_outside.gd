## The crop tool's Clear Outside box, read back texel by texel.
##
## The note asks for a crop that "completely clears what is not selected", and
## the place a plain crop keeps something is the overhang of the last chunk in
## a row or a column: a chunk is 256 texels wide, a canvas edge almost never
## lands on that grid, and the copy that rebuilds the grid brings the whole
## chunk across. Nothing shows it until Image > Canvas Size grows the document
## back, so the suite crops and grows twice over, once with the box off and
## once with it on, and reads the same texel both times.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## The crop the suite runs. It is 400 wide, so its second column of chunks
## reaches 512 and carries 112 texels of the old picture past the new canvas,
## which is the overhang the box is about.
const RECT := Rect2i(300, 200, 400, 300)

## A texel inside that overhang, in the cropped document's coordinates. The
## grow below anchors top left, so the crop's own origin stays at (0, 0) and
## this reads the same texel before and after it.
const OVERHANG := Vector2i(450, 100)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _crop: SaCrop = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(1024, 768))
    _doc = _easel.document
    _crop = SaCrop.new(_doc)


func after_each() -> void:
    _crop = null
    _easel.free()
    _easel = null
    _doc = null


## Read as `core/api/document/tests/test_crop.gd` reads, because a claim about what survives a
## crop is a claim about texels and nothing smaller says it.
func _texel(x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := _doc.active_layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(
        bytes, texture.format, (y - grid.y * SaChunk.SIZE) * texture.size.x + (x - grid.x * SaChunk.SIZE)
    )


## Paints, crops with the box as *clear_outside* says, and grows the canvas
## back to where it was, which is the only way to look at what the crop kept.
func _crop_and_grow_back(clear_outside: bool) -> void:
    _doc.active_layer.fill(Color(0.9, 0.1, 0.4, 1.0))
    assert_true(_crop.crop_to(RECT, clear_outside), "The crop happens")
    assert_eq(_doc.canvas_size, RECT.size, "and the document is the rectangle")
    assert_true(_crop.resize_to(Vector2i(1024, 768), Vector2i.ZERO), "The canvas grows back")


## The defect the box is for. Without it the overhang is still there, which is
## the behaviour every crop has had and the reason the box is worth having.
func test_a_plain_crop_keeps_the_overhang() -> void:
    _crop_and_grow_back(false)
    var kept := _texel(OVERHANG.x, OVERHANG.y)
    assert_almost_eq(kept.a, 1.0, 1e-4, "A plain crop leaves the last chunk's overhang to be found again")
    assert_almost_eq(kept.r, 0.9, 1e-4, "with the paint that was on it")


## The box's claim: nothing outside the rectangle survives, so growing the
## canvas back finds nothing.
func test_the_box_clears_what_the_rectangle_left_out() -> void:
    _crop_and_grow_back(true)
    assert_almost_eq(_texel(OVERHANG.x, OVERHANG.y).a, 0.0, 1e-4, "The box clears the overhang the crop kept")


## What the box must not do is take anything the rectangle asked for, so the
## texel just inside the new edge is read as well as the one just outside.
func test_the_box_keeps_every_texel_the_rectangle_asked_for() -> void:
    _doc.active_layer.fill(Color(0.9, 0.1, 0.4, 1.0))
    assert_true(_crop.crop_to(RECT, true), "The crop happens")
    assert_almost_eq(_texel(0, 0).a, 1.0, 1e-4, "The rectangle's first texel is there")
    var last := _texel(RECT.size.x - 1, RECT.size.y - 1)
    assert_almost_eq(last.a, 1.0, 1e-4, "and so is its last")
    assert_almost_eq(last.r, 0.9, 1e-4, "with the paint that was on it")


## One crop is one undo, box or no box, and the undo brings back what the box
## cleared as well as what the crop released.
func test_the_clear_rides_the_crop_s_own_step() -> void:
    _doc.active_layer.fill(Color(0.9, 0.1, 0.4, 1.0))
    var steps := _doc.history.step_count()
    assert_true(_crop.crop_to(RECT, true), "The crop happens")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step rather than two")

    assert_true(_doc.undo(), "which undoes")
    assert_eq(_doc.canvas_size, Vector2i(1024, 768), "restoring the size")
    assert_almost_eq(_texel(OVERHANG.x, OVERHANG.y).a, 1.0, 1e-4, "and the paint the box cleared")


## The box is the tool's, so Image > Crop to Selection keeps the crop it has
## always done. Nothing on that menu offers the box and inventing one here
## would be this class deciding what the menu means.
func test_crop_to_selection_is_unchanged() -> void:
    _doc.active_layer.fill(Color(0.9, 0.1, 0.4, 1.0))
    _doc.selection.select_rect(RECT)
    assert_true(_crop.crop_to_selection(), "The menu crops to the bounds")
    assert_true(_crop.resize_to(Vector2i(1024, 768), Vector2i.ZERO), "and growing back")
    assert_almost_eq(_texel(OVERHANG.x, OVERHANG.y).a, 1.0, 1e-4, "still finds the overhang")
