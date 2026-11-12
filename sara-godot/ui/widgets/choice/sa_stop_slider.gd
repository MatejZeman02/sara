## A choice of a few named ways drawn as one control: a track with a stop per
## option spread evenly, each option's label over its stop, and one thumb on
## the stop picked.
##
## One control rather than three buttons in one group, which a painter reads in
## a dialog's button row as three more buttons rather than one choice, and any
## number of options rather than three.
##
## A press anywhere on the track puts the thumb under the pointer, a drag
## slides it, and letting go settles it on the nearest stop. Left and Right
## step it while it has the focus. A hand's pick emits [signal picked] once,
## and a script's write to [member value] emits nothing, the way a `Range`'s
## silent setter does, so a page pushing a stored value back never hears
## itself.
##
## A stop can be dimmed with a reason, which its tooltip then says in place of
## its own, and no hand's pick lands on it.
##
## Drawn rather than built of child controls, because the thumb sits between
## two stops while it is dragged. Every size is logical (hard rule 7, one writer for UI scale), and the
## label's font is the theme's, so the Font size preference reaches it. The
## labels and tooltips are translated here, the way a `Button` translates its
## own text, so a caller hands over the English.
##
## A slider made to follow its width asks only for its widest label, so a
## language longer than English never widens the docker that holds it. When its
## labels then do not fit their cells side by side, it shows the picked one
## alone over the track, under the thumb and kept inside the control, and the
## stop a drag is nearest while it is held. A tooltip still names each stop.
class_name SaStopSlider
extends Control

## A hand moved the thumb to another stop. Once per change, and never for a
## write to [member value].
signal picked(id: Variant)

## The track's height, logical.
const TRACK_HEIGHT: int = 14

## The room between the track's edge and the thumb inside it, logical.
const INSET: int = 2

## A stop's mark on the track, its diameter, logical.
const TICK: int = 4

## What a dimmed stop's label keeps of its colour.
const DIMMED_ALPHA: float = 0.4

## How far a cell may fall short of its label before the labels count as not
## fitting, for the rounding of a container's sort.
const SLACK: float = 0.5

## The options, left to right, each `{"id": Variant, "label": String,
## "tooltip": String}`. An entry may be a bare label, whose id is its index,
## the shape `SaPageSection.normalize_choices` gives with the tooltip kept.
var options: Array = []

## The id of the picked option. A write redraws and emits nothing.
var value: Variant = null:
    set(val):
        value = val
        queue_redraw()

## The stops no hand can pick, id to the reason, written through [method dim].
var dimmed: Dictionary = {}

## Whether the control asks only for its widest label and shows the picked one
## alone when the labels do not fit side by side, set once by the constructor.
var _follows_width: bool = false

## The pointer's x while a press is held, or NAN when none is.
var _drag_x: float = NAN

## The stop under the pointer, or -1 when the pointer is elsewhere.
var _hovered: int = -1

var _track: StyleBoxFlat = SaTheme.make_toggle_style("normal")
var _track_focused: StyleBoxFlat = SaTheme.make_toggle_style("focus")
var _thumb: StyleBoxFlat = SaTheme.make_toggle_style("pressed")
var _hover: StyleBoxFlat = SaTheme.make_toggle_style("hover")


## *choices* are the options, and the first is picked. *follows_width* makes
## the control ask for its widest label rather than every label side by side.
func _init(choices: Array = [], follows_width: bool = false) -> void:
    _follows_width = follows_width
    focus_mode = Control.FOCUS_ALL
    mouse_filter = Control.MOUSE_FILTER_STOP
    for index in choices.size():
        var given: Variant = choices[index]
        var entry: Dictionary = given if given is Dictionary else {"label": String(given)}
        options.append(
            {"id": entry.get("id", index), "label": String(entry.get("label", "")), "tooltip": String(entry.get("tooltip", ""))}
        )
    if not options.is_empty():
        value = options[0]["id"]


func _ready() -> void:
    # The boxes are bound to the palette, and they are drawn by hand, so a
    # theme switch shows only on the next draw.
    if not EventBus.theme_changed.is_connected(_on_theme_changed):
        EventBus.theme_changed.connect(_on_theme_changed)


