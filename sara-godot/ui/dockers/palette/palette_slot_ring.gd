## The pop-up palette's face: the ten brush slots on a ring, and the colour
## wheel in the middle of it.
##
## The ring is the ten slots and nothing else, so the palette and the ten
## Ctrl+Alt chords are one list: a cell asks `SaBrushSlotCommands.preset_for`
## what it holds and a press calls the same select a chord does. Krita's palette
## keeps a list of its own, filled by a tag, and Sara does not: a painter who
## set up their ten brushes would have to do it twice.
##
## The wheel is the colour docker's own shape, `SaPickerShape`, taken whole
## rather than drawn again, so a colour picked here moves the same store the
## docker and the title bar's pair follow. It takes the shape the docker shows,
## `SaSettings.color_picker_shape`, when it is built and whenever the setting
## changes, the palette open or not, so the two show one shape. A shape with a
## bar beside it,
## the OKHSL disc and the HSL square, is drawn smaller, so its frame and its
## bar stay clear of every slot, see [method _wheel_side].
##
## **The slot holding the preset in use is marked**, with the grid's own mark,
## `SaBrushPresetsChooser.draw_mark`, so a painter summoning the ring to change
## brush sees what they are changing from as well as what is in reach. The
## ring hears a load
## and a save on the bus itself, the one piece of wiring it keeps, because the
## mark is drawn here and a ring a suite builds without its docker moves it too.
##
## **Each name is shown whole**, because a name cut to "Charc" or "Airbru"
## reads as a typo. A name wraps to two lines at its cell's width, and the
## ring's text steps down
## from the interface's size, no lower than [constant NAME_FLOOR] of it, to the
## size at which the most names fit, measured against the font. One size for
## the ten rather than a size each, because the factory ten sized one by one
## come out at six sizes from 13 pixels to 20, which reads as six kinds of
## button. A name that fits at no size is cut on one line and leaves the others
## at the size they fit, and the line under the wheel shows the hovered slot's
## name whole at the largest size its strip takes.
##
## Its own file beside the docker because the geometry is most of it, and the
## docker is the window and the wiring around it.
class_name PaletteSlotRing
extends Control

## A cell's width and height and the wheel's side, as fractions of the ring's
## shorter side. Chosen together: the ten cells sit at 36 degree steps from
## the top pair, which leaves the two nearest cells of any pair apart at these
## sizes, and the wheel reaches as close to the inner corners as it can
## without touching one.
##
## The height is what holds a name on two lines. It was 0.09, one line at the
## interface's size. The cell beside a pair sits 0.14 of the side lower than
## the pair's own, so a cell grows no taller than 0.133 and keeps a gap of three
## pixels to it at the docker's default size, where the ring's shorter side is
## 331 and two lines fit at 14 pixels.
const CELL_WIDTH: float = 0.22
const CELL_HEIGHT: float = 0.133
const WHEEL_SIDE: float = 0.48

## The gap kept between a shape with a bar and the nearest cell, in the
## interface's pixels, so the bar does not sit flush against a slot's edge.
const WHEEL_CLEARANCE: int = 4

## The most lines a slot's name is wrapped to.
const NAME_LINES: int = 2

## The smallest a slot's name is drawn at, as a fraction of the interface's
## text size: the Info docker's rows', the smallest text a docker draws. Every
## shipped preset's name fits its cell at it or above at the docker's default
## size, which `test_the_palettes_slots_show_each_name` measures, and the
## longest, "Splattered Block", fits at it and not a pixel larger.
const NAME_FLOOR: float = 0.65

## Where slot one sits, in degrees clockwise from the right, which is the upper
## left of the pair at the top. The slots then run clockwise like a dial, and
## no cell sits alone on the vertical axis, where two neighbours would overlap.
const FIRST_ANGLE: float = -108.0

## The ten cells in slot order, slot one first. A cell that loses the mark is
## built again in its place, so a reader takes a cell from here each time rather
## than keeping one.
var cells: Array[Button] = []

## The colour wheel at the centre.
var wheel: SaPickerShape

## The name of the slot under the pointer, whole, in the strip between the
## wheel and the bottom pair. Empty while no filled slot is under it.
var name_line: Label

