## The presets chooser's cells: each one built, the queue of those still to
## build, and the pictures they wait for.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Out of `brush_presets_chooser.gd` for the reason `SaBrushPresetStars` is: the
## chooser owns which presets the grid lists and what it is filtered by, and
## this owns the cells that show them. A cell is a column holding the picture's
## button, the star on it and the name under it, with the hover plate behind all
## three, and its picture comes off disk or from `SaBrushPresetPictures`.
##
## **A grid is built over frames rather than in one.** The chooser binds the grid
## in one call, and on a boot that call is the presets scan's, so every cell
## built in it, each picture read off disk on a warm profile, lengthens the
## scan's frame by tens of milliseconds. So a grid built in shares puts
## a stand-in of a cell's size wherever a cell will be, and builds the cells
## `SLICE_USEC` a frame, the ones in sight first. A grid built at once builds
## every cell in the call, which is what a suite's chooser and the brush
## editor's do.
##
## **A cell is kept while it is still right.** It shows one preset at one icon
## size, as a stroke or a tip, marked or not, so a grid laid out again keeps the
## cell of every preset it still lists the same way and moves it to its new
## place. A search typed while the cells are being built answers from the cells
## there are, and a preset picked builds two cells again, the one losing the
## mark and the one taking it, rather than every one.
class_name SaBrushPresetCells
extends RefCounted

## How long building may take of one frame, in microseconds, a quarter of a
## frame at 60 Hz. A cell costs under a millisecond, its picture read off disk
## among it, so a share is a row or two of the docker's grid.
const SLICE_USEC: int = 4000

## The grid the cells are children of, which is the chooser's.
var grid: GridContainer = null

## The star every cell carries, and what a press on a cell means, both the
## chooser's and handed over.
var _stars: SaBrushPresetStars = null
var _chosen: Callable = Callable()
var _menu: Callable = Callable()

## The pictures still to come, drawn a few events a frame once no cell waits.
var _pictures := SaBrushPresetPictures.new()

## What the cells are built for: the store, the icon size, whether they show the
## tip, and which preset is marked. A change to the first three lets every cell
## go, a change of the mark the two cells it moves between.
var _store: SaPresetStore = null
var _icon: int = 0
var _tip: bool = false
var _marked: String = ""

## How wide and how tall every cell's name is declared, the chooser's
## `name_width` and two lines of the name's font, written before [method refresh].
var name_floor := Vector2.ZERO

## Preset name to its cell, `{box, button, label, drawn, marked}`, for the cells
## built. A name the grid lists and has not built stands in `_stand_ins`.
var _cells: Dictionary = {}
var _stand_ins: Dictionary = {}

## The names the grid holds, in its order, and each one's place in it.
var _order: Array[String] = []
var _place: Dictionary = {}

## The names still to build, in the grid's order. The ones in sight are taken
## out of it first.
var _waiting: Array[String] = []

## The name of the tile the pointer is over, empty when it is over none. The tile
## draws its own hover from it, because the picture's button draws its hover over
## the picture only. Written by the tile's pointer handlers alone.
var _hovered: String = ""

## The tile a left press landed on outside its picture and where, in the
## window's pixels, until its release picks it or not.
var _left_pressed: String = ""
var _left_press_at := Vector2.ZERO

## What a share reads the time off, in microseconds, `Time.get_ticks_usec`
## unless a suite hands it a clock of its own.
var _clock: Callable = Time.get_ticks_usec


## *chosen* is called with a preset's name when its cell is pressed, and *menu*
## with the name and the picture's button when it is pressed with the right
## button, so what both mean stays the chooser's to say. *clock* answers the time
## in microseconds, and is a suite's to hand over.
func _init(
    cell_grid: GridContainer, stars: SaBrushPresetStars, chosen: Callable, menu: Callable, clock: Callable = Callable()
) -> void:
    grid = cell_grid
    _stars = stars
    _chosen = chosen
    _menu = menu
    if clock.is_valid():
        _clock = clock
    _pictures.drawn.connect(_show_drawn)


