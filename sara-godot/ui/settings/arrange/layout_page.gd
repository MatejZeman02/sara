## A Preferences page that is a reorderable element list: every docker's, and
## the top bar's through `SaTopBarPage`. Derived from SaSettings, so a docker
## declared there gets one here for free.
##
## **A docker's is reached from Layouts and dockers, not from the sidebar**. A
## page per docker would double the sidebar's length for rows that are mostly
## the same, so there is one page, `SaDockersPage`, with a line per docker and
## an Elements… button on each, and Options… beside it where the docker has
## more. So a docker's page is one of two parts, [constant ELEMENTS] the list
## and [constant OPTIONS] the options a docker registered, each drawn by itself
## in the page area with a way back to the line it came from. The top bar is no
## docker and keeps its page in the sidebar, the list with its own rows above
## and below it.
##
## The reorder is the page's own, in `_input`, and not Godot's drag-and-drop.
## Two reasons, and the second is why the first was allowed to stand for so
## long. Godot's version drops a row onto whichever row the pointer is over when
## the button comes up, so the four logical pixels between two rows are dead, a
## list taller than the pane cannot be reordered past its own edge, and nothing
## on screen says where the row will land. And it is driven from `gui_input`,
## which an injected motion never reaches, so no capture scenario could ever
## show any of that. A press, a move and a release do reach `_input`, which is
## the same reason `DockerDragHandle` lives there.
##
## **The page is declared and the list is not**. The sections, the note and
## the docker's option rows are rows of an `SaPage`, and the list rides among
## them as one custom row that spans the page, because a
## reorderable list is nothing the row layer has a kind for or ever will. So
## `_init` builds the list first and calls `super()` last, which is the order
## `SaSettingsPage` asks of a page with fields `build` reads.
class_name SaLayoutPage
extends SaSettingsPage

## The two rows every docker carries that mean nothing in an order: the drag bar
## is drawn at the top of a docker and the resize grip in its corner, wherever
## the list puts them. They are pinned to the front of the list, in this order,
## and nothing may be dropped above them.
const PINNED_ELEMENTS := ["Drag Handle", "Resizer"]

## How far the pointer travels, in logical units, before a press on a row
## becomes a reorder. Under it the press is still a press, so a row is not
## picked up by someone aiming at its switch.
const DRAG_SLOP := 4.0

## How near an edge of the scrolling pane the pointer has to be for the list to
## follow it, and how fast it then travels, in logical units per second.
const AUTOSCROLL_EDGE := 28.0
const AUTOSCROLL_SPEED := 700.0

## The two parts a docker's page is drawn as, one at a time: the element list,
## and the options the docker registered. The top bar's page is the first.
const ELEMENTS := &"elements"
const OPTIONS := &"options"


