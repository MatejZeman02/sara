## What the search lists and what a pick of each row does, walked from the
## sources the search is handed: every registry the context holds that answers
## `search_rows`, every one a module announced through the door, the presets and
## the menus' own rows (`SaSearchActions`), and the settings Preferences' own
## search lands on. No registry is read here by name, so a module's tool,
## docker, filter, command, kind of layer or registry of its own is found with no
## call to the search. The contract is `SaSearchRegistry.Row`'s.
##
## **One list, each thing once.** A row covering a command is listed in its
## place, so a filter's command is shown as the filter, a docker's toggle as the
## docker and a tool's chord as the tool. A command's own row is left out when
## another row covers it.
##
## **What the walk adds to a row.** A row standing for a command no registry
## holds any more stands for nothing, so its offer is dimmed, and one standing
## for a registered command is dimmed while the command is. A row with no pick
## of its own runs its command, as its menu row would, and keeps it for Repeat
## Last. A row with no place is a command's, looked for on the bar's menus by
## the rows each `SaMenu` drew, and a command no menu draws lives on the
## Keyboard Shortcuts page, under the group its id files in.
##
## **The settings are never read on an opening.** Building the catalogue makes
## every Preferences page off the tree, far too long for an opening to wait
## on. [method warm_page] builds it a page at a time
## out of sight, the window driving it once the main scene has gone idle and
## again when the pages change, and [method entries] lists what the last
## complete build holds.
class_name SaSearchIndex
extends RefCounted

## What each kind says it is on its row, and the order the empty search lists
## them in.
const SETTING := "Setting"
const TOOL := SaSearchRegistry.TOOL
const DOCKER := SaSearchRegistry.DOCKER
const FILTER := SaSearchRegistry.FILTER
const COMMAND := SaSearchRegistry.COMMAND

## The page a command no menu draws is found on, before its group.
const SHORTCUTS_PAGE := "Keyboard Shortcuts"

## The Preferences page whose chord rows repeat the command rows.
const KEYBOARD_PAGE := "Keyboard shortcuts"


## One row of the list. Written by its constructor alone, and *enabled* is what
## the registries said when the window opened.
class Entry:
    extends RefCounted
    var kind: String
    var title: String
    var place: String
    var chord: String
    var enabled: bool
    ## The command the row stands for, which the right press and the Menu key
    ## offer to keep and to bind, or `&""` for a row no command stands behind: a
    ## tool, a setting, a preset, a kind of layer and a menu's own row.
    var command: StringName
    ## What the row is found by: the title, the kind, the place and what else the
    ## row's owner says of it, its menu label and its sentence, folded by `SaSettingsSearch.fold`.
    var words: String
    var pick: Callable
    ## What the row's owner said of it, and the command whose own state dims
    ## it on top of that, or null, both read again by [method recheck].
    var _live: bool
    var _descriptor: SaCommandDescriptor

    func _init(
        what: String,
        named: String,
        found_in: String,
        keys: String,
        sentence: String,
        live: bool,
        act: Callable,
        command_id: StringName = &"",
        descriptor: SaCommandDescriptor = null
    ) -> void:
        kind = what
        command = command_id
        title = named
        place = found_in
        chord = keys
        _live = live
        _descriptor = descriptor
        enabled = live and (descriptor == null or descriptor.is_enabled())
        words = SaSettingsSearch.fold(" ".join([named, what, found_in, sentence]).strip_edges())
        pick = act

    ## Asks the command again whether it runs now, which an undo that came to
    ## have something to undo changes with no registry saying so, and answers
    ## whether the row's dimming changed.
    func recheck() -> bool:
        var was := enabled
        enabled = _live and (_descriptor == null or _descriptor.is_enabled())
        return enabled != was


## The context the commands are run and their chords read through, and what
## the walk is handed: the context's own sources when *_sources* is empty, and
## *_sources* alone otherwise, which a suite hands to read one registry's rows.
var context: SaContext = null
var _sources: Array = []

## Every place Preferences' own search lands on, built once off the tree and kept
## with the page titles it was built for, which a module that brings a page or
## takes it away changes.
##
## *_settings_pages* is empty until a build completes, and a build under way
## keeps its rows in *_building*, the pages it has still to make in *_pending*
## and the never shown window it makes them with in *_maker*, for the titles in
## *_building_for*.
var _settings: Array[Entry] = []
var _settings_pages: Array = []
var _building: Array[Entry] = []
var _pending: Array = []
var _maker: SaSettingsWindow = null
var _building_for: Array = []

