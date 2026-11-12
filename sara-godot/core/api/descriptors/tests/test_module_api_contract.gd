## The executable form of the guiding rule.
##
##   Every built-in feature registers through the same API a third party would
##   use. If a built-in cannot be expressed that way, the API is incomplete - and
##   you find out at compile time, not from a bug report.
##
## This registers a synthetic third-party tool, blend mode, command and docker,
## then asserts each one reaches the place a built-in reaches. It fails the day a
## hardcoded string comes back.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const ToolBoxDockerScript = preload("res://ui/dockers/toolbox/toolbox_docker.gd")
const SkeletonBlendModes = preload("res://core/loader/skeleton_blend_modes.gd")

const THIRD_PARTY := &"contract-test-module"


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    return registries


## A module tool must reach the toolbox, which used to hardcode six buttons.
func test_a_module_tool_appears_in_the_toolbox() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(THIRD_PARTY)

    var descriptor := Fixtures.make_tool_descriptor(&"contract_tool")
    descriptor.display_name = "Contract Tool"
    assert_true(ctx.register_tool(descriptor), "A module may register a tool")

    var toolbox := ToolBoxDockerScript.new()
    toolbox.name = "ToolBoxDocker"
    toolbox.rebuild_from_registry(registries.tools)

    # A button draws a category rather than a tool, so reaching the
    # toolbox means having a button and being one of the tools it stands for.
    # Both halves, because a button with the tool missing from its list is a
    # button the module's tool can never be chosen from.
    assert_not_null(toolbox.button_for_tool("contract_tool"), "It must get a toolbox button like any built-in")
    assert_true(toolbox.tools_in_category_of("contract_tool").has("contract_tool"), "and be one of the tools that button offers")
    toolbox.free()


## A module tool's options must reach the bar, which used to duck-type the
## brush and could show nothing for anyone else.
func test_a_module_tools_options_reach_the_bar() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    var ctx := registries.context.for_module(THIRD_PARTY)

    var descriptor := Fixtures.make_tool_descriptor(&"contract_tool")
    descriptor.display_name = "Contract Tool"
    var amount := SaOptionSpec.make_float(&"contract_amount", "Amount", 0.0, 2.0, 0.1)
    amount.on_tool = true
    descriptor.options = [amount]
    assert_true(ctx.register_tool(descriptor), "A module may register a tool with options")

    var machine := ToolMachine.new()
    machine._ready()
    machine.bind(surface, registries.tools)
    var bar := ToolOptionsBar.new()
    bar.target_tool_machine = machine
    bar._ready()

    var slider := bar.control_for(&"contract_amount") as FactorSlider
    assert_not_null(slider, "It must get a control on the bar like any built-in")
    assert_true(
        SaSettings.get_layout_order("TopMenuBar").has("contract_amount"), "and a row in the Preferences list to move and hide"
    )
    assert_eq(SaSettings.element_title("TopMenuBar", "contract_amount"), "Amount (Contract Tool)", "under a readable title")

    SaSettings.unregister_layout_element("TopMenuBar", "contract_amount")
    bar.free()
    Fixtures.teardown(surface, machine)


## A module blend mode must reach both dropdowns. It could previously be
## registered but never selected, because both read a closed const in sa_layer.gd.
func test_a_module_blend_mode_appears_in_the_dropdowns() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(THIRD_PARTY)

    var mode := SaBlendModeDescriptor.create(&"contract_blend", "multiply")
    mode.display_name = "Contract Blend"
    assert_true(ctx.register_blend_mode(mode), "A module may register a blend mode")

    var button := BlendModeButton.new()
    button.registry = registries.blend_modes
    button.refresh()
    assert_true(button.mode_ids().has(&"contract_blend"), "It must appear in a menu built from the registry")
    # It named no category, so the menu's last section is the one that holds it.
    var other := button.section_labels("Other")
    assert_false(other.is_empty(), "A mode with no category opens the Other section")
    assert_true(other.has("Contract Blend"), "and it is in it")
    button.free()


