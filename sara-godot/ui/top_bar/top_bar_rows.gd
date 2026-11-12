## The top bar's two rows: the first with the tool options slot, the second with
## the colour pair, its own slot and the controls a profile puts after the
## sentinel. Which control sits on which row, whether the second row is shown,
## which controls did not fit and went into the overflow, and what each row has
## spent against what it has.
##
## A fresh profile shows both, with the sentinel after the last menu, so the
## first row is the menus and the window buttons and the second is the colour
## pair, every tool option and the overflow button, the way Krita's tool
## options bar sits under its menu bar.
##
## A class of its own state. It was arithmetic over a bar handed to it, split
## out of `top_menu_bar.gd` by a line count while the placement it measured
## stayed behind on the bar: two halves of one subject in two files, each
## reaching into the other. It is handed the bar's two margins as numbers and
## the tool options bar when there is one, and measures the width of the box it
## is placed in, which is the bar. The bar puts its menus, a separator and the
## window buttons on `main_row` around the slot, and this counts them as pinned
## by name.
class_name SaTopBarRows
extends VBoxContainer

## The rows were split again, or a tool change showed or hid a control on them,
## so which controls are on the bar and which went to the overflow may have
## moved. The Tool Options docker leaves out a row the bar holds and listens
## here, since a narrower bar sends Size into the list and the row has to come
## back.
signal refitted

## The elements that leave a short row before any other, in the order they
## leave. They are the ones painting reaches for least, where Size and Opacity
## are reached for constantly, so a cut from the row's end, which would send
## Size and Opacity into the overflow at 1280 while these stayed, is not the
## rule. The rotation's reset leaves before its slider, and the eraser, which the E key
## toggles as well, last.
const LEAVE_FIRST: Array[String] = [
    ToolOptionsBar.ELEMENT_KEEP_BLEND,
    ToolOptionsBar.ELEMENT_MIRROR_H,
    ToolOptionsBar.ELEMENT_MIRROR_V,
    ToolOptionsBar.ELEMENT_RADIAL,
    ToolOptionsBar.ELEMENT_STABILIZER,
    SaTopBarRotation.ELEMENT_RESET,
    SaTopBarRotation.ELEMENT_SLIDER,
    ToolOptionsBar.ELEMENT_EDIT_BRUSH,
    "eraser_toggled",
]

## The elements that stay on a short row after every other, in the order they
## leave, so Size, which the brush calls `radius`, is the last control on the
## bar. Undo and Redo leave first of these, Redo before Undo, because on a
## tablet with no keyboard they are the way back a press away. Keys rather than
## a flag on the option, the way the shortcut for the brush's size names `radius`: a tool that declares these keys gets their
## place, and a control no list names leaves between the two lists, from the
## row's end.
const LEAVE_LAST: Array[String] = [
    SaTopBarHistory.ELEMENT_REDO,
    SaTopBarHistory.ELEMENT_UNDO,
    SaTopBarFocusMode.ELEMENT,
    ToolOptionControls.BLEND_KEY,
    ToolOptionsBar.ELEMENT_PRESETS,
    "opacity",
    "radius",
]

## The name a group's break is given on its row, with its index after it.
const BREAK_NAME := "GroupBreak"

var main_row: HBoxContainer
## The slot the tool options bar sits in on the first row.
var brush_options_slot: SaRowSlot
## The button after the slot, and the list it opens with every control that did
## not fit on its row. Hidden while that list holds nothing. At the end of the
## second row while that row shows and before the window buttons otherwise,
## `_seat_overflow`'s rule.
var overflow: SaTopBarOverflow
## Created hidden. The menus and the window buttons stay on the first row.
var second_row: HBoxContainer
var second_slot: SaRowSlot
## The container for the controls a profile puts after the sentinel.
var second_options_row: HBoxContainer
## The foreground and background pair, pinned at the left of the second row the
## way the menus are pinned at the left of the first.
var color_pair: SaColorPair

## Whether the tool options section is on, which Preferences switches. The
## second row follows it, because it holds nothing else a painter asked for.
var options_shown: bool = true

## The tool options bar, or null on a bar built without one.
var _options: ToolOptionsBar = null
## Controls that are row elements without being the tool options bar's own, the
## rotation pair, merged into what the profile orders.
var _extra_elements: Dictionary = {}
## The group of each of those, merged into the bar's own the same way.
var _extra_groups: Dictionary = {}

## Row -> the breaks drawn between its groups, kept on the row's container and
## hidden while a pass has no use for them, so the same few are shown again
## rather than built and freed on every resize.
var _breaks: Dictionary = {}
## The groups as the last placement read them, so the overflow's cut does not
## walk the registry again for every control it gives up.
var _group_of: Dictionary = {}

var _margin_left: float
var _margin_right: float

## True while `refit` is running, so the `resized` its own reparenting emits
## does not start a second pass inside the first.
var _refitting: bool = false

