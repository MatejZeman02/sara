## A list of choices as rows of controls rather than as menu items.
##
## **The reason it is not a `PopupMenu`.** A menu item has no geometry of its own
## and takes one press, so a row that picks a value and carries a second control
## cannot be one. The shape this file exists for is a label that is a button
## choosing the value and a box alongside it that adds the value to the
## favourites.
##
## So a row is a `Button` carrying the label and, when the caller asks for one, a
## `CheckBox` beside it. The box marks and **leaves the popup open**, because
## marking several is the gesture, and the label of a row with a box presses the
## box, the two being one act. A plain row's label chooses and closes, and so
## does every label in a list built with `label_ticks` false, the blend list,
## whose box is a favourite beside a choice rather than the row's own state.
##
## **No radio anywhere.** `harness/drivers/tests/test_menu_choice.gd` fails the run over a radio
## item, and the choice reads as a highlighted row the way `menu_choice.gd` makes
## a `PopupMenu` read. Here it is a theme colour on the chosen row's own button,
## which is what a control that has a rect can do and a menu item cannot.
##
## Built as its own file rather than inside the blend button because every list
## in Sara takes it: labels as buttons, one of them always selected, and no
## radio anywhere. Nothing here knows what a blend mode is.
##
## **A list over twenty rows opens with a search field**, which is
## `SaChoiceSearch` beside this file: it owns the field and which rows a needle
## leaves showing, and this class owns the rows. A shorter list opens without
## one, so nine rows never carry a search box that failed to find anything.
## A menu under the top bar is the exception, `_searched` below.
##
## **It is the app's menu**, rather than the engine's `PopupMenu`, which
## looks out of place and cannot carry a note inside it. So a row also takes an icon at the row's height, a shortcut hint and a
## disabled state, and the list answers the arrow keys, enter, escape, a row's
## underlined letter (`SaChoiceLetters`) and type-ahead, none of which a
## `PopupMenu` item can be told.
##
## **Two ways of marking the chosen row.** A list of plain buttons marks it with
## the accent colour, which is what the blend list needed. A list `one_of` turns
## on makes every row a toggle in one `ButtonGroup`, so the mark is the engine's
## pressed stylebox, which stays under the pointer where a `PopupMenu`'s only
## highlight, `hover`, follows it and leaves the choice unreadable while a
## painter chooses.
##
## **A row can open a child list beside it**, one per section.
## `add_branch_row` draws such a row, and a press, a
## resting pointer or the right arrow on it emits `branched` instead of closing
## the list, so the caller fills a second `SaChoicePopup` and hands it to
## `open_child`. The child is a window under this one, which is what makes the
## engine keep this list open while the child holds the keyboard, and it closes
## with this list, closes this list when it chooses, and gives the keyboard back
## when escape or the left arrow closes it alone.
@tool
class_name SaChoicePopup
extends PopupPanel

## A label that chooses was pressed. The popup closes on this.
signal chosen(id: StringName)

## A row's check box moved, from the box or from its label. The popup stays open.
signal marked(id: StringName, on: bool)

## A row `add_branch_row` drew asked for its child list, by a press, by the
## pointer resting on it or by the right arrow. The popup stays open, and the
## caller answers with `open_child`.
signal branched(id: StringName)

## The search's text changed, and the rows the last needle found were taken
## away. A row or heading added while this is answered is a found one, shown
## while the field holds text, so a list can offer what its column does not
## hold, the way the Filter menu finds the filters inside its sections.
signal searching(needle: String)

## The tallest a capped list goes before it scrolls, in logical pixels. A blend
## registry of twenty-odd modes would otherwise open taller than a 1080 screen.
const MAX_HEIGHT: int = 520

## The chosen row's own colour, taken from the theme's accent rather than from a
## stylebox, so a row reads as picked without a dot beside every row that is not.
const CHOSEN_ALPHA: float = 1.0
const PLAIN_ALPHA: float = 0.82

## How far a row that takes no press is faded. Dimmed **and** disabled, because
## a control a painter cannot press has to look like one, and a row that only
## looks pressable is the worse of the two bugs. 0.80 rather than a deeper fade
## such as 0.45, which leaves white text under 3 to 1 on every palette Sara
## ships, so a painter could not read why a row is off. 0.80 holds at least 3 to
## 1 on all six. A menu's rows are flat and draw no box, so what says
## a row is off is its text, `text_muted` where a plain row is `text_primary`,
## which is at least 0.15 of lightness apart in every palette. A suite holds both.
const DISABLED_ALPHA: float = 0.80

## A row's least height in logical pixels, and the widest an icon on it may be
## drawn. The height is on every row and not only on the ones carrying an icon,
## which is what keeps a list of mixed rows from stepping: without it Duplicate
## and Clear would tower over Merge Down, because a
## `PopupMenu` draws an icon at the texture's own size and grows the item around
## it.
const ROW_HEIGHT: int = 24
const ICON_SIZE: int = 18
## The width of the slot a menu keeps at its rows' left for a tick.
const TICK_SLOT: int = 24

