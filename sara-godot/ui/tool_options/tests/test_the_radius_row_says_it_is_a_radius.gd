## The brush's size row reads Radius in both engines, with a tooltip that says
## what the number is and that a double-click types one.
##
## A row called Size once read "30.34 px" beside a ring 57
## across, because the number was always the radius. The key stays `radius`,
## so a stored bar layout and a saved preset still find the row, and only the
## words a painter reads move. The field to type into was there all along
## behind a double-click, and nothing on the row said so.
## `scenarios/the-size-slider-takes-a-typed-number-and-a-fine-step-and-says-it-is-a-radius.json`
## is the same claim on the running app.
extends "res://tests/test_framework.gd"

## The bar's test needs the machine it reads its tools from, which needs a
## device.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")


static func _radius_of(specs: Array[SaOptionSpec]) -> SaOptionSpec:
    for spec: SaOptionSpec in specs:
        if spec.key == &"radius":
            return spec
    return null


func _engines() -> Dictionary:
    return {"stamp": _radius_of(StampModuleScript.brush_options()), "noise": _radius_of(NoiseModuleScript.options())}


func test_both_engines_label_the_row_radius() -> void:
    var engines := _engines()
    for engine: String in engines:
        var spec: SaOptionSpec = engines[engine]
        assert_not_null(spec, "The %s engine declares a radius row" % engine)
        if spec == null:
            continue
        assert_eq(spec.label, "Radius", "and the %s engine's row reads Radius rather than Size" % engine)
        assert_eq(spec.suffix, "px", "in pixels, as it did")


## The tooltip's three clauses, each required: the number is the
## radius, it is in pixels of this document, and a double-click types one.
## The two engines say it in the same words, because the bar builds one
## control for the key from whichever engine's row it meets first.
func test_both_engines_say_what_the_number_is_and_how_to_type_one() -> void:
    var engines := _engines()
    var stamp: SaOptionSpec = engines["stamp"]
    for engine: String in engines:
        var spec: SaOptionSpec = engines[engine]
        if spec == null:
            continue
        assert_true(spec.tooltip.contains("radius"), "The %s row's tooltip says the number is the radius" % engine)
        assert_true(spec.tooltip.contains("pixels of this document"), "in pixels of this document")
        assert_true(spec.tooltip.contains("Double-click"), "and that a double-click types one")
        if stamp != null:
            assert_eq(spec.tooltip, stamp.tooltip, "The %s row says it in the stamp brush's words" % engine)


## The bar's own control, built the way the app builds it, reads Radius and
## carries the tooltip, so the words reach the painter and not only the spec.
func test_the_bar_draws_radius_and_carries_the_tooltip() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var registries := Fixtures.make_registries(surface)
    var bar := ToolOptionsBar.new()
    bar.target_tool_machine = machine
    bar._ready()
    bar.bind_registries(registries.blend_modes)

    var slider := bar.control_for(&"radius") as FactorSlider
    assert_not_null(slider, "The bar built a slider for the radius")
    if slider != null:
        assert_eq(slider.prefix, "Radius: ", "which reads Radius")
        assert_true(slider._label.text.begins_with("Radius: "), "on the box itself: %s" % slider._label.text)
        assert_true(slider.tooltip_text.contains("Double-click"), "and carries the tooltip")
    bar.free()
    Fixtures.teardown(surface, machine)
