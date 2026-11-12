## The three slider adjustments register through the door.
##
## What the move must not have cost a painter: the chord each one opens on, the
## command id a profile may have rebound, and a row in the Filter menu, which is
## now under the base module's name. The passes themselves are
## `test_adjustments.gd` and `test_color_balance.gd` beside this.
extends "res://tests/test_framework.gd"

const MODULE_ID := &"sara-base-modules"

## Command id -> the chord it shipped with before the move and ships with now.
const CHORDS := {
    &"filter_brightness_contrast": "Ctrl+Shift+B",
    &"filter_hue_saturation_lightness": "Ctrl+U",
    # Ctrl+B is what Photoshop and Krita both put it on, and
    # Brightness/Contrast sits on Ctrl+Shift+B rather than in the way of it.
    &"filter_color_balance": "Ctrl+B",
}


## The skeleton's own commands and the three filters, registered the way the
## base module registers them.
func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var ctx := registries.context.for_module(MODULE_ID)
    assert_true(ctx.register_filter_section(&"tone", "Tone", 100), "the Tone section registers")
    assert_true(ctx.register_filter_section(&"color", "Colour", 200), "the Colour section registers")
    assert_true(ctx.register_filter(SaBrightnessContrastFilter.new()), "Brightness/Contrast registers")
    assert_true(ctx.register_filter(SaHueSaturationLightnessFilter.new()), "Hue/Saturation/Lightness registers")
    assert_true(ctx.register_filter(SaColorBalanceFilter.new()), "Colour Balance registers")
    return registries


func test_the_three_keep_their_command_ids_and_their_chords() -> void:
    var registries := _registries()
    for command_id: StringName in CHORDS:
        assert_true(registries.commands.has(command_id), "%s is registered" % command_id)
        assert_eq(registries.commands.chord_text(command_id), CHORDS[command_id], "%s answers to it" % command_id)
        assert_eq(registries.commands.get_descriptor(command_id).owner_module, MODULE_ID, "and the module owns it now")
    # The three slider filters: Levels and Curves have a suite of their
    # own, which registers all five.
    var three: Array[StringName] = [
        SaPointAdjust.BRIGHTNESS_CONTRAST, SaPointAdjust.HUE_SATURATION_LIGHTNESS, SaPointAdjust.COLOR_BALANCE
    ]
    for kind: StringName in three:
        assert_true(registries.filters.has(StringName("%s.%s" % [MODULE_ID, kind])), "%s is a filter keyed by its kind" % kind)


func test_no_command_of_the_skeleton_shares_one_of_the_three_chords() -> void:
    var registries := _registries()
    var seen: Dictionary = {}
    var clashes: Array[String] = []
    for command_id: StringName in registries.commands.list_ids():
        for chord in registries.commands.chord_text(command_id).split(", ", false):
            if seen.has(chord):
                clashes.append("%s and %s both answer %s" % [seen[chord], command_id, chord])
            seen[chord] = command_id
    assert_true(clashes.is_empty(), ", and ".join(clashes))


## A rebind is written onto the InputMap action by the command's id, so the id
## the filter declares is the whole of what keeps it.
func test_a_profile_that_rebound_one_keeps_its_chord() -> void:
    var action := &"filter_brightness_contrast"
    var registries := _registries()
    var shipped := SaShortcutStore.chords_for(action)
    SaShortcutStore.set_chords(action, ["Ctrl+Alt+K"])
    assert_eq(registries.commands.chord_text(action), "Ctrl+Alt+K", "The rebind lands on the filter's command")
    # The next launch: the action already carries the painter's chord by the
    # time the module registers, and registering must not put the shipped one
    # back beside it.
    var again := _registries()
    assert_eq(again.commands.chord_text(action), "Ctrl+Alt+K", "and a second registration leaves it alone")
    SaShortcutStore.set_chords(action, shipped)
    assert_eq(again.commands.chord_text(action), CHORDS[action], "Put back, for the suites after this one")


func test_the_filter_menu_lists_the_three_under_their_families() -> void:
    var registries := _registries()
    # The browser's row is a command of the shortcut table, the way main has it.
    SaShortcutCommands.new(Callable(), Callable(), Callable(), null).register_into(registries.commands)
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(registries.commands)
    var menu := bar.menu("Filter") as SaFilterMenu
    menu.filters = registries.filters
    var popup: SaChoicePopup = bar.menus["Filter"]
    var labels := popup.row_labels()
    # Apply Again's row and the browser's are the first two.
    assert_eq(Array(labels).slice(2, 4), ["Tone", "Colour"], "a row per section after the browser's, tone first by its place")
    var tone := Array(menu.show_section(menu.section_item(&"tone")).row_labels())
    assert_eq(tone[0], "Brightness/Contrast", "The Tone list holds Brightness/Contrast, nothing being built in")
    var colour := menu.show_section(menu.section_item(&"color"))
    assert_eq(
        Array(colour.row_labels()).slice(0, 2),
        ["Hue/Saturation/Lightness", "Colour Balance"],
        "and the other two keep their order in the Colour list"
    )
    var hints: Dictionary = {}
    for entry: Dictionary in colour.row_report():
        hints[String(entry.get("label", ""))] = String(entry.get("hint", ""))
    assert_eq(hints.get("Colour Balance", ""), "Ctrl+B", "and a row shows the chord its filter declared")
    bar.free()
