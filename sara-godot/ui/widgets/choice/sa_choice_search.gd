## The search field over a long list, and what it hides.
##
## Its own file rather than more of `sa_choice_popup.gd`, cut by
## responsibility: this class owns the field and which rows a needle leaves showing, and the popup
## owns the rows themselves. Nothing here knows what a choice is, and nothing in
## the popup knows how a row is matched.
##
## **A field only appears over `MIN_ROWS`.** The three lists over the line today
## are the blend modes, the colour spaces and the shortcut page's commands, and a
## menu of nine rows with a search box on it reads as a search box that failed to
## find anything. `wanted_for` is the question, asked by the popup as rows are
## added. A menu under the top bar skips the question and always has the field,
## which is the popup's `searched` argument, so that the short menus there look
## like the long ones.
##
## **A section heading lives or dies with its rows.** A filtered list that keeps
## "Darken" over nothing says the filter is broken, and dropping a heading whose
## rows are all still there loses what the list is grouped by. So a heading is
## shown exactly while one of the rows under it is, which is what the walk below
## works out in one pass.
@tool
class_name SaChoiceSearch
extends LineEdit

## The rows left showing after the last `apply`, so the popup can move its
## highlight onto the first of them without walking the column again.
signal filtered(shown: int)

## Escape emptied the field, which is the popup's cue to put its highlight back
## on the first row of the whole list.
signal cleared

## How many rows a list needs before it earns a field: twenty-five gets one,
## nineteen does not.
const MIN_ROWS: int = 20

## The meta on a row or heading the popup's `searching` handler added for the
## needle in the field. A found row was found by its list's own rule rather than
## by its label, so it is shown while the field holds text, whatever its words.
const FOUND := &"sa_choice_found"

var _column: VBoxContainer = null


## The column is a constructor argument rather than an assignment, because a
## private is written by its own class only. Defaulted so `.new()` still works the way Godot
## expects of a Control.
func _init(column: VBoxContainer = null) -> void:
    _column = column
    name = "ChoiceSearch"
    placeholder_text = tr("Search")
    clear_button_enabled = true
    SaSearchField.mark(self)
    visible = false


## Whether a list of *rows* rows is long enough to want a field.
static func wanted_for(rows: int) -> bool:
    return rows > MIN_ROWS


## Hides every row whose label, or second name, does not hold *needle*,
## folded, and answers how many are left. A found row shows while there is a
## needle at all, `FOUND`. An empty needle puts the whole list back, gaps and all.
##
## `contains` rather than `begins_with`, which is the opposite of the popup's
## type-ahead and deliberately so: type-ahead is a jump to a row whose name the
## painter already knows, and a search is for the row whose name they only half
## remember. "dodge" finds Colour Dodge, and no first-letter search would.
func apply(needle: String) -> int:
    if _column == null:
        return 0
    var folded := needle.strip_edges().to_lower()
    var shown := 0
    var heading: Label = null
    var heading_kept := false
    for child in _column.get_children():
        var label := child as Label
        if label != null:
            _close(heading, heading_kept)
            heading = label
            heading_kept = false
            continue
        var line := child as HSeparator
        if line != null:
            # A gap between two groups means nothing once the groups are cut to
            # three rows between them, so the separators go while a filter is on.
            line.visible = folded.is_empty()
            continue
        var row := child as HBoxContainer
        if row == null:
            continue
        var on := folded.is_empty() or matches(row, folded)
        if row.has_meta(FOUND):
            on = not folded.is_empty()
        row.visible = on
        if on:
            shown += 1
            heading_kept = true
    _close(heading, heading_kept)
    filtered.emit(shown)
    return shown


## Whether *row* holds *folded*, a needle already lowered: in its label, or in
## the second name a row of `SaChoiceRow` may carry and never shows. The blend
## list under another language is why there is a second name, a painter typing
## the English Multiply over a row that reads in their own language.
static func matches(row: Control, folded: String) -> bool:
    if label_of(row).to_lower().contains(folded):
        return true
    var choice := row as SaChoiceRow
    return choice != null and not choice.other_name.is_empty() and choice.other_name.to_lower().contains(folded)


## The text a row is matched on first: its label button's, which is the only
## part of a row a painter reads as its name. The shortcut hint beside it is
## deliberately not searched, because "Ctrl" would otherwise match half a menu.
static func label_of(row: Control) -> String:
    var button := row.get_node_or_null("Label") as Button
    return button.text if button != null else ""


## Hears its own window's close, so the field it closes on is never the field
## the list opens with. On entering the tree rather than in `_init`, because the
## popup builds the field before either of them has a window.
func _notification(what: int) -> void:
    if what != NOTIFICATION_ENTER_TREE:
        return
    var window := get_window()
    if window != null and not window.popup_hide.is_connected(_on_window_hidden):
        window.popup_hide.connect(_on_window_hidden)


## A list that closes, by a chosen row, a click outside, Escape or its own
## button, takes its needle with it, so the next open shows the whole list and
## not the rows the last search left. The way an `OptionButton` and the blend
## lists of Photoshop and Krita behave.
##
## Through `text_changed` rather than `apply` alone, because the popup hears the
## field there and does what a needle's going asks beyond hiding rows: the rows
## its list found for the needle go, and the keyboard lands on the first row.
## Setting `text` from a script emits nothing, so the signal is sent here.
##
## An Escape that emptied the field first has already done all of this, and the
## popup reopens itself from that close, so a field already empty is left alone.
func _on_window_hidden() -> void:
    if text.is_empty():
        return
    text = ""
    text_changed.emit("")


static func _close(heading: Label, kept: bool) -> void:
    if heading != null:
        heading.visible = kept


## Escape empties the field before anything else sees the key, which is what
## every search box does: one escape undoes the search, a second leaves the list.
##
## **Here rather than in the popup**, and this is the whole reason the field
## handles input at all. `Popup::_input` closes the window on `ui_cancel` in the
## engine's own C++, and a script `_input` on the popup itself cannot get in
## front of it, so the first escape would close the list with letters still in
## the field. `_input` walks the tree from the
## leaves up, so a child of the popup is asked first, and this is a child.
func _input(event: InputEvent) -> void:
    if not visible or text.is_empty():
        return
    var key := event as InputEventKey
    if key == null or not key.pressed or key.echo or key.keycode != KEY_ESCAPE:
        return
    text = ""
    apply("")
    cleared.emit()
    if is_inside_tree():
        # Marked handled even though the engine closes the popup anyway, so
        # nothing further down acts on the same key. `sa_choice_popup.gd`'s
        # `_on_popup_hidden` is what puts the window back.
        get_viewport().set_input_as_handled()