## How many times the rows were walked, which a suite counts, and a number that
## moves whenever what [method entries] answers changes, its rows or a row's
## dimming, which the window keeps its drawn rows by.
var builds: int = 0
var version: int = 0

## The rows of the last walk, kept until something they were read from says it
## changed, and what the menus and the presets held then.
var _kept: Array[Entry] = []
var _stale: bool = true
var _held: Array = []


func _init(ctx: SaContext, sources: Array = []) -> void:
    context = ctx
    _sources = sources
    # A rebind and a module's arrival are said on the bus rather than by a
    # registry of the context.
    EventBus.shortcuts_changed.connect(_go_stale)
    EventBus.module_loaded.connect(_go_stale.unbind(1))


## Every row, in the order its sources are walked: the context's registries in
## the order it declares them and the ones modules announced, then
## `SaSearchActions`' presets and menu rows, then the settings of the last
## complete build. *menus* is the bar's menu objects by title, which say where a
## command lives and hold the menu rows, and may be empty. Handed sources of
## its own, the index lists theirs alone.
##
## **The walk is kept.** It took 17 ms of the 80 ms frame Search Commands
## opened on, so the rows are walked again only when something they were read
## from changed: a registry's `changed`, which a module registering a command,
## a tool, a filter, a docker or a kind of layer says, a rebind or a module
## said on the bus, a settings build that completed, a menu's rows, the presets'
## names or the language. Otherwise the kept rows answer, each asked again
## whether its command runs now, unless *all* is false: asking every row took
## 4 ms of an opening's frame on a large profile, so an opening asks the rows
## it shows through [method recheck], and a page is asked as it is drawn.
func entries(menus: Dictionary = {}, all: bool = true) -> Array[Entry]:
    if context == null:
        return [] as Array[Entry]
    var sources := _sources
    if sources.is_empty():
        sources = SaSearchRegistry.sources_of(context)
        sources.append_array(SaSearchActions.sources(context, menus))
    var held := _holding(menus)
    if _stale or held != _held:
        _kept = _walk(sources, menus)
        _held = held
        _stale = false
        builds += 1
        version += 1
        _watch(sources)
        return _kept
    if all:
        recheck(_kept)
    return _kept


## The rows as [method entries] answers them for an opening, with only
## *drawn*, the rows the list shows, asked whether their commands run now.
func shown_rows(menus: Dictionary, drawn: Array[Entry]) -> Array[Entry]:
    var rows := entries(menus, false)
    recheck(drawn)
    return rows


## Asks each of *rows* again whether its command runs now, and moves
## [member version] when one's dimming changed.
func recheck(rows: Array[Entry]) -> void:
    var changed := false
    for entry: Entry in rows:
        changed = entry.recheck() or changed
    if changed:
        version += 1


## Whether [method entries] would walk the rows again for *menus*.
func is_stale(menus: Dictionary = {}) -> bool:
    return _stale or _holding(menus) != _held


## The rows *sources* give, as [method entries] lists them.
func _walk(sources: Array, menus: Dictionary) -> Array[Entry]:
    var out: Array[Entry] = []
    var rows: Array[SaSearchRegistry.Row] = []
    for source: Object in sources:
        for row: SaSearchRegistry.Row in source.call("search_rows"):
            rows.append(row)
    var places := _menu_places(menus)
    var covered := {}
    for row: SaSearchRegistry.Row in rows:
        if not row.covers.is_empty():
            covered[row.covers] = true
    var titles := {}
    for row: SaSearchRegistry.Row in rows:
        if row.covers.is_empty() and covered.has(row.command):
            continue
        var key := SaSettingsSearch.fold(row.title)
        if row.gives_way and titles.has(key):
            continue
        titles[key] = true
        out.append(_entry_of(row, places))
    if _sources.is_empty():
        _add_settings(out)
    return out


## Every source of *sources* that says when it changed is listened to, once.
func _watch(sources: Array) -> void:
    for source: Object in sources:
        if source.has_signal(&"changed") and not source.is_connected(&"changed", _go_stale):
            source.connect(&"changed", _go_stale)


