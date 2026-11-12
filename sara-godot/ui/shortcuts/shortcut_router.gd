## Routes key events to application-level actions.
##
## Every window in the app funnels key events here, the main window through
## _unhandled_input, and every other window through its own window_input signal,
## so a shortcut works regardless of which window has focus. `watch_windows()`
## is what subscribes to those signals, so a window nobody in Sara builds is
## wired too: a dropdown's popup belongs to the OptionButton that owns it.
##
## What a chord does is asked of SaCommandRegistry (below) and of the tool
## registry's own activate_action rather than mapped here, so a module gets a
## working shortcut without editing this file.
extends Node

class_name ShortcutRouter

## Brush radius is a fraction of the canvas's smaller dimension. The bounds live
## on ToolMachine, which also owns the shift-drag resize, so the keys and the
## drag cannot clamp to different sizes.
const BRUSH_RADIUS_STEP: float = 0.002

## The registered commands and their chords, tried after everything the router
## does itself, so a module's shortcut and the skeleton's own commands fire from
## the keyboard. Set through
## `bind_commands()`, which also puts the router's own chords in there.
var commands: SaCommandRegistry = null

## Collaborators, injected rather than reached for, so this can be tested without
## building the whole application tree.
var tool_machine_provider: Callable = Callable()  # () -> ToolMachine
var canvas_provider: Callable = Callable()  # () -> SaCanvas
var dockers_provider: Callable = Callable()  # () -> Array[Dictionary]
var toggle_docker: Callable = Callable()  # (index: int) -> void
var toggle_all_dockers: Callable = Callable()  # () -> void
## () -> void. Quitting goes through main, so a modified document gets its
## prompt. Without one the router quits outright, which is what a test wants.
var request_quit: Callable = Callable()
## (action: StringName) -> void. The File menu's chords. They are also on the
## menu items as global shortcuts, which the MenuBar honours only for input in
## the root viewport: with embedded subwindows a focused docker takes every key,
## so Ctrl+S over the Layers docker reached nothing. Every window already
## forwards its keys here, so here is where the chord has to be read.
var file_command: Callable = Callable()
## The summon Escape sends a pop-up back through, null where no docker is out.
var summon: DockerSummon = null

## The File menu actions, which the input map holds.
const FILE_ACTIONS: Array[String] = ["file_new", "file_open", "file_save", "file_save_as"]
## The instance ids of the windows already subscribed to, so a docker that is
## reparented into another host does not end up feeding this twice. Each holds
## the `ChordGate` put in that window, which goes when the router does.
var _watched: Dictionary = {}

## The commands this router registers and the handlers behind them, in
## `shortcut_commands.gd`. Built by `bind_commands()`, because what they act on
## is found through the providers above, which the host sets after `new()`.
var _commands: SaShortcutCommands = null

## True while a Keyboard Shortcuts row is waiting for the key that becomes its
## chord. Every entry point below stands down, because a window emits
## `window_input` before it pushes the event into its own tree, so otherwise the
## router would see Ctrl+N first and open a document, and the row would record
## the chord after.
## Static, so the page can say it without holding a router, and there is only
## ever one capture in flight whatever window it is in.
static var capture_in_progress: bool = false

## The key the router took last, which the `ChordGate` in the window it arrived
## in stops before anything else there has it. `set_input_as_handled()`
## from `window_input` does not hold, because the window's `push_input` clears
## the flag on its way in, so Ctrl+comma would shut Preferences and go on into
## the focused search, which would type the comma.
var _taken: InputEvent = null

## The key whose press the router took, until that key is let go. Its repeats are
## the chord's too, with or without the modifiers still held: a held Ctrl+comma
## repeated into the search after its press had opened Preferences, and a comma
## kept down after Ctrl came up repeated as plain commas.
var _held_key: Key = KEY_NONE


## Stops a key the router took from going on into the window it arrived in.
##
## The window's own `_input` pass is the one place after `push_input` has
## cleared the handled flag and before the focused control hears the key, and a
## `Node` added last runs first in it. `SaFloatingPanel.Guard` is the same door,
## and is handed what to take the same way, as a question rather than its
## asker.
class ChordGate:
    extends Node

    ## Answers whether an event is one the router took.
    var takes: Callable

    func _init(asks: Callable) -> void:
        takes = asks
        name = "ShortcutChordGate"
        process_mode = Node.PROCESS_MODE_ALWAYS

    func _input(event: InputEvent) -> void:
        if takes.is_valid() and takes.call(event):
            get_viewport().set_input_as_handled()


