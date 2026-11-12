## The one search over every action. F3, the loupe after the last menu title
## and the command Search... all open it, a list at the pointer with a field
## over it, and a pick does what that row's menu would have done.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## It reaches anything without the painter knowing which menu holds it. The
## rows and their order are [SaSearchIndex] with `SaSearchActions`, private to
## this folder, and the shell is an [SaChoicePopup] at the pointer whose right
## press and Menu key offer a row's command to Quick Favourites and to Assign
## Shortcut.
##
## **Typing narrows by the start of a word**, the rule Preferences' own search
## keeps, so "blur" finds Gaussian Blur and Box Blur and not "Unblurred", and
## ranks: a title that starts with the query, then a word of the title, then
## the rest. The first row that can be picked is highlighted, the arrows move
## it, and Enter picks it. A row whose command says it cannot run now is drawn
## dimmed and takes no pick, the way its menu row is greyed.
##
## **An opening draws a page of rows.** Each row is a control, and drawing every
## one of several hundred holds an opening for a time a painter feels. The rows
## are drawn a page at a time, the first on opening and on every keystroke, the
## next when the scroll or the highlight reaches the end of what is drawn, so an
## opening costs the same however many rows there are.
##
## **Built once**, under the current scene, a few seconds after the commands are
## registered, and kept hidden between openings. It then builds the settings'
## rows out of sight, a page of Preferences a frame, and again when the pages
## change. Each opening reads the registries again, so a module loaded since the
## last one is in the list.
##
## **F3 is a toggle**, as the loupe is: pressed again with the list up, the
## field holding the keyboard, it closes the list and lets the loupe up. A chord
## with no modifier never reaches the router from a focused field, so the list
## hears it itself in [method _input].
##
## **The chord is never cut**, since a chord is what a painter opens the list
## for. Its column is as wide as the widest chord the query leaves, measured in
## the font in use, and the Kind and Place columns give way before the title
## does. The corner grip resizes the list, never below a chord and a title of
## [constant MIN_TITLE_CHARS] characters, and the size it is left at is the size
## the next opening takes, kept as `search_window_size` in the settings.
##
## **An opening that finds the settings not built builds them while it is up,**
## so an F3 in the first seconds after launch lists them too. A page can hold a
## frame long enough for a painter typing to feel it, so a page is built only
## once the field has been still for a moment, by `SaSearchWarmer`, and the rows
## are read again and the query ranked over them once the last page is in.
##
## **The last three rows picked come first** when the field is empty, under a
## heading Recent and above every other row, so a search the painter repeats
## is one press away when the list opens again. A pick by Enter, a click or the door is kept by what the row
## acts on, its [method key_of], newest first in `SaSettings.search_recents`, so
## the three are there after a restart. A kept row this opening does not list,
## its module unloaded, is left out. A typed query ranks them with the rest.
@tool
class_name SaSearchWindow
extends SaChoicePopup

## The node this list is put under, and the name [method find_in] looks for.
const NODE_NAME := "SearchWindow"

## The command the loupe runs, Help's Search..., with no chord by default. Help's
## menu draws no row for it, since a row there moves the ids two menu suites read.
const COMMAND := &"help_search"

## How long after the commands are registered the list is built, in seconds,
## so a launch has drawn its window by then. Its settings' rows wait for the
## painter to stop as well.
const WARM_AFTER := 3.0

## How many rows a page draws: a few more than the tallest list shows.
const PAGE := 24

## How wide the list opens, logical, so a title and its three columns fit.
const WIDTH := 640

## The widths, logical, of the Kind and Place columns after a row's title when
## there is room, so the kinds and the places line up down the list.
const KIND_WIDTH := 90
const PLACE_WIDTH := 200
## The narrowest the chord column is, logical. It is otherwise as wide as the
## widest chord of the rows shown.
const CHORD_WIDTH := 90

## How many of a title's characters the narrowest list still shows beside the
## chord.
const MIN_TITLE_CHARS := 12

## The narrowest a Kind or Place column is drawn, logical, below which it is
## hidden rather than drawn as an ellipsis.
const MIN_CELL := 24

## The fewest rows the shortest list shows.
const MIN_ROWS := 6

## The loupe's icon, logical, the grid it is drawn on.
const LOUPE_ICON := 16

## The group every loupe is in, which follows the list's visibility.
const LOUPES := &"sa_search_loupes"

## The list last put in a tree, which [method find_in] answers without a walk.
static var _live: WeakRef = null

## What the rows are read from and what a pick calls.
var index: SaSearchIndex = null

## Every row of this opening, and the rows the query leaves in the order they
## rank, of which the first [member _drawn] are drawn.
var entries: Array[SaSearchIndex.Entry] = []
var shown: Array[SaSearchIndex.Entry] = []
## How many of the first rows of *shown* are the recent picks, none once a query
## is typed.
var recent_count: int = 0

