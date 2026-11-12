## What every menu under the top bar shares: the popup it fills and a populate
## that is safe to run twice.
##
## One file per menu, so that a change to the Layer menu edits layer_menu.gd and
## nothing else. The bar keeps the structure, the popups, their order and their
## visibility, and hands each popup to the class here that knows what goes in it.
## The class is a RefCounted rather than a node: it owns no scene state, it lives
## exactly as long as the bar holds it, and a freed one takes its signal
## connections with it.
##
## **A static menu is a list of commands**, rather than a row written four
## times as an `ID_` constant, an `add_item` call, an `explain` line and a case
## in `on_id_pressed` calling what the command registry already holds. A list
## names the command and the registry answers the rest, the words, the chord, the
## sentence, whether the row is dimmed, its tick and what a press does. What is
## left in a menu file is the part that changes while Sara runs, the recent
## files, the filters, the modules and the dockers.
##
## **A row keeps its number.** Every `menu_item` step and a good many suites
## name a row by its integer id, so a list entry pairs the id with the command
## and the popup still keys the row `item_<id>`.
##
## **No registry, no command rows.** The words live in the registry now, so a bar
## that nobody bound draws only a menu's own rows. Main binds the registry right
## after the bar's `_ready`, before a painter can open anything, and a suite that
## wants the rows binds one too.
##
## **The list is `SaChoicePopup`**, whose rows are `Control`s a note can be made
## on, and it is rebuilt before every open, so a tick, a dim and a sentence are
## arguments to the row rather than four lines that find it again.
class_name SaMenu
extends RefCounted

## What an integer id looks like as a popup row id. A prefix rather than the
## bare number, because `StringName(&"3")` is a name a type-ahead would match
## and a reader would not recognise.
const ID_PREFIX := "item_"

## The mark a command list writes where a line goes across the menu.
const LINE := &"---"

## The meta a submenu's list carries, which tells it from a list a row opens
## for a choice, such as Ground's, when the popup's children are walked.
const GROUP_META := &"sa_menu_group"

## The label colours a choice row's mark is written on, every state the pointer
## or the keyboard can put a row in, so the mark never gives way to a hover.
const CHOICE_COLOURS: Array[StringName] = [
    &"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"
]

var popup: SaChoicePopup

## The chord a command entry reads from. Null until main binds it, which is
## after the bar's own `_ready`, so every menu is built once with no chord shown
## and again once the registry arrives.
var commands: SaCommandRegistry = null

## The command behind each row a list drew, item id -> command id, so a press on
## one runs the command and a tick is read back from it.
var _command_rows: Dictionary = {}
## The rows a fixed command list drew, row id -> true, which `SaMenuLetters`
## letters before the rows that arrive while Sara runs.
var _listed_rows: Dictionary = {}
## The rows of a choice of one, item id -> the name of its section, so a pick
## moves the mark within its own section and no other.
var _choice_rows: Dictionary = {}
## The submenus' lists, group row id -> `SaChoicePopup`, kept from build to
## build, and the group rows the last build drew, in order.
var _groups: Dictionary = {}
var _shown_groups: Array[int] = []
## The menu's own popup while a group's rows are being added to its list, and
## null otherwise.
var _menu_popup: SaChoicePopup = null


func _init(menu_popup: SaChoicePopup) -> void:
    popup = menu_popup


## Whether the popup is in the tree, which is what a detached bar in a suite is
## not. Every question below that needs the tree asks this first, because
## `get_tree()` on a detached node prints an error rather than answering null.
func in_tree() -> bool:
    return popup != null and popup.is_inside_tree()


## The node that holds the popup, which is where a dialog a menu opens goes, so
## it inherits what the popup's own host inherits. Null for a popup nobody holds.
func host() -> Node:
    return popup.get_parent() if popup != null else null


## The popup row id an integer item id is written as.
static func key(item_id: int) -> StringName:
    return StringName(ID_PREFIX + str(item_id))


## The integer item id behind a popup row id, or -1 for a row that is not one.
static func id_of(row_id: StringName) -> int:
    var text := String(row_id)
    if not text.begins_with(ID_PREFIX):
        return -1
    return int(text.substr(ID_PREFIX.length()))


