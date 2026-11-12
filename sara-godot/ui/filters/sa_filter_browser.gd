## The filter browser: every registered filter in one list, with a search, the
## sentence the filter says, a preview over the active layer and an Open that
## is the Filter menu row's own invoke.
##
## **A control both browsers stand on.** The Filters docker holds one and the
## layer kind browser's window holds another, and neither is the other's
## subclass. There is no browser window of its own, only the docker, so what a
## window would have and the layer kind browser shares is here: the list, the
## search, the detail, the preview and Open. A host says what differs through
## the constructor, which filters it lists and what Open does, and puts the
## browser in a frame of its own.
##
## The Filter menu's lists stay, so this is a second door onto one registry
## rather than a replacement for the first. Nothing here runs a filter
## into a layer: Open calls `registry.invoke(key)` unless its host says
## otherwise, which is the single line the menu row calls, and
## [SaFilterDialogWindow] opens on the other side knowing nothing about where
## the invoke came from.
##
## **The list is grouped by section, like the menu's.** A section holds every
## module's filters of one kind, so the module is on each row's tooltip and in
## the detail column. The groups are `SaFilterMenu.sections`, so the two doors
## cannot disagree.
##
## **The preview runs the filter at its declared defaults.** A filter's widgets
## carry their default the moment `build` declares them, before any control is
## realized, so the browser builds a throwaway [SaDialog], lets the filter
## declare into it and runs against a preview context. Nothing is realized, so
## no control is created for a picture, and nothing is written, because a
## preview context's [method SaFilterContext.show] is the only thing called. A
## point or a neighbourhood filter shows nothing and records a pass instead, so
## the browser runs that pass over the layer's chunks into a texture of its own
## and shows that, which the dialog never needs because the canvas is its
## picture.
##
## **A filter already open in its dialog is not previewed.** One filter instance
## serves both windows, and `build` replaces its widget rows, so previewing the
## filter whose dialog is up would hand that dialog's realized controls a set of
## rows nobody is reading. The picture is worth less than the open dialog.
##
## **Every other pick starts at the filter's defaults.** The one instance keeps
## what the last window wrote into it, and the layer kind browser added the
## values of a cancelled dialog. A pick puts the store back
## to its defaults before the preview runs, as `SaFilterDialogWindow` does on
## open, unless a window or the panel shows that store, whose widgets would
## move under the painter.
@tool
class_name SaFilterBrowser
extends VBoxContainer

## The name the browser takes under its host. A scenario's `"in":
## "FilterBrowser"` found the window by it and finds this by it now.
const NODE_NAME := "FilterBrowser"

## How wide the list column asks to be, logical, beside the detail. Wide enough
## for a module heading and a filter title beside each other without wrapping.
const LIST_WIDTH := 240

## How tall the list asks to be at least, logical, when it stands over the
## detail, five rows of the 160 wide strip a docker is given in the shipped
## layouts. The 96 it was showed one and a half.
const STACKED_FLOOR := 160

## The meta a filter's row carries its registry key under, which Map to MIDI
## reads off the row a click lands on.
const FILTER_META := &"sa_filter_key"

## The registry the list and the sentences are read from, and the commands a
## filter that says nothing is asked a sentence of. Both null on a browser
## nobody pointed at a registry, which is what a detached test builds.
var registry: SaFilterRegistry = null
var commands: SaCommandRegistry = null

## The key the browser is showing, or "" when nothing is picked.
var selected: StringName = &""

## How many previews have been run since this browser was built, which is the
## number a scenario reads beside the shown rectangle.
var previews: int = 0

## The canvas this browser previews on, or null to walk `current_scene`, which
## is `Main` in the running app. Set by a test so a browser outside the tree can
## show a bench canvas's layer, as [member SaFilterDialogWindow.target_canvas] is.
var target_canvas: SaCanvas = null

## Whether the list stands beside the detail or over it, which
## [method lay_out] writes.
var side_by_side: bool = true

## The field the search is typed in, which a window gives the keyboard first.
var search: LineEdit = null
## The column right of the list or under it: the words and the picture, the
## row of buttons, and under them whatever parts a host adds, the Filters
## docker's parameters and looks.
var detail: VBoxContainer = null
## The scroll over the words and the picture, which a dialog grows to its
## content and which takes what the host has left.
var detail_scroll: ScrollContainer = null
## The row under the detail that Open sits in, at its end, and that a host puts
## a button of its own in.
var buttons: HBoxContainer = null
var open_button: Button = null