## The place in *shown* of the highlighted row, or -1 when none can be picked.
var marked_at: int:
    get:
        return _place_of(highlighted())

## The query, the list's own search field.
var field: LineEdit = null

var _drawn: int = 0
var _count: Label = null
var _bar: TopMenuBar = null
## The frame the list last closed on, so the press on the loupe that closed it
## by landing outside it does not open it again.
var _closed_on: int = -1
## The build of the settings' rows, a page a frame.
var warmer: SaSearchWarmer = null
## The empty query's rows drawn ahead out of sight, a few a frame.
var draw_ahead: SaSearchDrawAhead = null
## The chord column's width, logical, the widest chord of the rows shown.
var _chord_width: float = 0.0
## The widest the first [constant MIN_TITLE_CHARS] characters of any title are,
## logical, which the list never narrows below.
var _title_floor: float = 0.0
## The widest whole title of the rows shown, which the Kind and Place columns
## give way to.
var _title_width: float = 0.0
## The corner the painter drags to resize the list.
var grip: Grip = null
## What the drawn rows are of when they are the empty query's, the index's
## version and the recent picks, so an opening that finds the same draws none,
## and empty while they are a typed query's.
var _drawn_for: Array = []
## The widths [method _measure] read over every row, kept with the rows and the
## fonts they were read for: the widest chord, the widest title and the widest
## first characters of a title.
var _widths: Array = []
var _widths_for: Array = []


## *bar* is the bar whose menus say where a command lives, the main window's
## found in the tree when null.
func _init(search_index: SaSearchIndex = null, bar: TopMenuBar = null) -> void:
    super(false, true, true)
    name = NODE_NAME
    index = search_index
    _bar = bar
    field = search
    # The Menu key is the row's offer, never the field's own menu.
    search.context_menu_enabled = false
    SaSearchField.mark(search)
    search.placeholder_text = tr("A word of a command, filter, docker, tool or setting")
    search.text_submitted.connect(func(_text: String) -> void: pick_marked())
    warmer = SaSearchWarmer.new(index, is_visible)
    add_child(warmer, false, Node.INTERNAL_MODE_FRONT)
    warmer.warmed.connect(_on_warmed)
    search.text_changed.connect(warmer.still.unbind(1))
    var steps := SaSearchDrawAhead.Page.new(
        read_rows, drawn_stale, start_fill.bind(""), add_rows.bind(1, false), end_fill.bind("")
    )
    draw_ahead = SaSearchDrawAhead.new(index, warmer, is_visible, steps)
    add_child(draw_ahead, false, Node.INTERNAL_MODE_FRONT)
    # The rows' minimum width is the list's to set, so a narrowing drag is never
    # stopped at the width the columns had before it.
    wrap_controls = false
    var footer := SaMake.row(_body, "SearchFooter")
    _count = SaMake.label(footer, "SearchCount")
    _count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    SaTheme.bind_font(_count, "text_muted")
    grip = Grip.new()
    footer.add_child(grip)
    size_changed.connect(_lay_columns)
    _scroll.get_v_scroll_bar().value_changed.connect(_on_scrolled)
    chosen.connect(_on_chosen)
    visibility_changed.connect(_show_on_loupes)
    popup_hide.connect(func() -> void: _closed_on = Engine.get_process_frames())
    popup_hide.connect(remember_size)
    popup_hide.connect(_after_close)
    SaQuickCommands.watch(self, _command_of)


func _enter_tree() -> void:
    _live = weakref(self)


## Registers the two commands that open the list through *ctx*, the one call
## `SaAppCommands.register_all` makes: F3's Search Commands..., filed under
## Edit, and Search..., filed under Help, which the loupe runs. Both stay, so a
## painter's saved binding of either still opens the list. Deferred, as
## Preferences is, because a chord pressed over an open menu arrives while that
## menu is still mid-hide.
##
## **The handler holds no registry.** A handler bound to the context would be
## held by the command registry the context holds, a circle of references
## nothing ever frees, which is what the suite's run reported as three thousand
## objects leaked at exit. The list reads the registries from the scene when it
## is first built instead, the way the filter browser does.
static func register_command(ctx: SaContext, toggle_docker: Callable, tool_machine_provider: Callable = Callable()) -> void:
    var asked := _asked
    var by_f3 := SaCommandDescriptor.create(SaQuickCommands.SEARCH, "Search every command", asked)
    by_f3.label = "Search Commands..."
    by_f3.sentence = "Type a word of any command, filter, docker, tool or setting, and Enter runs the one picked."
    var f3 := InputEventKey.new()
    f3.keycode = KEY_F3
    by_f3.default_events = [f3]
    by_f3.category = &"edit"
    ctx.register_command(by_f3)
    var command := SaCommandDescriptor.create(COMMAND, "Search every action", asked)
    command.category = &"help"
    command.label = "Search..."
    command.sentence = "Find any command, filter, docker, tool or setting by a word of its name, and run it."
    ctx.register_command(command)
    wire(ctx, toggle_docker, tool_machine_provider)
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null and not Engine.is_editor_hint():
        tree.create_timer(WARM_AFTER).timeout.connect(_prepare)


