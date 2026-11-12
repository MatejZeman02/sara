## The switch that says On or Off on its face: a toggle button whose word is its
## state, at the width of its longer word so its edge never moves when it turns.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Tool Options docker and the brush editor dress their `BOOL` rows and the
## editor its page switch through this one class, so the two surfaces cannot
## drift apart, rather than a long coloured bar with nothing saying which state
## it is in or a small `CheckButton` at the far end of a title.
##
## A `Node` hung on the button rather than a `Button` of its own, because the
## rows' toggles are built by `ToolOptionControls` for both surfaces and only
## dressed here, the way `SaSettingsRows.SwitchWord` dresses a Preferences
## switch. The word is read on a toggle and on every draw, since a value mirrored
## onto the button with `set_pressed_no_signal` emits nothing but redraws it.
class_name SaOnOffSwitch
extends Node

## The child's name, which is how a suite and a dump tell a dressed switch.
const NODE_NAME := "OnOff"

var _button: Button


## A new switch reading *pressed*, under *parent* as *node_name*. The brush
## editor's page switch and the switch above each of several graphs on a page.
static func make(parent: Node, node_name: String, pressed: bool) -> Button:
    var button := SaMake.button(parent, node_name)
    button.toggle_mode = true
    button.button_pressed = pressed
    button.custom_minimum_size.y = SaUI.px(SaUI.BASE_ICON_SIZE + 2)
    button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    SaTheme.make_toggle(button)
    dress(button)
    return button


## Makes *button*, a toggle, say On or Off, and answers what it hung on it. A
## button already dressed is answered as it is.
static func dress(button: Button) -> SaOnOffSwitch:
    var had := of(button)
    if had != null:
        return had
    return SaOnOffSwitch.new(button)


## What dresses *button*, or null for a button that is not an On/Off switch.
static func of(control: Control) -> SaOnOffSwitch:
    if control == null or not control.has_node(NODE_NAME):
        return null
    return control.get_node(NODE_NAME) as SaOnOffSwitch


## Puts *button*'s word back on what it holds now, for a reader that asks before
## the next draw. Nothing for a button that is not dressed.
static func refresh(button: Control) -> void:
    var dressed := of(button)
    if dressed != null:
        dressed.read()


## The word a switch holding *on* says.
static func word(on: bool) -> String:
    return TranslationServer.translate("On") if on else TranslationServer.translate("Off")


func _init(button: Button) -> void:
    _button = button
    name = NODE_NAME
    button.toggle_mode = true
    # A switch rather than a field: stretched across a value column it read as
    # an empty text box, and as a coloured bar on the brush editor's pages. It
    # sits at the column's start at the width `read` holds.
    button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    # An iconed toggle centres its icon, which drew it over the word, so the
    # icon leads and the word follows it.
    button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
    button.clip_text = false
    button.add_child(self)
    # Methods and never lambdas, so the button holds this node's id and no
    # reference that could keep it.
    button.toggled.connect(_on_toggled)
    button.draw.connect(read)
    read()


## Writes the word for the state the button holds, and holds the button at the
## width of the longer word. Measured on every read rather than once, because a
## row's font scale is applied after the row is built, and from the font rather
## than by writing both words into the button, which inside a draw would queue
## another draw.
func read() -> void:
    var said := word(_button.button_pressed)
    var font := _button.get_theme_font(&"font")
    var points := _button.get_theme_font_size(&"font_size")
    var widest := 0.0
    for each: String in [word(true), word(false)]:
        widest = maxf(widest, font.get_string_size(each, HORIZONTAL_ALIGNMENT_LEFT, -1, points).x)
    widest += _button.get_theme_stylebox(&"normal").get_minimum_size().x
    # An expanding icon asks for no room of its own and is drawn in whatever
    # the word leaves, which at the word's own width is nothing at all.
    if _button.icon != null:
        widest += _button.get_theme_constant(&"icon_max_width") + _button.get_theme_constant(&"h_separation")
    widest = ceilf(widest)
    if not is_equal_approx(_button.custom_minimum_size.x, widest):
        _button.custom_minimum_size.x = widest
    if _button.text != said:
        _button.text = said


func _on_toggled(_on: bool) -> void:
    read()
