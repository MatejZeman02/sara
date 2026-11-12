## Shift with a tool's key steps through that tool's family.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The family is the tools that share a button in the toolbox, in the flyout's
## order, wrapping after the last. Shift+M steps the selection tools and
## Shift+L the lassos, a tool alone in its group is just picked, and the docker
## toggles that held a Shift chord a tool took still open from their summon.
## The commands are registered through the public door, so they show on the
## Keyboard page and no two default commands share a chord.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The machine is bound to a surface, which builds an easel.
const REQUIRES_GPU := true

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _hidden: Array[String] = []


func before_each() -> void:
    _hidden.clear()
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _registries = Fixtures.make_registries(_surface)
    var machine := _machine
    SaToolFamilies.register_all(_registries.context, func() -> ToolMachine: return machine)
    _machine.set_active_tool(&"brush")


func after_each() -> void:
    for entry: String in _hidden:
        SaSettings.set_element_visible(SaDockerIds.TOOLBOX, entry, true)
    _registries = null
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func _active() -> StringName:
    return _machine.registry.tool_of(_machine.default_tool_name)


func _press(command: StringName) -> void:
    assert_true(_registries.commands.execute(command), "%s runs" % command)


func test_shift_m_steps_the_selection_tools_in_order_and_wraps() -> void:
    var family := SaToolFamilies.family_of(_machine, &"marquee")
    assert_true(family.size() >= 2, "the marquee shares a button: %s" % [family])
    assert_eq(family[0], &"marquee", "the rectangle leads the flyout")
    _press(&"tool_family_marquee")
    assert_eq(_active(), &"marquee", "with none of them in hand the first is picked")
    for step: int in range(1, family.size()):
        _press(&"tool_family_marquee")
        assert_eq(_active(), family[step], "step %d is the next of the flyout" % step)
    _press(&"tool_family_marquee")
    assert_eq(_active(), &"marquee", "and the step past the last wraps to the rectangle")


func test_shift_l_steps_the_lassos() -> void:
    var family := SaToolFamilies.family_of(_machine, &"lasso")
    assert_eq(family, [&"lasso", &"polygonal_lasso", &"magnetic_lasso"] as Array[StringName], "the three lassos, freehand first")
    var seen: Array[StringName] = []
    for i: int in 4:
        _press(&"tool_family_lasso")
        seen.append(_active())
    assert_eq(seen, [&"lasso", &"polygonal_lasso", &"magnetic_lasso", &"lasso"] as Array[StringName], "in order, and wrapping")


func test_a_tool_alone_in_its_group_is_just_picked() -> void:
    assert_eq(SaToolFamilies.family_of(_machine, &"eyedropper"), [&"eyedropper"] as Array[StringName], "the eyedropper is alone")
    _press(&"tool_family_eyedropper")
    assert_eq(_active(), &"eyedropper", "Shift+I picks it")
    _press(&"tool_family_eyedropper")
    assert_eq(_active(), &"eyedropper", "and again keeps it")


func test_a_tool_hidden_from_the_toolbox_is_skipped() -> void:
    var registry := _machine.registry
    var entry := SaToolBoxGrid.layout_entry_for(registry.get_descriptor(&"polygonal_lasso"))
    _hidden.append(entry)
    SaSettings.set_element_visible(SaDockerIds.TOOLBOX, entry, false)
    assert_eq(
        SaToolFamilies.family_of(_machine, &"lasso"),
        [&"lasso", &"magnetic_lasso"] as Array[StringName],
        "the hidden lasso is out"
    )


func test_the_fill_family_starts_at_the_fill() -> void:
    _press(&"tool_family_gradient")
    assert_eq(_active(), &"bucket_fill", "with neither in hand the first member is picked")
    _press(&"tool_family_gradient")
    assert_eq(_active(), &"gradient", "and the next press steps to the gradient")


func test_next_member_is_pure_and_wraps() -> void:
    var members := [&"a", &"b", &"c"]
    assert_eq(SaToolFamilies.next_member(members, &"a"), &"b", "a then b")
    assert_eq(SaToolFamilies.next_member(members, &"c"), &"a", "c wraps to a")
    assert_eq(SaToolFamilies.next_member(members, &"z"), &"a", "a stranger starts at the first")
    assert_eq(SaToolFamilies.next_member([], &"a"), &"", "no members, no tool")


func test_each_cycle_is_a_command_with_a_shift_chord_and_none_of_them_clash() -> void:
    for row: Array in SaToolFamilies.ROWS:
        var descriptor := _registries.commands.get_descriptor(row[0])
        assert_not_null(descriptor, "%s is registered" % row[0])
        assert_eq(descriptor.category, &"tool", "%s is filed under Tools" % row[0])
    SaShortcutStore.capture_defaults()
    for row: Array in SaToolFamilies.ROWS:
        var chord := "Shift+" + char(row[2])
        assert_eq(SaShortcutStore.holders(chord), [String(row[0])] as Array[String], "%s is %s's alone" % [chord, row[0]])
    assert_eq(SaShortcutStore.all_conflicts().keys(), [], "no two default commands share a chord")


func test_the_photoshop_map_steps_the_families_too() -> void:
    var table: Dictionary = SaShortcutStore.SHIPPED_PROFILES["Photoshop"]
    for row: Array in SaToolFamilies.ROWS:
        assert_eq(table.get(String(row[0])), "Shift+" + char(row[2]), "Photoshop steps %s on its Shift chord" % row[0])
