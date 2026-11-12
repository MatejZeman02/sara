## The brush editor's left-hand list: one row per page under two headings,
## and a dot beside each dynamic that is on.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Its own file rather than a block of `brush_editor_window.gd`, because the row
## is the one piece of this window with a rule in it and the window is otherwise
## a layout.
##
## **The rule.** The pages that make the brush, the tip
## and the general rows, sit under "Brush", and every page with something to
## switch on, a curve option or a page switch, sits under "Dynamics". A row is a
## title and nothing a painter can press but the title: a dynamic that is on
## carries a dot in the accent, and its switch is at the top of its own page.
##
## A dot rather than Krita's checkbox on every row that names a curve option,
## because a painter who clicks the box to open a page turns a dynamic on
## without seeing it. The dot says what a tick would, and pressing it does
## nothing, so reading the list cannot change the brush.
##
## **The Brush Presets section** chooses a different brush without leaving
## the editor. It is a header the painter presses, above the rows, and a box that the
## window fills with the chooser the Brush Presets docker already hosts, so this
## file names no chooser and no store: it owns the fold and the room, and the
## window owns what goes in it.
##
## **The box is a column of its own, left of the page rows**, resizable and
## optional as the scratchpad is. It is the first child of the split the window hands
## this list, takes the editor's height, and carries the same `SaSplitSnap` the
## scratchpad does: dragged under its floor it snaps shut, dragged back it snaps
## to the width it had, and the header's fold is the same shut and open with no
## drag. The header stays above the rows rather than at the top of the column,
## because a column that is gone has nowhere to show the button that brings it
## back.
##
## Collapsed by default, and the state is a profile preference rather than a
## field here, because a painter who works from presets wants it open in every
## document and a painter who does not never wants to see it.
class_name SaBrushEditorPageList
extends VBoxContainer

## A row's button was pressed. The window swaps the page on the right.
signal page_selected(index: int)

## The presets section was folded open or shut. The window remembers it.
signal presets_folded(open: bool)

## The height of a row, and the slot the dot sits in at its right end with the
## dot's own size. The slot is kept on every row, so a dot coming and going
## moves no title.
const ROW_HEIGHT: int = 26
const DOT_SLOT: int = 18
const DOT_SIZE: int = 8

## The two headings, the pages that make the brush and the pages that move it.
const BRUSH_HEADING: String = "Brush"
const DYNAMICS_HEADING: String = "Dynamics"

## What the section's header reads, and the icon before it, folded and open.
## The arrows are the pair the Recorder's fold and a group's row draw, icons
## rather than the triangles U+25B6 and U+25BC in the text, which Atkinson
## Hyperlegible and IBM Plex Sans have no glyph for.
const PRESETS_TITLE: String = "Brush Presets"
const FOLDED_ARROW: String = "chevron_right"
const OPEN_ARROW: String = "chevron_down"

## How wide the presets column is when a profile has no width for it, and the
## floor under a drag, in logical units. The column takes the editor's height
## rather than a fixed slice of the page list, because a fixed slice pushes the
## page rows down, the rows scroll, and the library is a strip. A library too big for the column scrolls inside
## it, which is why the box is a `ScrollContainer`. The default is what the
## chooser's top row, search, tag and size, asks for at the default font, so
## nothing is clipped until the painter makes it narrower.
const PRESETS_WIDTH: int = 300
const PRESETS_MIN_WIDTH: int = 150

## The gap around the column's chrome, the same eight every other box in this
## window insets by, and the four sides it is written on.
const MARGIN: int = 8
const SIDES: Array[String] = ["margin_left", "margin_right", "margin_top", "margin_bottom"]

## title -> the row's controls, in the order the pages were declared, which is
## the index a row is selected and marked by whichever heading it sits under.
var _rows: Array[Dictionary] = []

## The headings the last build drew, freed with the rows by the next one.
var _headings: Array[Control] = []
var selected: int = -1

## The fold: the header the painter presses, the box the window puts the chooser
## in, and whether it is showing. All three are read from outside, which the
## privates rule allows, and all three are written by this class alone:
## [method fold_presets] is the only thing that moves the state, and the window
## calls it rather than assigning.
var presets_header: Button = null
var presets_box: ScrollContainer = null
var presets_open: bool = false

## The column the box sits in, the split's first child, and the snap on that
## split. The split is a constructor argument because the window builds it
## before this list and adds the column to it after, and a list built alone,
## which is every headless test of this file, has a snap with no split.
var presets_column: MarginContainer = null
var snap: SaSplitSnap = null