class DragRow:
    extends PanelContainer

    var category: String
    var element_name: String
    var check_button: CheckButton
    var parent_panel: Node

    ## The sentinel row of the top bar: not dragged, carries the second row's
    ## own switch rather than a generic one, and is what a control is dropped
    ## onto to change rows.
    var is_sentinel: bool = false

    ## Drag Handle and Resizer: their place in the list means nothing, so they
    ## sit pinned above it, keep their own switch, and lose only the drag.
    var is_locked: bool = false

    var _resting: StyleBoxFlat
    var _picked_up: StyleBoxFlat

    func _init(cat: String, elem: String, is_vis: bool, parent_p: Node) -> void:
        category = cat
        element_name = elem
        parent_panel = parent_p
        is_sentinel = cat == "TopMenuBar" and elem == SaSettings.ROW_SENTINEL
        is_locked = elem == "Drag Handle" or elem == "Resizer"

        _resting = _make_style(false)
        _picked_up = _make_style(true)
        add_theme_stylebox_override("panel", _resting)

        var hbox := SaMake.row(self, "Line", 10)
        var title := tr("Second row starts here") if is_sentinel else SaSettings.translated_element_title(category, element_name)
        # The docker bars' six dots, and their room kept on a row that cannot be dragged, so the titles line up.
        var lbl := SaGrip.before(SaMake.label(hbox, "Title", title), can_drag())
        lbl.mouse_default_cursor_shape = Control.CURSOR_DRAG if can_drag() else Control.CURSOR_ARROW
        if not can_drag():
            var room := StyleBoxEmpty.new()
            room.content_margin_left = float(SaGrip.room())
            lbl.add_theme_stylebox_override("normal", room)
        lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var holds_preferences := category == "TopMenuBar" and element_name == "Edit"
        if holds_preferences:
            _say_why_it_stays(hbox)

        check_button = CheckButton.new()
        # Named, because the note scenario freezes on it by name and every other
        # row's switch is one of many. With an auto name the scenario takes no
        # note at all, which the capture runner hides: it prints only errors.
        if is_sentinel:
            check_button.name = "SecondRowCheck"
        check_button.button_pressed = SaSettings.second_row if is_sentinel else is_vis
        check_button.toggled.connect(_on_sentinel_toggled if is_sentinel else _on_toggled)
        hbox.add_child(check_button)

        if holds_preferences:
            check_button.disabled = true
            check_button.button_pressed = true
            check_button.tooltip_text = tr("Edit holds Preferences, so it stays in the menu bar.")

    ## The muted words after Edit's title, beside its dimmed switch, because a
    ## tooltip alone is not in a still shot and the row reads as dimmed with no
    ## word why. Sized and coloured as an explanation under a row's title is,
    ## and kept to one line, because it sits in the line itself and a wrap would
    ## make Edit's row the tallest.
    func _say_why_it_stays(hbox: HBoxContainer) -> void:
        var why := SaSettingsRows.hint_label(tr("always shown, it holds Preferences"))
        why.name = "WhyItStays"
        why.autowrap_mode = TextServer.AUTOWRAP_OFF
        why.size_flags_horizontal = Control.SIZE_SHRINK_END
        why.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        hbox.add_child(why)

    ## Two styles rather than one repainted in place, because `SaTheme.bind` is
    ## a registration and not a one-shot: rebinding the same box on every pick
    ## up would grow the theme's list for as long as the page is open.
    func _make_style(dragging: bool) -> StyleBoxFlat:
        var style := StyleBoxFlat.new()
        SaTheme.bind(style, {"bg_color": "bg_panel", "border_color": "border_drag" if dragging else "border_secondary"})
        style.border_width_bottom = 1
        if dragging:
            style.border_width_left = 1
            style.border_width_top = 1
            style.border_width_right = 1
        style.content_margin_left = float(SaUI.px(8))
        style.content_margin_right = float(SaUI.px(8))
        style.content_margin_top = float(SaUI.px(6))
        style.content_margin_bottom = float(SaUI.px(6))
        return style

    ## Whether this row can be picked up at all. The sentinel marks where the
    ## second row starts and the pinned pair have nowhere else to be.
    func can_drag() -> bool:
        return not (is_sentinel or is_locked)

    ## Whether a press at *at* lands on a control of the row rather than on the
    ## row, which keeps it a press and never a pick up.
    func holds_control_at(at: Vector2) -> bool:
        return check_button != null and check_button.get_global_rect().has_point(at)

    ## A top bar menu, which reorders among menus only.
    func is_menu() -> bool:
        return category == "TopMenuBar" and TopMenuBar.MENU_NAMES.has(element_name)

    ## The orange border every drag bar in Sara wears, so a picked-up row reads
    ## as held rather than merely selected.
    func set_picked_up(held: bool) -> void:
        add_theme_stylebox_override("panel", _picked_up if held else _resting)

    func _on_toggled(pressed: bool) -> void:
        SaSettings.set_element_visible(category, element_name, pressed)

    ## The sentinel has no element visibility of its own to toggle: its switch
    ## is the second row's.
    func _on_sentinel_toggled(pressed: bool) -> void:
        SaSettings.second_row = pressed


var category: String

## Which of the two parts this page draws, written once by `_init`.
var part: StringName = ELEMENTS

## What the Back row at the top calls, or nothing for a page with no way back.
## A docker's page has one, which returns to its line on Layouts and dockers.
## The top bar's page is the sidebar's own and has none.
var _back: Callable = Callable()

## The element list, or null for the options part, which draws no list.
var _list: VBoxContainer
var _scroll: ScrollContainer

## The section the list sits in, kept because `_declare_below` puts its rows
## there and a capture has to read them back. Found from the list once the page
## is realized: the list spans the page, so it is a child of it. On the options
## part it is the section the option rows are in, found from the first of them.
var _rows: Container

