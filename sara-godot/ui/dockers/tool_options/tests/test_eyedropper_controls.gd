## The eyedropper's two controls reach the tool, and mirror it back.
##
## They are Tool Options docker rows rather than bar ones: neither is
## something a painter reaches for mid-stroke, and on the brush's row the two
## of them overflowed 1920.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")
const VIEW := StateEyedropperScript.SampleFrom.VIEW
const LAYER := StateEyedropperScript.SampleFrom.LAYER

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true


func test_the_sample_controls_write_the_eyedropper_and_read_it_back() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var host := Node.new()
    var docker := ToolOptionsDocker.new()
    host.add_child(docker)
    docker.target_tool_machine = machine
    var dropper: Variant = machine.get_tool("eyedropper")
    assert_not_null(dropper, "The machine holds an eyedropper")
    assert_eq(dropper.sample_size, 1, "which starts at one texel")
    assert_eq(dropper.sample_from, VIEW, "and picks what the view shows, as Merged did")

    # The controls write the shown tool, so the eyedropper has to be the
    # permanent one for its own controls to reach it.
    machine.set_active_tool(&"eyedropper")
    docker.sync_from_tool()
    var size_opt := docker.options.control(&"sample_size") as FactorSlider
    var from_opt := docker.options.control(&"sample_from") as SaChoiceButton
    assert_not_null(size_opt, "The eyedropper declares its sample size, so the docker built a slider")
    assert_not_null(from_opt, "and a dropdown for what it samples, in place of the Merged toggle")
    size_opt.step_by_units(2.0)
    assert_eq(dropper.sample_size, 5, "Two steps up from one texel is five")
    from_opt.pick_row(1)
    assert_eq(dropper.sample_from, LAYER, "and the second Sample entry reads the layer")

    dropper.sample_size = 9
    dropper.sample_from = VIEW
    docker.sync_from_tool()
    assert_eq(size_opt.value, 9.0, "The slider follows the tool")
    assert_eq(int(from_opt.selected_value()), VIEW, "and so does the Sample one")

    host.free()
    Fixtures.teardown(surface, machine)


## Neither is on the bar any more, and neither is in the tool's own docker rows
## while another tool is the permanent one.
##
## "Not on the bar" is not written as
## `bar = false` on the spec, which builds no control at all: with no control there is no
## Preferences > Top Menu Bar row to hide or show, so the row promised something
## the switch could not deliver. The control exists now and
## `SaSettingsLayout.DEFAULT_HIDDEN` keeps it off a fresh bar, which is the same
## bar for a painter who changes nothing and one tick away for a painter who
## wants it.
func test_the_two_controls_are_docker_rows_and_not_bar_ones() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var bar := ToolOptionsBar.new()
    bar.target_tool_machine = machine
    bar._ready()
    assert_false(SaSettings.get_element_visible("TopMenuBar", "sample_size"), "A fresh bar does not show the sample size")
    assert_false(SaSettings.get_element_visible("TopMenuBar", "sample_from"), "nor what it samples")
    assert_not_null(bar.control_for(&"sample_size"), "and each has a control to put back, which `DEFAULT_HIDDEN` provides")
    assert_not_null(bar.control_for(&"sample_from"), "for both of them")
    assert_not_null(bar.control_for(&"radius"), "while the brush's size is still a bar control")
    assert_true(SaSettings.get_element_visible("TopMenuBar", "radius"), "and shown on a fresh bar, unlike the two")

    var host := Node.new()
    var docker := ToolOptionsDocker.new()
    host.add_child(docker)
    docker.target_tool_machine = machine

    assert_eq(String(machine.active_tool_name), "brush", "The machine starts on the brush")
    assert_false(docker.shown_keys().has(&"sample_size"), "so the sample dropdown has no row")
    assert_true(docker.shown_keys().has(&"stabilizer_amount"), "while the brush's own smoothing does")

    machine.set_active_tool(&"eyedropper")
    docker.sync_from_tool()
    assert_true(docker.shown_keys().has(&"sample_size"), "The eyedropper brings its dropdown")
    assert_true(docker.shown_keys().has(&"sample_from"), "and its Sample choice")
    assert_false(docker.shown_keys().has(&"sample_merged"), "and no Merged toggle, which is the wand's alone now")
    assert_false(docker.shown_keys().has(&"stabilizer_amount"), "and takes the brush's rows away")

    machine.set_active_tool(&"brush")
    docker.sync_from_tool()
    assert_false(docker.shown_keys().has(&"sample_size"), "and the brush takes them away again")
    assert_true(docker.shown_keys().has(&"stabilizer_amount"), "and brings its own back")

    host.free()
    bar.free()
    Fixtures.teardown(surface, machine)
