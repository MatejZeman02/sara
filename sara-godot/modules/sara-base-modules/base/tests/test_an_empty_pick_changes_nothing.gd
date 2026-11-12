## A pick over canvas where nothing is painted leaves the colour as it was, and
## says so in the corner once a press.
##
## The Eyedropper, with Sample set to Layer, clicked on a fresh layer must not set the foreground to
## rgba (2.896, -1.651, -0.725, 0), which would paint the next stroke solid red.
## A pick of a chunk nobody painted answering `Color.TRANSPARENT` would do it, as
## that is Godot's transparent white, and the Oklab default reads white's
## (1, 1, 1) as a lightness and two opponents far past any colour. The pick
## answers transparent black, and a pick of no coverage
## is not emitted at all, on the layer and on the view, at one texel and at nine.
## The same click on the running app is
## `scenarios/the-eyedropper-on-an-empty-layer-pixel-sets-no-garbage-colour.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")

## The colour the painter had before the pick.
const KEPT := Color(0.16, 0.3, 0.56, 1.0)
## A colour painted where a pick should find it.
const PAINTED := Color(0.8, 0.4, 0.1, 1.0)

var _picked: Array[Color] = []
var _notices: Array[String] = []


func before_each() -> void:
    _picked.clear()
    _notices.clear()
    EventBus.color_picked.connect(_on_picked)
    EventBus.corner_notice.connect(_on_notice)


func after_each() -> void:
    EventBus.color_picked.disconnect(_on_picked)
    EventBus.corner_notice.disconnect(_on_notice)


## The eyedropper with a pointer the suite moves.
class ScriptedPointer:
    extends "res://modules/sara-base-modules/base/tools/state_eyedropper.gd"

    var at := Vector2(100, 100)

    func get_document_mouse_position() -> Vector2:
        return at


## The pick itself answers transparent black where no chunk is, so no colour
## space can read a colour into it.
func test_a_pick_of_a_chunk_nobody_painted_is_transparent_black() -> void:
    var surface := _surface()
    var eyedropper := _eyedropper(surface, StateEyedropperScript.SampleFrom.LAYER, 1)
    var picked := eyedropper.pick_color_at_pos(Vector2(100, 100))
    assert_eq(picked, Color(0, 0, 0, 0), "No chunk is no paint, got %s" % picked)
    _free(surface)


func test_an_empty_layer_pick_changes_nothing_at_one_and_at_nine() -> void:
    for side: int in [1, 9]:
        var surface := _surface()
        var eyedropper := _eyedropper(surface, StateEyedropperScript.SampleFrom.LAYER, side)
        _click(eyedropper)
        assert_eq(_picked.size(), 0, "At %d, a click on a fresh layer picks nothing, got %s" % [side, _picked])
        assert_eq(_notices.size(), 1, "and says so once")
        _clear_heard()
        _free(surface)


## A chunk that exists because a stroke landed elsewhere in it holds no paint at
## the texel the click is on.
func test_an_unpainted_texel_of_a_painted_chunk_changes_nothing() -> void:
    for side: int in [1, 9]:
        var surface := _surface()
        var layer := surface.get_document().active_layer
        layer.get_or_create_chunk(Vector2i.ZERO)
        var eyedropper := _eyedropper(surface, StateEyedropperScript.SampleFrom.LAYER, side)
        _click(eyedropper)
        assert_eq(_picked.size(), 0, "At %d, an empty texel of a held chunk picks nothing" % side)
        assert_eq(_notices.size(), 1, "and says so once")
        _clear_heard()
        _free(surface)


func test_an_empty_view_pick_changes_nothing_at_one_and_at_nine() -> void:
    for side: int in [1, 9]:
        var surface := _surface()
        # Transparent white, the value that turned into the garbage colour.
        GlobalShaderCompiler.get_rd().texture_clear(surface.easel.output.rid, Color(1, 1, 1, 0), 0, 1, 0, 1)
        var eyedropper := _eyedropper(surface, StateEyedropperScript.SampleFrom.VIEW, side)
        _click(eyedropper)
        assert_eq(_picked.size(), 0, "At %d, a view with nothing in it picks nothing" % side)
        assert_eq(_notices.size(), 1, "and says so once")
        _clear_heard()
        _free(surface)