## How long a type-ahead keeps collecting letters before the next one starts a
## new search, in milliseconds. Long enough to type "brigh" at a normal speed,
## short enough that a letter typed after a pause means the letter.
const TYPE_AHEAD_GAP_MS: int = 900

## How long the pointer rests on a row before its child list opens, or before an
## open child closes because the pointer went to another row, in seconds. The
## engine's own submenu delay, so a pointer crossing the rows on its way to the
## child does not open and close every list it passes.
const HOVER_DELAY: float = 0.2

var _body: VBoxContainer = null
var _scroll: ScrollContainer = null
var _column: VBoxContainer = null
## The search field, hidden until the list is long enough to want one. Public
## because a scenario presses it and a test reads its text, and written only
## here.
var search: SaChoiceSearch = null
## Row id -> its `SaChoiceRow`, so a mark can be moved without a search and a
## capture can find a row by what it holds rather than by index.
var _rows: Dictionary = {}
## The ids in the order they were added, because a Dictionary's order is its
## insertion order and a reader should not have to know that.
var _order: Array[StringName] = []
var current: StringName = &""
## Where the keyboard is, as an index into `_order`, or -1 for nowhere. Separate
## from `current`: the mark says what is chosen and this says what enter would
## choose, and on an open menu those are usually two different rows.
var _highlight: int = -1
## The letters typed so far and when the last one arrived, for the type-ahead.
var _typed: String = ""
var _typed_at_ms: int = 0
## Where to put the window back after an escape that only meant to empty the
## search field, or a zero rect for a hide that meant to close. See
## `_on_popup_hidden`.
var _reopen_at: Rect2i = Rect2i()
## Whether the rows are toggles in one `ButtonGroup`, which is what makes the
## mark survive the pointer. Set before the first `add_row`.
var one_of: bool = false
var _group: ButtonGroup = null
## Whether the label of a row with a box presses the box, and whether the list
## stops at `MAX_HEIGHT` before the room does, which a top bar menu does not.
var _label_ticks: bool = true
var _capped: bool = true
## Whether the last `wanted_size` already widened the list for its scroll bar,
## which `SaPopupRect.with_bar` reads so a list is not widened twice.
var _bar_asked: bool = false
## Whether the rows of this menu keep a slot at their left for a tick. On from
## the first row that carries a box, in a menu (a list that is not capped) whose
## label presses its box, so a ticked row and an unticked one start their words
## at one x and the shortcut column has one edge. Off again on `clear`.
var _tick_slot: bool = false
## Whether the field shows however few rows there are. Set by a menu under the
## top bar, because a painter should not have to know which menus are long. Every other list keeps the twenty row line.
var _searched: bool = false
## The rows that open a child list rather than choose, row id -> true.
var _branches: Dictionary = {}
## The child list `open_child` last opened, or null, and the row it hangs from.
## Read by the suites and the state dump, written only here.
var child_list: SaChoicePopup = null
var child_row: StringName = &""
## The row the pointer came to rest on last, which the hover delay reads back
## when it runs out.
var _rested: StringName = &""
## The control the list opened under, asked again by every search.
var _anchor: Control = null
## Whether a `searching` handler is adding rows, which marks them found.
var _finding: bool = false
## The rows kept between builds, `SaChoiceKeep`, for a list built with *keeps_rows*,
## or null for one that frees its rows on `clear`. Read by the suites.
var row_keep: SaChoiceKeep = null


func _init(label_ticks: bool = true, capped: bool = true, searched: bool = false, keeps_rows: bool = false) -> void:
    _label_ticks = label_ticks
    _capped = capped
    _searched = searched
    # An opaque panel of its own. A `PopupPanel` takes the engine's default
    # `panel` stylebox, which is transparent under Sara's theme, and the first
    # capture showed four rows floating over the docker underneath with the
    # swatch row reading through them. The theme pass does not reach a popup,
    # which `sa_ui.gd` already says of every other one, so it is drawn here from
    # the palette rather than waited for. Bound rather than read once: the rows'
    # own font colours follow a palette switch and this panel did not, so a menu
    # built under a dark palette kept its dark ground and drew the light
    # palette's near-black words on it.
    var panel := StyleBoxFlat.new()
    SaTheme.bind(panel, {"bg_color": "bg_panel", "border_color": "border_secondary"})
    panel.set_border_width_all(1)
    panel.set_corner_radius_all(SaUI.px(4))
    panel.set_content_margin_all(float(SaUI.px(6)))
    add_theme_stylebox_override("panel", panel)

    # A column of two under the panel: the field, which is usually hidden, and
    # the scrolling list. A `PopupPanel` lays one child out to fill it, so the
    # pair has to be one node.
    _body = SaMake.column(self, "ChoiceBody", SaTheme.GAP_TIGHT)

    _scroll = SaMake.scroll(null, "ChoiceScroll")
    _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    _scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

    _column = SaMake.column(_scroll, "ChoiceColumn", 2)
    _column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    if keeps_rows:
        row_keep = SaChoiceKeep.new(_column)
    search = SaChoiceSearch.new(_column)
    search.text_changed.connect(_on_search_typed)
    search.cleared.connect(_on_search_cleared)
    search.filtered.connect(func(_shown: int) -> void: SaPopupRect.refit(_anchor, self, wanted_size))
    popup_hide.connect(_on_popup_hidden, CONNECT_DEFERRED)
    about_to_popup.connect(_settle)
    about_to_popup.connect(_attach_cursor)
    popup_hide.connect(_detach_cursor)
    popup_hide.connect(close_child)
    _body.add_child(search)
    _body.add_child(_scroll)


