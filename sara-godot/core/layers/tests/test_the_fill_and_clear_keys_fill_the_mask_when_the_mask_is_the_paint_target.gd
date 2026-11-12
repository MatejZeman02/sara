## While a layer's mask is the paint target, Fill with
## Foreground, Fill with Background and Clear act on the mask and leave the
## layer's pixels alone. A painter's note of 2026-10-31 was "fill shortcut
## doesn't respect when a mask layer is selected": `_fill_command` read the
## active layer and never the mask target, so the fill landed on the paint.
##
## Each case runs the registered command, the one every chord and menu row
## reaches, reads the mask texel by texel inside and outside the selection,
## reads the layer's albedo before and after, and undoes once.
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
var _layer: SaLayer = null
var _pair: Array = []
var _notices: Array[String] = []


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(512, 512))
    _registries = Fixtures.make_registries(_surface)
    _doc = _surface.easel.document
    _layer = _doc.active_layer
    _layer.fill(RED)
    _pair = [SaColors.foreground, SaColors.background]
    _notices.clear()
    EventBus.corner_notice.connect(_hear)


func after_each() -> void:
    EventBus.corner_notice.disconnect(_hear)
    SaColors.foreground = _pair[0]
    SaColors.background = _pair[1]
    _registries = null
    Fixtures.teardown(_surface)
    _surface = null
    _doc = null
    _layer = null


func _hear(line: String) -> void:
    _notices.append(line)


func _texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


func _grid(at: Vector2i) -> Vector2i:
    @warning_ignore("integer_division")
    return Vector2i(at.x / SaChunk.SIZE, at.y / SaChunk.SIZE)


## The coverage the layer's mask holds at a document pixel, its rest where it
## holds nothing.
func _coverage(at: Vector2i) -> float:
    var texture := _layer.mask.texture_for(_grid(at))
    if texture == null:
        return _layer.mask.rest
    return _texel(texture, at - _grid(at) * SaChunk.SIZE).r


func _paint(at: Vector2i) -> Color:
    return _texel(_layer.get_field(_grid(at)), at - _grid(at) * SaChunk.SIZE)


## The layer's paint at the three pixels, which no mask fill may move.
func _paints() -> Array[Color]:
    return [_paint(INSIDE), _paint(BESIDE), _paint(AFAR)]


## A mask on the layer, hiding nothing when *showing* and everything otherwise,
## made the mask target, with the history cleared so a case counts its own.
func _target_mask(showing: bool) -> void:
    var ops := SaMaskOps.new(_doc)
    ops.add(_layer)
    if not showing:
        ops.invert(_layer)
    _doc.mask_target = _layer.mask
    _doc.undo_redo.clear_history()


func test_a_white_fill_inside_a_selection_shows_the_rectangle_and_nothing_else() -> void:
    _target_mask(false)
    _doc.selection.select_rect(BOX)
    SaColors.foreground = WHITE
    var paint := _paints()
    var steps := _doc.undo_redo.get_history_count()

    assert_true(_registries.commands.execute(&"fill_foreground"), "Fill with Foreground runs with the mask the target")
    assert_almost_eq(_coverage(INSIDE), 1.0, 0.001, "the mask shows inside the rectangle")
    assert_almost_eq(_coverage(BESIDE), 0.0, 0.001, "and still hides beside it in the same chunk")
    assert_almost_eq(_coverage(AFAR), 0.0, 0.001, "and in another chunk")
    assert_eq(_paints(), paint, "the layer's paint is what it was")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "in one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Fill Mask", "titled for the mask")
    assert_true(_notices.is_empty(), "and a fill inside a selection says nothing")

    assert_true(_doc.undo(), "one undo")
    assert_almost_eq(_coverage(INSIDE), 0.0, 0.001, "puts the hidden mask back")
    assert_eq(_paints(), paint, "with the paint untouched")


func test_clear_inside_a_selection_hides_the_rectangle_and_nothing_else() -> void:
    _target_mask(true)
    _doc.selection.select_rect(BOX)
    var paint := _paints()

    assert_true(_registries.commands.execute(&"layer_clear"), "Clear runs with the mask the target")
    assert_almost_eq(_coverage(INSIDE), 0.0, 0.001, "the rectangle is hidden")
    assert_almost_eq(_coverage(BESIDE), 1.0, 0.001, "and beside it still shows")
    assert_almost_eq(_coverage(AFAR), 1.0, 0.001, "as does another chunk")
    assert_eq(_paints(), paint, "the layer's paint is what it was, alpha and all")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Clear Mask", "titled for the mask")

    assert_true(_doc.undo(), "one undo")
    assert_almost_eq(_coverage(INSIDE), 1.0, 0.001, "shows the rectangle again")