var _body: BoxContainer = null
var _list_scroll: ScrollContainer = null
var _list: VBoxContainer = null
var _title_label: Label = null
var _owner_label: Label = null
var _sentence_label: Label = null
var _preview: SaFilterPreview = null

## What Open does with the picked key, or an empty callable for the Filter
## menu row's own `registry.invoke`.
var _on_open: Callable

## Whether a key is listed at all, or an empty callable for every key, which
## the layer kind browser narrows to the filters its kind can hold.
var _admits: Callable

## Registry key -> the button that offers it, rebuilt with the list because a
## module unloading takes its rows with it.
var _rows: Dictionary = {}

## The keys the list is offering, in the order it offers them.
var _shown_keys: Array[StringName] = []
## The headings over them, in order, which is how the dump says the list is
## grouped the menu's way.
var _shown_headings: PackedStringArray = []

## The context the last preview ran against, held only so the texture it showed
## outlives the call. A `Texture2DRD` over a released RID is a crash, which is
## the entry `sa_easel.gd`'s header keeps.
var _context: SaFilterContext = null


## A browser with the list beside the detail when *beside*, or over it, as
## [method lay_out] says. *on_open* is called with the picked key in place of
## the registry's invoke, and *admits* answers whether a key is listed.
func _init(beside: bool = true, on_open: Callable = Callable(), admits: Callable = Callable()) -> void:
    name = NODE_NAME
    _on_open = on_open
    _admits = admits
    add_theme_constant_override("separation", SaUI.px(8))
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL

    search = LineEdit.new()
    search.name = "BrowserSearch"
    search.placeholder_text = tr("Search filters")
    search.clear_button_enabled = true
    SaSearchField.mark(search)
    search.text_changed.connect(func(_text: String) -> void: refresh())
    add_child(search)

    _body = BoxContainer.new()
    _body.name = "BrowserBody"
    _body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_child(_body)

    _build_list(_body)
    _build_detail(_body)
    lay_out(beside)
    # The rows' tooltips and headings are written through tr() as they are
    # built, which the Filters docker does before a language module's
    # catalogue arrives, so the list is built again at each change of language.
    SaOnLanguage.watch(self, refresh)


## Stands the list beside the detail when *beside*, the shape of a window and
## of the Filters docker wide enough for a sidebar, or over it, the narrow
## docker's. Beside, the list is a column [constant LIST_WIDTH] wide and a
## title asks for its whole width. Over, the list is the detail's width and
## [constant STACKED_FLOOR] tall at least, and a title wider than it takes a
## second line, since a trimmed "Hue/Saturation/Lig..." is a name nobody reads.
func lay_out(beside: bool) -> void:
    side_by_side = beside
    _body.vertical = not beside
    _body.add_theme_constant_override("separation", SaUI.px(12 if beside else 8))
    var floor_size := Vector2(float(SaUI.px(LIST_WIDTH)), 0.0) if beside else Vector2(0.0, float(SaUI.px(STACKED_FLOOR)))
    _list_scroll.custom_minimum_size = floor_size
    _list_scroll.size_flags_horizontal = Control.SIZE_FILL if beside else Control.SIZE_EXPAND_FILL
    for row: Button in _rows.values():
        row.autowrap_mode = TextServer.AUTOWRAP_OFF if beside else TextServer.AUTOWRAP_WORD_SMART


## Puts a host's *parts* in the detail column under the buttons, the Filters
## docker's parameters and looks. The words and the picture then show whole,
## because a host with parts of its own scrolls the column as one.
func hold(parts: Array[Control]) -> void:
    detail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    for part in parts:
        detail.add_child(part)


## The list: a scroller over one button per filter, grouped by section.
func _build_list(into: BoxContainer) -> void:
    _list_scroll = ScrollContainer.new()
    _list_scroll.name = "BrowserList"
    _list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    into.add_child(_list_scroll)

    _list = VBoxContainer.new()
    _list.name = "BrowserRows"
    _list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _list_scroll.add_child(_list)