## Fills the popup from scratch and makes sure a press reaches `on_id_pressed`.
##
## Both signals, because the popup answers a row on one of two: `chosen` for a
## command row's label, and `marked` for a tick row, whose label presses its box
## so a painter aiming at either half means the same thing. A `PopupMenu` had one
## signal for both and this is that signal put back together.
##
## Named `menu build` in the frame trace, because a menu is built from scratch
## before every open and on a list of forty rows that is most of the frame the
## menu opens in, which the trace had counted among the frame's unnamed rest.
func populate() -> void:
    if popup == null:
        return
    var began := SaFrameTrace.now()
    _build()
    SaFrameTrace.spent("menu build", began)


## The list itself, which [method populate] times.
func _build() -> void:
    popup.clear()
    _command_rows.clear()
    _listed_rows.clear()
    _choice_rows.clear()
    _shown_groups.clear()
    for list: SaChoicePopup in _groups.values():
        list.clear()
    _add_items()
    if not popup.branched.is_connected(_on_group_asked):
        popup.branched.connect(_on_group_asked)
    _wire(popup)
    for item_id: int in _shown_groups:
        _wire(_groups[item_id])


## Letters, the right press's offer and the presses, on *list*, the menu's own
## popup or one of its submenus, each of which a painter works the same way.
func _wire(list: SaChoicePopup) -> void:
    var letters := SaMenuLetters.pick(_letter_rows(list))
    for row_id: StringName in letters:
        SaChoiceLetters.underline(list.row_of(row_id), letters[row_id])
    SaQuickCommands.watch(list, row_command)
    if not list.chosen.is_connected(_on_row_chosen):
        list.chosen.connect(_on_row_chosen)
    if not list.marked.is_connected(_on_row_marked):
        list.marked.connect(_on_row_marked)


## Every row of *list* as `SaMenuLetters.pick` reads it, `[row id, label,
## listed]`, in the order the list draws them. A row of a module, a docker or a
## recent file carries no letter of its own and gets one here by the same rule.
func _letter_rows(list: SaChoicePopup) -> Array:
    var out: Array = []
    for row_id: StringName in list.row_ids():
        var button := list.label_button(row_id)
        out.append([row_id, button.text if button != null else "", _listed_rows.has(row_id)])
    return out


## Opens a submenu: a row on this list named *label*, with *sentence* on its
## hover as every row of a top menu has one, that opens a list of its own
## beside it, and every row added until [method end_group] goes on that
## list rather than on this one.
##
## **Submenus, so a long menu fits a screen.** The View, Layer and Window menus
## ran past a laptop's height and scrolled. Rows of one kind under one row
## leave the menu a screen tall, and every row keeps its id, its words and its
## chord, so a press, a tick and a scenario's `menu_item` reach it as before.
##
## The rows are added through the same calls as the menu's own, because
## `popup` is the submenu's list until the group ends. The submenu's list is
## made once per *item_id*, a child window of the menu's popup so the menu
## frees it with itself, and is filled again on every build. A group that ends
## with no row in it hides its row again, since a row opening an empty list
## tells a painter nothing.
func begin_group(item_id: int, label: String, sentence: String) -> void:
    if popup == null or _menu_popup != null:
        return
    _menu_popup = popup
    popup.add_branch_row(key(item_id), label)
    set_item_tooltip(item_id, sentence)
    if not _groups.has(item_id):
        var list := SaChoicePopup.new(true, false)
        list.name = "%sGroup%d" % [popup.name, item_id]
        list.set_meta(GROUP_META, item_id)
        popup.add_child(list)
        list.branched.connect(_relay_branched)
        _groups[item_id] = list
    _shown_groups.append(item_id)
    popup = _groups[item_id]


## Closes the submenu [method begin_group] opened, so the rows after it go on
## the menu's own list again.
func end_group() -> void:
    if _menu_popup == null:
        return
    var list := popup
    popup = _menu_popup
    _menu_popup = null
    if list.row_ids().is_empty():
        var item_id: int = _shown_groups.pop_back()
        popup.row_of(key(item_id)).visible = false


## The list among *list* and the submenus it opens that holds *row_id*, or
## null. Static, because a docker row and a harness step ask it of a popup
## whose menu they never hold.
static func list_holding(list: SaChoicePopup, row_id: StringName) -> SaChoicePopup:
    for each: SaChoicePopup in lists_of(list):
        if each.row_ids().has(row_id):
            return each
    return null


