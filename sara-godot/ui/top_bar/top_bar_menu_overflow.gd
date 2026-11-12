## The menu row's last title, and the list it opens with every menu title that
## did not fit on the row.
##
## A host 640 logical pixels wide, 1280 by 1024 or 1280 by 800 at scale 2, held
## the window buttons and not quite all of the eleven titles, and the row ran on
## past the window's edge: Modules was cut there, and Help, the window buttons
## and the tool options' overflow button were past it, where no press reaches.
## The titles that do not fit leave the row from its end and are listed behind
## this one, the way the overflow button at the end of the tool options holds
## the controls that do not fit and the way Qt's own menu bar folds its titles
## behind a chevron. The order is the profile's, so with the shipped one the
## titles leave from Help backwards.
##
## A row of the list opens its menu under this title rather than beside the
## list as a child of it. A menu's dialogs go where its popup is parented,
## `SaMenu.host`, and a popup moved under this list for a submenu would take
## them into a window that closes when the menu does.
##
## Which titles fit is decided here, from the room `SaTopBarRows` measures for
## the menus, and the menu a row names is opened by the bar, whose menus they
## are. The list is a child of the button so it goes when the button does,
## which is how `SaDropdownButton` keeps its own.
class_name SaTopBarMenuOverflow
extends Button

## A row of the list was pressed, and the list has closed. The bar opens
## *menu_name*'s own list under this title.
signal menu_asked(menu_name: String)

## The title's text, the chevron a menu bar draws for the titles it could not
## fit.
const LABEL := "»"

## The list this title opens, one row per title that did not fit.
var list: SaChoicePopup

## The titles that did not fit, by the name the profile stores, in the row's
## order. Empty while every title the profile shows is on the row.
var folded: Array[String] = []

## The row of titles this folds, which is the bar's.
var _titles: HBoxContainer

## The process frame the list was last hidden in, or -1 for never. A press in
## that frame is the close itself, `SaDropdownButton`'s rule.
var _closed_frame: int = -1


## *titles* is the bar's row of menu buttons, and *box* the look every title on
## it has, so this one reads as one more of them.
func _init(titles: HBoxContainer, box: StyleBox) -> void:
    name = "MenuOverflowButton"
    _titles = titles
    text = LABEL
    flat = true
    focus_mode = FOCUS_NONE
    # On the press, like every title on the bar, so a press while the list is
    # open finds it still showing and is the close.
    action_mode = ACTION_MODE_BUTTON_PRESS
    size_flags_vertical = SIZE_SHRINK_CENTER
    visible = false
    tooltip_text = tr("Menus that do not fit on the bar.")
    for state: String in ["normal", "pressed", "focus"]:
        add_theme_stylebox_override(state, box)

    var made := SaChoicePopup.new(true, false)
    made.name = "MenuOverflowList"
    made.popup_hide.connect(_on_list_hidden)
    made.chosen.connect(_on_chosen)
    # A press outside it puts it away and goes no further, as a menu's does.
    SaPutAway.join(made)
    add_child(made)
    list = made
    pressed.connect(toggle_list)


## Shows every title the profile shows, from the row's start, while the next
## one still fits in *room* logical pixels, and folds the rest behind this
## title, which shows only while it holds one. Room for this title is taken
## only when a title has to leave, so a row where all eleven fit is the row as
## it was. What the holder keeps after this title, the search's loupe, is taken
## off *room* first and always, so a narrow window folds a title rather than
## push the loupe off the row.
func fit(room: float) -> void:
    var shown: Array[Button] = []
    for child in _titles.get_children():
        var title := child as Button
        if title != null and SaSettings.get_element_visible("TopMenuBar", String(title.name)):
            shown.append(title)
    var gap := float(_titles.get_theme_constant("separation"))
    var holder := get_parent() as Container
    var own_gap := float(holder.get_theme_constant("separation")) if holder != null else 0.0
    var limit := room
    for child in holder.get_children() if holder != null else []:
        var kept := child as Control
        if kept != null and kept != _titles and kept != self and kept.visible:
            limit -= kept.get_combined_minimum_size().x + own_gap
    if _width_of(shown, gap) > limit:
        limit -= get_combined_minimum_size().x + own_gap
    folded.clear()
    var used := 0.0
    for title in shown:
        var cost := title.get_combined_minimum_size().x + (gap if used > 0.0 else 0.0)
        if folded.is_empty() and used + cost <= limit:
            used += cost
            title.visible = true
        else:
            folded.append(String(title.name))
            title.visible = false
    visible = not folded.is_empty()
    if not visible:
        list.hide()


## What *titles* take side by side, each with the gap before it but the first.
static func _width_of(titles: Array[Button], gap: float) -> float:
    var total := 0.0
    for title in titles:
        total += title.get_combined_minimum_size().x
    if titles.size() > 1:
        total += gap * float(titles.size() - 1)
    return total


## Opens the list under this title, filled with the titles that did not fit,
## or closes it when it is open. A press in the frame the list was closed in
## is that same close and opens nothing.
func toggle_list() -> void:
    if list.visible:
        list.hide()
        return
    if _closed_frame == Engine.get_process_frames():
        return
    open_list()


## Opens the list under this title, filled with the titles that did not fit,
## without asking whether it closed in this frame, which is a press's question.
## The pointer arriving on this title opens it here, since the list it left may
## have closed a moment ago and the pointer has not pressed anything.
func open_list() -> void:
    list.clear()
    for menu_name in folded:
        list.add_row(StringName(menu_name), TopMenuBar.menu_title(menu_name))
    list.open_under(self)


func _on_list_hidden() -> void:
    _closed_frame = Engine.get_process_frames()


func _on_chosen(id: StringName) -> void:
    menu_asked.emit(String(id))


## The title and its list as numbers, for a capture and a suite: whether it
## shows, where it stands, which titles it holds and which stayed on the row.
func report() -> Dictionary:
    var on_row: Array = []
    for child in _titles.get_children():
        var title := child as Button
        if title != null and title.visible:
            on_row.append(String(title.name))
    var rect := get_global_rect() if is_inside_tree() else Rect2()
    return {
        "shown": visible,
        "folded": folded.duplicate(),
        "on_row": on_row,
        "x": rect.position.x,
        "w": rect.size.x,
        "list_open": list.visible,
        "list_rows": Array(list.row_labels()),
    }
