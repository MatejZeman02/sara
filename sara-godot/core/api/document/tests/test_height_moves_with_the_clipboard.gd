## Height moves with the clipboard.
##
## A copy built its chunks from the layer's schema, which leaves a lazy field
## out, so a copied ridge came back flat. Now a copy takes the height times the
## selection's coverage, a cut thins it by the same selection, and a paste puts
## it down on a new layer that gains the field inside the paste's own step. The
## row's decision: a paste above a flat layer keeps its relief rather than
## dropping it, because a painter who copies thick paint expects it to stay
## thick. Every claim is read back texel by texel.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)

## Above one on purpose, so a clamp would show, and exact in a half float.
const THICK: float = 3.5

## The selection, inside the first chunk and clear of its edges.
const BOX := Rect2i(64, 64, 128, 128)

var _easel: SaEasel = null
var _doc: SaDocument = null
## The clipboard under test, the one `SaDocuments` holds for every open document.
var _held: SaClipboard = null


func before_each() -> void:
    _held = SaClipboard.new()
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


func _height_at(layer: SaLayer, x: int, y: int) -> float:
    var grid := Vector2i(floori(float(x) / SaChunk.SIZE), floori(float(y) / SaChunk.SIZE))
    var texture := layer.get_field(grid, SaFieldSpec.HEIGHT)
    if texture == null:
        return 0.0
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var index := (y - grid.y * SaChunk.SIZE) * texture.size.x + (x - grid.x * SaChunk.SIZE)
    return SaFieldSpec.decode_texel(bytes, texture.format, index).r


## The bottom layer, red, standing THICK high over its first chunk and with no
## height in the others.
func _thick_layer() -> SaLayer:
    var layer := _doc.active_layer
    layer.fill(RED)
    SaHeightOps.new(_doc).gain(layer)
    var texture := layer.get_or_create_field(Vector2i(0, 0), SaFieldSpec.HEIGHT)
    var bytes := PackedByteArray()
    bytes.resize(texture.size.x * texture.size.y * 2)
    for i in texture.size.x * texture.size.y:
        bytes.encode_half(i * 2, THICK)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)
    return layer


func test_a_copy_takes_the_height_the_selection_covers() -> void:
    var layer := _thick_layer()
    _doc.selection.select_rect(BOX)
    assert_true(_held.copy(_doc, layer) > 0, "A selection over thick paint copies")
    var taken: SaChunk = _held.chunks[Vector2i(0, 0)]
    var height := taken.field(SaFieldSpec.HEIGHT)
    assert_not_null(height, "The copied chunk holds the height")
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(height.rid, 0)
    assert_almost_eq(SaFieldSpec.decode_texel(bytes, height.format, 128 * 256 + 128).r, THICK, 1e-3, "inside the selection")
    assert_almost_eq(SaFieldSpec.decode_texel(bytes, height.format, 32 * 256 + 32).r, 0.0, 1e-4, "and none outside it")
    assert_almost_eq(_height_at(layer, 128, 128), THICK, 1e-3, "A copy leaves the layer's height alone")


func test_a_paste_onto_a_flat_layer_keeps_the_relief_in_one_step() -> void:
    var thick := _thick_layer()
    _doc.selection.select_rect(BOX)
    _held.copy(_doc, thick)
    var flat := SaLayerOps.new(_doc).add()
    flat.fill(RED)
    assert_false(flat.carries_height(), "The layer pasted onto is flat")
    var steps := _doc.history.step_count()

    var pasted := _held.paste(_doc)
    assert_not_null(pasted, "The paste lands")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step, the height inside it")
    assert_true(pasted.carries_height(), "The pasted layer carries height")
    assert_almost_eq(_height_at(pasted, 128, 128), THICK, 1e-3, "and stands as thick as what was copied")
    assert_almost_eq(_height_at(pasted, 32, 32), 0.0, 1e-4, "only where the selection took some")
    assert_false(flat.carries_height(), "The flat layer below stays flat")

    _doc.undo()
    assert_false(is_instance_valid(pasted) and pasted.is_inside_tree(), "Undo takes the pasted layer away whole")
    _doc.redo()
    assert_true(pasted.carries_height(), "Redo brings it back carrying height")
    assert_almost_eq(_height_at(pasted, 128, 128), THICK, 1e-3, "with the relief it had")

    SaLayerOps.new(_doc).merge_down(pasted)
    assert_true(flat.carries_height(), "Merged down, the flat layer gains the height")
    assert_almost_eq(_height_at(flat, 128, 128), THICK, 1e-3, "and holds the pasted relief")


func test_a_copy_of_flat_paint_pastes_a_flat_layer() -> void:
    var thick := _thick_layer()
    var elsewhere := Rect2i(64 + SaChunk.SIZE, 64, 64, 64)
    _doc.selection.select_rect(elsewhere)
    _held.copy(_doc, thick)
    var pasted := _held.paste(_doc)
    assert_false(pasted.carries_height(), "Paint copied from where no height stands pastes with no field")


func test_a_cut_thins_the_height_under_the_hole_and_undo_restores_it() -> void:
    var layer := _thick_layer()
    _doc.selection.select_rect(BOX)
    assert_true(_held.cut(_doc, layer), "A cut over thick paint cuts")
    assert_almost_eq(_height_at(layer, 128, 128), 0.0, 1e-4, "The hole has no height left")
    assert_almost_eq(_height_at(layer, 32, 32), THICK, 1e-3, "and outside the selection it stands")
    _doc.undo()
    assert_almost_eq(_height_at(layer, 128, 128), THICK, 1e-3, "Undo puts the height back")


## The selection acts on the thickness the way it acts on alpha: at a texel a
## feathered rim covers in part, the copy takes the height times the coverage
## and the cut leaves the rest, so the two sum to what stood there.
func test_a_soft_edge_splits_the_height_by_its_coverage() -> void:
    var layer := _thick_layer()
    _doc.selection.select_rect(BOX)
    SaSelectionFilters.feather(_doc.selection, 8, _doc.canvas_size)
    var mask := _doc.selection.texture_for(Vector2i(0, 0))
    var coverage := GlobalShaderCompiler.get_rd().texture_get_data(mask.rid, 0)
    var row := BOX.get_center().y
    var edge := -1
    var covered := 0.0
    for x in range(BOX.position.x, BOX.get_center().x):
        covered = SaFieldSpec.decode_texel(coverage, mask.format, row * mask.size.x + x).r
        if covered > 0.05 and covered < 0.95:
            edge = x
            break
    assert_true(edge >= 0, "The feathered rim covers a texel of the middle row in part")
    if edge < 0:
        return
    assert_true(_held.cut(_doc, layer), "The cut runs")
    var taken: SaTexture = (_held.chunks[Vector2i(0, 0)] as SaChunk).field(SaFieldSpec.HEIGHT)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(taken.rid, 0)
    var copied := SaFieldSpec.decode_texel(bytes, taken.format, row * taken.size.x + edge).r
    assert_almost_eq(copied, THICK * covered, 2e-3, "The copy takes the height times the coverage")
    assert_almost_eq(_height_at(layer, edge, row), THICK * (1.0 - covered), 2e-3, "and the cut leaves the rest")
