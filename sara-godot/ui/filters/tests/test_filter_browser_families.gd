## The filter browser groups its list the way the Filter menu does, by the
## sections modules register, and a section's id and word join the search.
##
## On a detached Filters docker, for the reason `ui/filters/tests/test_filter_browser.gd`
## opens with.
extends "res://tests/test_framework.gd"


## A filter with a title and a family of the suite's choosing.
class FamilyFilter:
    extends SaFilter
    var entry_title: String
    var entry_family: StringName

    func _init(text: String, word: StringName) -> void:
        entry_title = text
        entry_family = word

    func title() -> String:
        return entry_title

    func family() -> StringName:
        return entry_family

    func run(_ctx: SaFilterContext) -> void:
        pass


var _docker: FiltersDocker = null


func after_each() -> void:
    if _docker != null:
        _docker.free()
    _docker = null


## A blur and two tone filters on `alpha`, the blur first, one filter with no
## section on `beta`, and a colour filter, in sections `alpha` registers with the
## blur's placed after tone's.
func _build() -> FiltersDocker:
    var filters := SaFilterRegistry.new()
    filters.register_section(&"tone", "Tone", 100, &"alpha")
    filters.register_section(&"color", "Colour", 150, &"alpha")
    filters.register_section(&"blur", "Blur", 200, &"alpha")
    filters.register(FamilyFilter.new("Smear", &"blur"), &"alpha")
    filters.register(FamilyFilter.new("Lift", &"tone"), &"alpha")
    filters.register(FamilyFilter.new("Press", &"tone"), &"alpha")
    filters.register(FamilyFilter.new("Plain", &""), &"beta")
    filters.register(FamilyFilter.new("Tint", &"color"), &"beta")
    _docker = FiltersDocker.new()
    _docker.browser.watch(filters, SaCommandRegistry.new())
    return _docker


func test_the_list_is_grouped_by_section() -> void:
    var docker := _build()
    var texts: Array = []
    for child in docker.browser._list.get_children():
        texts.append((child as Label).text if child is Label else (child as Button).text)
    assert_eq(
        texts,
        ["Tone", "Lift", "Press", "Colour", "Tint", "Blur", "Smear", "Other", "Plain"],
        "the sections by place and Other last, each over its filters from every module"
    )
    assert_eq(docker.describe()["headings"], ["Tone", "Colour", "Blur", "Other"], "and the dump says so")


func test_the_section_id_joins_the_search() -> void:
    var docker := _build()
    docker.browser.search_for("blur")
    assert_eq(docker.describe()["listed"], ["alpha.smear"], "no title says blur, and the section found it")
    assert_eq(docker.describe()["headings"], ["Blur"], "under its heading alone")


func test_the_sections_word_is_searched_as_well_as_its_id() -> void:
    var docker := _build()
    docker.browser.search_for("colou")
    assert_eq(docker.describe()["listed"], ["beta.tint"], "the id is color, so the word Colour found it")
