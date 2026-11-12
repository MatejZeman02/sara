## The transform tool's translate, as pixels rather than as arithmetic.
##
## Every assertion reads texels back, because a lift through the wrong mask or
## a shift into the wrong chunk returns a plausible picture rather than an
## error. The claims: the lift takes the selection and leaves the hole, the
## preview is in the stroke layer and the layer keeps its hole while it is
## there, a commit is one history step that undo puts back whole, Escape
## restores, and a landing outside the old chunks leaves the grid sparse.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)

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


func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x)


func _layer_texel(layer: SaLayer, x: int, y: int) -> Color:
    var grid := Vector2i(floori(float(x) / SaChunk.SIZE), floori(float(y) / SaChunk.SIZE))
    var texture := layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    return _texel(texture, x - grid.x * SaChunk.SIZE, y - grid.y * SaChunk.SIZE)


func test_the_lift_takes_the_selection_and_leaves_the_hole() -> void:
    _doc.active_layer.fill(RED)
    _doc.selection.select_rect(Rect2i(100, 100, 120, 120))

    assert_true(_pass.lift(_doc.active_layer, Rect2i(100, 100, 120, 120)), "A selection over paint is something to lift")
    assert_almost_eq(_layer_texel(_doc.active_layer, 150, 150).a, 0.0, 1e-4, "Inside the box the layer is a hole now")
    assert_almost_eq(_layer_texel(_doc.active_layer, 50, 50).a, 1.0, 1e-4, "and outside it nothing moved")
    assert_true(_doc.stroke_layer.chunks.is_empty(), "Nothing is previewed until the first move")


func test_the_preview_is_the_stroke_layer_and_the_hole_stays() -> void:
    _doc.active_layer.fill(RED)
    _doc.selection.select_rect(Rect2i(100, 100, 120, 120))
    _pass.lift(_doc.active_layer, Rect2i(100, 100, 120, 120))

    _pass.preview(Vector2i(200, 0))
    _pass.tick()

    assert_false(_doc.stroke_layer.chunks.is_empty(), "The moved picture is in the stroke layer")
    assert_almost_eq(_layer_texel(_doc.stroke_layer, 350, 150).a, 1.0, 1e-4, "which holds it 200 to the right of where it was")
    assert_almost_eq(_layer_texel(_doc.stroke_layer, 150, 150).a, 0.0, 1e-4, "and not where it was")
    assert_almost_eq(_layer_texel(_doc.active_layer, 150, 150).a, 0.0, 1e-4, "The layer keeps its hole during the drag")
    assert_almost_eq(_layer_texel(_doc.active_layer, 350, 150).a, 1.0, 1e-4, "and what was already there is untouched")


func test_a_commit_is_one_step_that_undo_puts_back_whole() -> void:
    _doc.active_layer.fill(RED)
    _doc.selection.select_rect(Rect2i(100, 100, 120, 120))
    var steps := _doc.history.step_count()
    _pass.lift(_doc.active_layer, Rect2i(100, 100, 120, 120))
    _pass.preview(Vector2i(0, 200))

    assert_true(_pass.commit(), "Enter writes the move down")
    assert_eq(_doc.history.step_count(), steps + 1, "as exactly one step, hole and landing together")
    assert_true(_doc.stroke_layer.chunks.is_empty(), "and hands the preview chunks back")
    assert_almost_eq(_layer_texel(_doc.active_layer, 150, 150).a, 0.0, 1e-4, "The hole is in the layer now")
    assert_almost_eq(_layer_texel(_doc.active_layer, 150, 350).a, 1.0, 1e-4, "and the picture is where it was dropped")

    _doc.undo()
    assert_almost_eq(_layer_texel(_doc.active_layer, 150, 150).a, 1.0, 1e-4, "One undo fills the hole back in")
    assert_almost_eq(_layer_texel(_doc.active_layer, 50, 50).a, 1.0, 1e-4, "and leaves everything else as it was")


func test_escape_puts_the_pixels_back() -> void:
    _doc.active_layer.fill(RED)
    _doc.selection.select_rect(Rect2i(100, 100, 120, 120))
    var steps := _doc.history.step_count()
    _pass.lift(_doc.active_layer, Rect2i(100, 100, 120, 120))
    _pass.preview(Vector2i(120, 120))

    _pass.cancel()

    assert_false(_pass.is_lifted(), "Escape ends the move")
    assert_true(_doc.stroke_layer.chunks.is_empty(), "with nothing left in the preview")
    assert_almost_eq(_layer_texel(_doc.active_layer, 150, 150).a, 1.0, 1e-4, "and the pixels back where they were")
    assert_eq(_doc.history.step_count(), steps, "A move that was put back is not a step in the history")


func test_a_landing_outside_the_grid_allocates_only_what_it_covers() -> void:
    var layer := _doc.active_layer
    layer.get_or_create_chunk(Vector2i(0, 0)).clear(RED)
    var before := layer.chunks.size()

    _pass.lift(layer, Rect2i(0, 0, 256, 256))
    _pass.preview(Vector2i(300, 0))
    _pass.commit()

    assert_eq(layer.chunks.size(), before + 2, "A landing across a seam allocates the two chunks it covers")
    assert_almost_eq(_layer_texel(layer, 350, 100).a, 1.0, 1e-4, "and the picture is in them")

    _doc.undo()
    assert_eq(layer.chunks.size(), before, "and undo takes the chunks it added away again, not just their pixels")


func test_a_second_preview_leaves_nothing_of_the_first_behind() -> void:
    _doc.active_layer.fill(RED)
    _doc.selection.select_rect(Rect2i(100, 100, 120, 120))
    _pass.lift(_doc.active_layer, Rect2i(100, 100, 120, 120))

    _pass.preview(Vector2i(200, 0))
    _pass.preview(Vector2i(0, 300))
    _pass.tick()

    assert_almost_eq(_layer_texel(_doc.stroke_layer, 150, 450).a, 1.0, 1e-4, "The picture is where the second move put it")
    assert_almost_eq(_layer_texel(_doc.stroke_layer, 350, 150).a, 0.0, 1e-4, "and nothing of the first move is left")
    assert_almost_eq(_layer_texel(_doc.stroke_layer, 150, 150).a, 0.0, 1e-4, "nor anything where it started")
    assert_almost_eq(
        _layer_texel(_doc.stroke_layer, 30, 480).a, 0.0, 1e-6, "and a fresh tile is transparent where nothing landed"
    )
