## The bar shows Opacity and not Flow, and the brush editor keeps both.
##
## Flow and Opacity are different numbers that must reach the kernel apart, flow
## the rate one dab moves towards opacity's ceiling, so merging them in the
## engine would take away the thing a wash brush is made of. Only the bar shows
## one, and the editor shows two.
##
## What this asserts is that the default moved and nothing else. Flow is
## hidden on a fresh bar by the brush's own spec, rather than
## by `bar = false` on the spec, which builds no control and leaves a Preferences
## switch that moves nothing. So Flow is still declared,
## still built, still reachable in one tick, and still a row everywhere the brush
## editor and the Tool Options docker draw rows.
##
## `scenarios/flow-and-opacity-as-one-slider.json` is the same claim on the
## running app, and the stroke either side of showing Flow again is what says
## the paint did not move.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

static var scratch_profile: String = SaDataRoot.path("test_flow_leaves_the_bar.cfg")

var _saved_path: String = ""


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()
    SaSettings.load_settings()


func after_each() -> void:
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()


func _remove_profile() -> void:
    var path := ProjectSettings.globalize_path(scratch_profile)
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(path)


func _brush_specs() -> Dictionary:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var out := {}
    for spec: SaOptionSpec in machine.get_descriptor(&"brush").options:
        out[String(spec.key)] = spec
    Fixtures.teardown(surface, machine)
    return out


func test_a_fresh_bar_hides_flow_and_keeps_opacity() -> void:
    assert_false(SaSettings.get_element_visible("TopMenuBar", "flow"), "Flow is off a fresh bar")
    assert_true(SaSettings.get_element_visible("TopMenuBar", "opacity"), "and Opacity is on it")


func test_flow_is_hidden_by_a_default_and_not_by_the_spec() -> void:
    var specs := _brush_specs()
    assert_true(specs.has("flow"), "The brush still declares Flow")
    if specs.has("flow"):
        assert_true((specs["flow"] as SaOptionSpec).bar, "flagged for the bar, so a control is built for a tick to show")
        assert_true((specs["flow"] as SaOptionSpec).bar_hidden, "The profile default is what hides it")


## A hidden default a painter can undo, rather than a switch that reads as off and has nothing behind it.
func test_a_painter_who_wants_flow_back_gets_it_in_one_tick() -> void:
    SaSettings.set_element_visible("TopMenuBar", "flow", true)
    assert_true(SaSettings.get_element_visible("TopMenuBar", "flow"), "A tick in Preferences puts Flow back")
    SaSettings.set_element_visible("TopMenuBar", "flow", false)
    assert_false(SaSettings.get_element_visible("TopMenuBar", "flow"), "and another takes it off again")


func test_the_editor_and_the_docker_keep_both() -> void:
    var specs := _brush_specs()
    for key: String in ["opacity", "flow"]:
        assert_true(specs.has(key), "The brush declares %s" % key)
        if specs.has(key):
            var spec := specs[key] as SaOptionSpec
            assert_true(spec.in_editor, "%s is a row the brush editor draws" % key)
    assert_true(specs.has("flow_option"), "and Flow's curve option page is untouched")
    assert_true(specs.has("opacity_option"), "beside Opacity's")


## The engine half: two numbers, still apart. Hiding a row cannot
## reach the settings, and this is the assertion that says it did not.
func test_hiding_the_row_leaves_both_numbers_on_the_settings() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var settings: Variant = machine.active_tool.get("settings")
    assert_true(settings != null, "The brush has settings")
    if settings != null:
        # Flow is a `GammaFloat` and Opacity a plain float, which is the two
        # numbers being different things written down in the settings' types.
        settings.flow.value = 0.35
        settings.opacity = 0.8
        SaSettings.set_element_visible("TopMenuBar", "flow", false)
        assert_almost_eq(settings.flow.value, 0.35, 1e-6, "Flow keeps its value while its row is hidden")
        assert_almost_eq(float(settings.opacity), 0.8, 1e-6, "and Opacity keeps its own")
    Fixtures.teardown(surface, machine)