## The row under a press that has not travelled far enough to be a drag yet,
## and where that press landed.
var _armed_row: DragRow
var _press_at := Vector2.ZERO

## The row being carried, where it started, and the last place the pointer was
## seen. The pointer is kept because the pane keeps scrolling under a hand that
## has stopped moving, and a motion event only arrives when it moves.
var _drag_row: DragRow
var _drag_from := -1
var _pointer := Vector2.ZERO

## The per-docker option rows of the options part, and the door a scenario sets
## one through. Its own file because building a row from a spec and driving it
## from a scenario are one job that the reorder has nothing to do with. Built in
## `_init`, not here: a member initializer runs before `category` is written, so
## one built here would be asking the registry about "".
var _docker_options: SaLayoutDockerOptions

## The elements placed in this docker, drawn after its own rows, or null on the
## top bar's page, which is no docker's. Its own file, `placed_elements.gd`,
## since what it writes is the library and not the profile this page writes.
var _placed: SaPlacedElements = null


## *page_part* is [constant ELEMENTS] or [constant OPTIONS]. *back* is what the
## Back row calls, and a page handed none draws no Back row. *library* is a
## suite's own, the app's when left out, for what is placed in the docker.
##
## The list is built for the elements part alone. Built for the options part
## too it would be a container nothing ever adds to the tree, which is an object
## the run counts as leaked.
func _init(
    category_id: String, page_part: StringName = ELEMENTS, back: Callable = Callable(), library: SaComposedDockers = null
) -> void:
    category = category_id
    part = page_part
    _back = back
    _docker_options = SaLayoutDockerOptions.new(category_id)
    set_process(false)
    if part == ELEMENTS and category_id != "TopMenuBar":
        _placed = SaPlacedElements.new(category_id, _fill_list, library)
    if part == ELEMENTS:
        _list = SaMake.column(null, "LayoutList", SaTheme.GAP_TIGHT)
        _fill_list()
    super()
    _rows = _list.get_parent() as Container if _list != null else _docker_options.rows_box()


func build(ui: SaPage) -> void:
    if _back.is_valid():
        # No heading over it: the window's title above already names the docker,
        # and a heading over one button would read as a section with nothing in
        # it.
        ui.section("").action(tr("Back to Layouts and dockers"), _back).named(&"back").node("BackToDockers")
    _declare_above(ui)
    if part == OPTIONS:
        _docker_options.declare(ui.section(tr("Options")))
        return
    var section := ui.section(tr("Elements"))
    # Nine docker pages list only the pinned pair, and a note offering a drag
    # there promises something no row can do.
    if SaComposedDockers.is_composed(category):
        section.note(SaPlacedElements.note())
    elif has_draggable_row():
        section.note(tr("Drag a row anywhere to reorder it, or switch it off to hide it."))
    section.custom("", _list).named(&"elements")
    _declare_below(section)
    if _placed != null:
        _placed.declare(ui)


## A row per element in the order the settings hold, the pinned pair first,
## then what the library places in the docker. Emptied first,
## so a reset, a pick and a Take out draw the list they left.
func _fill_list() -> void:
    for child in _list.get_children():
        _list.remove_child(child)
        child.free()
    for element: String in pinned_first(SaSettings.get_layout_order(category)):
        _list.add_child(DragRow.new(category, element, SaSettings.get_element_visible(category, element), self))
    if _placed != null:
        for row: DragRow in _placed.rows(self):
            _list.add_child(row)


## Whether any row of the list can be picked up, which is what the page's note
## about dragging is true of. The options part has no list and so no row.
func has_draggable_row() -> bool:
    if _list == null:
        return false
    for child in _list.get_children():
        var row := child as DragRow
        if row != null and row.can_drag():
            return true
    return false


## Drag Handle and Resizer first, whatever the stored order says.
##
## The two cannot be reordered, so they stand on top and nothing is placed above
## them. A fresh profile lists them first only because the defaults happen to,
## and a profile written before either element existed gets them appended at the
## end by `get_layout_order`. Hoisting here makes the rule true of every
## profile, and the first reorder writes the hoisted order back.
static func pinned_first(order: Array) -> Array:
    var pinned: Array = []
    var rest: Array = []
    for element: String in order:
        if PINNED_ELEMENTS.has(element):
            pinned.append(element)
        else:
            rest.append(element)
    pinned.sort_custom(func(a: String, b: String) -> bool: return PINNED_ELEMENTS.find(a) < PINNED_ELEMENTS.find(b))
    pinned.append_array(rest)
    return pinned