## Gives the open list a `CursorOverlay` of its own, the way a docker and a
## dialog have one, so Sara's pointer is drawn over its rows.
##
## **The list stays a window.** A window has its own viewport and a control can
## draw inside one viewport only, so the main window's overlay would draw the
## pen's arrow under the list with embedded subwindows on and nothing at all
## over it with them off. With an overlay here
## the cursor policy reads the list as a window where the pointer is certainly
## drawn, and a pen under Wayland, whose driver gives it no cursor over any
## window, has Sara's arrow on every row. A mouse keeps the system pointer, as it
## does over a docker.
##
## On every open rather than in `_init`, because every caller opens the list
## through `popup` whichever way it measures the rectangle, and `about_to_popup`
## is the one signal they all pass through.
func _attach_cursor() -> void:
    if Engine.is_editor_hint() or not is_inside_tree():
        return
    CursorOverlay.attach_to(self)


## Takes the overlay off a closed list, so the lists a session opened once do
## not each check the pointer every frame for the rest of it. At once rather
## than deferred, so the escape that only empties the search field, which hides
## the list and opens it again from `_on_popup_hidden` a moment later, finds no
## overlay on its way out and `about_to_popup` puts a fresh one back.
func _detach_cursor() -> void:
    var overlay := get_node_or_null("CursorOverlay")
    if overlay == null:
        return
    remove_child(overlay)
    overlay.queue_free()


## Empties the list. The rows are freed rather than hidden, because the caller
## rebuilds whenever what it lists changes and a hidden row would still be found
## by `row_ids`. A list that keeps its rows hands them to `row_keep` instead, which
## frees the ones the next build does not ask for.
func clear() -> void:
    if row_keep != null:
        row_keep.stash()
        _settle.call_deferred()
    else:
        for child in _column.get_children():
            _column.remove_child(child)
            child.queue_free()
    _rows.clear()
    _order.clear()
    _branches.clear()
    close_child()
    _highlight = -1
    _typed = ""
    _group = ButtonGroup.new() if one_of else null
    _tick_slot = false
    search.text = ""
    search.visible = _searched


## A heading over the rows under it. Not a row: it takes no press and is not in
## `row_ids`, which is what tells a section title from a choice.
func add_section(heading: String) -> void:
    if row_keep != null and not _finding and row_keep.reuse_section(heading):
        return
    var label := SaMake.label(_column, "Section" + heading.replace(" ", ""), heading)
    if row_keep != null and not _finding:
        row_keep.place(label, true)
    label.set_meta(SaUI.FONT_SCALE_META, 0.85)
    label.modulate = Color(1.0, 1.0, 1.0, 0.6)
    if _finding:
        label.set_meta(SaChoiceSearch.FOUND, true)


## A line across the column, for the same job a menu separator does.
func add_gap() -> void:
    if row_keep != null and not _finding and row_keep.reuse_gap():
        return
    var line := HSeparator.new()
    _column.add_child(line)
    if row_keep != null and not _finding:
        row_keep.place(line, true)


## One choice. *checked* is only read when *checkable*, and a row added twice
## under one id replaces nothing: the caller clears first.
##
## *icon_name* is a file under `res://assets/icons/`, drawn at `ICON_SIZE`. *hint*
## is a shortcut at the row's right, the caller's own text rather than an
## `InputEvent`, since a menu row and the Shortcuts page draw one chord from two
## places. *disabled* dims the row and takes its press away, and `press_row`
## refuses it too. *box_tip* is what the box says on hover, or nothing.
## *other_name* is a second name the search finds the row by and nothing draws,
## `SaChoiceRow.other_name`.
##
## The row builds itself, `SaChoiceRow` beside this file. Everything it is is one
## call, because a row built and then written over can be shot half built.
func add_row(
    id: StringName,
    label: String,
    checkable: bool = false,
    checked: bool = false,
    icon_name: String = "",
    hint: String = "",
    disabled: bool = false,
    box_tip: String = "",
    other_name: String = ""
) -> void:
    if one_of and _group == null:
        _group = ButtonGroup.new()
    var row := row_keep.take_row(id) if row_keep != null and not _finding else null
    if row != null and not row.refill(label, checkable, checked, icon_name, hint, disabled, _group, box_tip, other_name):
        row_keep.drop(row)
        row = null
    var fresh := row == null
    if fresh:
        row = _wired(SaChoiceRow.new(id, label, checkable, checked, icon_name, hint, disabled, _group, box_tip, other_name))
    if _finding:
        row.set_meta(SaChoiceSearch.FOUND, true)
    if checkable and _label_ticks and not _capped and not _tick_slot:
        _tick_slot = true
        for earlier: SaChoiceRow in _rows.values():
            earlier.reserve_tick_slot()
    if _tick_slot:
        row.reserve_tick_slot()
    if row_keep != null and not _finding:
        row_keep.place(row, fresh)
    else:
        _column.add_child(row)
    _rows[id] = row
    _order.append(id)
    # Asked as the rows arrive rather than on open, so a caller that fills the
    # list and reads its shape back gets the same answer either way.
    search.visible = _searched or SaChoiceSearch.wanted_for(_order.size())


