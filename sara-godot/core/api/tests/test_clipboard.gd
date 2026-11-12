## Cut, copy and paste through the selection.
##
## The clipboard is chunks copied on the GPU through the mask, with the colour
## space they were painted in. Every assertion reads pixels back, because a
## copy through the wrong mask or into the wrong space returns plausible
## numbers rather than an error.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)

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


func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x)


func _layer_texel(layer: SaLayer, x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    return _texel(texture, x - grid.x * SaChunk.SIZE, y - grid.y * SaChunk.SIZE)


## A red layer everywhere, so a copy has something to take and a cut something
## to leave a hole in.
func _paint_everywhere() -> void:
    _doc.active_layer.fill(RED)


func _layer_count() -> int:
    return SaLayerOps.new(_doc).layers().size()


func test_a_copy_takes_the_selection_and_nothing_outside_it() -> void:
    _paint_everywhere()
    _doc.selection.select_rect(Rect2i(100, 100, 200, 200))

    var taken := _held.copy(_doc, _doc.active_layer)

    assert_eq(taken, 4, "A rectangle over the seams takes four chunks")
    assert_eq(_held.bounds, Rect2i(100, 100, 200, 200), "and remembers where they were")
    var copied: SaChunk = _held.chunks[Vector2i(0, 0)]
    assert_almost_eq(_texel(copied.albedo(), 150, 150).a, 1.0, 1e-4, "Inside the selection the copy is opaque")
    assert_almost_eq(_texel(copied.albedo(), 150, 150).r, 1.0, 1e-4, "and red")
    assert_almost_eq(_texel(copied.albedo(), 50, 50).a, 0.0, 1e-6, "Outside it the copy is transparent")
    assert_almost_eq(_layer_texel(_doc.active_layer, 150, 150).a, 1.0, 1e-4, "and the source is untouched by a copy")
    assert_true(_held.space.matches(_doc.color_space), "The copy knows what its colours mean")


func test_without_a_selection_a_copy_takes_the_whole_layer() -> void:
    _paint_everywhere()

    var taken := _held.copy(_doc, _doc.active_layer)

    assert_eq(taken, 4, "Every chunk of the layer")
    assert_eq(_held.bounds, Rect2i(0, 0, 512, 512), "over the whole canvas")
    var copied: SaChunk = _held.chunks[Vector2i(1, 1)]
    assert_almost_eq(_texel(copied.albedo(), 200, 200).a, 1.0, 1e-4, "with its alpha as it was")


func test_a_cut_leaves_a_hole_the_size_of_the_selection_and_undo_fills_it() -> void:
    _paint_everywhere()
    _doc.selection.select_rect(Rect2i(0, 0, 128, 128))
    var steps_before: int = _doc.history.step_count()

    assert_true(_held.cut(_doc, _doc.active_layer), "A cut with paint under the selection happens")

    assert_almost_eq(_layer_texel(_doc.active_layer, 64, 64).a, 0.0, 1e-6, "Inside the selection the layer is cleared")
    assert_almost_eq(_layer_texel(_doc.active_layer, 127, 64).a, 0.0, 1e-6, "up to the last selected column")
    assert_almost_eq(_layer_texel(_doc.active_layer, 128, 64).a, 1.0, 1e-4, "and not one pixel further")
    assert_almost_eq(_layer_texel(_doc.active_layer, 300, 300).a, 1.0, 1e-4, "nor in a chunk the selection left out")
    assert_eq(_held.chunks.size(), 1, "and the clipboard holds what was cut")
    assert_eq(_doc.history.step_count(), steps_before + 1, "as one history step")

    assert_true(_doc.undo(), "which undoes")
    assert_almost_eq(_layer_texel(_doc.active_layer, 64, 64).a, 1.0, 1e-4, "bringing the pixels back")
    assert_true(_doc.redo(), "and redoes")
    assert_almost_eq(_layer_texel(_doc.active_layer, 64, 64).a, 0.0, 1e-6, "cutting them again")


func test_a_paste_lands_in_place_as_a_new_layer_above_the_active_one() -> void:
    _paint_everywhere()
    _doc.selection.select_rect(Rect2i(300, 300, 100, 100))
    _held.copy(_doc, _doc.active_layer)
    var source := _doc.active_layer
    var layers_before := _layer_count()

    var pasted := _held.paste(_doc)

    assert_not_null(pasted, "A paste makes a layer")
    assert_eq(_layer_count(), layers_before + 1, "one more than before")
    assert_eq(pasted.get_index(), source.get_index() + 1, "directly above the one that was active")
    assert_eq(_doc.active_layer, pasted, "and it is the active one now")
    assert_eq(str(pasted.name), "Pasted Layer", "named for what it is")
    assert_almost_eq(_layer_texel(pasted, 350, 350).r, 1.0, 1e-4, "with the copied pixels where they came from")
    assert_almost_eq(_layer_texel(pasted, 350, 350).a, 1.0, 1e-4, "opaque inside the selection")
    assert_almost_eq(_layer_texel(pasted, 100, 100).a, 0.0, 1e-6, "and nothing outside it")
    assert_eq(pasted.chunks.size(), 1, "in one chunk, because the copy was sparse")

    var again := _held.paste(_doc)
    assert_eq(str(again.name), "Pasted Layer 2", "A second paste is a second layer")
    assert_almost_eq(_layer_texel(again, 350, 350).r, 1.0, 1e-4, "with the same picture, since the clipboard keeps its own")

    assert_true(_doc.undo(), "Undo takes the second paste out")
    assert_eq(_layer_count(), layers_before + 1, "leaving the first")


func test_a_paste_from_another_space_converts_into_this_one() -> void:
    _doc.active_layer.fill(Color(0.5, 0.5, 0.5, 1.0))
    _held.copy(_doc, _doc.active_layer)
    assert_true(SaColorConversion.new(_doc).convert_to(SaColorSpace.linear_srgb()), "The document moves to linear")

    var pasted := _held.paste(_doc)

    # A mid grey encoded in sRGB is 0.214 in light, which is what the pasted
    # layer has to hold for it to look the same beside the converted layer.
    var texel := _layer_texel(pasted, 10, 10)
    assert_almost_eq(texel.r, 0.2140, 2e-3, "The pasted grey was converted from sRGB to linear")
    assert_almost_eq(texel.a, 1.0, 1e-4, "and stays opaque")


func test_a_paste_across_depths_is_refused_and_says_so() -> void:
    _paint_everywhere()
    _held.copy(_doc, _doc.active_layer)
    var half := SaEasel.create_default(Vector2i(256, 256))
    half.document.reset_to_default(Vector2i(256, 256), SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F16))
    var layers_before: int = SaLayerOps.new(half.document).layers().size()
    # The refusal record and not the fault record, because a paste across depths
    # is the painter's own gesture refused and sent to the corner.
    var reported_before: int = SaProblems.pending_refusals.size()

    # The refusal is the point, so it is recorded without the alarm.
    SaProblems.announce = false
    var pasted := _held.paste(half.document)
    SaProblems.announce = true

    assert_null(pasted, "An F32 clipboard does not paste into an F16 document")
    assert_eq(SaLayerOps.new(half.document).layers().size(), layers_before, "and no layer was added")
    assert_eq(SaProblems.pending_refusals.size(), reported_before + 1, "and the refusal reached the problem record")
    half.free()


func test_an_empty_clipboard_pastes_nothing() -> void:
    var layers_before := _layer_count()
    assert_true(_held.is_empty(), "Fresh, it holds nothing")
    assert_null(_held.paste(_doc), "so a paste makes no layer")
    assert_eq(_layer_count(), layers_before, "and the stack is as it was")


func test_the_clipboard_survives_file_new() -> void:
    _paint_everywhere()
    _held.copy(_doc, _doc.active_layer)
    _doc.reset_to_default(Vector2i(512, 512))
    assert_false(_held.is_empty(), "What was copied is still there to paste into the new picture")
