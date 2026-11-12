## A transform commit builds no compute: the selection's carry runs on three
## kernels the pass made at the lift and keeps.
##
## A commit that made the carry's three `SaCompute` objects afresh, each loaded
## at the document's depth and again at the mask's `r32f`, would make the first
## commit of a session wait on those pipelines inside the frame the painter
## pressed Enter in. These cases pin where the kernels are made, that
## they are the same objects commit after commit, and that the mask still lands
## where the picture did on the second commit, which is the one that reuses them.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## The lifted box. Inside one chunk, so the arithmetic below stays readable.
const BOX := Rect2i(64, 64, 128, 128)

## How far each commit moves the piece, a chunk's half so both land inside the
## 512 square document.
const STEP := 128

var _easel: SaEasel = null
var _doc: SaDocument = null
var _pass: SaTransform = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document
    _pass = SaTransform.new(_doc)
    _doc.active_layer.fill(Color(1.0, 0.0, 0.0, 1.0))


func after_each() -> void:
    _pass = null
    _easel.free()
    _easel = null
    _doc = null


## How much of the mask covers the document position *at*, read off the GPU.
func _covered(at: Vector2i) -> float:
    var grid := Vector2i(floori(float(at.x) / SaChunk.SIZE), floori(float(at.y) / SaChunk.SIZE))
    var texture := _doc.selection.texture_for(grid)
    if texture == null or not texture.rid.is_valid():
        return 0.0
    var local := at - grid * SaChunk.SIZE
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * texture.size.x + local.x).r


## Lifts *box* with the selection on it, moves it by *by* and commits.
func _move(box: Rect2i, by: Vector2i) -> void:
    assert_true(_pass.lift(_doc.active_layer, box), "There is a square to lift at %s" % box)
    _pass.preview_affine(by, Vector2.ONE, 0.0)
    assert_true(_pass.commit(), "Enter commits the move")


func test_a_lift_with_a_selection_makes_the_carry_kernels_at_the_mask_format() -> void:
    _doc.selection.select_rect(BOX)
    assert_true(_pass._mask_kernels.shift == null, "No kernel is made before the first lift")
    assert_true(_pass.lift(_doc.active_layer, BOX), "There is a square to lift")
    var kernels := [_pass._mask_kernels.shift, _pass._mask_kernels.resample, _pass._mask_kernels.blank]
    for compute: SaCompute in kernels:
        assert_true(compute != null, "The lift made the carry's kernels before Enter")
        assert_eq(
            compute.pipelines.storage_format, SaSelection.FORMAT, "%s is at the mask's format already" % compute.shader_name
        )
    _pass.cancel()


func test_a_lift_with_no_selection_makes_no_carry_kernel() -> void:
    assert_true(_pass.lift(_doc.active_layer, BOX), "There is a square to lift")
    assert_true(_pass._mask_kernels.shift == null, "A move with nothing selected has no mask to carry")
    _pass.cancel()


func test_two_commits_run_on_the_same_kernels_and_both_carry_the_mask() -> void:
    _doc.selection.select_rect(BOX)
    _move(BOX, Vector2i(STEP, 0))
    var shift: SaCompute = _pass._mask_kernels.shift
    var resample: SaCompute = _pass._mask_kernels.resample
    var blank: SaCompute = _pass._mask_kernels.blank
    assert_almost_eq(_covered(Vector2i(250, 128)), 1.0, 1e-2, "The first commit moved the mask right")

    var moved := Rect2i(BOX.position + Vector2i(STEP, 0), BOX.size)
    _move(moved, Vector2i(0, STEP))
    assert_true(is_same(_pass._mask_kernels.shift, shift), "The second commit stitched with the same shift")
    assert_true(is_same(_pass._mask_kernels.resample, resample), "and resampled with the same kernel")
    assert_true(is_same(_pass._mask_kernels.blank, blank), "and opened the stitch with the same one")
    assert_almost_eq(_covered(Vector2i(250, 250)), 1.0, 1e-2, "The second commit carried the mask down")
    assert_almost_eq(_covered(Vector2i(250, 128)), 0.0, 1e-2, "and left where the first had put it")
