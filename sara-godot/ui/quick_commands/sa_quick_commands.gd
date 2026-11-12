## Four habits a Blender hand brings, so every command is a few keys away
## rather than a trip through the bar: every command searched on F3, Quick
## Favourites on Shift+Q, Repeat Last on Shift+R, and Assign Shortcut on a menu
## row's right click. F3's search is the one search, `SaSearchWindow`, which
## registers F3's command and offers its rows through [method offer].
##
## Blender is the inspiration, each habit beside the Blender key it follows:
## Menu Search on F3, Quick Favourites on Q, on Shift+Q here because Q alone is
## the Pan tool, Repeat Last on Shift+R, and Assign Shortcut on a menu item's
## right click. The ideas are Blender's and no code of Blender's is taken.
##
## These four serve an experienced hand rather than more chords in the shipped
## map, which follows Krita's (`core/registry/shortcuts/shortcut_krita_table.gd`).
##
## **Static, like the commands it registers.** There is one Sara and one
## painter, the registries are held weakly for the cycle `SaFilterAgain` gives
## the same answer for, and the last command run is kept for the run the way
## Apply Again keeps its filter. The registries rather than the context,
## because `SaAppCommands` registers on a context scoped to the skeleton that
## nothing keeps once it has registered.
##
## Two files beside this one, each owning one thing: `QuickFavourites` the list
## kept with the profile, and `QuickAssign` the chord a right click listens for.
class_name SaQuickCommands
extends RefCounted

## F3's command, which `SaSearchWindow` registers, named here because Repeat
## Last never repeats it and the Edit menu draws it.
const SEARCH := &"edit_search_commands"
const FAVOURITES := &"edit_quick_favourites"
const REPEAT := &"edit_repeat_last"

## Never the last command. Undo and redo step through what was done rather
## than doing something, which is why Blender leaves them out as well, and the
## three here only reach other commands.
const NOT_REPEATED: Array[StringName] = [&"edit_undo", &"edit_redo", &"ui_undo", &"ui_redo", SEARCH, FAVOURITES, REPEAT]

## The rows of the list a right press on a menu row opens.
const ROW_ADD := &"quick_add"
const ROW_REMOVE := &"quick_remove"
const ROW_ASSIGN := &"quick_assign"

## The registries the commands were registered on.
static var _held: Held = null
## The last command a menu, a chord, the search or a favourite ran, which
## Repeat Last runs, or `&""` before any. Written here alone.
static var last_run: StringName = &""
## What runs [member last_run] again when it is no registered command, as the
## four older docker toggles, Tab, the colour pair, the brush size steps and a
## tool's key are not: the chord sent through the router once more, or the
## Window menu's row pressed once more. Empty while the last is a command.
static var _again: Callable = Callable()
## The favourites list on screen, so a second press replaces it.
static var _open: SaChoicePopup = null
## The assignment waiting for its chord, while one is, which a suite sends the
## chord to. Written here alone.
static var assigning: QuickAssign = null


## The registries the three commands answer from, each held weakly, because
## they hold the commands whose handlers hold this.
class Held:
    extends RefCounted

    var _commands: WeakRef = null
    var _filters: WeakRef = null
    var _tools: WeakRef = null

    func _init(ctx: SaContext) -> void:
        _commands = weakref(ctx.commands) if ctx.commands != null else null
        _filters = weakref(ctx.filters) if ctx.filters != null else null
        _tools = weakref(ctx.tools) if ctx.tools != null else null

    ## The command registry, or null once it was freed.
    func commands() -> SaCommandRegistry:
        return _commands.get_ref() as SaCommandRegistry if _commands != null else null

    ## The filter registry, or null.
    func filters() -> SaFilterRegistry:
        return _filters.get_ref() as SaFilterRegistry if _filters != null else null

    ## The tool registry, or null.
    func tools() -> SaToolRegistry:
        return _tools.get_ref() as SaToolRegistry if _tools != null else null