## *list* and the submenus [method begin_group] gave it, in the order they were
## made, which is what a walk of every row a menu holds reads: the search, the
## letters and a suite. A list a row opens beside it for a choice, such as
## Ground's, is not among them, since its rows are not the menu's.
static func lists_of(list: SaChoicePopup) -> Array[SaChoicePopup]:
    var out: Array[SaChoicePopup] = []
    if list == null:
        return out
    out.append(list)
    for child: Node in list.get_children():
        if child is SaChoicePopup and child.has_meta(GROUP_META):
            out.append(child)
    return out


## The words of every row *list* and its submenus hold, the list's own first,
## for a reader that asks whether a menu has a row and not where it stands.
static func labels_of(list: SaChoicePopup) -> Array[String]:
    var out: Array[String] = []
    for each: SaChoicePopup in lists_of(list):
        out.append_array(each.row_labels())
    return out


## The list that holds the row *item_id*, the menu's own when none does, so a
## question about a row nobody drew is asked of the menu and answered there.
func _list_of(item_id: int) -> SaChoicePopup:
    var found := list_holding(popup, key(item_id))
    return found if found != null else popup


## The submenu's list for the group row *item_id* on *list*, the menu's
## popup, or null for a row that opens none or stands hidden. Static, since a
## harness step asks it of a menu it holds only as a popup.
static func group_list(list: SaChoicePopup, item_id: int) -> SaChoicePopup:
    var row: SaChoiceRow = list.row_of(key(item_id)) if list != null else null
    if row == null or not row.visible:
        return null
    for child: Node in list.get_children():
        if child is SaChoicePopup and child.get_meta(GROUP_META, -1) == item_id:
            return child
    return null


## Opens the submenu of the group row *item_id* beside it and answers its list,
## which a suite reads without a window. Deferred from the press for the
## reason the Filter menu gives, since the list takes the focus.
static func open_group(list: SaChoicePopup, item_id: int) -> SaChoicePopup:
    var group := group_list(list, item_id)
    if group != null:
        list.open_child(group, key(item_id))
    return group


func _on_group_asked(row_id: StringName) -> void:
    if group_list(popup, id_of(row_id)) != null:
        open_group.call_deferred(popup, id_of(row_id))


## A branch row inside a submenu, such as Ground under a group, asked for its
## list, which the menu answers as it answers its own list's.
func _relay_branched(row_id: StringName) -> void:
    popup.branched.emit(row_id)


## A press on a command row's label, which closes the menu behind it the way the
## engine's did. A tick row is not answered here: its label presses its box, so
## both halves of the row reach `_on_row_marked` and the menu stays open, three
## ticks being three presses rather than three trips to the bar.
func _on_row_chosen(row_id: StringName) -> void:
    SaUsageTally.menu_row(String(popup.name), _usage_name(row_id))
    var item_id := id_of(row_id)
    if item_id < 0:
        return
    popup.hide()
    on_id_pressed(item_id)


## A press on a tick row, on its box or on its label, which presses the box.
##
## **The box flipped itself on the way here and is put back**, so the handler
## sees the state the row was in before the press. `on_id_pressed` is what a
## `PopupMenu` called and what suites still call directly, and every tick row's
## handler reads the tick, flips it and writes what it now says. A box left
## flipped would have those handlers write the value that was already there,
## which is the dead menu item the View menu's own comment records from the
## other direction.
func _on_row_marked(row_id: StringName, on: bool) -> void:
    SaUsageTally.menu_row(String(popup.name), _usage_name(row_id))
    var item_id := id_of(row_id)
    if item_id < 0:
        return
    var holder := list_holding(popup, row_id)
    var box := holder.check_box(row_id) if holder != null else null
    if box != null:
        box.set_pressed_no_signal(not on)
    var shown := _shown_windows()
    on_id_pressed(item_id)
    # A tick whose press showed a window closes its menu, which stood over that
    # window, as it stood over Modules › Local Server's dialog. A window of its
    # own is not counted, since it takes the focus and a popup closes on
    # losing it.
    if _shown_windows() > shown:
        popup.hide()


## How many windows the root embeds and shows, this menu's own among them.
func _shown_windows() -> int:
    if not in_tree():
        return 0
    return popup.get_tree().root.get_embedded_subwindows().filter(func(window: Window) -> bool: return window.visible).size()


## One row. *disabled* dims it and takes its press away, from the row's first
## draw rather than written after the fact.
func add_item(text: String, item_id: int, disabled: bool = false, hint: String = "", icon_name: String = "") -> void:
    popup.add_row(key(item_id), text, false, false, icon_name, hint, disabled)
    _clear_placeholder_tooltip(item_id)