## Binds what the rows of the registries that need the app do when picked,
## the place the app wires them: a tool's row puts the tool in hand through the
## machine *tool_machine_provider* answers, a docker's shows it by
## *toggle_docker*, the Window menu's toggle, and a kind of layer presses its
## Layer menu row. The search reads none of these registries, so this is the
## whole of what the app hands them.
static func wire(ctx: SaContext, toggle_docker: Callable, tool_machine_provider: Callable = Callable()) -> void:
    if tool_machine_provider.is_valid():
        ctx.tools.search_pick = _pick_tool.bind(tool_machine_provider)
    if toggle_docker.is_valid():
        ctx.ui.search_pick = toggle_docker
    ctx.layer_types.search_pick = SaSearchActions.add_kind.bind(weakref(ctx.commands))


## The Tools menu's own line, so a tool picked in the search is the tool its row
## would have put in hand: the engine in use for the Brush, and the tool itself
## for anything else.
static func _pick_tool(tool_id: StringName, tool_machine_provider: Callable) -> void:
    var machine := tool_machine_provider.call() as ToolMachine
    if machine == null:
        return
    machine.set_active_tool(machine.registry.picked(tool_id) if machine.registry != null else tool_id)


static func _asked() -> bool:
    _open_with.call_deferred()
    return true


## Builds the list in the scene the commands were registered for, out of sight,
## and starts on the settings' rows once the painter stops. Nothing happens in a tree whose scene holds
## no registries, a suite's.
static func _prepare() -> void:
    var window := _built()
    if window != null:
        window.start_warming()


## Opens the list, building it on the first call over the scene's registries,
## and closes it when it is up, so the chord is a toggle. A list the same key
## closed in this frame, through [method _input], stays closed.
static func _open_with() -> void:
    var window := _built()
    if window == null:
        return
    if window.visible:
        window.hide()
    elif window._closed_on != Engine.get_process_frames():
        window.open()


static func _built() -> SaSearchWindow:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return null
    var window := find_in(tree)
    if window != null:
        return window
    var host := tree.current_scene
    var registries: SaRegistries = (host.get("registries") as SaRegistries) if host != null else null
    if registries == null:
        return null
    window = SaSearchWindow.new(SaSearchIndex.new(registries.context))
    host.add_child(window)
    return window


## The list in *tree*, or null before anything asked for it.
static func find_in(tree: SceneTree) -> SaSearchWindow:
    if tree == null:
        return null
    var live := (_live.get_ref() as SaSearchWindow) if _live != null else null
    if live != null and live.is_inside_tree() and live.get_tree() == tree:
        return live
    for node in tree.root.find_children(NODE_NAME, "Window", true, false):
        var window := node as SaSearchWindow
        if window != null:
            return window
    return null


## The loupe the top bar puts after its last menu title, drawn in *box*, the
## style of that title so the two read as one row. It is a toggle that follows
## the list: a press opens it, at the pointer and so under the loupe, and a
## press while it is open closes it.
static func loupe(box: StyleBox) -> Button:
    var button := Loupe.new()
    button.name = "SearchLoupe"
    button.add_to_group(LOUPES)
    # The bare name, which the engine needs to be non-empty before it asks
    # `_get_tooltip` at all.
    button.tooltip_text = TranslationServer.translate(Loupe.NAME)
    SaUI.set_button_icon(button, "search")
    # Drawn on the grid it was drawn on, so its lines stay on whole pixels and it
    # reads at the height of a title's letters rather than of the bar's icons.
    button.add_theme_constant_override("icon_max_width", SaUI.px(LOUPE_ICON))
    button.focus_mode = Control.FOCUS_NONE
    button.toggle_mode = true
    button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    button.custom_minimum_size = Vector2(SaUI.px(SaUI.BASE_ICON_SIZE + 4), SaUI.px(SaUI.BASE_ICON_SIZE + 2))
    for state: String in ["normal", "focus"]:
        button.add_theme_stylebox_override(state, box)
    # The pressed look is the toggle style every pressed toggle in Sara has,
    # bound to the palette, at the title's margins so a press never moves the row.
    for state: String in ["pressed", "hover_pressed"]:
        var down := SaTheme.make_toggle_style("pressed")
        for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
            down.set_content_margin(side, box.get_content_margin(side))
        button.add_theme_stylebox_override(state, down)
    button.pressed.connect(func() -> void: _flip(button))
    return button