func _input(event: InputEvent) -> void:
    if _list == null or not is_visible_in_tree():
        return

    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if button.pressed:
            _arm(button.position)
        else:
            _drop()
        return

    var motion := event as InputEventMouseMotion
    if motion == null:
        return
    _pointer = motion.position
    if _drag_row != null:
        _reorder_to(motion.position.y)
        get_viewport().set_input_as_handled()
    elif _armed_row != null and _press_at.distance_to(motion.position) > DRAG_SLOP:
        _pick_up()


## The pane keeps travelling while the pointer rests near its edge, which is
## the whole of "the drag is hard to do" on the top bar's thirty rows: a target
## below the fold could not be reached at all, because releasing outside the
## pane dropped the row nowhere.
func _process(delta: float) -> void:
    if _drag_row == null or _scroll == null:
        return
    # What the painter can see, not what the pane claims. The Preferences window
    # is smaller than a long list, so the scrolling pane runs off the bottom of
    # it and its own lower edge is nowhere on screen. Keying the travel off the
    # visible part means the list follows the pointer at the edge a hand can
    # actually reach, at any window size.
    var pane := _scroll.get_global_rect().intersection(get_viewport().get_visible_rect())
    var direction := 0.0
    if _pointer.y < pane.position.y + AUTOSCROLL_EDGE:
        direction = -1.0
    elif _pointer.y > pane.end.y - AUTOSCROLL_EDGE:
        direction = 1.0
    if is_zero_approx(direction):
        return
    var before := _scroll.scroll_vertical
    _scroll.scroll_vertical = before + int(direction * AUTOSCROLL_SPEED * delta)
    if _scroll.scroll_vertical != before:
        _reorder_to(_pointer.y)


## Remembers the row a press landed on, without claiming the press.
##
## The switch at the end of a row is a control of its own, so a press that
## lands on it stays a toggle: a row that could be picked up by its switch
## would both move and flip on release.
func _arm(at: Vector2) -> void:
    _armed_row = null
    for child in _list.get_children():
        var row := child as DragRow
        if row == null or not row.can_drag() or not row.get_global_rect().has_point(at):
            continue
        if row.holds_control_at(at):
            return
        _armed_row = row
        _press_at = at
        return


func _pick_up() -> void:
    _drag_row = _armed_row
    _armed_row = null
    _drag_from = _drag_row.get_index()
    _drag_row.set_picked_up(true)
    _scroll = _scrolling_pane()
    set_process(true)


func _drop() -> void:
    _armed_row = null
    if _drag_row == null:
        return
    var row := _drag_row
    _drag_row = null
    set_process(false)
    row.set_picked_up(false)
    if row.get_index() == _drag_from:
        return
    # A placed row's order is the library's to keep, and it is never carried
    # among the docker's own, so the profile's order holds none of it.
    if row is SaPlacedElements.PlacedRow:
        _placed.write()
        return
    var order: Array = []
    for child in _list.get_children():
        var moved := child as DragRow
        if moved != null and not moved is SaPlacedElements.PlacedRow:
            order.append(moved.element_name)
    SaSettings.set_layout_order(category, order)


## Puts the carried row where the pointer is, now, rather than where the button
## comes up. The row is the marker: there is nothing else to draw, and no gap
## between two rows can swallow a release.
func _reorder_to(at_y: float) -> void:
    var target := _target_index(at_y)
    if target != _drag_row.get_index():
        _list.move_child(_drag_row, target)


## How many rows the carried one should sit after, clamped to where it is
## allowed to be.
func _target_index(at_y: float) -> int:
    var idx := 0
    for child in _list.get_children():
        var row := child as DragRow
        if row == null or row == _drag_row:
            continue
        if at_y <= row.get_global_rect().get_center().y:
            break
        idx += 1
    var band := drop_band(_drag_row)
    return clampi(idx, band.x, band.y)