## Subscribes to every window in *tree*, and to every window that appears later.
##
## The root is left out on purpose: its keys arrive through Main's
## `_unhandled_input`, which runs after the GUI has had them, and a second door
## here would fire every chord twice.
##
## Every window in the tree is wired from one place rather than by whoever built
## it, because some are built by nobody in Sara. A dropdown's popup is made by
## its OptionButton and a tooltip by the viewport, so wired by their builders,
## Ctrl+Shift+N over an open blend menu would reach nothing at all.
func watch_windows(tree: SceneTree) -> void:
    if tree == null or tree.root == null:
        return
    if not tree.node_added.is_connected(_on_node_added):
        tree.node_added.connect(_on_node_added)
    for node in tree.root.find_children("*", "Window", true, false):
        watch_window(node as Window)


## Subscribes to one window. Safe to call again for the same one.
func watch_window(window: Window) -> void:
    if window == null or not is_inside_tree() or window == get_tree().root:
        return
    var id := window.get_instance_id()
    if _watched.has(id):
        return
    var gate := ChordGate.new(_is_taken)
    _watched[id] = gate
    window.window_input.connect(_on_window_input.bind(window))
    window.add_child(gate, false, Node.INTERNAL_MODE_BACK)


## The gates go with the router, so a window that outlives it, as one a suite
## leaves behind does, keeps no node that answers to nobody.
func _notification(what: int) -> void:
    if what != NOTIFICATION_PREDELETE:
        return
    for gate: Variant in _watched.values():
        if is_instance_valid(gate):
            (gate as Node).queue_free()


func _on_node_added(node: Node) -> void:
    if node is Window:
        watch_window(node as Window)


## A popup answers to different rules from a docker, and the window itself is
## the only thing that says which this is.
func _on_window_input(event: InputEvent, window: Window) -> void:
    if window is Popup:
        handle_popup_input(event, window)
    else:
        handle_docker_input(event, window)


## Whether a focused text box keeps *event* rather than the router taking it.
##
## A search box needs the shortcuts turned off so that typing works, and Escape
## escapes from it. So a focused `LineEdit` or `TextEdit` keeps every key that
## is not a chord, Space included, and Space is the held-modifier pan that
## `_forward_to_tool_machine` would otherwise have given the tool.
##
## **A chord goes past on purpose**, and is the other half: Ctrl+comma
## toggles Preferences and does not type a comma. Shift is
## not a chord to `SaShortcutKeys.is_chord`, which is right here, because Shift
## and a letter is how a capital is typed.
##
## **Six chords do not**, the ones the box answers itself, which
## `SaShortcutKeys.text_editing_chord` names: select all, copy, cut, paste, undo
## and redo. Both the box and the router acted on Ctrl+A, so the text and the whole
## canvas were selected. Every other chord still passes, so Ctrl+S saves.
##
## **One more is kept**, Alt+F in a search field, which empties it
## ([SaSearchField]), so no command the key might be bound to runs as well.
static func text_field_keeps(focus_owner: Object, event: InputEvent) -> bool:
    if not (focus_owner is LineEdit or focus_owner is TextEdit):
        return false
    if SaSearchField.keeps(focus_owner, event):
        return true
    return not SaShortcutKeys.is_chord(event) or SaShortcutKeys.text_editing_chord(event)


## Whether a value slider under the pointer or holding the focus keeps a bare
## Backspace, which puts it back to the value it was built with in
## `FactorSlider._unhandled_key_input`.
##
## A docker's window hands the router a key before its own controls see it,
## and the clear holds bare Backspace, so without this the press over a slider
## in a docker would reset the slider and clear the layer both. In the main window
## the slider answers first and marks the key handled, so the bar's sliders
## need nothing here.
static func slider_keeps(viewport: Viewport, focus_owner: Object, event: InputEvent) -> bool:
    var key := event as InputEventKey
    if key == null or key.keycode != KEY_BACKSPACE or SaShortcutKeys.is_chord(event):
        return false
    return focus_owner is FactorSlider or (viewport != null and viewport.gui_get_hovered_control() is FactorSlider)


## The meta a control carries to keep a bare Delete for itself, which a curve's
## point and a colour ramp's stop go with. Named by the control and not by
## class, so the router names nothing in the toolkit or a module.
const KEEPS_DELETE_META := &"keeps_delete"


## Whether the control holding the focus keeps a bare Delete, as the graph of a
## curve does for its picked point.
##
## A docker's window hands the router a key before its own controls see it, and
## the clear holds Delete, so without this the Delete that takes a stop away
## would empty the layer as well. In the main window the control answers first and
## marks the key handled.
static func delete_keeps(focus_owner: Object, event: InputEvent) -> bool:
    var key := event as InputEventKey
    if key == null or key.keycode != KEY_DELETE or SaShortcutKeys.is_chord(event):
        return false
    return focus_owner is Control and (focus_owner as Control).has_meta(KEEPS_DELETE_META)