## What a press of the loupe does: closes the list when it is up, and otherwise
## asks for it. A press that landed outside an open list closed it on its way
## to the loupe, in this frame, and opens nothing. The pressed state is then
## the list's own.
static func _flip(button: Button) -> void:
    var tree := button.get_tree()
    var window := find_in(tree)
    if window != null and window.visible:
        window.hide()
    elif window == null or window._closed_on != Engine.get_process_frames():
        ask(tree, button)
    window = find_in(tree)
    button.set_pressed_no_signal(window != null and window.visible)


## What the loupe does: opens the list when it is built, under *under* when
## one is given, and otherwise runs the command, whose handler builds it.
static func ask(tree: SceneTree, under: Control = null) -> void:
    var window := find_in(tree)
    if window != null:
        window.open(under)
        return
    var registries: SaRegistries = (tree.current_scene.get("registries") as SaRegistries) if tree.current_scene != null else null
    if registries != null:
        registries.commands.execute(COMMAND)


## The command registry *window*'s rows are read through, or null.
static func _commands_of(window: SaSearchWindow) -> SaCommandRegistry:
    if window == null or window.index == null or window.index.context == null:
        return null
    return window.index.context.commands


## The command registry the loupe reads its chord from: the built list's, and
## the scene's before there is one. Null in a tree that has neither.
static func commands_in(tree: SceneTree) -> SaCommandRegistry:
    if tree == null:
        return null
    var window := find_in(tree)
    var commands := _commands_of(window)
    if commands != null:
        return commands
    var registries: SaRegistries = (tree.current_scene.get("registries") as SaRegistries) if tree.current_scene != null else null
    return registries.commands if registries != null else null


## Builds the settings' rows a page a frame from now on, by [member warmer],
## at once when *asked*, and draws the rows ahead once they are in.
func start_warming(asked: bool = false) -> void:
    if not Engine.is_editor_hint() and index != null:
        warmer.start(asked)
        draw_ahead.wake()


## The settings joined the rows: an open list reads them again and ranks the
## query over them, so the settings join the list the painter is typing in,
## and a hidden one walks and draws them before the painter asks.
func _on_warmed() -> void:
    if visible:
        entries = index.entries(_menus())
        _fill(search.text)
        return
    draw_ahead.want()


## Reads the rows again as an opening would, so a command that came to run or
## stopped running since is dimmed or lit on the drawn rows, and answers
## whether that walked them, which took 17 ms.
func read_rows() -> bool:
    var walk := index.is_stale(_menus())
    entries = index.shown_rows(_menus(), _drawn_rows())
    return walk


## Every loupe pressed while the list is up and released when it goes, whichever
## way it went: Escape, a pick, a press outside it, or F3 opening it.
func _show_on_loupes() -> void:
    if not is_inside_tree():
        return
    for node in get_tree().get_nodes_in_group(LOUPES):
        (node as Button).set_pressed_no_signal(visible)


## Either command's chord closes the open list, in the field or out of it,
## before the list's own keys are read.
func _input(event: InputEvent) -> void:
    if visible and is_toggle_chord(event):
        hide()
        if is_inside_tree():
            get_viewport().set_input_as_handled()
        return
    super(event)


## Whether *event* is the press of F3's command or of Search..., as the input
## map binds them now.
func is_toggle_chord(event: InputEvent) -> bool:
    var key := event as InputEventKey
    var commands := _commands_of(self)
    if key == null or not key.pressed or key.echo or commands == null:
        return false
    var actions: Array = []
    for command: StringName in [SaQuickCommands.SEARCH, COMMAND]:
        var descriptor := commands.get_descriptor(command)
        if descriptor != null:
            actions.append(String(descriptor.action))
    return SaShortcutKeys.pressed(event, actions, false, true)


## Keeps the size the list was left at, logical, for the next opening.
func remember_size() -> void:
    var factor := maxf(SaUI.window_scale(self), 0.001)
    var logical := Vector2i((Vector2(size) / factor).round())
    if logical.x > 0 and logical.y > 0 and logical != SaSettings.search_window_size:
        SaSettings.search_window_size = logical


## Reads every row again, empties the field and opens the list at the pointer
## with the field holding the keyboard, which is what F3, the loupe and
## Search... all do. Under *under*, a loupe, when one is given.
##
## The rows are the index's kept ones, and the empty query's rows drawn at the
## last opening or after a close are shown again rather than drawn anew, which
## with the walk took the opening's frame to 80 ms.
func open(under: Control = null) -> void:
    var traced := SaFrameTrace.now()
    entries = index.shown_rows(_menus(), _drawn_rows()) if index != null else ([] as Array[SaSearchIndex.Entry])
    SaFrameTrace.spent("search rows read", traced)
    draw_ahead.drop()
    search.text = ""
    traced = SaFrameTrace.now()
    if drawn_stale():
        _fill("")
        SaFrameTrace.spent("search rows drawn", traced)
    else:
        _back_to_top()
        SaFrameTrace.spent("search rows kept", traced)
    warmer.opened()
    if warmer.building:
        draw_ahead.wake()
    if visible:
        search.grab_focus()
        return
    traced = SaFrameTrace.now()
    _open_at_pointer(under)
    SaFrameTrace.spent("search placed", traced)


