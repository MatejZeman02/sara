## Brightness and contrast, and hue, saturation and lightness, as destructive
## passes over a layer.
##
## Read back pixel by pixel, because the kernel is arithmetic on stored values
## and the invariant under test is that nothing between the slider and the
## chunk clamps: a negative or a value above one comes out transformed, never
## discarded.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

var _easel: SaEasel = null
var _doc: SaDocument = null
var _engine: SaPointAdjust = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document
    _engine = SaPointAdjust.new()


func after_each() -> void:
    _engine = null
    _easel.free()
    _easel = null
    _doc = null


## *brightness* is added to the encoded RGB view and *contrast* is a factor
## about 0.5, as one step over the active layer.
func _brightness_contrast(brightness: float, contrast: float) -> bool:
    var values := {"brightness": brightness, "contrast": contrast}
    return _engine.apply(_doc, _doc.active_layer, SaPointAdjust.BRIGHTNESS_CONTRAST, values, "Brightness/Contrast")


## *hue* in degrees, *saturation* a factor and *lightness* an offset, in Oklab.
func _hue_saturation_lightness(hue: float, saturation: float, lightness: float) -> bool:
    var values := {"hue": hue, "saturation": saturation, "lightness": lightness}
    return _engine.apply(_doc, _doc.active_layer, SaPointAdjust.HUE_SATURATION_LIGHTNESS, values, "Hue/Saturation/Lightness")


