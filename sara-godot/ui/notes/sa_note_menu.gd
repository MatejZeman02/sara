## The open menu a note is about, and the item in it.
##
## Two kinds of menu open in Sara. A `PopupMenu`, the engine's, behind an
## `OptionButton`: its items have no geometry and `get_focused_item()` is the
## only per-item answer it gives, so the mark outlines the whole window and the
## tag names the item inside it. And an `SaChoicePopup`, the app's own list and
## every menu under the top bar: its rows are controls, so the row under the
## pointer is found by rectangle, outlined on its own, and is what the note
## freezes on. Until this class the second kind was read as any other popup,
## whose owner is what a note is about, and a note taken over the Image menu
## named the title bar with no Item line at all.
##
## Split out of `sa_note_mode.gd` because that file stood at the 700-line rule
## with the first kind alone, and which menu is open and which line of it the
## pointer is on is a thing of its own to own.
class_name SaNoteMenu
extends RefCounted

## The open menu, a `PopupMenu` or an `SaChoicePopup`, and the item in it.
## Written here only, by `take()` and `clear()`, and read by the mode.
var window: Window = null
var index: int = -1

## The engine menu made deaf for the click, and the setting it had before.
var _hushed: PopupMenu = null
var _hushed_hides: bool = true


func clear() -> void:
    window = null
    index = -1


## Takes what `under_pointer()`, `item_at()` or `item_of()` answered, or nothing.
func take(item: Dictionary) -> void:
    window = item.get("menu")
    index = int(item.get("index", -1))


func is_set() -> bool:
    return window != null and index >= 0


func same_as(item: Dictionary) -> bool:
    return item.get("menu") == window and int(item.get("index", -1)) == index


## The item's text, as the menu shows it.
func text() -> String:
    var popup := window as SaChoicePopup
    if popup != null:
        var ids := popup.row_ids()
        if index < 0 or index >= ids.size():
            return ""
        var button := popup.label_button(ids[index])
        return button.text if button != null else ""
    var engine_menu := window as PopupMenu
    if engine_menu != null and index >= 0 and index < engine_menu.item_count:
        return engine_menu.get_item_text(index)
    return ""


## How many items the menu has. Rows only for a choice list, so a heading or a
## gap between rows is not counted as something a painter could pick.
func count() -> int:
    if window is SaChoicePopup:
        return (window as SaChoicePopup).row_ids().size()
    if window is PopupMenu:
        return (window as PopupMenu).item_count
    return 0


## `Screen, item 8 of 20`, the tag drawn on the mark and the entry's Item line.
func tag() -> String:
    if not is_set():
        return ""
    return "%s, item %d of %d" % [text(), index + 1, count()]


## Where the mark goes, in the menu window's own coordinates: the row's own
## rectangle in a choice list, and the whole window for an engine menu, inset
## so the two-pixel border is inside the window rather than half outside it.
func rect() -> Rect2:
    var popup := window as SaChoicePopup
    if popup != null:
        var ids := popup.row_ids()
        if index >= 0 and index < ids.size():
            return popup.row_of(ids[index]).get_global_rect()
    return Rect2(Vector2.ONE * 2.0, Vector2(window.size) - Vector2.ONE * 4.0)


## The item of the open menu the pointer is on: `menu`, `index`, `text` and
## `count`, or empty when no menu is open or the pointer is between items.
##
## *pointer_window* is the window the last motion went to. With embedded
## subwindows off a menu is a window of the operating system and not among the
## embedded ones, and a note under WinTab that searched only those never found the
## row it hovered and drew no yellow mark on it. A window of its own is asked
## only while it has the pointer, because its reading of the mouse is the last
## motion it heard and stays on the row the pointer left.
##
## A menu that stands over *pointer_window*'s reading is asked first, at that
## reading, for the reason `menu_over()` gives. *pointer_window* is never a
## freed window, because a freed object handed to a typed argument is a script
## error of its own, and the mode drops one before it asks.
static func under_pointer(root: Window, pointer_window: Window = null) -> Dictionary:
    if pointer_window != null and pointer_window.is_inside_tree():
        var over := menu_over(pointer_window, pointer_window.get_mouse_position())
        if not over.is_empty():
            var covered := item_in(over["menu"], over["at"])
            if not covered.is_empty():
                return covered
    for sub in menus_to_ask(root, pointer_window):
        var item := item_in(sub, sub.get_mouse_position())
        if not item.is_empty():
            return item
    return {}


## The item of *sub* at *point*, in *sub*'s own space: the row there in a
## choice list, and the focused item of an engine menu, which gives no geometry
## for an item and so answers the same wherever the point is. Empty over a
## heading, a gap, a separator, or a window that is no menu.
static func item_in(sub: Window, point: Vector2) -> Dictionary:
    var popup := sub as SaChoicePopup
    if popup != null:
        return item_at(popup, point)
    var engine_menu := sub as PopupMenu
    if engine_menu == null:
        return {}
    var focused := engine_menu.get_focused_item()
    if focused < 0 or focused >= engine_menu.item_count or engine_menu.is_item_separator(focused):
        return {}
    return {
        "menu": engine_menu,
        "index": focused,
        "text": engine_menu.get_item_text(focused),
        "count": engine_menu.item_count,
    }


