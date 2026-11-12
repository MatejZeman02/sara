## Named commands with shortcuts, so a module's command gets a working chord
## the way a built-in does, where ShortcutRouter's if-chain was skeleton-only.
class_name SaCommandRegistry
extends RefCounted

signal changed

## The command the last [method try_handle_input] ran, or answered with the
## corner line for its hidden docker, which is how the shortcut router names a
## chord to the usage tally. Read only after a true answer.
var last_command: StringName = &""

var _commands: Dictionary[StringName, SaCommandDescriptor] = {}
var _order: Array[StringName] = []
## Recomputed on change so dispatch does not sort per input event.
var _dispatch_order: Array = []

## How many `batch` calls are running, and whether anything changed inside
## them that has not been announced yet.
var _batches: int = 0
var _held_change: bool = false
## The commands `execute` has reported a dead handler for, so each says so once.
var _reported_dead: Dictionary[StringName, bool] = {}
## The registered dockers, asked whether the one a command acts in is showing.
## Null in a registry built alone, whose commands all run as they always did.
var _dockers: SaUIRegistry = null


func _init(dockers: SaUIRegistry = null) -> void:
    _dockers = dockers


func register(descriptor: SaCommandDescriptor, module_id: StringName = &"") -> bool:
    if descriptor == null or String(descriptor.id).is_empty():
        push_error("SaCommandRegistry: refusing a command with no id.")
        return false
    if _commands.has(descriptor.id):
        push_error("SaCommandRegistry: command '%s' is already registered." % descriptor.id)
        return false

    descriptor.owner_module = module_id
    _commands[descriptor.id] = descriptor
    _reported_dead.erase(descriptor.id)
    _order.append(descriptor.id)
    _ensure_action(descriptor)
    _announce()
    return true


## Removes one command, whoever registered it, so a module can take a
## built-in away. Its InputMap action stays, because another command may
## name the same one and an action with nothing behind it is harmless.
func unregister(command_id: StringName) -> void:
    if not _commands.has(command_id):
        return
    _commands.erase(command_id)
    _order.erase(command_id)
    _announce()


func unregister_module(module_id: StringName) -> void:
    var doomed: Array[StringName] = []
    for command_id: StringName in _order:
        if _commands[command_id].owner_module == module_id:
            doomed.append(command_id)
    for command_id in doomed:
        _commands.erase(command_id)
        _order.erase(command_id)
    if not doomed.is_empty():
        _announce()


## Runs *work*, and announces what it registered and removed once, after it,
## rather than once a command. Every bound menu repopulates on `changed`, so an
## announcement a command would cost a boot whole seconds. The dispatch order is
## rebuilt with the announcement, and nothing dispatches inside a batch, because
## *work* runs to its end first.
func batch(work: Callable) -> void:
    _batches += 1
    work.call()
    _batches -= 1
    if _batches == 0 and _held_change:
        _held_change = false
        _announce()


## The dispatch order rebuilt and `changed` emitted, or both held for the end
## of the batch running now.
func _announce() -> void:
    if _batches > 0:
        _held_change = true
        return
    _rebuild_dispatch_order()
    changed.emit()


func has(command_id: StringName) -> bool:
    return _commands.has(command_id)


func get_descriptor(command_id: StringName) -> SaCommandDescriptor:
    return _commands.get(command_id, null)


func list_ids() -> Array[StringName]:
    return _order.duplicate()


## The chord *command_id* answers to right now, as "Ctrl+Shift+G", or "" when
## it has none. `limit` is `format_events`' own, so a menu row asks for one.
##
## Read from the InputMap rather than from the descriptor, because that is what
## a rebind writes and what the app actually answers to. A command whose action
## was never created falls back to what it shipped with, so a registry built
## without an InputMap still says the chord.
func chord_text(command_id: StringName, limit: int = 0) -> String:
    var descriptor: SaCommandDescriptor = _commands.get(command_id, null)
    if descriptor == null:
        return ""
    var action := descriptor.action
    if not String(action).is_empty() and InputMap.has_action(action):
        return format_events(InputMap.action_get_events(action), limit)
    return format_events(descriptor.default_events, limit)


