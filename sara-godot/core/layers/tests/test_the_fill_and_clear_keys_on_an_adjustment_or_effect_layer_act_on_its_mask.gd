## On a layer that holds no pixels of its own, an adjustment
## or an effect layer, Fill with Foreground, Fill with Background and Clear act
## on its mask, giving it one first, and no key ever says it cleared or filled
## when nothing changed. A painter's note of 2026-10-31 was "I cannot clear a
## layer by backspace", on a paint layer converted to an adjustment: the clear
## released chunks the layer never had and the corner still said the whole
## layer was cleared.
##
## Each case runs the registered command, the one every chord reaches, and
## reads the mask's coverage texel by texel inside and outside the selection.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The proof is the coverage the kernel wrote, which needs a RenderingDevice.
const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)
const WHITE := Color(1.0, 1.0, 1.0, 1.0)
const BLACK := Color(0.0, 0.0, 0.0, 1.0)

## The rectangle selected, inside the first chunk, and a pixel in it, a pixel
## of the same chunk outside it and a pixel of another chunk.
const BOX := Rect2i(40, 40, 100, 80)
const INSIDE := Vector2i(60, 60)
const BESIDE := Vector2i(200, 200)
const AFAR := Vector2i(400, 400)

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _doc: SaDocument = null
var _paint: SaLayer = null
var _layer: SaLayer = null
var _pair: Array = []
var _notices: Array[String] = []
var _refusals: Array[String] = []


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(512, 512))
    _registries = Fixtures.make_registries(_surface)
    _doc = _surface.easel.document
    _paint = _doc.active_layer
    _paint.fill(RED)
    _pair = [SaColors.foreground, SaColors.background]
    _notices.clear()
    _refusals.clear()
    EventBus.corner_notice.connect(_hear)
    EventBus.paint_refused.connect(_refused)


func after_each() -> void:
    EventBus.corner_notice.disconnect(_hear)
    EventBus.paint_refused.disconnect(_refused)
    SaColors.foreground = _pair[0]
    SaColors.background = _pair[1]
    _registries = null
    Fixtures.teardown(_surface)
    _surface = null
    _doc = null
    _paint = null
    _layer = null


func _hear(line: String) -> void:
    _notices.append(line)


func _refused(line: String) -> void:
    _refusals.append(line)


## A layer of *input* above the paint, active, with no mask and a clear history,
## the shape of a painter's "Desaturate".
func _above(input: StringName) -> void:
    _layer = SaLayer.new()
    _layer.name = "Desaturate"
    _layer.input = input
    _doc.add_child(_layer)
    _doc.active_layer = _layer
    _doc.undo_redo.clear_history()


func _grid(at: Vector2i) -> Vector2i:
    @warning_ignore("integer_division")
    return Vector2i(at.x / SaChunk.SIZE, at.y / SaChunk.SIZE)


## The coverage the layer's mask holds at a document pixel, its rest where it
## holds nothing.
func _coverage(at: Vector2i) -> float:
    var texture := _layer.mask.texture_for(_grid(at))
    if texture == null:
        return _layer.mask.rest
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local := at - _grid(at) * SaChunk.SIZE
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * texture.size.x + local.x).r


func test_clear_with_nothing_selected_hides_the_adjustment_through_a_mask_it_gains() -> void:
    _above(SaLayerTypeDescriptor.INPUT_BELOW)
    assert_null(_layer.mask, "the adjustment starts with no mask")

    assert_true(_registries.commands.execute(&"layer_clear"), "Clear runs on the adjustment")
    assert_not_null(_layer.mask, "the adjustment has a mask now")
    for at: Vector2i in [INSIDE, BESIDE, AFAR]:
        assert_almost_eq(_coverage(at), 0.0, 0.001, "which hides it at %s" % at)
    assert_eq(_doc.undo_redo.get_history_count(), 1, "in one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Clear Mask", "titled for the mask")
    assert_eq(_notices.size(), 1, "the corner says what happened")
    assert_true(_notices[0].contains("adjustment is hidden across the whole layer"), "in the mask's words: %s" % _notices[0])
    assert_true(_paint.chunks.size() > 0, "and the paint below keeps its chunks")

    assert_true(_doc.undo(), "one undo")
    assert_null(_layer.mask, "takes the added mask away")


