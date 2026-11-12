## Every control a painter presses carries a tooltip.
##
## Size, Opacity, Hardness, Flow, Stabilizer, Smoothing, the hex field, the six
## picker sliders and a layer's eye had none, nor did the brush's rows, the
## three window buttons or the layer's Opacity. This suite walks each place,
## the brush's rows, the bar, the Colour Picker, the Layers docker and the
## title bar's window buttons, and holds a sentence on every control, and on
## the eye in both states.
## `scenarios/every-control-a-painter-presses-carries-a-tooltip.json` hovers
## them in the running app.
extends "res://tests/test_framework.gd"

## The bar's controls come from the tools' descriptors, which need a machine and
## a surface, and the Layers docker shows a document. All three need a device.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModule = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const NoiseModule = preload("res://modules/sara-noise-brush-engine/module.gd")
const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")

## The brush's rows by key: Size, which reads Radius,
## and the six that carry a sentence.
const BRUSH_KEYS: Array[StringName] = [
    &"radius", &"opacity", &"hardness", &"flow", &"exposure", &"stabilizer_mode", &"stabilizer_amount"
]

## The node each of those is built as on the bar, in the same order, which is
## the name a scenario hovers.
const BAR_NAMES: Array[String] = [
    "RadiusSlider",
    "OpacitySlider",
    "HardnessSlider",
    "FlowSlider",
    "ExposureSlider",
    "StabilizerModeOpt",
    "StabilizerAmountSlider",
]

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _host: Node = null


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    if _machine != null:
        Fixtures.teardown(_surface, _machine)
        _surface = null
        _machine = null


## *key*'s spec among *specs*, or null.
static func _spec_in(specs: Array[SaOptionSpec], key: StringName) -> SaOptionSpec:
    for spec: SaOptionSpec in specs:
        if spec.key == key:
            return spec
    return null


func _stamp(key: StringName) -> SaOptionSpec:
    return _spec_in(StampModule.brush_options(), key)


func test_every_brush_row_the_sweeps_named_says_what_it_does() -> void:
    for key: StringName in BRUSH_KEYS:
        var spec := _stamp(key)
        assert_not_null(spec, "the brush declares %s" % key)
        if spec == null:
            continue
        assert_false(spec.tooltip.strip_edges().is_empty(), "%s carries a tooltip" % spec.label)
        # What the control does rather than its name again, which is all the
        # label already said.
        assert_false(
            spec.tooltip.begins_with(spec.label), "%s's tooltip says more than its name: '%s'" % [spec.label, spec.tooltip]
        )


func test_the_bars_brush_controls_carry_the_brushs_sentences() -> void:
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    var options := ToolOptionsBar.new()
    _host = options
    options.target_tool_machine = _machine
    options._ready()
    for i in BRUSH_KEYS.size():
        var control := options.control_for(BRUSH_KEYS[i])
        assert_not_null(control, "the bar builds %s" % BAR_NAMES[i])
        if control == null:
            continue
        assert_eq(String(control.name), BAR_NAMES[i], "under the name a scenario hovers")
        assert_eq(control.tooltip_text, _stamp(BRUSH_KEYS[i]).tooltip, "%s carries the brush's sentence" % BAR_NAMES[i])


## One slider serves every tool that declares its key, and a switch of tool
## applied the new tool's range and label and kept the first tool's tooltip.
## Opacity is declared by both engines, in two different sentences, because the
## noise brush's stroke stops at its opacity and the stamp's builds up past it.
func test_a_shared_slider_reads_the_sentence_of_the_tool_it_shows() -> void:
    var host := Control.new()
    _host = host
    var controls := ToolOptionControls.new(host)
    var stamp_spec := _stamp(&"opacity")
    var noise_spec := _spec_in(NoiseModule.options(), &"opacity")
    assert_false(stamp_spec.tooltip == noise_spec.tooltip, "the two engines word their Opacity apart")
    var stamp := SaToolDescriptor.new()
    stamp.id = &"n15_stamp"
    stamp.options.assign([stamp_spec])
    var noise := SaToolDescriptor.new()
    noise.id = &"n15_noise"
    noise.options.assign([noise_spec])
    controls.build_for(stamp)
    controls.build_for(noise)
    var slider := controls.control(&"opacity")

    controls.sync(null, noise.id, 1.0)
    assert_eq(slider.tooltip_text, noise_spec.tooltip, "the noise brush shown, the slider reads its sentence")
    controls.sync(null, stamp.id, 1.0)
    assert_eq(slider.tooltip_text, stamp_spec.tooltip, "and the stamp brush's again when it comes back")