## The chord a menu row of *command_id* shows: its own, and with none, the
## chord of a command whose `shows_on` names it, which is the key that runs it
## from that row's point of view. `chord_text` stays what the command itself
## answers, which the clash checks and the Shortcuts page read.
func shown_chord(command_id: StringName, limit: int = 0) -> String:
    var own := chord_text(command_id, limit)
    if not own.is_empty() or not _commands.has(command_id):
        return own
    for other_id: StringName in _order:
        if _commands[other_id].shows_on.has(command_id):
            return chord_text(other_id, limit)
    return ""


## True when the command answers to at least one key.
func has_chord(command_id: StringName) -> bool:
    return not chord_text(command_id).is_empty()


## The keys a painter names by the glyph on them, or by the word the Shortcuts
## page uses, rather than by Godot's word for them, keycode -> name.
##
## Godot spells both bracket keys "BracketLeft" and "BracketRight", the top
## row's equals and plus "Equal" and "Plus", and a numpad key "Kp Add" or
## "Kp 5", so zoom in read "Ctrl+Equal, Ctrl+Plus, Ctrl+Kp Add" on its menu row
## while the Shortcuts page said "Numpad" for the same key. One table here is
## what both of them and the stored profile read, so the two cannot drift. The
## rest of Sara's chords are letters and named keys, which already read as
## themselves.
##
## The comma, the full stop, the slash, the semicolon and the apostrophe joined
## when the Keyboard Shortcuts page spelt Preferences "Ctrl+Comma" and the zoom
## "Ctrl+=". The backslash stays a word: a bare "\"
## reads as nothing in `SaShortcutStore.parse_chord`, as
## `core/registry/tests/test_krita_profile.gd` holds, and a glyph here is what
## that function looks a key's name up in.
const KEY_GLYPHS: Dictionary[int, String] = {
    KEY_BRACKETLEFT: "[",
    KEY_BRACKETRIGHT: "]",
    KEY_EQUAL: "=",
    KEY_PLUS: "+",
    KEY_MINUS: "-",
    KEY_COMMA: ",",
    KEY_PERIOD: ".",
    KEY_SLASH: "/",
    KEY_SEMICOLON: ";",
    KEY_APOSTROPHE: "'",
    KEY_KP_0: "Numpad 0",
    KEY_KP_1: "Numpad 1",
    KEY_KP_2: "Numpad 2",
    KEY_KP_3: "Numpad 3",
    KEY_KP_4: "Numpad 4",
    KEY_KP_5: "Numpad 5",
    KEY_KP_6: "Numpad 6",
    KEY_KP_7: "Numpad 7",
    KEY_KP_8: "Numpad 8",
    KEY_KP_9: "Numpad 9",
    KEY_KP_ADD: "Numpad +",
    KEY_KP_SUBTRACT: "Numpad -",
    KEY_KP_MULTIPLY: "Numpad *",
    KEY_KP_DIVIDE: "Numpad /",
    KEY_KP_PERIOD: "Numpad .",
    KEY_KP_ENTER: "Numpad Enter",
}


## Where the key's name starts in a chord's text, so "Ctrl+" is the modifiers
## and what follows is the key.
##
## After the last "+", except when the key is the plus key itself: "Ctrl++" and
## "Numpad +" end in one, and the key there is "+" or "Numpad +" and not "".
static func key_name_at(chord: String) -> int:
    if chord.ends_with("+") and (chord.length() == 1 or chord.ends_with("++") or chord.ends_with(" +")):
        var before := chord.substr(0, chord.length() - 1)
        if before.ends_with(" "):
            # "Numpad +", whose name holds a space and a plus of its own.
            return before.rfind("+", before.length() - 2) + 1
        return chord.length() - 1
    return chord.rfind("+") + 1