## The meta a docker carries, on its window or a Control in it, to keep bare
## Delete and Backspace while it has the focus or the pointer.
const KEEPS_ERASE_KEYS_META := &"keeps_erase_keys"


## Whether a bare Delete or Backspace is such a docker's: the window the key
## arrived in, or the Control under the pointer or with the focus, is in one.
static func erase_keys_kept(viewport: Viewport, focus_owner: Object, event: InputEvent) -> bool:
    var key := event as InputEventKey
    if key == null or SaShortcutKeys.is_chord(event) or not key.keycode in [KEY_DELETE, KEY_BACKSPACE]:
        return false
    var hovered: Control = viewport.gui_get_hovered_control() if viewport != null else null
    for start: Node in [viewport, focus_owner as Node, hovered]:
        var node := start
        while node != null and not node.has_meta(KEEPS_ERASE_KEYS_META):
            node = node.get_parent()
        if node != null:
            return true
    return false


## Entry point for the main window, and for every other window through
## `handle_docker_input`, which hands its own window in as the viewport, and
## *in_docker* says so because the main window's is a `Window` too. A docker is
## a viewport of its own, so the Tab that toggles is released there as well.
func handle_viewport_input(event: InputEvent, viewport: Viewport, in_docker: bool = false) -> void:
    SaKeyLog.note(event)
    if capture_in_progress or SaNoteMode.taking_note or not SaShortcutKeys.is_key_like(event):
        return
    if _repeats_a_taken_key(event):
        _take(viewport, event)
        return
    # Once, and from the viewport the event arrived in, which is what makes the
    # two gates below answer for the window the painter is typing in.
    var focus_owner: Control = viewport.gui_get_focus_owner() if viewport != null else null
    if SaShortcutKeys.is_escape(event):
        _handle_escape(event, viewport, in_docker)
        return
    if text_field_keeps(focus_owner, event) or slider_keeps(viewport, focus_owner, event) or delete_keeps(focus_owner, event):
        return
    if erase_keys_kept(viewport, focus_owner, event):
        return
    if _typed_into_the_tool(event, viewport):
        return
    if _forward_to_tool_machine(event, viewport):
        return
    if SaShortcutKeys.is_bare_tab(event) and _focus_blocks_tab(focus_owner, in_docker):
        return
    # A bracket's echo is let past this gate on purpose, and a history chord's:
    # every other shortcut still answers once per real keydown, and the two that
    # step one place per press repeat. Holding down Ctrl+Z keeps
    # performing the undo, not just triggering one, so a held undo walks back
    # through the history at the platform's repeat rate. Ctrl+Q's echo still
    # reaches nobody.
    if event.is_pressed() and (not event.is_echo() or repeats_while_held(event)) and handle(event):
        if viewport != null and SaShortcutKeys.is_bare_tab(event):
            _release_focus_owner(viewport)
        _take_a_press(viewport, event)


## Marks *event* handled in *viewport* and as the router's, so the `ChordGate`
## of a window it came from marks it again once `push_input` has cleared it.
func _take(viewport: Viewport, event: InputEvent) -> void:
    _taken = event
    if viewport != null:
        viewport.set_input_as_handled()


## Whether *event* is the one the router took last, which a `ChordGate` asks.
func _is_taken(event: InputEvent) -> bool:
    return event == _taken


## `_take`, and the key held from here until it is let go, unless *event* is
## itself a repeat, which only a chord that repeats on purpose is by now.
func _take_a_press(viewport: Viewport, event: InputEvent) -> void:
    _take(viewport, event)
    var key := event as InputEventKey
    if key != null and not key.echo:
        _held_key = key.keycode


## Whether *event* is a repeat of the key whose press the router took, which
## the chord keeps until the key is let go.
##
## A fresh press starts over, whatever it is, and the release of the held key
## ends it. A chord that repeats on purpose, a bracket or undo held down, is
## left to answer every repeat as it always has.
func _repeats_a_taken_key(event: InputEvent) -> bool:
    var key := event as InputEventKey
    if key == null:
        return false
    if not key.pressed:
        if key.keycode == _held_key:
            _held_key = KEY_NONE
        return false
    if not key.echo:
        _held_key = KEY_NONE
        return false
    return key.keycode == _held_key and _held_key != KEY_NONE and not repeats_while_held(event)


# --- Escape -------------------------------------------------------------------