## A row built afresh and wired to the list's answers, as a kept row already is.
func _wired(row: SaChoiceRow) -> SaChoiceRow:
    var id := row.id
    row.label_button().pressed.connect(_on_row_pressed.bind(id))
    row.label_button().mouse_entered.connect(_on_row_rested.bind(id))
    var box := row.check_box()
    if box != null:
        # `toggled` rather than `pressed`, so the value the signal carries is the
        # box's own new state and the caller never has to work it out.
        box.toggled.connect(_on_check_toggled.bind(id))
    return row


## Frees the spares the last build of a kept list did not ask for, before
## anything measures, opens or searches the column, and takes back the tick
## slot of a kept row when the build held no row with a box.
func _settle() -> void:
    if row_keep == null:
        return
    row_keep.settle()
    if not _tick_slot:
        for row: SaChoiceRow in _rows.values():
            row.release_tick_slot()


## A row that opens a child list beside it rather than choosing, with *hint*
## and `SaChoiceRow.BRANCH_MARK` after it at its right where a command row shows
## its chord. Its press emits `branched` and leaves the list open, which is the
## one thing a plain row's press cannot do.
func add_branch_row(id: StringName, label: String, hint: String = "", disabled: bool = false) -> void:
    add_row(id, label, false, false, "", (hint + " " + SaChoiceRow.BRANCH_MARK).strip_edges(), disabled)
    _branches[id] = true


## Whether *id* is a row that opens a child list.
func is_branch(id: StringName) -> bool:
    return _branches.has(id)


## Opens *list* beside *from_id*'s row, as a child of this list, and answers
## whether it is on screen.
##
## **A child window, not a sibling.** The engine closes a popup when a window it
## hangs from takes focus, and only then, so a list under this one leaves this
## one open while it holds the keyboard and closes when a painter goes back to
## a row here, which is what a submenu does. The list is moved under this one
## the first time it is handed over, and a list already open from another row
## is closed first.
##
## Filled and parented but not shown while this list is closed or out of the
## tree, because a closed menu has no row to open beside and a suite reads the
## rows without a window. The scale is this list's, taken through the one writer
## (hard rule 7), so the child never opens at a different size from the menu it
## came from.
func open_child(list: SaChoicePopup, from_id: StringName) -> bool:
    if list == null or list == self:
        return false
    if child_list != null and child_list != list:
        close_child()
    if list.get_parent() != self:
        if list.get_parent() != null:
            list.get_parent().remove_child(list)
        add_child(list)
    child_list = list
    child_row = from_id
    if not list.chosen.is_connected(_on_child_chosen):
        list.chosen.connect(_on_child_chosen)
    if not list.popup_hide.is_connected(_on_child_hidden):
        list.popup_hide.connect(_on_child_hidden)
    var row := row_of(from_id)
    if row == null or not is_inside_tree() or not visible:
        return false
    list.set_meta(SaUI.EXTRA_SCALE_META, get_meta(SaUI.EXTRA_SCALE_META, 1.0))
    SaUI.apply_to_window(list)
    var factor := list.content_scale_factor
    var wanted := Vector2i((Vector2(list.wanted_size(0.0)) * factor).round())
    var own := Rect2(Vector2(position), Vector2(size))
    var room := SaPopupRect.room_for(list)
    var at := SaPopupRect.beside(own, SaPopupRect.of_anchor(row), wanted, room)
    var widened := SaPopupRect.with_bar(list, wanted, at.size.y)
    if widened != wanted:
        at = SaPopupRect.beside(own, SaPopupRect.of_anchor(row), widened, room)
    list.popup(at)
    return true


## Closes the child list, if one is open. This list stays as it is.
func close_child() -> void:
    if child_list != null and is_instance_valid(child_list) and child_list.visible:
        child_list.hide()


## Whether a child list is on screen beside this one.
func has_open_child() -> bool:
    return child_list != null and is_instance_valid(child_list) and child_list.visible


## The child chose a row and closed itself, so the menu behind it closes too, the
## way a submenu's choice closes the whole menu.
func _on_child_chosen(_id: StringName) -> void:
    hide()


