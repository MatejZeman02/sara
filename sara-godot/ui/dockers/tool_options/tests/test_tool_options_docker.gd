## The Tool Options docker: every option the tool declares, built from the
## same specs the bar builds from, and the two surfaces following each other.
##
## The docker is a Window, so it is built detached under a plain Node and its
## `_ready` never runs, which is how `test_ui_components` exercises the others.
## What it looks like is `scenarios/tool-options-docker.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

## Wide enough that the bar's first row holds everything, at any theme scale.
const ROOMY := 4000.0

## A fresh profile, so the bar holds what a fresh bar holds.
static var scratch_profile: String = SaDataRoot.path("test_n9_tool_options_docker.cfg")


## The split: the bar keeps the few a painter reaches for mid-stroke, the
## docker holds all of them, and neither surface names a tool to do it.
func test_the_docker_holds_every_option_and_the_bar_the_flagged_ones() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var bar := ToolOptionsBar.new()
    bar.target_tool_machine = machine
    bar._ready()
    var host := Node.new()
    var docker := ToolOptionsDocker.new()
    host.add_child(docker)
    docker.target_tool_machine = machine

    var brush := machine.get_descriptor(&"brush")
    for spec: SaOptionSpec in brush.options:
        # A row marked `in_docker` false is a page's alone, the stamp brush's
        # tip preview, and the docker leaves it out.
        if spec.in_docker:
            assert_not_null(docker.options.control(spec.key), "The docker built '%s'" % spec.key)
        else:
            assert_null(docker.options.control(spec.key), "The docker left out '%s', which is a page's alone" % spec.key)
        if spec.bar:
            assert_not_null(bar.control_for(spec.key), "and the bar built the flagged '%s'" % spec.key)
        else:
            assert_null(bar.control_for(spec.key), "and left the unflagged '%s' to the docker" % spec.key)

    var shown := docker.shown_keys()
    assert_true(shown.has(&"radius"), "The brush's size is a docker row")
    assert_true(shown.has(&"stabilizer_amount"), "and so is its smoothing, which the bar no longer shows")
    # The painter meets Smoothing in the docker and not on the bar. That is held
    # by the profile rather than by `bar.control_for(...) == null`, which would
    # take the Preferences row down with it, so the page would offer a switch
    # that moved nothing.
    assert_false(SaSettings.get_element_visible("TopMenuBar", "stabilizer_amount"), "Smoothing is not on a fresh bar")
    assert_not_null(bar.control_for(&"stabilizer_amount"), "and it has a control to put back")
    assert_not_null(bar.control_for(&"radius"), "and size is the other half of it: on the bar as well")
    assert_true(SaSettings.get_element_visible("TopMenuBar", "radius"), "and shown there without a tick")

    host.free()
    bar.free()
    Fixtures.teardown(surface, machine)


## The lasso's own two, which is the rest of that claim. Feather is the
## tool's own, applied as the shape lands, and separate from the Select menu's,
## which acts on a selection that already exists.
func test_the_lasso_shows_its_feather_and_its_mode() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var host := Node.new()
    var docker := ToolOptionsDocker.new()
    host.add_child(docker)
    docker.target_tool_machine = machine

    machine.set_active_tool(&"lasso")
    docker.sync_from_tool()
    var shown := docker.shown_keys()
    assert_true(shown.has(&"feather"), "The lasso's feather has a row")
    assert_true(shown.has(&"selection_mode"), "and so has the mode")
    assert_false(shown.has(&"radius"), "and the brush's size does not")

    var lasso: Variant = machine.get_tool("lasso")
    var was := SaSettings.selection_feather
    assert_almost_eq(lasso.feather, 0.0, 0.0001, "A hard edge to begin with")
    var slider := docker.options.control(&"feather") as FactorSlider
    assert_not_null(slider, "Feather is a slider, because it is a number of pixels")
    slider.value_changed.emit(0.007)
    assert_almost_eq(lasso.feather, 0.007, 0.0001, "and moving it writes the tool")

    lasso.feather = 0.003
    docker.sync_from_tool()
    assert_almost_eq(slider.value, 0.003, 0.0001, "and the slider follows the tool back")

    SaSettings.selection_feather = was
    host.free()
    Fixtures.teardown(surface, machine)


## Two controls for one option that disagree read as broken, so each surface
## follows the other's writes.
func test_the_two_surfaces_follow_each_other() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var bar := ToolOptionsBar.new()
    bar.target_tool_machine = machine
    bar._ready()
    var host := Node.new()
    var docker := ToolOptionsDocker.new()
    host.add_child(docker)
    docker.peer_bar = bar
    docker.target_tool_machine = machine

    var bar_size := bar.control_for(&"radius") as FactorSlider
    var docker_size := docker.options.control(&"radius") as FactorSlider
    bar_size.value_changed.emit(0.05)
    assert_almost_eq(docker_size.value, 0.05, 0.0001, "The bar moved, so the docker's own slider moved with it")
    docker_size.value_changed.emit(0.02)
    assert_almost_eq(bar_size.value, 0.02, 0.0001, "and the other way round")
    assert_almost_eq(machine.get_tool("brush").settings.radius, 0.02, 0.0001, "with the tool holding what was written last")

    host.free()
    bar.free()
    Fixtures.teardown(surface, machine)


## A tool that declares nothing gets the empty note rather than a blank panel.
func test_a_tool_with_no_options_says_so() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var host := Node.new()
    var docker := ToolOptionsDocker.new()
    host.add_child(docker)
    docker.target_tool_machine = machine

    machine.set_active_tool(&"pan")
    docker.sync_from_tool()
    assert_true(docker.shown_keys().is_empty(), "The pan tool declares no options")

    host.free()
    Fixtures.teardown(surface, machine)