## Lays the grid out as *names* in that order, keeping every cell that is still
## right and building or standing in for the rest, and queues the pictures that
## are out of date. *painter* and *painters* draw a picture, as the chooser holds
## them, and *name_box* is the name's declared width and height. With
## *at_once* every cell is built here, and otherwise by `build`.
func lay_out(
    names: Array[String],
    store: SaPresetStore,
    painter: Script,
    painters: Dictionary,
    icon: int,
    tip: bool,
    marked: String,
    name_box: Vector2,
    at_once: bool
) -> void:
    if store != _store or icon != _icon or tip != _tip:
        _let_go_of_every_cell()
    _store = store
    _icon = icon
    _tip = tip
    _marked = marked
    name_floor = name_box
    var listed := {}
    for stored_name: String in names:
        listed[stored_name] = true
    for stored_name: String in _cells.keys():
        if not listed.has(stored_name) or bool(_cells[stored_name]["marked"]) != (stored_name == marked):
            _let_go(_cells[stored_name]["box"])
            _cells.erase(stored_name)
    for stored_name: String in _stand_ins.keys():
        if not listed.has(stored_name):
            _let_go(_stand_ins[stored_name])
            _stand_ins.erase(stored_name)
    if not _cells.has(_hovered):
        _hovered = ""
    _order = names.duplicate()
    _place.clear()
    _waiting.clear()
    for at in _order.size():
        var stored_name := _order[at]
        _place[stored_name] = at
        if _cells.has(stored_name):
            _keep(stored_name, at)
        elif at_once:
            _build(stored_name)
        else:
            _stand_in(stored_name, at)
            _waiting.append(stored_name)
    _queue_pictures(painter, painters)


## One frame's share: cells built for *budget_usec*, the ones in sight first, or
## every one when it is negative. A frame with no cell to build draws a share of
## the pictures instead, so a frame is one share however much is still to come.
## Answers whether the share went to cells.
##
## **A share stops before the cell that would take it past its budget**, by the
## slowest cell it built so far, rather than at the first cell past it. A cell is
## never cut, so the first of a share is built whatever it costs, and a share runs
## over only by a cell slower than every one before it in that frame.
##
## **A clock that counts frames builds the grid whole**, as
## `SaBrushPresetPictures.draw` draws a picture whole under one, because a share
## of real microseconds fills the grid over as many frames as the machine was
## fast, and the grid's widest cell is what the docker asks to be: a lesson
## filmed twice by `lesson_videos.py` had its Brush Presets docker 60 pixels
## narrower in one of the two from the frame the flyout opened to the end. A
## cell costs well under a millisecond, so a whole grid is a frame of tens of
## them, and the pictures stay one a frame.
func build(budget_usec: int) -> bool:
    if SaPenClock.is_pinned():
        budget_usec = -1
    if _waiting.is_empty():
        _pictures.draw(SaBrushPresetPictures.share_usec() if budget_usec > 0 else budget_usec)
        return false
    var started: int = _clock.call()
    var last := started
    var slowest := 0
    var sight := _in_sight()
    while not _waiting.is_empty():
        _build(_take_next(sight))
        var now: int = _clock.call()
        slowest = maxi(slowest, now - last)
        last = now
        if budget_usec >= 0 and now - started + slowest > budget_usec:
            break
    return true


## Builds every cell still waiting and draws every picture still to come, for a
## test or a scenario that wants the grid finished rather than filling.
func finish() -> void:
    build(-1)
    while _pictures.draw(-1):
        pass


## Lets go of the picture under way, which holds an easel and not a reference.
func drop() -> void:
    _pictures.drop()


