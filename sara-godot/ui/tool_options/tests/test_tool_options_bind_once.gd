## The tool options bar and the Tool Options docker bind through
## one `ToolOptionControls` binding rather than a copy each, so what either
## surface follows is asserted here on both at once.
##
## The bar is built under a plain Node and its `_ready` called by hand, and the
## docker is built detached, the way `test_tool_options_docker.gd` builds them.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

## Stands for a third-party module, the way `test_module_api_contract.gd` does.
const THIRD_PARTY := &"p7_fixture_module"
const LATE_TOOL := &"p7_late_tool"

const LATE_KEY := &"p7_late_amount"

var _surface: SaSurface
var _registries: SaRegistries
var _machine: ToolMachine
var _host: Node
var _bar: ToolOptionsBar
var _docker: ToolOptionsDocker


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    # The shipped tools, because the brush is what declares the blend list.
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _host = Node.new()
    _bar = ToolOptionsBar.new()
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar._ready()
    _bar.bind_registries(_registries.blend_modes)
    _docker = ToolOptionsDocker.new()
    _host.add_child(_docker)
    _docker.target_tool_machine = _machine
    _docker.bind_registries(_registries.blend_modes)


func after_each() -> void:
    SaSettings.unregister_layout_element("TopMenuBar", String(LATE_KEY))
    if _machine.registry.has(LATE_TOOL):
        _machine.registry.unregister(LATE_TOOL)
    _host.free()
    _host = null
    _bar = null
    _docker = null
    Fixtures.teardown(_surface, _machine)
    _registries = null


## A module tool registered once both surfaces are bound, which is a module
## loaded after the boot: the one binding follows the registry for both.
func test_a_tool_registered_after_the_boot_reaches_both_surfaces() -> void:
    assert_null(_bar.control_for(LATE_KEY), "Nothing declares the option yet")

    var descriptor := Fixtures.make_tool_descriptor(LATE_TOOL)
    descriptor.display_name = "Late Tool"
    var amount := SaOptionSpec.make_float(LATE_KEY, "Late Amount", 0.0, 2.0, 0.1)
    amount.on_tool = true
    amount.bar = true
    descriptor.options = [amount]
    assert_true(
        _machine.registry.register(descriptor, THIRD_PARTY), "The module registers its tool after both surfaces are bound"
    )

    assert_not_null(_bar.control_for(LATE_KEY), "The bar built the late tool's control")
    assert_eq(
        SaSettings.element_title("TopMenuBar", String(LATE_KEY)),
        "Late Amount (Late Tool)",
        "and titled its row for Preferences, which the bar does on a rebuild"
    )
    assert_not_null(_docker.options.control(LATE_KEY), "The docker built it too")
    assert_true(_docker._rows.has(LATE_KEY), "as a row it can show and hide")


## A document converted to another colour space: both blend lists are rebuilt
## for it, because plain Normal's label names the space the document stores.
func test_a_converted_document_refills_both_blend_lists() -> void:
    var bar_blend := _bar.control_for(ToolOptionControls.BLEND_KEY) as BlendModeButton
    var docker_blend := _docker.options.control(ToolOptionControls.BLEND_KEY) as BlendModeButton
    assert_not_null(bar_blend, "The bar has a blend list")
    assert_not_null(docker_blend, "and so has the docker")
    if bar_blend == null or docker_blend == null:
        return
    var document := _surface.get_document()
    assert_eq(bar_blend.space, document.color_space, "Both start on the document's space")
    assert_eq(docker_blend.space, document.color_space, "on both surfaces")

    var linear := SaColorSpace.linear_srgb()
    document.color_space = linear

    assert_eq(bar_blend.space, linear, "The bar's list follows the converted document")
    assert_eq(docker_blend.space, linear, "and so does the docker's")
    assert_true(bar_blend.mode_ids().has(&"normal"), "and the list was refilled rather than emptied")


## A blend mode a module registers later lands in both lists through the same
## binding.
func test_a_blend_mode_registered_later_reaches_both_lists() -> void:
    var mode := SaBlendModeDescriptor.create(&"p7_late_blend", "multiply")
    mode.display_name = "Late Blend"
    assert_true(_registries.context.for_module(THIRD_PARTY).register_blend_mode(mode), "A module registers a mode")
    var bar_blend := _bar.control_for(ToolOptionControls.BLEND_KEY) as BlendModeButton
    var docker_blend := _docker.options.control(ToolOptionControls.BLEND_KEY) as BlendModeButton
    assert_true(bar_blend != null and bar_blend.mode_ids().has(&"p7_late_blend"), "The bar offers it")
    assert_true(docker_blend != null and docker_blend.mode_ids().has(&"p7_late_blend"), "and so does the docker")