## How far the first row overran when the painter asked for one row, or 0.0 when
## it fitted or the switch is on. Read by the state dump and by the top bar's
## list on Layouts and dockers.
var _second_row_forced_by: float = 0.0

## What each control asked for on the first row, so a return from the second
## gives it back rather than leaving every control stretched.
var _first_row_v_flags: Dictionary = {}

## What the last refit left: the bar's width, the profile's order and switches,
## the name and width of every control that was shown and what is pinned beside
## them, in `_fit_key`'s shape. A tool change or a width signal that answers the
## same key has nothing to move, because the controls, the room and the order
## are what the split is made from. Empty until the first refit.
var _fitted: Array = []

## How many refits have run, counted for the suites that say a switch between
## two tools with the same controls runs none and a switch of the overflow
## settles.
var _refits: int = 0


func _init(margin_left: float, margin_right: float, slot_color: Color) -> void:
    name = "Rows"
    _margin_left = margin_left
    _margin_right = margin_right
    add_theme_constant_override("separation", DockerUtils.px(2))

    main_row = SaMake.row(self, "MainRow", SaTheme.GAP_TIGHT)

    brush_options_slot = SaRowSlot.new(slot_color)
    brush_options_slot.name = "BrushOptionsScrollContainer"
    main_row.add_child(brush_options_slot)

    SaTopBarOverflow.register_option()
    overflow = SaTopBarOverflow.new()
    main_row.add_child(overflow)

    second_row = SaMake.row(self, "SecondRow", SaTheme.GAP_TIGHT)
    second_row.visible = false

    color_pair = SaColorPair.new()
    color_pair.swap_requested.connect(SaColors.swap)
    color_pair.reset_requested.connect(SaColors.reset)
    second_row.add_child(color_pair)

    var pair_sep := SaMake.separator(second_row, "ColorPairSeparator", true)
    pair_sep.size_flags_vertical = SIZE_EXPAND_FILL
    var pair_sep_style := StyleBoxFlat.new()
    SaTheme.bind(pair_sep_style, {"bg_color": "border_primary"})
    # The rule's width. A separator draws its style as wide as the style's own
    # minimum, which a flat box with no margins has none of, so without this
    # pixel the pair's rule is a gap with no line in it.
    pair_sep_style.content_margin_left = float(DockerUtils.px(1))
    pair_sep_style.expand_margin_top = float(DockerUtils.px(6))
    pair_sep_style.expand_margin_bottom = float(DockerUtils.px(6))
    pair_sep.add_theme_stylebox_override("separator", pair_sep_style)
    pair_sep.add_theme_constant_override("separation", DockerUtils.px(SaTheme.GAP_TIGHT))

    second_slot = SaRowSlot.new(slot_color)
    second_slot.name = "SecondRowSlot"
    second_slot.min_height = SaRowSlot.SECOND_ROW_HEIGHT
    second_row.add_child(second_slot)

    second_options_row = SaMake.row(null, "SecondOptionsRow")
    second_options_row.size_flags_horizontal = SIZE_SHRINK_BEGIN
    # The row is as tall as its tallest control and a slider is shorter, so the
    # container fills the row and hands the height on to whatever is placed on
    # it, and a slider's fill reaches the row's edges rather than floating in
    # the middle of a band.
    second_options_row.size_flags_vertical = SIZE_EXPAND_FILL
    # The same spacing the tool options bar asks for, so a control reads the
    # same on either row.
    second_options_row.set_meta(SaUI.SEPARATION_SCALE_META, 0.4)
    DockerUtils.apply_compact_ui(second_options_row)
    second_slot.add_content(second_options_row)
    second_options_row.minimum_size_changed.connect(refit_if_moved)


## A tool change is heard here rather than through the bar, because what it
## moves is only what this places.
func _ready() -> void:
    if not EventBus.tool_changed.is_connected(_on_tool_changed):
        EventBus.tool_changed.connect(_on_tool_changed)


## Puts *options* in the first row's slot and takes *extra* as row elements
## beside its own, in the groups *extra_groups* names.
func attach(options: ToolOptionsBar, extra: Dictionary, extra_groups: Dictionary = {}) -> void:
    _extra_elements = extra
    _extra_groups = extra_groups
    _options = options
    if options.get_parent() != null:
        options.get_parent().remove_child(options)
    # The slot is a `Control` and not a container, so the bar is anchored to
    # its height rather than given size flags.
    options.set_anchor(SIDE_LEFT, 0.0)
    options.set_anchor(SIDE_TOP, 0.0)
    options.set_anchor(SIDE_BOTTOM, 1.0)
    options.offset_left = 0
    options.offset_top = 0
    options.offset_bottom = 0
    brush_options_slot.add_content(options)
    if not options.minimum_size_changed.is_connected(refit_if_moved):
        options.minimum_size_changed.connect(refit_if_moved)


## Shows or hides the tool options section, and says whether that changed
## anything.
func show_options(vis: bool) -> bool:
    if options_shown == vis:
        return false
    options_shown = vis
    brush_options_slot.visible = vis
    refit()
    return true


