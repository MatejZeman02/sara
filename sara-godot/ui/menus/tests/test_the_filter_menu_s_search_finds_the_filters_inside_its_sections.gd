## The Filter menu's search finds the filters inside its sections, not only the
## section headings.
##
## The real base module's filters, so "gauss" is read against the Gaussian Blur
## a painter has, and one fixture filter in Blur that cannot run, for the dim.
## The bar stands detached, as `test_filters_are_sorted_into_sections_the_modules_register.gd`
## stands it: the search narrows a column, which needs no window, and the
## scenario `scenarios/the-filter-menu-s-search-finds-the-filters-inside-its-sections.json`
## types into the running app's open menu.
extends "res://tests/test_framework.gd"

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")


## A Blur filter whose kernel did not compile, which its section list dims.
class BrokenFilter:
    extends SaFilter

    func title() -> String:
        return "Broken Smear"

    func family() -> StringName:
        return &"blur"

    func problem() -> String:
        return "broken_smear.gmacs:3: unexpected token\nmore"

    func run(_ctx: SaFilterContext) -> void:
        pass


var _bar: TopMenuBar = null


func after_each() -> void:
    if _bar != null:
        _bar.free()
    _bar = null
    SaQuickCommands.last_run = &""


func _menu() -> SaFilterMenu:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    SaShortcutCommands.new(Callable(), Callable(), Callable(), null).register_into(registries.commands)
    var base := BaseModule.new()
    base.register(registries.context.for_module(base.get_id()))
    registries.context.for_module(&"fixture").register_filter(BrokenFilter.new())
    _bar = TopMenuBar.new()
    _bar._ready()
    _bar.bind_commands(registries.commands)
    var menu := _bar.menu("Filter") as SaFilterMenu
    menu.filters = registries.filters
    return menu


## The row the search shows labelled *label*, or an empty id.
func _shown(popup: SaChoicePopup, label: String) -> StringName:
    for row_id: StringName in popup.row_ids():
        if popup.is_row_shown(row_id) and popup.label_button(row_id).text == label:
            return row_id
    return &""


## The row of *label* in *section*'s list, the list a section row opens.
func _in_section(menu: SaFilterMenu, section: StringName, label: String) -> StringName:
    menu.show_section(menu.section_item(section))
    var list := menu.section_list.popup
    for row_id: StringName in list.row_ids():
        if list.label_button(row_id).text == label:
            return row_id
    return &""


func test_gauss_shows_the_gaussian_blur_and_its_press_runs_what_the_section_row_runs() -> void:
    var menu := _menu()
    var popup := menu.popup
    assert_eq(_shown(popup, "Gaussian Blur"), &"", "the menu's own rows are sections before a search")
    assert_true(popup.filter("gauss") > 0, "gauss finds something")
    var found := _shown(popup, "Gaussian Blur")
    assert_false(found.is_empty(), "the Gaussian Blur filter's row is shown in the menu")
    assert_true(popup.section_titles().has("Blur"), "under its section's name")
    assert_eq(popup.highlighted(), found, "and Enter would pick it, the first row left")
    assert_true(popup.press_row(found), "the row takes a press")
    var from_search := SaQuickCommands.last_run
    SaQuickCommands.last_run = &""
    var listed := _in_section(menu, &"blur", "Gaussian Blur")
    assert_eq(found, listed, "the row carries the id its row in the Blur list carries")
    assert_true(menu.section_list.popup.press_row(listed), "the Blur list's row takes a press")
    assert_false(from_search.is_empty(), "the search's row ran a command")
    assert_eq(from_search, SaQuickCommands.last_run, "the one its row in the Blur section list runs")
    assert_eq(menu.row_command(found), menu.section_list.row_command(listed), "and the same command is its row's")


func test_a_sentence_word_blur_and_an_emptied_search() -> void:
    var menu := _menu()
    var popup := menu.popup
    var before := popup.row_labels()
    var titles_before := popup.section_titles()
    assert_false("Gaussian Blur".to_lower().contains("bell-shaped"), "the word is in the sentence only")
    popup.filter("bell-shaped")
    assert_false(_shown(popup, "Gaussian Blur").is_empty(), "a word of the sentence finds the filter")
    popup.filter("blur")
    assert_false(_shown(popup, "Blur").is_empty(), "blur keeps the Blur section's row")
    for label: String in ["Gaussian Blur", "Motion Blur", "Lens Blur", "Low Pass", "Bloom"]:
        assert_false(_shown(popup, label).is_empty(), "and shows the section's %s" % label)
    popup.filter("")
    assert_eq(popup.row_labels(), before, "an emptied search gives the menu's rows back")
    assert_eq(popup.section_titles(), titles_before, "and its headings")
    for row_id: StringName in popup.row_ids():
        assert_true(popup.is_row_shown(row_id), "every row shown again: %s" % row_id)


func test_a_dimmed_filter_is_dimmed_in_the_search() -> void:
    var menu := _menu()
    var listed := _in_section(menu, &"blur", "Broken Smear")
    assert_true(menu.section_list.popup.is_disabled(listed), "the section list dims the broken filter")
    menu.popup.filter("smear")
    var found := _shown(menu.popup, "Broken Smear")
    assert_false(found.is_empty(), "the search shows it")
    assert_true(menu.popup.is_disabled(found), "dimmed as its section row is")
    assert_false(menu.popup.press_row(found), "and refusing a press")