## "Ctrl+D", or "Ctrl+Z, Ctrl+Shift+Z" when a command answers to more than one.
##
## Static, because the toolbox tooltip and the shortcuts dialog ask the same
## question about a tool's action, which is in the InputMap and not here.
##
## `limit` caps how many are named, because a place with one line to spend
## wants the first rather than all of them: zoom in answers the top row's
## equals, its plus and the keypad's, and the full sentence is wider than the
## shortcuts dialog, which pushed the whole key column off the right edge.
static func format_events(events: Array, limit: int = 0) -> String:
    var out: PackedStringArray = PackedStringArray()
    for event: InputEvent in events:
        if limit > 0 and out.size() >= limit:
            break
        var key := event as InputEventKey
        if key == null:
            if event is InputEventMouseButton:
                out.append(event.as_text())
            continue
        out.append(key_text(key))
    return ", ".join(out)


## One key event as a painter reads it, modifiers included.
##
## project.godot binds most keys by physical keycode, and the keycode text of
## such an event reads "(unset)", so which of the two is asked depends on the
## event rather than on the caller.
static func key_text(key: InputEventKey) -> String:
    var text := key.as_text_keycode() if key.keycode != KEY_NONE else key.as_text_physical_keycode()
    var code: int = key.keycode if key.keycode != KEY_NONE else key.physical_keycode
    if not KEY_GLYPHS.has(code):
        return text
    # Only the key name is respelled. It is whatever follows the last "+", so
    # "Ctrl+BracketLeft" keeps its modifier and becomes "Ctrl+[".
    var cut := text.rfind("+")
    return text.substr(0, cut + 1) + String(KEY_GLYPHS[code])


## The commands a module asked to have in the Modules menu, grouped by the module
## that owns them, as { module_id -> Array[SaCommandDescriptor] }.
##
## Registration order within a module, which is the order the module wrote them
## in and therefore the order it meant. Nothing is sorted alphabetically: a menu
## a module author cannot control the order of is a menu they will work around.
func list_menu_commands() -> Dictionary[StringName, Array]:
    var grouped: Dictionary[StringName, Array] = {}
    for command_id: StringName in _order:
        var descriptor: SaCommandDescriptor = _commands[command_id]
        if not descriptor.show_in_modules_menu:
            continue
        if not grouped.has(descriptor.owner_module):
            grouped[descriptor.owner_module] = []
        grouped[descriptor.owner_module].append(descriptor)
    return grouped


## The commands that asked for the Help menu, in registration order, for the
## reason [method list_menu_commands] keeps it.
func list_help_commands() -> Array[SaCommandDescriptor]:
    var out: Array[SaCommandDescriptor] = []
    for command_id: StringName in _order:
        var descriptor: SaCommandDescriptor = _commands[command_id]
        if descriptor.show_in_help_menu:
            out.append(descriptor)
    return out


## The commands that asked for the Select menu, in registration order, for the
## reason [method list_menu_commands] keeps it.
func list_select_commands() -> Array[SaCommandDescriptor]:
    var out: Array[SaCommandDescriptor] = []
    for command_id: StringName in _order:
        var descriptor: SaCommandDescriptor = _commands[command_id]
        if descriptor.show_in_select_menu:
            out.append(descriptor)
    return out


## A row of the search for every command in registration order, less those
## whose `show_in_search` is off. A command a filter, a docker or a tool stands
## for is listed as that thing, which the search does since its row covers the
## command. The place is left to the search, which knows the menus.
func search_rows() -> Array[SaSearchRegistry.Row]:
    var out: Array[SaSearchRegistry.Row] = []
    for command_id: StringName in _order:
        var descriptor: SaCommandDescriptor = _commands[command_id]
        if not descriptor.show_in_search:
            continue
        var named := tr(descriptor.title if not descriptor.title.is_empty() else String(command_id))
        var said := "%s %s" % [descriptor.label, descriptor.sentence]
        var kind := SaSearchRegistry.COMMAND
        out.append(SaSearchRegistry.Row.new(kind, named, "", Callable(), command_id, said, true, &"", command_id))
    return out