func _notification(what: int) -> void:
    match what:
        NOTIFICATION_THEME_CHANGED, NOTIFICATION_TRANSLATION_CHANGED:
            update_minimum_size()
            queue_redraw()
        NOTIFICATION_MOUSE_EXIT:
            _hovered = -1
            queue_redraw()
        NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT:
            queue_redraw()


## The widest label times the count, with the theme's gap beside each, so no
## label is ever cut, over the track. A control following its width asks for
## the widest label once, which is all it shows when the labels do not fit.
func _get_minimum_size() -> Vector2:
    var cell := _widest_cell()
    var count := 1 if _follows_width else options.size()
    return Vector2(cell * count, _track_top() + float(SaUI.px(TRACK_HEIGHT)))


## Whether every label fits its own cell, so all of them are drawn. Always so
## for a control that does not follow its width, whose minimum makes it so.
func shows_every_label() -> bool:
    return _widest_cell() <= _cell() + SLACK


## The stops whose labels are drawn, left to right: every one, or when they do
## not fit side by side, the one the thumb stands on or a held drag is nearest.
func shown_labels() -> Array[int]:
    var shown: Array[int] = []
    if shows_every_label():
        for index in options.size():
            shown.append(index)
        return shown
    var at := index_of(value) if is_nan(_drag_x) else _stop_at(clampf(_drag_x, 0.0, maxf(size.x - 1.0, 0.0)))
    if at >= 0:
        shown.append(at)
    return shown


## Dims the stop *id* with *why* as its tooltip, or brings it back under its own
## tooltip when *why* is empty.
func dim(id: Variant, why: String) -> void:
    if why.is_empty():
        dimmed.erase(id)
    else:
        dimmed[id] = why
    queue_redraw()


## Picks *id* the way a hand would, and answers whether the thumb moved. A
## dimmed stop and an id no option has are refused.
func pick(id: Variant) -> bool:
    return _pick_index(index_of(id))


## Where option *id* stands, left to right, or -1.
func index_of(id: Variant) -> int:
    for index in options.size():
        if options[index]["id"] == id:
            return index
    return -1


## The x of stop *index*'s centre, in the control's own space. Each option
## has an equal cell of the width, and its stop is the cell's middle.
func stop_x(index: int) -> float:
    return _cell() * (float(index) + 0.5)


## Where the label of stop *index* is drawn: its own width, centred over its
## stop, on the top line. A label shown alone is kept inside the control, so
## the first and last stops' do not pass its edges.
func label_rect(index: int) -> Rect2:
    var width := _text_width(atr(options[index]["label"]))
    var left := stop_x(index) - width / 2.0
    if not shows_every_label():
        left = clampf(left, 0.0, maxf(size.x - width, 0.0))
    return Rect2(left, 0.0, width, _line_height())


## The stop nearest *x* a hand may pick, dimmed stops left out, or -1 when
## every stop is dimmed.
func nearest(x: float) -> int:
    var best := -1
    for index in options.size():
        if dimmed.has(options[index]["id"]):
            continue
        if best < 0 or absf(stop_x(index) - x) < absf(stop_x(best) - x):
            best = index
    return best


## What the control shows, for the state dump and a suite: the pick, and each
## stop's label and whether a hand may take it.
func describe() -> Dictionary:
    var stops: Array = []
    for option: Dictionary in options:
        stops.append({"id": option["id"], "label": option["label"], "dimmed": dimmed.has(option["id"])})
    return {"value": value, "stops": stops, "dragging": not is_nan(_drag_x)}


func _gui_input(event: InputEvent) -> void:
    var press := event as InputEventMouseButton
    if press != null and press.button_index == MOUSE_BUTTON_LEFT:
        if press.pressed:
            _drag_x = press.position.x
            if is_inside_tree():
                grab_focus()
        elif not is_nan(_drag_x):
            var settled := nearest(_drag_x)
            _drag_x = NAN
            _pick_index(settled)
        queue_redraw()
        accept_event()
        return
    var motion := event as InputEventMouseMotion
    if motion != null:
        _hovered = _stop_at(motion.position.x)
        if not is_nan(_drag_x):
            _drag_x = motion.position.x
            accept_event()
        queue_redraw()
        return
    var key := event as InputEventKey
    if key != null and key.pressed and (key.keycode == KEY_LEFT or key.keycode == KEY_RIGHT):
        _step(-1 if key.keycode == KEY_LEFT else 1)
        accept_event()