## Where the page rows go, under the fold. Its own scrolling box rather than
## this list's direct children, so the fold takes its room from the rows'
## scrollbar rather than from the rows.
var rows_box: VBoxContainer = null


func _init(presets_split: HSplitContainer = null) -> void:
    name = "BrushEditorPageList"
    add_theme_constant_override("separation", SaUI.px(2))
    snap = SaSplitSnap.new(presets_split, true, PRESETS_MIN_WIDTH, PRESETS_WIDTH)
    snap.moved.connect(_on_snap_moved)
    _build_presets_section()
    _build_rows_box()


## The header above every page row, so the section reads as a heading over the
## list rather than as another page, and the column with the empty box in it,
## which the window puts left of the list.
func _build_presets_section() -> void:
    presets_header = SaMake.button(self, "PresetsHeader")
    presets_header.flat = true
    presets_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
    # The arrow as tall as the row and no taller, the height it had as text.
    presets_header.expand_icon = true
    presets_header.focus_mode = Control.FOCUS_NONE
    presets_header.custom_minimum_size = Vector2(0.0, float(SaUI.px(ROW_HEIGHT)))
    presets_header.pressed.connect(func() -> void: fold_presets(not presets_open, true))

    presets_column = MarginContainer.new()
    presets_column.name = "PresetsColumn"
    # Fill and not expand, which is what makes the column's width the split's
    # offset rather than a share of the room the pages leave.
    presets_column.size_flags_horizontal = Control.SIZE_FILL
    presets_column.size_flags_vertical = Control.SIZE_EXPAND_FILL

    presets_box = SaMake.scroll(presets_column, "PresetsBox")
    presets_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    presets_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
    # No bar sideways, and no minimum from what is inside either. A grid counts
    # the columns that fit the width it was given, so a horizontal bar would
    # mean it had counted against the wrong number. Disabled, the mode first chosen,
    # also made the box as wide as the chooser's top row, 300 at the default
    # font, and a split refuses to drag a child under its minimum, so the
    # grabber could never reach the floor and the column could never be shut by
    # hand: the first run of the fold's scenario showed 300 for an offset of
    # 220. Never shown lets the box be any width and clips the row's right end
    # when the column is narrower than the row asks for.
    presets_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER

    fold_presets(false, false)


## The column is this list's until the window places it, and a list freed
## with the column still in hand takes it along: a list built alone, which is
## every headless test of this file, would otherwise leave a node the leak
## check counts. Placed, the column is the split's to free.
func _notification(what: int) -> void:
    if what != NOTIFICATION_PREDELETE:
        return
    if is_instance_valid(presets_column) and presets_column.get_parent() == null:
        presets_column.free()


## The rows' own scrolling box.
func _build_rows_box() -> void:
    var scroll := SaMake.scroll(self, "PageRows")
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    rows_box = SaMake.column(scroll, "Rows", 2)
    rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Opens or shuts the section. *announce* is false for the state restored from
## the profile, so putting the painter back where they were is not a change the
## profile has to be told about again.
func fold_presets(open: bool, announce: bool = true) -> void:
    presets_open = open
    if presets_header != null:
        presets_header.icon = SaUI.get_icon(OPEN_ARROW if open else FOLDED_ARROW)
        presets_header.text = tr(PRESETS_TITLE)
    if snap.shut == open:
        snap.restore(0, not open)
    _lay_out_column()
    if announce:
        presets_folded.emit(open)


## Reads the profile's width and open state and lays the column out to them, on
## every open of the editor. The open state keeps its first key.
func restore_presets() -> void:
    var stored: int = SaSettings.brush_editor_presets_width
    snap.restore(stored if stored > 0 else PRESETS_WIDTH, not SaSettings.brush_editor_presets_open)
    fold_presets(SaSettings.brush_editor_presets_open, false)


## The snap moved, by a hand on the grabber or a scenario's drag. The width
## is the profile's at once, and a drag that shut the column or snapped it
## open is the same fold the header makes, announced so the window writes the
## open state the way it does for a press.
func _on_snap_moved(open_width: int, shut: bool) -> void:
    SaSettings.brush_editor_presets_width = open_width
    if presets_open == shut:
        fold_presets(not shut, true)
    else:
        _lay_out_column()


## Puts the inset and the box where the state says. Shut is offset nought and
## no inset, so the pages have the whole width and nothing of the column is
## left to see.
func _lay_out_column() -> void:
    if presets_column == null:
        return
    for side in SIDES:
        presets_column.add_theme_constant_override(side, SaUI.px(0 if snap.shut else MARGIN))
    if presets_box != null:
        presets_box.visible = not snap.shut


