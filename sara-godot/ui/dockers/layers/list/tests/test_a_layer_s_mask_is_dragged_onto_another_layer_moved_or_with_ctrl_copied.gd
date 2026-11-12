## A layer's mask is dragged from its row onto another layer's row, moved or
## with Ctrl copied, as one step.
##
## A mask can be dragged and dropped from one layer to another. The drag goes through the list's own calls, `begin_drag` with the
## mask, `drag_over` and `drop`, and every case reads the coverage texels of
## both masks rather than whether a mask object is there, because a mask moved
## with the wrong chunks is still a mask. The running app's half, with a real
## press on the mask picture, is
## `scenarios/a-layer-s-mask-is-dragged-onto-another-layer-moved-or-with-ctrl-copied.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Inside the left half of the canvas, and inside the right half.
const LEFT := Vector2i(100, 300)
const RIGHT := Vector2i(400, 300)

var _easel: SaEasel
var _doc: SaDocument
var _canvas: SaCanvas
var _layers: LayersDocker
var _a: SaLayer
var _b: SaLayer


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _easel.document
    _a = SaLayerOps.new(_doc).add()
    _a.name = "A"
    _b = SaLayerOps.new(_doc).add()
    _b.name = "B"
    _a.fill(Color(0.8, 0.2, 0.1, 1.0))
    _b.fill(Color(0.1, 0.3, 0.8, 1.0))
    # A's mask shows the left half and hides the right.
    _doc.selection.select_rect(Rect2i(0, 0, 256, 512))
    SaMaskOps.new(_doc).add_from_selection(_a)
    _doc.selection.deselect()
    _doc.undo_redo.clear_history()
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _layers = LayersDocker.new()
    _layers.target_canvas = _canvas
    _layers.list_keeper.listen()
    _layers.sync_layer_list()


func after_each() -> void:
    _layers.free()
    _canvas.free()
    _easel.free()
    _a = null
    _b = null


func _list() -> SaLayerList:
    return _layers.item_list


func _row_of(layer: SaLayer) -> int:
    for i in _list().rows.size():
        if _list().layer_at(i) == layer:
            return i
    return -1


func _steps() -> int:
    return _doc.undo_redo.get_history_count()


func _grid(at: Vector2i) -> Vector2i:
    @warning_ignore("integer_division")
    return Vector2i(at.x / SaChunk.SIZE, at.y / SaChunk.SIZE)


## The coverage *owner*'s mask holds at a document pixel, its rest where it
## holds nothing, and -1 for an owner with no mask.
func _coverage(owner: SaLayer, at: Vector2i) -> float:
    if owner.mask == null:
        return -1.0
    var texture := owner.mask.texture_for(_grid(at))
    if texture == null:
        return owner.mask.rest
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var inside := at - _grid(at) * SaChunk.SIZE
    return SaFieldSpec.decode_texel(bytes, texture.format, inside.y * texture.size.x + inside.x).r


## A drag of *from*'s mask released over *onto*'s row, with Ctrl held when *copy*.
func _drag_mask(from: SaLayer, onto: SaLayer, copy: bool = false) -> void:
    _list().begin_drag(_row_of(from), true)
    _list().drag_over(_row_of(onto), SaLayerList.Drop.BELOW)
    _list().drop(copy)


func test_a_dragged_mask_moves_onto_the_other_layer_as_one_step() -> void:
    assert_eq(_coverage(_a, LEFT), 1.0, "A's mask shows the left half")
    assert_eq(_coverage(_a, RIGHT), 0.0, "and hides the right")
    _list().begin_drag(_row_of(_a), true)
    _list().drag_over(_row_of(_b), SaLayerList.Drop.BELOW)
    assert_eq(_list().drop_mode, SaLayerList.Drop.INTO, "B's row shows it takes the mask")
    _list().drop()

    assert_eq(_coverage(_b, LEFT), 1.0, "B shows the left half A showed")
    assert_eq(_coverage(_b, RIGHT), 0.0, "and hides the right half A hid")
    assert_null(_a.mask, "A is left with no mask")
    assert_eq(_steps(), 1, "as one step")

    assert_true(_doc.undo(), "the step is undone")
    assert_eq(_coverage(_a, LEFT), 1.0, "one undo gives A its mask back")
    assert_eq(_coverage(_a, RIGHT), 0.0, "with the coverage it had")
    assert_null(_b.mask, "and takes B's away")

    assert_true(_doc.redo(), "and redone")
    assert_eq(_coverage(_b, RIGHT), 0.0, "B has it again")
    assert_null(_a.mask, "and A has none")