## The docker shows what the bar does not. A row whose control
## the bar is showing is left out and named at the docker's foot, and comes back
## once a narrow bar has sent the control to its overflow or the painter has hid
## it from the bar.
##
## The bar is put in the tree under the event bus, because a row is left out
## only for a control visible in the tree, and a bar that is not on screen holds
## nothing for the painter. The docker stays detached, since it is a `Window`
## and one added to the tree maps a real OS window. The two are joined the way
## Main joins them, the rows' `refitted` to `sync_from_tool`.
func test_the_docker_shows_what_the_bar_does_not() -> void:
    var saved_path := SaSettings.settings_path
    var saved_row := SaSettings.second_row
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_scratch_profile()
    SaSettings.load_settings()
    SaSettings.second_row = false
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var options := ToolOptionsBar.new()
    options.target_tool_machine = machine
    options._ready()
    var bar := TopMenuBar.new()
    bar.add_tool_options(options)
    var bar_host := Node.new()
    bar_host.name = "N9BarHost"
    EventBus.add_child(bar_host)
    bar_host.add_child(bar)
    # A bar outside a container keeps the width written to it only with its
    # anchors pinned together.
    bar.set_anchor(SIDE_RIGHT, 0.0)
    var host := Node.new()
    var docker := ToolOptionsDocker.new()
    host.add_child(docker)
    docker.peer_bar = options
    bar.rows.refitted.connect(docker.sync_from_tool)
    docker.target_tool_machine = machine
    machine.set_active_tool(&"brush")

    _lay_out(bar, ROOMY)
    for key: StringName in [&"radius", &"opacity", ToolOptionControls.BLEND_KEY]:
        assert_true(docker.bar_shows(key), "The roomy bar shows '%s'" % key)
        assert_false(docker.shown_keys().has(key), "so the docker leaves '%s' out" % key)
    for key: StringName in [&"hardness", &"flow", &"stabilizer_amount"]:
        assert_true(docker.shown_keys().has(key), "and draws '%s', which the fresh bar does not show" % key)
    var foot := docker._foot_line.text
    assert_true((docker._foot_line.get_parent() as Control).visible, "The foot line is on")
    for label: String in ["Radius", "Opacity", "Blend Mode"]:
        assert_true(foot.contains(label), "and it names %s: '%s'" % [label, foot])
    assert_true(foot.ends_with(" are on the top bar."), "in a sentence that says where they are: '%s'" % foot)
    assert_false(docker._empty_label.visible, "and a brush with rows on the bar is not a tool with no options")

    # So narrow the first row holds almost nothing, which sends Size, the last
    # control to leave, into the list.
    var pinned := ROOMY - bar.rows.row_budget(1, ROOMY)
    _lay_out(bar, pinned + 120.0)
    assert_true(options.control_for(&"radius").get_parent() == bar.rows.overflow.box, "The narrow bar sent Size to its overflow")
    assert_false(docker.bar_shows(&"radius"), "so the bar no longer shows it")
    assert_true(docker.shown_keys().has(&"radius"), "and Size is a docker row again, from the refit alone")
    assert_false(docker._foot_line.text.contains("Radius"), "and the foot line no longer names it: '%s'" % docker._foot_line.text)
    # Shown in place rather than opened, because opening it moves the list into
    # a frame on the root, which a suite inside `run_all._ready` cannot add to.
    # What the painter sees open is the scenario's third shot.
    bar.rows.overflow.list.visible = true
    assert_true(options.control_for(&"radius").is_visible_in_tree(), "The shown list shows Size")
    docker.sync_from_tool()
    assert_true(docker.shown_keys().has(&"radius"), "and the row stays, since a control in the list is not at hand")
    bar.rows.overflow.list.visible = false

    _lay_out(bar, ROOMY)
    assert_false(docker.shown_keys().has(&"radius"), "A roomy bar takes Size back and the docker lets it go")
    SaSettings.set_element_visible("TopMenuBar", "opacity", false)
    bar.apply_layout_settings()
    assert_true(docker.shown_keys().has(&"opacity"), "Opacity hidden from the bar is a docker row again")
    assert_false(docker._foot_line.text.contains("Opacity"), "and the foot line lets it go: '%s'" % docker._foot_line.text)

    host.free()
    bar_host.free()
    Fixtures.teardown(surface, machine)
    _remove_scratch_profile()
    SaSettings.settings_path = saved_path
    SaSettings.load_settings()
    SaSettings.second_row = saved_row


## A tool whose every row the bar shows is a tool with options, and the foot
## line says where they are rather than the empty note saying there are none.
func test_the_foot_line_names_one_or_several() -> void:
    var host := Node.new()
    var docker := ToolOptionsDocker.new()
    host.add_child(docker)
    docker._write_foot_line(["Radius"] as Array[String])
    assert_eq(docker._foot_line.text, "Radius is on the top bar.", "One row is on the bar")
    docker._write_foot_line(["Radius", "Opacity", "Blend Mode"] as Array[String])
    assert_eq(docker._foot_line.text, "Radius, Opacity and Blend Mode are on the top bar.", "and several are")
    assert_true((docker._foot_line.get_parent() as Control).visible, "and the line shows")
    docker._write_foot_line([] as Array[String])
    assert_false((docker._foot_line.get_parent() as Control).visible, "and none takes the line away")
    host.free()


func _lay_out(bar: TopMenuBar, width: float) -> void:
    bar.size.x = width
    bar.apply_layout_settings()


func _remove_scratch_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)