## Which row each tool option control sits on, and the second row's own rule.
##
## The half of the bar's layout pass that depends on the width rather than on a
## setting, so a resize can run it without repopulating the menus and rereading
## the profile's order for the window buttons.
##
## **Reentrant, and it has to be guarded rather than avoided.** The second pass
## reparents controls between the rows, which shows or hides the second row,
## which changes the bar's own height, which emits `resized` on the bar. Without
## the flag that is this method calling itself from inside its own second pass.
## Returning early is right and not a compromise: the outer call is still
## walking the same order with the same budget and will finish the job.
##
## **The second row is shown or hidden once, at the end, and never in between.**
## Showing a control makes Godot read its minimum size there and then and keep
## it as the last one it reported, and its deferred check emits
## `minimum_size_changed` when the size it finds later differs from that. A row
## shown while still empty and filled after would keep an empty row's width,
## find the full one a moment later and emit, and `refit_if_moved` would run
## this again, which shows the row empty again, all inside one flush of the
## message queue, a hang and then a crash. Shown once, after its controls are
## in it, the row is measured with them and there is nothing left to report.
func refit() -> void:
    if _refitting:
        return
    _refitting = true
    _refits += 1
    _listen_to_pinned()
    var order := SaSettings.get_layout_order("TopMenuBar")
    var two_rows := SaSettings.second_row
    _seat_overflow(two_rows and options_shown)
    _fold_menus()
    _place(order, two_rows)
    _second_row_forced_by = 0.0
    if SaTopBarOverflow.enabled():
        _overflow(two_rows)
    # Second pass, and only when the painter asked for one row and switched the
    # overflow off, which is the plain one-row bar. Everything after
    # the sentinel joins the first row there, and the default assignment needs
    # 1163 logical pixels of the 1030 a 1920 bar has for it. The slot scrolls,
    # so nothing is lost, but a painter reaching for Mirror V has to drag the
    # bar to find it, which is not what the switch is for. The second row comes
    # back rather than the row overrunning, and `second_row_forced` in the state
    # dump says it did and by how much.
    elif not two_rows and options_shown:
        var over := row_spent(1) - row_budget(1)
        if over > 0.0:
            _second_row_forced_by = over
            two_rows = true
            _seat_overflow(true)
            _place(order, true)
    second_row.visible = two_rows and options_shown
    # Taken after the moves, so it is what the rows hold now and a signal that
    # only echoes them compares equal to it.
    _fitted = _fit_key(order)
    _refitting = false
    refitted.emit()


## Puts the overflow button at the end of the row the tool options are on: the
## second, after its slot, when *on_second*, and the first, between its slot and
## the window buttons, when not. Every tool option belongs on the second row,
## the overflow with them, and a button for the second row's tail
## standing on the first row beside the window buttons was a button for one row
## drawn on the other.
##
## Before the cut, because each row's budget counts the button where it stands,
## and a reparent only when the row changes, since a reparent re-sorts the row.
func _seat_overflow(on_second: bool) -> void:
    var row_box: HBoxContainer = second_row if on_second else main_row
    var slot: SaRowSlot = second_slot if on_second else brush_options_slot
    if not row_box.is_ancestor_of(overflow):
        (main_row if on_second else second_row).remove_child(overflow)
        row_box.add_child(overflow)
    row_box.move_child(overflow, slot.get_index() + 1)


## The menu titles that do not fit in `menu_room` go behind the row's last
## title, before the row is cut, since what the tool options have on the first
## row is what the menus leave. The title is the bar's, found by name the way
## everything pinned is.
func _fold_menus() -> void:
    var fold := main_row.get_node_or_null(^"HBoxMenuBar/MenuOverflowButton") as SaTopBarMenuOverflow
    if fold != null:
        fold.fit(menu_room())


## Logical pixels the menu titles have on the first row: the bar's width less its
## margins, the separator, the window buttons, the slot's gap, and the overflow
## button while the tool options are on this row and may need it, each with the
## gap after it. The button is counted whether it shows yet or not, because the
## cut that shows it runs after the titles are fitted, and without it a host
## 640 wide holds 698 of titles on a row of 628.
##
## The slot is its gap alone, since `SaRowSlot` asks for no width. Its minimum is
## not read here, because reading it measures every control in it before `_place`
## has fitted the sliders, and a control outside the tree keeps the minimum it
## first measured, so the sliders would read wider than they stand.
func menu_room(bar_width: float = -1.0) -> float:
    var width := bar_width if bar_width > 0.0 else _bar_width()
    var separation := float(main_row.get_theme_constant("separation"))
    var room := width - _margin_left - _margin_right - _pinned(main_row, ["MenuSeparator", "HBoxWindowControls"])
    if brush_options_slot.visible:
        room -= separation
    if main_row.is_ancestor_of(overflow) and options_shown and SaTopBarOverflow.enabled():
        room -= overflow.get_combined_minimum_size().x + separation
    return room


