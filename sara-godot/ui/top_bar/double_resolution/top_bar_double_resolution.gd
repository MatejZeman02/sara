## The top bar's Double Resolution toggle, and every view of it a custom docker
## holds, all showing and driving the switch on the document in front,
## `SaDocument.double_resolution`.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Registered as a `TopMenuBar` element with a view through
## `SaSettings.register_layout_element`, the door a module's element takes, as
## the Environment View toggle is, so a custom docker can place it too. The
## switch is the document's and not the button's, so the bar's button and a
## docker's read the same state every frame, follow a change of tab, and
## neither keeps a copy. Greyed with its reason while no document is open.
class_name SaTopBarDoubleResolution
extends RefCounted

## The layout key, English like every other key and translated on the button.
const ELEMENT := "Double Resolution"
const CATEGORY := "TopMenuBar"
## The node name of every button, the bar's and a docker's.
const NODE_NAME := "DoubleResolutionToggle"
## The icon the button shows, from `assets/icons/`: a square of four smaller
## squares, four texels where there was one. The drawn "2x" of
## `double_resolution.svg` read as two letters on the bar.
const ICON := "double_resolution_texels"
## The command View > Double Resolution runs, the button's press as a command
## so the menu's tick, a chord and Quick Favourites reach the switch.
const COMMAND := &"view_double_resolution"


## Registers the element and its view, through the door a module uses. Its
## place on a fresh bar is the skeleton's default order's. *documents* answers
## the `SaDocument` the buttons drive, the front canvas's when empty, which is
## every caller but a suite with a document of its own. A second call replaces
## the first, so a suite puts the shipped one back by calling this without one.
static func register(documents: Callable = Callable()) -> void:
    var builder := func() -> Control: return make(null, documents)
    SaSettings.register_layout_element(CATEGORY, ELEMENT, ELEMENT, false, "", builder)


## Registers [constant COMMAND] against *ctx*. It turns the switch of the
## document in front, or with no front canvas, which is a suite's, of *ctx*'s
## easel's document, and is dimmed with no document at all.
static func register_command(ctx: SaContext) -> void:
    var reach := SaContext.new(ctx.easel_provider, ctx.surface_provider)
    var document_of := func() -> SaDocument:
        var front := Follower.front_document()
        if front != null:
            return front
        var easel := reach.get_easel()
        return easel.document if easel != null else null
    var flip := func() -> bool:
        var document: SaDocument = document_of.call()
        if document != null:
            document.double_resolution.turn(document, not document.double_resolution.on)
        return true
    var command := SaCommandDescriptor.create(COMMAND, "Double resolution", flip)
    command.label = "Double Resolution"
    command.category = &"view"
    command.sentence = "New paint layers hold four times the texels, for fine work zoomed in."
    command.checked = func() -> bool:
        var document: SaDocument = document_of.call()
        return document != null and document.double_resolution.on
    command.enabled = func() -> bool: return document_of.call() != null
    ctx.register_command(command)


## The bar's own button under *host*, built the first time and found there
## after, as the element map the bar's rows order. *documents* as for
## [method register].
static func home(host: Node, documents: Callable = Callable()) -> Dictionary:
    if host == null:
        return {}
    register(documents)
    var button := host.get_node_or_null(NODE_NAME) as Button
    if button == null:
        button = make(host, documents)
    return {ELEMENT: button}


## Element key -> group, beside [method home]: it says what the next layer is
## made at, which is about the document and not the brush, so it sits in the
## view's group with the Environment View toggle, the other document switch.
static func groups() -> Dictionary:
    return {ELEMENT: SaOptionSpec.BAR_GROUP_VIEW}


## A button that shows and drives the switch, under *parent* or loose. It shows
## the four squares of [constant ICON], with the label 2x where the icon cannot
## be loaded, rather than its name, which would cost the second row 150 pixels
## it has not got at 1920. The name is the tooltip's first words and the
## element's row in Preferences.
##
## Shaped by `SaBarIconButton` as Undo and the erase toggle are. With the icon
## set to expand and no least size of its own, the button would shrink to the
## 8 by 8 pixels of its box's margins and draw the icon into no room at all, so
## the bar would show no icon.
##
## Boxed by `SaTheme.make_toggle`, as Keep Blend Mode is, so on is the accent
## fill and not the theme's plain pressed box, which on the bar read as a shade
## off its hover. The box under the pointer while on is the pressed one too, so
## a painter reaching for the button still sees it on.
static func make(parent: Node, documents: Callable = Callable()) -> Button:
    var button := SaMake.button(parent, NODE_NAME, TranslationServer.translate("%sx") % "2")
    SaBarIconButton.shape(button, ICON, button.text)
    button.toggle_mode = true
    SaTheme.make_toggle(button)
    button.add_theme_stylebox_override("hover_pressed", SaTheme.make_toggle_style("pressed"))
    button.focus_mode = Control.FOCUS_NONE
    var follower := Follower.new(button, documents if documents.is_valid() else Follower.front_document)
    button.add_child(follower)
    button.toggled.connect(follower.drive)
    return button


## The follower under *button*, which a suite asks to read the switch at once.
static func follower_of(button: Button) -> Follower:
    return button.get_node_or_null(Follower.NODE_NAME) as Follower if button != null else null


## Reads the switch off the document in front every frame, and hands a press to
## it. A child of the button and not a subclass of it, so the button is the made
## `Button` the harness and the theme read like any other.
class Follower:
    extends Node

    const NODE_NAME := "Follower"

    var _button: Button
    ## Answers the `SaDocument` to show and drive, or null.
    var _documents: Callable

    func _init(button: Button = null, documents: Callable = Callable()) -> void:
        _button = button
        _documents = documents
        name = NODE_NAME

    ## The document of the canvas in front, or null while there is none.
    static func front_document() -> SaDocument:
        var canvas := SaCanvasView.front_canvas()
        return canvas.document if canvas != null else null

    func _ready() -> void:
        sync()

    func _process(_delta: float) -> void:
        sync()

    func sync() -> void:
        var document: SaDocument = _documents.call() if _documents.is_valid() else null
        var on := document != null and document.double_resolution.on
        if _button.button_pressed != on:
            _button.set_pressed_no_signal(on)
        var lock := document == null
        if _button.disabled != lock:
            _button.disabled = lock
        var tip: String = (
            String(tr("There is no document to make layers in."))
            if lock
            else (
                String(tr("Double Resolution is on.") if on else tr("Double Resolution is off."))
                + "\n"
                + String(tr("Double Resolution: new paint layers hold four times the texels, for fine work zoomed in."))
                + " "
                + String(tr("Layers already painted are left as they are."))
            )
        )
        if _button.tooltip_text != tip:
            _button.tooltip_text = tip

    func drive(wanted: bool) -> void:
        var document: SaDocument = _documents.call() if _documents.is_valid() else null
        if document != null:
            document.double_resolution.turn(document, wanted)
        sync()