## The view the empty query's rows are drawn for, which [member _drawn_for]
## keeps.
func _view() -> Array:
    var at := [SaUI.scale(), SaUI.user_font_scale, TranslationServer.get_locale()]
    return [index.version if index != null else 0, entries.size(), SaSettings.search_recents.duplicate(), at]


## Whether the drawn rows are not the empty query's for the view now.
func drawn_stale() -> bool:
    return _drawn_for.is_empty() or _drawn_for != _view()


## The rows drawn now, the only ones whose dimming shows. A row is asked
## whether it runs as its page is drawn, so the rest need not be asked.
func _drawn_rows() -> Array[SaSearchIndex.Entry]:
    return shown.slice(0, _drawn)


## The drawn empty query's rows shown from the top with the first that can be
## picked highlighted, as a fill leaves them.
func _back_to_top() -> void:
    _scroll.scroll_vertical = 0
    for id: StringName in row_ids():
        if set_highlight(id):
            break
    _lay_columns()


## A list closed on a typed query draws the empty query's rows a frame later,
## so the next opening finds them drawn.
func _after_close() -> void:
    if _drawn_for.is_empty() and not Engine.is_editor_hint() and index != null:
        draw_ahead.want()


## The query typed or set by `filter`, which ranks the rows again rather than
## hiding the drawn ones by the substring `SaChoiceSearch` matches, and answers
## how many rows it leaves. The close that empties the field leaves the empty
## query's rows to [member draw_ahead], so the frame it closed in, often one a
## menu opens in, draws none.
func _narrow(needle: String) -> int:
    if not visible and needle.is_empty() and index != null:
        draw_ahead.want()
        return shown.size()
    _fill(needle)
    return shown.size()


## Escape emptied the field, so every row is back before the list's own answer.
func _on_search_cleared() -> void:
    _fill("")
    super()


## Moving down past the last drawn row the keyboard can land on draws the next
## page first, so the arrows reach every row the query leaves.
func move_highlight(step: int) -> bool:
    var at := _place_of(highlighted())
    while step > 0 and _drawn < shown.size() and not _can_land_after(at):
        add_rows()
    return super(step)


func _can_land_after(at: int) -> bool:
    for later in range(at + 1, _drawn):
        if shown[later].enabled:
            return true
    return false


## Picks the highlighted row, which Enter does.
func pick_marked() -> void:
    pick(entry_of(highlighted()))


## Closes the list and does what *entry*'s row is for. A row that cannot be
## picked does nothing and the list stays.
func pick(entry: SaSearchIndex.Entry) -> void:
    if entry == null or not entry.enabled:
        return
    hide()
    remember(entry)
    entry.pick.call()


## What *entry* acts on, the key the recent picks keep: its command when one
## stands behind it, and its kind and title otherwise.
static func key_of(entry: SaSearchIndex.Entry) -> String:
    if not entry.command.is_empty():
        return "command:" + String(entry.command)
    return "row:%s:%s" % [entry.kind, entry.title]


## Puts *entry* at the front of the recent picks.
static func remember(entry: SaSearchIndex.Entry) -> void:
    SaSettings.remember_search_pick(key_of(entry))


## The rows of *rows* the recent picks name, newest first, a key no row has
## left out.
static func recents_in(rows: Array[SaSearchIndex.Entry]) -> Array[SaSearchIndex.Entry]:
    var by_key := {}
    for entry: SaSearchIndex.Entry in rows:
        var key := key_of(entry)
        if not by_key.has(key):
            by_key[key] = entry
    var out: Array[SaSearchIndex.Entry] = []
    for key: String in SaSettings.search_recents:
        if by_key.has(key):
            out.append(by_key[key])
    return out


## The rows this opening has, as the summary a scenario and a suite read: the
## query, how many rows are left of how many, and the first rows' titles with
## their kinds, the highlighted one first.
func report(limit: int = 12) -> Dictionary:
    var titles: Array = []
    for entry: SaSearchIndex.Entry in shown.slice(0, limit):
        titles.append("%s (%s)" % [entry.title, entry.kind])
    var mark := shown[marked_at].title if marked_at != -1 else ""
    var listed := {"query": search.text, "shown": shown.size() - recent_count, "of": entries.size(), "marked": mark}
    listed["recent"] = recent_count
    listed["rows"] = titles
    return listed


## The rows *query* leaves, ranked, of which the first page is drawn with the
## first that can be picked highlighted. The field keeps what was typed, which
## the list's `clear` empties.
func _fill(query: String) -> void:
    start_fill(query)
    add_rows()
    end_fill(query)


