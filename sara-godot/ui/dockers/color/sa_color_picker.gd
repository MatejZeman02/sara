## The colour docker's contents: a picker shape, the pair, the kept swatches,
## the recent colours, a hex box and two rows of numbers.
##
## A choice of shape, [SaPickerShape], with Sara's own ok-hsl, a triangle and
## a wheel, rather than Godot's own `ColorPicker`, which is wider and taller
## than the docker's default size, pushes the rows under it past the bottom
## edge, and draws Godot's typography rather than Sara's.
##
## It shows the colour pair, the kept swatches and the recent colours, and
## owns none of them: `color` and `background` are set from outside, the lists
## are handed in, and every choice goes out as a signal. [SaColorPickerView]
## wires it to `SaColors`, which is the one store behind all three.
##
## A row that is more than a control and a signal is a class beside this one:
## [SaPaletteRow] owns the kept swatches, their four buttons and the `.gpl` file
## round trip, the way [SaPickerSliders] owns a row of numbers, [SaExposureRow]
## the paint exposure and [SaPickerShape] the area. This file lays the rows out, shows the colour
## and passes the choices on under the signal names the wiring already knew.
##
## **The wheel is square at the column's width**, capped by the height the
## other shown rows leave and never under [constant WHEEL_MIN], and [method
## wheel_side] is the rule. The Default layout shows the shape and the pair
## alone. Every
## other row is a switch on the docker's element list, and a fresh profile hides
## the same five.
##
## **A press on a swatch picks which of the pair the picker edits.** The wheel,
## the sliders, the hex box and the chips all write the swatch with the green
## rim, and a foreground edit goes out as `color_changed` and a background one
## as `background_changed`. The eyedropper still sets the foreground, because
## it comes in through `color` from the bus rather than through the picker.
##
## **`color` is the foreground's colour part** and the exposure row its stops.
## The swatch and what is kept or noted get the colour painted, and a chip, a
## whole colour, goes out as `foreground_picked` too.
extends VBoxContainer

class_name SaColorPicker

signal color_changed(color: Color)
## The background swatch is the one being edited and the painter moved it. The
## docker hands it to `SaColors.background`.
signal background_changed(color: Color)
## A gesture on the wheel ended, or a hex code was entered: the colour was
## chosen rather than passed through, which is what the recent list records.
signal color_committed(color: Color)
signal reset_requested
## The swap button was pressed, which is X's job done by a press.
signal swap_requested
signal swatch_add_requested(color: Color)
## Remove was chosen from a kept chip's menu. The index alone, because the
## store remembers the colour and the name for Undo remove itself.
signal swatch_remove_requested(index: int)
## A kept chip's Rename was applied. *called* may be empty, which unnames it.
signal swatch_rename_requested(index: int, called: String)
## Undo remove was chosen from the swatch strip's menu.
signal swatch_undo_remove_requested
## A palette file was opened and these colours are to be kept after the swatches
## already there, under the names the file gave them. The store's
## `add_swatches` is what hears it.
signal swatches_add_requested(colors: Array, names: Array)
## The kept swatches are to go, because Clear was confirmed or because a load
## was answered Replace. The store's `clear_swatches` is what hears it, and a
## replace sends this before `swatches_add_requested` rather than instead.
signal swatches_clear_requested
signal exposure_changed(stops: float)
## A chip named the whole foreground, ahead of the `color_changed` it sends.
signal foreground_picked(color: Color)

const SaPickerShapeScript = preload("res://ui/widgets/picker/sa_picker_shape.gd")
## The Preferences key of the switch that makes a ring turn keep the chroma.
const KEEP_CHROMA_KEY := "keep_chroma"

## A swatch or a recent colour is a square this big, logical units.
const CHIP_SIZE: int = 18

## The shape's minimum side, logical units.
const WHEEL_MIN: int = 120

var _color: Color = Color.BLACK
var _background: Color = Color.WHITE
## Whether the wheel, the sliders and the hex box edit the background rather
## than the foreground. A press on a swatch is the only thing that writes it.
var _editing_background: bool = false
## The wheel's side as [method _hold_wheel] last wrote it, so a sort that
## lands on the same side writes nothing.
var _wheel_side: float = 0.0
## The part of the shape the gesture under way moves, as [method _part_moving]
## read it, which is how the usage tally counts the colour the gesture ends on.
var _shape_part: StringName = &""

## The foreground colour. A write from outside moves its swatch, and the shape
## and the numbers while the foreground is what they edit, and the picker's own handlers write `_color` underneath because a
## colour that came out of the shape must not go back in: a round trip through
## OKHSV moves a channel by a few ulps, which the docker's equality check and
## any test would read as a different colour. Property syntax rather than a
## `set_color` and a `get_color` pair, which f16 removed, because this is the
## one door where the write has to do something the plain member cannot.
var color: Color:
    set(value):
        _adopt(value)
    get:
        return _color