func test_clear_inside_a_selection_hides_the_adjustment_there_only_and_one_undo_takes_the_mask_away() -> void:
    _above(SaLayerTypeDescriptor.INPUT_BELOW)
    _doc.selection.select_rect(BOX)

    assert_true(_registries.commands.execute(&"layer_clear"), "Clear runs on the adjustment")
    assert_almost_eq(_coverage(INSIDE), 0.0, 0.001, "the rectangle hides the adjustment")
    assert_almost_eq(_coverage(BESIDE), 1.0, 0.001, "beside it in the same chunk it still shows")
    assert_almost_eq(_coverage(AFAR), 1.0, 0.001, "and in another chunk")
    assert_eq(_doc.undo_redo.get_history_count(), 1, "in one step")
    assert_true(_notices[0].contains("adjustment is hidden in the selected area"), "the corner says where: %s" % _notices[0])

    assert_true(_doc.undo(), "one undo")
    assert_null(_layer.mask, "takes the mask away with the clear")


func test_the_fill_keys_write_the_colour_s_grey_into_an_effect_layer_s_mask() -> void:
    _above(SaLayerTypeDescriptor.INPUT_NAMED)
    SaColors.foreground = BLACK
    SaColors.background = WHITE

    assert_true(_registries.commands.execute(&"fill_foreground"), "black fills the effect")
    for at: Vector2i in [INSIDE, BESIDE, AFAR]:
        assert_almost_eq(_coverage(at), 0.0, 0.001, "and hides it at %s" % at)
    assert_eq(_doc.undo_redo.get_current_action_name(), "Fill Mask", "titled for the mask")
    assert_true(_registries.commands.execute(&"fill_background"), "white fills it")
    for at: Vector2i in [INSIDE, BESIDE, AFAR]:
        assert_almost_eq(_coverage(at), 1.0, 0.001, "and shows it again at %s" % at)

    _doc.selection.select_rect(BOX)
    assert_true(_registries.commands.execute(&"fill_foreground"), "black inside a selection")
    assert_almost_eq(_coverage(INSIDE), 0.0, 0.001, "hides the rectangle")
    assert_almost_eq(_coverage(BESIDE), 1.0, 0.001, "and nothing beside it")


func test_a_clear_that_changes_nothing_answers_false_and_says_nothing_was_cleared() -> void:
    _above(SaLayerTypeDescriptor.INPUT_BELOW)
    assert_true(_registries.commands.execute(&"layer_clear"), "the first clear hides the adjustment")
    var steps := _doc.undo_redo.get_history_count()
    _notices.clear()

    assert_false(_registries.commands.execute(&"layer_clear"), "a second clear changes nothing and answers false")
    assert_true(_notices.is_empty(), "no corner line says something was cleared: %s" % [_notices])
    assert_eq(_refusals.size(), 1, "the refusal says why")
    assert_true(_refusals[0].contains("nothing changed"), "in words: %s" % _refusals[0])
    assert_eq(_doc.undo_redo.get_history_count(), steps, "and nothing reached the history")


func test_a_paint_layer_with_nothing_to_clear_answers_false() -> void:
    _paint.release_chunks()
    _doc.undo_redo.clear_history()

    assert_false(_registries.commands.execute(&"layer_clear"), "an empty layer's clear answers false")
    assert_true(_notices.is_empty(), "with no line that the whole layer was cleared: %s" % [_notices])
    assert_eq(_refusals.size(), 1, "and a reason in the corner")
    assert_eq(_doc.undo_redo.get_history_count(), 0, "and no step")

    _paint.fill(RED)
    _doc.selection.select_rect(BOX)
    assert_true(_registries.commands.execute(&"layer_clear"), "a painted layer's clear under a selection still runs")