## What the usage tally calls the row *row_id*: the command it runs, and for a
## row of the menu's own, a recent file or a docker, the words on it, which is
## what a reader of the tally knows it by.
func _usage_name(row_id: StringName) -> String:
    var item_id := id_of(row_id)
    if item_id >= 0 and not command_at(item_id).is_empty():
        return String(command_at(item_id))
    var holder := list_holding(popup, row_id)
    var button := holder.label_button(row_id) if holder != null else null
    return button.text if button != null and not button.text.is_empty() else String(row_id)


## A row with a tick, whose state is what it is built with.
func add_check_item(text: String, item_id: int, checked: bool = false, disabled: bool = false) -> void:
    popup.add_row(key(item_id), text, true, checked, "", "", disabled)
    _clear_placeholder_tooltip(item_id)


## One row of a choice of one, a section of rows where exactly one is chosen,
## such as the Stabilizer's modes.
##
## **No box on any row.** Ticks read as things that can each be on, and Sara's
## rule is that a choice of one is a list of labels where one is always chosen.
## The chosen row wears the accent colour the blend list's chosen row wears, on
## its hover and pressed colours as well, so the mark stays put while the pointer
## rests on it or on another row.
##
## **A pick leaves the menu open**, as a tick row's did, so a painter sees the
## mark move. The popup closes on any label press it answers, so the row's press
## is taken from the popup and answered here instead. *section* names the rows
## that share one choice. The menu moves the mark with `mark_choice` once its
## `on_id_pressed` has written the pick, so a suite calling that directly sees
## the same mark.
func add_choice_item(text: String, item_id: int, section: StringName, chosen: bool = false) -> void:
    popup.add_row(key(item_id), text)
    _clear_placeholder_tooltip(item_id)
    _choice_rows[item_id] = section
    var button := popup.label_button(key(item_id))
    # A kept row comes back wired from its last build, so every answer, the
    # popup's and this menu's, is taken off before this menu's goes on once.
    for link: Dictionary in button.pressed.get_connections():
        var answer: Callable = link["callable"]
        if answer.get_object() == popup or answer.get_object() == self:
            button.pressed.disconnect(answer)
    button.pressed.connect(_on_choice_pressed.bind(item_id))
    _paint_choice(item_id, chosen)


## Marks *item_id* chosen and every other row of its section not chosen.
func mark_choice(item_id: int) -> void:
    if not _choice_rows.has(item_id):
        return
    var section: StringName = _choice_rows[item_id]
    for other: int in _choice_rows:
        if _choice_rows[other] == section:
            _paint_choice(other, other == item_id)


## Whether *item_id* is a choice row wearing the mark.
func is_choice_marked(item_id: int) -> bool:
    return _choice_rows.has(item_id) and _list_of(item_id).is_marked(key(item_id))


## The mark on one choice row, or its absence.
func _paint_choice(item_id: int, chosen: bool) -> void:
    var row := _list_of(item_id).row_of(key(item_id))
    if row == null:
        return
    var button := row.label_button()
    for colour: StringName in CHOICE_COLOURS:
        if chosen:
            button.add_theme_color_override(colour, SaTheme.palette.accent_primary)
        elif button.has_theme_color_override(colour):
            button.remove_theme_color_override(colour)
    row.apply_alpha(chosen)


## A press on a choice row, by the pointer, its letter or the keyboard's enter.
func _on_choice_pressed(item_id: int) -> void:
    SaUsageTally.menu_row(String(popup.name), _usage_name(key(item_id)))
    on_id_pressed(item_id)


## A line across the list, for the job a menu separator did.
func add_separator() -> void:
    popup.add_gap()


## A heading over the rows under it, which is what a submenu became: the popup
## has no window of its own to hang a second list off, and a run of rows under a
## title is what the engine's submenu was drawing anyway.
func add_heading(text: String) -> void:
    popup.add_section(text)


## Whether the list holds a row for this id.
func has_item(item_id: int) -> bool:
    return list_holding(popup, key(item_id)) != null


## Writes a tick without announcing it, which is what a sync is: the state
## changed elsewhere and the row is catching up, so `on_id_pressed` must not run.
func set_item_checked(item_id: int, on: bool) -> void:
    var box := _list_of(item_id).check_box(key(item_id)) if popup != null else null
    if box != null:
        box.set_pressed_no_signal(on)