## The commands that asked for the canvas right-click menu, in registration
## order, for the same reason the Modules menu keeps it, less those whose
## `context_when` answers that the menu is not theirs now.
func list_context_commands() -> Array:
    var out: Array = []
    for command_id: StringName in _order:
        var descriptor: SaCommandDescriptor = _commands[command_id]
        var wanted := not descriptor.context_when.is_valid() or SaTyped.flag(descriptor.context_when.call())
        if descriptor.show_in_context_menu and wanted:
            out.append(descriptor)
    return out


## Runs a command by id regardless of input, so a menu item and a shortcut share
## one implementation.
##
## A handler whose object was freed says so once, so a dead menu is never
## silent. A missing command may be an unloaded module's, so is silent.
##
## The trail names the command while its handler runs, and its return gives
## back the place before it, here and in `try_handle_input`, so a stall long
## after names where Sara is rather than the last command it ran.
func execute(command_id: StringName) -> bool:
    var descriptor: SaCommandDescriptor = _commands.get(command_id, null)
    if descriptor == null:
        return false
    if not descriptor.handler.is_valid():
        if not _reported_dead.has(command_id):
            _reported_dead[command_id] = true
            var line := "SaCommandRegistry: command '%s' of '%s' lost its handler's object, so it does nothing."
            push_error(line % [command_id, descriptor.owner_module])
        return false
    var ticket := SaTrail.enter("the command %s" % command_id)
    var result: Variant = descriptor.handler.call()
    SaTrail.give_back(ticket)
    if result == null:
        return true
    var consumed: bool = result
    return consumed


## Offers the event to every command in priority order. Returns true once one
## consumes it, so ShortcutRouter.handle() has no table of its own.
##
## **A command whose docker is hidden runs nothing and says why.** Here rather
## than in each command's own handler, where a docker shut would answer its
## chord with silence and every docker command would write the same check. Here
## once, any command that names its docker gets the corner line, a module's
## included. The chord is consumed, so it does not travel on to a command the
## painter did not mean.
func try_handle_input(event: InputEvent) -> bool:
    for descriptor: SaCommandDescriptor in _dispatch_order:
        var action := descriptor.action
        if String(action).is_empty() or not InputMap.has_action(action):
            continue
        if not event.is_action_pressed(action, descriptor.allow_echo, descriptor.exact_match):
            continue
        if not descriptor.handler.is_valid():
            continue
        last_command = descriptor.id
        if _docker_hidden(descriptor):
            EventBus.corner_notice.emit(_hidden_docker_line(descriptor, event))
            return true
        var ticket := SaTrail.enter("the command %s" % descriptor.id)
        var result: Variant = descriptor.handler.call()
        SaTrail.give_back(ticket)
        # A handler returning false declines the event, so a later command can
        # take it (undo with an empty history must not swallow the keypress).
        if result == null:
            return true
        var consumed: bool = result
        if consumed:
            return true
    return false


## True when *descriptor* names a registered docker that is not on screen, one
## Tab hid and one whose window is not built yet included. A docker that was
## never registered is left to the handler, since nothing could say how to show
## it.
func _docker_hidden(descriptor: SaCommandDescriptor) -> bool:
    if String(descriptor.docker).is_empty() or _dockers == null or not _dockers.has_docker(descriptor.docker):
        return false
    var node: Variant = _dockers.get_docker_entry(descriptor.docker).get("node")
    if not is_instance_valid(node) or not node is Window:
        return true
    var window: Window = node
    return not window.visible