## The background colour, the same way: the swatch follows a write from outside,
## and so does the shape while the background is what it edits. A write of the
## colour already held moves nothing, because the picker's own
## `background_changed` comes back here through the store and the bus, and a
## round trip through the shape would move the colour by a few ulps.
var background: Color:
    set(value):
        if _background.is_equal_approx(value):
            return
        _background = value
        _show(_editing_background)
    get:
        return _background

# Control components
var shape: SaPickerShape

var hex_row: HBoxContainer
var hex_input: LineEdit

## The pair: foreground on the left, background on the right, then the button
## X stands for and the one D stands for. A press on a swatch makes it the one
## the picker edits, and the green rim says which.
var preview_box: HBoxContainer
var foreground_swatch: Swatch
var background_swatch: Swatch
var swap_button: Button
var reset_button: Button

## The Swatches row: the kept colours as chips, and the four buttons that add,
## load, save and clear them. It owns the chips and the `.gpl` round trip in
## `sa_palette_row.gd`, and this file passes its choices on.
var palette_row: SaPaletteRow

var recent_box: HBoxContainer
var recent_flow: HFlowContainer

## The two numeric rows. `sa_picker_sliders.gd` holds what a row of numbers
## means, this file holds where it sits and who it talks to.
var rgb_sliders: SaPickerSliders
var okhsv_sliders: SaPickerSliders

## The seven shapes as a list, opened by a right press on the shape. A pick
## goes through [method set_shape_kind], so the Preferences row reads the same.
var shape_menu: SaShapeMenu

## The paint exposure in stops, under the shape by default.
var exposure_row: SaExposureRow


func _init() -> void:
    name = "SaColorPicker"
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_theme_constant_override("separation", DockerUtils.px(6))

    # 1. The picker shape: the hue ring and whatever is inside it. As tall as
    #   [method wheel_side] says and no taller, so the rows under it follow the
    #   wheel rather than the docker's bottom edge. [method _fit_wheel] sets the
    #   height before every sort, and WHEEL_MIN is the floor until it has.
    shape = SaPickerShapeScript.new()
    _hold_wheel(float(DockerUtils.px(WHEEL_MIN)))
    shape.size_flags_vertical = Control.SIZE_FILL
    shape.color_changed.connect(_on_shape_color_changed)
    shape.color_committed.connect(_on_shape_color_committed)
    add_child(shape)
    shape.frame.tooltip_text = tr("Right-click to change the shape.")
    for part: Control in [shape.frame, shape.hue_bar, shape.lightness_bar]:
        part.gui_input.connect(_on_shape_input.bind(part))
    shape_menu = SaShapeMenu.new()
    shape_menu.chosen.connect(_on_shape_menu_chosen)
    add_child(shape_menu)
    exposure_row = SaExposureRow.make()
    exposure_row.stops_changed.connect(_on_exposure_row_changed)
    add_child(exposure_row)

    # 2. Which shape it is lives in Preferences rather than on the docker.
    #   The row is a per-docker option on the Colour Picker page, registered
    #   below, and `SaSettings.color_picker_shape` is the one setting behind
    #   it. A
    #   right press on the shape opens the same choice as a list, which adds no
    #   row, so the Default layout keeps to the shape and the pair.

    # 3. The pair: foreground and background, with reset beside them.
    preview_box = SaMake.row(self, "SelectedColorPreview", SaTheme.GAP_TIGHT)
    preview_box.custom_minimum_size = Vector2(0, DockerUtils.px(24))

    foreground_swatch = Swatch.new(_color, true)
    foreground_swatch.name = "ForegroundSwatch"
    foreground_swatch.tooltip_text = tr("Foreground colour. Click to edit it on the wheel.")
    foreground_swatch.gui_input.connect(_on_swatch_input.bind(false))
    preview_box.add_child(foreground_swatch)

    background_swatch = Swatch.new(_background, false)
    background_swatch.name = "BackgroundSwatch"
    background_swatch.tooltip_text = tr("Background colour. Click to edit it on the wheel.")
    background_swatch.gui_input.connect(_on_swatch_input.bind(true))
    preview_box.add_child(background_swatch)

    swap_button = _small_button("swap", tr("Swap the two colours (X)"), swap_requested.emit)
    swap_button.name = "SwapButton"
    preview_box.add_child(swap_button)

    reset_button = _small_button("reset", tr("Reset to black and white (D)"), _on_reset_pressed)
    reset_button.name = "ResetButton"
    preview_box.add_child(reset_button)

    # 4. Swatches the painter kept, and 5. the colours last used. The kept row
    #   is its own class, and every choice it takes is passed on here under the
    #   picker's own signal names, which are what `sa_color_picker_view.gd`
    #   wires.
    palette_row = SaPaletteRow.new()
    palette_row.add_requested.connect(_on_add_swatch_pressed)
    palette_row.chip_picked.connect(_on_swatch_chip_picked)
    palette_row.chip_remove_requested.connect(swatch_remove_requested.emit)
    palette_row.chip_rename_requested.connect(swatch_rename_requested.emit)
    palette_row.undo_remove_requested.connect(swatch_undo_remove_requested.emit)
    palette_row.swatches_add_requested.connect(swatches_add_requested.emit)
    palette_row.swatches_clear_requested.connect(swatches_clear_requested.emit)
    add_child(palette_row)

    recent_box = SaMake.row(self, "RecentColours")
    recent_flow = HFlowContainer.new()
    recent_flow.name = "RecentFlow"
    recent_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    recent_flow.tooltip_text = tr("Recent colours, newest first.")
    recent_box.add_child(recent_flow)

    # 6. The hex box, after the chips rather than second, which is where the
    #   default order puts it.
    hex_row = SaMake.row(self, "HexRow", SaTheme.GAP)

    var hex_lbl := Label.new()
    hex_lbl.text = tr("Hex")
    hex_row.add_child(hex_lbl)

    hex_input = SaMake.line_edit(hex_row, "HexInput")
    hex_input.tooltip_text = tr(
        "The edited colour in hex: type six digits or three, with or without the #, and press Enter or click elsewhere."
    )
    hex_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    hex_input.text_submitted.connect(_on_hex_submitted)
    hex_input.focus_exited.connect(_on_hex_focus_exited)
    hex_input.gui_input.connect(_on_hex_gui_input)

    # 7 and 8. The numbers, one row per model. Both are rows of the layout list
    # like everything above, so either can be moved or hidden on its own.
    rgb_sliders = SaPickerSliders.make(SaPickerSliders.Model.RGB)
    okhsv_sliders = SaPickerSliders.make(SaPickerSliders.Model.OKHSV)
    for row: SaPickerSliders in [rgb_sliders, okhsv_sliders]:
        row.color_changed.connect(_on_sliders_color_changed)
        row.color_committed.connect(_on_sliders_color_committed)
        add_child(row)