## The name's declared width and height moved, which is a theme pass, so every
## cell and stand-in takes `name_floor` now rather than at the next build.
func refresh() -> void:
    for stored_name: String in _cells:
        ((_cells[stored_name] as Dictionary)["label"] as Label).custom_minimum_size = name_floor
    for stored_name: String in _stand_ins:
        (_stand_ins[stored_name] as Control).custom_minimum_size = _stand_in_size()


## The widest a cell of the grid asks to be, built or standing in, which is the
## pitch `_columns_that_fit` counts with.
func widest() -> float:
    var widest_cell := 0.0
    for child in grid.get_children():
        widest_cell = maxf(widest_cell, (child as Control).get_combined_minimum_size().x)
    return widest_cell


## What the chooser's report says of the cells: how many show their picture, how
## many pictures and cells are still to come, and the size a picture is shown at.
func report() -> Dictionary:
    var drawn := 0
    for stored_name: String in _cells:
        if bool((_cells[stored_name] as Dictionary)["drawn"]):
            drawn += 1
    var picture := _picture_size()
    return {
        "drawn": drawn,
        "pending": _pictures.waiting(),
        "building": _waiting.size(),
        "cell": [int(picture.x), int(picture.y)] if not _order.is_empty() else [],
    }


## Moves the mark to *marked*, "" for none, by building again the two cells it
## leaves and reaches in their places. A cell still to be built takes the mark
## when it is, and every other cell is left as it stands.
func mark(marked: String) -> void:
    if marked == _marked:
        return
    var was := _marked
    _marked = marked
    for stored_name: String in [was, marked]:
        if not _cells.has(stored_name):
            continue
        _let_go((_cells[stored_name] as Dictionary)["box"])
        _cells.erase(stored_name)
        _stand_in(stored_name, _place[stored_name])
        _build(stored_name)


## Scrolls the scroll the grid sits in until the cell of *stored_name*, or the
## stand-in where it will be built, is inside its visible area, and answers
## whether there was one to scroll to. Asked a frame after the grid was laid
## out, since a scroll reads a control's place off its last layout.
func bring_into_view(stored_name: String) -> bool:
    var scroll := _scroll()
    var node: Control = _cells[stored_name]["box"] if _cells.has(stored_name) else _stand_ins.get(stored_name)
    if scroll == null or node == null:
        return false
    scroll.ensure_control_visible(node)
    return true


## Moves the cell of *stored_name* to *at* and gives it its star again, since
## `SaBrushPresetStars.begin_build` forgot every star the grid carried and the
## preset may have been starred meanwhile.
##
## **A kept cell enters the grid again**, because what a host puts on a cell it
## puts on as the cell enters: the docker's engine line, its dim and its tooltip,
## off the grid's `child_entered_tree`. A preset saved over as an eraser or an
## engine taken up since has to reach a kept cell the way it reaches a new one.
func _keep(stored_name: String, at: int) -> void:
    var cell: Dictionary = _cells[stored_name]
    var button: Button = cell["button"]
    var star := button.get_node_or_null("Star")
    if star != null:
        _let_go(star)
    _stars.add_to(button, stored_name)
    (cell["label"] as Label).custom_minimum_size = name_floor
    var box: Control = cell["box"]
    grid.remove_child(box)
    grid.add_child(box)
    grid.move_child(box, at)


## A control of a cell's size where the cell of *stored_name* will be, so the
## grid keeps its rows and its scroll while the cells arrive.
func _stand_in(stored_name: String, at: int) -> void:
    var stand_in: Control = _stand_ins.get(stored_name)
    if stand_in == null:
        stand_in = Control.new()
        stand_in.name = "Waiting_" + stored_name.validate_node_name()
        # A right press on it is the chooser's, which opens New preset... alone.
        stand_in.mouse_filter = Control.MOUSE_FILTER_PASS
        _stand_ins[stored_name] = stand_in
        grid.add_child(stand_in)
    stand_in.custom_minimum_size = _stand_in_size()
    grid.move_child(stand_in, at)