## The first and last index a row may take, as a closed range.
##
## Drag Handle and Resizer hold the front of a docker's list and nothing goes
## above them. On the top bar the menus hold the front of the first row, so a
## menu stays among the menus and a tool control stays after them, which is what
## the old `_can_drop_data` said one target at a time. A band rather than a
## per-target answer, because the reorder happens while the pointer moves and
## there is no target until it stops.
func drop_band(carried: DragRow) -> Vector2i:
    var pinned := 0
    var menus := 0
    var own := 0
    for child in _list.get_children():
        var row := child as DragRow
        if row == null or row == carried:
            continue
        if row.is_locked:
            pinned += 1
        if row.is_menu():
            menus += 1
        if not row is SaPlacedElements.PlacedRow:
            own += 1
    var last := _list.get_child_count() - 1
    # What is placed stays after the docker's own rows, where its window draws it.
    if carried is SaPlacedElements.PlacedRow:
        return Vector2i(own, last)
    if category != "TopMenuBar":
        return Vector2i(pinned, own)
    if carried.is_menu():
        return Vector2i(0, menus)
    return Vector2i(menus, last)


## The row carrying an element, or null. The list is private and a caller that
## wants one row should not have to walk it.
func row_for(element: String) -> DragRow:
    if _list == null:
        return null
    for child in _list.get_children():
        var row := child as DragRow
        if row != null and row.element_name == element:
            return row
    return null


## The part of the scrolling pane a hand can actually reach, in the root
## window's logical units, or a zero rect for a page built off the tree.
##
## The intersection with the window's own visible rect is the point of it. The
## pane is a child of an embedded subwindow and takes whatever height its
## container gives it, which can be more than the window shows, and a row drawn
## in the part that hangs past the window's bottom edge is drawn where no click
## can land.
func visible_pane(origin: Vector2) -> Rect2:
    return pane_of(self, origin)


## The part of the pane *control* scrolls in that a hand can reach, the way
## [method visible_pane] measures it for this page. Static, because the Layouts
## and dockers page measures its own buttons by it too.
static func pane_of(control: Control, origin: Vector2) -> Rect2:
    var pane := scrolling_pane_of(control)
    if pane == null:
        return Rect2()
    var seen := pane.get_global_rect().intersection(control.get_viewport().get_visible_rect())
    return Rect2(origin + seen.position, seen.size)


## Whether a point a scenario is about to press is inside the pane it belongs
## to. A zero rect means the page is off the tree, where there is nothing to be
## outside of, so everything counts as reachable.
static func reachable(at: Vector2, seen: Rect2) -> bool:
    return seen.size.y <= 0.0 or seen.has_point(at)


## The pane the list scrolls inside, or null for a page built off the tree.
func _scrolling_pane() -> ScrollContainer:
    return scrolling_pane_of(self)


## The nearest `ScrollContainer` above *node*, or null.
static func scrolling_pane_of(node: Node) -> ScrollContainer:
    var above: Node = node.get_parent()
    while above != null:
        var pane := above as ScrollContainer
        if pane != null:
            return pane
        above = above.get_parent()
    return null


## Reads the layout page's rows: what the page holds, and where a scenario has
## to aim to pick a row up, `{"layout_rows": {}}`.
##
## The centres are in the root window's logical units, not the page's own. The
## page lives in an embedded subwindow, so a row's `get_global_rect()` is
## measured from that window's corner, and a scenario pressing at those numbers
## presses somewhere else entirely.
##
## Untyped on purpose. A cast to this file's own `class_name` inside a static
## function leaks the script, which leaks 545 live objects.
static func capture_rows(tree: SceneTree) -> String:
    for node in tree.root.find_children("*", "Window", true, false):
        if not node.has_method("show_page"):
            continue
        for open_page in node.find_children("*", "VBoxContainer", true, false):
            if open_page.has_method("describe_rows"):
                return open_page.describe_rows(Vector2(node.position))
    return "SaCapture: no open layout page to read rows from"