## The child closed alone, by escape or the left arrow, so the keyboard comes
## back to this list, which is still open. At once rather than deferred, so no
## other window takes the focus between the two and closes this list by it.
func _on_child_hidden() -> void:
    if visible and is_inside_tree():
        grab_focus()


## The pointer came to rest on *id*. A branch row opens its child and any other
## row closes an open one, each after `HOVER_DELAY` and only if the pointer is
## still there, so crossing rows on the way to the child changes nothing.
func _on_row_rested(id: StringName) -> void:
    _rested = id
    if not is_inside_tree() or not visible:
        return
    if not is_branch(id) and not has_open_child():
        return
    # A timer's signal rather than an await, so a list freed before it runs out
    # takes the connection with it instead of resuming on a gone instance.
    get_tree().create_timer(HOVER_DELAY).timeout.connect(_on_rest_timed.bind(id))


## The rest on *id* lasted `HOVER_DELAY`, so the child it asked for opens, or the
## one it left closes, unless the pointer has moved on since.
func _on_rest_timed(id: StringName) -> void:
    if _rested != id or not visible or not is_inside_tree():
        return
    if is_branch(id):
        if not (has_open_child() and child_row == id) and not is_disabled(id):
            branched.emit(id)
    elif has_open_child():
        close_child()


## Marks *id* as the chosen one, which is a colour on its label and nothing on
## any other row. An id the list does not hold clears the mark.
func set_current(id: StringName) -> void:
    set_current_where(id, func(row_id: StringName) -> bool: return row_id == id)


## The same, for a list where one value has more than one row. The blend list
## draws a favourited mode twice, at the top and in its own section, and marking
## one of the two would say they were different modes.
##
## *id* is what `current()` reports afterwards and *matches* is what decides
## which rows wear the mark, so a caller cannot get the two out of step by
## marking rows it then cannot name.
func set_current_where(id: StringName, matches: Callable) -> void:
    current = id
    if one_of:
        # Every row cleared before any is set. A `ButtonGroup` unpresses its
        # siblings whenever one of them is written, so a single loop that marks
        # the chosen row and then clears the rows after it clears the chosen row
        # with them.
        for row_id: StringName in _order:
            var first := label_button(row_id)
            if first != null:
                first.set_pressed_no_signal(false)
        for row_id: StringName in _order:
            var second := label_button(row_id)
            if second != null and bool(matches.call(row_id)):
                second.set_pressed_no_signal(true)
        return
    for row_id: StringName in _order:
        var button := label_button(row_id)
        if button == null:
            continue
        var on: bool = bool(matches.call(row_id))
        var colour := SaTheme.palette.accent_primary if on else SaTheme.palette.text_primary
        # Written only on a change, as an override tells the row its theme changed.
        if not button.has_theme_color_override("font_color") or button.get_theme_color("font_color") != colour:
            button.add_theme_color_override("font_color", colour)
        row_of(row_id).apply_alpha(on)


## Whether *id*'s row wears the mark, which is not always `id == current()`:
## see `set_current_where`.
func is_marked(id: StringName) -> bool:
    var button := label_button(id)
    if button == null:
        return false
    if one_of:
        return button.button_pressed
    return not is_disabled(id) and button.modulate.a >= CHOSEN_ALPHA


## Whether *id*'s row takes a press. A row the list does not hold reads as
## disabled, because nothing can press it either.
func is_disabled(id: StringName) -> bool:
    var row := row_of(id)
    return row == null or row.disabled


## Whether *id*'s row is on screen, which a search can take away. Separate from
## `is_disabled`: a row the filter hid is not a row that refuses a press, it is a
## row that is not there at the moment.
func is_row_shown(id: StringName) -> bool:
    var row := row_of(id)
    return row != null and row.visible


## Whether the keyboard may land on *id*: on screen and pressable. The one
## question `move_highlight`, `set_highlight` and `type_ahead` ask, so enter can
## never choose a row a painter cannot see or press.
func _selectable(id: StringName) -> bool:
    return is_row_shown(id) and not is_disabled(id)


## Every row's id, in the order they were added.
func row_ids() -> Array[StringName]:
    return _order.duplicate()


## Every row's label, in the same order, which is what a test reads: an index
## says nothing without the list it indexes.
func row_labels() -> Array[String]:
    var out: Array[String] = []
    for id: StringName in _order:
        var button := label_button(id)
        out.append(button.text if button != null else "")
    return out


## The section headings, in order.
func section_titles() -> Array[String]:
    var out: Array[String] = []
    for child in _column.get_children():
        var label := child as Label
        if label != null:
            out.append(label.text)
    return out


## The button carrying *id*'s label, or null. Public because a capture presses
## it and a test reads its text.
func label_button(id: StringName) -> Button:
    var row := row_of(id)
    return row.label_button() if row != null else null


## The check box beside *id*, or null when that row carries none.
func check_box(id: StringName) -> CheckBox:
    var row := row_of(id)
    return row.check_box() if row != null else null