func is_item_checked(item_id: int) -> bool:
    return popup != null and _list_of(item_id).is_checked(key(item_id))


## The sentence the row shows on hover.
##
## Written on the row's own `Button` rather than through a setter on the popup,
## because the popup hands the button out and a tooltip is the button's own
## property. `add_row` puts the label there as a placeholder, so a row with
## nothing to say still says its own words rather than nothing.
func set_item_tooltip(item_id: int, sentence: String) -> void:
    var button := _list_of(item_id).label_button(key(item_id)) if popup != null else null
    if button != null:
        button.tooltip_text = sentence


## A row's tooltip is its sentence or nothing.
##
## `SaChoicePopup.add_row` puts the label there as a placeholder, which is right
## for a dropdown whose rows are one word and wrong for a menu: the menus' rule
## is that every row explains itself and that a command row with no registered
## sentence says nothing rather than repeating its own label. `explain` is the
## only writer here, so the placeholder is cleared on the way in.
func _clear_placeholder_tooltip(item_id: int) -> void:
    var button := popup.label_button(key(item_id))
    if button != null:
        button.tooltip_text = ""


## How many rows the list holds.
func item_count() -> int:
    return popup.row_ids().size() if popup != null else 0


## Points the menu at the registry a command entry's chord comes from, and
## rebuilds so the chord shows without a restart. A menu that needs the
## registry for more than a chord (`SaModulesMenu`) overrides this and calls
## it first.
func bind_commands(registry: SaCommandRegistry) -> void:
    commands = registry
    if registry != null and not registry.changed.is_connected(_on_commands_changed):
        registry.changed.connect(_on_commands_changed)
    populate()


## The registry changed, a chord or a command, so the list is built again: at
## once when it is open or out of the tree, and otherwise on a frame of its own
## after this one, a closed menu a frame.
##
## **One a frame, because twelve at once held a frame.** A shortcut profile
## switched from Quick settings rebuilt every menu of the bar in the frame of
## the press, 90 ms of the 3 s it took. A closed list is built again
## before it opens anyway (`TopMenuBar._show_menu`), so a menu waiting
## its frame never shows a stale chord.
func _on_commands_changed() -> void:
    if not in_tree() or popup.visible:
        populate()
        return
    StaleMenus.add(self, popup.get_tree())


## The closed menus the registry changed under, rebuilt one a frame in the order
## they were told.
class StaleMenus:
    ## The menus waiting, as weak references, so a bar freed meanwhile is not
    ## kept alive by its place in the line.
    static var _waiting: Array[WeakRef] = []

    ## Puts *menu* in the line once, and starts the line when it was empty.
    static func add(menu: SaMenu, tree: SceneTree) -> void:
        for waiting: WeakRef in _waiting:
            if waiting.get_ref() == menu:
                return
        _waiting.append(weakref(menu))
        if _waiting.size() == 1:
            _drain(tree)

    ## How many menus wait, which a suite reads to know the line has run out.
    static func count() -> int:
        return _waiting.size()

    static func _drain(tree: SceneTree) -> void:
        while not _waiting.is_empty():
            await tree.process_frame
            if _waiting.is_empty():
                return
            var menu := _waiting.pop_front().get_ref() as SaMenu
            if menu != null and is_instance_valid(menu.popup):
                menu.populate()


## *text* with its chord appended, when `command_id` answers to a key:
## `"Cut (Ctrl+X)"`, the toolbox tooltip's own shape. Composed here rather than
## typed by the menu, so the chord a row shows is the key the router answers,
## and an entry that answers to nothing keeps its text alone.
##
## **The registry first, then the input map**. Undo and Redo are bound in `project.godot`
## and have no registry entry, so they were the two rows a painter reaches for most often
## and the only two on the Edit menu that said nothing. The fallback is here rather than
## a second registration in `ui/shortcuts/sa_app_commands.gd`, which sits elsewhere
## and which would have made a chord on a menu row wait on a chain three deep. It reads
## the same input map the router already answers from, so a row cannot draw a chord that
## does not work.
##
## **Only once a registry is bound.** Every menu is built once before that and
## again after, and until the registry has spoken there is no telling whether a
## command is about to answer on a different key from the one the input map
## holds. So the first build still shows bare text.
func chorded(text: String, command_id: StringName) -> String:
    var chord := chord_of(command_id)
    if chord.is_empty():
        return text
    return "%s (%s)" % [text, chord]


