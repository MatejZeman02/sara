## The skeleton's shortcut table names no module, and the base module's usual
## filters read their own titles on the Keyboard Shortcuts page and in the
## Filter menu, the three blurs in title case with the rest of the family.
##
## `SaShortcutRows.LABELS` carried twelve keys spelling `sara-base-modules`,
## written by two earlier changes, and the three blurs read in sentence case there while
## every other filter of the module reads in title case, so the Filter menu and
## the shortcuts page mixed the two inside one family list. A table in the
## skeleton cannot name a module's filters, which is what the fallback says
## and what this row carries the last twelve rows through.
##
## The three blurs keep the commands they had: `SaFilter.id` is the slug of the
## title, which lowercases, so `filter_sara-base-modules_gaussian_blur` is the
## command a chord reaches either way. What left is the table's word for it.
extends "res://tests/test_framework.gd"

## The module the table must not name. Spelled once, because the check is on the
## word rather than on any one of the twelve keys.
const MODULE_WORD := "sara-base-modules"
const MODULE_ID := &"sara-base-modules"

## The table's file, read as text by a literal check: a
## grep of it for the module's name finds nothing.
const SOURCE_PATH := "res://ui/settings/keyboard/shortcut_rows.gd"

## The command each of the three blurs still answers to, with the title it must
## now read. The commands are the old table's keys, which is the point: the row
## that left the table did not move the chord.
const BLURS := [
    ["filter_sara-base-modules_gaussian_blur", "Gaussian Blur"],
    ["filter_sara-base-modules_motion_blur", "Motion Blur"],
    ["filter_sara-base-modules_lens_blur", "Lens Blur"],
]

var _bar: TopMenuBar = null


func after_each() -> void:
    if _bar != null:
        _bar.free()
    _bar = null


## The three blurs registered the way the base module registers them, under the
## module's own id, so the commands below are spelled from real registrations
## rather than from the suite's constants.
func _registry() -> SaFilterRegistry:
    var filters := SaFilterRegistry.new()
    assert_true(filters.register(SaGaussianBlurFilter.new(), MODULE_ID), "the Gaussian blur registers")
    assert_true(filters.register(SaMotionBlurFilter.new(), MODULE_ID), "the motion blur registers")
    assert_true(filters.register(SaLensBlurFilter.new(), MODULE_ID), "the lens blur registers")
    return filters


func test_the_three_blurs_register_under_the_commands_the_table_carried() -> void:
    var filters := _registry()
    for row: Array in BLURS:
        var wanted: String = row[0]
        var found := false
        for key: StringName in filters.list_keys():
            var filter := filters.get_filter(key)
            if String(SaFilterRegistry.command_for(key, filter)) == wanted:
                found = true
        assert_true(found, "%s is the command a chord still reaches" % wanted)


func test_the_table_names_no_module() -> void:
    for action: String in SaShortcutRows.ORDER + SaShortcutRows.WORDS.keys():
        assert_false(action.contains(MODULE_WORD), "the table must name no module, and '%s' does" % action)


## The literal check, over the file rather than over
## the parsed table, so a key spelled back into the page fails here too.
func test_the_tables_file_names_no_module() -> void:
    var file := FileAccess.open(SOURCE_PATH, FileAccess.READ)
    assert_not_null(file, "the table's file is readable")
    var text := file.get_as_text()
    file.close()
    assert_false(text.contains(MODULE_WORD), "shortcut_rows.gd names no module anywhere in it")


func test_the_three_blurs_read_their_title_case_title_on_both_doors() -> void:
    var filters := _registry()
    for row: Array in BLURS:
        var command: String = row[0]
        var title: String = row[1]
        assert_false(SaShortcutRows.ORDER.has(StringName(command)), "%s left the table" % command)
        assert_eq(SaShortcutRows.label_for(command, null, filters), title, "the row reads the filter's title")
        assert_eq(SaShortcutsPage.label_for(command, null, filters), title, "and the page's door says the same")


## The six the order table keeps, which are the filters that declare a command
## of their own (declared by the filters). They keep their place because their
## commands are older, and each reads the word its filter declares,
## which is what the sweep below holds.
const THE_SIX := [
    "filter_brightness_contrast",
    "filter_levels",
    "filter_curves",
    "filter_hue_saturation_lightness",
    "filter_color_balance",
    "filter_palette",
]


## Every filter of the module read at once: the twelve are absent
## from the table and read their own title, the six that are older are
## present and read the same title, and the family list is therefore one
## family's spelling rather than two.
func test_the_rest_of_the_module_reads_off_the_registry_as_well() -> void:
    var filters := SaFilterRegistry.new()
    var commands := SaCommandRegistry.new()
    var module: SaModule = load("res://modules/sara-base-modules/base/module.gd").new()
    var ctx := SaContext.create(
        SaToolRegistry.new(),
        SaBlendModeRegistry.new(),
        commands,
        SaLayerTypeRegistry.new(),
        SaUIRegistry.new(),
        null,
        Callable(),
        Callable(),
        filters,
        SaRoleRegistry.new()
    )
    module.register(ctx.for_module(module.get_id()))
    var seen := 0
    for key: StringName in filters.list_keys():
        var filter := filters.get_filter(key)
        var command := String(SaFilterRegistry.command_for(key, filter))
        assert_eq(
            SaShortcutRows.ORDER.has(StringName(command)),
            THE_SIX.has(command),
            "%s is in the skeleton's order only if it is one of the six that declared a command" % command
        )
        assert_eq(SaShortcutsPage.label_for(command, null, filters, commands), filter.title(), "and reads as its own title")
        seen += 1
    assert_eq(
        seen,
        43,
        (
            "the base module registers its usual set, the six first shipped, and ten more since: "
            + "Low Pass, White Point, High Pass, Red-eye, Drifting Noise, the LUT, Hot Pixels, Tonemap, "
            + "Lens Correction and Local Contrast, Grain having become a type of Add Noise, "
            + "and Box Blur, a module of its own until it joined the base module's blurs"
        )
    )
    module.unregister(ctx)


## The menu's rows are the filters' titles, read off the same registry the page
## reads, so the two surfaces cannot disagree about how a family is spelled.
func test_the_filter_menu_reads_the_same_titles() -> void:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var base := registries.context.for_module(StringName(MODULE_WORD))
    assert_true(base.register_filter(SaGaussianBlurFilter.new()), "the Gaussian blur registers through the door")
    assert_true(base.register_filter(SaMotionBlurFilter.new()), "the motion blur does too")
    assert_true(base.register_filter(SaLensBlurFilter.new()), "and the lens blur")
    _bar = TopMenuBar.new()
    _bar._ready()
    _bar.bind_commands(registries.commands)
    var menu := _bar.menu("Filter") as SaFilterMenu
    menu.filters = registries.filters
    # No section is registered here, so the three blurs are in Other's list.
    var labels := Array(menu.show_section(menu.section_item(SaFilterRegistry.OTHER)).row_labels())
    for row: Array in BLURS:
        var title: String = row[1]
        assert_true(labels.has(title), "the Filter menu lists '%s', and it reads %s" % [title, labels])