## The open menu that stands over *point*, in *heard*'s own space, as `menu`,
## and `at`, the point in the menu's own space. Empty when none does, and when
## *heard* is not in a tree, which has no place on the desktop to measure from.
##
## With subwindows off a menu is a window of the operating system over the main
## one, and an event can still be handed to the window under it. A tap on
## Manual under WinTab went to the main window at a point the Help list
## covered, so the note froze on the canvas under the list while the mark stood
## on Manual. A list stands over every window that is not one, which is
## the rule the ring keeps in `SaCursorPolicy.windows_of_their_own`, so the
## point is the list's whichever window heard it. An embedded list is asked as
## well: the engine hands it its own events first, so the answer there is the
## one it already had.
##
## The deepest list wins where two stand over the point, since a child list
## opens over the one it hangs from.
static func menu_over(heard: Window, point: Vector2) -> Dictionary:
    if heard == null or not heard.is_inside_tree():
        return {}
    var found := {}
    for sub in _open_menus(heard.get_tree().root, heard):
        var over := SaCursorPolicy.rect_in(heard, sub).abs()
        if not over.has_area() or not over.has_point(point):
            continue
        found = {"menu": sub, "at": (point - over.position) * sub.get_visible_rect().size / over.size}
    return found


## Every open menu that could stand over *asked*: embedded or a window of its
## own, never *asked* itself or a window it is drawn inside.
static func _open_menus(root: Window, asked: Window) -> Array[Window]:
    var found: Array[Window] = []
    var windows := SaCursorPolicy.embedded_subwindows(root, true)
    windows.append_array(SaCursorPolicy.windows_of_their_own(root, asked))
    for sub in windows:
        if sub == asked or sub.is_ancestor_of(asked) or not sub.visible:
            continue
        if sub is SaChoicePopup or sub is PopupMenu:
            found.append(sub)
    return found


## The windows `under_pointer()` asks: every embedded one, and ahead of them
## *pointer_window* when it is a menu of its own that is open.
static func menus_to_ask(root: Window, pointer_window: Window) -> Array[Window]:
    var found := SaCursorPolicy.embedded_subwindows(root, true)
    if (
        pointer_window != null
        and is_instance_valid(pointer_window)
        and pointer_window != root
        and pointer_window.visible
        and not pointer_window.is_embedded()
        and (pointer_window is SaChoicePopup or pointer_window is PopupMenu)
    ):
        found.push_front(pointer_window)
    return found


## Closes the menu once the note has its picture, rather than leaving that to
## the focus. A menu of its own need not lose the focus to the box, and one
## left open hears the letters typed for the note: its type-ahead jumps to a
## row and a space chooses it, so a note typed over an open menu chooses one of
## its rows.
func close() -> void:
    if window != null and is_instance_valid(window) and window.visible:
        window.hide()


## The row of *popup* under *point*, in the popup's own coordinates, as an
## item, or empty over a heading, a gap or the list's edge.
static func item_at(popup: SaChoicePopup, point: Vector2) -> Dictionary:
    return item_of(popup, row_holding(SaNoteMode.control_under(popup, point)))


## The item *row* is in *popup*, or empty for a row the list does not hold.
static func item_of(popup: SaChoicePopup, row: SaChoiceRow) -> Dictionary:
    if popup == null or row == null:
        return {}
    var ids := popup.row_ids()
    var at := ids.find(row.id)
    if at < 0:
        return {}
    var button := popup.label_button(row.id)
    return {"menu": popup, "index": at, "text": button.text if button != null else "", "count": ids.size()}


## The row *control* is, or sits in, below its window. Null for anything else,
## so a heading, the search field or a control outside any list answers null.
static func row_holding(control: Control) -> SaChoiceRow:
    var cursor: Node = control
    while cursor != null and not (cursor is Window):
        if cursor is SaChoiceRow:
            return cursor
        cursor = cursor.get_parent()
    return null


## Keeps an engine menu from acting on the click that is taking a note about
## it. A `PopupMenu` reads the release before an overlay's `_input` can swallow
## it, so instead its signals are blocked
## and `hide_on_item_selection` turned off, which keeps it open for the
## photograph and deaf to the pick. Both are put back by `unhush()`, at the end
## of the freeze or on the release, whichever comes first. A choice list needs
## none of this: its rows are buttons, which act on a release the overlay
## swallows first, so `hush(null)` is what the mode calls over one.
func hush(open_menu: PopupMenu) -> void:
    if open_menu == null or _hushed != null:
        return
    _hushed = open_menu
    _hushed_hides = open_menu.hide_on_item_selection
    open_menu.hide_on_item_selection = false
    open_menu.set_block_signals(true)


func unhush() -> void:
    if _hushed == null:
        return
    if is_instance_valid(_hushed):
        _hushed.set_block_signals(false)
        _hushed.hide_on_item_selection = _hushed_hides
    _hushed = null