func _texel(x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := _doc.active_layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(
        bytes, texture.format, (y - grid.y * SaChunk.SIZE) * texture.size.x + (x - grid.x * SaChunk.SIZE)
    )


func test_brightness_adds_and_contrast_scales_about_mid_grey() -> void:
    _doc.active_layer.fill(Color(0.25, 0.5, 0.75, 1.0))

    assert_true(_brightness_contrast(0.1, 1.0), "A brightness step happens")
    var lifted := _texel(10, 10)
    assert_almost_eq(lifted.r, 0.35, 1e-4, "Brightness adds to every channel")
    assert_almost_eq(lifted.b, 0.85, 1e-4, "the same amount")
    assert_almost_eq(lifted.a, 1.0, 1e-6, "and leaves alpha alone")

    assert_true(_doc.undo(), "which undoes")
    assert_true(_brightness_contrast(0.0, 2.0), "and a contrast step happens")
    var spread := _texel(10, 10)
    assert_almost_eq(spread.r, 0.0, 1e-4, "Contrast doubles the distance from mid grey downwards")
    assert_almost_eq(spread.g, 0.5, 1e-4, "leaves mid grey where it is")
    assert_almost_eq(spread.b, 1.0, 1e-4, "and upwards")


## Hard rule 5. A contrast that pushes a value past one or below zero keeps it
## there, and a negative that goes in comes out more negative, not zero.
func test_nothing_clamps_on_the_way_through() -> void:
    _doc.active_layer.fill(Color(-0.5, 0.9, 3.0, 1.0))

    assert_true(_brightness_contrast(0.0, 2.0), "Applied")

    var texel := _texel(100, 100)
    assert_almost_eq(texel.r, -1.5, 1e-4, "A negative goes further negative")
    assert_almost_eq(texel.g, 1.3, 1e-4, "a value crosses one and stays there")
    assert_almost_eq(texel.b, 5.5, 1e-4, "and a large one is scaled, not discarded")


func test_the_pass_honours_the_selection_and_is_one_step() -> void:
    _doc.active_layer.fill(Color(0.5, 0.5, 0.5, 1.0))
    _doc.selection.select_rect(Rect2i(0, 0, 128, 128))
    var steps_before: int = _doc.history.step_count()

    assert_true(_brightness_contrast(0.2, 1.0), "Applied")

    assert_almost_eq(_texel(64, 64).r, 0.7, 1e-4, "Inside the selection the pass lands")
    assert_almost_eq(_texel(200, 64).r, 0.5, 1e-4, "outside it, in the same chunk, nothing changes")
    assert_almost_eq(_texel(300, 300).r, 0.5, 1e-4, "nor in a chunk the selection leaves out")
    assert_eq(_doc.history.step_count(), steps_before + 1, "and it is one history step")
    assert_true(_doc.undo(), "which undoes")
    assert_almost_eq(_texel(64, 64).r, 0.5, 1e-4, "putting the pixels back")


func test_saturation_zero_is_grey_at_the_same_lightness() -> void:
    _doc.active_layer.fill(Color(1.0, 0.0, 0.0, 1.0))

    assert_true(_hue_saturation_lightness(0.0, 0.0, 0.0), "Applied")

    var texel := _texel(10, 10)
    assert_almost_eq(texel.r, texel.g, 1e-3, "No chroma left: red equals green")
    assert_almost_eq(texel.g, texel.b, 1e-3, "and green equals blue")
    # Oklab lightness of sRGB red is about 0.63, and the grey with that L is
    # about 0.56 encoded, which is well away from both black and white.
    assert_true(texel.r > 0.4 and texel.r < 0.7, "at the lightness red had, not black or white")


func test_a_half_turn_of_hue_takes_red_towards_cyan() -> void:
    _doc.active_layer.fill(Color(1.0, 0.0, 0.0, 1.0))

    assert_true(_hue_saturation_lightness(180.0, 1.0, 0.0), "Applied")

    var texel := _texel(10, 10)
    assert_true(texel.r < texel.g and texel.r < texel.b, "The complement of red has less red than either other channel")


func test_lightness_lifts_a_grey() -> void:
    _doc.active_layer.fill(Color(0.5, 0.5, 0.5, 1.0))

    assert_true(_hue_saturation_lightness(0.0, 1.0, 0.2), "Applied")

    var texel := _texel(10, 10)
    assert_true(texel.r > 0.6, "Brighter than it was")
    assert_almost_eq(texel.r, texel.b, 1e-3, "and still grey")


func test_a_locked_layer_and_an_empty_layer_are_left_alone() -> void:
    var steps_before: int = _doc.history.step_count()
    assert_false(_brightness_contrast(0.5, 1.0), "No chunks, nothing to do")
    _doc.active_layer.fill(Color(0.5, 0.5, 0.5, 1.0))
    _doc.active_layer.is_locked = true
    assert_false(_brightness_contrast(0.5, 1.0), "A locked layer is not rewritten")
    assert_almost_eq(_texel(10, 10).r, 0.5, 1e-4, "and keeps its pixels")
    assert_eq(_doc.history.step_count(), steps_before, "with no step recorded either way")


func test_the_filters_report_their_sliders_in_the_units_the_pass_takes() -> void:
    var filter := SaBrightnessContrastFilter.new()
    var dialog := SaDialog.new()
    var host := VBoxContainer.new()
    filter.build(dialog)
    dialog.realize(host)
    filter.capture_set({"brightness": 25.0, "contrast": 50.0})
    var values := filter.values()
    assert_almost_eq(values["brightness"], pow(2.0, 0.225), 1e-5, "Brightness is a factor, 0.9 stops at the slider's hundred")
    assert_almost_eq(values["contrast"], 1.25, 1e-6, "and contrast an exponent about one, half a unit at its hundred")

    var other := SaHueSaturationLightnessFilter.new()
    assert_eq(
        other.values(),
        {
            "hue": 0.0,
            "saturation": 1.0,
            "lightness": 0.0,
            "colorize": false,
            "saturation_model": SaPointAdjust.SATURATION_IN_CAM16
        },
        "The other kind starts at no change, Colourise off, saturation in CAM16"
    )

    var reruns: Array = []
    dialog.rerun.connect(func() -> void: reruns.append(true))
    dialog.flush_rerun()
    assert_eq(reruns.size(), 1, "Two sliders moved in one frame ask for one run")
    assert_eq(other.id(), SaPointAdjust.HUE_SATURATION_LIGHTNESS, "and a filter's id is its kind")
    host.free()