## What a press calls with the slot number, `SaBrushSlotCommands.select` in the
## app. A constructor argument so a suite can hear the press without a tool
## options bar to load a preset into.
var _select: Callable

## What answers the name of the preset in use, the empty string for none. A
## constructor argument for the reason *select* is one, so a suite can say what
## is loaded without a tool options bar. The app's ring is handed none and asks
## the bar, through the same door the chord's select loads through.
var _loaded: Callable

## The slots whose cell carries the mark, slot one as 1, so `refresh` knows
## which cell to build again when the mark leaves it. Written by `refresh` alone.
var _marked: Array[int] = []

## The slots whose name does not fit its cell at the size the ring chose and
## is cut, slot one as 1, for the state dump. Written by `_fit` alone.
var _cut: Array[int] = []

## The slot under the pointer, slot one as 1, or 0 for none.
var _hovered: int = 0

## A cell's size and the strip under the wheel, as `lay_out` last placed them. Kept rather than read back off the controls,
## because a control grows to the least size its text needs and a name fitted
## against a cell its own text had grown would always fit. Written by `lay_out`.
##
## **The cell is whole pixels, and so is where it stands.** The line breaker
## keeps a line whole when it is a fraction of a pixel wider than its width,
## and the cell then cuts it: "Bristle Flat" at 13 pixels was one line of 65 in
## a cell 64.82 wide, cut, where at 14 it broke into two lines and fit. A cell
## at a fractional place came back 43.99998 tall for a size of 44, which two
## lines of 18 then overran.
var _cell_size := Vector2.ZERO
var _name_strip := Rect2()

## The part of the wheel the gesture under way moves, which is how the usage
## tally counts the colour the gesture ends on.
var _wheel_part: StringName = &""


func _init(select: Callable, loaded: Callable = Callable()) -> void:
    name = "SlotRing"
    _select = select
    _loaded = loaded
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    mouse_filter = Control.MOUSE_FILTER_PASS

    wheel = SaPickerShape.new()
    wheel.name = "Wheel"
    add_child(wheel)
    _follow_shape()
    wheel.color_changed.connect(_on_wheel_moved)
    wheel.color_committed.connect(_on_wheel_chosen)

    for slot in range(1, SaBrushSlotCommands.COUNT + 1):
        cells.append(_build_cell(slot))

    name_line = SaMake.label(self, "NameLine")
    name_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    name_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    name_line.clip_text = true
    name_line.text_overrun_behavior = SaTheme.TEXT_CUT
    name_line.mouse_filter = Control.MOUSE_FILTER_IGNORE

    resized.connect(lay_out)
    SaSettings.changed.connect(_on_setting_changed)
    SaSettings.profile_changed.connect(_follow_shape)
    EventBus.preset_loaded.connect(_on_preset_loaded)
    EventBus.preset_store_changed.connect(_on_preset_store_changed)
    refresh()


## Writes each cell's name from the slots, and marks the cell of the preset in
## use. An empty slot shows its key and is disabled, because pressing it would do
## nothing, and a dimmed cell that still answered a press would be the one
## control here that lied.
##
## Only a cell the mark leaves is built again. The cell the mark lands on is
## often the one just pressed, inside its own `pressed`, and is marked where it
## stands rather than freed under the press.
func refresh() -> void:
    var loaded := _loaded_name()
    var marked: Array[int] = []
    for i in cells.size():
        var slot := i + 1
        var preset := SaBrushSlotCommands.preset_for(slot)
        var wanted := not preset.is_empty() and preset == loaded
        if _marked.has(slot) and not wanted:
            _rebuild_cell(i)
        var key := "%d" % (slot % 10)
        var cell := cells[i]
        cell.disabled = preset.is_empty()
        if preset.is_empty():
            cell.text = key
            cell.tooltip_text = tr("Slot %s is empty. Fill it in Preferences > Brushes.") % key
        else:
            cell.text = preset
            cell.tooltip_text = tr("Slot %s holds %s.") % [key, preset]
        if wanted:
            if not _marked.has(slot):
                SaBrushPresetsChooser.draw_mark(cell)
            marked.append(slot)
    _marked = marked
    _fit()
    _show_hovered()