## The detail: what the picked filter is, and what it would do, over Open.
func _build_detail(into: BoxContainer) -> void:
    detail = VBoxContainer.new()
    detail.name = "BrowserDetail"
    detail.add_theme_constant_override("separation", SaUI.px(6))
    detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
    into.add_child(detail)

    # The words and the picture scroll, and the buttons stay under them. At an
    # interface scale of 2 on a 1280 by 800 screen the room below the bar is
    # 335 tall, and the column with the preview's floor of 200 in it ran on to
    # 416, so Close and Open were under the bottom edge.
    detail_scroll = ScrollContainer.new()
    detail_scroll.name = "BrowserDetailScroll"
    detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    detail.add_child(detail_scroll)

    var words := VBoxContainer.new()
    words.name = "BrowserWords"
    words.add_theme_constant_override("separation", SaUI.px(6))
    words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    words.size_flags_vertical = Control.SIZE_EXPAND_FILL
    detail_scroll.add_child(words)

    _title_label = Label.new()
    _title_label.name = "BrowserTitle"
    _title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    words.add_child(_title_label)

    _owner_label = Label.new()
    _owner_label.name = "BrowserOwner"
    # Wrapped, as the title is, so a module's long name never holds a narrow
    # docker wider than its layout made it.
    _owner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _owner_label.set_meta(SaUI.FONT_SCALE_META, 0.8)
    _owner_label.modulate = Color(1.0, 1.0, 1.0, 0.7)
    words.add_child(_owner_label)

    _sentence_label = Label.new()
    _sentence_label.name = "BrowserSentence"
    _sentence_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _sentence_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
    words.add_child(_sentence_label)

    _preview = SaFilterPreview.new()
    _preview.name = "BrowserPreview"
    words.add_child(_preview)

    buttons = HBoxContainer.new()
    buttons.name = "BrowserButtons"
    buttons.alignment = BoxContainer.ALIGNMENT_END
    buttons.add_theme_constant_override("separation", SaUI.px(8))
    detail.add_child(buttons)

    open_button = Button.new()
    open_button.name = "BrowserOpenButton"
    open_button.text = tr("Open", "open a filter")
    open_button.disabled = true
    open_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    open_button.pressed.connect(open_selected)
    buttons.add_child(open_button)


## Fills *dialog*, the window this browser stands in, with what a dialog asks
## of its body: the search takes the keyboard first, the detail column is what
## scrolls when the window is short, Open is the default and reads
## *open_label*, *lead* stands first in the row of buttons, and the window
## showing and hiding is followed as `follow_window` says. The layer kind
## browser is the dialog that holds one, the Filters docker being no dialog.
func serve(dialog: SaDialogWindow, lead: Button, open_label: String) -> void:
    dialog.first_focus = search
    dialog.scrolling_body = detail_scroll
    dialog.default_button = open_button
    open_button.text = open_label
    buttons.add_child(lead)
    buttons.move_child(lead, 0)
    dialog.visibility_changed.connect(follow_window)


## Draws *filters* from now on, with *from_commands* behind a filter's sentence.
##
## The list is rebuilt on the registry's `changed` for the reason the Filter
## menu refills on it: a module loaded or unloaded while the browser is up takes
## its rows with it, and a row over a filter nobody holds any more invokes
## nothing.
func watch(filters: SaFilterRegistry, from_commands: SaCommandRegistry) -> void:
    commands = from_commands
    if filters == registry:
        refresh()
        return
    if registry != null and registry.changed.is_connected(refresh):
        registry.changed.disconnect(refresh)
    registry = filters
    if filters != null and not filters.changed.is_connected(refresh):
        filters.changed.connect(refresh)
    refresh()


## Types *text* in the search the way a hand would, which refreshes the list.
func search_for(text: String) -> void:
    search.text = text
    search.text_changed.emit(text)


## Picks *key* the way a press on its row would, or nothing when it is empty.
## False, and nothing picked, when the list is not offering it.
func pick(key: StringName) -> bool:
    if not String(key).is_empty() and not _rows.has(key):
        return false
    _select(key)
    return true


