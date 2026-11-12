## A colour picker wired to `SaColors` on its own, which is every picker on
## screen: the Colour Picker docker's, showing the rows its switches leave on,
## and each view of one of its seven elements another docker holds, showing
## that element alone.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A placed wheel, box or swatch row shows and sets the one brush colour the
## docker does. [SaColorPicker] owns no colour. The pair and the lists are
## handed in and every choice goes out as a signal. A view wired some other way
## would be a second road to the brush, so the wiring is here rather than in
## `ColorDocker`, and the docker's own picker and every view are this one class
## wired the one way. Nothing pins a view to a colour of its
## own: what it shows is the store's, through the bus, and what it sets goes to
## the store.
##
## **A view is a whole picker showing one row.** The hex box's parsing, the
## pair's buttons and the shape's menu and its fit are the picker's, and a view
## built from the rows' own classes would have wired each of them a second
## time. The rows a view hides are refreshed with every colour and never drawn.
##
## **The side the pickers edit is one.** A press on a swatch of the pair makes
## that colour the one the wheel, the sliders and the hex box edit. A placed
## pair beside a placed wheel steers that wheel, and the docker's own and every
## other view with it, so [member _side] is shared by every picker this class
## builds, and a view built later starts on the side the others are on.
class_name SaColorPickerView
extends SaColorPicker

## The Preferences category the Colour Picker's elements are filed under, the
## settings key that predates the docker id.
const CATEGORY := "ColorPicker"

## Which colour of the pair every picker edits.
static var _side := Side.new()

## The element this picker shows alone, by its layout name, or empty for the
## docker's own picker.
var _element := ""

## True while this picker hands the store a colour of its own, so it does not
## take that colour back as one from outside.
var _sending := false

## True from a chip's whole pick until the `color_changed` the picker sends
## after it, which carries the colour part the pick already set.
var _whole_pick := false


## A picker showing *element* alone, or every row the docker's switches leave
## on when *element* is empty, wired to the store from the start, so a view
## that is in no tree yet already shows and sets the store's colours.
func _init(element := "") -> void:
    super()
    _element = element
    if not element.is_empty():
        name = element.replace(" ", "").replace("-", "") + "View"
    color = SaColors.foreground_base
    show_exposure(SaColors.exposure_stops)
    background = SaColors.background
    set_swatches(SaColors.swatches, SaColors.swatch_names, SaColors.last_removed_swatch != null)
    set_recent(SaColors.recent)
    edit_background(_side.background)
    color_changed.connect(_on_own_color)
    foreground_picked.connect(_on_own_foreground_picked)
    exposure_changed.connect(_on_own_exposure)
    color_committed.connect(SaColors.note_used)
    background_changed.connect(_on_own_background)
    reset_requested.connect(SaColors.reset)
    swap_requested.connect(SaColors.swap)
    swatch_add_requested.connect(SaColors.add_swatch)
    swatch_remove_requested.connect(ColorDocker.remove_swatch)
    swatch_rename_requested.connect(SaColors.rename_swatch)
    swatch_undo_remove_requested.connect(ColorDocker.undo_remove)
    swatches_add_requested.connect(SaColors.add_swatches)
    # The Clear button, and the Replace answer to a load, which the picker sends
    # as this and then the add above: a replace is the row's own two steps in
    # one press rather than a third door into the store.
    swatches_clear_requested.connect(SaColors.clear_swatches)
    SaColors.foreground_changed.connect(_on_store_foreground_changed)
    EventBus.background_color_changed.connect(_on_bus_background)
    SaColors.swatches_changed.connect(_on_swatches_changed)
    SaColors.recent_changed.connect(_on_recent_changed)
    _side.changed.connect(edit_background)
    add_child(SaGreyVeil.new())
    foreground_swatch.gui_input.connect(_on_pair_input.bind(false))
    background_swatch.gui_input.connect(_on_pair_input.bind(true))
    if not element.is_empty():
        apply_layout_settings()


