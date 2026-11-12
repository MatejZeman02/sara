## A filter from a module the skeleton has never heard of reads on the Keyboard
## Shortcuts page as its own title, not as its command's identifier.
##
## The page's own table of words named every filter of the base module, which
## is why the earlier suite passed while the box blur's row read "Filter Box Blur Box".
## A table in the skeleton cannot name a stranger's filters, so the row asks the
## filter registry the way a tool row asks the tool registry. The table is gone
## since the page reads each command's title, and the filter's own title is
## what a row with no command title reads.
extends "res://tests/test_framework.gd"

const BoxBlur = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")


## A filter whose title is the suite's choice and whose command may be too.
class StrangerFilter:
    extends SaFilter
    var entry_title: String
    var entry_action: StringName

    func _init(text: String, action: StringName = &"") -> void:
        entry_title = text
        entry_action = action

    func title() -> String:
        return entry_title

    func action_name() -> StringName:
        return entry_action

    func run(_ctx: SaFilterContext) -> void:
        pass


func test_a_strangers_filter_reads_as_its_title() -> void:
    var filters := SaFilterRegistry.new()
    var filter := StrangerFilter.new("Crackle glaze")
    assert_true(filters.register(filter, &"made_up_module"), "the fixture registers on a module nobody ships")
    var key := SaFilterRegistry.key_for(&"made_up_module", filter)
    var command := String(SaFilterRegistry.command_for(key, filter))
    assert_eq(command, "filter_made_up_module_crackle_glaze", "its command is spelled from its key")
    assert_false(SaShortcutRows.WORDS.has(command), "and the skeleton's table does not know it")
    assert_eq(SaShortcutRows.label_for(command, null, filters), "Crackle glaze", "so the row reads the filter's own title")


func test_a_declared_command_name_is_found_as_well() -> void:
    var filters := SaFilterRegistry.new()
    filters.register(StrangerFilter.new("Crackle glaze", &"filter_crackle"), &"made_up_module")
    assert_eq(SaShortcutRows.label_for("filter_crackle", null, filters), "Crackle glaze", "a filter that named its own command")


func test_without_the_registry_the_identifier_is_what_is_left() -> void:
    assert_eq(
        SaShortcutRows.label_for("filter_made_up_module_crackle_glaze"),
        "Filter Made Up Module Crackle Glaze",
        "no registry, so the row falls back to the identifier as before",
    )


func test_the_commands_title_wins_over_a_filters_title() -> void:
    var filters := SaFilterRegistry.new()
    filters.register(StrangerFilter.new("Not the page's word", &"filter_levels"), &"made_up_module")
    var commands := SaCommandRegistry.new()
    commands.register(SaCommandDescriptor.create(&"filter_levels", "Levels", func() -> bool: return true))
    assert_eq(SaShortcutRows.label_for("filter_levels", null, filters, commands), "Levels", "the command's own title is kept")


## The box blur as a module of its own,
## a student's copy in a folder `box-blur` with no `module.gd`, whose command is
## `filter_box_blur_box_blur`, registered the way the loader does it.
func test_the_box_blur_row_reads_its_title() -> void:
    var filters := SaFilterRegistry.new()
    var mod := SaModule.new(SaDataRoot.path("modules/box-blur"))
    var filter := BoxBlur.new()
    filters.register(filter, mod.get_id())
    var command := String(SaFilterRegistry.command_for(SaFilterRegistry.key_for(mod.get_id(), filter), filter))
    assert_eq(command, "filter_box_blur_box_blur", "the command is the module id twice")
    assert_eq(SaShortcutRows.label_for(command, null, filters), "Box Blur", "reads as the filter's title")
    assert_eq(SaShortcutsPage.label_for(command, null, filters), "Box Blur", "and the page's door says the same")