func _go_stale() -> void:
    _stale = true


## What the rows read that says nothing when it changes: every menu row's id,
## label and dimming, which a recent file or a toggle's state changes, the
## presets' names and the language the titles are in.
func _holding(menus: Dictionary) -> Array:
    var out: Array = [TranslationServer.get_locale()]
    for title: String in menus:
        var menu := menus[title] as SaMenu
        if menu == null or menu.popup == null:
            continue
        for popup: SaChoicePopup in SaMenu.lists_of(menu.popup):
            for row_id: StringName in popup.row_ids():
                var button := popup.label_button(row_id)
                out.append([row_id, button.text if button != null else "", popup.is_disabled(row_id)])
    var tree := Engine.get_main_loop() as SceneTree
    var group := ToolOptionsPresets.in_tree(tree.root) if tree != null else null
    if group != null:
        out.append(group.preset_store.list_names())
        out.append(SaSettings.preset_bundles_off)
    return out


## *row* as the list shows it, with what the walk adds to every row.
func _entry_of(row: SaSearchRegistry.Row, places: Dictionary) -> Entry:
    var descriptor := _descriptor(row.command)
    var command := row.command if descriptor != null else &""
    var live := row.enabled
    var act := row.pick
    if act.is_null():
        live = live and descriptor != null
        act = _run.bind(command) if descriptor != null else Callable()
    var place := row.place
    if place.is_empty() and descriptor != null:
        place = String(places.get(command, _page_place(command)))
    var keys := _command_chord(row.chord) if not row.chord.is_empty() else ""
    return Entry.new(row.kind, row.title, place, keys, row.sentence, live, act, command, descriptor)


## The rows *query* finds, in the order they rank. Each word of the query has
## to start a word of the row, the rule `SaSettingsSearch.matches` keeps for
## Preferences. A row whose title starts with the query comes first, then one
## with a word of its title starting so, then the rest, and rows that rank
## alike keep the list's order. An empty query finds every row.
static func narrowed(rows: Array[Entry], query: String) -> Array[Entry]:
    var needle := SaSettingsSearch.fold(query.strip_edges())
    if needle.is_empty():
        return rows.duplicate()
    var parts := needle.split(" ", false)
    var ranked: Array = [[], [], []]
    for entry: Entry in rows:
        var found := true
        for part: String in parts:
            found = found and SaSettingsSearch.matches(entry.words, part)
        if not found:
            continue
        var named := SaSettingsSearch.fold(entry.title)
        var rank := 2
        if named.begins_with(needle):
            rank = 0
        elif SaSettingsSearch.matches(named, parts[0]):
            rank = 1
        ranked[rank].append(entry)
    var out: Array[Entry] = []
    for bucket: Array in ranked:
        out.append_array(bucket)
    return out


## Every place on every Preferences page, by the words the Preferences search
## finds it by, so the two searches cannot disagree. A pick asks the Preferences
## door for the page and the row's title, which marks it, gives it the keyboard
## and scrolls it into view as a door's landing does.
##
## **A chord row of Keyboard shortcuts is left out** when its title is already a
## row above, a command, a filter, a docker or a tool, because that row is the
## same thing found twice and a pick of it would only open the page. The rows
## that page has of its own, its profile and its search, are listed. So is the
## chord row of a command that stays out of the search, so the opt-out holds on
## that page as well.
func _add_settings(out: Array[Entry]) -> void:
    var listed := {}
    for entry: Entry in out:
        listed[SaSettingsSearch.fold(entry.title)] = true
    var commands := _commands()
    if commands != null:
        for id: StringName in commands.list_ids():
            var descriptor := commands.get_descriptor(id)
            if not descriptor.show_in_search:
                listed[SaSettingsSearch.fold(tr(descriptor.title))] = true
    for entry: Entry in _settings:
        if entry.place != KEYBOARD_PAGE or not listed.has(SaSettingsSearch.fold(entry.title)):
            out.append(entry)


## Whether the settings rows are not those of the pages Preferences has now,
## because none were built yet or a module brought a page or took one away.
func settings_stale() -> bool:
    var registry := _ui()
    return registry != null and _page_titles(registry) != _settings_pages