## *id*'s row, or null. The door to everything a row knows about itself, so a
## caller that wants two of them does not ask this class twice.
func row_of(id: StringName) -> SaChoiceRow:
    return _rows.get(id, null) as SaChoiceRow


## Whether *id*'s box is ticked. False for a row with no box, which is not the
## same statement and is why `check_box` is public beside it.
func is_checked(id: StringName) -> bool:
    var box := check_box(id)
    return box != null and box.button_pressed


## Presses *id*'s label the way a pointer would, for a scenario: an injected
## click does not route into a popup, which is a `Window` of its own.
##
## A disabled row answers false and chooses nothing. Emitting `pressed` by hand
## walks straight past `Button.disabled`, which the engine only consults on a
## real press, so without this line a scenario could reach a row a painter
## cannot.
func press_row(id: StringName) -> bool:
    var button := label_button(id)
    if button == null or not _selectable(id):
        return false
    button.pressed.emit()
    return true


## Ticks or unticks *id*'s box, for the same reason.
func press_check(id: StringName) -> bool:
    var box := check_box(id)
    if box == null:
        return false
    box.button_pressed = not box.button_pressed
    return true


## What each row is, for a state dump, `SaChoiceReport` beside this file.
func row_report() -> Array:
    return SaChoiceReport.rows(self)


## Opens under *anchor*, at that control's width or wider, and never taller than
## `MAX_HEIGHT` unless it was built without the cap.
##
## The width comes from the control rather than from the content, because the
## thing a painter aims at is the button they just pressed, and a list that opens
## narrower than its own button reads as a different control.
##
## **Nothing is opened while the list is out of the tree**. A window that is not
## in a tree cannot be shown, and each of the three lines below says so in an
## engine error rather than in a return value: `get_screen_position` prints
## `Condition "!is_inside_tree()" is true`, `popup` prints that and
## `Parameter "data.tree" is null` behind it, and every one of them is printed
## before the call returns. A suite may build an `OptionButton` that is never
## parented, which is a fair fixture and the reason this path is reached at
## all.
##
## Tested with `is_inside_tree()` rather than by checking `get_tree()` for null,
## because the null check catches the value and never the error, the error having already been printed.
##
## Silent rather than a warning, because a detached anchor is a test fixture and
## not a state the running app can reach: `_open_choice` adds the list as a child
## of the button, so the two are in the tree together or not at all.
##
## **The scale is taken on open** (hard rule 7). A popup is a `Window` of its
## own, so it does not inherit the host's `content_scale_factor` and would open
## at the OS pixel size beside a scaled docker. `SaUI.apply_to_window()` is the one
## writer. On open rather than in `_init`, because the scale can move between
## the two and the popup outlives the change.
## **The list asks for its docker's extra factor**: a maximised docker draws a
## quarter larger, and a list that asked for nothing would open at 1.0, a fifth
## narrower than its dropdown and pushed up over it. Where it opens is
## `SaPopupRect`, which measures the dropdown in the host's units and keeps the
## list off it.
##
## **At a point instead** when *at* is one, a point in the space `SaPopupRect`
## measures in, which `SaPopupRect.at_press` answers for a right press.
## *anchor* is then the control the press was on, and the list opens under the
## point when there is room and above it when there is more room there, so it
## never lies over the pointer.
func open_under(anchor: Control, at: Variant = null) -> void:
    if not is_inside_tree() or (anchor != null and not anchor.is_inside_tree()):
        return
    set_meta(SaUI.EXTRA_SCALE_META, SaUI.extra_scale(anchor.get_window() if anchor != null else null))
    SaUI.apply_to_window(self)
    if at is Vector2:
        _anchor = null
        var asked := Vector2i((Vector2(wanted_size(0.0)) * content_scale_factor).round())
        var room := SaPopupRect.room_for(self)
        var point := Rect2((at as Vector2).floor(), Vector2.ZERO)
        var placed := SaPopupRect.under(point, asked, room)
        popup(SaPopupRect.under(point, SaPopupRect.with_bar(self, asked, placed.size.y), room))
        return
    if search.visible:
        # The field takes the keyboard on open, so a painter who opened a long
        # list starts typing into the search rather than into the type-ahead.
        # Deferred, because a window that is not on screen yet cannot be focused.
        search.call_deferred("grab_focus")
    _anchor = anchor
    if anchor == null:
        popup_centered()
        return
    popup(SaPopupRect.place(anchor, self, wanted_size))


## Where the keyboard is, or "" for nowhere. Not `current`: the mark says what is
## chosen and this says what enter would choose.
func highlighted() -> StringName:
    if _highlight < 0 or _highlight >= _order.size():
        return &""
    return _order[_highlight]


## Puts the keyboard on *id*, and says whether it landed. A disabled row and a
## row the list does not hold both refuse it, so nothing has to check first.
func set_highlight(id: StringName) -> bool:
    var at := _order.find(id)
    if at == -1 or not _selectable(id):
        return false
    _highlight = at
    _show_highlight()
    return true


