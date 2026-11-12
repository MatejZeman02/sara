## The bar's menus as views another docker can hold: a button with the menu's
## title that opens that menu's own list beside it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## What a custom docker can place is exactly the registered layout elements, and
## the eleven menus, File to Help, are the first entries of the bar's order. A
## placed one is a second view of the same state as at home, and a menu's state
## is its list: the rows, their ticks, which are
## dimmed and the commands behind them. So a view opens the bar's own list
## rather than one built alike. The bar fills that list before every open from
## what the canvas holds then, so the list a view opens is the list the title
## opens, row for row, and a press on a row runs what it runs from the bar. A
## list built alike would be a second filler per menu, and the Layer menu's
## document, the View menu's two calls into the bar and the Window menu's
## docker rows would each have to be handed to it a second time.
##
## Registered through `SaSettings.register_layout_element`, the call a module
## makes for an element of its own, which is hard rule 6, a built-in using the public door, and called from
## `TopMenuBar._ready`. The bar hands in the callable that opens a menu beside a
## control, so nothing here names the bar or reaches into it.
class_name SaMenuViews
extends RefCounted

## The Preferences category the bar's elements are filed under.
const CATEGORY: String = "TopMenuBar"


## Registers a view of each menu of *names* through the door a module uses.
##
## *opens* is called with a menu's name and the view pressed, and opens that
## menu's list beside the view, or closes it when it is up. A second call
## replaces the first, so a bar built again hands its own.
static func register(names: Array, opens: Callable) -> void:
    for m_name: String in names:
        var builder := func() -> Control: return MenuView.new(m_name, opens)
        SaSettings.register_layout_element(CATEGORY, m_name, m_name, false, "", builder)


## One menu's view. Drawn as a dropdown, the menu's title with the arrow every
## list in a docker has, because in a docker the bar's flat title would read as
## a label. It answers on the press, as the bar's title does, so a press on the
## view while its list is up is the close rather than a second open.
class MenuView:
    extends Button

    ## The menu this view opens, "Filter".
    var menu_name: String = ""

    ## Opens or closes the menu's list beside a control, the bar's own.
    var _opens: Callable

    func _init(for_menu: String, opens: Callable) -> void:
        menu_name = for_menu
        _opens = opens
        name = for_menu + "MenuView"
        set_meta(SaMake.KIND_META, SaMake.Kind.BUTTON)
        focus_mode = Control.FOCUS_NONE
        action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
        SaTheme.make_dropdown(self)
        text = TopMenuBar.menu_title(for_menu)
        pressed.connect(open_list)

    ## Dimmed while no bar is there to open the list, which a suite that freed
    ## its bar leaves behind and the running app never does.
    func _notification(what: int) -> void:
        if what == NOTIFICATION_ENTER_TREE:
            disabled = not _opens.is_valid()
        elif what == NOTIFICATION_TRANSLATION_CHANGED:
            text = TopMenuBar.menu_title(menu_name)

    ## Opens the menu's list beside this view, or closes it when it is up.
    func open_list() -> void:
        if _opens.is_valid():
            _opens.call(menu_name, self)