## Rebuilds the list from the registry, keeping only what the search matches,
## in the order `SaFilterBrowserRows.order` gives a search's rows.
##
## The picked filter survives a search that still holds it and is dropped by one
## that does not, so the detail column never describes a row that is not on
## screen.
func refresh() -> void:
    if _list == null:
        return
    # Freed rather than queued: a queue needs a frame, and the suites that
    # build this browser hold no tree to give it one, so a queued row would be a
    # leak the runner counts.
    for child in _list.get_children():
        _list.remove_child(child)
        child.free()
    _rows.clear()
    _shown_keys.clear()
    _shown_headings.clear()
    if registry == null:
        _select(&"")
        return
    var needle := search.text.strip_edges().to_lower() if search != null else ""
    var found: Array[Dictionary] = []
    for section: Dictionary in SaFilterMenu.sections(registry):
        var words := section_words(section)
        var rows: Array = []
        var ranks: Array = []
        for key: StringName in section["keys"]:
            var ranked := rank(key, needle, words)
            if ranked > SaFilterMenu.RANK_NONE:
                rows.append(key)
                ranks.append(ranked)
        found.append({"label": section["label"], "rows": rows, "ranks": ranks})
    for section: Dictionary in order(found):
        _add_heading(tr(section["label"]))
        for key: StringName in section["rows"]:
            _add_row(key)
    _select(selected if _rows.has(selected) else &"")


## Whether *key*'s filter answers the search word *needle*, which is lower case
## and already stripped, and is one the host lists. An empty word matches
## everything the host lists.
##
## The title and the sentence both, which is the clause the browser is
## graded on: a painter looking for "blur" is as likely to have read the word in
## a description as in a name. And *words*, its section's, so "blur" finds a
## blur whose title never says so.
func matches(key: StringName, needle: String, words := "") -> bool:
    return rank(key, needle, words) > SaFilterMenu.RANK_NONE


## How well *key*'s filter answers *needle*, `SaFilterMenu.rank`'s answer, and
## none for a filter the host does not list, which is the order the list is in.
func rank(key: StringName, needle: String, words := "") -> int:
    if _admits.is_valid() and not bool(_admits.call(key)):
        return SaFilterMenu.RANK_NONE
    if needle.is_empty():
        return SaFilterMenu.RANK_STARTS
    var filter := _filter_for(key)
    if filter == null:
        return SaFilterMenu.RANK_NONE
    return SaFilterMenu.rank(filter, needle, words, sentence_for(key))


## *found*'s sections and rows in the order a search lists them, which
## `SaFilterBrowserRows.order` says, the door the Filter menu's search orders by.
static func order(found: Array[Dictionary]) -> Array[Dictionary]:
    return SaFilterBrowserRows.order(found)


## The words a search finds a section's filters by, its id and its label in
## lower case. None for Other, whose word says nothing about a filter and would
## match "the".
static func section_words(section: Dictionary) -> String:
    if section["section"] == SaFilterRegistry.OTHER:
        return ""
    var label := TranslationServer.translate(String(section["label"]))
    return ("%s %s" % [String(section["section"]), label]).to_lower()


## The sentence *key*'s filter says, or its command's when it says none. Asked by
## `command_for`: a filter that declares an `action_name()` is not under its key's name.
func sentence_for(key: StringName) -> String:
    var filter := _filter_for(key)
    var said := filter.sentence() if filter != null else ""
    if not said.is_empty() or filter == null or commands == null:
        return said
    var descriptor := commands.get_descriptor(SaFilterRegistry.command_for(key, filter))
    return descriptor.sentence if descriptor != null else ""


## The filter registered under *key*, or null.
func _filter_for(key: StringName) -> SaFilter:
    return registry.get_filter(key) if registry != null else null


## The name *module_id* shows under, its own `get_name()` where the module is
## loaded and the bare id where it is not.
##
## A walk of its own rather than `SaMenu.module_display_name`, which is an
## instance method of a menu: reaching it from here would mean either holding a
## menu this browser has no use for or calling an instance method statically,
## which the LSP check counts as a warning.
func module_display_name(module_id: StringName) -> String:
    if String(module_id).is_empty():
        return tr("Filters")
    for folder_name: Variant in ModuleLoader.loaded_modules:
        var mod: SaModule = ModuleLoader.loaded_modules[folder_name]
        if mod.get_id() == module_id:
            return mod.get_name()
    return String(module_id)


## Asks the registry for the picked filter's dialog, or hands the key to the
## host's own Open.
##
## `registry.invoke` and nothing else, which is the same call the menu row makes
## and the reason the dialog on the other side needs no line for this browser.
## A summoned Filters docker going back at Open is the docker's own Open.
##
## Not deferred, unlike the menu row's. The re-entrancy the menu guards against
## is a `PopupMenu`'s own `id_pressed` handler, and this is a `Button`'s
## `pressed`, which is what the dialog host's own note calls the safe side of
## that defer.
func open_selected() -> void:
    if registry == null or String(selected).is_empty():
        return
    if _on_open.is_valid():
        _on_open.call(selected)
    else:
        registry.invoke(selected)