## Registers a view of each of the Colour Picker's seven elements through
## `SaSettings.register_layout_element`, the call a module makes, under the titles its page gives them,
## "Picker Shape" for the stored
## "HSV Wheel". Called from `ColorDocker._init`, which the boot runs whether
## the docker is open or not, and a second call replaces the first one's views.
## Static, so the door holds no docker a suite has freed.
static func register_views() -> void:
    for element: String in SaSettingsLayout.DEFAULT_ORDERS[CATEGORY]:
        if SaSettings.ELEMENT_PLACES.has(element):
            continue
        var builder := func() -> Control: return SaColorPickerView.new(element)
        var title := SaSettings.element_title(CATEGORY, element)
        SaSettings.register_layout_element(CATEGORY, element, title, false, "", builder)


## The docker's own picker orders and shows its rows by the switches, and a
## view shows its element alone whatever they say, because the switches are the
## Colour Picker's and the view's own switch is the docker it stands in.
func apply_layout_settings() -> void:
    if _element.is_empty():
        super()
        return
    apply_shape_setting()
    var rows := element_rows()
    for element: String in rows:
        rows[element].visible = element == _element


## What this picker shows, for the state dump beside the docker's own report:
## its element, the pair, the colour its shape holds, which of the pair it
## edits and the rows it draws, with where it is on screen.
func view_report() -> Dictionary:
    var rows := element_rows()
    var drawn: Array[String] = []
    for element: String in rows:
        if rows[element].visible:
            drawn.append(element)
    var rect := get_global_rect()
    return {
        "element": _element,
        "name": String(name),
        "color": color.to_html(false),
        "background": background.to_html(false),
        "shape_color": shape.color().to_html(false),
        "editing": "background" if _editing_background else "foreground",
        "drawn": drawn,
        "rect": {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y},
    }


## The wheel, the sliders or the hex box moved the colour part, and the store
## keeps the stops. The store announces the foreground on the bus, which every
## tool and every other picker hears.
func _on_own_color(new_color: Color) -> void:
    if _whole_pick:
        _whole_pick = false
        return
    if _sending:
        return
    _sending = true
    SaColors.foreground_base = new_color
    _sending = false


## A kept or recent chip is a pick of a whole colour, so the store splits it:
## a chip at (16, 0, -0.5) is 4 stops of its colour part, not 4 more.
func _on_own_foreground_picked(new_color: Color) -> void:
    _whole_pick = true
    SaColors.foreground = new_color


func _on_own_exposure(stops: float) -> void:
    if _sending:
        return
    _sending = true
    SaColors.exposure_stops = stops
    _sending = false


## The painter moved the background here. The store's setter announces it on
## the bus, which comes back to this picker as the colour it already holds and
## moves nothing.
func _on_own_background(new_color: Color) -> void:
    SaColors.background = new_color


## The store's split moved, by a pick from anywhere or by either slider, so
## the picker shows the colour part and the stops. Heard during the picker's
## own edits too, because the store may fold a peak above 1 into the stops. A
## half the picker already holds is not written back, because a colour that
## came out of the shape must not go back in (see `SaColorPicker.color`), and
## a wheel drag would refresh every row twice an event.
func _on_store_foreground_changed() -> void:
    if not color.is_equal_approx(SaColors.foreground_base):
        color = SaColors.foreground_base
    if not is_equal_approx(exposure_row.stops(), SaColors.exposure_stops):
        show_exposure(SaColors.exposure_stops)


func _on_bus_background(new_color: Color) -> void:
    background = new_color


func _on_swatches_changed() -> void:
    set_swatches(SaColors.swatches, SaColors.swatch_names, SaColors.last_removed_swatch != null)


func _on_recent_changed() -> void:
    set_recent(SaColors.recent)


## A left press on a swatch of the pair makes it the side every picker edits.
## The picker's own handler has already moved this one.
func _on_pair_input(event: InputEvent, background_side: bool) -> void:
    var press := event as InputEventMouseButton
    if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_LEFT:
        return
    _side.choose(background_side)


## Which colour of the pair the pickers edit, one for them all, and the signal
## each picker follows it by.
class Side:
    extends RefCounted

    signal changed(background: bool)

    ## True while the background is the colour edited.
    var background := false

    func choose(on: bool) -> void:
        background = on
        changed.emit(on)