## Builds a row per entry of *pages*, each `{"title": String, "dynamic": bool,
## "switch": bool, "on": bool}`, and forgets whatever was there.
##
## The brush's pages first and the dynamics after, each in the order they were
## declared, so a module that declares a plain page after a dynamic still gets
## two headings rather than a third. A row keeps its index in *pages*, which is
## what `page_selected` answers, whatever heading it was drawn under.
##
## The dictionary rather than the `SaCurveOption` itself, because the list has no
## business holding the resource: the window owns the binding and the list owns
## the row.
func build(pages: Array) -> void:
    # The rows only. The presets section is this list's own chrome rather than a
    # page, and a rebuild that took it away would empty the box the window put
    # the chooser in and leave a header over nothing.
    # Taken out of the box before they are freed, rather than left in it until
    # the frame ends. Left in, the new rows are laid out under the old ones, the
    # open page's row is scrolled to down there, and the old rows going take
    # the list to its bottom, so the Brush Tip page opens with the list showing
    # the rows far below it.
    for entry: Dictionary in _rows:
        var row := entry.get("row") as Control
        if row != null:
            rows_box.remove_child(row)
            row.queue_free()
    for heading: Control in _headings:
        rows_box.remove_child(heading)
        heading.queue_free()
    _rows.clear()
    _headings.clear()
    selected = -1
    for i in pages.size():
        _rows.append({})
    for dynamic: bool in [false, true]:
        var headed := false
        for i in pages.size():
            var page := pages[i] as Dictionary
            if bool(page.get("dynamic", false)) != dynamic:
                continue
            if not headed:
                _headings.append(_build_heading(DYNAMICS_HEADING if dynamic else BRUSH_HEADING))
                headed = true
            _rows[i] = _build_row(i, page)


## A heading over a group, drawn the way a page's own sections are. As tall as
## a row with its words at the bottom, so the room above it is what sets the
## group off from the rows of the one before.
func _build_heading(text: String) -> Label:
    var heading := SaMake.label(rows_box, "%sHeading" % text, tr(text))
    SaUI.size_text(heading, SaUI.fraction_of(13))
    SaSettingsRows.embolden(heading)
    heading.custom_minimum_size = Vector2(0.0, float(SaUI.px(ROW_HEIGHT)))
    heading.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
    return heading


func _build_row(index: int, page: Dictionary) -> Dictionary:
    var title := String(page.get("title", ""))
    var row := SaMake.row(rows_box, "Row%d" % index, SaTheme.GAP_TIGHT)
    row.custom_minimum_size = Vector2(0.0, float(SaUI.px(ROW_HEIGHT)))

    var button := SaMake.button(row, "Title", title)
    button.flat = true
    button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.pressed.connect(func() -> void: page_selected.emit(index))

    # A slot on every row and a dot in it only for a dynamic, so the titles end
    # where they end whatever is on. A round panel in the accent rather than a
    # glyph, because the accent is what "on" means across Sara and a glyph's
    # colour is the font's.
    var slot := CenterContainer.new()
    slot.name = "DotSlot"
    slot.custom_minimum_size = Vector2(float(SaUI.px(DOT_SLOT)), 0.0)
    slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(slot)
    var dot: Panel = null
    if bool(page.get("switch", false)):
        dot = Panel.new()
        dot.name = "OnDot"
        # Passed rather than ignored, so the tooltip below can be read, and a
        # press on it still reaches nothing that switches.
        dot.mouse_filter = Control.MOUSE_FILTER_PASS
        dot.custom_minimum_size = Vector2(float(SaUI.px(DOT_SIZE)), float(SaUI.px(DOT_SIZE)))
        var style := StyleBoxFlat.new()
        SaTheme.bind(style, {"bg_color": "accent_primary"})
        style.set_corner_radius_all(SaUI.px(DOT_SIZE))
        dot.add_theme_stylebox_override("panel", style)
        dot.tooltip_text = tr("On. Its switch is at the top of its page.")
        dot.visible = bool(page.get("on", false))
        slot.add_child(dot)

    return {"title": title, "row": row, "dot": dot, "button": button, "dynamic": bool(page.get("dynamic", false))}


## Marks the row at *index* as the open one. The chosen row is the one drawn
## unflat, which is how the Preferences list says the same thing.
func select(index: int) -> void:
    selected = index
    for i in _rows.size():
        var button := _rows[i]["button"] as Button
        if button != null:
            button.flat = i != index
    _carry_focus(index)
    # Scrolled into view a frame later, because the rows are laid out after the
    # call that selected one: The first shot of a switch on its tick had the
    # Texture page open and its row below the bottom of the column, so the tick
    # being proved was not in the picture.
    if index >= 0 and index < _rows.size():
        var row := _rows[index]["row"] as Control
        var scroll := rows_box.get_parent() as ScrollContainer
        if row != null and scroll != null:
            scroll.ensure_control_visible.call_deferred(row)