## Drags on the layout list: the press, motion and release a hand makes on the
## layout page's list, aimed at a row by name, `{"layout_gesture": {...}}`.
##
## By name and not by coordinate, because the coordinates move. This scenario
## was written in pixels first and stopped touching the list the same day, when
## another unit changed where the Preferences window opens: every step still
## ran, nothing errored, and the shots showed a list that had not been dragged.
## A capture that cannot fail is worse than none.
##
## `{"drag": "Hex Input", "over": "Drag Handle", "offset": -48}` carries a row
## to a point measured from another row. `{"drag": "File", "to": "bottom"}`
## carries one to the visible pane's edge and leaves the button down, so the
## scenario can wait while the list travels under it, and `{"release": true}`
## ends that gesture. `{"switch": "HSV Wheel"}` clicks a row's own switch,
## which is what a page claiming presses in `_input` is most likely to break,
## `{"back": true}` the Back row of a docker's page and `{"reset": true}` its
## Reset to shipped. On Layouts and dockers
## `{"elements": "Layers"}` and `{"options": "Toolbox"}` press a docker's two
## buttons, which `SaDockersPage.drive_gesture` answers. On any docker's page
## `{"add_element": true}`, `{"pick": "Brush Tool", "from": "Toolbox"}` and
## `{"take_out": "Brush Tool"}` are `SaPlacedElements.drive`'s.
static func capture_gesture(tree: SceneTree, spec: Dictionary) -> String:
    for node in tree.root.find_children("*", "Window", true, false):
        if not node.has_method("show_page"):
            continue
        for open_page in node.find_children("*", "VBoxContainer", true, false):
            if open_page.has_method("drive_gesture"):
                return open_page.drive_gesture(tree, Vector2(node.position), spec)
    return "SaCapture: no open layout page to act on"


func drive_gesture(tree: SceneTree, origin: Vector2, spec: Dictionary) -> String:
    if _placed != null and SaPlacedElements.drives(spec):
        return _placed.drive(tree, origin, spec)
    if bool(spec.get("release", false)):
        var at := origin + _pointer
        _send(tree, at, "release")
        return "SaCapture: layout_gesture released at (%d, %d)" % [at.x, at.y]

    # `{"option": "orientation", "value": "horizontal"}`: sets a per-docker
    # option through the control the painter would use. A press on an
    # `OptionButton` opens a popup that a scenario cannot then drive by
    # coordinate, so a click would prove nothing about a choice row.
    #
    # The elements part draws no option, and a scenario written while a docker's
    # page held both is told where they went rather than that they are gone.
    if spec.has("option"):
        if part != OPTIONS:
            return (
                "SaCapture: layout_gesture found no option '%s' on the elements of '%s', they are behind its Options… button"
                % [spec["option"], category]
            )
        return _docker_options.drive(String(spec["option"]), spec.get("value"))

    # `{"back": true}` presses the Back row the way a hand does, for the same
    # reason the switch below is clicked rather than set, and `{"reset": true}`
    # the Reset to shipped row under the list.
    for key: StringName in [&"back", &"reset"]:
        if not bool(spec.get(String(key), false)):
            continue
        var said := "the Back row" if key == &"back" else "Reset to default"
        var pressed := page.row(key)
        if pressed == null or pressed.control == null:
            return "SaCapture: layout_gesture found no %s on '%s'" % [said, category]
        return click(tree, origin, pressed.control as Control, said)

    if spec.has("switch"):
        var wanted := String(spec["switch"])
        var switched := row_for(wanted)
        var target: Control = switched.check_button if switched != null else below_control(wanted)
        if target == null:
            return "SaCapture: layout_gesture found no row called '%s'" % wanted
        return click(tree, origin, target, "the switch of '%s'" % wanted)

    var row := row_for(String(spec.get("drag", "")))
    if row == null:
        return "SaCapture: layout_gesture found no row called '%s'" % spec.get("drag", "")
    var from := origin + row.get_global_rect().get_center()
    var to := from
    var edge := String(spec.get("to", ""))
    if edge != "":
        var pane := _scrolling_pane()
        if pane == null:
            return "SaCapture: layout_gesture found no scrolling pane"
        var seen := pane.get_global_rect().intersection(get_viewport().get_visible_rect())
        var half := AUTOSCROLL_EDGE * 0.5
        to.y = origin.y + (seen.end.y - half if edge == "bottom" else seen.position.y + half)
    else:
        var over := row_for(String(spec.get("over", "")))
        if over == null:
            return "SaCapture: layout_gesture found no row called '%s'" % spec.get("over", "")
        to = origin + over.get_global_rect().get_center() + Vector2(0, float(spec.get("offset", 0)))

    _send(tree, from, "move")
    _send(tree, from, "press")
    # The first motion has to clear the slop on its own, whatever the distance,
    # or a short carry never becomes a drag at all.
    _send(tree, from + Vector2(0, signf(to.y - from.y) * (DRAG_SLOP + 2.0)), "move")
    for share: float in [0.5, 1.0]:
        _send(tree, from.lerp(to, share), "move")
    if edge != "":
        return "SaCapture: layout_gesture holds '%s' at the %s edge, (%d, %d)" % [row.element_name, edge, to.x, to.y]
    _send(tree, to, "release")
    return "SaCapture: layout_gesture carried '%s' to (%d, %d)" % [row.element_name, to.x, to.y]