## Builds one more page of the catalogue and answers whether the build is over,
## true at once when nothing is stale. The first call of a build makes the
## window the pages are made with, never shown or added to anything, and the
## last frees it, so Preferences is not opened and nothing of it stays. A page
## brought or taken while a build runs starts it again.
func warm_page() -> bool:
    var registry := _ui()
    if registry == null:
        return true
    var titles := _page_titles(registry)
    if _maker != null and titles != _building_for:
        _drop_build()
    if _maker == null:
        if titles == _settings_pages:
            return true
        _maker = SaSettingsWindow.new(registry)
        _maker.tools_registry = context.tools
        _maker.filters_registry = context.filters
        _maker.commands_registry = _commands()
        _pending = _maker.categories.duplicate()
        _building_for = titles
        _building.clear()
    if not _pending.is_empty():
        var category := String(_pending.pop_front())
        for landing: Dictionary in SaSettingsSearch.catalogue([category], _maker.build_page):
            var title := String(landing["title"])
            if not title.is_empty():
                var page := String(landing["page"])
                var act := _open_setting.bind(page, title)
                _building.append(Entry.new(SETTING, tr(title), tr(page), "", String(landing["words"]), true, act))
    if not _pending.is_empty():
        return false
    _settings = _building.duplicate()
    _settings_pages = _building_for
    _drop_build()
    _stale = true
    return true


## Builds the whole catalogue at once, which a suite asks for since it has no
## frames to spread the build over, and the window never does.
func warm() -> void:
    while not warm_page():
        pass


## A build cut short by the index going frees the window it made the pages with.
func _notification(what: int) -> void:
    # A script method cannot be called on an object being deleted, so the
    # unfinished build's window is freed here.
    if what == NOTIFICATION_PREDELETE and _maker != null:
        _maker.free()


func _drop_build() -> void:
    if _maker != null:
        _maker.free()
    _maker = null
    _pending.clear()
    _building.clear()
    _building_for = []


## The Preferences pages' titles, the built-in ones registered first, as the
## window that shows them would.
static func _page_titles(registry: SaUIRegistry) -> Array:
    SaSettingsWindow.register_builtins(registry)
    return registry.list_settings_pages().map(func(page: Dictionary) -> String: return String(page["title"]))


static func _open_setting(page: String, title: String) -> void:
    EventBus.settings_row_requested.emit.call_deferred(page, StringName(title))


## Command id -> the title of the first menu that draws it, from the rows each
## `SaMenu` drew.
static func _menu_places(menus: Dictionary) -> Dictionary:
    var places := {}
    for title: String in menus:
        var menu := menus[title] as SaMenu
        if menu == null:
            continue
        for command: StringName in menu._command_rows.values():
            if not places.has(command):
                places[command] = TopMenuBar.menu_title(title)
    return places


## *text* through the translation server, which a static function asks without
## an object to call `tr` on.
static func _translated(text: String) -> String:
    return TranslationServer.translate(text)


## "Keyboard Shortcuts > Help" for `help_search`: the page and the group the
## page files the id under, or the page alone for an id no group takes.
static func _page_place(command: StringName) -> String:
    for group: Array in SaShortcutRows.GROUPS:
        if String(command).begins_with(String(group[0])):
            return "%s > %s" % [_translated(SHORTCUTS_PAGE), _translated(String(group[1]))]
    return _translated(SHORTCUTS_PAGE)


## The command registry every command row reads, or null in a context that
## has none yet.
func _commands() -> SaCommandRegistry:
    return context.commands


## The UI registry the settings' pages are read from, or null in a
## run with no context.
func _ui() -> SaUIRegistry:
    return context.ui if context != null else null


func _descriptor(command: StringName) -> SaCommandDescriptor:
    var commands := _commands()
    return commands.get_descriptor(command) if commands != null else null


func _command_chord(command: StringName) -> String:
    var commands := _commands()
    var chord := commands.chord_text(command, 1) if commands != null else ""
    # Undo and Redo are bound through the engine's own actions of their name,
    # which the menus' rows read as well.
    if chord.is_empty() and InputMap.has_action(command):
        chord = SaCommandRegistry.format_events(InputMap.action_get_events(command), 1)
    return chord


## Runs *command* as its menu row would, and keeps it for Repeat Last, as a
## command run from a menu is kept.
func _run(command: StringName) -> void:
    _commands().execute(command)
    SaQuickCommands.note_run(command)