## The next name to build: the first waiting in *sight*, the grid's places from
## `x` up to `y`, or the first waiting at all.
func _take_next(sight: Vector2i) -> String:
    var taken := 0
    for i in _waiting.size():
        var at: int = _place[_waiting[i]]
        if at >= sight.x and at < sight.y:
            taken = i
            break
    var stored_name: String = _waiting[taken]
    _waiting.remove_at(taken)
    return stored_name


## The places of the cells the painter can see in the scroll the grid sits in,
## the first and one past the last. Every place when there is no scroll to ask
## or it has no height yet, so the queue keeps the grid's order.
func _in_sight() -> Vector2i:
    var every := Vector2i(0, _order.size())
    var scroll := _scroll()
    var pitch := _stand_in_size().y + float(grid.get_theme_constant("v_separation"))
    if scroll == null or scroll.size.y <= 0.0 or pitch <= 0.0 or not grid.is_inside_tree():
        return every
    var top := scroll.get_global_rect().position.y - grid.get_global_rect().position.y
    var first := maxi(0, floori(top / pitch))
    var last := ceili((top + scroll.size.y) / pitch)
    var columns := maxi(1, grid.columns)
    return Vector2i(first * columns, mini(_order.size(), last * columns))


func _scroll() -> ScrollContainer:
    var above := grid.get_parent()
    while above != null and not (above is ScrollContainer):
        above = above.get_parent()
    return above as ScrollContainer


## One cell: a button carrying the picture, with the name under it, put in the
## grid at its place in place of its stand-in.
func _build(stored_name: String) -> void:
    var box := SaMake.column(null, "Cell_" + stored_name.validate_node_name(), 2)
    # **The cell takes the slack, and the name spends it**. A `GridContainer`
    # hands its spare width to the columns whose children ask to expand, and at
    # the slider's floor a docker has plenty: six cells of thirty in a docker of
    # three hundred leave more room unused than the pictures take. Expanding is
    # free of the ratchet a minimum size makes, because a flag is not one, and
    # `_columns_that_fit` counts minimums.
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.set_meta(SaBrushPresetsChooser.PRESET_META, stored_name)
    _make_tile_answer(box, stored_name)

    var button := SaMake.button(box, "Icon", "", stored_name)
    button.custom_minimum_size = _picture_size()
    button.expand_icon = true
    # **Bounded by the cell and by nothing else** (d24). The theme's icon cap, `BASE_ICON_SIZE` on
    # every `Button`, holds an expanded icon too and drew a cell's picture 20 pixels wide at its
    # edge, so the cell lifts it for itself (0 is Godot's no cap) and centres what it fits.
    button.add_theme_constant_override("icon_max_width", 0)
    button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
    # Shrunk rather than filling what the cell was given, so the slack reaches the name and never
    # the picture: a stretched thumbnail is a different brush.
    button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    button.pressed.connect(_chosen.bind(stored_name))
    button.gui_input.connect(_on_cell_gui_input.bind(stored_name, button))
    button.mouse_entered.connect(_on_tile_hover.bind(stored_name, true))
    button.mouse_exited.connect(_on_tile_hover.bind(stored_name, false))
    box.gui_input.connect(_on_tile_gui_input.bind(stored_name, button, box))
    _stars.add_to(button, stored_name)

    var label := SaMake.label(box, "Name", stored_name)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    # **The name wraps between words and nowhere else**. The smart wrap broke a
    # word wider than its column, so the factory docker read "Airbr / ush" and
    # "Char / coal". The column is as wide as the widest word in the grid,
    # `name_width`, so the plain word wrap always has a boundary to break at and
    # a two word name takes the two lines `NAME_LINES` makes room for.
    #
    # **Autowrap is still what keeps the whole name out of the cell's width**. A
    # wrapping `Label` asks for one pixel, and `custom_minimum_size` raises that
    # to the column, a number taken from the names and the font and never from
    # the host, so the grid asks for what its columns were counted against and
    # there is nothing for the chooser's column ratchet to turn.
    label.autowrap_mode = TextServer.AUTOWRAP_WORD
    label.max_lines_visible = SaBrushPresetsChooser.NAME_LINES
    label.text_overrun_behavior = SaTheme.TEXT_CUT
    # The stand-in leaves the grid before the cell joins it, so the cell's place
    # is the stand-in's and nothing else holds its name.
    var at := grid.get_child_count()
    var stand_in: Control = _stand_ins.get(stored_name)
    if stand_in != null:
        at = stand_in.get_index()
        _stand_ins.erase(stored_name)
        _let_go(stand_in)
    grid.add_child(box)
    grid.move_child(box, at)
    # After the tree, because the height of two lines is the height of two lines
    # of the theme's font, and a Label outside a tree has no theme to ask.
    label.custom_minimum_size = name_floor
    var marked := stored_name == _marked
    if marked:
        SaBrushPresetsChooser.draw_mark(button, label)
    var cell := {"box": box, "button": button, "label": label, "drawn": false, "marked": marked}
    _cells[stored_name] = cell
    # A picture still to be drawn arrives by `_show_drawn`, and one drawn before
    # its cell was built is on disk by now.
    if not SaPresetThumbs.is_stale(_store.dir, stored_name, _tip):
        cell["drawn"] = SaBrushPresetsChooser.show_picture(button, SaPresetThumbs.path_for(_store.dir, stored_name, _tip))