## Picks *key*, or nothing when it is empty, and fills the detail column.
##
## **Nothing picked shows the active layer as it stands**, copied GPU to GPU, so
## a pick is read against the picture it changes. A dark box under a sentence
## about modules read as a preview that failed to load. The box stays dark with
## no layer, in a hidden host, which holds nothing, and on an empty layer,
## whose context answers the whole canvas to show nothing but transparency.
func _select(key: StringName) -> void:
    selected = key
    for row_key: StringName in _rows:
        var button := _rows[row_key] as Button
        button.set_pressed_no_signal(row_key == key)
    var filter := _filter_for(key)
    if filter == null:
        _title_label.text = tr("No filter selected")
        _owner_label.text = ""
        _sentence_label.text = tr("Select a filter to see what it does to the active layer.")
        open_button.disabled = true
        var document := _active_document() if is_shown() else null
        if document == null or document.active_layer == null or document.active_layer.chunks.is_empty():
            _show_preview(null)
            return
        var context := SaFilterContext.new(document, document.active_layer, &"", "", true)
        _show_preview(context.layer_pixels(0), context.rect)
        return
    _title_label.text = filter.title()
    _owner_label.text = tr("Added by %s") % module_display_name(registry.owner_of(key))
    var problem := filter.problem()
    var sentence := sentence_for(key)
    if not problem.is_empty():
        _sentence_label.text = problem.split("\n")[0].strip_edges()
    elif not sentence.is_empty():
        _sentence_label.text = sentence
    else:
        _sentence_label.text = tr("No description. Open the filter to see its settings.")
    open_button.disabled = not problem.is_empty()
    _run_preview(key, filter)


## Whether the painter can see the browser: the window it is in is shown, or,
## in none, the browser itself is. Read off the window rather than the tree,
## because a window outside the tree, which is how a suite holds one, records
## its flag and nothing else.
func is_shown() -> bool:
    var host := get_parent()
    while host != null and not host is Window:
        host = host.get_parent()
    return (host as Window).visible if host != null else visible


## Follows the window the browser is in being shown or hidden, which the host
## connects its `visibility_changed` to.
##
## A hidden browser holds nothing. The preview is a texture the size of the
## run's rectangle, which is the whole canvas on a layer painted edge to edge,
## and a browser nobody is looking at has no use for it. Held on, it is
## reported as leaked RIDs at exit. Shown, it runs its pick again, or shows the
## layer with none, because a show no refresh came before runs nothing and the
## Filters docker shown in its strip would read "Preview" over an empty box.
func follow_window() -> void:
    if not is_shown():
        _show_preview(null)
    else:
        _select(selected)


## Runs *filter* at its declared defaults and puts the result in the preview.
##
## Nothing is written: the context is built previewing, so `show` is the only
## thing the run reaches and the layer is untouched whatever the filter does.
## A pass that reads the whole layer is the preview's own run over where it
## writes, [method SaFilterPreview.show_whole_pass], since its picture is not
## the run's rectangle.
##
## The registry holds one instance of a filter, and a page the guard below
## cannot see may be reading its store: the Filter Brush's rows live in a
## module, which `ui` never names, and write the store back onto the brush
## after the next move. So the values the store held go back once the run is
## over, as the brush's own stroke puts them back around its run.
func _run_preview(key: StringName, filter: SaFilter) -> void:
    var held := filter.parameters()
    _run_at_defaults(key, filter)
    filter.set_parameters(held)


## The record *filter* is filed as at its declared defaults, the values a
## preview runs, with the values its one instance held put back after, so a
## layer added from a pick holds what its preview showed and nothing another
## page had moved.
static func filed_at_defaults(filter: SaFilter, key: StringName) -> SaAttachedFilter:
    var held := filter.parameters()
    filter.store.reset()
    var filed := filter.filed_as(key)
    filter.set_parameters(held)
    return filed