## The hovered stop's own tooltip, or the reason it is dimmed.
func _get_tooltip(at_position: Vector2) -> String:
    var index := _stop_at(at_position.x)
    if index < 0:
        return ""
    var id: Variant = options[index]["id"]
    return atr(String(dimmed[id]) if dimmed.has(id) else String(options[index]["tooltip"]))


func _draw() -> void:
    if options.is_empty():
        return
    var font := _font()
    var font_size := _font_size()
    var top := _track_top()
    var track := Rect2(0.0, top, size.x, float(SaUI.px(TRACK_HEIGHT)))
    draw_style_box(_track_focused if has_focus() else _track, track)
    var mid := track.get_center().y
    var at := index_of(value)
    var labels := shown_labels()
    if _hovered >= 0 and _hovered != at and not dimmed.has(options[_hovered]["id"]):
        draw_style_box(_hover, _thumb_rect(stop_x(_hovered), track))
    for index in options.size():
        var id: Variant = options[index]["id"]
        var colour := SaTheme.palette.text_primary if index == at else SaTheme.palette.text_muted
        if dimmed.has(id):
            colour.a *= DIMMED_ALPHA
        draw_circle(Vector2(stop_x(index), mid), float(SaUI.px(TICK)) / 2.0, colour)
        if not labels.has(index):
            continue
        var place := label_rect(index)
        draw_string(
            font,
            Vector2(place.position.x, font.get_ascent(font_size)),
            atr(options[index]["label"]),
            HORIZONTAL_ALIGNMENT_LEFT,
            -1,
            font_size,
            colour
        )
    if at < 0 and is_nan(_drag_x):
        return
    var x := stop_x(at) if is_nan(_drag_x) else clampf(_drag_x, stop_x(0), stop_x(options.size() - 1))
    draw_style_box(_thumb, _thumb_rect(x, track))


## The thumb's box when it stands at *x*: one cell wide less the inset, inside
## the track.
func _thumb_rect(x: float, track: Rect2) -> Rect2:
    var inset := float(SaUI.px(INSET))
    var width := maxf(_cell() - 2.0 * inset, 0.0)
    return Rect2(x - width / 2.0, track.position.y + inset, width, track.size.y - 2.0 * inset)


## Moves the thumb *direction* stops along, past any dimmed stop, and stays put
## at either end.
func _step(direction: int) -> void:
    var index := index_of(value) + direction
    while index >= 0 and index < options.size():
        if not dimmed.has(options[index]["id"]):
            _pick_index(index)
            return
        index += direction


func _pick_index(index: int) -> bool:
    if index < 0 or index >= options.size() or dimmed.has(options[index]["id"]):
        return false
    var id: Variant = options[index]["id"]
    if id == value:
        queue_redraw()
        return false
    value = id
    picked.emit(id)
    return true


## The stop whose cell *x* falls in, dimmed or not, or -1 off the control.
func _stop_at(x: float) -> int:
    if options.is_empty() or x < 0.0 or x >= size.x:
        return -1
    return clampi(int(x / _cell()), 0, options.size() - 1)


## A label's cell when the widest label sets it: that label and the theme's gap.
func _widest_cell() -> float:
    var widest := 0.0
    for option: Dictionary in options:
        widest = maxf(widest, _text_width(atr(option["label"])))
    return ceilf(widest) + float(SaUI.px(SaTheme.GAP))


func _cell() -> float:
    return size.x / float(maxi(1, options.size()))


func _track_top() -> float:
    return _line_height() + float(SaUI.px(SaTheme.GAP_TIGHT))


func _line_height() -> float:
    return ceilf(_font().get_height(_font_size()))


func _text_width(text: String) -> float:
    return _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size()).x


## A label's font and size, or the control's own where a theme pass wrote an
## override onto it, the way a docker's pass reaches every control it holds.
func _font() -> Font:
    return get_theme_font("font") if has_theme_font_override("font") else get_theme_font("font", "Label")


func _font_size() -> int:
    if has_theme_font_size_override("font_size"):
        return get_theme_font_size("font_size")
    return get_theme_font_size("font_size", "Label")


func _on_theme_changed(_theme_id: String) -> void:
    queue_redraw()