func test_with_nothing_selected_the_fill_and_the_clear_take_the_whole_mask() -> void:
    _target_mask(true)
    SaColors.background = BLACK
    var paint := _paints()

    assert_true(_registries.commands.execute(&"fill_background"), "Fill with Background runs")
    for at: Vector2i in [INSIDE, BESIDE, AFAR]:
        assert_almost_eq(_coverage(at), 0.0, 0.001, "black hides the whole mask at %s" % at)
    assert_eq(_notices.size(), 1, "and the corner says the fill took everything")
    assert_true(_notices[0].contains("mask"), "naming the mask: %s" % _notices[0])

    SaColors.foreground = WHITE
    assert_true(_registries.commands.execute(&"fill_foreground"), "Fill with Foreground runs")
    assert_almost_eq(_coverage(AFAR), 1.0, 0.001, "white shows it all again")
    assert_true(_registries.commands.execute(&"layer_clear"), "and Clear runs")
    for at: Vector2i in [INSIDE, BESIDE, AFAR]:
        assert_almost_eq(_coverage(at), 0.0, 0.001, "clear hides the whole mask at %s" % at)
    assert_true(_notices[2].contains("mask"), "naming the mask: %s" % _notices[2])
    assert_eq(_paints(), paint, "the layer's paint is what it was through all three")

    assert_true(_doc.undo(), "one undo")
    for at: Vector2i in [INSIDE, BESIDE, AFAR]:
        assert_almost_eq(_coverage(at), 1.0, 0.001, "gives back the white fill at %s" % at)


func test_a_grey_fills_the_coverage_a_brush_takes_from_it() -> void:
    _target_mask(true)
    _doc.selection.select_rect(BOX)
    var grey := Color(0.5, 0.5, 0.5, 1.0)
    SaColors.foreground = grey
    var space := _doc.color_space
    var expected := clampf(space.lightness(space.from_display(grey)), 0.0, 1.0)

    assert_true(_registries.commands.execute(&"fill_foreground"), "the fill runs")
    assert_almost_eq(_coverage(INSIDE), expected, 0.001, "the mask holds the grey's lightness")
    assert_true(expected > 0.05 and expected < 0.95, "which is a grey between: %s" % expected)


func test_a_locked_layer_refuses_its_mask_fill() -> void:
    _target_mask(true)
    _layer.is_locked = true
    SaColors.background = BLACK

    assert_false(_registries.commands.execute(&"fill_background"), "the fill is declined")
    assert_false(_registries.commands.execute(&"layer_clear"), "and so is the clear")
    _layer.is_locked = false
    assert_almost_eq(_coverage(AFAR), 1.0, 0.001, "the mask is as it was")
    assert_eq(_doc.undo_redo.get_history_count(), 0, "and nothing reached the history")


func test_with_the_layer_the_target_the_keys_act_on_the_layer_as_before() -> void:
    _target_mask(true)
    _doc.mask_target = null
    SaColors.foreground = Color(0.0, 0.0, 1.0, 1.0)
    _doc.selection.select_rect(BOX)

    assert_true(_registries.commands.execute(&"fill_foreground"), "Fill with Foreground runs on the layer")
    assert_almost_eq(_paint(INSIDE).b, 1.0, 0.001, "the rectangle is blue")
    assert_almost_eq(_paint(BESIDE).r, 1.0, 0.001, "and beside it still red")
    assert_almost_eq(_coverage(INSIDE), 1.0, 0.001, "while the mask is untouched")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Fill Layer", "titled for the layer")

    assert_true(_registries.commands.execute(&"layer_clear"), "Clear runs on the layer")
    assert_almost_eq(_paint(INSIDE).a, 0.0, 0.001, "the rectangle is empty")
    assert_almost_eq(_paint(BESIDE).a, 1.0, 0.001, "and beside it still painted")
    assert_almost_eq(_coverage(INSIDE), 1.0, 0.001, "and the mask still shows")