func _run_at_defaults(key: StringName, filter: SaFilter) -> void:
    if not filter.problem().is_empty():
        _show_preview(null)
        return
    var document := _active_document()
    if document == null or document.active_layer == null:
        _show_preview(null)
        return
    if _shown_elsewhere(filter):
        _show_preview(null)
        return
    filter.store.reset()
    var probe := SaDialog.new()
    filter.build(probe)
    _context = SaFilterContext.new(document, document.active_layer, registry.owner_of(key), filter.title(), true)
    previews += 1
    var picture: SaTexture = null
    var ran := SaFilterApply.call_run(filter, _context)
    if ran and reads_whole(_context):
        _preview.show_whole_pass(_context)
        _free_declared(probe)
        return
    if ran:
        picture = picture_of(_context)
    if picture != null:
        _preview.show_texture(picture, _context.shown_rect)
    else:
        _show_preview(null)
    _free_declared(probe)


## Whether a page on *filter*'s one instance is up: the Filter dialog's, an
## attached record's window or its panel in the tool options docker.
func _shown_elsewhere(filter: SaFilter) -> bool:
    if not is_inside_tree():
        return false
    var dialog := SaFilterDialogWindow.find_in(get_tree())
    var editor := SaFilterEditWindow.find_in(get_tree())
    if dialog != null and dialog.visible and dialog.filter == filter:
        return true
    if editor != null and editor.visible and editor.filter == filter:
        return true
    for panel in get_tree().root.find_children(SaFilterPanel.NODE_NAME, "", true, false):
        if panel is SaFilterPanel and (panel as SaFilterPanel).filter == filter:
            return true
    return false


## What a preview run of *ctx* looks like, blended with the layer under the
## selection's mask as the dialog's own preview is, or null when the run
## left nothing to look at.
##
## A run that showed a texture is that texture. A run that recorded a pass is
## the pass run over the layer's chunks into a texture over the run's rectangle
## and handed to [method SaFilterContext.show], which is the context's own door
## for a result and leaves [member SaFilterContext.point] as it was. Once only
## the first kind previewed, so the six adjustments, the box blur and every
## point filter a module registers showed an empty box.
##
## A pass that reads the whole layer is no picture here, null, because run over
## the run's rectangle a chunk at a time it is a fragment. Its picture is [method SaFilterPreview.show_whole_pass].
static func picture_of(ctx: SaFilterContext) -> SaTexture:
    if ctx == null:
        return null
    if ctx.shown == null and ctx.point != null:
        var evaluated := PassPicture.evaluate(ctx)
        if evaluated == null:
            return null
        ctx.show(evaluated)
    return SaFilterPreview.blended(ctx)


## Whether *ctx*'s run recorded a pass that reads the whole layer, a
## kaleidoscope, a mirror or a wrap, whose picture is the preview's own.
static func reads_whole(ctx: SaFilterContext) -> bool:
    var gather := ctx.point as SaNeighbourhoodPass if ctx != null else null
    return gather != null and gather.whole()


## Frees the controls a declaration built that nobody realized.
##
## Two of the dialog's kinds build their `Control` in the declaration rather
## than in `realize`: `ui.preview()` makes an [SaFilterPreview] and
## `ui.apply_cancel()` an `HBoxContainer` holding two buttons. A dialog that is
## realized hands both to a container that owns them from then on, and this
## probe realizes nothing, so a node still without a parent here is a node
## nobody will ever free, and every filter selected leaks its canvas items,
## shaped text buffers and objects at exit.
static func _free_declared(probe: SaDialog) -> void:
    for row: SaPageRow in probe.rows():
        # `custom_control` and not `control`: the node a declaration hands over
        # sits in the first, and `realize` is what copies it into the second.
        for node: Control in [row.custom_control, row.control]:
            if node != null and is_instance_valid(node) and node.get_parent() == null:
                node.free()


## Shows *texture* over *covering*, in document pixels, or clears the preview
## when it is null, and drops the context behind the last run.
func _show_preview(texture: SaTexture, covering := Rect2i()) -> void:
    _context = null
    if _preview != null:
        _preview.show_texture(texture, covering)


## One section's heading, drawn the way the menu draws its separator.
func _add_heading(text: String) -> void:
    var heading := Label.new()
    heading.name = "BrowserHeading"
    heading.text = text
    _shown_headings.append(text)
    heading.set_meta(SaUI.FONT_SCALE_META, 0.8)
    heading.modulate = Color(1.0, 1.0, 1.0, 0.7)
    _list.add_child(heading)