## What Escape means, which depends on what else is going on rather than on the
## event, and so sits off the `handle()` chain, which asks each group of chords
## in turn and knows nothing about the state of anything.
##
## The order is the whole design. A slider held in a drag takes the key first,
## a dialog's as well, which would otherwise close. A dialog takes the key for
## itself, below, and a pop-up out on a summon goes back next. Then a tool with
## a gesture in the air sees the key, a text field keeps it, and whatever else
## holds the keyboard gives it up last. **A text field keeps it because the
## focus is read**, or Escape out of a rename box would close the docker the
## box is in.
##
## **Escape closes no docker**, and escapes from what is selected instead,
## while a dialog closes on it, as `escape_in_a_dialog` says. So outside a dialog the
## last thing Escape does is release the focus owner, which is what an
## OptionButton that swallowed Space needed. The quick mask sits between the
## text box and the focus owner: a mode the painter did not ask for is left by
## the same key.
##
## The gesture is read before the key is forwarded, because the forward is what
## abandons it: once the transform has put its move back, nothing left can say
## that Escape is the key that did it. The tool is offered the key either way,
## which is what `ToolMachine.handle_key_event` is for. *from_window* says the
## key came through a window's `window_input`, which `_release_text_focus` needs.
func _handle_escape(event: InputEvent, viewport: Viewport, from_window: bool) -> void:
    if SaSliderDrag.cancel_live(event, viewport):
        return
    if viewport is SaDialogWindow:
        escape_in_a_dialog(event, viewport as SaDialogWindow)
        return
    var fresh := event.is_pressed() and not event.is_echo()
    if fresh and _send_back_a_pop_up():
        if viewport != null:
            viewport.set_input_as_handled()
        return
    var gesture_wanted_it := _tool_gesture_is_live()
    _forward_to_tool_machine(event, viewport)
    if gesture_wanted_it or not fresh:
        return
    var heard: InputEvent = event if from_window else null
    if SaColors.leave_mask() or _release_text_focus(viewport, heard) or _leave_quick_mask() or _release_focus_owner(viewport):
        if viewport != null:
            viewport.set_input_as_handled()


## Escape in a dialog closes it, because closing a window on Escape is a
## painter's muscle memory.
##
## A text field with the keyboard lets go of it first and the window stays, so
## the Preferences search is left by one Escape and the window by the next.
## Otherwise the window emits `close_requested`, as its × does, which a filter
## dialog answers with Cancel and a question with its cancel index. A focused
## button is not let go first, since every dialog opens with one focused. Static
## and public for the captures, which press Escape into a window no router
## watches.
static func escape_in_a_dialog(event: InputEvent, dialog: SaDialogWindow) -> bool:
    if not event.is_pressed() or event.is_echo() or not dialog.visible:
        return false
    if not _release_text_focus(dialog, event):
        dialog.close_requested.emit()
    return true


## Escape sends the pop-up palette back, as a choice popup closes on it. The
## palette takes no focus, so the key never arrives in it and the docker is
## looked for. It goes back the way the leave sends it, not through its ×, which
## would write the layout as the painter's edit.
func _send_back_a_pop_up() -> bool:
    if summon == null or not dockers_provider.is_valid():
        return false
    for entry: Dictionary in dockers_provider.call():
        var window := entry.get("node") as Window
        var asks := window != null and window.has_method(&"goes_back_on_escape")
        if asks and bool(window.call(&"goes_back_on_escape")) and summon.is_summoned(window):
            summon.send_back(DockerLayoutStore.section_for(entry))
            return true
    return false


## Escape out of a focused text box, which is the whole of what the key does
## there.
##
## A text box owns the keyboard while it has the focus and Escape is the way out
## of it, and leaving the box is all of it: the docker or the window behind
## stays as it was. Without this one Escape out of a rename field would shut the
## Layers docker under it.
##
## Kept apart from `_release_focus_owner` below, which would let the same box go,
## because the two answer different needs and a text box is the one case where
## the control's own handler wants the key as well.
##
## **The box hears *event* first**, the key from a docker's or a dialog's
## `window_input`, which runs before the window's tree. Released unheard, a box
## that commits on leaving keeps its edit, so 0.99 typed into the Brush Editor's
## Strength and one Escape would leave it at 1 %. Null for the main
## window, whose box had the key before the router.
static func _release_text_focus(viewport: Viewport, event: InputEvent = null) -> bool:
    if viewport == null:
        return false
    var focused := viewport.gui_get_focus_owner()
    if not (focused is LineEdit or focused is TextEdit):
        return false
    if event != null:
        focused.gui_input.emit(event)
    if is_instance_valid(focused) and focused.has_focus():
        focused.release_focus()
    return true


