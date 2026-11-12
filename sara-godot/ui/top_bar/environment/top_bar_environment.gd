## The top bar's Flat or Environment button, and every view of it a custom
## docker holds, all showing and driving the one switch on the main canvas's
## `SaEnvironmentView`.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## On the top bar rather than in the View menu, registered as a `TopMenuBar`
## element with a view through `SaSettings.register_layout_element`, the door a
## module's element takes, so a custom docker can place it too, and greyed with
## its reason on a flat document. The switch is the view's
## and not the button's, so the bar's button and a docker's read the same state
## every frame and neither keeps a copy.
##
## It opens the view's group on the bar, before the rotation pair, the other
## thing there that changes how the canvas is looked at. Its key is the view's command, `SaEnvironmentView.register_command`.
class_name SaTopBarEnvironment
extends RefCounted

## The layout key, English like every other key and translated on the button.
const ELEMENT := "Environment View"
const CATEGORY := "TopMenuBar"
## The node name of every button, the bar's and a docker's.
const NODE_NAME := "EnvironmentToggle"


## Registers the element and its view, through the door a module uses. Its
## place on a fresh bar is the skeleton's default order's, as the rotation
## pair's is. *views* answers the `SaEnvironmentView` the buttons drive, the main canvas's
## when empty, which is every caller but a suite with a canvas of its own. A
## second call replaces the first view, so a suite puts the shipped one back by
## calling this without one.
static func register(views: Callable = Callable()) -> void:
    var builder := func() -> Control: return make(null, views)
    SaSettings.register_layout_element(CATEGORY, ELEMENT, ELEMENT, false, "", builder)


## The bar's own button under *host*, built the first time and found there
## after, as the element map the bar's rows order. *views* as for
## [method register].
static func home(host: Node, views: Callable = Callable()) -> Dictionary:
    if host == null:
        return {}
    register(views)
    var button := host.get_node_or_null(NODE_NAME) as Button
    if button == null:
        button = make(host, views)
    return {ELEMENT: button}


## Element key -> group, beside [method home]: it turns the view, like the
## rotation pair.
static func groups() -> Dictionary:
    return {ELEMENT: SaOptionSpec.BAR_GROUP_VIEW}


## A button that shows and drives the switch, under *parent* or loose.
static func make(parent: Node, views: Callable = Callable()) -> Button:
    var button := SaMake.button(parent, NODE_NAME, TranslationServer.translate("Flat"))
    button.toggle_mode = true
    button.focus_mode = Control.FOCUS_NONE
    button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    var follower := Follower.new(button, views if views.is_valid() else SaEnvironmentView.main)
    button.add_child(follower)
    button.toggled.connect(follower.drive)
    return button


## The follower under *button*, which a suite asks to read the view at once.
static func follower_of(button: Button) -> Follower:
    return button.get_node_or_null(Follower.NODE_NAME) as Follower if button != null else null


## Reads the switch, the word and the reason off the view every frame, and
## hands a press to it. A child of the button and not a subclass of it, so the
## button is the made `Button` the harness and the theme read like any other.
class Follower:
    extends Node

    const NODE_NAME := "Follower"

    var _button: Button
    ## Answers the `SaEnvironmentView` to show and drive, or null.
    var _views: Callable

    func _init(button: Button = null, views: Callable = Callable()) -> void:
        _button = button
        _views = views
        name = NODE_NAME

    func _ready() -> void:
        _button.theme_changed.connect(_fit_width)
        _fit_width()
        sync()

    func _process(_delta: float) -> void:
        sync()

    func sync() -> void:
        var view: SaEnvironmentView = _views.call() if _views.is_valid() else null
        var on := view != null and view.on
        var reason: String = view.refusal() if view != null else String(tr("There is no canvas to look at."))
        if _button.button_pressed != on:
            _button.set_pressed_no_signal(on)
        var word: String = tr("Environment") if on else tr("Flat")
        if _button.text != word:
            _button.text = word
        var lock: bool = not on and not reason.is_empty()
        if _button.disabled != lock:
            _button.disabled = lock
        var tip: String = (
            reason
            if lock
            else String(
                tr("Flat or Environment: a panorama seen from inside, where the pan tool turns the view, or a disc face on.")
            )
        )
        if _button.tooltip_text != tip:
            _button.tooltip_text = tip

    func drive(wanted: bool) -> void:
        var view: SaEnvironmentView = _views.call() if _views.is_valid() else null
        if view != null:
            view.set_on(wanted)
        sync()

    ## As wide as the wider of its two words, so the bar does not shift when
    ## the button changes.
    func _fit_width() -> void:
        var shown := _button.text
        var widest := 0.0
        for word: String in ["Flat", "Environment"]:
            _button.text = tr(word)
            _button.custom_minimum_size.x = 0.0
            widest = maxf(widest, _button.get_minimum_size().x)
        _button.text = shown
        _button.custom_minimum_size.x = widest