## A row's controls, or what is pinned beside them, asked for a different width,
## or the bar was resized, so the split is made again when that moved anything
## it is made from.
##
## A 1280 window on Windows drew "Keep blend" with the slot's
## arrow over its last letter from the first frame on, and the label came back
## after a menu was opened and closed. The split was made once, against widths
## that grew afterwards, and only a resize of the bar or a change of tool made it
## again, so the row held more than its budget and the slot scrolled the end of
## a control under its arrow. A control whose width changes, one that shows
## without a tool change, and menus whose titles change are all heard here.
##
## Godot sends the signal a frame later, when the size it finds differs from the
## last one it reported, and that last one is not always the size the refit
## left: showing a control reports it on the spot, whatever it held then. So a
## signal is taken as news only when what the split is made from differs from
## what the last refit left, and one that only echoes the refit's own moves runs
## nothing. Refitting on every echo can hold Sara in one frame until it
## crashes.
##
## The bar's `resized` comes here too. The second row shown or hidden changes
## the bar's height and nothing a row is measured by, and a resize that ran
## `refit` itself made every switch of the overflow cost two passes, the second
## moving nothing. A new width is in the key and still refits.
func refit_if_moved() -> void:
    if _refitting:
        return
    if _fit_key(SaSettings.get_layout_order("TopMenuBar")) == _fitted:
        return
    refit()


## The menus, the window buttons and the colour pair take the room they ask for
## from their row, so a change in one moves the budget. They are the bar's, and
## are put on the row after this is built, so they are listened to from the
## first refit rather than from here.
func _listen_to_pinned() -> void:
    for pinned: Control in [
        main_row.get_node_or_null(^"HBoxMenuBar"),
        main_row.get_node_or_null(^"HBoxWindowControls"),
        color_pair,
    ]:
        if pinned != null and not pinned.minimum_size_changed.is_connected(refit_if_moved):
            pinned.minimum_size_changed.connect(refit_if_moved)


## Puts every tool option control on the row *order* and *two_rows* say, and
## fits the sliders to what is left.
##
## Everything after the sentinel goes to the second row when there is one, and
## to the middle of the first when there is not. The controls keep their owner
## and their signals, only their parent moves, which is why calling this twice
## in one pass costs a reparent and not a rebuild.
##
## A control the order does not name comes after everything it does, the way
## `SaSettings.get_layout_order` appends what a stored order lacks, so it is
## past the sentinel and on the second row when there is one. Edit Brush is
## one, a row element on no order, and left wherever it was it would stay at
## the end of the first row, the one control of the brush up beside the menus.
##
## The second row's visibility is `refit`'s to set once it has placed
## everything, since a pass here is not the last word on how many rows there
## are.
func _place(order: Array, two_rows: bool) -> void:
    if _options == null:
        return
    # What the last pass put in the overflow goes back to the first row before
    # anything is placed, and the loops below put each of them where it goes.
    for held in overflow.box.get_children():
        overflow.box.remove_child(held)
        _options.add_child(held)
    _group_of = groups()
    var tool_opt_elements := elements()
    var past_sentinel := false
    var next_index := {}
    for element: String in order:
        if element == SaSettings.ROW_SENTINEL:
            past_sentinel = true
            continue
        if tool_opt_elements.has(element):
            _put(element, tool_opt_elements[element], second_options_row if past_sentinel and two_rows else _options, next_index)
    for element: String in tool_opt_elements:
        if not order.has(element):
            _put(element, tool_opt_elements[element], second_options_row if two_rows else _options, next_index)
    for row: int in [1, 2]:
        _draw_breaks(row)
    overflow.refresh()
    fit_sliders()


## Moves *node*, the control of *element*, to the next place on *target*, which
## *next_index* counts for each row, and shows it when the profile and the tool
## do.
func _put(element: String, node: Control, target: Container, next_index: Dictionary) -> void:
    if node == null:
        return
    if node.get_parent() != target:
        if node.get_parent() != null:
            node.get_parent().remove_child(node)
        target.add_child(node)
    _fit_height_to_row(element, node, target)
    _hold_whole(node)
    var index: int = next_index.get(target, 0)
    target.move_child(node, index)
    next_index[target] = index + 1
    node.visible = _element_visible(element, node)


