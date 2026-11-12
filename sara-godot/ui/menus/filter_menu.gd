## The Filter menu: one row per filter section, each opening a list of that section's filters from every
## module, under the row that opens the browser. The sections are what modules register through
## `SaContext.register_filter_section`, the base module the usual ones, and a filter that names none sits in
## Other. The skeleton brings no filter and no section of its own, so with no module loaded the menu holds
## Apply Again, disabled, and the browser's door, and nothing under them.
##
## **No row here is about writing a filter.** Copy the kernel prompt is in the Develop section of the Modules
## menu with the other rows for someone writing a module, and its prompt file and capture step are
## `SaModulesMenu`'s, because a painter reads past a developer's row under the filters every time.
##
## Deferred out of the popup's own signal handler, for the reason the Edit
## menu gives: a window that takes focus from inside that re-entrancy
## desynchronises the engine's popup focus bookkeeping.
##
## The registered half is the filter registry's. Picking one asks the registry
## to invoke it, and whatever owns the dialog answers `invoked`, so this file
## knows about no window at all.
class_name SaFilterMenu
extends SaMenu

## The row that runs the filter applied last again, the menu's first, where
## Krita keeps its Apply Filter Again.
const ID_APPLY_AGAIN := 408

## The row the browser opens from, a window where a painter can choose among
## all the filters. Above the filters rather than below them, because the top
## of the menu is where they look for one. The lists below it are untouched.
const ID_BROWSE := 407

## Registered filters count upwards from here, far enough above the browser's
## row that its id can never reach this far. 405 was the kernel prompt's row and
## is not used again, because an id is a row of the menu it was minted in.
const ID_FILTER_BASE := 450

## The section rows count upwards from here, by the section's place among every
## registered one, far enough above the filters' block that a module would have
## to register more than fifteen hundred filters to reach it.
const ID_SECTION_BASE := 4000

## What [method rank] answers, weakest first, so a higher number is listed
## higher.
const RANK_NONE := 0
const RANK_SAID := 1
const RANK_TITLE := 2
const RANK_STARTS := 3

## The seventh registry, once something binds it. Null on a detached bar, which
## is what `ui/menus/tests/test_menus.gd` builds and why the browser's row is the
## whole menu there.
var filters: SaFilterRegistry = null:
    set(value):
        if filters != null and filters.changed.is_connected(populate):
            filters.changed.disconnect(populate)
        filters = value
        if value != null and not value.changed.is_connected(populate):
            value.changed.connect(populate)
        populate()

## Item id -> filter key, rebuilt with the menu, because a module unloading
## takes its rows with it.
var _filter_ids: Dictionary = {}
## Section row id -> the section as [method sections] answers it, and -> its
## rows as `[filter item id, filter key]` pairs.
var _section_ids: Dictionary = {}
var _section_rows: Dictionary = {}

## The list a section row opens beside the menu, one for the menu and filled
## again on every open. Read by the suites and the harness, which press its rows.
var section_list: SectionList = null


## A section's filters as a list of their own. A menu of its own because it is
## one: rows with chords, tooltips and dims, a press that closes
## it and an id that says what was pressed. Its presses go back to the Filter
## menu's handler, which owns what a filter id means. Its popup is the Filter
## menu's child list, so it opens beside the section's row with the menu still
## open, and a filter picked from it closes both.
class SectionList:
    extends SaMenu

    var registry: SaFilterRegistry = null
    ## The heading over the rows, the section's word.
    var title: String = ""
    ## `[filter item id, filter key]` pairs, in the order the rows are drawn.
    var rows: Array = []
    var _press_back: Callable

    func _init(list_popup: SaChoicePopup, pressed: Callable) -> void:
        super(list_popup)
        _press_back = pressed

    func _add_items() -> void:
        if registry == null:
            return
        add_heading(title)
        for row: Array in rows:
            var filter_key: StringName = row[1]
            var filter := registry.get_filter(filter_key)
            if filter != null:
                SaFilterMenu.add_filter_row(self, row[0], filter_key, filter, registry.owner_of(filter_key))

    func _pressed(id: int) -> void:
        _press_back.call(id)

    ## A filter row's command, the one its chord runs, so a right click on it
    ## can keep it or bind it.
    func row_command(row_id: StringName) -> StringName:
        var item_id := id_of(row_id)
        for row: Array in rows:
            if row[0] == item_id and registry != null and registry.has(row[1]):
                return SaFilterRegistry.command_for(row[1], registry.get_filter(row[1]))
        return super(row_id)


