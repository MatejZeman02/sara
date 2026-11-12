## The eyedropper's sample size is a slider and fits the bar.
##
## `SampleSizeOpt` is a slider and not a choice list of 1, 3, 5 and 9, which the
## bar would cut to its first letter. The option is a slider of the square's
## side, 1 to 25 in steps of two, and a side a choice list stored opens where it
## was.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")
const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")

## Needs a RenderingDevice for the averaged square. The runner skips this suite
## without one.
const REQUIRES_GPU := true

const BASE_MODULE_ID := &"sara-base-modules"

static var scratch_path: String = SaDataRoot.path("test_d54_eyedropper_sample_size.cfg")

var _saved_path: String = ""


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    DirAccess.remove_absolute(_scratch())


func after_each() -> void:
    StateEyedropperScript.keep_choice_in(null)
    SaSettings.settings_path = _saved_path
    SaSettings.config = ConfigFile.new()
    SaSettings.load_settings()
    DirAccess.remove_absolute(_scratch())
    DirAccess.remove_absolute(_scratch() + SaSettings.BACKUP_SUFFIX)


func _scratch() -> String:
    return ProjectSettings.globalize_path(scratch_path)


## The base module's context over a scratch profile, handed to every eyedropper.
func _keep_in_scratch() -> SaContext:
    SaSettings.config = ConfigFile.new()
    SaSettings.settings_path = _scratch()
    SaSettings.load_settings()
    var context := Fixtures.make_registries().context.for_module(BASE_MODULE_ID)
    StateEyedropperScript.keep_choice_in(context)
    return context


## The option is a slider from 1 to 25 in steps of two, labelled Sample, read
## in whole pixels.
func test_the_option_is_a_slider_from_one_to_twenty_five() -> void:
    var size := BaseModule.eyedropper_options()[0]
    assert_eq(size.key, &"sample_size", "The first eyedropper option is its size")
    assert_eq(size.kind, SaOptionSpec.Kind.FLOAT, "a slider, the kind that honours its own step")
    assert_true(size.choices.is_empty(), "with no choice list left to cut")
    assert_eq(size.min_value, 1.0, "from one texel")
    assert_eq(size.max_value, 25.0, "to twenty-five")
    assert_eq(size.step, 2.0, "in steps of two")
    assert_eq(size.decimals, 0, "read in whole pixels")
    assert_eq(size.suffix, "px", "with the unit after the number, the slider puts the space")
    assert_eq(size.label, "Sample", "labelled Sample")
    var constants := (StateEyedropperScript as Script).get_script_constant_map()
    assert_false(constants.has("SAMPLE_SIZES"), "and the old list of four is gone")


## The slider lands on odd sides only, so the picked texel is the centre, by a
## drag, a typed number and an arrow step alike.
func test_the_slider_lands_on_odd_sides() -> void:
    var spec := BaseModule.eyedropper_options()[0]
    var slider := FactorSlider.new()
    slider.min_value = spec.min_value
    slider.max_value = spec.max_value
    slider.step = spec.step
    for asked: float in [1.0, 2.0, 4.0, 6.9, 12.0, 24.0, 25.0]:
        var landed := slider.quantized(asked)
        assert_eq(int(landed) % 2, 1, "%s lands on an odd side, %s" % [asked, landed])
    assert_eq(slider.quantized(7.0), 7.0, "and an odd side is itself")
    slider.value = 1.0
    slider.step_by_units(1.0)
    assert_eq(slider.value, 3.0, "One step up from one is three")
    slider.free()


## A floor on the step's grid keeps the rounding every other slider had.
func test_a_floor_on_the_grid_rounds_as_before() -> void:
    var slider := FactorSlider.new()
    slider.min_value = 0.05
    slider.max_value = 4.0
    slider.step = 0.01
    assert_almost_eq(slider.quantized(0.374), 0.37, 0.000001, "The transform's scale rounds to a hundredth as it did")
    slider.min_value = 0.0
    slider.step = 2.0
    assert_eq(slider.quantized(3.2), 4.0, "and a floor of nought steps from nought")
    slider.free()