## Escape out of the quick mask.
##
## A painter can reach it by accident with Shift+Q, and then cannot paint until
## they find the Select menu's row. Escape is the key a
## painter reaches for to leave a mode they did not ask for, so it leaves this
## one the way it leaves a gesture: the mask painted so far stays as the
## selection, and only the editing stops. Deselect is still what drops the
## selection itself, and `SaSelection.deselect` already leaves the mask too.
##
## After a text box and before any other focus owner: a painter typing in a
## box wants Escape to leave the box, and a focused button is the smaller thing
## to let go of, so the mode goes first and the next Escape frees the button.
func _leave_quick_mask() -> bool:
    var document := _document()
    if document == null or document.selection == null or not document.selection.editing:
        return false
    document.selection.editing = false
    return true


## Escape out of whatever else holds the keyboard.
##
## A dropdown is the reason. An `OptionButton` that has been picked from keeps
## the focus afterwards, and `ui_accept` is Space, so the pan quick key would
## open the list again rather than pan. Escape is the way out of that, and it is the same
## way out of any focused button, slider or list.
##
## `gui_release_focus` rather than `release_focus` on the owner, because a
## `Window` is a `Viewport` and this has to let go of the focus in the viewport
## the key arrived in rather than in whichever one the control thinks it is in.
static func _release_focus_owner(viewport: Viewport) -> bool:
    if viewport == null or viewport.gui_get_focus_owner() == null:
        return false
    viewport.gui_release_focus()
    return true


## Whether the active tool has something in the air that Escape abandons.
##
## Asked through `preview_shape()`, which the selection overlay already draws
## from, for the reason the state dump asks the transform's box by name: a tool
## lives in a module and the skeleton must not name a module's script. Every
## tool with a pending gesture answers it, and answers empty when there is
## none: the transform's box and move, the crop's rectangle, the lasso's
## outline and the marquee's drag.
##
## Two of those four do not consume Escape, the marquee not at all and the
## freehand lasso only once it is a polygon, so this reads wider than the key's
## real meaning. It errs towards leaving the focus alone, which is the side to
## be wrong on: a gesture and a focused control are rarely both live, and the
## one that is in the air is the one the painter is looking at.
func _tool_gesture_is_live() -> bool:
    var tool_machine := _tool_machine()
    if tool_machine == null or tool_machine.active_tool == null:
        return false
    var active: ToolState = tool_machine.active_tool
    if not active.has_method("preview_shape"):
        return false
    var shape: Dictionary = active.call("preview_shape")
    return not shape.is_empty()


## The chords a held key repeats, named in one place so the gate below and the
## handler that acts on them cannot drift.
##
## The bracket steps the brush size and a history chord walks the undo stack,
## and both have an effect per press so a painter holding the key down means
## every repeat. Nothing else is here: a chord whose second press means the same
## as its first, Ctrl+Q above all, still never sees an echo.
static func repeats_while_held(event: InputEvent) -> bool:
    return SaShortcutKeys.brush_size_direction(event) != 0 or SaShortcutKeys.history_chord(event)


## The chords a window that is not a docker still answers (f11).
##
## `ui_quit` because Ctrl+Q means the same thing wherever the keyboard is, and
## `edit_preferences` because Ctrl+comma is the door a painter uses to shut the
## very window they are typing in. Escape is not on the list because it never
## reaches this test: `handle_viewport_input` answers it first, under its own
## rules about which window it belongs to. `docker_maximise` joins them because
## the chord is for the selected docker or dialog window, and a dialog that
## declined it would leave the chord working on dockers alone. `ui_take_note`
## joins them because a note is about the window it is taken over, and a painter
## who meets a fault in Preferences has the keyboard in Preferences: Help > Take
## a Note already reaches that window, so the chord that is its shortcut has to
## as well. The action is named rather than the key, so a rebound chord follows.
const WINDOW_CHORDS: Array[String] = ["ui_quit", "edit_preferences", "docker_maximise", "ui_take_note"]


## Entry point for a window that is not a popup: a docker, a dialog.
##
## **The window itself is handed on, rather than `window.get_viewport()`**. A
## `Window` is a `Viewport`, and that call answers the *embedder* for an embedded
## subwindow and null for a window nobody parents. Every question the call below
## asks is about the window the key arrived in: which control has the keyboard
## there, and which window Escape belongs to. Asking the embedder is how a text
## box in the Preferences window was judged against the main window's focus
## owner, and it is why the two gates that need the right answer had to be
## written a second time here to work at all.
##
## Text fields are exempt from the shortcuts, which is `text_field_keeps`, and
## the exemption stops at a chord, bar the six a box answers itself.
func handle_docker_input(event: InputEvent, window: Window) -> void:
    if capture_in_progress or SaNoteMode.taking_note or window == null or not SaShortcutKeys.is_key_like(event):
        return
    # Before the dialog's test, since a comma repeating once Ctrl is up is no
    # chord any longer and would be the search's.
    if _repeats_a_taken_key(event):
        _take(window, event)
        return
    # A dialog is not a docker, and the whole router is more than it should be
    # handed (f11). Declining rather than consuming, so the key stays the focused
    # control's: a letter typed into a Preferences box is still that letter.
    if not takes_document_chords(window) and not _is_window_chord(event):
        # Bar the chord of the filter whose dialog is up, which closes it.
        if not SaFilterChord.close_its_dialog(self, event).is_empty():
            _take_a_press(window, event)
        return
    handle_viewport_input(event, window, true)