## Builds the section list as a child window of the menu's own popup, so the
## menu frees it with itself and the engine keeps the menu open while the list
## holds the keyboard, which a sibling under the bar could not have.
func _init(menu_popup: SaChoicePopup) -> void:
    super(menu_popup)
    var list := SaChoicePopup.new(true, false)
    list.name = "FilterSectionList"
    section_list = SectionList.new(list, on_id_pressed)
    if menu_popup != null:
        menu_popup.add_child(list)


## A list nobody holds is this menu's to free, since no tree will.
func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE and section_list != null:
        var list := section_list.popup
        if is_instance_valid(list) and list.get_parent() == null:
            list.free()


## Filled again every time the menu is about to open, which is what lets a
## student fix their kernel and find the row live without restarting.
##
## `problem()` is what recompiles, so the menu asks nothing about kernels and
## learns nothing about them. Connected here rather than in `_init` because the
## popup is handed over before the bar has it in the tree, and `populate` is the
## one call every path makes. The bar rebuilds a menu before it opens one, so
## this needs no connection to `about_to_popup` of its own. The override is kept
## because the doc paragraph above it
## is the reason this menu in particular cannot be built once, and a reader
## looking for it should find it on the menu rather than in the bar.
##
## The popup's `branched` is connected here for the same reason: a section row's
## press, a pointer resting on it or the right arrow asks for its list without
## closing the menu, and `SaMenu` hears only the presses that close it.
func populate() -> void:
    super()
    if popup != null and not popup.branched.is_connected(_on_section_asked):
        popup.branched.connect(_on_section_asked)
    if popup != null and not popup.searching.is_connected(_on_searching):
        popup.searching.connect(_on_searching)


## A section row asked for its list, which is the section's id pressed.
func _on_section_asked(row_id: StringName) -> void:
    on_id_pressed(id_of(row_id))


func _add_items() -> void:
    _add_again_row()
    _add_browse_row()
    _add_registered_filters()


## The row that runs the filter applied last again, the `SaFilterAgain`
## command, named after that filter once there is one: Apply Gaussian Blur
## Again. Before any filter has been applied it reads Apply Filter Again and is
## disabled, by its command, so neither a press nor a step can take it. A bar
## with no registry behind it has applied nothing.
func _add_again_row() -> void:
    var registry := _resolve_registry()
    var label := ""
    if SaFilterAgain.remembered(registry):
        label = tr("Apply %s Again") % tr(SaFilterAgain.last_title(registry))
        # A shipped filter's row is a whole sentence, so a language with cases
        # can decline its name. A module's own filter reads the generic one.
        if SaWholeSentences.FILTER_AGAIN.has(SaFilterAgain.last_title(registry)):
            label = tr(SaWholeSentences.FILTER_AGAIN[SaFilterAgain.last_title(registry)])
    add_command(ID_APPLY_AGAIN, SaFilterAgain.COMMAND, label)


## The row that opens the browser.
##
## The row is the `filter_browse` command, whose handler reaches the window
## directly rather than through a signal: one window serves the whole app, it is
## installed at boot beside the filter dialog, and with no tree behind it the
## handler finds nothing and does nothing.
func _add_browse_row() -> void:
    add_command(ID_BROWSE, &"filter_browse")


## One row per section that holds a filter, each opening that section's list,
## and a gap over the first so the browser's row reads as a door rather than as
## one more filter. With no section there is no gap, since a line under the last
## row divides nothing.
##
## Every filter gets its item id here, in section order, whether or not its
## list is open, so a scenario's `menu_item` step and a suite reach a filter by
## number on this menu the way they always have, and the section list's rows
## carry the same numbers back to [method on_id_pressed].
func _add_registered_filters() -> void:
    _filter_ids.clear()
    _section_ids.clear()
    _section_rows.clear()
    var registry := _resolve_registry()
    if registry == null:
        return
    var next_id := ID_FILTER_BASE
    for section: Dictionary in sections(registry):
        var item_id := ID_SECTION_BASE + int(section["place"])
        var rows: Array = []
        for filter_key: StringName in section["keys"]:
            rows.append([next_id, filter_key])
            _filter_ids[next_id] = filter_key
            next_id += 1
        _section_ids[item_id] = section
        _section_rows[item_id] = rows
        if _section_ids.size() == 1 and item_count() > 0:
            add_separator()
        popup.add_branch_row(key(item_id), tr(section["label"]))
        if SaWholeSentences.FILTER_SECTION.has(section["label"]):
            set_item_tooltip(item_id, tr(SaWholeSentences.FILTER_SECTION[section["label"]]))
        else:
            set_item_tooltip(item_id, tr("The %s filters of every module.") % tr(section["label"]))