## Moves what does not fit on each row into the overflow list, in the leave
## order, until the row fits, and lends the sliders what is then spare.
##
## A row gives up its controls in `leave_order`'s sequence rather than from its
## end, so what a painter reaches for most is the last to go: at 1280 Size and
## Opacity stay while the symmetry toggles are in the list. The list keeps the
## order the painter saw on the bar, the first row's controls and then the
## second's, whatever order they left in. The button's own width comes off the
## row it stands on before the cut, and the sliders are back at their minimum first,
## since a slider grown into the room of a row that fitted before the button
## appeared would push that row over.
##
## The second row is never brought back here. It shows when the painter asked for
## it, *two_rows*, and not otherwise, so the separator is there but optional,
## and a fresh profile asks for it.
func _overflow(two_rows: bool) -> void:
    if _options == null or not options_shown:
        return
    _reset_sliders()
    if _rows_over(two_rows).is_empty():
        fit_sliders()
        return
    overflow.visible = true
    # Counted again with the button shown, since it takes room from the row it
    # stands on, which may be the one that fitted.
    var rows_over := _rows_over(two_rows)
    var element_of := _element_of()
    var cut: Array[Control] = []
    for row in rows_over:
        var container := row_container(row)
        var budget := row_budget(row)
        var held := container.get_children()
        var leaving := {}
        for node in leave_order(row):
            if row_spent(row) <= budget:
                break
            container.remove_child(node)
            leaving[node] = true
            # A control that left can take a break's reason with it, the last
            # of a group or the one between two of the same, so the row's
            # breaks are drawn again before it is measured again.
            _draw_breaks(row)
        for child in held:
            if leaving.has(child):
                cut.append(child as Control)
    for node in cut:
        overflow.box.add_child(node)
        _fit_height_to_row(String(element_of[node]), node, overflow.box)
    overflow.refresh()
    fit_sliders()


## The rows that spend more than they have, the second only when it shows.
func _rows_over(two_rows: bool) -> Array[int]:
    var out: Array[int] = []
    for row: int in [1, 2]:
        if (row == 1 or two_rows) and row_spent(row) > row_budget(row):
            out.append(row)
    return out


## The controls *row* holds now, in the order a short row gives them up: the
## elements `LEAVE_FIRST` names, then every one neither list names from the row's
## end, then the elements `LEAVE_LAST` names, then the ones [method kept_on_row]
## keeps. Only a shown row element is in it, since a hidden one costs the row
## nothing and the next pass returns only row elements.
func leave_order(row: int) -> Array[Control]:
    var element_of := _element_of()
    var first: Array[Control] = []
    var middle: Array[Control] = []
    var last: Array[Control] = []
    var kept: Array[Control] = []
    var held_elements := kept_on_row()
    first.resize(LEAVE_FIRST.size())
    last.resize(LEAVE_LAST.size())
    var children := row_container(row).get_children()
    children.reverse()
    for child in children:
        var node := child as Control
        if node == null or not node.visible or not element_of.has(node):
            continue
        var element := String(element_of[node])
        if held_elements.has(element):
            kept.append(node)
        elif LEAVE_FIRST.has(element):
            first[LEAVE_FIRST.find(element)] = node
        elif LEAVE_LAST.has(element):
            last[LEAVE_LAST.find(element)] = node
        else:
            middle.append(node)
    var out: Array[Control] = []
    for node in first + middle + last + kept:
        if node != null:
            out.append(node)
    return out


## The elements a short row keeps whatever else it gives up: the brush's Erase
## while it is on, `ToolOptionsBar.ERASE_KEY` says why.
func kept_on_row() -> Array[String]:
    var out: Array[String] = []
    var erase := _options.control_for(ToolOptionsBar.ERASE_KEY) as Button if _options != null else null
    if erase != null and erase.button_pressed:
        out.append(String(ToolOptionsBar.ERASE_KEY))
    return out


## Control -> the element name it is stored under, for every row element there is.
func _element_of() -> Dictionary:
    var out := {}
    var tool_opt_elements := elements()
    for element: String in tool_opt_elements:
        if tool_opt_elements[element] != null:
            out[tool_opt_elements[element]] = element
    return out


## Stored element name -> the group it sits in, for every element that names
## one: the tool options bar's own and its tools' options, and the rotation's.
func groups() -> Dictionary:
    if _options == null:
        return {}
    var out: Dictionary = _options.layout_groups()
    out.merge(_extra_groups)
    return out


## Draws a break between two shown neighbours on *row* whose groups differ, and
## none at the row's start or beside an element with no group. Without them
## the bar read as "one run of buttons that look alike", the brush's controls,
## the stroke's switches and the view's turn in one row with nothing between
## them.
##
## A break is a child of the row like the controls, so `row_spent` counts the
## room it takes and the overflow cuts against it, and it is no row element, so
## nothing leaves the row or is ordered by the profile for its sake. Every
## break goes to the row's end hidden first, so the one shown before a control
## is moved there from behind it.
func _draw_breaks(row: int) -> void:
    var container := row_container(row)
    if container == null:
        return
    # Only the breaks still on this row's container, since a bar attached again
    # brings a container the old ones are not on.
    var rules: Array = _breaks.get(row, []).filter(
        func(rule: Variant) -> bool: return is_instance_valid(rule) and (rule as Node).get_parent() == container
    )
    _breaks[row] = rules
    for rule: VSeparator in rules:
        rule.visible = false
        container.move_child(rule, -1)
    var element_of := _element_of()
    var previous: StringName = &""
    for child in container.get_children():
        var node := child as Control
        if node == null or not node.visible or not element_of.has(node):
            continue
        var group: StringName = _group_of.get(element_of[node], &"")
        if group != previous and not group.is_empty() and not previous.is_empty():
            var rule := _break_rule(rules, container)
            rule.visible = true
            container.move_child(rule, node.get_index())
        previous = group