func test_a_painted_pixel_still_picks_on_the_layer_and_the_view() -> void:
    for from: int in [StateEyedropperScript.SampleFrom.LAYER, StateEyedropperScript.SampleFrom.VIEW]:
        for side: int in [1, 9]:
            var surface := _surface()
            var doc := surface.get_document()
            var stored := doc.color_space.from_display(PAINTED)
            doc.active_layer.fill(stored)
            GlobalShaderCompiler.get_rd().texture_clear(surface.easel.output.rid, stored, 0, 1, 0, 1)
            var eyedropper := _eyedropper(surface, from, side)
            _click(eyedropper)
            var what := "%s at %d" % ["Layer" if from == StateEyedropperScript.SampleFrom.LAYER else "View", side]
            assert_eq(_picked.size(), 1, "%s, a painted pixel is picked" % what)
            if _picked.size() == 1:
                assert_true(_near(_picked[0], PAINTED), "%s, as the colour painted, got %s" % [what, _picked[0]])
            assert_eq(_notices.size(), 0, "%s, and says nothing" % what)
            _clear_heard()
            _free(surface)


## A drag across empty canvas samples once a frame and says so once, and a drag
## that reaches paint picks it.
func test_a_drag_says_it_once_and_picks_the_paint_it_reaches() -> void:
    var surface := _surface()
    var layer := surface.get_document().active_layer
    var chunk := layer.get_or_create_chunk(Vector2i(1, 0))
    chunk.field(SaFieldSpec.ALBEDO).clear(surface.get_document().color_space.from_display(PAINTED))
    var eyedropper := _eyedropper(surface, StateEyedropperScript.SampleFrom.LAYER, 1)

    eyedropper.handle_input(_button(true))
    for x: int in [110, 120, 130]:
        eyedropper.at = Vector2(x, 100)
        eyedropper.handle_input(InputEventMouseMotion.new())
        eyedropper.tick(0.016)
    assert_eq(_picked.size(), 0, "Four samples of empty canvas pick nothing")
    assert_eq(_notices.size(), 1, "and say so once, not once a frame")

    eyedropper.at = Vector2(300, 100)
    eyedropper.handle_input(InputEventMouseMotion.new())
    eyedropper.tick(0.016)
    eyedropper.handle_input(_button(false))
    assert_eq(_picked.size(), 1, "The paint the drag reaches is picked")
    if _picked.size() == 1:
        assert_true(_near(_picked[0], PAINTED), "as the colour painted, got %s" % _picked[0])

    _clear_heard()
    eyedropper.at = Vector2(100, 100)
    _click(eyedropper)
    assert_eq(_notices.size(), 1, "The next press over empty canvas says so again")
    _free(surface)


## The document Sara opens on, Oklab with a cube-root curve, where white's
## transparent triple is the furthest from a colour.
func _surface() -> SaSurface:
    var surface := Fixtures.make_surface(Vector2i(512, 256))
    surface.get_document().color_space = SaColorSpace.oklab_srgb_gamma30()
    return surface


func _eyedropper(surface: SaSurface, from: int, side: int) -> ScriptedPointer:
    var eyedropper := ScriptedPointer.new()
    eyedropper.surface = surface
    eyedropper.sample_from = from as StateEyedropperScript.SampleFrom
    eyedropper.sample_size = side
    return eyedropper


func _click(eyedropper: ScriptedPointer) -> void:
    eyedropper.handle_input(_button(true))
    eyedropper.handle_input(_button(false))


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


func _free(surface: SaSurface) -> void:
    surface.get_document().free()
    surface.easel.free()


func _clear_heard() -> void:
    _picked.clear()
    _notices.clear()


func _near(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


func _on_picked(color: Color) -> void:
    _picked.append(color)


func _on_notice(line: String) -> void:
    _notices.append(line)