## One filter's row: a toggle carrying its title, dimmed when the filter says it
## cannot run, which is the same rule the menu row follows. A double click
## selects it and presses Open, unless Open is greyed for a filter that cannot
## run.
func _add_row(key: StringName) -> void:
    var filter := _filter_for(key)
    var button := Button.new()
    button.name = "BrowserRow"
    button.text = filter.title()
    button.set_meta(FILTER_META, key)
    button.toggle_mode = true
    button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    if not side_by_side:
        button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var problem := filter.problem()
    if problem.is_empty():
        button.tooltip_text = tr("Added by %s.") % module_display_name(registry.owner_of(key))
    else:
        button.tooltip_text = problem.split("\n")[0].strip_edges()
    button.pressed.connect(_select.bind(key))
    SaFilterBrowserRows.open_on_double_click(button, _select.bind(key), _open_when_it_can)
    _list.add_child(button)
    _rows[key] = button
    _shown_keys.append(key)


## Presses Open as a hand could, which is not at all while it is greyed.
func _open_when_it_can() -> void:
    if not open_button.disabled:
        open_selected()


func _active_document() -> SaDocument:
    var canvas := target_canvas
    if canvas == null and is_inside_tree():
        canvas = SaCanvasView.front_canvas()
    return canvas.document if canvas != null else null


## What the browser is, for the state dump: what it is offering, what is picked,
## and what the preview is looking at. Its host adds whether it is open and
## where it stands.
func describe() -> Dictionary:
    var listed: Array = []
    for key: StringName in _shown_keys:
        listed.append(String(key))
    return {
        "search": search.text,
        "listed": listed,
        "headings": Array(_shown_headings),
        "selected": String(selected),
        "title": _title_label.text,
        "owner": _owner_label.text,
        "sentence": _sentence_label.text,
        "can_open": not open_button.disabled,
        "previews": previews,
        "preview": _preview.describe(),
    }


## What each piece of the detail column asks for, where each button of the
## row under it is and where each part of the browser stands, which is what
## finding a host's height and reading that no part is over another need. The
## host puts its own rectangle beside these.
##
## The rectangles are global, so "the Open button is on the window" is two
## numbers a scenario compares, and the minimums name the control that pushed
## the host past the screen when one does.
func describe_layout() -> Dictionary:
    var minimums: Dictionary = {}
    for control: Control in [search, _title_label, _owner_label, _sentence_label, _preview]:
        var asked := control.get_combined_minimum_size()
        minimums[String(control.name)] = [asked.x, asked.y]
    var placed: Dictionary = {}
    for button: Node in buttons.get_children():
        if button is Button:
            var rect := (button as Button).get_global_rect()
            placed[String(button.name)] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
    var parts: Dictionary = {}
    for part: Control in [search, _list_scroll, detail, _title_label, _owner_label, _sentence_label, _preview, buttons]:
        var rect := part.get_global_rect()
        parts[String(part.name)] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
    return {"minimums": minimums, "buttons": placed, "parts": parts, "side_by_side": side_by_side}