## A square button beside the pair, drawn with an icon from `assets/icons/`.
## The two arrows were text once, and the default Inter has no glyph for the
## swap one, nor Atkinson Hyperlegible for either, so they drew a box.
func _small_button(icon_name: String, hint: String, on_pressed: Callable) -> Button:
    var button := Button.new()
    SaUI.set_button_icon(button, icon_name)
    button.tooltip_text = hint
    button.custom_minimum_size = Vector2(DockerUtils.px(24), DockerUtils.px(24))
    button.focus_mode = Control.FOCUS_NONE
    button.pressed.connect(on_pressed)
    return button


func _on_reset_pressed() -> void:
    reset_requested.emit()


func _on_add_swatch_pressed() -> void:
    swatch_add_requested.emit(_painted(_edited()))


## Shows *stops* on the exposure row and the swatch, without a signal.
func show_exposure(stops: float) -> void:
    exposure_row.show_stops(stops)
    _refresh_controls()


func _on_exposure_row_changed(stops: float) -> void:
    _refresh_controls()
    exposure_changed.emit(stops)


## *col* as the brush paints it, at the row's stops for the foreground.
func _painted(col: Color) -> Color:
    return col if _editing_background else exposure_row.painted(col)


## A left press on a swatch makes it the one the picker edits.
func _on_swatch_input(event: InputEvent, background_side: bool) -> void:
    var mb := event as InputEventMouseButton
    if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
        return
    edit_background(background_side)


## Makes the background the colour the wheel, the sliders and the hex box edit
## when *on*, and the foreground when not. The shape moves to the colour it now
## edits and nothing is emitted, because neither colour changed.
func edit_background(on: bool) -> void:
    _editing_background = on
    _show(true)


## The colour the picker edits, the foreground or the background.
func _edited() -> Color:
    return _background if _editing_background else _color


## Writes *col* into whichever colour is edited, and moves nothing else.
func _hold_edited(col: Color) -> void:
    if _editing_background:
        _background = col
    else:
        _color = col


## Says the edited colour changed, on the signal of the side it is.
func _emit_edited() -> void:
    if _editing_background:
        background_changed.emit(_background)
    else:
        color_changed.emit(_color)


## Hands the store's kept swatches and their names to the row that draws them,
## and whether the store has a removed one to give back.
func set_swatches(list: Array, names: Array = [], undo_offered: bool = false) -> void:
    palette_row.set_swatches(list, names, undo_offered)


## A kept chip was clicked, so the picker takes it as its colour and says it was
## chosen rather than passed through, which is what the recent list records.
func _on_swatch_chip_picked(chip_color: Color) -> void:
    _pick(chip_color, SaUsageTally.SWATCH)


