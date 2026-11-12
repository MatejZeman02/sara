## Every filter the base module registers declares a section the module itself
## registers, so none falls to Other by a typo, and its command has a row on the Keyboard Shortcuts page under
## a label that is not its identifier.
##
## The usual filters ship no chord, so the row is where a painter gives them
## one: `SaShortcutRows.actions_for` keeps an unbound action's row for exactly
## that reason.
extends "res://tests/test_framework.gd"

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")


## A context of its own with the whole module registered, the way the loader
## does it, so a filter a later row adds is counted without this suite naming it.
func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var mod := BaseModule.new()
    mod.register(registries.context.for_module(mod.get_id()))
    return registries


func test_every_base_filter_declares_a_section_the_module_registers() -> void:
    var registries := _registries()
    var words: Array[StringName] = []
    for section: SaFilterRegistry.Section in registries.filters.list_sections():
        words.append(section.id)
    var keys := registries.filters.list_keys()
    assert_true(keys.size() >= 15, "the six adjustments and the usual set are registered: %d" % keys.size())
    for key: StringName in keys:
        var family := registries.filters.get_filter(key).family()
        assert_true(words.has(family), "%s names a registered section, not '%s'" % [key, family])
        assert_true(family != SaFilterRegistry.OTHER, "and not Other, which is for a filter nobody sorted: %s" % key)


## The table holds no key that spells the module's name, so a filter of the
## module reads its own title through the registry the page is handed rather
## than from a label written into the skeleton.
func test_every_base_filter_has_a_labelled_row_on_the_shortcuts_page() -> void:
    var registries := _registries()
    var rows := SaShortcutRows.actions_for("filter_")
    for key: StringName in registries.filters.list_keys():
        var command := SaFilterRegistry.command_for(key, registries.filters.get_filter(key))
        assert_true(rows.has(command), "%s has a row in the Filter section" % command)
        var label := SaShortcutsPage.label_for(String(command), null, registries.filters)
        assert_true(label != String(command), "and %s reads as a title, '%s'" % [command, label])