func test_with_ctrl_held_the_mask_is_copied_and_the_source_keeps_its_own() -> void:
    _drag_mask(_a, _b, true)
    assert_eq(_coverage(_b, LEFT), 1.0, "B shows the left half")
    assert_eq(_coverage(_b, RIGHT), 0.0, "and hides the right")
    assert_eq(_coverage(_a, LEFT), 1.0, "A's mask is unchanged")
    assert_eq(_coverage(_a, RIGHT), 0.0, "on both halves")
    assert_true(_a.mask != _b.mask, "two masks, not one shared")
    assert_eq(_steps(), 1, "as one step")
    assert_true(_doc.undo(), "the step is undone")
    assert_null(_b.mask, "one undo takes the copy off B")
    assert_eq(_coverage(_a, RIGHT), 0.0, "and leaves A's as it was")


## The rule: a layer with a mask of its own refuses another,
## its row says so while the drag is over it, and the release changes nothing.
func test_a_layer_that_has_a_mask_refuses_the_drop_and_says_why() -> void:
    SaMaskOps.new(_doc).add(_b)
    _doc.undo_redo.clear_history()
    _list().begin_drag(_row_of(_a), true)
    _list().drag_over(_row_of(_b), SaLayerList.Drop.BELOW)
    assert_eq(_list().drop_mode, SaLayerList.Drop.REFUSED, "B's row shows it will not take the mask")
    assert_eq(_list().drop_row, _row_of(_b), "on B's row")
    assert_true(SaLayerMaskDrag.refusal(_a, _b).contains("'B'"), "the line names the layer")
    _list().drop()
    assert_eq(_coverage(_b, RIGHT), 1.0, "B keeps its own mask, which hides nothing")
    assert_eq(_coverage(_a, RIGHT), 0.0, "A keeps its own")
    assert_eq(_steps(), 0, "and no step is taken")


## The row the mask came from shows it will not take it, and a release there
## changes nothing and says nothing.
func test_the_source_row_refuses_its_own_mask() -> void:
    _list().begin_drag(_row_of(_a), true)
    _list().drag_over(_row_of(_a), SaLayerList.Drop.ABOVE)
    assert_eq(_list().drop_mode, SaLayerList.Drop.REFUSED, "A's own row shows the refusal")
    assert_eq(SaLayerMaskDrag.refusal(_a, _a), "", "with no line to say")
    _list().drop()
    assert_eq(_coverage(_a, RIGHT), 0.0, "A keeps its mask")
    assert_null(_b.mask, "and B has none")
    assert_eq(_steps(), 0, "and no step is taken")


## A group takes a mask, into a mask of its own chunks.
func test_a_group_takes_a_layer_s_mask() -> void:
    var group := SaLayerOps.new(_doc).group_layers([_b])
    _layers.sync_layer_list()
    _doc.undo_redo.clear_history()
    _drag_mask(_a, group)
    assert_eq(_coverage(group, LEFT), 1.0, "the group shows the left half")
    assert_eq(_coverage(group, RIGHT), 0.0, "and hides the right")
    assert_null(_a.mask, "and A has none")


## A drag that starts on the layer's own picture still moves the row.
func test_a_drag_from_the_layer_picture_moves_the_row() -> void:
    _list().begin_drag(_row_of(_a))
    assert_false(_list().mask_drag.armed(), "no mask is carried")
    _list().drag_over(_row_of(_b), SaLayerList.Drop.ABOVE)
    assert_eq(_list().drop_mode, SaLayerList.Drop.ABOVE, "the row's own mark")
    _list().drop()
    assert_true(_a.get_index() > _b.get_index(), "A went above B")
    assert_eq(_coverage(_a, RIGHT), 0.0, "carrying its mask")
    assert_null(_b.mask, "and B took none")