## The Menu key on a list's highlighted row, which opens what a right press on
## that row opens, so a painter working a menu from the keys reaches Add to
## Quick Favourites and Assign Shortcut without the pointer. It is also the one
## way a scenario reaches them, because an injected click does not route into a
## choice list's window (`harness/drivers/menu_choice.gd` says so).
##
## A node inside the list rather than a handler on it, because the list's own
## `_input` lets a key it has no use for go on, and an unhandled key is what a
## node of the list's window is offered next.
class RowKey:
    extends Node

    const NODE_NAME := &"QuickRowKey"

    var _list: SaChoicePopup = null
    var _command_of: Callable

    func _init(list: SaChoicePopup, command_of: Callable) -> void:
        name = NODE_NAME
        _list = list
        _command_of = command_of

    func _unhandled_key_input(event: InputEvent) -> void:
        var key := event as InputEventKey
        if key == null or not key.pressed or key.echo or key.keycode != KEY_MENU:
            return
        var row_id := _list.highlighted()
        if row_id.is_empty() or not _list.visible:
            return
        get_viewport().set_input_as_handled()
        SaQuickCommands.offer(_list, row_id, StringName(_command_of.call(row_id)))


## Registers Quick Favourites and Repeat Last on *ctx* and forgets the last command, since a
## fresh registry has run nothing.
static func register(ctx: SaContext) -> void:
    var held := Held.new(ctx)
    _held = held
    last_run = &""
    _again = Callable()
    var kept := SaCommandDescriptor.create(FAVOURITES, "Open the quick favourites", _favourites_in.bind(held))
    kept.label = "Quick Favourites..."
    kept.sentence = "Open the commands you added from a menu row's right click, at the pointer."
    kept.default_events = [_chord(KEY_Q, true)]
    var repeat := SaCommandDescriptor.create(REPEAT, "Repeat the last command", _repeat_in.bind(held))
    repeat.label = "Repeat Last"
    repeat.sentence = "Run the last command again, a filter with its last settings. Undo and redo are never the last command."
    repeat.default_events = [_chord(KEY_R, true)]
    repeat.enabled = can_repeat
    for command: SaCommandDescriptor in [kept, repeat]:
        command.category = &"edit"
        ctx.register_command(command)


static func _chord(keycode: Key, shift: bool) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.shift_pressed = shift
    return event


# --- Repeat Last ---------------------------------------------------------------


## Keeps *command_id* as the last command, which a menu row, a chord, the search
## and a favourite all call once they ran one. A filter is kept as Apply Again,
## so repeating it runs it with its last settings and no dialog, and undo, redo
## and the three here are never kept.
##
## *again* runs an id that is no registered command a second time, and without
## it such an id is not kept. The router answers a few chords outside the
## command registry, Shift+B for the Toolbox among them, and Repeat Last once
## dropped every one of those because the registry did not hold the id.
static func note_run(command_id: StringName, again: Callable = Callable()) -> void:
    var commands := _commands()
    if commands == null or command_id.is_empty() or NOT_REPEATED.has(command_id):
        return
    if commands.has(command_id):
        last_run = SaFilterAgain.COMMAND if _is_filter(command_id) else command_id
        _again = Callable()
    elif again.is_valid():
        last_run = command_id
        _again = again
        _release_at_exit()


## Lets *again* go when the root leaves the tree. A static is dropped after the
## engine's servers, and a Callable with a bound press freed then ends the run
## on a corrupt heap, as with every such static.
static func _release_at_exit() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null and not tree.root.tree_exiting.is_connected(release):
        tree.root.tree_exiting.connect(release)


## Forgets the press Repeat Last would send again, and the command with it.
static func release() -> void:
    _again = Callable()
    last_run = &""


## A press on a row of the Window menu's docker list, which toggles a docker or
## every docker without going through a command, kept as the last command the
## way its chord is. *row_id* is `docker_<index>` into *dockers*, the dockers'
## table, or the Focus Mode row, which is what Tab does.
static func note_docker_row(row_id: StringName, dockers: Array, toggle: Callable, toggle_all: Callable) -> void:
    var text := String(row_id)
    if not text.begins_with("docker_"):
        note_run(&"toggle_dockers", toggle_all)
        return
    var index := int(text.trim_prefix("docker_"))
    if index >= 0 and index < dockers.size():
        note_run(StringName(dockers[index].get("shortcut", "")), toggle.bind(index))


