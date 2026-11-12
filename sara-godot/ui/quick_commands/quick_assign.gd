## Assign Shortcut, from a menu row's right click: a window says which command
## is listening, the next chord pressed goes to it in the profile in use through
## `SaShortcutStore`, and a chord another command holds is asked about first,
## naming that command, before it is taken from it. Blender's Assign Shortcut,
## on a menu item's right click, is the inspiration, and no code of Blender's
## is taken.
##
## **The question is the Keyboard Shortcuts page's**, in its words, "Ctrl+Z is
## already used by Undo. Use it for Redo instead?", so a painter meets one way
## of being asked whichever door they came in by. It has no Share answer: a
## chord assigned from a menu is the one the painter means that command to
## have, and two holders is what the page is for.
##
## **The chord replaces the command's own**, as Blender's Assign Shortcut does,
## and taking it from a holder leaves that holder whatever else it answered to.
## Escape leaves everything as it was. The edit is saved the way every rebind
## is, `SaShortcutStore.remember_edit`, which forks a shipped profile.
##
## A node under the window rather than a window of its own, because `SaMessage`
## already is the window every question in Sara is, and the capture is only the
## `_input` that hears the key before the window's buttons do. The router stands
## down while it listens, as it does for the page's capture.
class_name QuickAssign
extends Node

## The question's answers, in the order of its buttons.
const ANSWER_MOVE := 0
const ANSWER_CANCEL := 1

var command_id: StringName = &""
var commands: SaCommandRegistry = null
var filters: SaFilterRegistry = null
var tools: SaToolRegistry = null
## The node both windows open under.
var host: Node = null
## The window saying what is listening, while it is up.
var asking: SaMessage = null
## The question about a chord another command holds, once one was asked.
var question: SaMessage = null
## Whether a key has been heard, after which the node listens no more.
var _heard: bool = false


func _init(
    command: StringName,
    registry: SaCommandRegistry,
    filter_registry: SaFilterRegistry,
    tool_registry: SaToolRegistry,
    under: Node
) -> void:
    name = "QuickAssign"
    command_id = command
    commands = registry
    filters = filter_registry
    tools = tool_registry
    host = under


## Puts the window up under `host` and listens for the next chord. A chord
## already heard, which a suite sends to `hear` before the window is up, leaves
## nothing to listen for, and the node goes.
func listen() -> void:
    if _heard or host == null or not is_instance_valid(host):
        queue_free()
        return
    var words := SaShortcutRows.label_for(String(command_id), tools, filters, commands)
    var text := tr("Press the keys for %s. They replace its shortcut, and Escape leaves it as it is.") % words
    asking = SaMessage.confirm(host, tr("Assign Shortcut"), text, PackedStringArray([tr("Cancel")]), _on_asking_closed)
    asking.add_child(self)
    ShortcutRouter.capture_in_progress = true


func _input(event: InputEvent) -> void:
    var key := event as InputEventKey
    if _heard or key == null or not key.pressed or key.echo:
        return
    var viewport := get_viewport()
    if viewport != null:
        viewport.set_input_as_handled()
    if key.keycode in [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META]:
        # A modifier on its own is the painter still reaching for the key.
        return
    hear("" if key.keycode == KEY_ESCAPE else SaShortcutStore.chord_of_event(key))


## What the window does with the chord a key gave it, or with "" for Escape:
## it goes, taking this node with it, and the chord is offered. Public, so a
## suite sends a chord the way a key would. Answers the question when one was
## asked, and only the first chord is heard.
func hear(chord: String) -> SaMessage:
    if _heard:
        return null
    _heard = true
    ShortcutRouter.capture_in_progress = false
    if asking != null and is_instance_valid(asking):
        asking.queue_free()
    if chord.is_empty() or host == null or not is_instance_valid(host):
        return null
    question = offer(host, command_id, chord, commands, filters, tools)
    return question


## Cancel, the close button or Escape on the window itself.
func _on_asking_closed(_answer: int) -> void:
    _heard = true
    ShortcutRouter.capture_in_progress = false


## Gives *chord* to *command* at once when no other command holds it, and
## otherwise asks under *under* first, naming each holder. Answers the question,
## or null when nothing was asked. Static, so the answer still lands once the
## listening window and this node are gone.
static func offer(
    under: Node,
    command: StringName,
    chord: String,
    registry: SaCommandRegistry,
    filter_registry: SaFilterRegistry = null,
    tool_registry: SaToolRegistry = null
) -> SaMessage:
    if chord.is_empty():
        return null
    if SaShortcutStore.conflicts(chord, command).is_empty():
        take(command, chord, registry)
        return null
    var who := SaShortcutRows.listed(SaShortcutStore.holders(chord, command), tool_registry, filter_registry, registry)
    var mover := SaShortcutRows.label_for(String(command), tool_registry, filter_registry, registry)
    var text := TranslationServer.translate("%s is already used by %s. Use it for %s instead?") % [chord, who, mover]
    var labels := PackedStringArray([TranslationServer.translate("Use for %s") % mover, TranslationServer.translate("Cancel")])
    var title_text := TranslationServer.translate("%s is already used") % chord
    var answered := _on_answered.bind(command, chord, registry)
    return SaMessage.confirm(under, title_text, text, labels, answered, ANSWER_CANCEL, ANSWER_MOVE)


static func _on_answered(answer: int, command: StringName, chord: String, registry: SaCommandRegistry) -> void:
    if answer == ANSWER_MOVE:
        take(command, chord, registry)


## Takes *chord* off whatever else answers to it, gives it to *command* as its
## one chord, writes the map where the next launch finds it, and says so.
static func take(command: StringName, chord: String, registry: SaCommandRegistry) -> void:
    SaShortcutStore.release_chord(chord, command)
    SaShortcutStore.set_chords(command, [chord])
    SaShortcutStore.remember_edit()
    EventBus.shortcuts_changed.emit()
    var words := SaShortcutRows.label_for(String(command), null, null, registry)
    SaMessage.notice(TranslationServer.translate("%s is on %s now.") % [words, chord])