## A recorded pass run over a layer into a picture, and never into the layer.
##
## The records' own contracts, so the browser and the dialog cannot disagree
## about what a filter does: a point pass is dispatched over a scratch copy of
## each chunk the way the compositor's point preview dispatches it, with the
## origin the pass writes into its push constant, and a neighbourhood pass goes
## through [SaNeighbourhoodPass.Runner], which gathers the halo from the chunks
## around. The point preview itself is a private file of `core/composite`,
## which the rules of structure (see `CONTRIBUTING.md`) keep a window from naming. Each chunk's answer
## is copied GPU to GPU into the picture over the part of the run's rectangle it
## covers, and the kernel is dispatched over that part alone (hard rules 1 and
## 2, nothing read back and no dispatch over the whole canvas).
##
## The kernel reads the full mask, `SaSelection.everything`, rather than the
## selection's own, because [method SaFilterPreview.blended] mixes the picture
## by the selection afterwards, the way it mixes a filter that showed a texture.
## Mixing by it here as well would square a feather.
class PassPicture:
    extends RefCounted

    ## The picture is at the layer's own density, twice the run's rectangle on
    ## a side on a layer at twice the document's resolution, which is the
    ## texture Apply writes there.
    ##
    ## A pass that reads the whole layer answers null, for the reason
    ## [method SaFilterBrowser.picture_of] gives.
    static func evaluate(ctx: SaFilterContext) -> SaTexture:
        if SaFilterBrowser.reads_whole(ctx):
            return null
        var document: SaDocument = ctx.document
        var layer: SaLayer = ctx.layer
        var rect := ctx.rect
        var rd := GlobalShaderCompiler.get_rd()
        if document == null or layer == null or rd == null or rect.size.x <= 0 or rect.size.y <= 0:
            return null
        var recorded := ctx.point
        var compute := ctx.kernel(recorded.shader)
        var format: int = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
        var spec := SaFieldSpec.find(layer.schema, SaFieldSpec.ALBEDO)
        if spec != null:
            format = spec.format
        var side := SaFilterDensity.side_of(layer)
        var picture := SaTexture.new(SaFilterDensity.texels(rect, side), format)
        # A fresh texture is undefined, and a position no chunk answers for has
        # to read as transparent. Only copies follow, so the clear is ordered.
        picture.clear(Color(0.0, 0.0, 0.0, 0.0))
        var everything := document.selection.everything()
        if recorded is SaNeighbourhoodPass:
            _gather(rd, recorded as SaNeighbourhoodPass, compute, layer, everything, rect, picture)
        else:
            _point(rd, recorded, compute, layer, everything, rect, picture)
        return picture

    static func _point(
        rd: RenderingDevice,
        recorded: SaPointPass,
        compute: SaCompute,
        layer: SaLayer,
        mask: SaTexture,
        rect: Rect2i,
        picture: SaTexture
    ) -> void:
        var side := SaFilterDensity.side_of(layer)
        var scratch := SaTexture.new(Vector2i(side, side), picture.format)
        compute.use_storage_format(picture.format)
        for grid_pos: Vector2i in layer.chunks.keys():
            var chunk: SaChunk = layer.chunks[grid_pos]
            var source: SaTexture = chunk.field(SaFieldSpec.ALBEDO) if chunk != null else null
            if source == null or source.size.x != side:
                continue
            var local: Rect2i = SaFilterDensity.place(grid_pos, rect, side)[0]
            if local.size.x <= 0 or local.size.y <= 0:
                continue
            var at := Vector3(local.position.x, local.position.y, 0)
            rd.texture_copy(source.rid, scratch.rid, at, at, Vector3(local.size.x, local.size.y, 1), 0, 0, 0, 0)
            compute.set_texture(0, scratch.rid)
            compute.set_texture(SaSelection.BINDING, mask.rid)
            recorded.bind(compute)
            compute.set_push_constant_float_array(recorded.push_for(local.position, grid_pos * SaChunk.SIZE))
            compute.dispatch_kernel(recorded.kernel, SaCompute.groups_for(local.size.x), SaCompute.groups_for(local.size.y), 1)
            SaFilterDensity.copy_share(rd, scratch, grid_pos, rect, picture)

    static func _gather(
        rd: RenderingDevice,
        recorded: SaNeighbourhoodPass,
        compute: SaCompute,
        layer: SaLayer,
        mask: SaTexture,
        rect: Rect2i,
        picture: SaTexture
    ) -> void:
        var runner := SaNeighbourhoodPass.Runner.new()
        runner.reads_canvas_of(layer)
        var side := SaFilterDensity.side_of(layer)
        var answer := SaTexture.new(Vector2i(side, side), picture.format)
        for grid_pos: Vector2i in SaChunkWalk.positions_in(rect):
            if not _near_paint(layer, grid_pos):
                continue
            var local: Rect2i = SaFilterDensity.place(grid_pos, rect, side)[0]
            if local.size.x <= 0 or local.size.y <= 0:
                continue
            runner.run(recorded, compute, answer, layer.get_field(grid_pos), layer.get_field, grid_pos, local, mask)
            SaFilterDensity.copy_share(rd, answer, grid_pos, rect, picture)

    ## Whether a halo can carry paint to *grid_pos*: a chunk there or in one of
    ## the eight around it. A position with neither is transparent whatever the
    ## filter reads, which the clear already says, so it costs no dispatch.
    static func _near_paint(layer: SaLayer, grid_pos: Vector2i) -> bool:
        for dy: int in [-1, 0, 1]:
            for dx: int in [-1, 0, 1]:
                if layer.chunks.has(grid_pos + Vector2i(dx, dy)):
                    return true
        return false