## Puts the wheel in the middle and the cells around it, from the ring's size.
## Public because a suite lays out a ring that is in no tree.
func lay_out() -> void:
    var side := minf(size.x, size.y)
    var centre := size / 2.0
    _cell_size = Vector2(side * CELL_WIDTH, side * CELL_HEIGHT).round()
    var radius := side / 2.0 - _cell_size.x / 2.0
    for i in cells.size():
        var at := centre + Vector2.from_angle(deg_to_rad(FIRST_ANGLE + 36.0 * i)) * radius
        cells[i].position = (at - _cell_size / 2.0).round()
    var wheel_side := _wheel_side(side * WHEEL_SIDE, centre)
    wheel.position = (centre - Vector2(wheel_side, wheel_side) / 2.0).round()
    wheel.size = Vector2(wheel_side, wheel_side)
    var below := wheel.position.y + wheel.size.y
    var bottom_pair := size.y
    for cell in cells:
        var middle := cell.position.x + _cell_size.x / 2.0
        if cell.position.y >= below and absf(middle - centre.x) < wheel_side / 2.0:
            bottom_pair = minf(bottom_pair, cell.position.y)
    _name_strip = _strip(below, bottom_pair)
    _fit()
    _show_hovered()


## The wheel's side, *most* when its shape has no bar. The round wheel and the
## triangles draw inside a circle, which clears the inner corners of the cells
## at *most*, but a shape with a bar fills a rectangle as wide as the side and
## as tall as the side less the bar, and that rectangle's corners reach into
## the four slanted cells. Such a side steps down a pixel at a time until the
## rectangle, with [constant WHEEL_CLEARANCE] of the interface's pixels
## around it, touches no cell.
func _wheel_side(most: float, centre: Vector2) -> float:
    var bar := wheel.bar_width()
    if bar <= 0.0:
        return most
    var clearance := float(SaUI.px(WHEEL_CLEARANCE))
    var wheel_side := floorf(most)
    while wheel_side > bar + 1.0:
        var held := Vector2(wheel_side, wheel_side - bar) + Vector2.ONE * clearance * 2.0
        var box := Rect2(centre - held / 2.0, held)
        var clear := true
        for cell in cells:
            if box.intersects(Rect2(cell.position, _cell_size)):
                clear = false
                break
        if clear:
            break
        wheel_side -= 1.0
    return wheel_side


## Puts the wheel into the shape the docker shows. Lays the ring out again,
## because a shape with a bar takes a smaller side than one without.
func _follow_shape() -> void:
    var wanted := SaPickerShape.kind_of(SaSettings.color_picker_shape)
    if wanted == wheel.kind:
        return
    wheel.set_kind(wanted)
    if _cell_size != Vector2.ZERO:
        lay_out()


func _on_setting_changed(property: StringName) -> void:
    if property == &"color_picker_shape":
        _follow_shape()


## Whether *text* fits *box* at *font_size* on at most *lines* lines, broken
## at spaces the way a cell breaks it. A word wider than the box does not fit,
## because a cell never breaks inside one.
static func _fits(text: String, font: Font, font_size: int, box: Vector2, lines: int) -> bool:
    if box.x <= 0.0 or box.y <= 0.0:
        return false
    var paragraph := TextParagraph.new()
    paragraph.add_string(text, font, font_size)
    paragraph.width = box.x
    paragraph.break_flags = (TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_TRIM_END_EDGE_SPACES)
    if paragraph.get_line_count() > lines:
        return false
    for line in paragraph.get_line_count():
        if paragraph.get_line_width(line) > box.x:
            return false
    return paragraph.get_size().y <= box.y