## Rebuilds the recent chips, newest first. Left click picks the colour.
##
## No right press here and no removable flag: the kept row's chips are the ones
## that can be thrown away, and they are `sa_palette_row.gd`'s.
func set_recent(list: Array) -> void:
    for child in recent_flow.get_children():
        recent_flow.remove_child(child)
        child.queue_free()
    for i in list.size():
        var chip := ColorRect.new()
        chip.color = list[i]
        chip.custom_minimum_size = Vector2(DockerUtils.px(CHIP_SIZE), DockerUtils.px(CHIP_SIZE))
        chip.tooltip_text = "#" + chip.color.to_html(false)
        chip.gui_input.connect(_on_recent_chip_input.bind(i, chip.color))
        recent_flow.add_child(chip)


func _on_recent_chip_input(event: InputEvent, _index: int, chip_color: Color) -> void:
    var mb := event as InputEventMouseButton
    if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
        return
    _pick(chip_color, SaUsageTally.SWATCH)


func _ready() -> void:
    DockerUtils.style_all_controls(self)
    _refresh_controls()
    _register_shape_option()
    _register_keep_chroma_option()

    if not SaSettings.profile_changed.is_connected(apply_layout_settings):
        SaSettings.profile_changed.connect(apply_layout_settings)
    apply_layout_settings()

    # The root window, because it hears every press in the main window, the
    # canvas's included, whichever window the docker sits in at the time. A
    # suite calls `_ready` on a picker outside the tree, which has no root.
    var root := get_tree().root if is_inside_tree() else null
    if root != null and not root.window_input.is_connected(_on_root_window_input):
        root.window_input.connect(_on_root_window_input)

    # The height the wheel is capped by is the scroll's, and a scroll dragged
    # shorter than this column does not resize the column, it only clips it. So
    # the scroll's own resize is what asks the wheel to fit again.
    var scroll := _scroll()
    if scroll != null and not scroll.resized.is_connected(queue_sort):
        scroll.resized.connect(queue_sort)


## The order and visibility of the rows, and which shape the picker is. All
## three come from the profile, so one `profile_changed` carries the lot.
func apply_layout_settings() -> void:
    apply_shape_setting()
    var rows := element_rows()
    var current_idx := 0
    for element: String in SaSettings.get_layout_order("ColorPicker"):
        var control: Control = rows.get(element)
        if control and control.get_parent() == self:
            move_child(control, current_idx)
            current_idx += 1
    for element: String in rows:
        rows[element].visible = SaSettings.get_element_visible("ColorPicker", element)


## Each row by the name the Colour Picker's element list gives it.
func element_rows() -> Dictionary[String, Control]:
    return {
        "HSV Wheel": shape,
        "Hex Input": hex_row,
        SaExposureRow.ELEMENT: exposure_row,
        "Selected Colour Preview": preview_box,
        "Swatches": palette_row,
        "Recent Colours": recent_box,
        SaPickerSliders.ELEMENT_RGB: rgb_sliders,
        SaPickerSliders.ELEMENT_OKHSV: okhsv_sliders,
    }


## Gives the Colour Picker page its Type row, once.
##
## Idempotent, because `SaSettings.register_docker_option` refuses a key it
## already holds. Backed by `color_picker_shape` through the option's `setting`
## key rather than by a value of its own, so the setting that committed
## scenarios write through `{"prefs": {...}}` stays the one authority on which
## shape the picker is.
func _register_shape_option() -> void:
    (
        SaSettings
        . register_docker_option(
            "ColorPicker",
            "shape",
            {
                "title": "Type",
                "hint": "Which colour model the picker reads, and how it lays its area out.",
                "kind": SaSettingsLayout.OPTION_CHOICE,
                "values": SaPickerShapeScript.KIND_KEYS,
                "labels": SaPickerShapeScript.KIND_LABELS,
                "default": SaPickerShapeScript.KIND_KEYS[0],
                "setting": "color_picker_shape",
            }
        )
    )


## Gives the page its Keep chroma switch, once, off by default.
##
## An option of its own rather than a setting, because nothing but this docker
## reads it, and [method apply_shape_setting] hands it to the shape on every
## `profile_changed`, which is what a flip of the switch emits.
func _register_keep_chroma_option() -> void:
    (
        SaSettings
        . register_docker_option(
            "ColorPicker",
            KEEP_CHROMA_KEY,
            {
                "title": "Keep chroma",
                "hint": "A turn of the hue ring keeps the colour's lightness and its distance from grey, where the hue allows.",
                "kind": SaSettingsLayout.OPTION_SWITCH,
                "default": false,
            }
        )
    )


## Puts the picker into *kind*, through the setting.
##
## Through the setting rather than straight into the shape, so the choice
## survives a restart and every picker in the tree hears the same answer, and
## applied here as well, because `profile_changed` only reaches a picker that is
## in a tree and the setter is silent when the value is already what was asked
## for. This is the door the Preferences row, a test and a scenario come
## through.
func set_shape_kind(kind: int) -> void:
    if kind < 0 or kind >= SaPickerShapeScript.KIND_KEYS.size():
        return
    SaSettings.color_picker_shape = SaPickerShapeScript.KIND_KEYS[kind]
    apply_shape_setting()


