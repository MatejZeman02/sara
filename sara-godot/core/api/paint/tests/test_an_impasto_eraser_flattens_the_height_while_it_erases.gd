## An impasto eraser flattens the height while it erases.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter's note of 2026-10-02: erasing with the impasto brush should
## flatten the layer as it goes, and the relief instead stood at full height
## until the pen lifted and then dropped all at once. A wash eraser gathers its
## coverage in the stroke buffer and carved the height at its commit only, so
## the relief under the pen was the layer's own and untouched. The document now
## lowers it under each region a wash eraser's dabs land on.
##
## Both engines erase in wash here, the noise brush always and the stamp when
## its painting mode asks, and each case reads the height back mid-stroke and
## after the lift, because a height that only moved at the lift reads right
## after it. The ground is a height of 2 under opaque white, and the eraser's
## opacity of a half takes it to 1 wherever the tip covers it fully.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const GammaFloatScript = preload("res://modules/sara-base-modules/stamp-brush/tools/gamma_float.gd")

## The height the ground stands at, in virtual millimetres.
const GROUND := 2.0
## The noise stroke runs from here to [constant TO] along one row.
const FROM := Vector2(30.0, 128.0)
const TO := Vector2(220.0, 128.0)
## A texel the noise stroke has passed by its middle, and one it reaches only
## after it.
const BEHIND := Vector2i(60, 128)
const AHEAD := Vector2i(190, 128)

var _surface: SaSurface = null
var _doc: SaDocument = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _doc = _surface.easel.document
    # Without the registry every mode composites as Normal, and the erase's
    # commit would leave the alpha where it was.
    _surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    SaHeightOps.new(_doc).gain(_doc.active_layer)
    var grid := Vector2i.ZERO
    var height := _doc.active_layer.get_or_create_field(grid, SaFieldSpec.HEIGHT)
    var bytes := PackedByteArray()
    bytes.resize(height.size.x * height.size.y * 2)
    for i in height.size.x * height.size.y:
        bytes.encode_half(i * 2, GROUND)
    GlobalShaderCompiler.get_rd().texture_update(height.rid, 0, bytes)
    _doc.active_layer.get_or_create_chunk(grid).albedo().clear(Color(1.0, 1.0, 1.0, 1.0))


func after_each() -> void:
    Fixtures.teardown(_surface)
    _surface = null
    _doc = null


## A hard noise eraser at half opacity whose cut lets every texel the tip
## reaches through, so the coverage is the tip's alone.
func _noise_eraser() -> StateNoiseBrushScript:
    var brush := StateNoiseBrushScript.new()
    brush.surface = _surface
    brush.stroke_seed = 7
    brush.settings.opacity = 0.5
    brush.settings.hardness = 1.0
    brush.settings.strength = 0.0
    brush.settings.strength_option.enabled = false
    brush.settings.radius = 12.0 / 256.0
    brush.settings.blend_mode = SaLayer.BLEND_MODE.ERASE
    return brush


## The layer's height at *at*, nought where it holds none.
func _height(at: Vector2i) -> float:
    var texture := _doc.active_layer.get_field(Vector2i.ZERO, SaFieldSpec.HEIGHT)
    if texture == null:
        return 0.0
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return bytes.decode_half((at.y * texture.size.x + at.x) * 2)


func _alpha(at: Vector2i) -> float:
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(_doc.active_layer.get_field(Vector2i.ZERO))
    return image.get_pixelv(at).a


func test_the_noise_eraser_lowers_the_height_under_the_pen_before_the_lift() -> void:
    var brush := _noise_eraser()
    brush.begin_stroke(FROM, 1.0)
    var steps := 20
    var half := 10
    for i in range(1, half + 1):
        brush.add_sample(FROM.lerp(TO, float(i) / steps), 1.0)
    assert_almost_eq(_height(BEHIND), GROUND * 0.5, 0.01, "The height the pen has passed is halved before the lift")
    assert_eq(_height(AHEAD), GROUND, "and the height it has not reached stands")
    assert_almost_eq(_alpha(BEHIND), 1.0, 0.001, "while the alpha waits for the lift, as a wash does")
    for i in range(half + 1, steps + 1):
        brush.add_sample(FROM.lerp(TO, float(i) / steps), 1.0)
    var before_lift := _height(BEHIND)
    brush.end_stroke()
    assert_eq(_height(BEHIND), before_lift, "The lift changes the height it lowered no further")
    assert_almost_eq(_height(AHEAD), GROUND * 0.5, 0.01, "and the rest of the stroke is lowered as well")
    assert_almost_eq(_alpha(BEHIND), 0.5, 0.01, "The lift carves the alpha by the same half")


func test_one_undo_gives_the_noise_erasers_height_and_alpha_back() -> void:
    var brush := _noise_eraser()
    brush.begin_stroke(FROM, 1.0)
    for i in range(1, 11):
        brush.add_sample(FROM.lerp(TO, float(i) / 10.0), 1.0)
    brush.end_stroke()
    assert_almost_eq(_height(BEHIND), GROUND * 0.5, 0.01, "The stroke lowered the height")
    assert_true(_doc.undo(), "One undo takes the stroke back")
    assert_eq(_height(BEHIND), GROUND, "and the height stands as it did")
    assert_almost_eq(_alpha(BEHIND), 1.0, 0.001, "and so does the alpha")


## A wash stamp eraser lays its press dab as the pen first moves, outside any
## walk, so the height under it is read before the release.
func test_the_wash_stamp_eraser_lowers_the_height_under_its_press() -> void:
    var at := Vector2i(128, 128)
    (_surface.view as Fixtures.FakeView).mouse_position = Vector2(at)
    var brush := StateBrushScript.new()
    brush.surface = _surface
    brush.settings.opacity = 0.5
    brush.settings.radius = 0.1
    brush.settings.hardness = GammaFloatScript.new(1.0, 1.0)
    brush.settings.opacity_by_pressure = false
    brush.settings.painting_mode = StampSettingsScript.PaintingMode.WASH
    brush.eraser_toggled = true
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    brush.handle_input(press)
    # A press with no pressure reads as a pen's hover, whose dab waits for the
    # first motion, so one motion where the press was lays it.
    var motion := InputEventMouseMotion.new()
    motion.pressure = 1.0
    brush.handle_input(motion)
    assert_almost_eq(_height(at), GROUND * 0.5, 0.01, "The press dab halves the height under it before the release")
    var lift := InputEventMouseButton.new()
    lift.button_index = MOUSE_BUTTON_LEFT
    lift.pressed = false
    brush.handle_input(lift)
    assert_almost_eq(_height(at), GROUND * 0.5, 0.01, "and the release lowers it no further")
    assert_almost_eq(_alpha(at), 0.5, 0.01, "while the alpha falls by the same half at the release")
    assert_true(_doc.undo(), "One undo takes the stroke back")
    assert_eq(_height(at), GROUND, "with its height")
