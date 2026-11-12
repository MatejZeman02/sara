## A filter registers the way a tool or a blend mode does, and
## the Filter menu, a command and the dialog host all read one list.
##
## The contract is what this suite reads back:
## "`SaFilter` is a `RefCounted` base with two methods, `build(ui)` and
## `run(ctx)`. `register_filter` puts it in the Filter menu under the module's
## name and in the command palette, and opens its dialog when picked." The
## fixture module under `tests/fixtures/modules/filter-menu-fixture/` is the
## third-party half, registered through `SaContext` and nothing else, so an
## API gap shows up here rather than in a bug report.
extends "res://tests/test_framework.gd"

const FIXTURE_MODULE = preload("res://tests/fixtures/modules/filter-menu-fixture/module.gd")
const TINT_FILTER = preload("res://tests/fixtures/modules/filter-menu-fixture/tint_filter.gd")

const FIXTURE_ID := &"filter-menu-fixture"
const FIXTURE_KEY := &"filter-menu-fixture.fixture_tint"


## A filter that answers to whatever title it is given, for the two-modules
## case and for the slug.
##
## The member is public because `title()` reading a private back is the getter
## shape `tests/test_privates_rule.gd` counts. Written by this class alone, in
## `_init`, which is what the rule asks of a member set from outside.
class NamedFilter:
    extends SaFilter
    var entry_title: String

    func _init(text: String) -> void:
        entry_title = text

    func title() -> String:
        return entry_title

    func run(_ctx: SaFilterContext) -> void:
        pass


func after_each() -> void:
    ModuleLoader.loaded_modules.erase(FIXTURE_ID)


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    return registries


## The fixture module registered through the public door, and the registries
## it registered into.
func _with_fixture() -> SaRegistries:
    var registries := _registries()
    var module := FIXTURE_MODULE.new()
    module.register(registries.context.for_module(module.get_id()))
    return registries


func test_a_module_registers_a_filter_through_the_public_door() -> void:
    var registries := _with_fixture()
    var registry := registries.filters
    assert_true(registry.has(FIXTURE_KEY), "The filter is in the registry under module.title")
    assert_eq(registry.owner_of(FIXTURE_KEY), FIXTURE_ID, "attributed to the module that registered it")
    assert_eq(registry.list_keys(), [FIXTURE_KEY] as Array[StringName], "and it is the only one")
    var filter := registry.get_filter(FIXTURE_KEY)
    assert_true(filter is SaFilter, "What comes back is the filter itself, not a descriptor")
    assert_eq(filter.title(), "Fixture Tint", "with the title the menu shows")


func test_the_key_is_the_module_and_the_slug_of_the_title() -> void:
    assert_eq(SaFilter.slug("Box blur"), &"box_blur", "Lower case, one underscore for the gap")
    assert_eq(SaFilter.slug("Hue/Saturation/Lightness..."), &"hue_saturation_lightness", "Runs collapse and edges are trimmed")
    assert_eq(SaFilter.slug("Blur 2D"), &"blur_2d", "Digits survive")
    var registries := _registries()
    var one := registries.context.for_module(&"module-a")
    var two := registries.context.for_module(&"module-b")
    assert_true(one.register_filter(NamedFilter.new("Box blur")), "Two modules may ship one name")
    assert_true(two.register_filter(NamedFilter.new("Box blur")), "and the second is not refused")
    assert_eq(
        registries.filters.list_keys(),
        [&"module-a.box_blur", &"module-b.box_blur"] as Array[StringName],
        "because the module id is half the key"
    )


func test_the_filter_reaches_the_command_list_and_opens_from_it() -> void:
    var registries := _with_fixture()
    var command_id := SaFilterRegistry.command_id(FIXTURE_KEY)
    assert_eq(command_id, &"filter_filter-menu-fixture_fixture_tint", "The command is the key under the page's own prefix")
    assert_true(registries.commands.has(command_id), "and it is in the command registry")
    assert_eq(registries.commands.get_descriptor(command_id).title, "Fixture Tint", "under the filter's own title")

    var opened: Array[StringName] = []
    registries.filters.invoked.connect(func(key: StringName) -> void: opened.append(key))
    assert_true(registries.commands.execute(command_id), "Running the command asks for the dialog")
    assert_eq(opened, [FIXTURE_KEY] as Array[StringName], "by naming the filter it belongs to")