## A right press anywhere on the shape opens the list of shapes at the pointer.
## The left button is the shape's own, and nothing else on the shape takes the
## right one.
func _on_shape_input(event: InputEvent, part: Control) -> void:
    var press := event as InputEventMouseButton
    if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_RIGHT:
        return
    shape_menu.open_at(part, press.position, shape.kind_key())
    part.accept_event()


func _on_shape_menu_chosen(id: StringName) -> void:
    set_shape_kind(SaPickerShapeScript.KIND_KEYS.find(String(id)))


## Steps the shape *by* places along [constant SaPickerShape.KIND_KEYS], wrapping
## past either end, and answers the key it landed on.
##
## Static and through the setting for the reason `set_shape_kind` gives above,
## and one further one: the chord that calls this has no picker to hand. The
## setting is the one place the shape lives, and every picker in a tree follows
## it through `profile_changed`, so a command that writes it moves the docker
## whether the docker is embedded, floating or not shown at all.
##
## Wrapping rather than stopping at the last shape, because the shortcut toggles
## between the modes, and a chord that goes dead on the
## seventh press is a chord a painter stops trusting.
static func step_shape_kind(by: int) -> String:
    var keys := SaPickerShapeScript.KIND_KEYS
    # An unknown key reads as the wheel, which is what `kind_of` answers, so a
    # profile holding a shape this build does not have steps off the wheel
    # rather than nowhere.
    var at := maxi(keys.find(SaSettings.color_picker_shape), 0)
    var landed: String = keys[posmod(at + by, keys.size())]
    SaSettings.color_picker_shape = landed
    return landed


## Puts the picker into the shape the profile names, and the dropdown onto the
## same row. Called from `apply_layout_settings`, so the setting and the row
## order arrive together rather than as two rebuilds.
func apply_shape_setting() -> void:
    shape.set_kind(SaPickerShapeScript.kind_of(SaSettings.color_picker_shape))
    shape.keep_chroma = SaSettings.get_docker_option("ColorPicker", KEEP_CHROMA_KEY) == true
    # The disc and the HSL square carry a bar beside them, which the wheel's
    # side gives way to, and showing it sorts nothing of this column's.
    queue_sort()


## The wheel's side in a column *width* wide whose rows have *room* to lay out
## in: the width, less the bar the disc and the HSL square carry beside them,
## capped by the height the other shown rows leave, and never under
## [constant WHEEL_MIN].
##
## **Square at the width, not grown into the height.** The shape's frame is
## the largest square that fits, so a shape expanded to whatever the rows below
## leave would draw small under six sliders, and with the rows hidden at the
## width with the height to spare above and below it. The height is the cap and the width is
## the aim, so what is left over falls under the last row.
func wheel_side(width: float, room: float) -> float:
    var left := room - _height_of_the_rest()
    return maxf(minf(width - shape.bar_width(), left), float(DockerUtils.px(WHEEL_MIN)))


## What every shown row but the wheel takes of the column's height, a gap above
## each one included.
##
## A top level child is no row, as the column's own sort skips it. The grey
## cover a mask as the target shows is one, and counted here it took a gap from
## the wheel each time the mask became the target.
func _height_of_the_rest() -> float:
    var gap := float(get_theme_constant("separation"))
    var rest := 0.0
    for child in get_children():
        var row := child as Control
        if row == null or row == shape or not row.visible or row.top_level:
            continue
        rest += row.get_combined_minimum_size().y + gap
    return rest


func _notification(what: int) -> void:
    if what == NOTIFICATION_PRE_SORT_CHILDREN:
        _fit_wheel()


## Gives the wheel its side before the column is sorted, which is where the
## width it is given and the room it has are both known.
##
## Only the height is written. The width is the column's, which the shape
## fills, and its frame is the largest square the two allow, so a shape as tall
## as it is wide draws a frame exactly that size. A side that did not move
## writes nothing, because a new minimum is another sort.
func _fit_wheel() -> void:
    var side := roundf(wheel_side(size.x, _room_height()))
    if not is_equal_approx(_wheel_side, side):
        _hold_wheel(side)


## Makes *side* the wheel's height, the one place the shape's minimum is
## written. The width stays at [constant WHEEL_MIN] because the column gives
## the shape its own.
func _hold_wheel(side: float) -> void:
    _wheel_side = side
    shape.custom_minimum_size = Vector2(float(DockerUtils.px(WHEEL_MIN)), side)


## The height this column has to lay its rows out in: the scroll's, less every
## margin between the scroll and this column, and this column's own when it
## sits in no scroll.
##
## The scroll's rather than this column's, because a column in a scroll is
## never shorter than its own minimum. Measured from itself, a wheel that had
## grown would keep the column tall, the tall column would keep the wheel's
## room, and a docker dragged shorter would scroll rather than shrink it.
func _room_height() -> float:
    var scroll := _scroll()
    if scroll == null:
        return size.y
    var room := scroll.size.y
    var node := get_parent()
    while node != null and node != scroll:
        var margin := node as MarginContainer
        if margin != null:
            room -= float(margin.get_theme_constant("margin_top") + margin.get_theme_constant("margin_bottom"))
        node = node.get_parent()
    return room


