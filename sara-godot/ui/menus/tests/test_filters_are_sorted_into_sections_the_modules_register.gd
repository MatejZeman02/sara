## Filters are sorted into sections the modules register: the base module the
## usual ones, a stranger's module a new one or an existing one by name, and
## Other for a filter nobody sorted. The Filter menu has a row per section that
## opens its list, and a reload drops a module's sections with its filters.
##
## Fixture modules for the door's half, so the suite reads the registration and
## not the base module's contents, and the real base module for the sections it
## registers and where each of its filters went.
extends "res://tests/test_framework.gd"

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const BoxBlur = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")
const Kaleidoscope = preload("res://modules/sara-base-modules/kaleidoscope/kaleidoscope.gd")

## Every base filter's title and the section it is listed in, the table the
## record carries.
const BASE_SECTIONS := {
    "Brightness/Contrast": &"tone",
    "Exposure": &"tone",
    "Levels": &"tone",
    "Equalize": &"tone",
    "Curves": &"tone",
    "Threshold": &"tone",
    "Posterize": &"tone",
    "Tonemap": &"tone",
    "LUT": &"color",
    "Hue/Saturation/Lightness": &"color",
    "Colour Balance": &"color",
    "Colour Lookup": &"color",
    "Gradient Map": &"color",
    "White Point": &"color",
    "Red-eye Removal": &"color",
    "Invert": &"color",
    "Desaturate": &"color",
    "Height to Normal Map": &"3d",
    "Bump Map": &"3d",
    "Gaussian Blur": &"blur",
    "Box Blur": &"blur",
    "Low Pass": &"blur",
    "Motion Blur": &"blur",
    "Lens Blur": &"blur",
    "Bloom": &"blur",
    "Sharpen": &"sharpen",
    "High Pass": &"sharpen",
    "Local Contrast": &"sharpen",
    "Wrap Offset": &"distort",
    "Wobble": &"distort",
    "Mirror": &"distort",
    "Add Noise": &"noise",
    "Drifting Noise": &"noise",
    "Denoise": &"noise",
    "Wavelet Denoise": &"noise",
    "Hot Pixels": &"noise",
    "Pixelate": &"pixelate",
    "Edge Detection": &"stylize",
    "Laplacian": &"stylize",
    "Dither": &"stylize",
    "Vignette": &"stylize",
    "Chromatic Aberration": &"distort",
    "Lens Correction": &"distort",
}


## A filter with a title and a section of the suite's choosing. Public members,
## written in `_init` alone.
class SortedFilter:
    extends SaFilter
    var entry_title: String
    var entry_section: StringName

    func _init(text: String, section_id: StringName) -> void:
        entry_title = text
        entry_section = section_id

    func title() -> String:
        return entry_title

    func family() -> StringName:
        return entry_section

    func run(_ctx: SaFilterContext) -> void:
        pass


var _bar: TopMenuBar = null


func after_each() -> void:
    if _bar != null:
        _bar.free()
    _bar = null


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    return registries


## `alpha` stands for the base module: a Blur section and a blur in it. `strange`
## is the stranger: a section of its own with a filter in it, a second filter in
## alpha's Blur, and a third naming a section nobody registered.
func _sorted() -> SaRegistries:
    var registries := _registries()
    var alpha := registries.context.for_module(&"alpha")
    assert_true(alpha.register_filter_section(&"blur", "Blur", 400), "alpha registers Blur")
    assert_true(alpha.register_filter(SortedFilter.new("Smear", &"blur")), "and a blur in it")
    var strange := registries.context.for_module(&"strange")
    assert_true(strange.register_filter_section(&"glitch", "Glitch", 450), "strange registers a section of its own")
    assert_true(strange.register_filter(SortedFilter.new("Scramble", &"glitch")), "and a filter in it")
    assert_true(strange.register_filter(SortedFilter.new("Streak", &"blur")), "and a second filter in alpha's Blur")
    assert_true(strange.register_filter(SortedFilter.new("Lost", &"nowhere")), "and one naming a section nobody registered")
    return registries


func _menu(registries: SaRegistries) -> SaFilterMenu:
    # The browser's row is a command of the shortcut table.
    SaShortcutCommands.new(Callable(), Callable(), Callable(), null).register_into(registries.commands)
    _bar = TopMenuBar.new()
    _bar._ready()
    _bar.bind_commands(registries.commands)
    var menu := _bar.menu("Filter") as SaFilterMenu
    menu.filters = registries.filters
    return menu


func _section_ids(registry: SaFilterRegistry) -> Array[StringName]:
    var ids: Array[StringName] = []
    for section: SaFilterRegistry.Section in registry.list_sections():
        ids.append(section.id)
    return ids