## Its kernel is resolved by name, so registration order carries no meaning.
func test_blend_modes_resolve_by_kernel_name_not_ordinal() -> void:
    var registries := _registries()

    var expected := GlobalShaderCompiler.get_kernel_index("composite", "erase")
    assert_true(expected > 0, "The erase kernel exists and is not the first one")
    assert_eq(
        registries.blend_modes.resolve_kernel(&"erase"), expected, "The registry must resolve the index from the shader, by name"
    )
    assert_true(registries.validate().is_empty(), "Every registered mode must name a real kernel")


## A module command must dispatch, and get a working shortcut without anyone
## editing project.godot.
func test_a_module_command_dispatches_and_gets_a_shortcut() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(THIRD_PARTY)

    var fired := [false]
    var command := SaCommandDescriptor.create(&"contract_command", "Contract", func() -> void: fired[0] = true)
    command.action = &"contract_command_action"
    var trigger := InputEventKey.new()
    trigger.physical_keycode = KEY_F13
    command.default_events = [trigger]
    assert_true(ctx.register_command(command), "A module may register a command")

    assert_true(InputMap.has_action(&"contract_command_action"), "Its action is created if absent")

    var press := InputEventKey.new()
    press.physical_keycode = KEY_F13
    press.pressed = true
    assert_true(registries.commands.try_handle_input(press), "The registry dispatches it")
    assert_true(fired[0], "and the handler runs")

    InputMap.erase_action(&"contract_command_action")


## Unregistering a module removes everything it added, so a module does not have
## to track its own bookkeeping.
func test_unregistering_removes_everything_the_module_added() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(THIRD_PARTY)

    ctx.register_tool(Fixtures.make_tool_descriptor(&"doomed_tool"))
    ctx.register_blend_mode(SaBlendModeDescriptor.create(&"doomed_blend", "screen"))
    assert_true(registries.tools.has(&"doomed_tool"), "Registered before removal")

    ctx.remove_all_registrations()

    assert_false(registries.tools.has(&"doomed_tool"), "Its tool is gone")
    assert_false(registries.blend_modes.has(&"doomed_blend"), "Its blend mode is gone")
    assert_true(registries.blend_modes.has(&"normal"), "The skeleton's own modes are untouched")


## The skeleton registers its built-ins through this same API. If it could not,
## the API would be incomplete - that is the whole point of the rule.
func test_the_skeleton_expresses_its_builtins_through_the_api() -> void:
    var registries := _registries()

    assert_not_null(registries.skeleton_module, "The skeleton is itself a module")
    # Counted from the table rather than written out, so adding a mode is one
    # edit. What this asserts is that every row of it arrived, which is the
    # contract: a built-in that could not register through the public API would
    # mean the API has a hole only the skeleton can reach around.
    var declared: int = SkeletonBlendModes.BLEND_MODES.size()
    assert_eq(registries.blend_modes.list_ids().size(), declared, "Every built-in mode registered through it")
    for expected: StringName in [&"normal", &"multiply", &"hue", &"erase"]:
        assert_true(registries.blend_modes.has(expected), "'%s' registered through the public API" % expected)


## Erase is a brush concept, so it must not be offered as a layer blend mode.
func test_layer_dropdown_hides_modes_marked_hidden() -> void:
    var registries := _registries()

    var layer_entries := registries.blend_modes.list_ui_entries(false)
    for entry: SaBlendModeDescriptor in layer_entries:
        assert_true(entry.id != &"erase", "Erase must not appear in the layer list")
    # An internal mode is in the table and in the registry and in neither menu
    #, so the brush's list is the table less those.
    assert_eq(
        registries.blend_modes.list_ui_entries(true).size(),
        SkeletonBlendModes.BLEND_MODES.size() - SkeletonBlendModes.INTERNAL_MODES.size(),
        "but it is still available to the brush"
    )


## An alpha-locked wash stroke composites through a registered mode, which
## is the public door hard rule 6 asks for, and no dropdown offers it: it is a
## rule about how a stroke lands rather than a mode anyone picks.
func test_internal_modes_are_registered_and_offered_nowhere() -> void:
    var registries := _registries()

    for mode_id: StringName in SkeletonBlendModes.INTERNAL_MODES:
        assert_true(registries.blend_modes.has(mode_id), "'%s' is registered" % mode_id)
        assert_true(registries.blend_modes.get_descriptor(mode_id).internal, "and marked internal")
        for include_hidden: bool in [true, false]:
            for entry: SaBlendModeDescriptor in registries.blend_modes.list_ui_entries(include_hidden):
                assert_true(entry.id != mode_id, "'%s' is in no menu" % mode_id)