## Each side the old list stored opens at the same side, and any other stored
## word opens at one texel.
func test_each_old_stored_value_opens_at_the_same_side() -> void:
    var context := _keep_in_scratch()
    assert_eq(StateEyedropperScript.new().sample_size, 1, "A profile that holds no size samples one texel")
    for side: int in [1, 3, 5, 9]:
        context.set_preference(StateEyedropperScript.SAMPLE_SIZE_KEY, side)
        assert_eq(StateEyedropperScript.new().sample_size, side, "A stored %d opens at %d" % [side, side])
    for stored: Variant in [0, 2, 4, 27, -3, 4.5, "nine", null, true]:
        context.set_preference(StateEyedropperScript.SAMPLE_SIZE_KEY, stored)
        assert_eq(StateEyedropperScript.new().sample_size, 1, "%s falls back to one" % str(stored))
    context.set_preference(StateEyedropperScript.SAMPLE_SIZE_KEY, 7.0)
    assert_eq(StateEyedropperScript.new().sample_size, 7, "and a whole float, which a profile may hold, is its side")


## The bar writes the slider's float through the property path, and the side
## outlives the session in the module's own section, as the Sample row does.
func test_the_bar_writes_the_side_and_a_second_launch_opens_on_it() -> void:
    # Held, because the eyedropper holds the context weakly.
    var context := _keep_in_scratch()
    var first := StateEyedropperScript.new()
    first.set_indexed(^"sample_size", 13.0)
    assert_eq(first.sample_size, 13, "The slider's float is a side of thirteen")
    assert_eq(StateEyedropperScript.new().sample_size, 13, "every eyedropper reads it")
    assert_eq(
        SaSettings.module_preference(BASE_MODULE_ID, StateEyedropperScript.SAMPLE_SIZE_KEY), 13, "from the module's own section"
    )
    SaSettings.config = ConfigFile.new()
    SaSettings.load_settings()
    assert_eq(StateEyedropperScript.new().sample_size, 13, "and a second launch opens on it")
    StateEyedropperScript.keep_choice_in(null)
    assert_eq(StateEyedropperScript.new().sample_size, 1, "With no module behind it a state remembers nothing")
    assert_not_null(context, "and the context was the module's throughout")


## A side of 7 averages a 7 by 7 square: one red texel in a blue field is one
## in forty-nine, and a red texel three away from the centre still counts while
## one four away does not.
func test_a_side_of_seven_averages_a_seven_by_seven_square() -> void:
    var surface := Fixtures.make_surface(Vector2i(64, 64))
    var rd := GlobalShaderCompiler.get_rd()
    var output := surface.easel.output
    rd.texture_clear(output.rid, Color(0.0, 0.0, 1.0, 1.0), 0, 1, 0, 1)
    var dot := SaTexture.new(Vector2i.ONE, output.format)
    rd.texture_clear(dot.rid, Color(1.0, 0.0, 0.0, 1.0), 0, 1, 0, 1)
    rd.texture_copy(dot.rid, output.rid, Vector3.ZERO, Vector3(35, 32, 0), Vector3.ONE, 0, 0, 0, 0)

    var eyedropper := StateEyedropperScript.new()
    eyedropper.surface = surface
    eyedropper.sample_from = StateEyedropperScript.SampleFrom.VIEW
    eyedropper.sample_size = 7
    assert_eq(eyedropper.sample_size, 7, "The side is seven")
    var picked := eyedropper.pick_color_at_pos(Vector2(32, 32))
    assert_almost_eq(picked.r, 1.0 / 49.0, 0.002, "Three texels off the centre is inside, one red in forty-nine")
    assert_almost_eq(picked.b, 48.0 / 49.0, 0.002, "and forty-eight blues")
    var beside := eyedropper.pick_color_at_pos(Vector2(31, 32))
    assert_almost_eq(beside.r, 0.0, 0.0001, "Four texels off the centre is outside")

    Fixtures.teardown(surface)
