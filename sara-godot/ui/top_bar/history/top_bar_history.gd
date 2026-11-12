## The top bar's Undo and Redo buttons, each a press that runs the Edit menu's
## own command and dims while that command can do nothing.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## On a tablet with no keyboard, undo was two menus away or the Undo History
## docker. The two are `TopMenuBar` elements like the rotation pair, ordered by
## the profile and hidden from Preferences, and registered with a view through
## `SaSettings.register_layout_element`, the door a module's element takes, so a
## custom docker can place them too.
##
## **One command, never a copy of it.** A press runs `edit_undo` or `edit_redo`
## through the command registry, the call the menu row makes, and the dimming
## asks the same command's `is_enabled`, the question that greys the menu row,
## so the bar and the menu cannot disagree about whether there is a step to take.
## The registry is the one main hands the top bar's menus, given here by
## [method bind] when the bar's menus take it.
class_name SaTopBarHistory
extends RefCounted

## The layout keys, English like every other key and translated on the buttons.
const ELEMENT_UNDO := "Undo"
const ELEMENT_REDO := "Redo"
const CATEGORY := "TopMenuBar"

## The bar's group the pair sits in, a word of its own, since the two act on the
## document's history and not on the brush, the line or the view. The bar draws a
## break between it and its neighbours as it does between any two groups.
const GROUP := &"history"

## The command each button runs, the Edit menu's.
const COMMANDS := {ELEMENT_UNDO: &"edit_undo", ELEMENT_REDO: &"edit_redo"}
## The node name of each button, the bar's and a docker's, which a scenario's
## click aims at.
const NODE_NAMES := {ELEMENT_UNDO: "UndoBtn", ELEMENT_REDO: "RedoBtn"}
## The icon each draws, a hooked arrow back and one forward.
const ICONS := {ELEMENT_UNDO: "undo", ELEMENT_REDO: "redo"}

## The command registry the presses run through, null until main binds it, and
## while it is null both buttons are dimmed.
var _commands: SaCommandRegistry = null


## Takes the command registry, from `SaTopMenuBar.bind_commands`, the call that
## hands it to the menus.
func bind(registry: SaCommandRegistry) -> void:
    _commands = registry


## Registers both elements and their views, through the door a module uses.
## Their place on a fresh bar is the skeleton's default order's.
func register() -> void:
    var held: WeakRef = weakref(self)
    for element: String in COMMANDS:
        var builder := func() -> Control: return make(null, element, _source_of(held))
        SaSettings.register_layout_element(CATEGORY, element, element, false, "", builder)


## The bar's own buttons under *host*, built the first time and found there
## after, as the element map the bar's rows order.
func home(host: Node) -> Dictionary:
    if host == null:
        return {}
    register()
    var out := {}
    for element: String in COMMANDS:
        var button := host.get_node_or_null(String(NODE_NAMES[element])) as Button
        if button == null:
            button = make(host, element, _source_of(weakref(self)))
        out[element] = button
    return out


## Element key -> group, beside [method home].
static func groups() -> Dictionary:
    return {ELEMENT_UNDO: GROUP, ELEMENT_REDO: GROUP}


## A button for *element* under *parent* or loose, running its command through
## the registry *commands* answers.
static func make(parent: Node, element: String, commands: Callable) -> Button:
    var label := TranslationServer.translate(element)
    var button := SaMake.button(parent, String(NODE_NAMES[element]), "", label)
    button.focus_mode = Control.FOCUS_NONE
    # The bar's one size for an icon button, the mirrors' and the erase toggle's.
    SaBarIconButton.shape(button, String(ICONS[element]), label)
    # Dimmed until the follower's first read, so a fresh bar never offers a
    # press that does nothing for the length of a frame.
    button.disabled = true
    var follower := Follower.new(button, COMMANDS[element], commands)
    button.add_child(follower)
    button.pressed.connect(follower.run)
    return button


## The follower under *button*, which a suite asks to read the history at once.
static func follower_of(button: Button) -> Follower:
    return button.get_node_or_null(Follower.NODE_NAME) as Follower if button != null else null


static func _source_of(held: WeakRef) -> Callable:
    return func() -> SaCommandRegistry: return (held.get_ref() as SaTopBarHistory)._commands if held.get_ref() != null else null


## Reads whether the command can act every frame and dims the button when it
## cannot, and runs the command on a press. A child of the button and not a
## subclass of it, so the button is the made `Button` the harness and the theme
## read like any other.
class Follower:
    extends Node

    const NODE_NAME := "Follower"

    var _button: Button
    var _command: StringName
    ## Answers the `SaCommandRegistry`, or null.
    var _commands: Callable

    func _init(button: Button = null, command: StringName = &"", commands: Callable = Callable()) -> void:
        _button = button
        _command = command
        _commands = commands
        name = NODE_NAME

    func _ready() -> void:
        sync()

    func _process(_delta: float) -> void:
        sync()

    func sync() -> void:
        var descriptor := _descriptor()
        var lock := descriptor == null or not descriptor.is_enabled()
        if _button.disabled != lock:
            _button.disabled = lock
        var tip := _tip(descriptor)
        if _button.tooltip_text != tip:
            _button.tooltip_text = tip

    ## The press: the menu row's own call, so a step taken here is the one the
    ## menu, the chord and the Undo History docker take.
    func run() -> void:
        var registry := _registry()
        if registry != null:
            registry.execute(_command)
        sync()

    func _registry() -> SaCommandRegistry:
        return _commands.call() as SaCommandRegistry if _commands.is_valid() else null

    func _descriptor() -> SaCommandDescriptor:
        var registry := _registry()
        return registry.get_descriptor(_command) if registry != null else null

    ## The element whose button runs the command, its word in English. Every
    ## follower runs one of [constant COMMANDS], so the loop always finds it.
    func _element() -> String:
        for element: String in COMMANDS:
            if COMMANDS[element] == _command:
                return element
        return ""

    ## The command's words, its chord in brackets when it answers to one, and
    ## its sentence under them, as the menu row reads them.
    func _tip(descriptor: SaCommandDescriptor) -> String:
        if descriptor == null:
            return tr(_element())
        var words := tr(descriptor.menu_label())
        var chord := registry_chord(_registry(), _command)
        if not chord.is_empty():
            words = "%s (%s)" % [words, chord]
        return words if descriptor.sentence.is_empty() else "%s\n%s" % [words, tr(descriptor.sentence)]

    ## The chord the menu row shows, the registry's first and then the input
    ## map's, where Undo and Redo are bound, `SaMenu.chord_of`'s order.
    static func registry_chord(registry: SaCommandRegistry, command: StringName) -> String:
        var chord := registry.chord_text(command, 1) if registry != null else ""
        if chord.is_empty() and InputMap.has_action(command):
            chord = SaCommandRegistry.format_events(InputMap.action_get_events(command), 1)
        return chord