## The two modes a painter switches between all day sit together at the top.
##
## Erase was last of seventeen, which put the most-used mode after the whole
## Oklab family. Pinned because the order is a sort key spread over one const
## column, so renumbering anything can move it without touching this file.
func test_the_brush_dropdown_opens_with_normal_then_erase() -> void:
    var registries := _registries()

    var entries := registries.blend_modes.list_ui_entries(true)
    assert_true(entries.size() >= 2, "There are at least two modes to order")
    assert_eq(entries[0].id, &"normal", "Normal stays pinned first")
    assert_eq(entries[1].id, &"erase", "Erase sits directly under it")


## Plain Normal has no blending space of its own: it mixes in whatever the
## document stores. "Normal" alone therefore does not say whether it is about to
## mix encoded RGB, light or perceptual coordinates, and those give visibly
## different greys, so the dropdown names the one it currently is.
func test_plain_normal_names_the_space_it_is_mixing_in() -> void:
    var registries := _registries()
    var normal: SaBlendModeDescriptor = registries.blend_modes.get_descriptor(&"normal")
    assert_not_null(normal, "Normal is registered")
    assert_true(normal.follows_document_space, "and is the mode with no space of its own")

    assert_eq(normal.label_for(SaColorSpace.srgb()), "Normal (sRGB)", "An sRGB document mixes encoded sRGB")
    assert_eq(normal.label_for(SaColorSpace.linear_srgb()), "Normal (linear)", "a linear one mixes light")
    assert_eq(normal.label_for(SaColorSpace.oklab()), "Normal (Oklab)", "and an Oklab one mixes perceptually")
    assert_eq(normal.label_for(null), "Normal", "With no document in hand the label stays static")

    # Every other mode is defined in its own space and must not pick up a bracket,
    # or seventeen labels would start moving with the document for no reason.
    var multiply: SaBlendModeDescriptor = registries.blend_modes.get_descriptor(&"multiply")
    assert_eq(multiply.label_for(SaColorSpace.oklab()), "Multiply", "A mode with its own space keeps its name")


## The three explicit Normals sit directly under Erase, which is where a painter
## looking for "the other Normal" will look, and they carry fixed names because
## each one names its own space rather than the document's.
func test_the_three_named_normals_follow_erase() -> void:
    var registries := _registries()
    var ids: Array[StringName] = []
    for entry: SaBlendModeDescriptor in registries.blend_modes.list_ui_entries(true):
        ids.append(entry.id)

    var erase_at := ids.find(&"erase")
    assert_true(erase_at >= 0, "Erase is in the list")
    assert_eq(ids[erase_at + 1], &"normal_srgb", "Normal (sRGB) follows Erase")
    assert_eq(ids[erase_at + 2], &"normal_linear", "then Normal (linear)")
    assert_eq(ids[erase_at + 3], &"normal_oklab", "then Normal (Oklab)")

    var button := BlendModeButton.new()
    button.registry = registries.blend_modes
    button.space = SaColorSpace.oklab()
    button.refresh()
    var labels := button.section_labels("Normal")
    assert_true(labels.has("Oklab Normal"), "The explicit Oklab Normal is in the dropdown")
    assert_true(labels.has("Linear Normal"), "and the linear one")
    # Plain Normal still carries the document's space in brackets, which is what
    # says which of the three it currently equals, and it is the only row that
    # does: the pinned three lead with their space instead, so no two rows of
    # this section read the same words. This asserted a count of two until
    # then, which was the collision written down as a requirement.
    assert_eq(labels.count("Normal (Oklab)"), 1, "and the document's own Normal says which one it equals")
    button.free()


## The item texts of a blend menu's section, in order.
func _menu_labels(menu: SaChoicePopup) -> Array[String]:
    var labels: Array[String] = []
    if menu == null:
        return labels
    labels.append_array(menu.row_labels())
    return labels