## Whether there is a command to repeat, which dims the Edit menu's row.
static func can_repeat() -> bool:
    var commands := _commands()
    if last_run.is_empty() or commands == null:
        return false
    return commands.has(last_run) or _again.is_valid()


## Runs the last command again, or says in the corner why nothing ran.
static func repeat_last() -> bool:
    if not can_repeat():
        SaMessage.notice(TranslationServer.translate("Nothing to repeat yet."))
        return true
    if not _commands().has(last_run):
        _again.call()
        return true
    var descriptor := _commands().get_descriptor(last_run)
    if not descriptor.is_enabled():
        SaMessage.notice(TranslationServer.translate("%s cannot run now.") % TranslationServer.translate(descriptor.menu_label()))
        return true
    _commands().execute(last_run)
    return true


## Runs *command_id* as a menu row would and keeps it as the last command. What
## a search row and a favourite do, and false for a dimmed command, which does
## not run.
static func run(command_id: StringName) -> bool:
    var commands := _commands()
    var descriptor := commands.get_descriptor(command_id) if commands != null else null
    if descriptor == null or not descriptor.is_enabled():
        return false
    var ran := commands.execute(command_id)
    note_run(command_id)
    return ran


static func _is_filter(command_id: StringName) -> bool:
    var filters := _filters()
    if filters == null:
        return false
    for key: StringName in filters.list_keys():
        if SaFilterRegistry.command_for(key, filters.get_filter(key)) == command_id:
            return true
    return false


# --- The favourites ------------------------------------------------------------


## The Quick Favourites list, filled and not yet opened.
static func favourites_list() -> SaChoicePopup:
    var list := SaChoicePopup.new(true, false)
    list.name = "QuickFavourites"
    QuickFavourites.fill(list, _commands())
    _connect(list)
    return list


## A row runs its command, and a right press on one offers what a menu row's
## does, Remove from Quick Favourites among it.
static func _connect(list: SaChoicePopup) -> void:
    list.chosen.connect(run)
    watch(list, func(row_id: StringName) -> StringName: return row_id)


## The commands kept in Quick Favourites, in the order they were added.
static func favourites() -> Array[StringName]:
    return QuickFavourites.listed()


## Opens *list* at the pointer, in place of the one open before.
static func _open_at_pointer(list: SaChoicePopup) -> SaChoicePopup:
    var host := _host()
    if host == null:
        list.free()
        return null
    if _open != null and is_instance_valid(_open):
        _open.queue_free()
    # Freed when the next one opens rather than when it hides, because Escape
    # in a list's field hides the list and opens it again with the field cleared.
    _open = list
    host.add_child(list)
    SaUI.apply_to_window(list)
    var at := host.get_viewport().get_mouse_position()
    var window := host.get_window()
    var spot := Vector2i(at)
    if not list.is_embedded() and window != null:
        # A native popup is placed on the screen, in physical pixels.
        spot = window.position + Vector2i(at * window.content_scale_factor)
    var factor := list.content_scale_factor
    var wanted := Vector2i((Vector2(list.wanted_size(0.0)) * factor).round())
    var room := SaPopupRect.room_for(list)
    if room.has_area():
        spot.x = clampi(spot.x, room.position.x, maxi(room.position.x, room.end.x - wanted.x))
        spot.y = clampi(spot.y, room.position.y, maxi(room.position.y, room.end.y - wanted.y))
    list.popup(Rect2i(spot, wanted))
    if list.search.visible:
        list.search.call_deferred("grab_focus")
    return list


## Deferred, for the reason `SaAppCommands` gives its Preferences: a chord
## pressed over an open menu arrives while that popup is mid-hide, and a window
## opened from inside it upsets the engine's popup bookkeeping.
static func _favourites_in(held: Held) -> bool:
    _held = held
    _open_favourites.call_deferred()
    return true


static func _open_favourites() -> void:
    _open_at_pointer(favourites_list())


static func _repeat_in(held: Held) -> bool:
    _held = held
    return repeat_last()


# --- A menu row's right click ---------------------------------------------------