## Hands the keyboard's focus to the open row when another row holds it, shown
## or hidden as it was.
##
## A flat row draws nothing but its focus box, so a row that kept the focus
## after another page was opened was outlined beside the open one, and the list
## read as two pages picked at once, Look open and General outlined. A press on
## a row moves the focus there itself,
## and hidden, so the case is a page opened some other way, by the door's page
## step or a rebind, while a row the keyboard had reached kept it. Moved rather
## than released, so a painter who walks the list with the keys still has it
## where they are, and arrowing to a row without opening it still outlines that
## row, which is the keyboard showing where it is. Only a row's focus is moved,
## because a slider or a field on the page that holds it is where the painter
## is working.
func _carry_focus(index: int) -> void:
    if index < 0 or index >= _rows.size() or not is_inside_tree():
        return
    var to := _rows[index]["button"] as Button
    var holder := get_viewport().gui_get_focus_owner()
    if to == null or holder == null or holder == to or not _is_row_button(holder):
        return
    to.grab_focus(not holder.has_focus(true))


func _is_row_button(control: Control) -> bool:
    for entry: Dictionary in _rows:
        if entry.get("button") == control:
            return true
    return false


func page_count() -> int:
    return _rows.size()


func title_at(index: int) -> String:
    return String(_rows[index]["title"]) if index >= 0 and index < _rows.size() else ""


## Shows or hides the row's dot, for a page whose switch moved, on its page
## or from somewhere else. A page with nothing to switch has no dot to show.
func show_on(index: int, on: bool) -> void:
    if index < 0 or index >= _rows.size():
        return
    var dot := _rows[index].get("dot") as Panel
    if dot != null:
        dot.visible = on


## Every row, for a dump: its title, the heading it sits under, whether it has a
## switch, whether its dot is showing, and whether it is the open page.
##
## `switch` is reported beside `on` on purpose. A plain page reads `on` false
## because it has nothing to switch, and a dynamic switched off reads the same,
## and only the first field tells the two apart. There is no `checkable` any
## more, because no row carries anything a press can tick.
func row_report() -> Array:
    var out: Array = []
    for i in _rows.size():
        var dot := _rows[i].get("dot") as Panel
        (
            out
            . append(
                {
                    "title": String(_rows[i].get("title", "")),
                    "group": DYNAMICS_HEADING if bool(_rows[i].get("dynamic", false)) else BRUSH_HEADING,
                    "switch": dot != null,
                    "on": dot != null and dot.visible,
                    "selected": i == selected,
                }
            )
        )
    return out


## `{"presets": {"fold": true, "drag": 300, "pick": "Inker"}}`: folds the
## section, drags the column's grabber to a width in logical units, and answers
## the name a cell click would have announced, or `""` when the step named none.
##
## The fold and the drag are applied here and the pick is answered rather than
## applied, because what a preset means is the window's to say and this list
## holds no store. A helper rather than a click for the reason the editor's
## whole capture door gives: the editor is its own `Window` and an injected
## press never reaches a control inside one.
func capture_presets(spec: Dictionary) -> String:
    if spec.has("fold"):
        fold_presets(bool(spec["fold"]))
    if spec.has("drag"):
        snap.drag_to(int(spec["drag"]))
    return String(spec.get("pick", ""))


## What the fold is showing, for a dump. Whether the section is open and whether
## the window has put anything in it, which is two claims a screenshot of a shut
## fold cannot make, and the column's width as laid out beside the width it
## snaps back to, because a column that is gone is a shot of the pages and only
## the numbers say it is a drag away.
func presets_report() -> Dictionary:
    var out := {
        "open": presets_open,
        "filled": presets_box != null and presets_box.get_child_count() > 0,
        "header": presets_header.text if presets_header != null else "",
        # Which icon the header draws, by its file's name, read off the button.
        "arrow": _arrow_drawn(),
        "width": int(presets_column.size.x) if presets_column != null else 0,
        "height": int(presets_column.size.y) if presets_column != null else 0,
    }
    out.merge(snap.report())
    return out


## The name of the icon the header draws, "chevron_right" or "chevron_down", or
## "" before it has one.
func _arrow_drawn() -> String:
    if presets_header == null or presets_header.icon == null:
        return ""
    return presets_header.icon.resource_path.get_file().get_basename()