## The first hidden break of *rules*, or a new one on *container*, kept in
## *rules*, when every one is shown.
func _break_rule(rules: Array, container: Container) -> VSeparator:
    for rule: VSeparator in rules:
        if not rule.visible:
            return rule
    var made := SaMake.separator(container, "%s%d" % [BREAK_NAME, rules.size()], true) as VSeparator
    var line := StyleBoxFlat.new()
    SaTheme.bind(line, {"bg_color": "border_primary"})
    # One logical pixel of rule, drawn short of the controls' top and bottom so
    # it reads as a division of the row rather than a wall across it.
    line.content_margin_left = float(DockerUtils.px(1))
    line.expand_margin_top = -float(DockerUtils.px(4))
    line.expand_margin_bottom = -float(DockerUtils.px(4))
    made.add_theme_stylebox_override("separator", line)
    # The gap, which the row's own separation on either side widens.
    made.add_theme_constant_override("separation", DockerUtils.px(SaTheme.GAP_TIGHT))
    made.visible = false
    rules.append(made)
    return made


## The breaks *row* shows, in order, each with the two elements it stands
## between and their groups, for a capture that has to say where the bar
## divides and not only that it draws a line.
func breaks_report(row: int) -> Array:
    var out: Array = []
    var container := row_container(row)
    if container == null:
        return out
    var rules: Array = _breaks.get(row, [])
    var element_of := _element_of()
    var group_of := groups()
    var left := ""
    var open: Dictionary = {}
    for child in container.get_children():
        var node := child as Control
        if node == null or not node.visible:
            continue
        if rules.has(node):
            var rect := node.get_global_rect()
            open = {"after": left, "groups": [String(group_of.get(left, &""))], "x": rect.position.x, "w": rect.size.x}
            out.append(open)
        elif element_of.has(node):
            left = String(element_of[node])
            if not open.is_empty():
                open["before"] = left
                (open["groups"] as Array).append(String(group_of.get(left, &"")))
                open = {}
    return out


## A control on the second row takes the row's whole height, and one on the
## first keeps the height it was built with. The second row is as tall as the
## tallest control it holds, and a slider that kept its own height would sit in
## a band of empty bar above and below it.
func _fit_height_to_row(element: String, node: Control, target: Container) -> void:
    if not _first_row_v_flags.has(element):
        _first_row_v_flags[element] = node.size_flags_vertical
    if target == second_options_row:
        node.size_flags_vertical = SIZE_FILL
    else:
        node.size_flags_vertical = int(_first_row_v_flags[element])


## Every button in *node* that clips or trims its text asks for the whole of it,
## so the cut measures a drop-down at its value's width and sends it to the
## overflow with the next control when the row has less. A clipped one stayed on
## the row reading "Aver…" at 1920 and the preset "P…" at a font size of 1.3,
## since its minimum was the width it was built at. The docker builds controls
## of its own, which still clip, and so does a drop-down's list, a window of its
## own the walk does not enter.
func _hold_whole(node: Node) -> void:
    var button := node as Button
    if button != null and (button.clip_text or button.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING):
        button.clip_text = false
        button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
    for child in node.get_children():
        if not child is Window:
            _hold_whole(child)


## Whether the profile shows *element*, and the active tool has a use for it.
## The second half is the tool options bar's to answer: the eyedropper's two
## controls are the first that belong to one tool, and with them on the brush's
## row the default does not fit at 1920.
func _element_visible(element: String, node: Control) -> bool:
    return SaSettings.get_element_visible("TopMenuBar", element) and _options.shows_for_active_tool(node)


## A tool change shows and hides the controls that follow a tool, and the
## sliders take or give back the room. The order and the rows are the profile's
## and do not move.
func _on_tool_changed(_tool_name: String) -> void:
    if _options == null:
        return
    # With the overflow on, a control a tool shows can push the row over, so the
    # split is made again rather than only the sliders fitted. Unless the switch
    # shows the same controls at the same widths in the same room as the last
    # split, which is the brush and the eraser, and then there is nothing to move.
    if SaTopBarOverflow.enabled():
        if _fit_key(SaSettings.get_layout_order("TopMenuBar")) != _fitted:
            refit()
        return
    var tool_opt_elements := elements()
    for element: Variant in tool_opt_elements:
        var node: Control = tool_opt_elements[element]
        if node != null:
            node.visible = _element_visible(element, node)
    for row: int in [1, 2]:
        _draw_breaks(row)
    fit_sliders()
    # No refit ran, and a control that follows a tool came or went all the same.
    # The docker hears the same `tool_changed` and may have heard it first.
    refitted.emit()