## What the wheel was given and why, for the state dump. `side` is the shape's
## height, and `width` and `room` the two numbers [method wheel_side] read,
## with `left` what the rows under it left of the room. The square the shape
## drew in that height is its own report's `frame_rect`.
func wheel_report() -> Dictionary:
    var room := _room_height()
    return {
        "side": _wheel_side,
        "width": size.x,
        "room": room,
        "left": room - _height_of_the_rest(),
        "min": DockerUtils.px(WHEEL_MIN),
    }


## Whether every visible row is inside the space the docker gives this column,
## and by how much it misses.
##
## `visible` on a row says the profile wants it drawn, not that anybody can see
## it. Two slider rows were added, the docker's default height did not move, and
## the last four sliders were laid out below its bottom edge: `visible` read
## true for all six and three of them were off the end of the window. The header
## already records the same failure with Godot's own ColorPicker in this file,
## so this is a number a scenario can watch rather than a shape somebody has to
## notice in a screenshot again.
##
## `needed` is the height the rows want, `given` is the height there is, and
## `overflow` is the difference when there is one. `fits` is false whenever the
## column is taller than its room, whether or not a scroll makes it reachable,
## because the two questions are different and a scenario should be able to ask
## either.
func rows_fit() -> Dictionary:
    var needed := get_combined_minimum_size().y
    # The scroll's own height, not the parent's. A ScrollContainer gives its
    # child every pixel the child asks for and clips, so measuring against the
    # parent answers "does the column fit itself", which is always yes.
    var scroll := _scroll()
    var room: Control = scroll if scroll != null else get_parent() as Control
    var given := room.size.y if room != null else size.y
    var wide_name := ""
    var wide := 0.0
    for child in get_children():
        var row := child as Control
        if row == null or not row.visible:
            continue
        var want := row.get_combined_minimum_size().x
        if want > wide:
            wide = want
            wide_name = String(row.name)
    return {
        "needed": needed,
        "given": given,
        "overflow": maxf(0.0, needed - given),
        "fits": needed <= given,
        "scrolls": scroll != null,
        # The other axis, and the row driving it. A column whose widest row
        # wants more than the docker gives runs under the right-hand edge
        # instead of wrapping, and no amount of scrolling downwards shows it.
        "needed_width": get_combined_minimum_size().x,
        "given_width": room.size.x if room != null else size.x,
        "widest_row": wide_name,
        "widest_row_width": wide,
    }


## The scroll this column sits in, or null when it sits in none. The docker puts
## one there so a stored geometry from before a row existed can still reach it.
func _scroll() -> ScrollContainer:
    var node: Node = get_parent()
    while node != null:
        var scroll := node as ScrollContainer
        if scroll != null:
            return scroll
        node = node.get_parent()
    return null


## What a capture reads to say which shape is up, which shapes there are, and
## what the picker is holding. A screenshot shows a triangle, not its name.
func picker_report() -> Dictionary:
    var out := shape.report()
    # The row left the docker, so a dump that still said whether it was visible
    # would be answering about nothing. What is left is the two halves a
    # scenario has to read against each other: the docker holds no such control,
    # and the shape it is in is the setting Preferences now writes.
    out["type_row_present"] = find_child("PickerTypeRow", true, false) != null
    out["type_setting"] = SaSettings.color_picker_shape
    out["type_items"] = SaPickerShapeScript.KIND_LABELS
    out["shape_menu"] = {"open": shape_menu.visible, "rows": shape_menu.row_report()}
    out["shape_hint"] = shape.frame.tooltip_text
    out["color"] = _color.to_html(false)
    out["background"] = _background.to_html(false)
    out["editing"] = "background" if _editing_background else "foreground"
    # The raw channels beside the hex, because `to_html` clamps and an HDR
    # colour would otherwise read as white in every dump.
    out["rgba"] = [_color.r, _color.g, _color.b, _color.a]
    out["exposure"] = {"stops": exposure_row.stops(), "shown": exposure_row.is_visible_in_tree()}
    out["rgb_sliders"] = rgb_sliders.report()
    out["okhsv_sliders"] = okhsv_sliders.report()
    out["rows_fit"] = rows_fit()
    out["wheel"] = wheel_report()
    out["clipped_rows"] = clipped_rows()
    out["hex"] = hex_report()
    out["swatches"] = palette_row.report()
    return out