## Whether *window* is one the painter works the picture from, so the whole
## router belongs to it.
##
## A docker is, and so is any window Sara did not build, which keeps the answer
## conservative: nothing that reaches the router today stops reaching it except
## from the one kind this is about. Every settings window, filter dialog and the
## brush editor is an `SaDialogWindow`, so one test names all three.
##
## Without it, Ctrl+T with Preferences open would make the canvas tool the
## transform, and Ctrl+U open Hue/Saturation/Lightness over the top of it. A
## bare B does nothing there, because `text_field_keeps` holds a plain key for
## the focused box, so the hole is exactly the chords that gate lets past on
## purpose: Ctrl+comma has to work from inside a search box, which is not every
## chord working from inside every window.
static func takes_document_chords(window: Window) -> bool:
    return not (window is SaDialogWindow)


## Whether *event* is one of the chords a dialog still answers.
static func _is_window_chord(event: InputEvent) -> bool:
    return SaShortcutKeys.is_escape(event) or SaShortcutKeys.pressed(event, WINDOW_CHORDS, false, true)


## Entry point for an open popup: a menu, a dropdown, a context menu.
##
## The popup keeps the plain keys, the arrows, Escape and a row's letter, so B
## over an open blend menu is the letter B and not the brush, and
## `SaMenuHeldKey` says in the corner when one was a command's key. Only a chord
## reaches the app, as Ctrl+Shift+N over that same open menu needs.
##
## An item of the open menu that carries the chord itself keeps it, or Ctrl+S
## with the File menu open would save twice: once here and once through the
## item. The held-modifier quick tools are skipped for the same reason the plain
## keys are, so ALT over an open menu is not the eyedropper.
##
## A popup holding a text box keeps the six chords the box answers itself, which
## is the gate `handle_viewport_input` has, so Ctrl+A in a popup's field selects
## the text and not the canvas.
func handle_popup_input(event: InputEvent, popup: Window) -> void:
    if capture_in_progress or SaNoteMode.taking_note or popup == null:
        return
    if _repeats_a_taken_key(event):
        _take(popup, event)
        return
    SaMenuHeldKey.tell(popup, event)
    if not SaShortcutKeys.is_chord(event) or SaShortcutKeys.menu_claims(popup, event):
        return
    if text_field_keeps(popup.gui_get_focus_owner(), event):
        return
    if event.is_pressed() and not event.is_echo() and handle(event):
        _take_a_press(popup, event)


## Returns true when the event was consumed.
##
## The usage tally counts what answered, by the id each group below returns,
## which is why a group names its action rather than saying only that it took
## the key. Repeat Last keeps it as the last command too, with the chord to send
## again for an answer the command registry does not hold: a docker of the four
## older toggles, Tab, the colour pair, the brush size and a tool's key.
func handle(event: InputEvent) -> bool:
    var answered := _answer(event)
    if answered.is_empty():
        return false
    SaUsageTally.shortcut(answered, event)
    SaQuickCommands.note_run(answered, _answer.bind(event.duplicate()))
    return true


## What *event* ran, as the action or command it is bound to, or `&""` when
## nothing took it.
func _answer(event: InputEvent) -> StringName:
    # Quit is checked first so Ctrl+Q is never swallowed by tool_pan, which is Q.
    # Ctrl+Q only, and not Escape, or the key every other program uses to back
    # out of something would close Sara without a word.
    if SaShortcutKeys.pressed(event, ["ui_quit"], false, true):
        if request_quit.is_valid():
            request_quit.call()
        else:
            get_tree().quit()
        return &"ui_quit"

    var answered := _handle_file(event)
    if answered.is_empty():
        answered = _handle_dockers(event)
    if answered.is_empty():
        answered = ColorDocker.answer_undo(event, _handle_history)
    if answered.is_empty():
        answered = _handle_brush(event)
    if answered.is_empty():
        answered = _handle_colors(event)
    # The registered commands, which include the router's own view,
    # interface-scale and clipboard chords, answered here rather than by keycode
    # so that they can be listed and rebound. A filter's chord closes its own
    # dialog first, or its command would open the dialog again.
    if answered.is_empty():
        answered = SaFilterChord.close_its_dialog(self, event)
    if answered.is_empty() and commands != null:
        if commands.try_handle_input(event) or SaOpacityDigitCommands.answer_by_position(commands, event):
            answered = commands.last_command
    if answered.is_empty():
        answered = SaToolKeys.answer(_tool_machine(), event)
    return answered