## The corner's line for *descriptor*'s chord pressed while its docker is
## hidden: the chord as pressed and the command it would run, then the
## docker's own chord as the painter's profile binds it, or the Window menu
## when it has none.
##
## The command is named by its title, the short phrase the Keyboard Shortcuts
## page lists it by, in one whole sentence. The menu row's sentence lowered
## after "would" read in English only, and lowering a translated sentence
## breaks a language whose nouns keep their capitals and a name at its start.
func _hidden_docker_line(descriptor: SaCommandDescriptor, event: InputEvent) -> String:
    var pressed := format_events([event], 1)
    if pressed.is_empty():
        pressed = chord_text(descriptor.id, 1)
    var does := tr('%s would run "%s".') % [pressed, tr(descriptor.title)]
    var entry := _dockers.get_docker_entry(descriptor.docker)
    var docker_title: String = entry.get("title", "")
    var title := tr(docker_title)
    var toggle: StringName = entry.get("shortcut", &"")
    var toggle_chord := ""
    if not String(toggle).is_empty() and InputMap.has_action(toggle):
        toggle_chord = format_events(InputMap.action_get_events(toggle), 1)
    # A shipped docker's line is a whole sentence, so a language with cases can
    # decline its name. A module's own docker reads the generic one.
    if toggle_chord.is_empty():
        if SaWholeSentences.DOCKER_FIRST_MENU.has(docker_title):
            return "%s %s" % [does, tr(SaWholeSentences.DOCKER_FIRST_MENU[docker_title])]
        return "%s %s" % [does, tr("Show the %s docker first, from the Window menu.") % title]
    if SaWholeSentences.DOCKER_FIRST_CHORD.has(docker_title):
        return "%s %s" % [does, tr(SaWholeSentences.DOCKER_FIRST_CHORD[docker_title]) % toggle_chord]
    return "%s %s" % [does, tr("Show the %s docker first (%s).") % [title, toggle_chord]]


## Creates the InputMap action from `default_events` when it is missing, which is
## what lets a third-party command ship a working shortcut on a fresh install.
## An action the user already has is never overwritten.
##
## **A command that ships no chord gets its action all the same**, empty. Every
## surface that lists a bindable thing reads the InputMap, so a command with no
## action was one the Keyboard Shortcuts page could not show and nobody could
## give a key to: it could be reached from a menu and from nowhere else, for the
## life of the install. An action with no events matches no input, so nothing is
## dispatched by adding it, and `SaShortcutStore.remember_shipped` records the
## empty chord list, which is what makes Reset put it back to unbound rather
## than to whatever a painter last tried.
func _ensure_action(descriptor: SaCommandDescriptor) -> void:
    var action := descriptor.action
    if String(action).is_empty():
        return
    if InputMap.has_action(action):
        # Deliberately not recorded here. An action that already exists may have
        # been rebound since, and reading its chords now would promote a
        # painter's override to a default. `project.godot` binds it, so the
        # sweep in `SaShortcutStore.capture_defaults` has it or will. The one
        # exception is an action a saved profile created before this command
        # registered, which the sweep never saw: the command's own events are
        # what the build ships for it, and the store records them only then.
        SaShortcutStore.remember_shipped_events(action, descriptor.default_events)
        return
    InputMap.add_action(action)
    for event: InputEvent in descriptor.default_events:
        InputMap.action_add_event(action, event)
    # The moment the build's own chords are on the action and nothing has been
    # laid over them, which is the only moment the shipped map can be read from
    # a command registered after `SaShortcutStore.capture_defaults` swept the
    # InputMap. Without it such an action was in no shipped map at all: every
    # profile a painter saved wrote its ordinary chord down as an override, and
    # switching profiles never put it back.
    SaShortcutStore.remember_shipped(action)


func _rebuild_dispatch_order() -> void:
    _dispatch_order.clear()
    for command_id in _order:
        _dispatch_order.append(_commands[command_id])
    _dispatch_order.sort_custom(func(a: SaCommandDescriptor, b: SaCommandDescriptor) -> bool: return a.priority > b.priority)
