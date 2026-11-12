## The Merged row's hover is true of whichever tool is in hand.
##
## The eyedropper and the wand once both declared `sample_merged`,
## and the bar and the Tool Options docker keep one control for a key however
## many tools declare it, so the first declaration's hover showed for both.
## With the wand in hand the row said Eyedropper. The two declarations then
## carried one hover that named neither tool.
##
## The eyedropper has a Sample row of its own in place of Merged, so the
## wand is the one tool that declares the key now, and its hover
## still names no tool.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

## Words that would name one of the two tools to a painter holding the other.
const TOOL_WORDS: Array[String] = ["eyedropper", "wand", "picker", "dropper"]


func test_the_docker_row_names_no_tool_with_the_wand_in_hand() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var host := Node.new()
    var docker := ToolOptionsDocker.new()
    host.add_child(docker)
    docker.target_tool_machine = machine

    machine.set_active_tool(&"wand")
    docker.sync_from_tool()
    assert_true(docker.shown_keys().has(&"sample_merged"), "With the wand in hand the Merged row is shown")
    var control := docker.options.control(&"sample_merged")
    assert_not_null(control, "and the docker built its toggle")
    var hover := ToolOptionsDocker.row_tooltip(control) if control != null else ""
    assert_false(hover.is_empty(), "The row says what it does")
    assert_true(hover.to_lower().contains("every layer"), "it says it reads every layer: %s" % hover)
    for word in TOOL_WORDS:
        assert_false(hover.to_lower().contains(word), "and names no tool: %s" % hover)

    machine.set_active_tool(&"eyedropper")
    docker.sync_from_tool()
    assert_false(docker.shown_keys().has(&"sample_merged"), "With the eyedropper in hand there is no Merged row")

    host.free()
    Fixtures.teardown(surface, machine)


## The wand's declaration names no tool, and the eyedropper declares no Merged
## row, so there is no second declaration to disagree with it.
func test_the_one_declaration_names_no_tool() -> void:
    var dropper_hover := _merged_hover(BaseModule.eyedropper_options())
    var wand_hover := _merged_hover(BaseModule.wand_options())
    assert_true(dropper_hover.is_empty(), "The eyedropper declares no Merged row")
    assert_false(wand_hover.is_empty(), "The wand declares it with a hover")
    for word in TOOL_WORDS:
        assert_false(wand_hover.to_lower().contains(word), "which names no tool: %s" % wand_hover)


func _merged_hover(specs: Array[SaOptionSpec]) -> String:
    for spec in specs:
        if spec.key == &"sample_merged":
            return spec.tooltip
    return ""