## A fill's start: the rows *query* leaves, ranked, none of them drawn yet.
func start_fill(query: String) -> void:
    var typed := search.text
    var caret := search.caret_column
    clear()
    # An empty query is the empty field's, and the draw-ahead's after a close.
    search.text = typed if not query.is_empty() else ""
    search.caret_column = caret
    shown = SaSearchIndex.narrowed(entries, query)
    var recent: Array[SaSearchIndex.Entry] = []
    if query.strip_edges().is_empty():
        recent = recents_in(entries)
    recent_count = recent.size()
    recent.append_array(shown)
    shown = recent
    _drawn = 0
    _drawn_for = []


## A fill's end, once its first rows are drawn: the columns measured and the
## first row that can be picked highlighted.
func end_fill(query: String) -> void:
    _measure()
    move_highlight(1)
    _drawn_for = _view() if query.strip_edges().is_empty() else []
    _count.text = tr_n("%d of %d", "%d of %d", entries.size()) % [shown.size() - recent_count, entries.size()]


## Draws the next *count* rows, laying the columns out again when *lay*, and
## answers whether the first page is in.
func add_rows(count: int = PAGE, lay: bool = true) -> bool:
    var last := mini(_drawn + count, shown.size())
    if index != null:
        index.recheck(shown.slice(_drawn, last))
    for at in range(_drawn, last):
        if at == 0 and recent_count > 0:
            add_section(tr("Recent"))
        if at == recent_count and recent_count > 0:
            add_gap()
        _add_entry(at)
    _drawn = last
    if lay:
        _lay_columns()
    return _drawn >= mini(PAGE, shown.size())


## The list's rows as a scenario's state reads them, each with the kind and the
## place its columns show, so a dump says what a row is as well as its title,
## and its chord with the width its cell has and the width its text needs.
func row_report() -> Array:
    var out := super.row_report()
    for row: Dictionary in out:
        var entry := entry_of(StringName(row["id"]))
        if entry != null:
            row["kind"] = entry.kind
            row["place"] = entry.place
            row["chord"] = entry.chord
            var cell := row_of(StringName(row["id"])).get_node("Chord") as Label
            row["chord_width"] = cell.size.x
            row["chord_needs"] = _text_width(cell.get_theme_font(&"font"), cell.get_theme_font_size(&"font_size"), cell.text)
    return out


## One row: the title, which the list's row draws and presses, and the three
## columns of what it is, where it lives and its chord.
func _add_entry(at: int) -> void:
    var entry := shown[at]
    var id := StringName("r%d" % at)
    add_row(id, entry.title, false, false, "", "", not entry.enabled)
    var row := row_of(id)
    var heading := row.label_button()
    heading.clip_text = true
    heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    heading.gui_input.connect(_on_row_input.bind(id))
    var dim := not entry.enabled
    _cell(row, "Kind", tr(entry.kind), KIND_WIDTH, dim)
    _cell(row, "Place", entry.place, PLACE_WIDTH, dim)
    var chord := _cell(row, "Chord", entry.chord, CHORD_WIDTH, dim)
    chord.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    # Never cut: the label's own minimum is its whole text.
    chord.clip_text = false
    chord.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING


static func _cell(row: HBoxContainer, node_name: String, text: String, width: int, dim: bool) -> Label:
    var cell := SaMake.label(row, node_name, text)
    cell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    cell.clip_text = true
    cell.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
    cell.custom_minimum_size.x = SaUI.px(width)
    cell.set_meta(SaUI.FONT_SCALE_META, 0.85)
    cell.modulate = Color(1.0, 1.0, 1.0, SaChoiceRow.hint_alpha(0.6, dim))
    return cell


## Measures, in the fonts the first drawn row uses, the widest chord and the
## widest title the query leaves, and the widest twelve characters any title
## starts with, then lays the columns out at the list's width.
func _measure() -> void:
    var first := row_of(&"r0")
    if first == null:
        _lay_columns()
        return
    var heading := first.label_button()
    var title_font := heading.get_theme_font(&"font")
    var title_size := heading.get_theme_font_size(&"font_size")
    var chord_cell := first.get_node("Chord") as Label
    var chord_font := chord_cell.get_theme_font(&"font")
    var chord_size := chord_cell.get_theme_font_size(&"font_size")
    var widest_chord := float(SaUI.px(CHORD_WIDTH))
    var widest_title := 0.0
    # Every row's widths, read once for the rows and the fonts they are in. The
    # empty query shows every row, the recent picks being rows as well, so its
    # widest are every row's, and a typed query reads only the rows it leaves.
    var walk := index.builds if index != null else 0
    var key := [walk, entries.size(), title_font, title_size, chord_font, chord_size, SaUI.px(CHORD_WIDTH)]
    if key != _widths_for:
        var all_chord := widest_chord
        var all_title := 0.0
        var all_floor := 0.0
        for entry: SaSearchIndex.Entry in entries:
            all_chord = maxf(all_chord, _text_width(chord_font, chord_size, entry.chord))
            all_title = maxf(all_title, _text_width(title_font, title_size, entry.title))
            all_floor = maxf(all_floor, _text_width(title_font, title_size, entry.title.left(MIN_TITLE_CHARS)))
        _widths = [all_chord, all_title, all_floor]
        _widths_for = key
    if shown.size() == entries.size() + recent_count:
        widest_chord = _widths[0]
        widest_title = _widths[1]
    else:
        for entry: SaSearchIndex.Entry in shown:
            widest_chord = maxf(widest_chord, _text_width(chord_font, chord_size, entry.chord))
            widest_title = maxf(widest_title, _text_width(title_font, title_size, entry.title))
    var floor_width: float = _widths[2]
    var pad := heading.get_combined_minimum_size().x
    _chord_width = ceilf(widest_chord) + 1.0
    _title_width = ceilf(widest_title + pad) + 1.0
    _title_floor = maxf(_title_floor, ceilf(floor_width + pad) + 1.0)
    _lay_columns()