## The size a cell's picture is shown at, in pixels: two to one for the stroke,
## the shape a thumbnail is rendered at, so a cell frames the picture rather
## than boxing it, and square for the tip, because a dab is.
func _picture_size() -> Vector2:
    # `@warning_ignore` because the halving is meant to discard the odd pixel: a
    # 45 by 22 cell and a 45 by 22.5 one are the same cell.
    @warning_ignore("integer_division")
    var down := _icon if _tip else _icon / 2
    return Vector2(float(SaUI.px(_icon)), float(SaUI.px(down)))


## The size a cell asks for before the docker gives it an engine line: the name's
## column across, and the picture, the column's gap and the name down.
func _stand_in_size() -> Vector2:
    var picture := _picture_size()
    return Vector2(maxf(picture.x, name_floor.x), picture.y + float(SaUI.px(2)) + name_floor.y)


## Every picture the grid lists that is missing or older than its preset, queued
## to be drawn.
func _queue_pictures(painter: Script, painters: Dictionary) -> void:
    var stale: Array[String] = []
    for stored_name: String in _order:
        if SaPresetThumbs.is_stale(_store.dir, stored_name, _tip):
            stale.append(stored_name)
    _pictures.queue(stale, _store, painter, painters, _tip, grid.queue_redraw)


## A picture is drawn and kept at *path*. A cell not built yet reads it off disk
## when it is.
func _show_drawn(stored_name: String, path: String) -> void:
    if not _cells.has(stored_name):
        return
    var cell: Dictionary = _cells[stored_name]
    if SaBrushPresetsChooser.show_picture(cell["button"] as Button, path):
        cell["drawn"] = true


## Removed before it is freed. `queue_free` alone leaves the old cells in the
## grid until the end of the frame, so the grid's minimum width is the old cells
## and the new ones together, and the width the columns are counted against is a
## width nothing will ever be drawn at.
func _let_go(node: Node) -> void:
    node.get_parent().remove_child(node)
    node.queue_free()


func _let_go_of_every_cell() -> void:
    for stored_name: String in _cells:
        _let_go((_cells[stored_name] as Dictionary)["box"])
    for stored_name: String in _stand_ins:
        _let_go(_stand_ins[stored_name])
    _cells.clear()
    _stand_ins.clear()
    _hovered = ""


