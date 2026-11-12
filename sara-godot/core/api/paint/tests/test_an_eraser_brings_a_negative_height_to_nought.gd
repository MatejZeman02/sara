## An eraser brings a negative height to nought.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A layer's height is signed, the maintainers' ruling of 2026-10-02, so a stroke
## that levelled a lower layer's bump holds a negative height. Erasing moves a
## layer's own height towards nought under each dab, and a
## wash eraser's `height_erased` only ever let a texel fall, so a negative
## height under it stood where it was. It comes nearer nought now from either
## side, and never past it.
##
## The ground is a height of minus 2 under opaque white. Each engine erases
## it, the noise brush and the stamp in wash, which lower through the
## document as the stroke goes, and the stamp in build-up, whose dab lowers
## texel by texel, and each case reads the height back across the tip.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const GammaFloatScript = preload("res://modules/sara-base-modules/stamp-brush/tools/gamma_float.gd")

## The height the ground stands at, in virtual millimetres, below nought.
const GROUND := -2.0
## The noise stroke runs from here to [constant TO] along one row.
const FROM := Vector2(30.0, 128.0)
const TO := Vector2(220.0, 128.0)
## A texel the noise stroke passes over.
const UNDER := Vector2i(120, 128)

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


## A hard noise eraser at *opacity* whose cut lets every texel the tip
## reaches through, so the coverage is the tip's alone.
func _noise_eraser(opacity: float) -> StateNoiseBrushScript:
    var brush := StateNoiseBrushScript.new()
    brush.surface = _surface
    brush.stroke_seed = 7
    brush.settings.opacity = opacity
    brush.settings.hardness = 1.0
    brush.settings.strength = 0.0
    brush.settings.strength_option.enabled = false
    brush.settings.radius = 12.0 / 256.0
    brush.settings.blend_mode = SaLayer.BLEND_MODE.ERASE
    return brush


func _noise_stroke(opacity: float) -> void:
    var brush := _noise_eraser(opacity)
    brush.begin_stroke(FROM, 1.0)
    for i in range(1, 21):
        brush.add_sample(FROM.lerp(TO, float(i) / 20.0), 1.0)
    brush.end_stroke()


## A stamp eraser at full opacity in *mode*, one press dab at *at*.
func _stamp_dab(at: Vector2i, mode: StampSettingsScript.PaintingMode) -> void:
    (_surface.view as Fixtures.FakeView).mouse_position = Vector2(at)
    var brush := StateBrushScript.new()
    brush.surface = _surface
    brush.settings.opacity = 1.0
    brush.settings.radius = 0.1
    brush.settings.hardness = GammaFloatScript.new(1.0, 1.0)
    brush.settings.opacity_by_pressure = false
    brush.settings.painting_mode = mode
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
    var lift := InputEventMouseButton.new()
    lift.button_index = MOUSE_BUTTON_LEFT
    lift.pressed = false
    brush.handle_input(lift)


## The layer's whole height in the chunk at the origin, row by row.
func _heights() -> PackedFloat32Array:
    var found := PackedFloat32Array()
    var texture := _doc.active_layer.get_field(Vector2i.ZERO, SaFieldSpec.HEIGHT)
    if texture == null:
        return found
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    found.resize(texture.size.x * texture.size.y)
    for i in found.size():
        found[i] = bytes.decode_half(i * 2)
    return found


func _at(heights: PackedFloat32Array, at: Vector2i) -> float:
    return heights[at.y * SaChunk.SIZE + at.x] if heights.size() > at.y * SaChunk.SIZE + at.x else NAN


## Holds that no texel stands past nought or below where it began, and answers
## how many the eraser moved.
func _assert_between_ground_and_nought(heights: PackedFloat32Array, what: String) -> int:
    var past := 0
    var moved := 0
    for value in heights:
        if value > 0.0 or value < GROUND:
            past += 1
        elif value > GROUND:
            moved += 1
    assert_eq(past, 0, "%s leaves no texel past nought or below the ground" % what)
    assert_true(moved > 0, "%s moves the height it reaches" % what)
    return moved


func test_the_noise_eraser_raises_a_negative_height_towards_nought() -> void:
    _noise_stroke(0.5)
    var heights := _heights()
    assert_almost_eq(_at(heights, UNDER), GROUND * 0.5, 0.01, "A half strength eraser halves a negative height, from below")
    _assert_between_ground_and_nought(heights, "The half strength stroke")


func test_the_noise_eraser_at_full_strength_stops_at_nought() -> void:
    _noise_stroke(1.0)
    assert_almost_eq(_at(_heights(), UNDER), 0.0, 0.0001, "A full strength eraser brings the height to nought")
    _noise_stroke(1.0)
    var heights := _heights()
    assert_almost_eq(_at(heights, UNDER), 0.0, 0.0001, "and a second stroke over it leaves it there")
    _assert_between_ground_and_nought(heights, "Two full strength strokes")


func test_the_wash_stamp_eraser_stops_at_nought() -> void:
    var at := Vector2i(128, 128)
    _stamp_dab(at, StampSettingsScript.PaintingMode.WASH)
    _stamp_dab(at, StampSettingsScript.PaintingMode.WASH)
    var heights := _heights()
    assert_almost_eq(_at(heights, at), 0.0, 0.0001, "Two wash dabs bring the height under them to nought and no further")
    _assert_between_ground_and_nought(heights, "The wash stamp eraser")


func test_the_build_up_stamp_eraser_stops_at_nought() -> void:
    var at := Vector2i(128, 128)
    _stamp_dab(at, StampSettingsScript.PaintingMode.BUILD_UP)
    _stamp_dab(at, StampSettingsScript.PaintingMode.BUILD_UP)
    var heights := _heights()
    assert_almost_eq(_at(heights, at), 0.0, 0.0001, "Two build-up dabs bring the height under them to nought and no further")
    _assert_between_ground_and_nought(heights, "The build-up stamp eraser")