func test_a_module_registers_a_section_and_sorts_into_its_own_and_an_existing_one() -> void:
    var registry := _sorted().filters
    assert_eq(_section_ids(registry), [&"blur", &"glitch", &"other"] as Array[StringName], "by place, Other last")
    assert_eq(registry.section_of(&"strange.scramble"), &"glitch", "the stranger's filter is in its own section")
    assert_eq(registry.section_of(&"strange.streak"), &"blur", "and its second in the section alpha registered")
    var groups := SaFilterMenu.sections(registry)
    assert_eq(groups[0]["keys"], [&"alpha.smear", &"strange.streak"] as Array[StringName], "Blur holds both modules' blurs")
    assert_eq(groups[1]["keys"], [&"strange.scramble"] as Array[StringName], "and Glitch the stranger's filter")


func test_a_filter_naming_an_unknown_section_lands_in_other() -> void:
    var registry := _sorted().filters
    assert_eq(registry.section_of(&"strange.lost"), SaFilterRegistry.OTHER, "a section nobody registered is Other")
    var bare := SaFilterRegistry.new()
    bare.register(SortedFilter.new("Plain", &""), &"beta")
    assert_eq(bare.section_of(&"beta.plain"), SaFilterRegistry.OTHER, "and so is naming none")
    var groups := SaFilterMenu.sections(bare)
    assert_eq(groups.size(), 1, "one section")
    assert_eq(groups[0]["label"], "Other", "Other, which nobody had to register")


func test_other_is_last_whatever_place_it_asked_for() -> void:
    var registry := SaFilterRegistry.new()
    registry.register_section(SaFilterRegistry.OTHER, "Everything else", 0, &"alpha")
    registry.register_section(&"late", "Late", 5000, &"alpha")
    registry.register_section(&"early", "Early", 10, &"beta")
    registry.register_section(&"tied", "Tied", 10, &"beta")
    var labels: Array[String] = []
    for section: SaFilterRegistry.Section in registry.list_sections():
        labels.append(section.label)
    assert_eq(labels, ["Early", "Tied", "Late", "Everything else"] as Array[String], "a tie keeps registration order")


func test_a_second_registration_of_one_id_is_refused() -> void:
    var registries := _sorted()
    var intruder := registries.context.for_module(&"intruder")
    assert_false(intruder.register_filter_section(&"blur", "Smudges", 10), "a second Blur is refused")
    assert_false(
        registries.context.for_module(&"alpha").register_filter_section(&"blur", "Blur", 400), "by its own module as well"
    )
    var blur: SaFilterRegistry.Section = registries.filters.list_sections()[0]
    assert_eq([blur.label, blur.place, blur.owner_module], ["Blur", 400, &"alpha"], "and the first one stands")
    assert_eq(
        SaFilterRegistry.section_clash_line(&"intruder", &"blur", &"alpha"),
        "SaFilterRegistry.register_section: 'intruder' asked for the section 'blur', which 'alpha' already registered.",
        "the console names both, the way register_filter's clash does"
    )
    assert_false(intruder.register_filter_section(&"", "Nameless", 10), "and an empty id is refused")


func test_a_reload_drops_a_modules_sections() -> void:
    var registries := _sorted()
    var menu := _menu(registries)
    assert_true(menu.section_item(&"glitch") >= 0, "the menu has a Glitch row while strange is loaded")
    registries.context.for_module(&"strange").remove_all_registrations()
    assert_eq(_section_ids(registries.filters), [&"blur", &"other"] as Array[StringName], "its section went with it")
    assert_eq(menu.section_item(&"glitch"), -1, "and so did its row, the menu rebuilding on the registry's change")
    assert_true(registries.filters.has(&"alpha.smear"), "while alpha's filter stays")
    registries.context.for_module(&"alpha").remove_all_registrations()
    var orphan := SaFilterRegistry.new()
    orphan.register_section(&"glitch", "Glitch", 450, &"strange")
    orphan.register(SortedFilter.new("Borrowed", &"glitch"), &"beta")
    orphan.unregister_module(&"strange")
    assert_eq(orphan.section_of(&"beta.borrowed"), SaFilterRegistry.OTHER, "a filter left in a dropped section falls to Other")


func test_the_menu_has_a_row_per_section_that_opens_its_list() -> void:
    var registries := _sorted()
    var menu := _menu(registries)
    var popup: SaChoicePopup = _bar.menus["Filter"]
    assert_eq(
        Array(popup.row_labels()),
        ["Apply Filter Again", "Browse Filters...", "Blur", "Glitch", "Other"],
        "Apply Again's row, the browser's and a row per section in order, the prompt's row being Modules'"
    )
    var blur_row := menu.section_item(&"blur")
    assert_eq(blur_row, SaFilterMenu.ID_SECTION_BASE, "a section row's id is its place among the sections")
    var hints: Dictionary = {}
    for entry: Dictionary in popup.row_report():
        hints[String(entry.get("label", ""))] = String(entry.get("hint", ""))
    assert_eq(hints.get("Blur", ""), SaChoiceRow.BRANCH_MARK, "and it says it opens a list")
    var list := menu.show_section(blur_row)
    assert_eq(list.section_titles(), ["Blur"], "the list is headed by its section")
    assert_eq(Array(list.row_labels()), ["Smear", "Streak"], "both modules' blurs, and nothing beside them")
    var streak := list.label_button(list.row_ids()[1])
    assert_true(streak.tooltip_text.contains("strange"), "and a row's tooltip names its module: %s" % streak.tooltip_text)
    assert_eq(menu._filter_ids[SaMenu.id_of(list.row_ids()[1])], &"strange.streak", "the row's id is the filter's")
    assert_eq(menu.show_section(-1), null, "and an id that is no section opens nothing")