## Makes the whole tile a target: the column takes a press over its name, over the
## engine line the docker adds and over the gap between them, and draws the hover
## plate the picture's button does not reach.
##
## **`PASS` and not `STOP`**, which is the filter a container has. A press the
## tile answers is accepted by its handler, so it goes no further, and the wheel
## the handler leaves alone still reaches the scroll the docker puts this grid in.
## The name and the engine line are labels, which let the mouse through, so the
## column is what a press on either of them lands on.
func _make_tile_answer(box: Control, stored_name: String) -> void:
    box.mouse_filter = Control.MOUSE_FILTER_PASS
    box.mouse_entered.connect(_on_tile_hover.bind(stored_name, true))
    box.mouse_exited.connect(_on_tile_hover.bind(stored_name, false))
    box.draw.connect(_draw_tile_hover.bind(box, stored_name))


## A press on a cell's picture that is not the left one. The right press opens
## the tag menu for that preset, which is where a painter's hand is at the moment
## they decide a brush belongs somewhere.
##
## On the cell's own button rather than on the grid, so the preset the menu
## belongs to is the one the press was over and nothing counts positions. The
## menu opens at the pointer, the press measured by `SaPopupRect.at_press`, as
## every right-click menu does.
func _on_cell_gui_input(event: InputEvent, stored_name: String, button: Button) -> void:
    var press := event as InputEventMouseButton
    if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_RIGHT:
        return
    _menu.call(stored_name, button, SaPopupRect.at_press(press, button))
    button.accept_event()


## A press on the tile outside its picture, which is the name, the engine line
## and the gap between them. The picture's button is a control of its own and
## takes its own presses, so nothing here is answered twice.
##
## The left press picks on its release, as the picture's button does, and only
## when the pointer let go on the tile no further than [constant
## SaDragScroll.DRAG_THRESHOLD] from where it pressed. A press and drag scrolls
## the docker with the tile under the pointer, so the release lands on the tile
## it pressed and the travel is what says it was a scroll and not a pick. The
## right press opens the tag menu at the pointer, as a press on the picture
## opens it, and the wheel and everything else is left to the scroll above.
func _on_tile_gui_input(event: InputEvent, stored_name: String, button: Button, box: Control) -> void:
    var press := event as InputEventMouseButton
    if press == null:
        return
    if press.button_index == MOUSE_BUTTON_LEFT and not press.pressed:
        var still := (press.global_position - _left_press_at).length() < SaDragScroll.DRAG_THRESHOLD
        if _left_pressed == stored_name and still and Rect2(Vector2.ZERO, box.size).has_point(press.position):
            _chosen.call(stored_name)
        _left_pressed = ""
        return
    if not press.pressed:
        return
    if press.button_index == MOUSE_BUTTON_LEFT:
        _left_pressed = stored_name
        _left_press_at = press.global_position
    elif press.button_index == MOUSE_BUTTON_RIGHT:
        _menu.call(stored_name, button, SaPopupRect.at_press(press, box))
    else:
        return
    button.accept_event()


## The pointer came onto or left a tile's box or its picture.
##
## Both are asked, because the box is told it has been left when the pointer
## moves onto the picture above it and is never told again when the pointer
## leaves the picture for the outside. So a leave settles by where the pointer is
## and not by which control said so, and only an enter names the tile outright.
func _on_tile_hover(stored_name: String, entered: bool) -> void:
    var cell: Variant = _cells.get(stored_name)
    if cell == null:
        return
    var box: Control = (cell as Dictionary)["box"]
    if entered:
        _hovered = stored_name
    elif _hovered == stored_name and not box.get_global_rect().has_point(box.get_global_mouse_position()):
        _hovered = ""
    box.queue_redraw()


## The plate under the tile the pointer is over, in the palette's button hover, so
## the tile reads as one control from the top of its picture to the foot of its
## name. Drawn by the column before its children, so the picture's own hover lands
## on it and the same colour does not show twice.
func _draw_tile_hover(box: Control, stored_name: String) -> void:
    if _hovered == stored_name:
        box.draw_rect(Rect2(Vector2.ZERO, box.size), SaTheme.palette.button_hover)