## Moves the keyboard *step* rows, skipping every disabled row and wrapping at
## both ends, and says whether it moved. From nowhere it lands on the first row
## going down and on the last going up, which is what a menu opened with the
## keyboard does.
##
## Bounded by the row count rather than by "until an enabled row", so a list
## whose rows are all disabled ends rather than spins.
func move_highlight(step: int) -> bool:
    if _order.is_empty() or step == 0:
        return false
    var at := _highlight
    if at < 0:
        at = -1 if step > 0 else _order.size()
    for _tries in _order.size():
        at = wrapi(at + step, 0, _order.size())
        if _selectable(_order[at]):
            _highlight = at
            _show_highlight()
            return true
    return false


## Chooses the highlighted row, the way enter does. False when the keyboard is
## nowhere, which is not an error: a menu opened with the pointer has no
## highlight until an arrow key is pressed.
func choose_highlighted() -> bool:
    var id := highlighted()
    if id.is_empty():
        return false
    return press_row(id)


## Moves the keyboard to the first enabled row whose label starts with *letters*,
## folded, and says whether one was found. The search starts after the
## highlighted row and wraps, so typing the same letter twice steps through the
## rows that share it rather than sitting on the first.
func type_ahead(letters: String) -> bool:
    var needle := letters.strip_edges().to_lower()
    if needle.is_empty() or _order.is_empty():
        return false
    # A single letter steps to the next row that starts with it, so pressing the
    # same letter twice walks the rows that share it. A longer needle is a search
    # still being typed and starts on the highlighted row, which it usually still
    # matches, so "br" does not jump off the row "b" just landed on.
    var first: int = _highlight + 1 if needle.length() == 1 else maxi(_highlight, 0)
    for offset in _order.size():
        var at := wrapi(first + offset, 0, _order.size())
        var id: StringName = _order[at]
        if not _selectable(id):
            continue
        var button := label_button(id)
        if button != null and button.text.to_lower().begins_with(needle):
            _highlight = at
            _show_highlight()
            return true
    return false


## Narrows the list to the rows whose label holds *needle*, and answers how many
## are left. The field's own `text_changed` calls this, and so does a test or a
## scenario, which cannot type into a `LineEdit` inside a popup Window.
func filter(needle: String) -> int:
    if search.text != needle:
        search.text = needle
    return _narrow(needle)


## What a filter does beyond hiding rows: the keyboard lands on the first row
## left, so enter picks the best match rather than nothing. Without it a painter
## types three letters, presses enter and the menu closes on whatever the arrows
## had reached before they typed.
func _narrow(needle: String) -> int:
    _settle()
    for child in _column.get_children():
        if child.has_meta(SaChoiceSearch.FOUND):
            _column.remove_child(child)
            child.queue_free()
            var row := child as SaChoiceRow
            if row != null:
                _rows.erase(row.id)
                _order.erase(row.id)
    _finding = true
    searching.emit(needle.strip_edges())
    _finding = false
    var shown := search.apply(needle)
    _highlight = -1
    if shown > 0:
        move_highlight(1)
    return shown


func _on_search_typed(needle: String) -> void:
    _narrow(needle)


## Escape emptied the field, which the field itself does for the reason its own
## `_input` gives. The rows are back already, the found ones go, the keyboard
## goes to the first row left and the window is booked to come back.
func _on_search_cleared() -> void:
    _narrow("")
    _reopen_at = Rect2i(position, size)


## The window put back where it was, after an escape that only meant to empty the
## field: `Popup` closes on `ui_cancel` in C++ after node input, which no script
## can veto, so a second escape finding an empty field is what closes it.
##
## **Connected deferred**. `Window.set_visible` emits `popup_hide` before it takes
## the viewport off the active list, so a `popup` inside the signal makes the
## engine refuse two activations. A later reopen finds the field without the
## keyboard (measured), so it is handed back. Out of the tree, or shown again by
## then, the list is left as it is.
func _on_popup_hidden() -> void:
    if _reopen_at.size == Vector2i.ZERO:
        return
    var at := _reopen_at
    _reopen_at = Rect2i()
    if is_inside_tree() and not visible:
        popup(at)
        search.call_deferred("grab_focus")


## The size the list wants under an anchor *anchor_width* wide, capped at
## `MAX_HEIGHT` unless `_init` said otherwise. Public so a test can read the cap
## without a tree, the only way to ask this question away from a running window.
func wanted_size(anchor_width: float) -> Vector2i:
    _settle()
    var wanted := _column.get_combined_minimum_size()
    var width := maxf(anchor_width, wanted.x + float(SaUI.px(24)))
    # The field is over the list rather than in it, so its height is not in the
    # column's and has to be added before the cap. Before rather than after:
    # `MAX_HEIGHT` is what the popup may not exceed, so a field takes its height
    # off the list and never off the screen.
    var chrome := float(SaUI.px(16))
    if search.visible:
        chrome += search.get_combined_minimum_size().y + float(SaUI.px(4))
    var cap := float(SaUI.px(MAX_HEIGHT)) if _capped else INF
    # A list the cap stops scrolls, and its bar takes its own width out of the
    # rows', so the rows are given that much more.
    _bar_asked = wanted.y + chrome > cap
    if _bar_asked:
        width += float(SaPopupRect.bar_width(self))
    var height := minf(wanted.y + chrome, cap)
    return Vector2i(int(width), int(height))