## The chord the input map has bound to *action*, as words, for a row whose key
## is in `project.godot` rather than in the command registry.
##
## The keycode twin goes in front of every physical binding, because a physically
## bound key spells itself "Ctrl+N - Physical" and that is not a chord anybody
## recognises. `SaFileMenu` is where the five rows that read that way were, and
## it is the only caller.
static func action_chord(action: StringName) -> String:
    if not InputMap.has_action(action):
        return ""
    var events := InputMap.action_get_events(action)
    if events.is_empty():
        return ""
    var ordered: Array[InputEvent] = []
    for event: InputEvent in events:
        var key_event := event as InputEventKey
        if key_event == null or key_event.keycode != KEY_NONE or key_event.physical_keycode == KEY_NONE:
            continue
        var twin := key_event.duplicate() as InputEventKey
        twin.keycode = key_event.physical_keycode
        twin.physical_keycode = KEY_NONE
        ordered.append(twin)
    ordered.append_array(events)
    # The first, not the list. A `Shortcut` drew its first event and so does a
    # row: an action bound twice, which is what a physical binding and its twin
    # are, would otherwise read "Ctrl+N, Ctrl+N".
    return SaKeyLabels.column(SaCommandRegistry.format_events([ordered[0]] as Array[InputEvent]))


## The chord *command_id* answers to, as words, or "" for one that answers to
## nothing and for a menu built before the registry arrived.
##
## Split out of `chorded`, because a row draws the chord in its own column now
## and only a caller that wants it inside the label joins the two.
##
## **The first chord, not the list.** Zoom in answers three keys, and its row
## read "Ctrl+=, Ctrl++, Ctrl+Numpad +" in a column meant for one. The
## Shortcuts page is where every chord of a command is listed, and a row names
## the one its command lists first, as the toolbox's tool rows already did.
##
## **Nothing on a tablet with no keyboard**, where a chord is a key nobody can
## press, which `SaKeyLabels` decides for every menu.
func chord_of(command_id: StringName) -> String:
    if commands == null:
        return ""
    var chord := commands.chord_text(command_id, 1)
    if chord.is_empty():
        chord = commands.shown_chord(command_id, 1)
    if chord.is_empty() and InputMap.has_action(command_id):
        chord = SaCommandRegistry.format_events(InputMap.action_get_events(command_id), 1)
    return SaKeyLabels.column(chord)


## The sentence a row shows on hover, by item id, so the row and its
## explanation sit one line apart rather than two and nobody adds the first
## without the second.
##
## Here rather than in each menu, because every menu needs the same two lines
## and copies of a helper are how menus drift. A row whose sentence already
## exists in a registry or a descriptor passes that one in rather than a second
## wording of it.
func explain(item_id: int, sentence: String) -> void:
    set_item_tooltip(item_id, tr(sentence))


## Draws a command list, in order. An entry is `[item_id, command_id]`, or
## [constant LINE] for a line across the menu.
##
## A third element is the row's words in this menu, for a command whose own
## label says more than the menu around it needs. The Edit menu's Clear is the
## Layer menu's Clear Layer, and one command answers both rows.
##
## A command the registry does not hold draws nothing, which is a module that
## is not loaded or a bar nobody bound, and a line with no row left above it or
## below it is not drawn either.
func add_commands(rows: Array) -> void:
    var line_waiting := false
    for entry: Variant in rows:
        if entry is StringName and entry == LINE:
            line_waiting = item_count() > 0
            continue
        var row: Array = entry
        if not _descriptor(row[1]):
            continue
        if line_waiting:
            add_separator()
            line_waiting = false
        add_command(row[0], row[1], row[2] if row.size() > 2 else "")
        _listed_rows[key(row[0])] = true


## One row for the registered command *command_id*, drawn from what the command
## says of itself: its menu words, its chord in the column at the row's right,
## its sentence, its tick and whether it can be pressed now.
##
## The chord is the row's hint rather than part of its label, which is where a
## menu has always drawn one and where type-ahead cannot match it. *label*, when
## given, takes the place of the command's own words on this row alone.
func add_command(item_id: int, command_id: StringName, label: String = "") -> void:
    var descriptor := _descriptor(command_id)
    if descriptor == null:
        return
    popup.add_row(
        key(item_id),
        tr(label if not label.is_empty() else descriptor.menu_label()),
        descriptor.has_tick(),
        descriptor.is_checked(),
        "",
        chord_of(command_id),
        not descriptor.is_enabled()
    )
    _clear_placeholder_tooltip(item_id)
    if not descriptor.sentence.is_empty():
        explain(item_id, descriptor.sentence)
    _command_rows[item_id] = command_id