## Where each cell and the wheel are, and the shape the wheel shows with its
## frame and its bar, for the state dump: a scenario presses a cell or a hue by
## these. *offset* is where the docker's own viewport starts
## in the space a scenario's press is measured in.
func report(offset: Vector2) -> Dictionary:
    var slots: Array = []
    for i in cells.size():
        var cell := cells[i]
        (
            slots
            . append(
                {
                    "slot": i + 1,
                    "text": cell.text,
                    "disabled": cell.disabled,
                    "marked": _marked.has(i + 1),
                    "cut": _cut.has(i + 1),
                    "font_size": cell.get_theme_font_size("font_size"),
                    "rect": _rect(cell.get_global_rect(), offset),
                }
            )
        )
    return {
        "slots": slots,
        "wheel": _rect(wheel.get_global_rect(), offset),
        "shape": wheel.kind_key(),
        "frame": _rect(wheel.frame.get_global_rect(), offset),
        "bar": _bar(offset),
        "ring": _rect(get_global_rect(), offset),
        "name_line": _line(name_line, offset),
    }


## The rectangle of the bar the shape carries beside its frame, or an empty
## list for a shape with none.
func _bar(offset: Vector2) -> Array:
    for bar: Control in [wheel.lightness_bar, wheel.hue_bar]:
        if bar.visible:
            return _rect(bar.get_global_rect(), offset)
    return []


static func _line(label: Label, offset: Vector2) -> Dictionary:
    return {
        "text": label.text,
        "visible": label.visible,
        "font_size": label.get_theme_font_size("font_size"),
        "rect": _rect(label.get_global_rect(), offset),
    }


static func _rect(r: Rect2, offset: Vector2) -> Array:
    return [roundi(r.position.x + offset.x), roundi(r.position.y + offset.y), roundi(r.size.x), roundi(r.size.y)]


## The wheel's gesture moved the colour, and which part moved it, counted as
## the colour docker's `SaColorPicker._part_moving` counts it: the ring or the
## hue bar that does its job beside the HSL square, the area, or the disc's
## lightness bar. Asked while the colour moves, because the wheel lets go of
## the part before it says the colour was chosen.
func _on_wheel_moved(_moved: Color) -> void:
    _wheel_part = wheel.part_moving()


func _on_wheel_chosen(_chosen: Color) -> void:
    SaUsageTally.color_set(_wheel_part)


## A press on a cell is a preset picked in the palette, which the usage tally
## counts whether or not the slot's preset loads.
func _on_cell_pressed(slot: int) -> void:
    SaUsageTally.preset_picked(SaUsageTally.PALETTE)
    if _select.is_valid():
        _select.call(slot)


## One cell, a button that presses its slot. It cuts its name on one line
## with the mark until `_fit` finds the name a size it fits at and wraps it.
func _build_cell(slot: int) -> Button:
    var cell := SaMake.button(self, "Slot%d" % slot)
    # A summoned docker takes no keyboard, and a button that grabbed the
    # focus on a press would take it back from the canvas.
    cell.focus_mode = Control.FOCUS_NONE
    cell.clip_text = true
    cell.text_overrun_behavior = SaTheme.TEXT_CUT
    cell.pressed.connect(_on_cell_pressed.bind(slot))
    cell.mouse_entered.connect(_on_cell_entered.bind(slot))
    cell.mouse_exited.connect(_on_cell_exited.bind(slot))
    return cell


## Puts a new cell where the one at *index* stands, at its place among the
## children and on its rectangle, because the mark it carries cannot be taken
## off it. Removed before it is freed, so its name is free for the new one.
func _rebuild_cell(index: int) -> void:
    var old := cells[index]
    var at := old.get_index()
    remove_child(old)
    old.queue_free()
    var cell := _build_cell(index + 1)
    move_child(cell, at)
    cell.position = old.position
    cell.size = old.size
    cells[index] = cell


## The preset in use, from the source this ring was handed or else from the bar.
func _loaded_name() -> String:
    if _loaded.is_valid():
        return String(_loaded.call())
    var presets := SaBrushSlotCommands.preset_box()
    return presets.selected_preset if presets != null else ""