## A press and a release at the middle of *target*, said as *what*, or why
## not. Public because the Layouts and dockers page presses its Elements… and
## Options… buttons the same way.
##
## A press outside the pane lands on whatever is under it, and the control is
## not pressed. Saying so is the whole point: a step that reports a clean click
## either way reads a row drawn past the window's bottom edge as a pass.
static func click(tree: SceneTree, origin: Vector2, target: Control, what: String) -> String:
    var at := origin + target.get_global_rect().get_center()
    var seen := pane_of(target, origin)
    if not reachable(at, seen):
        return "SaCapture: layout_gesture cannot reach %s, it is at y %d and the pane ends at y %d" % [what, at.y, seen.end.y]
    _send(tree, at, "move")
    _send(tree, at, "press")
    _send(tree, at, "release")
    return "SaCapture: layout_gesture clicked %s" % what


## One event, at a point in the root window's logical units.
##
## Pre-multiplied by the root's final transform, because an event pushed in from
## a script is not scaled on the way in, and a 2x display would otherwise halve
## every coordinate. the capture step lost every scripted
## move to exactly this.
static func _send(tree: SceneTree, at: Vector2, kind: String) -> void:
    var physical: Vector2 = tree.root.get_final_transform() * at
    if kind == "move":
        var motion := InputEventMouseMotion.new()
        motion.position = physical
        motion.global_position = physical
        Input.parse_input_event(motion)
        return
    var button_event := InputEventMouseButton.new()
    button_event.button_index = MOUSE_BUTTON_LEFT
    button_event.pressed = kind == "press"
    button_event.position = physical
    button_event.global_position = physical
    Input.parse_input_event(button_event)


## One line per row: its index, its element key, whether it can be picked up,
## and the point a scenario presses to pick it up.
func describe_rows(origin: Vector2) -> String:
    var lines: Array[String] = ["SaCapture: layout rows of '%s', its %s" % [category, part]]
    var seen := visible_pane(origin)
    if seen.size.y > 0.0:
        var bar := _scrolling_pane().get_v_scroll_bar()
        lines.append(
            (
                "  pane  y %d to %d, scrolled %d of %d"
                % [seen.position.y, seen.end.y, bar.value, maxf(0.0, bar.max_value - bar.page)]
            )
        )
    var listed: Array[Node] = _list.get_children() if _list != null else ([] as Array[Node])
    for child in listed:
        var row := child as DragRow
        if row == null:
            continue
        var rect := row.get_global_rect()
        var centre := origin + rect.get_center()
        var kind := "draggable"
        if row.is_locked:
            kind = "pinned"
        elif row.is_sentinel:
            kind = "sentinel"
        var switch := origin + row.check_button.get_global_rect().get_center()
        # A dimmed switch and the words beside it, which is Edit's on the top
        # bar, so a dump says what the shot beside it shows.
        var why := row.find_child("WhyItStays", true, false) as Label
        var said := ", dimmed" if row.check_button.disabled else ""
        if why != null and why.is_visible_in_tree():
            said += ", says '%s'" % why.text
        said += _placed.describe_row(row, origin) if _placed != null else ""
        (
            lines
            . append(
                (
                    "  %2d  %-24s %-9s %-3s centre=(%4d, %4d) switch=(%4d, %4d)%s%s"
                    % [
                        row.get_index(),
                        row.element_name,
                        kind,
                        "on" if row.check_button.button_pressed else "off",
                        centre.x,
                        centre.y,
                        switch.x,
                        switch.y,
                        said,
                        "" if reachable(switch, seen) else "  UNREACHABLE, outside the pane",
                    ]
                )
            )
        )
    for line in below_rows():
        var control := below_control_of(line)
        var at := origin + (line if control == null else control).get_global_rect().get_center()
        (
            lines
            . append(
                (
                    "  --  %-24s %-9s %-3s switch=(%4d, %4d)"
                    % [
                        String(line.get_meta(SaSettingsRows.TITLE_META, "")),
                        "below",
                        _control_state(control),
                        at.x,
                        at.y,
                    ]
                )
            )
        )
        lines.append("      %s" % below_hint(line))
    lines.append_array(_placed.describe(origin) if _placed != null else ([] as Array[String]))
    return "\n".join(lines)


