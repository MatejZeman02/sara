## A named action with an optional default shortcut.
##
## Lets a module ship a working keyboard shortcut without editing
## project.godot, and collapses the skeleton's hand-written shortcut chain into
## a registry lookup.
class_name SaCommandDescriptor
extends RefCounted

var id: StringName
var title: String = ""

## The sentence a menu row shows on hover, in one line of plain English.
##
## Here rather than in the menu file. Sixty-seven sentences were typed into
## `ui/menus/`, one line under the row they belonged to, so a command reached
## from two places had one explanation and the second place had to invent its
## own or say nothing. The Modules menu was the second place, and what it
## said was that a module had registered the row, because that was all it
## could know. A command that carries its own sentence is explained wherever
## it is offered, and a module gets a tooltip the way a built-in does.
##
## Empty is allowed and means the row keeps whatever the menu puts on it.
var sentence: String = ""

## InputMap action name. If it does not exist and `default_events` is set, the
## registry creates it, which is what makes a third-party shortcut work on a
## fresh install.
var action: StringName = &""

## InputEvent list used to create `action` when absent.
var default_events: Array = []

## Called with no arguments when the command fires. Must return true if it
## consumed the event. False lets the next candidate try.
var handler: Callable = Callable()

## Higher runs first. Quit is checked before tool switching because Ctrl+Q would
## otherwise be swallowed by tool_pan, which is Q.
var priority: int = 0

## Repeat while held (brush size nudging), rather than firing once.
var allow_echo: bool = false

## Require an exact modifier match, so Ctrl+Z does not also trigger Z.
var exact_match: bool = true

var category: StringName = &"general"

## The registered id of the docker this command acts in, or empty for none.
## While that docker is hidden its chord runs nothing, and the registry says in
## the corner what the chord does and how to show the docker.
var docker: StringName = &""

## Offer this command in the Modules menu, the way Krita offers a plugin's
## actions under Tools > Scripts.
##
## Off by default and deliberately opt-in. Most commands are shortcuts for things
## that already have a home in the UI, and a menu that lists every registered
## command is a menu nobody reads. A module that ships an action with nowhere
## else to live turns this on and gets a menu entry under its own name.
var show_in_modules_menu: bool = false

## Offer this command in the Help menu, under the skeleton's own help rows, for
## a module whose action is help a painter looks for there: the tutorials
## module's Tutorials row. Opt-in for the reason the Modules menu's is, and the
## row reads the command's label and its sentence as every menu row does.
var show_in_help_menu: bool = false

## The sentence the welcome window shows a painter who has never painted, for a
## module whose command is a place to begin: the tutorials module's lessons.
## The window reads it from the command registered as `help_tutorials`, and says
## its own sentence for the manual alone when no module registers one or this
## is empty. The skeleton holds no words of any lesson, so the text is the
## module's, and the window draws the command's `sentence` on the button.
var beginner_line: String = ""

## Offer this command in the Select menu, after the skeleton's own rows, for a
## module whose action makes a selection: the background removal module's
## Select Subject. Opt-in for the reason the Help menu's is.
var show_in_select_menu: bool = false

## Offer this command in the canvas right-click menu, under the permanent
## tool's own switches. Opt-in for the same reason as the Modules menu: the
## menu is for what a painter reaches for mid-stroke, and the skeleton's
## three symmetry switches are the first.
var show_in_context_menu: bool = false

## List this command in the search F3 and the loupe open. On by default, since
## a command a module registers is found with no other call. A command that is
## plumbing, a step another row or another command takes and no painter asks
## for by name, turns it off. It still runs through `execute`, keeps its chord
## and its row on the Keyboard Shortcuts page, and is only not listed.
var show_in_search: bool = true

## () -> bool, whether the canvas right-click menu offers this command now,
## for one that asked to be there only in a state of the document: Layer via
## Copy and Layer via Cut stand in it while a selection is. Empty means always.
var context_when: Callable = Callable()

var owner_module: StringName = &""

## The words a menu row shows, when they are not the title.
##
## The title is what the Keyboard Shortcuts page lists, a phrase that stands on
## its own: "Move the layer up". A menu row stands under its menu's name and says
## less: "Move Up" on the Layer menu. Empty means the row reads the title.
var label: String = ""

## () -> bool, whether a menu row for this command can be pressed now. A row it
## answers false for is drawn dimmed and takes no press. Empty means always.
##
## A menu is rebuilt before every open, so the answer is asked then and follows
## the document without a subscription.
var enabled: Callable = Callable()

## () -> bool, the state a menu row's tick shows. A command that flips something
## carries it, and a row for one with none carries no tick at all.
var checked: Callable = Callable()

## Other commands whose rows show this command's chord while they hold none of
## their own, because this one runs theirs in the state that asks for it. A
## module's Ctrl+I names Invert Mask this way, so the skeleton names nothing of
## the module's. `SaCommandRegistry.shown_chord` reads it, and the Keyboard
## Shortcuts page still lists each row's own chord.
var shows_on: Array[StringName] = []

## For a title built from a pattern, "Opacity %d%%" and a figure, the pattern
## and what fills it, so the title is translated whole where it is shown. A
## catalogue holds the pattern and never the phrase built from it, so `title`
## alone would stay English under every language. The template reads the
## pattern where a command's maker assigns it.
var title_pattern: String = ""
var title_value: Variant = null


static func create(command_id: StringName, title_text: String, callback: Callable) -> SaCommandDescriptor:
    var descriptor := SaCommandDescriptor.new()
    descriptor.id = command_id
    descriptor.title = title_text
    descriptor.handler = callback
    descriptor.action = command_id
    return descriptor


## The title in the painter's language, translated from its pattern when it
## was built from one.
func shown_title() -> String:
    if title_pattern.is_empty():
        return String(TranslationServer.translate(title))
    return String(TranslationServer.translate(title_pattern)) % title_value


## The words for a menu row: `label`, or the title when it has none.
func menu_label() -> String:
    return label if not label.is_empty() else title


## Whether a menu row for this command takes a press now.
func is_enabled() -> bool:
    return SaTyped.flag(enabled.call()) if enabled.is_valid() else true


## Whether a menu row for this command carries a tick.
func has_tick() -> bool:
    return checked.is_valid()


## The tick's state, false for a command that has none.
func is_checked() -> bool:
    return SaTyped.flag(checked.call()) if checked.is_valid() else false