## The command *command_id*, or null before a registry is bound and for one it
## does not hold.
func _descriptor(command_id: StringName) -> SaCommandDescriptor:
    return commands.get_descriptor(command_id) if commands != null else null


## The command behind the row *item_id*, or `&""` for a row of the menu's own.
func command_at(item_id: int) -> StringName:
    return _command_rows.get(item_id, &"")


## The command a press on *row_id* runs, a list row's or one a menu runs from
## its own row, which a menu that has such rows answers by overriding this.
## What a right click adds to Quick Favourites or assigns a chord to, what the
## search names a menu path for, and what Repeat Last keeps.
func row_command(row_id: StringName) -> StringName:
    return command_at(id_of(row_id))


## The list a right press on *row_id* opens beside it, Add to Quick Favourites
## and Assign Shortcut. Public, so a suite opens it without a pointer.
func ask_row(row_id: StringName) -> SaChoicePopup:
    var holder := list_holding(popup, row_id)
    return SaQuickCommands.offer(holder if holder != null else popup, row_id, row_command(row_id))


## Puts every command row's tick back to what its command says, without running
## anything. The state changed elsewhere and the rows are catching up.
func sync_ticks() -> void:
    for item_id: int in _command_rows:
        var descriptor := _descriptor(_command_rows[item_id])
        if descriptor != null and descriptor.has_tick():
            set_item_checked(item_id, descriptor.is_checked())


## The items, in order. A menu with nothing to offer yet leaves this alone.
func _add_items() -> void:
    pass


## What a click on the item with this id does: the command, for a row a list
## drew, and the menu's own answer for the rest.
##
## A group row's press is not answered here, since its submenu opens on the
## popup's `branched`, which a menu of its own may hear as well.
func on_id_pressed(id: int) -> void:
    if group_list(popup, id) != null:
        return
    var command_id := command_at(id)
    if command_id.is_empty():
        _pressed(id)
        SaQuickCommands.note_run(row_command(key(id)))
        return
    if commands != null:
        commands.execute(command_id)
        SaQuickCommands.note_run(command_id)
    sync_ticks()


## What a press on one of the menu's own rows does, the ones no list drew.
func _pressed(_id: int) -> void:
    pass


## Sara's main scene, or null for a popup outside the tree. The one walk to it
## every menu shares, so a menu that needs something main owns asks here rather
## than finding the scene for itself.
func main_scene() -> Node:
    return popup.get_tree().current_scene if in_tree() else null


## The front document's canvas, or null before there is one. A menu that
## changes pixels rather than state has to ask it to composite again.
func main_canvas() -> SaCanvas:
    return SaCanvasView.front_canvas() if in_tree() else null


## The document the main canvas shows, or null before there is one. What the
## Layer and Edit menus act on.
func main_document() -> SaDocument:
    var canvas := main_canvas()
    return canvas.document if canvas != null else null


## The human name of the module *module_id*, for a menu that groups its rows by
## who registered them.
##
## Answers *unattributed* for a registration nobody attributed, the module's own
## `get_name()` when it is loaded, and the id itself for one that is registered
## and not loaded through ModuleLoader, which is what a test fixture looks like.
##
## Here rather than on each menu. The Modules menu and the Filter menu both
## group by owner, both asked this question, and both answered it with the same
## six lines, which is how two menus start to disagree about what a module is
## called. It sits beside `main_canvas` and `main_document` because it is the
## same kind of question: something every menu may ask of the app around it,
## answered once.
##
## **The empty id is checked first**, which neither copy did.
## `SaModule.get_id()` answers `&""` by default, so a group nobody attributed
## would otherwise take the name of the first loaded module that never overrode
## it. No module in the tree leaves it at the default, so nothing drew the wrong
## name, and the guard is what keeps that an accident that cannot happen rather
## than one that has not happened yet.
func module_display_name(module_id: StringName, unattributed: String = "") -> String:
    if String(module_id).is_empty():
        return unattributed
    for folder_name: Variant in ModuleLoader.loaded_modules:
        var mod: SaModule = ModuleLoader.loaded_modules[folder_name]
        if mod.get_id() == module_id:
            return mod.get_name()
    return String(module_id)