static func _text_width(font: Font, font_size: int, text: String) -> float:
    if font == null or text.is_empty():
        return 0.0
    return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## Gives every drawn row's columns their widths at the list's width now: the
## chord its widest, the title its widest whole when there is room, the Kind
## and Place their own widths from what is left and then less, down to nothing,
## and the title what is left after that, never under its twelve characters.
## The list's least size follows, so a drag stops where those still show.
func _lay_columns() -> void:
    var first := row_of(&"r0")
    if first == null or _chord_width <= 0.0:
        return
    var kind_want := float(SaUI.px(KIND_WIDTH))
    var place_want := float(SaUI.px(PLACE_WIDTH))
    var overhead := _row_overhead(first)
    var room := get_visible_rect().size.x - _chrome_width() - overhead - _chord_width
    var spare := room - _title_width
    var kind := kind_want
    var place := place_want
    if spare < kind_want + place_want:
        var share := maxf(spare, 0.0) / (kind_want + place_want)
        kind = floorf(kind_want * share)
        place = floorf(place_want * share)
    for id: StringName in row_ids():
        var row := row_of(id)
        _fit(row.get_node("Kind") as Label, kind)
        _fit(row.get_node("Place") as Label, place)
        (row.get_node("Chord") as Label).custom_minimum_size.x = _chord_width
    var least := Vector2(_chrome_width() + overhead + _chord_width + _title_floor, float(SaUI.px(ROW_HEIGHT * MIN_ROWS)))
    min_size = SaUI.window_size_for(self, Vector2i(least.ceil()))


static func _fit(cell: Label, width: float) -> void:
    cell.visible = width >= float(SaUI.px(MIN_CELL))
    cell.custom_minimum_size.x = width if cell.visible else 0.0


## What a row takes beside its four columns: its separations and whatever it
## draws before its title.
func _row_overhead(row: SaChoiceRow) -> float:
    var cells := 0.0
    var gaps := 0
    for node_name: String in ["Kind", "Place", "Chord"]:
        var cell := row.get_node(node_name) as Control
        cells += cell.get_combined_minimum_size().x if cell.visible else 0.0
        gaps += 0 if cell.visible else 1
    var separation := float(row.get_theme_constant(&"separation"))
    var heading := row.label_button().get_combined_minimum_size().x
    # A hidden cell takes its separation with it, so the gaps are counted as if
    # every cell showed.
    return row.get_combined_minimum_size().x - cells - heading + separation * gaps


## What the panel takes from the rows' width: its margins and the scroll bar,
## whether or not the bar shows, so the columns do not move when it does.
func _chrome_width() -> float:
    var panel := get_theme_stylebox(&"panel")
    var margins := panel.get_margin(SIDE_LEFT) + panel.get_margin(SIDE_RIGHT) if panel != null else 0.0
    return margins + float(SaPopupRect.bar_width(self))


## The scroll came near the end of what is drawn, so the next page is drawn.
func _on_scrolled(value: float) -> void:
    var bar := _scroll.get_v_scroll_bar()
    if _drawn < shown.size() and value + bar.page >= bar.max_value - float(SaUI.px(ROW_HEIGHT * 4)):
        add_rows()


## A right press on a row offers what a menu row's does, for the command the
## row stands for, dimmed on a row no command stands behind.
func _on_row_input(event: InputEvent, id: StringName) -> void:
    var press := event as InputEventMouseButton
    if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_RIGHT:
        return
    var heading := label_button(id)
    if heading != null:
        heading.accept_event()
    SaQuickCommands.offer(self, id, _command_of(id))


func _command_of(id: StringName) -> StringName:
    var entry := entry_of(id)
    return entry.command if entry != null else &""


func _on_chosen(id: StringName) -> void:
    var entry := entry_of(id)
    if entry != null and entry.enabled:
        remember(entry)
        entry.pick.call()


func entry_of(id: StringName) -> SaSearchIndex.Entry:
    var at := _place_of(id)
    return shown[at] if at >= 0 and at < shown.size() else null