## Sizes the ten names: the size from the interface's own down to the floor at
## which the most names fit their cells, on at most [constant NAME_LINES] lines,
## and the largest of those. A name that fits nowhere is cut on one line at that
## size, so one long name a painter gave a preset does not shrink the other
## nine for nothing.
##
## The size is written as the theme pass's fraction as well as the size, so
## the docker's pass on a theme or font change keeps it rather than putting the
## interface's size back, and the ring sizes again on the theme change itself.
## Each cell is put back to its size after, since a cell the larger text grew
## does not shrink by itself.
func _fit() -> void:
    if _cell_size.x <= 0.0 or _cell_size.y <= 0.0:
        return
    var font := cells[0].get_theme_font("font")
    var chosen := 0
    var fitting: Array[Button] = []
    for font_size in range(SaUI.get_font_size(), _scaled(NAME_FLOOR) - 1, -1):
        var here: Array[Button] = []
        for cell in cells:
            if _fits(cell.text, font, font_size, _text_box(cell), NAME_LINES):
                here.append(cell)
        if chosen == 0 or here.size() > fitting.size():
            chosen = font_size
            fitting = here
    var cut: Array[int] = []
    for i in cells.size():
        var cell := cells[i]
        var whole := fitting.has(cell)
        cell.autowrap_mode = TextServer.AUTOWRAP_WORD if whole else TextServer.AUTOWRAP_OFF
        _size_text(cell, chosen)
        cell.size = _cell_size
        if not whole:
            cut.append(i + 1)
    _cut = cut


## Writes the hovered slot's name into the line under the wheel, at the
## largest size from the interface's own down to the floor that its strip
## takes on one line.
func _show_hovered() -> void:
    var preset := SaBrushSlotCommands.preset_for(_hovered) if _hovered > 0 else ""
    name_line.text = preset
    if not preset.is_empty():
        var font := name_line.get_theme_font("font")
        var chosen := _scaled(NAME_FLOOR)
        for font_size in range(SaUI.get_font_size(), chosen, -1):
            if _fits(preset, font, font_size, _name_strip.size, 1):
                chosen = font_size
                break
        _size_text(name_line, chosen)
    _place(name_line, _name_strip)


## Where a cell's text is drawn: the cell's size less its box's margins.
func _text_box(cell: Button) -> Vector2:
    var box := cell.get_theme_stylebox("normal")
    return _cell_size - (box.get_minimum_size() if box != null else Vector2.ZERO)


## *control*'s text at *font_size*, as an override and as the theme pass's
## fraction of the interface's size, so the pass writes the same size back.
static func _size_text(control: Control, font_size: int) -> void:
    control.set_meta(SaUI.FONT_SCALE_META, float(font_size) / float(SaUI.get_font_size()))
    control.add_theme_font_size_override("font_size", font_size)


## The interface's text size times *fraction*, in whole pixels.
static func _scaled(fraction: float) -> int:
    return maxi(1, roundi(float(SaUI.get_font_size()) * fraction))


## The widest strip between *top* and *bottom* that no cell reaches into,
## bounded by the nearest cell on each side of the middle.
func _strip(top: float, bottom: float) -> Rect2:
    var middle := size.x / 2.0
    var left := 0.0
    var right := size.x
    for cell in cells:
        if cell.position.y + _cell_size.y <= top or cell.position.y >= bottom:
            continue
        if cell.position.x + _cell_size.x / 2.0 < middle:
            left = maxf(left, cell.position.x + _cell_size.x)
        else:
            right = minf(right, cell.position.x)
    return Rect2(left, top, maxf(0.0, right - left), maxf(0.0, bottom - top))


static func _place(control: Control, rect: Rect2) -> void:
    control.position = rect.position
    control.size = rect.size


func _notification(what: int) -> void:
    if what == NOTIFICATION_THEME_CHANGED and not cells.is_empty():
        _fit()
        _show_hovered()


func _on_cell_entered(slot: int) -> void:
    _hovered = slot
    _show_hovered()


## Only the slot the line shows empties it, because the pointer can enter the
## next cell before it leaves the last.
func _on_cell_exited(slot: int) -> void:
    if _hovered == slot:
        _hovered = 0
        _show_hovered()


func _on_preset_loaded(_preset_name: String) -> void:
    refresh()


## A save puts the brush on the preset it wrote and a delete takes it off, so
## either can move the mark without a load.
func _on_preset_store_changed(_preset_name: String, _saved: bool) -> void:
    refresh()