## The rows `_declare_below` put under the list, in the order it declared them.
##
## They are not DragRows and never move, so the walk above misses them, and a
## docker's own options are what they hold. A scenario
## that has to prove a page offers a control and the sentence under it needs
## both read back, and a state dump of the window does not carry either.
func below_rows() -> Array[HBoxContainer]:
    var found: Array[HBoxContainer] = []
    if _rows == null:
        return found
    for child in _rows.get_children():
        var line := child as HBoxContainer
        if line != null and line.has_meta(SaSettingsRows.ROW_META):
            found.append(line)
    return found


## The control at the right of a below-list row, or null for a row that is only
## text. `SaSettingsRows.row` puts the labels first and the control last, so a
## row with one child has no control.
func below_control_of(line: HBoxContainer) -> Control:
    if line.get_child_count() < 2:
        return null
    return line.get_child(line.get_child_count() - 1) as Control


## The explanation under a below-list row's title, which `SaSettingsRows.row`
## builds as the second label of the labels column.
func below_hint(line: HBoxContainer) -> String:
    var labels := line.get_child(0) as VBoxContainer
    if labels == null or labels.get_child_count() < 2:
        return ""
    var hint := labels.get_child(1) as Label
    return "" if hint == null else hint.text


## The below-list control a row of that title carries, for `layout_gesture`.
func below_control(title: String) -> Control:
    for line in below_rows():
        if String(line.get_meta(SaSettingsRows.TITLE_META, "")) == title:
            return below_control_of(line)
    return null


## What a control is showing, in one word, for the line above.
##
## A dimmed row says so. A per-docker option can be made inert by another one,
## the toolbox's line cap is the case, and a dump that printed the class name
## for a `SpinBox` could say neither what it was set to nor that a painter could
## not touch it, and neither is in a screenshot.
func _control_state(control: Control) -> String:
    var option := control as OptionButton
    if option != null:
        return option.get_item_text(option.selected) + ("" if not option.disabled else ", dimmed")
    var counter := control as SpinBox
    if counter != null:
        return "%d%s" % [int(counter.value), "" if counter.editable else ", dimmed"]
    # A button that only presses has no state, so the dump says what it reads.
    var plain := control as Button
    if plain != null and not plain.toggle_mode:
        return "'%s'%s" % [plain.text, "" if not plain.disabled else ", dimmed"]
    var button := control as BaseButton
    if button != null:
        return ("on" if button.button_pressed else "off") + ("" if not button.disabled else ", dimmed")
    return "-" if control == null else control.get_class()


## What a page declares above its list. Nothing, for a docker.
func _declare_above(_ui: SaPage) -> void:
    pass


## What a page declares under its list, in the same section: Reset to shipped,
## for a docker that has an arrangement to go back to. The options it registered
## are its page's other part, and what every docker shares is on Layouts and
## dockers once.
##
## The hide button's switch, the two summon rows and the pop-up palette's switch
## are settings every docker shares, so they are drawn once, on `SaDockersPage`,
## rather than on each docker's page, where one setting shows many times and
## reads as the docker's own. The reset stands here, and it undoes this docker's
## edits alone, so it is the one row here. A docker with nothing shipped, a
## composed one, has nothing to reset to and no row. The Top Menu Bar page
## overrides this with its row-width readout, since the bar is not a docker.
func _declare_below(section: SaPageSection) -> void:
    if not SaSettings.layout_ships(category) or SaComposedDockers.is_composed(category):
        return
    var said := tr(
        (
            "Restores this docker's default order and hidden parts and takes out what was placed in it."
            + " Its options and its place stay."
        )
    )
    section.action(tr("Reset to default"), _reset_to_shipped).button(tr("Reset")).named(&"reset").node("ResetToShipped").explain(
        said
    )


## Forgets this docker's order and hidden elements, takes out what was placed in
## it, and draws the list again from what both answer now.
func _reset_to_shipped() -> void:
    SaSettings.reset_layout_category(category)
    _placed.take_out_all()
    _fill_list()