## A section row opens its list beside the menu, so its press
## leaves the menu open and asks for the list, and the list is the menu's child
## window. The windows themselves are `test_a_filter_section_opens_beside_the_filter_menu.gd`.
func test_a_section_row_asks_for_its_list_and_leaves_the_menu_open() -> void:
    var registries := _sorted()
    var menu := _menu(registries)
    var popup: SaChoicePopup = _bar.menus["Filter"]
    var blur := SaMenu.key(menu.section_item(&"blur"))
    assert_true(popup.is_branch(blur), "a section row opens a list")
    assert_false(popup.is_branch(SaMenu.key(SaFilterMenu.ID_BROWSE)), "and the browser's row does not")
    var asked: Array[StringName] = []
    popup.branched.connect(func(row_id: StringName) -> void: asked.append(row_id))
    var chose: Array[StringName] = []
    popup.chosen.connect(func(row_id: StringName) -> void: chose.append(row_id))
    assert_true(popup.press_row(blur), "the row takes a press")
    assert_eq(asked, [blur] as Array[StringName], "which asks for its list")
    assert_eq(chose, [] as Array[StringName], "and chooses nothing, so the menu is not closed by it")
    var list := menu.show_section(menu.section_item(&"blur"))
    assert_eq(list.get_parent(), popup, "the list is the menu's child window")
    assert_eq(popup.child_list, list, "and the menu knows its child")
    assert_eq(popup.child_row, blur, "and the row it hangs from")


## Where a child list opens against its parent: right of it at the row's top,
## on the left when the right has no room, and moved up off the foot.
func test_a_child_list_opens_beside_its_row() -> void:
    var room := Rect2i(0, 0, 1920, 1080)
    var parent := Rect2(100.0, 40.0, 240.0, 300.0)
    var row := Rect2(106.0, 120.0, 228.0, 24.0)
    assert_eq(
        SaPopupRect.beside(parent, row, Vector2i(200, 150), room),
        Rect2i(340, 120, 200, 150),
        "right of the menu, level with the row"
    )
    var far := Rect2(1700.0, 40.0, 200.0, 300.0)
    var at := SaPopupRect.beside(far, Rect2(1706.0, 120.0, 188.0, 24.0), Vector2i(200, 150), room)
    assert_eq(at.position.x, 1500, "no room on the right, so it opens on the left")
    var low := SaPopupRect.beside(parent, Rect2(106.0, 1000.0, 228.0, 24.0), Vector2i(200, 300), room)
    assert_eq(low.end.y, 1080, "and near the foot it is moved up to end on it")
    assert_eq(
        SaPopupRect.beside(parent, row, Vector2i(200, 150), Rect2i()),
        Rect2i(340, 120, 200, 150),
        "with no room known it opens as asked"
    )


func test_the_box_blur_goes_to_blur_and_the_kaleidoscope_to_distort() -> void:
    assert_eq(BoxBlur.new().family(), &"blur", "the box blur sits beside the base module's blurs")
    assert_eq(Kaleidoscope.new().family(), &"distort", "and the kaleidoscope in Distort")


func test_the_base_module_registers_the_sections_and_sorts_every_filter() -> void:
    var registries := _registries()
    var base := BaseModule.new()
    base.register(registries.context.for_module(base.get_id()))
    var labels: Array[String] = []
    for section: SaFilterRegistry.Section in registries.filters.list_sections():
        labels.append(section.label)
    assert_eq(
        labels,
        ["Tone", "Colour", "3D", "Blur", "Sharpen", "Distort", "Noise", "Pixelate", "Stylize", "Other"] as Array[String],
        "the list with the two adjustments first and Sharpen beside Blur"
    )
    var seen: Dictionary = {}
    for key: StringName in registries.filters.list_keys():
        var title := registries.filters.get_filter(key).title()
        seen[title] = registries.filters.section_of(key)
    assert_eq(seen, BASE_SECTIONS, "every base filter is where the record says")
    registries.context.for_module(base.get_id()).remove_all_registrations()
    assert_eq(_section_ids(registries.filters), [&"other"] as Array[StringName], "and unloading it leaves Other alone")