## The registry's filters as the sections the menu and the browser draw, each
## `{"section": id, "label": word, "place": index, "keys": Array[StringName]}`.
##
## Sections in the registry's order, Other last, and only those holding a
## filter, since a heading or a row that opens nothing tells a painter nothing.
## *place* is the section's index among all registered sections, empty ones
## included, so a section's item id does not move when another fills up. Keys
## keep their registration order, whichever module registered them. One
## function, because a second copy of the menu's grouping is the one that
## drifts.
static func sections(registry: SaFilterRegistry) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    if registry == null:
        return out
    var by_section: Dictionary = {}
    for filter_key: StringName in registry.list_keys():
        var section_id := registry.section_of(filter_key)
        if not by_section.has(section_id):
            var keys: Array[StringName] = []
            by_section[section_id] = keys
        by_section[section_id].append(filter_key)
    var place := 0
    for section: SaFilterRegistry.Section in registry.list_sections():
        if by_section.has(section.id):
            out.append({"section": section.id, "label": section.label, "place": place, "keys": by_section[section.id]})
        place += 1
    return out


## The filters the search's *needle* finds, added under their section's word
## as rows of this menu, so a search reaches the filters themselves and not only
## the first level of sections, in the order `SaFilterBrowser.order`
## gives the browser's search, a title beginning with the word first.
##
## Each row carries the filter's own item id, the one its row in the section
## list carries, so a press or Enter reaches [method on_id_pressed] and runs
## what the section list's row runs, and it is drawn by
## [method add_filter_row], so it is dimmed where that row is. The popup adds
## them as found rows, shown while the field holds text and taken away as it
## changes, so an emptied field gives the menu back as it was. A section row
## the needle matches stays, since the field still matches rows by their words.
func _on_searching(needle: String) -> void:
    var folded := needle.to_lower()
    var registry := _resolve_registry()
    if folded.is_empty() or registry == null:
        return
    var found: Array[Dictionary] = []
    for item_id: int in _section_ids:
        var section: Dictionary = _section_ids[item_id]
        var words := SaFilterBrowser.section_words(section)
        var rows: Array = []
        var ranks: Array = []
        for row: Array in _section_rows[item_id]:
            var filter := registry.get_filter(row[1])
            var ranked := rank(filter, folded, words, sentence_of(row[1], filter, commands)) if filter != null else RANK_NONE
            if ranked > RANK_NONE:
                rows.append(row)
                ranks.append(ranked)
        found.append({"label": section["label"], "rows": rows, "ranks": ranks})
    for section: Dictionary in SaFilterBrowser.order(found):
        add_heading(tr(section["label"]))
        for row: Array in section["rows"]:
            add_filter_row(self, row[0], row[1], registry.get_filter(row[1]), registry.owner_of(row[1]))


## Whether *filter* answers the search word *needle*, lower case and already
## stripped: in its title, its translated title, its section's *words* or its
## *sentence*. The one rule the Filter menu's search and the browser's both
## find a filter by, so the two doors find the same filters.
static func finds(filter: SaFilter, needle: String, words: String, sentence: String) -> bool:
    return rank(filter, needle, words, sentence) > RANK_NONE


## How well *filter* answers *needle*, by the words `finds` reads: a title that
## begins with the word, [constant RANK_STARTS], above one that holds it,
## [constant RANK_TITLE], above a filter that holds it only in its section's
## *words* or its *sentence*, [constant RANK_SAID], and [constant RANK_NONE]
## when nothing does. An empty word ranks every filter alike. The title is the
## English one or the translated one, whichever ranks higher.
##
## The one order both searches list by. "levels" found Equalize by its sentence,
## which ends "Opens in Levels", and listed it above Levels in Tone, so the
## first row the painter took added Equalize.
static func rank(filter: SaFilter, needle: String, words: String, sentence: String) -> int:
    if needle.is_empty():
        return RANK_STARTS
    var best := RANK_NONE
    for title: String in [filter.title().to_lower(), filter.translated_title().to_lower()]:
        if title.begins_with(needle):
            return RANK_STARTS
        if title.contains(needle):
            best = RANK_TITLE
    if best == RANK_NONE and (words.contains(needle) or sentence.to_lower().contains(needle)):
        best = RANK_SAID
    return best


## The sentence *filter* says, or its command's when it says none, which is
## what its row's tooltip and the browser's detail column show.
static func sentence_of(filter_key: StringName, filter: SaFilter, from_commands: SaCommandRegistry) -> String:
    var said := filter.sentence()
    if not said.is_empty() or from_commands == null:
        return said
    var descriptor := from_commands.get_descriptor(SaFilterRegistry.command_for(filter_key, filter))
    return descriptor.sentence if descriptor != null else ""


## The item id of *section_id*'s row, or -1 when the menu shows no such row.
func section_item(section_id: StringName) -> int:
    for item_id: int in _section_ids:
        if _section_ids[item_id]["section"] == section_id:
            return item_id
    return -1