## Makes a right press on any of *list*'s rows open `offer` beside it, for the
## command *command_of* answers for the row, and so does the Menu key on the
## highlighted row. Every menu under the bar calls it as it is filled, and so
## does the Shift+Q list here. The search calls it once for the Menu key, and
## its rows, drawn a page at a time, connect their right press themselves. The
## rows are new on every fill and the key's node is not, since `clear` frees the
## rows alone, so the node is added once.
static func watch(list: SaChoicePopup, command_of: Callable) -> void:
    for row_id: StringName in list.row_ids():
        var button := list.label_button(row_id)
        if button != null and not button.gui_input.is_connected(_on_row_input.bind(list, row_id, command_of)):
            button.gui_input.connect(_on_row_input.bind(list, row_id, command_of))
    if list.get_node_or_null(NodePath(RowKey.NODE_NAME)) == null:
        list.add_child(RowKey.new(list, command_of))


static func _on_row_input(event: InputEvent, list: SaChoicePopup, row_id: StringName, command_of: Callable) -> void:
    var press := event as InputEventMouseButton
    if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_RIGHT:
        return
    var button := list.label_button(row_id)
    if button != null:
        button.accept_event()
    offer(list, row_id, StringName(command_of.call(row_id)))


## The list a right press on *row_id* of *menu* opens beside it: the row's
## command added to Quick Favourites or taken off them, and Assign Shortcut.
## Both are dimmed on a row no command stands behind, a recent file or a
## layout, since there is nothing to keep or to bind. Answers the list, which is
## filled whether or not the menu is on screen, so a suite presses its rows.
static func offer(menu: SaChoicePopup, row_id: StringName, command_id: StringName) -> SaChoicePopup:
    if menu == null:
        return null
    var commands := _commands()
    var none := command_id.is_empty() or commands == null or not commands.has(command_id)
    var list := SaChoicePopup.new(true, false)
    list.name = "QuickRowMenu"
    if not none and QuickFavourites.listed().has(command_id):
        list.add_row(ROW_REMOVE, list.tr("Remove from Quick Favourites"))
    else:
        list.add_row(ROW_ADD, list.tr("Add to Quick Favourites"), false, false, "", "", none)
    list.add_row(ROW_ASSIGN, list.tr("Assign Shortcut..."), false, false, "", "", none)
    list.chosen.connect(_on_offer_chosen.bind(command_id))
    list.popup_hide.connect(list.queue_free, CONNECT_DEFERRED)
    menu.open_child(list, row_id)
    return list


static func _on_offer_chosen(row: StringName, command_id: StringName) -> void:
    var words := _words(command_id)
    match row:
        ROW_ADD:
            if QuickFavourites.add(command_id):
                SaMessage.notice(TranslationServer.translate("%s is in Quick Favourites, on Shift+Q.") % words)
        ROW_REMOVE:
            if QuickFavourites.remove(command_id):
                SaMessage.notice(TranslationServer.translate("%s left Quick Favourites.") % words)
        ROW_ASSIGN:
            assign(command_id)


## Starts listening for the next chord for *command_id*, and answers the
## listener. Its window opens a frame later, for the reason `_favourites_in` gives:
## the row that asked is mid-hide when this runs.
static func assign(command_id: StringName) -> QuickAssign:
    var host := _host()
    var commands := _commands()
    if host == null or commands == null or not commands.has(command_id):
        return null
    assigning = QuickAssign.new(command_id, commands, _filters(), _held.tools(), host)
    assigning.listen.call_deferred()
    return assigning


static func _words(command_id: StringName) -> String:
    var commands := _commands()
    var descriptor := commands.get_descriptor(command_id) if commands != null else null
    return String(TranslationServer.translate(descriptor.menu_label())) if descriptor != null else String(command_id)


# --- Where things are -----------------------------------------------------------


static func _commands() -> SaCommandRegistry:
    return _held.commands() if _held != null else null


static func _filters() -> SaFilterRegistry:
    return _held.filters() if _held != null else null


## The node the lists open under: the main window's scene, or the root.
static func _host() -> Node:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return null
    return tree.current_scene if tree.current_scene != null else tree.root