# --- Groups -------------------------------------------------------------------


func _handle_file(event: InputEvent) -> StringName:
    for action: String in FILE_ACTIONS:
        if SaShortcutKeys.pressed(event, [action], false, true):
            if file_command.is_valid():
                file_command.call(StringName(action))
            return StringName(action)
    return &""


func _handle_dockers(event: InputEvent) -> StringName:
    if SaShortcutKeys.is_bare_tab(event) or SaShortcutKeys.pressed(event, ["toggle_dockers"]):
        if toggle_all_dockers.is_valid():
            toggle_all_dockers.call()
        _drop_focus_to_canvas()
        return &"toggle_dockers"

    # Exactly, not loosely. A loose match asks only that the event hold at least
    # the modifiers the action does, so Shift+B for the toolbox would also answer
    # Ctrl+Shift+B, and this branch runs before every other one: the adjustment
    # on Ctrl+Shift+B would toggle the toolbox instead.
    var dockers: Array = dockers_provider.call() if dockers_provider.is_valid() else []
    for i in dockers.size():
        var shortcut: String = dockers[i].get("shortcut", "")
        if shortcut != "" and SaShortcutKeys.pressed(event, [shortcut], false, true):
            if toggle_docker.is_valid():
                toggle_docker.call(i)
            return StringName(shortcut)
    return &""


func _handle_history(event: InputEvent) -> StringName:
    var document := _document()
    if document == null:
        return &""
    if SaShortcutKeys.pressed(event, ["ui_undo", "edit_undo"], true, true):
        _close_session()
        return &"edit_undo" if document.undo() else &""
    # Ctrl+Shift+Z only, since Ctrl+Y is the canvas proof. `ui_redo` is off this
    # list for the same reason: Godot's own action answers Ctrl+Y too, and this
    # branch runs before the registered commands do, so with it in the proof
    # chord would redo a stroke instead.
    if SaShortcutKeys.pressed(event, ["edit_redo"], true, true):
        _close_session()
        return &"edit_redo" if document.redo() else &""
    return &""


## A liquify or a transform session open on the canvas becomes a step before
## the history moves, so the undo takes it back rather than the step under it.
func _close_session() -> void:
    var machine := _tool_machine()
    if machine != null:
        machine.close_session()


## X swaps the colour pair and D resets it, as in every painting program.
func _handle_colors(event: InputEvent) -> StringName:
    if SaShortcutKeys.pressed(event, ["color_swap"], false, true):
        SaColors.swap()
        return &"color_swap"
    if SaShortcutKeys.pressed(event, ["color_reset"], false, true):
        SaColors.reset()
        return &"color_reset"
    return &""


func _handle_brush(event: InputEvent) -> StringName:
    # Not through the InputMap, because the InputMap holds a key's position and
    # a keyboard on another layout sends the character. SaShortcutKeys carries the rule
    # and what widening it costs.
    var step := SaShortcutKeys.brush_size_direction(event)
    if step != 0:
        var machine := _tool_machine()
        # A proportion of the size rather than a fixed amount, because the Size
        # row is geometric: a constant distance along a geometric scale is a
        # constant ratio, and a fixed step was invisible at fifty pixels and
        # enormous at half of one.
        var delta := SaShortcutKeys.brush_size_step(SaShortcutKeys.current_brush_radius(machine), step)
        SaShortcutKeys.nudge_brush_radius(machine, delta)
        return &"brush_size_increase" if step > 0 else &"brush_size_decrease"
    return &""


## Takes the registry the app dispatches through, and puts the router's own
## chords in it, which `SaShortcutCommands` holds the table of. *view_transforms*
## is what the view mode chords flip, and a router bound without one answers
## them with nothing to flip.
func bind_commands(registry: SaCommandRegistry, view_transforms: SaViewTransformRegistry = null) -> void:
    commands = registry
    SaColors.follow(_document())
    if _commands == null:
        _commands = SaShortcutCommands.new(tool_machine_provider, canvas_provider, _maximise_focused, view_transforms)
    _commands.register_into(registry)