## The hex box: what it holds, where it is, and whether it has the keyboard.
##
## `focused` is the whole point of the block. The claim is about who the next
## keystroke belongs to, and no screenshot shows that: the box looks the same
## either way, and a scenario that clicked at a point and assumed it landed is
## the reason the filing's own evidence went stale. `rect` is in the docker
## window's coordinates, which is what a scenario adds the window's position to,
## so a click can be aimed at the box rather than at a number somebody read off
## a picture.
func hex_report() -> Dictionary:
    if not is_instance_valid(hex_input):
        return {"present": false}
    var rect := hex_input.get_global_rect()
    return {
        "present": true,
        "text": hex_input.text,
        "focused": hex_input.has_focus(),
        "rect": {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y},
    }


## Every row of the picker whose right edge is past the docker's own, with how
## far past it goes.
##
## `rows_fit` answers whether the column as a whole wants more width than it has,
## which is one number for the docker. This is a list instead, because "no
## control of the picker is clipped at either width" is a claim about each row,
## and a column that fits on average can still have one row over the edge.
## Everything past that edge is not drawn and cannot be pressed, which is what
## the hide button was measured doing.
func clipped_rows() -> Array:
    var out: Array = []
    var window := get_window()
    if window == null:
        return out
    var edge := float(window.size.x)
    for child in get_children():
        var row := child as Control
        if row == null or not row.visible:
            continue
        var rect := row.get_global_rect()
        var over := rect.position.x + rect.size.x - edge
        if over > 0.0:
            out.append({"row": String(row.name), "right": rect.position.x + rect.size.x, "over_by": over})
    return out


## The foreground was written from outside. The shape follows it only while
## the foreground is what it edits.
func _adopt(col: Color) -> void:
    _color = col
    _show(not _editing_background)


## A chip, a hex code or a slider names a colour outright, so the shape follows
## it rather than the other way round, into whichever colour is edited.
func _adopt_edited(col: Color) -> void:
    _hold_edited(col)
    _show(true)


## Shows the pair on every row, and moves the shape to the edited colour as
## well when *move_shape*. A colour that came out of the shape is never put
## back into it, for the round trip `color` above describes.
func _show(move_shape: bool) -> void:
    if move_shape:
        shape.set_from_color(_edited())
    _refresh_controls()


## A colour the painter chose outright, from a chip or a hex code, which the
## usage tally counts as *how*. Announced as changed, which is the signal the
## docker hands on to the brush or the background, and then as committed, which
## is the recent row's. The commit alone left the brush on the old colour while
## the picker showed the new one.
func _pick(col: Color, how: StringName) -> void:
    _adopt_edited(col)
    if how == SaUsageTally.SWATCH and not _editing_background:
        foreground_picked.emit(col)
    _emit_edited()
    color_committed.emit(col)
    SaUsageTally.color_set(how)


## A slider moved. The shape follows, the way it follows a chip or a hex code,
## and the sliders are refreshed from the colour rather than from each other so
## the row that was dragged and the row that was not agree.
func _on_sliders_color_changed(new_color: Color) -> void:
    _adopt_edited(new_color)
    _emit_edited()


func _on_sliders_color_committed(new_color: Color) -> void:
    _adopt_edited(new_color)
    color_committed.emit(_painted(new_color))
    SaUsageTally.color_set(SaUsageTally.SLIDER)


func _on_shape_color_changed(new_color: Color) -> void:
    _shape_part = _part_moving()
    _hold_edited(new_color)
    _refresh_controls()
    _emit_edited()


func _on_shape_color_committed(new_color: Color) -> void:
    _hold_edited(new_color)
    _refresh_controls()
    color_committed.emit(_painted(new_color))
    SaUsageTally.color_set(_shape_part)


## Which part of the shape the gesture under way moves, as the usage tally
## names it: the ring, or the hue bar that does its job beside the HSL square,
## the area inside it, or the disc's lightness slider. Asked while the colour
## moves, because the shape lets go of the part before it says the colour was
## chosen.
func _part_moving() -> StringName:
    return shape.part_moving()


## Enter is a painter saying they are finished with the box, so the keyboard goes
## back to the application whether the code parsed or not. Without this the focus
## stayed on the field until something else was clicked, and every one-letter
## shortcut from there was a character typed into it: `x` did not swap the pair,
## `d` did not reset it, and nothing on screen said why.
##
## A code that does not parse is put back to the colour the picker is actually
## showing, rather than left on screen meaning nothing.
##
## **Six digits or three, as the tooltip says.** Godot's check also takes four
## and eight, which carry an alpha, and `#e8431c80` left the swatch a checker
## blend while the brush painted the colour solid. The foreground has no alpha
## a code could set, so such a code is refused like any other bad one rather
## than taken with a part dropped.
func _on_hex_submitted(text_val: String) -> void:
    if text_val.begins_with("#"):
        text_val = text_val.substr(1)
    if _is_hex_without_alpha(text_val):
        _pick(Color.html("#" + text_val), SaUsageTally.HEX)
    else:
        _show_hex(_edited())
    _release_hex()