## Up, down, enter, escape, a row's underlined letter and type-ahead, so a menu
## can be worked without the pointer. Here rather than on the buttons' own focus
## handling, because a `Button` answers enter only while it holds focus and a popup that has just
## opened holds none, which is exactly the moment the first arrow key arrives.
func _input(event: InputEvent) -> void:
    if not visible:
        return
    var key := event as InputEventKey
    if key == null or not key.pressed or key.echo:
        return
    var handled := true
    match key.keycode:
        KEY_UP:
            move_highlight(-1)
        KEY_DOWN:
            move_highlight(1)
        KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
            # A visible field owns a space as it owns the letters below.
            handled = (key.keycode != KEY_SPACE or not search.visible) and choose_highlighted()
        KEY_RIGHT:
            # Into the highlighted row's child, the way a submenu is entered.
            # A visible field owns the arrow, which moves its caret.
            handled = not search.visible and is_branch(highlighted())
            if handled:
                branched.emit(highlighted())
        KEY_LEFT:
            # Out of a child list, back to the row it hangs from.
            handled = not search.visible and get_parent() is SaChoicePopup
            if handled:
                hide()
        KEY_ESCAPE:
            # A field with text took this escape first, `sa_choice_search.gd` saying
            # why, so an escape that arrives here is one nothing else wanted.
            hide()
        _:
            # A visible field owns the letters. `_input` runs before a focused
            # control's `gui_input`, so a type-ahead here would eat the first
            # letter of every search and jump the highlight while it did.
            # The row's own letter first, and a letter no row holds is the
            # type-ahead's, so one key is never both.
            handled = _letter_key(key) or (not search.visible and _type_ahead_key(key))
    if handled and is_inside_tree():
        get_viewport().set_input_as_handled()


## A key that is a row's underlined letter, pressed. Plain in a list with no
## search field, and with Alt held in a list that has one, because there a plain
## letter is the first of a search and taking it away would leave the field
## unable to start. A chord with Ctrl or Meta is a shortcut and is left to the
## router.
func _letter_key(key: InputEventKey) -> bool:
    if key.ctrl_pressed or key.meta_pressed or (search.visible and not key.alt_pressed):
        return false
    var letter := char(key.unicode) if key.unicode >= 32 else OS.get_keycode_string(key.keycode)
    return letter.length() == 1 and SaChoiceLetters.press(self, letter)


## One letter of a type-ahead. Letters typed inside `TYPE_AHEAD_GAP_MS` of each
## other narrow one search, and a letter after the gap starts a new one, which is
## what every list in every toolkit does and what a painter expects without being
## told.
func _type_ahead_key(key: InputEventKey) -> bool:
    var letter := char(key.unicode) if key.unicode >= 32 else ""
    if key.unicode < 32 or letter.strip_edges().is_empty():
        return false
    var now := Time.get_ticks_msec()
    _typed = (_typed + letter) if now - _typed_at_ms <= TYPE_AHEAD_GAP_MS else letter
    _typed_at_ms = now
    return type_ahead(_typed)


## The highlight on screen: a box behind the row, and the scroll brought to it.
##
## Not the row's focus. A list with a search field cannot move focus onto a row,
## because the field is what the painter is typing into and a `LineEdit` that has
## lost focus stops taking letters. The box is the row's own, so both kinds of
## list mark the keyboard the same way.
##
## Silent out of the tree, where `ensure_control_visible` is an error and a test
## builds the list detached on purpose.
func _show_highlight() -> void:
    var here := highlighted()
    for id: StringName in _order:
        var row := row_of(id)
        if row != null:
            row.set_highlighted(id == here)
    var button := label_button(here)
    if button != null and button.is_inside_tree():
        _scroll.ensure_control_visible(button)


func _on_row_pressed(id: StringName) -> void:
    if is_branch(id):
        # The list stays open: the child opens beside it, which is the press.
        branched.emit(id)
        return
    if _label_ticks and press_check(id):
        return
    if one_of:
        # The group has already put the mark on this row, so the list closing on
        # a choice it has drawn is the whole of it.
        current = id
    hide()
    chosen.emit(id)


## A box moved, and the list takes the keyboard back if the caller's answer
## took it, so Escape still closes the list.
##
## The Window menu's answer to a tick is to show a docker, and an embedded
## window shown takes the subwindow focus as it is registered. The Escape after
## it would go to the docker, which spends it releasing its own focus, and the
## menu would stay open through two of them. The keyboard goes back here rather
## than to the main window, because the list is still open and is what a
## painter who ticked a row is still working.
func _on_check_toggled(on: bool, id: StringName) -> void:
    marked.emit(id, on)
    if visible and is_inside_tree() and not has_focus():
        grab_focus()