static func _place_of(id: StringName) -> int:
    var text := String(id)
    return int(text.substr(1)) if text.begins_with("r") and text.substr(1).is_valid_int() else -1


## Opens the list at the pointer, or under *under* or a loupe the pointer is
## on, in the window it is under, kept inside the room that window has, at
## [constant WIDTH] or wider.
func _open_at_pointer(under: Control) -> void:
    if not is_inside_tree():
        return
    var host := get_parent() as Node
    SaUI.apply_to_window(self)
    var at := host.get_viewport().get_mouse_position()
    # Under the loupe that was pressed, or under one the pointer is on, so the
    # loupe stays uncovered and a second press reaches it and shuts the list.
    for node: Variant in [under] + get_tree().get_nodes_in_group(LOUPES):
        var button := node as Control
        if button != null and button.is_visible_in_tree() and button.get_viewport() == host.get_viewport():
            var box := button.get_global_rect()
            if button == under or box.has_point(at):
                at = Vector2(box.position.x, box.end.y)
                break
    var window := host.get_window()
    var spot := Vector2i(at)
    if not is_embedded() and window != null:
        # A native popup is placed on the screen, in physical pixels.
        spot = window.position + Vector2i(at * window.content_scale_factor)
    var factor := content_scale_factor
    var wanted := Vector2i((Vector2(wanted_size(0.0)) * factor).round())
    wanted.x = maxi(wanted.x, roundi(WIDTH * factor))
    # The size the painter last left it at, kept logical.
    var kept := SaSettings.search_window_size
    if kept.x > 0 and kept.y > 0:
        wanted = SaUI.window_size_for(self, kept)
    wanted = wanted.max(min_size)
    var room := SaPopupRect.room_for(self)
    if room.has_area():
        spot.x = clampi(spot.x, room.position.x, maxi(room.position.x, room.end.x - wanted.x))
        spot.y = clampi(spot.y, room.position.y, maxi(room.position.y, room.end.y - wanted.y))
    popup(Rect2i(spot, wanted))
    search.call_deferred("grab_focus")


## The bar's menus by title, which say where a command lives, or none when
## there is no bar: the one this list was built with, or the main window's.
func _menus() -> Dictionary:
    var bar := _bar
    if bar == null and is_inside_tree():
        bar = SaSearchActions.bar_in(get_tree())
    return SaSearchActions.menus_of(bar)


## The loupe's button, whose hover reads the chord either command has when it
## is shown, F3's first, so a rebind on the Keyboard Shortcuts page is on the
## next hover.
class Loupe:
    extends Button

    ## The command's name, which the hover starts with.
    const NAME := "Search every action"

    func _get_tooltip(_at_position: Vector2) -> String:
        var words := TranslationServer.translate(NAME)
        var commands: SaCommandRegistry = null
        if is_inside_tree():
            commands = SaSearchWindow.commands_in(get_tree())
        var chord := ""
        if commands != null:
            for command: StringName in [SaQuickCommands.SEARCH, SaSearchWindow.COMMAND]:
                if chord.is_empty():
                    chord = commands.chord_text(command, 1)
        if chord.is_empty():
            return words
        return "%s (%s)" % [words, chord]


## The corner the painter drags to resize the list, in its footer. A drag
## changes the list's size by the pointer's travel, the window keeping it at or
## over its least size, and the size the drag ends on is remembered.
class Grip:
    extends Control

    ## The grip's side, logical.
    const SIDE := 14

    var _dragging: bool = false

    func _init() -> void:
        name = "SearchGrip"
        custom_minimum_size = Vector2(SaUI.px(SIDE), SaUI.px(SIDE))
        size_flags_vertical = Control.SIZE_SHRINK_END
        mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
        tooltip_text = TranslationServer.translate("Drag to resize the window.")

    func _gui_input(event: InputEvent) -> void:
        var press := event as InputEventMouseButton
        if press != null and press.button_index == MOUSE_BUTTON_LEFT:
            _dragging = press.pressed
            var list := get_window() as SaSearchWindow
            if not press.pressed and list != null:
                list.remember_size()
            accept_event()
            return
        var motion := event as InputEventMouseMotion
        if motion != null and _dragging:
            drag_by(motion.relative)
            accept_event()

    ## Grows the list it is in by *travel*, in the list's own logical units.
    func drag_by(travel: Vector2) -> void:
        var list := get_window()
        if list == null:
            return
        var grown := list.size + Vector2i((travel * list.content_scale_factor).round())
        list.size = grown.max(list.min_size)

    func _draw() -> void:
        var ink := SaTheme.palette.text_muted
        var side := size.x
        for step: int in 3:
            var inset := side * (0.25 + 0.25 * step)
            draw_line(Vector2(inset, side - 1.0), Vector2(side - 1.0, inset), ink, 1.0)