## Whether *digits*, with no `#`, is a colour of three or six hex digits.
static func _is_hex_without_alpha(digits: String) -> bool:
    return (digits.length() == 3 or digits.length() == 6) and digits.is_valid_html_color()


## A click elsewhere is the painter finished with the box as surely as Enter
## is, so a code typed and left applies the same way, rather than staying in
## the field until the next refresh puts the old colour back over it with
## nothing to say Enter had been needed.
##
## Enter and Escape both release the focus, which lands here as well, but each
## has already put the field back to the colour the picker shows by then. So
## does a click in and out with no edit. A box that still shows that colour is
## therefore left alone, and one Enter is never two picks or two recent chips.
func _on_hex_focus_exited() -> void:
    if hex_input.text != _hex_of(_edited()):
        _on_hex_submitted(hex_input.text)


## A press anywhere but the field takes the keyboard from it. Godot leaves the
## focus where it was when the press lands on something that takes none, which
## the canvas is, so without this the field holds the typed code through a
## click on the canvas and the focus loss above never comes. Heard before the press
## reaches what it lands on, so a swatch pressed this way picks after the code.
##
## The press is in the root window's own pixels, and the field's screen
## transform is too, through any embedded window it sits in. A docker in a
## window of its own is never under a press the root hears.
func _on_root_window_input(ev: InputEvent) -> void:
    var press := ev as InputEventMouseButton
    if press == null or not press.pressed or not is_instance_valid(hex_input) or not hex_input.has_focus():
        return
    var window := hex_input.get_window()
    var own_window := window != get_tree().root and not window.is_embedded()
    var at := hex_input.get_screen_transform().affine_inverse() * press.position
    if own_window or not Rect2(Vector2.ZERO, hex_input.size).has_point(at):
        _release_hex()


## Escape is taken here rather than in unhandled input, the way `layer_rename.gd`
## takes it, because a `LineEdit` that does not consume it lets it reach whatever
## else in the window answers Escape.
##
## It cancels: the box goes back to the colour the picker holds and nothing is
## adopted or emitted, which is the difference between this key and Enter.
func _on_hex_gui_input(ev: InputEvent) -> void:
    var key := ev as InputEventKey
    if key == null or not key.pressed or key.keycode != KEY_ESCAPE:
        return
    _show_hex(_edited())
    _release_hex()
    if is_instance_valid(hex_input):
        hex_input.accept_event()


func _show_hex(value: Color) -> void:
    if hex_input:
        hex_input.text = _hex_of(value)


static func _hex_of(value: Color) -> String:
    return "#" + value.to_html(false)


## A field outside the tree has no viewport to give the focus back to, which is
## every picker a test builds: `add_child` is refused inside `run_all._ready`.
func _release_hex() -> void:
    if is_instance_valid(hex_input) and hex_input.is_inside_tree():
        hex_input.release_focus()


## The swatches show `_color` and `_background`, and the hex box and the
## numbers show whichever of the two is edited. All of them exist from `_init`,
## so a picker that is not in a tree yet still shows what it was given.
func _refresh_controls() -> void:
    _show_hex(_edited())
    if foreground_swatch:
        foreground_swatch.display(exposure_row.painted(_color), not _editing_background)
    if background_swatch:
        background_swatch.display(_background, _editing_background)
    # Without a signal, so showing a colour on the numbers cannot write it back
    # through them, and never from the sliders themselves, which is what keeps a
    # channel above 1.0 alive.
    if rgb_sliders:
        rgb_sliders.show_color(_edited())
    if okhsv_sliders:
        okhsv_sliders.show_color(_edited())


## One swatch of the pair: the colour, a thin grey rim so a colour as dark as
## the docker still shows, and the theme's green rim outside it while it is the
## one the picker edits.
##
## Drawn rather than a `ColorRect` in a bordered panel, because the rim changes
## with a press and a panel's stylebox would be one more node per swatch.
class Swatch:
    extends Control

    ## The rims' widths in logical pixels.
    const RIM: int = 1
    const EDITED_RIM: int = 2

    var color: Color
    ## Whether this is the swatch the picker edits, which the green rim marks.
    var edited: bool

    func _init(start: Color, start_edited: bool) -> void:
        color = start
        edited = start_edited
        size_flags_horizontal = Control.SIZE_EXPAND_FILL
        mouse_filter = Control.MOUSE_FILTER_STOP

    ## Shows *col*, marked as edited when *is_edited*.
    func display(col: Color, is_edited: bool) -> void:
        color = col
        edited = is_edited
        queue_redraw()

    func _draw() -> void:
        var rect := Rect2(Vector2.ZERO, size)
        var outer := float(DockerUtils.px(EDITED_RIM))
        if edited:
            draw_rect(rect, SaTheme.palette.border_selected)
        var inner := rect.grow(-outer)
        draw_rect(inner, SaTheme.palette.text_muted)
        draw_rect(inner.grow(-float(DockerUtils.px(RIM))), color)