func test_the_hex_field_and_the_six_picker_sliders_say_what_they_take() -> void:
    var picker := SaColorPicker.new()
    _host = picker
    assert_false(picker.hex_input.tooltip_text.is_empty(), "the hex field carries a tooltip")
    assert_true(picker.hex_input.tooltip_text.contains("#"), "which says the # is optional: '%s'" % picker.hex_input.tooltip_text)
    var units := {"R": "255", "G": "255", "B": "255", "H": "degrees", "S": "per cent", "V": "per cent"}
    for row: SaPickerSliders in [picker.rgb_sliders, picker.okhsv_sliders]:
        assert_eq(row.sliders.size(), 3, "%s holds three sliders" % row.name)
        for slider: FactorSlider in row.sliders:
            var channel := String(slider.name).right(1)
            assert_true(
                slider.tooltip_text.contains(units[channel]),
                "%s names its unit, %s: '%s'" % [slider.name, units[channel], slider.tooltip_text]
            )


func _layers_docker() -> LayersDocker:
    var canvas := SaCanvas.new()
    _host = canvas
    canvas.canvas_size = Vector2i(256, 256)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    var docker: LayersDocker = LayersDockerScript.new()
    docker.name = "LayersDocker"
    canvas.add_child(docker)
    docker.target_canvas = canvas
    docker._ready()
    return docker


## The first layer's row in *docker*.
static func _layer_row(docker: LayersDocker) -> SaLayerRowView:
    for row: SaRowFrame in docker.item_list.rows:
        if row is SaLayerRowView and row.has_layer():
            return row
    return null


func test_the_layers_opacity_says_what_it_sets() -> void:
    var docker := _layers_docker()
    assert_false(docker.opacity_slider.tooltip_text.is_empty(), "the layer's Opacity carries a tooltip")
    assert_true(docker.opacity_slider.tooltip_text.contains("layer"), "about the layer, not the brush")


## The eye's state is the icon, and the text the button draws only where the
## icon is missing, so a hover said nothing until the tooltip said the press.
func test_the_eye_says_what_a_press_does_in_both_states() -> void:
    var docker := _layers_docker()
    var row := _layer_row(docker)
    assert_not_null(row, "the docker lists a layer")
    if row == null:
        return
    var layer := row.layer
    assert_true(layer.visible, "a new layer shows")
    var tip := row.eye_btn.tooltip_text
    assert_true(tip.begins_with("Hide this layer"), "so its eye offers to hide it: '%s'" % tip)

    SaLayerOps.new(docker.target_canvas.easel.document).set_visible(layer, false)
    docker.sync_layer_list()
    row = _layer_row(docker)
    assert_false(row.layer.visible, "hidden")
    tip = row.eye_btn.tooltip_text
    assert_true(tip.begins_with("Show this layer"), "its eye offers to show it: '%s'" % tip)
    assert_eq(String(row.eye_btn.name), "EyeBtn", "under the name a scenario hovers")


## A filter's eye turns the filter off and on, which is a different press from a
## layer's and is worded as one.
func test_a_filters_eye_says_it_turns_the_filter_off_and_on() -> void:
    var record := SaAttachedFilter.new(&"n15_filter")
    var row := SaFilterRowView.new(record, null, "Blur", 0, 0)
    _host = row
    row.refresh(null)
    assert_eq(row.eye_btn.tooltip_text, "Turn this filter off", "an enabled filter's eye offers to turn it off")
    record.enabled = false
    row.refresh(null)
    assert_eq(row.eye_btn.tooltip_text, "Turn this filter on", "and a disabled one's to turn it on")


func test_the_three_window_buttons_say_what_they_do() -> void:
    var buttons := SaTopBarWindowButtons.new()
    _host = buttons
    for btn: Button in [buttons.minimize_btn, buttons.maximize_btn, buttons.close_btn]:
        assert_false(btn.tooltip_text.is_empty(), "%s carries a tooltip" % btn.name)
    assert_eq(buttons.maximize_btn.tooltip_text, SaTopBarWindowButtons.maximize_hint(), "maximize says what a press does now")
    # The macOS look draws three coloured dots and no glyph, which is where a
    # tooltip is all a painter has to go on.
    buttons.os_name_override = "macOS"
    buttons.apply_settings()
    for btn: Button in [buttons.minimize_btn, buttons.maximize_btn, buttons.close_btn]:
        assert_false(btn.tooltip_text.is_empty(), "%s keeps it as a traffic light" % btn.name)
