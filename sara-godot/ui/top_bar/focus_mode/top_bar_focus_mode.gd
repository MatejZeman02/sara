## The top bar's Focus Mode button, a press that hides the open dockers or
## brings the same ones back, held down while the mode is on.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A tablet with no keyboard has no Tab, and the Window menu's Focus Mode row is
## two presses away, so a painter who had hidden the dockers had no short way
## back. The button is a `TopMenuBar` element like the Undo and Redo pair,
## ordered by the profile and hidden from Preferences, and registered with a
## view through `SaSettings.register_layout_element`, the door a module's
## element takes, so a custom docker can place it too. Focus mode hides dockers
## and never the bar, so the button stays where the painter pressed it.
##
## **One toggle, never a copy of it.** A press runs the toggle Tab runs, which
## main hands the bar through [method bind], and the pressed state reads
## `SaFocusMode.active` every frame, so a Tab or a press on the menu row moves
## the button as well, and a press that hides nothing, with every docker closed,
## leaves it up.
class_name SaTopBarFocusMode
extends RefCounted

## The layout key, English like every other key and translated on the button.
const ELEMENT := "Focus Mode"
const CATEGORY := "TopMenuBar"

## The element it follows on a fresh bar, so it opens at the row's right end
## beside Undo and Redo, the other way back a tablet painter needs a press away.
const AFTER := SaTopBarHistory.ELEMENT_REDO

## The bar's group it sits in, a word of its own, since it acts on the window's
## dockers and not on the document, the brush or the view.
const GROUP := &"window"

## The node name of every button, the bar's and a docker's, which a scenario's
## click aims at.
const NODE_NAME := "FocusModeBtn"
## The icon it draws, four corners round a point.
const ICON := "focus_mode"

## The chord the tooltip names when the input map binds nothing to
## `toggle_dockers`, which it does not by default, since the router reads a bare
## Tab as a keycode.
const KEY := "Tab"

## Tab's toggle, null until main binds it, and while it is null the button is
## dimmed.
var _toggle: Callable = Callable()


## Takes the toggle Tab runs, `MainDockers.toggle_all_dockers`.
func bind(toggle: Callable) -> void:
    _toggle = toggle


## Registers the element and its view, through the door a module uses, after
## [constant AFTER] on a fresh bar.
func register() -> void:
    var held: WeakRef = weakref(self)
    var builder := func() -> Control: return make(null, _source_of(held))
    SaSettings.register_layout_element(CATEGORY, ELEMENT, ELEMENT, false, AFTER, builder)


## The bar's own button under *host*, built the first time and found there
## after, as the element map the bar's rows order.
func home(host: Node) -> Dictionary:
    if host == null:
        return {}
    register()
    var button := host.get_node_or_null(NODE_NAME) as Button
    if button == null:
        button = make(host, _source_of(weakref(self)))
    return {ELEMENT: button}


## Element key -> group, beside [method home].
static func groups() -> Dictionary:
    return {ELEMENT: GROUP}


## A toggle button under *parent* or loose, running the toggle *toggles*
## answers.
static func make(parent: Node, toggles: Callable) -> Button:
    var label := TranslationServer.translate(ELEMENT)
    var button := SaMake.button(parent, NODE_NAME, "", label)
    button.focus_mode = Control.FOCUS_NONE
    SaBarIconButton.shape(button, ICON, label)
    button.toggle_mode = true
    # Dimmed until the follower's first read, as Undo is.
    button.disabled = true
    var follower := Follower.new(button, toggles)
    button.add_child(follower)
    button.toggled.connect(follower.run)
    return button


## The follower under *button*, which a suite asks to read the mode at once.
static func follower_of(button: Button) -> Follower:
    return button.get_node_or_null(Follower.NODE_NAME) as Follower if button != null else null


static func _source_of(held: WeakRef) -> Callable:
    return func() -> Callable: return (held.get_ref() as SaTopBarFocusMode)._toggle if held.get_ref() != null else Callable()


## Reads the mode every frame and holds the button down while it is on, and
## runs the toggle on a press. A child of the button and not a subclass of it,
## so the button is the made `Button` the harness and the theme read like any
## other.
class Follower:
    extends Node

    const NODE_NAME := "Follower"

    var _button: Button
    ## Answers the toggle Callable, or an empty one.
    var _toggles: Callable

    func _init(button: Button = null, toggles: Callable = Callable()) -> void:
        _button = button
        _toggles = toggles
        name = NODE_NAME

    func _ready() -> void:
        sync()

    func _process(_delta: float) -> void:
        sync()

    func sync() -> void:
        if _button.button_pressed != SaFocusMode.active:
            _button.set_pressed_no_signal(SaFocusMode.active)
        var lock := not _toggle().is_valid()
        if _button.disabled != lock:
            _button.disabled = lock
        var tip := _tip()
        if _button.tooltip_text != tip:
            _button.tooltip_text = tip

    ## The press: Tab's own call, then the state the mode decided, since the
    ## button flipped itself on the way here whether or not anything hid.
    func run(_on: bool = true) -> void:
        var toggle := _toggle()
        if toggle.is_valid():
            toggle.call()
        sync()

    func _toggle() -> Callable:
        var toggle: Variant = _toggles.call() if _toggles.is_valid() else null
        return toggle as Callable if toggle is Callable else Callable()

    ## The words of the Window menu's row, its chord in brackets and its
    ## sentence under them.
    func _tip() -> String:
        var chord := SaMenu.action_chord(&"toggle_dockers")
        if chord.is_empty():
            chord = KEY
        return (
            "%s (%s)\n%s"
            % [
                tr("Focus Mode"),
                chord,
                tr("Hides every open docker to give the painting the window, and brings back the same ones."),
            ]
        )