## Ctrl+Space: the focused docker or dialog fills the window, and the same chord
## puts it back where the layout had it ("just like in blender").
##
## **False when nothing but the main window has the keyboard**, which is what
## lets the zoom tool keep Ctrl+Space. A declined
## command leaves the event for the rest of the chain, and the quick zoom is a
## held gesture over the canvas, where by definition no docker is focused.
##
## That is half of it. Declining here keeps the maximise off the canvas, and
## `_focused_window_answers` keeps the quick zoom off a focused docker, so the
## two share a chord and never both answer one press.
##
## The docker in front is deliberately not the fallback. Its rule is "the last
## visible docker of the table", so a painter holding Ctrl+Space over the canvas
## would have maximised whichever docker that happened to be. Nothing focused,
## or a reference board under the pointer that zooms on the chord, maximises nothing.
func _maximise_focused() -> bool:
    if not is_inside_tree() or ReferenceZoomGestures.shares_the_quick_zoom():
        return false
    var window := SaDockerMaximise.focused_window(get_tree())
    if window == null:
        return false
    print(SaDockerMaximise.toggle_window(window))
    return true


# --- Helpers ------------------------------------------------------------------


## Whether a bare Tab belongs to whatever holds the focus rather than to focus
## mode.
##
## A dialog is declined before it gets here, by `takes_document_chords`, so the
## Tab that walks its buttons stays its own. In a docker the control that took
## the focus last is often a check box, which would keep the Tab while the
## dockers stay open, so there only a text field keeps it, and a `SpinBox`'s field is
## a `LineEdit`. In the main window the canvas, or nothing focused, is the mode's.
static func _focus_blocks_tab(focus_owner: Control, in_docker: bool) -> bool:
    var text := focus_owner is LineEdit or focus_owner is TextEdit
    return focus_owner != null and not (focus_owner is SaCanvas) and (text or not in_docker)


## Nothing focused means the canvas has it, which makes the next bare Tab a
## toggle rather than focus traversal, as the first one left the focus on a top
## bar button and the second walked the bar.
func _drop_focus_to_canvas() -> void:
    if not canvas_provider.is_valid():
        return
    var canvas := canvas_provider.call() as SaCanvas
    if canvas == null or not canvas.is_inside_tree():
        return
    var viewport := canvas.get_viewport()
    if viewport != null:
        viewport.gui_release_focus()


func _tool_machine() -> ToolMachine:
    if not tool_machine_provider.is_valid():
        return null
    return tool_machine_provider.call() as ToolMachine


func _document() -> SaDocument:
    if not canvas_provider.is_valid():
        return null
    var canvas := canvas_provider.call() as SaCanvas
    return canvas.document if canvas != null else null


## Held-modifier quick tools (Space=pan, Ctrl+Space=zoom, Alt=eyedropper) need
## every key event, press and release, even while a docker holds focus.
##
## Except the press a focused window is about to answer itself, because the
## maximise is on Ctrl+Space too. `_maximise_focused` declines with nothing
## focused, and without this the quick zoom would take the key wherever it was
## pressed, so a painter who had clicked a docker and then leaned on Ctrl+Space
## would get both, the zoom tool from here and the maximise from `handle` a few
## lines below.
##
## `handle_popup_input` skips the quick tools over an open menu for the same
## reason and in the same shape: a press another part of the app owns is not a
## canvas gesture. The quick zoom has Ctrl+Space over the canvas, and the plain
## keys are untouched, so Space over a focused docker is the pan.
## Whether the active tool took *event* as typing, a text block being edited,
## which is asked before the tool machine and before any chord, so "b" types
## and does not pick the brush and Space types and does not pan. The machine
## never sees the key, since its held keys are what start a quick tool.
func _typed_into_the_tool(event: InputEvent, viewport: Viewport) -> bool:
    var key := event as InputEventKey
    var tool_machine := _tool_machine()
    if key == null or tool_machine == null or tool_machine.active_tool == null:
        return false
    if not tool_machine.active_tool.takes_typing(key):
        return false
    tool_machine.active_tool.handle_input(key)
    if viewport != null:
        viewport.set_input_as_handled()
    return true


func _forward_to_tool_machine(event: InputEvent, viewport: Viewport) -> bool:
    if not (event is InputEventKey):
        return false
    if _focused_window_answers(event):
        return false
    var tool_machine := _tool_machine()
    if tool_machine == null:
        return false
    # A tool's own key, Enter committing a transform, can switch the tool back.
    SaUsageTally.note_key()
    if not tool_machine.handle_key_event(event):
        return false
    if viewport != null:
        viewport.set_input_as_handled()
    return true


## Whether *event* is a press a focused docker or dialog takes as one of
## `WINDOW_CHORDS`, so the quick tools stand down for it.
##
## The same question `_maximise_focused` asks, and asked here rather than read
## off its result, because the answer is needed before `handle` runs at all.
func _focused_window_answers(event: InputEvent) -> bool:
    if not event.is_pressed() or not _is_window_chord(event):
        return false
    if not is_inside_tree():
        return false
    return SaDockerMaximise.focused_window(get_tree()) != null