func test_a_filter_whose_command_is_taken_is_refused_whole() -> void:
    var registries := _with_fixture()
    var clash := SaCommandDescriptor.create(&"filter_module-a_box_blur", "Something Else", func() -> bool: return true)
    assert_true(registries.commands.register(clash, &"someone-else"), "A command lands on the id a filter would want")
    var ctx := registries.context.for_module(&"module-a")
    assert_false(ctx.register_filter(NamedFilter.new("Box blur")), "and the filter is refused")
    assert_false(registries.filters.has(&"module-a.box_blur"), "with nothing left in the filter registry")


func test_an_unregistered_key_opens_nothing() -> void:
    var registries := _registries()
    var opened: Array[StringName] = []
    registries.filters.invoked.connect(func(key: StringName) -> void: opened.append(key))
    assert_false(registries.filters.invoke(&"nobody.at_all"), "A key nobody registered is refused")
    assert_true(opened.is_empty(), "and nothing was asked to open")


func test_unloading_the_module_takes_its_filter_and_its_command() -> void:
    var registries := _with_fixture()
    var scoped := registries.context.for_module(FIXTURE_ID)
    scoped.remove_all_registrations()
    assert_false(registries.filters.has(FIXTURE_KEY), "The filter goes with its module")
    assert_false(registries.commands.has(SaFilterRegistry.command_id(FIXTURE_KEY)), "and so does its command")


func test_the_filter_menu_lists_it_under_the_modules_name() -> void:
    var registries := _with_fixture()
    ModuleLoader.loaded_modules[FIXTURE_ID] = FIXTURE_MODULE.new()
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(SaTestFixtures.make_menu_registries().commands)
    var menu := bar.menu("Filter") as SaFilterMenu
    menu.filters = registries.filters

    var popup: SaChoicePopup = bar.menus["Filter"]
    # The filter names no section, so the menu holds one section row, Other,
    # under the browser's row, and the filter's own rows are in the list that
    # row opens, headed by the section's word. The module is on the filter
    # row's tooltip, since a section holds every module's filters. Apply Again
    # sits above the browser's row.
    var labels := popup.row_labels()
    assert_eq(labels.size(), 3, "Apply Again's row, the browser's and the one section's row")
    assert_eq(labels[0], "Apply Filter Again", "Apply Again is the first row, where Krita keeps it")
    assert_eq(labels[1], "Browse Filters...", "the browser is next, above the lists it does not replace")
    assert_eq(labels[2], "Other", "the section row is Other, which nobody had to register")
    assert_eq(popup.section_titles(), [], "and the menu carries no heading")
    var list := menu.show_section(menu.section_item(SaFilterRegistry.OTHER))
    var rows := list.row_labels()
    assert_eq(list.section_titles(), ["Other"], "The list is headed by its section's word")
    assert_eq(rows.size(), 1, "the section's own filter and nothing beside it")
    assert_eq(rows[0], "Fixture Tint", "and the row carries the filter's title")
    assert_eq(list.row_ids()[0], SaMenu.key(SaFilterMenu.ID_FILTER_BASE), "under the id the menu gave it")
    assert_eq(
        list.label_button(SaMenu.key(SaFilterMenu.ID_FILTER_BASE)).tooltip_text,
        "Added by Filter Menu Fixture.",
        "and says who put it there, by the module's name and not its id, and no chord it does not have"
    )

    # The row's own handler defers the invoke, for the reason every menu that
    # opens a window defers, and a suite that cannot pump the message queue
    # reads the map the handler defers through instead. That the invoke then
    # asks for the right dialog is the assertion two suites above.
    assert_eq(
        menu._filter_ids, {SaFilterMenu.ID_FILTER_BASE: FIXTURE_KEY}, "The row it added stands for that filter and no other"
    )
    bar.free()


func test_a_bar_with_no_registry_shows_the_menus_own_row() -> void:
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(SaTestFixtures.make_menu_registries().commands)
    var popup: SaChoicePopup = bar.menus["Filter"]
    # No filter is built in: the slider adjustments, Levels, Curves and the
    # palette belong to the base module, whose rows need a registry to be drawn.
    # So the browser's row is the whole of it, a command, which is why the bar
    # is bound to the commands, and Apply Again above it is a command as well.
    var labels := Array(popup.row_labels())
    assert_eq(
        labels,
        ["Apply Filter Again", "Browse Filters..."],
        "A bar with no filter registry shows Apply Again and the browser's row"
    )
    assert_true(popup.row_ids().has(SaMenu.key(SaFilterMenu.ID_BROWSE)), "under the menu's own id")
    assert_eq(popup.section_titles(), [], "with no heading")
    bar.free()