## What a refit is made from, as one array to compare: the bar's width, the
## section and row switches, *order*, the elements the profile and the active
## tool show, in the order `elements` names them, the minimum width of each
## shown control that is not a slider, the overflow's switch, and what the
## menus, the window buttons and the colour pair take from their rows.
##
## The widths are there because a control grows after the bar is fitted, a
## dropdown whose label is synced late or a preset name read after the first
## pass, which a refit on every switch would put right in passing. Without them
## the first switch after boot leaves a button past the row's edge. The sliders are left out because a refit sets their width
## itself, so they would never compare equal. What is pinned is there because
## `refit_if_moved` hears it, and a menu title that grows is news to
## the split that no control of the rows carries.
func _fit_key(order: Array) -> Array:
    var shown: Array[String] = []
    var widths: Array[float] = []
    # A dictionary and not the typed array `sliders` answers, which refuses to
    # be asked about a control that is not a slider.
    var sliders := {}
    if _options != null:
        for slider: Control in _options.sliders():
            sliders[slider] = true
    var tool_opt_elements := elements()
    for element: String in tool_opt_elements:
        var node: Control = tool_opt_elements[element]
        if node == null or not _element_visible(element, node):
            continue
        shown.append(element)
        if not sliders.has(node):
            widths.append(node.get_combined_minimum_size().x)
    # What was added for the width signal goes at the end, since a suite reads
    # the shown elements off the key by index.
    return [
        _bar_width(),
        options_shown,
        SaSettings.second_row,
        order.duplicate(),
        shown,
        widths,
        SaTopBarOverflow.enabled(),
        _pinned(main_row, ["HBoxMenuBar", "HBoxWindowControls"]),
        _pinned(second_row, ["ColorPair"]),
    ]


## Stored element name -> the control it stands for. The tool options bar
## answers for its own, because the controls are built from each tool's
## descriptor and a fixed dictionary here would miss every module's.
func elements() -> Dictionary:
    if _options == null:
        return {}
    var out: Dictionary = _options.layout_elements()
    out.merge(_extra_elements)
    return out


## The container the controls of *row* sit in: the tool options bar on the
## first, the second row's own on the second.
func row_container(row: int) -> Container:
    return second_options_row if row == 2 else _options


## Logical pixels the tool option controls on *row* need: the sum of their
## minimum widths plus the separation between them. Minimum sizes rather than
## laid-out rects, so this can be asked before the container has laid anything
## out, which is what makes it testable inside `_ready`.
func row_spent(row: int) -> float:
    var container := row_container(row)
    if container == null:
        return 0.0
    var total := 0.0
    var shown := 0
    for child in container.get_children():
        var control := child as Control
        if control == null or not control.visible:
            continue
        total += control.get_combined_minimum_size().x
        shown += 1
    if shown > 1:
        total += float(container.get_theme_constant("separation")) * float(shown - 1)
    return total


## Logical pixels *row* has for its tool option controls, given the bar is
## *bar_width* wide: the whole width less the bar's margins, and on the first
## row less the menus, the separator and the window buttons as well, because
## those are pinned. The second row loses the colour pair and its separator for
## the same reason, since they are pinned there. The overflow button comes off
## whichever row it stands on, and only while it shows.
##
## The width is the parent's rather than this box's own, because the bar sorts
## its children a frame after it is resized, and a refit run from the bar's
## `resized` has to measure the width the bar already has.
func row_budget(row: int, bar_width: float = -1.0) -> float:
    var width := bar_width if bar_width > 0.0 else _bar_width()
    var budget := width - _margin_left - _margin_right
    if row == 2:
        return budget - _pinned(second_row, ["ColorPair", "ColorPairSeparator", "OverflowButton"])
    return budget - _pinned(main_row, ["HBoxMenuBar", "MenuSeparator", "HBoxWindowControls", "OverflowButton"])


## The width of the bar this is placed in, or the project's window width before
## the bar has one.
##
## The width the bar's anchors and offsets give it in what it is anchored to,
## its parent control or the window when it has none, as `Main` is a `Node`,
## rather than the bar's size. A control is never narrower than its minimum, so a
## menu row wider than the window holds the bar wider than its host, and a fit
## measured against the bar's own width would find room for every title and
## never let it shrink.
func _bar_width() -> float:
    var bar := get_parent_control()
    var host := 0.0
    if bar != null and bar.get_parent_control() != null:
        host = bar.get_parent_control().size.x
    elif bar != null and bar.is_inside_tree():
        host = bar.get_viewport_rect().size.x
    if host > 0.0:
        return host * (bar.anchor_right - bar.anchor_left) + bar.offset_right - bar.offset_left
    if bar != null and bar.size.x > 0.0:
        return bar.size.x
    return float(ProjectSettings.get_setting("display/window/size/viewport_width", 1920))


