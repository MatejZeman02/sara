## A brush on a mask paints the lightness of its colour.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every case presses and lifts the real stamp brush over a fake view, so the
## stroke goes through the route, the paint context and the coverage branch the
## way a painter's does, and every assertion reads the mask's texel back. A colour
## painted white would be a reading a picture cannot tell
## from a mask nobody touched: the layer simply stays shown. So the first case is
## the black one, and it asks for nought.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: every case paints through a real surface.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const BrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const GammaFloatScript = preload("res://modules/sara-base-modules/stamp-brush/tools/gamma_float.gd")

const BLACK := Color(0.0, 0.0, 0.0, 1.0)
const GREY := Color(0.5, 0.5, 0.5, 1.0)
const WHITE := Color(1.0, 1.0, 1.0, 1.0)

## Where every dab lands, well inside the first chunk.
const AT := Vector2i(64, 64)

var _surface: SaSurface = null
var _doc: SaDocument = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _doc = _surface.easel.document
    (_surface.view as Fixtures.FakeView).mouse_position = Vector2(AT)


func after_each() -> void:
    Fixtures.teardown(_surface)
    _surface = null
    _doc = null


## A hard brush of a tenth of the canvas, whose centre is the colour at full
## strength, so the texel under it is the arithmetic and not the falloff.
func _brush(color: Color, opacity: float = 1.0) -> BrushScript:
    var brush := BrushScript.new()
    brush.surface = _surface
    brush.settings.color = color
    brush.settings.opacity = opacity
    brush.settings.radius = 0.1
    brush.settings.hardness = GammaFloatScript.new(1.0, 1.0)
    brush.settings.opacity_by_pressure = false
    return brush


## One press and one release at `AT`, which is one dab and one stroke.
func _stroke(brush: BrushScript) -> void:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    brush.handle_input(press)
    var lift := InputEventMouseButton.new()
    lift.button_index = MOUSE_BUTTON_LEFT
    lift.pressed = false
    brush.handle_input(lift)


func _paint(color: Color, opacity: float = 1.0) -> void:
    _stroke(_brush(color, opacity))


func _erase() -> void:
    var brush := _brush(WHITE)
    brush.eraser_toggled = true
    _stroke(brush)


## The coverage *mask* holds at `AT`, one where it holds nothing.
func _coverage(mask: SaMask) -> float:
    var texture := mask.texture_for(Vector2i.ZERO)
    if texture == null:
        return 1.0
    return _texel(texture)


func _texel(texture: SaTexture) -> float:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, AT.y * texture.size.x + AT.x).r


func _layer_mask() -> SaMask:
    var mask := _doc.active_layer.add_mask()
    _doc.mask_target = mask
    return mask


# --- The Done-when's four readings --------------------------------------------


func test_black_on_a_shown_mask_hides_the_layer() -> void:
    var mask := _layer_mask()
    assert_almost_eq(_coverage(mask), 1.0, 1e-6, "A fresh mask shows the whole layer")
    _paint(BLACK)
    assert_almost_eq(_coverage(mask), 0.0, 1e-4, "and black paints nought, which hides it")


func test_a_mid_grey_paints_half_coverage() -> void:
    var mask := _layer_mask()
    _paint(GREY)
    assert_almost_eq(_coverage(mask), 0.5, 1e-3, "A grey stored as a half paints a half over a shown mask")
    _paint(BLACK)
    _paint(GREY)
    assert_almost_eq(_coverage(mask), 0.5, 1e-3, "and a half over a hidden one, because the dab is opaque")


func test_white_over_a_hidden_mask_shows_the_layer_again() -> void:
    var mask := _layer_mask()
    _paint(BLACK)
    _paint(WHITE)
    assert_almost_eq(_coverage(mask), 1.0, 1e-4, "White shows what black hid")


func test_the_eraser_still_takes_coverage_away() -> void:
    var mask := _layer_mask()
    _erase()
    assert_almost_eq(_coverage(mask), 0.0, 1e-4, "The eraser hides, whatever colour the brush holds")


# --- The ask's other clauses ---------------------------------------------------


## The brush's opacity lies over the lightness as it lies over paint: black at
## a quarter over a shown mask leaves three quarters.
func test_opacity_lies_over_the_lightness_as_over_paint() -> void:
    var mask := _layer_mask()
    _paint(BLACK, 0.25)
    assert_almost_eq(_coverage(mask), 0.75, 2e-3, "A quarter of black takes a quarter of the coverage")


## Coverage is a fraction, so a colour past white shows fully and no more.
func test_a_colour_past_white_writes_no_more_than_one() -> void:
    var mask := _layer_mask()
    _paint(BLACK)
    _paint(Color(4.0, 4.0, 4.0, 1.0))
    assert_almost_eq(_coverage(mask), 1.0, 1e-4, "Four times white is shown, not four times shown")


## A colour's lightness, not its brightest channel: pure red is darker than
## white, so it shows less than white does. The weights are the sRGB
## primaries' luminance, which is the default document's.
func test_a_colour_paints_its_lightness_and_not_its_brightest_channel() -> void:
    var mask := _layer_mask()
    _paint(Color(1.0, 0.0, 0.0, 1.0))
    assert_almost_eq(_coverage(mask), 0.2126, 2e-3, "Red shows as much as its luminance")


## Read in the document's own numbers: the picker's mid grey is stored in a
## linear document as 0.214, and that is what the mask gets.
func test_the_lightness_is_read_in_the_documents_space() -> void:
    _doc.color_space = SaColorSpace.linear_srgb()
    var mask := _layer_mask()
    _paint(GREY)
    assert_almost_eq(_coverage(mask), 0.21404114, 2e-3, "A linear document's mid grey is its stored light")


## The own form, which a group's and a filter's mask keep, goes the same way.
func test_a_filters_own_mask_goes_the_same_way() -> void:
    var mask := SaMask.own()
    _doc.mask_target = mask
    _paint(BLACK)
    assert_almost_eq(_coverage(mask), 0.0, 1e-4, "Black hides through an own mask as well")


## The quick mask follows, which is the row's decision: Krita's selection
## paints by lightness too, so black deselects and grey half selects.
func test_the_quick_mask_paints_lightness_as_well() -> void:
    _doc.selection.editing = true
    _paint(WHITE)
    var selection := _doc.selection.texture_for(Vector2i.ZERO)
    assert_almost_eq(_texel(selection), 1.0, 1e-4, "White selects")
    _paint(GREY)
    assert_almost_eq(_texel(selection), 0.5, 1e-3, "grey half selects")
    _paint(BLACK)
    assert_almost_eq(_texel(selection), 0.0, 1e-4, "and black deselects")