## Fills *item_id*'s section list and opens it beside the section's row, and
## answers the list, which a suite reads without a tree.
##
## **Beside the menu, which stays open**, one submenu per section rather than a
## list in place of the menu. The list is the menu popup's child window, placed
## and scaled by `SaChoicePopup.open_child`.
## A menu that is closed has no row to open beside, so the list is filled and
## left shut.
func show_section(item_id: int) -> SaChoicePopup:
    if not _section_ids.has(item_id):
        return null
    section_list.registry = _resolve_registry()
    section_list.commands = commands
    section_list.title = tr(_section_ids[item_id]["label"])
    section_list.rows = _section_rows[item_id]
    section_list.populate()
    var list := section_list.popup
    popup.open_child(list, key(item_id))
    return list


## A filter's command for a filter row, which the press runs through the
## registry rather than the command, so Repeat Last keeps it.
func row_command(row_id: StringName) -> StringName:
    var registry := _resolve_registry()
    var filter_key: StringName = _filter_ids.get(id_of(row_id), &"")
    if registry == null or not registry.has(filter_key):
        return super(row_id)
    return SaFilterRegistry.command_for(filter_key, registry.get_filter(filter_key))


## The registry, from whatever bound it or from the main scene that owns it.
##
## Reached through the tree the way `main_canvas()` and `main_document()` are,
## rather than bound by main: main builds the registries before any UI, and the
## menu is populated again once the command registry arrives, so the walk has
## always found them by the time a painter can open the menu. A detached bar
## finds nothing and shows the browser's row alone.
##
## **Nothing is assigned to `filters` here.** Writing it would call the setter,
## whose `populate()` would fill the popup from inside the walk that is filling
## it, and every registered row would be added twice. The subscription is made
## instead, which is the only part that has to survive the call.
func _resolve_registry() -> SaFilterRegistry:
    if filters != null:
        return filters
    var main_node := main_scene()
    if main_node == null:
        return null
    var registries := main_node.get("registries") as SaRegistries
    if registries == null:
        return null
    var registry := registries.filters
    if registry != null and not registry.changed.is_connected(populate):
        registry.changed.connect(populate)
    return registry


func _pressed(id: int) -> void:
    if _section_ids.has(id):
        # Deferred for the reason at the top of the file: the list takes focus.
        show_section.call_deferred(id)
        return
    if _filter_ids.has(id):
        var registry := _resolve_registry()
        if registry != null:
            # Deferred for the reason at the top of the file: the dialog the
            # host opens takes focus, and it must not do that from inside the
            # popup's own signal handler.
            registry.invoke.call_deferred(_filter_ids[id])
        return


## One filter's row on *menu*, the section list's or this menu's own while its
## search holds text, with its tooltip and whether it can be picked at all. One
## function for both, so a filter dimmed in its section is dimmed in the search.
##
## The filter's own sentence when its module wrote one, which
## `SaContext.register_filter` puts on its command, so the row says what the
## browser's detail column says from the same string, and then the module
## that registered it, because a section mixes every module's filters and
## "which module added this" is the first question asked of a row nobody
## expected. Nothing here is invented about what the filter does, which only
## its module knows.
##
## A filter that wrote no sentence says only who added it. A chord beside
## the row needs no sentence to say it opens the same dialog, as no other
## menu row's does.
##
## A filter that answers [method SaFilter.problem] is dimmed and says why. A
## dimmed control is a disabled one, so the row is both: picking it would open a dialog over a kernel that cannot run. The
## message is the compiler's own, already located back to the student's file
## and line, and is not translated for the same reason no compiler message
## is. `SaChoicePopup` refuses a press on a disabled row from a scenario as
## well as from a pointer.
static func add_filter_row(menu: SaMenu, item_id: int, filter_key: StringName, filter: SaFilter, module_id: StringName) -> void:
    var command_id := SaFilterRegistry.command_for(filter_key, filter)
    var problem := filter.problem()
    var chord := menu.chord_of(command_id)
    menu.add_item(filter.translated_title(), item_id, not problem.is_empty(), chord)
    if not problem.is_empty():
        menu.set_item_tooltip(item_id, problem.split("\n")[0].strip_edges())
        return
    var said := ""
    if menu.commands != null:
        var descriptor := menu.commands.get_descriptor(command_id)
        said = descriptor.sentence if descriptor != null else ""
    var registered := menu.tr("Added by %s.") % menu.module_display_name(module_id, menu.tr("Filters"))
    if not said.is_empty():
        menu.set_item_tooltip(item_id, "%s\n%s" % [said, registered])
    else:
        menu.set_item_tooltip(item_id, registered)