## What the named children of *row_box* cost it, each with the separation that
## follows it, counting only the ones on screen.
func _pinned(row_box: Container, names: Array) -> float:
    var separation := float(row_box.get_theme_constant("separation"))
    var spent := 0.0
    for child_name: String in names:
        var node := row_box.get_node_or_null(NodePath(child_name)) as Control
        if node == null or not node.visible:
            continue
        spent += node.get_combined_minimum_size().x + separation
    return spent


## What *row* holds, child by child, for a capture that has to say which control
## overruns rather than only by how much.
##
## `row_spent` and `row_budget` are two numbers and a row that overruns by 133
## logical pixels is not answerable from them: the question a fixer asks is which
## control is past the edge and what the row did to the ones before it. So this
## reports the name, the minimum width and the laid-out rect of every visible
## child, plus the row's own rect, and `over_by` per child, which is how far its
## right edge is past the row's.
##
## Minimum widths beside the rects on purpose. An `HBoxContainer` whose children
## want more than it has shrinks them below their minimums rather than
## overflowing, so the symptom of an overrun is a control narrower than it says
## it can be, and neither number shows it alone.
func row_report(row: int) -> Dictionary:
    var row_box: Container = main_row if row == 1 else second_row
    var edge := row_box.get_global_rect().end.x
    var children: Array = []
    for child in row_box.get_children():
        var control := child as Control
        if control == null or not control.visible:
            continue
        var rect := control.get_global_rect()
        (
            children
            . append(
                {
                    "name": String(control.name),
                    "min": control.get_combined_minimum_size().x,
                    "x": rect.position.x,
                    "w": rect.size.x,
                    "squeezed": maxf(0.0, control.get_combined_minimum_size().x - rect.size.x),
                    "over_by": maxf(0.0, rect.end.x - edge),
                }
            )
        )
    var options: Array = []
    var container := row_container(row)
    if container != null:
        var slot_edge := container.get_global_rect().position.x + row_budget(row)
        for child in container.get_children():
            var control := child as Control
            if control == null or not control.visible:
                continue
            var rect := control.get_global_rect()
            (
                options
                . append(
                    {
                        "name": String(control.name),
                        "min": control.get_combined_minimum_size().x,
                        # The height it asks for, which is what the second row's
                        # height was measured from.
                        "min_h": control.get_combined_minimum_size().y,
                        "x": rect.position.x,
                        "w": rect.size.x,
                        "over_by": maxf(0.0, rect.end.x - slot_edge),
                    }
                )
            )
    var slot := brush_options_slot if row == 1 else second_slot
    return {
        "present": true,
        "spent": row_spent(row),
        "budget": row_budget(row),
        "x": row_box.get_global_rect().position.x,
        "w": row_box.get_global_rect().size.x,
        # How tall the row is and where it starts, and the bar's own height,
        # which is what the docker columns start under.
        "y": row_box.get_global_rect().position.y,
        "h": row_box.get_global_rect().size.y,
        "bar_h": get_parent_control().size.y if get_parent_control() != null else 0.0,
        "children": children,
        # The controls inside the slot, which is where an overrun actually lives:
        # the row itself never breaks, the slot is given exactly its budget and
        # scrolls whatever does not fit.
        "options": options,
        # Which edges of the slot carry the arrow that says controls are past
        # them, so a capture reads the sign and not only the picture.
        "sign": {"left": slot._fade_left.visible, "right": slot._fade_right.visible},
        # The button and its list hold the tails of both rows, and are reported
        # with the first, wherever the button stands.
        "overflow": overflow.report() if row == 1 else {},
        # Whether the button stands on this row, which a fresh bar answers
        # with the second.
        "holds_overflow": row_box.is_ancestor_of(overflow),
        # Where the row divides between its groups.
        "breaks": breaks_report(row),
    }


## Widens the sliders of each row into the room the row has spare, up to the
## bar's extra, and never below the minimum. Idempotent: every slider goes back
## to the minimum first, so the spare is measured the same way on every call,
## and a resize re-runs it.
func fit_sliders() -> void:
    if _options == null:
        return
    var base := _reset_sliders()
    for row: int in [1, 2]:
        var container := row_container(row)
        var row_sliders: Array = []
        for slider: Control in _options.sliders():
            if slider.get_parent() == container and slider.visible:
                row_sliders.append(slider)
        if row_sliders.is_empty():
            continue
        var spare := row_budget(row) - row_spent(row)
        if spare <= 0.0:
            continue
        var extra := minf(float(DockerUtils.px(ToolOptionsBar.SLIDER_EXTRA_WIDTH)), spare / float(row_sliders.size()))
        for slider: FactorSlider in row_sliders:
            slider.preferred_width = int(base + floorf(extra))
            slider.custom_minimum_size.x = base + floorf(extra)


## Every slider back at the minimum width, which is answered.
func _reset_sliders() -> float:
    var base := float(DockerUtils.px(ToolOptionsBar.SLIDER_MIN_WIDTH))
    for slider: FactorSlider in _options.sliders():
        slider.preferred_width = int(base)
        slider.custom_minimum_size.x = base
    return base
