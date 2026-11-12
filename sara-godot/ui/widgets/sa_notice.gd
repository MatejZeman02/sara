## A line in the canvas's bottom centre that goes away by itself.
##
## Bottom centre because the bottom left is already `SaFocusMode`'s corner. It is
## where the line lands when nothing stands there, and when a window does it goes
## to the nearest place none covers. The default layout puts the
## Reference docker at the bottom left and Layers at the bottom right, and a line
## as long as a client's first message would run under both, leaving only its
## middle to read. A line wider than any place there is wraps into the widest one, so
## it is read whole rather than pushed back under a docker. A full-rect Control
## that ignores the mouse, so nothing underneath stops working while it shows.
##
## A place rather than a window of its own above the dockers, the other way
## out. A window of its own is a native window with subwindows off, and that
## one needs a position Wayland never gives a toplevel, its own theme and scale,
## and a claim on the pointer that the cursor package would have to learn to
## leave alone. A place works the same in both modes and needs none of it.
##
## The panel is its own Control rather than a second `SaFocusMode`: that one is
## a mode's own announcement and owns the memory of which dockers were open,
## and folding the two into one widget would drag that memory along with it.
##
## Its own file, cut by responsibility: what it owns is a line and a clock, and
## the dialog window owns neither. `SaMessage.notice_widget()` is the call that
## reaches it.
@tool
class_name SaNotice
extends Control

## How long a line stays, in seconds. Long enough to read one sentence, and
## short enough that it is gone before the next stroke wants the room.
const SECONDS: float = 2.5

## Distance from the bottom edge, in logical pixels.
const BOTTOM_MARGIN: int = 24

## Room kept between the line and a window beside it, in logical pixels.
const WINDOW_GAP: int = 8

## The narrowest a line is wrapped to, in logical pixels. Below it the notice
## stays wide and stands in its usual place, since a column of three words a
## line is no easier to read under a docker than beside one.
const MIN_WIDTH: int = 240

var panel: PanelContainer
var label: Label

var _timer: Timer

## True while `_place` is running, so the resize its own wrapping causes is not
## answered with a second placement in the middle of the first.
var _placing: bool = false


func _init() -> void:
    name = "Notice"
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE

    panel = PanelContainer.new()
    panel.name = "Panel"
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.visible = false
    var style := StyleBoxFlat.new()
    SaTheme.bind(style, {"bg_color": "bg_panel", "border_color": "border_drag"})
    style.set_border_width_all(2)
    style.set_content_margin_all(float(SaUI.px(8)))
    panel.add_theme_stylebox_override("panel", style)
    add_child(panel)

    label = SaMake.label(panel, "Text")
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
    _timer = Timer.new()
    _timer.name = "NoticeTimer"
    _timer.one_shot = true
    _timer.wait_time = SECONDS
    _timer.timeout.connect(_hide)
    add_child(_timer)
    _place()
    resized.connect(_place)
    # The panel is only as wide as the text once the layout pass has run, so
    # a placement computed the moment the text is written centres the width
    # of the line before it.
    panel.resized.connect(_place)


## Shows *text* and restarts the clock.
##
## The panel is taken back to one line first, so the width a previous line was
## wrapped to is not this line's, and `reset_size` gives it that line's own size
## at once instead of after the next layout pass.
func show_line(text: String) -> void:
    label.text = text
    label.autowrap_mode = TextServer.AUTOWRAP_OFF
    label.custom_minimum_size.x = 0.0
    panel.reset_size()
    panel.visible = true
    _place()
    if _timer != null and _timer.is_inside_tree():
        _timer.start()


## Whether a line is on screen right now.
func showing() -> bool:
    return panel != null and panel.visible


func _hide() -> void:
    panel.visible = false


func _place() -> void:
    if panel == null or _placing:
        return
    _placing = true
    var margin := float(SaUI.px(BOTTOM_MARGIN))
    var gap := float(SaUI.px(WINDOW_GAP))
    var covering := _covering_rects()
    var found: Variant = SaClearSlot.find_slot(size, panel.size, covering, margin, gap)
    if found == null:
        # No row has a stretch as wide as the line, so the line is wrapped to the
        # widest there is, when that is wide enough to be worth reading.
        var room := SaClearSlot.widest_room(size, panel.size.y, covering, margin, gap)
        if room >= float(SaUI.px(MIN_WIDTH)) and room < panel.size.x:
            _wrap_to(room)
            found = SaClearSlot.find_slot(size, panel.size, covering, margin, gap)
    var slot: Rect2 = found if found != null else SaClearSlot.home_slot(size, panel.size, margin)
    panel.position = slot.position
    _placing = false


## Wraps the line to *width*, the panel's outer width. The height follows on the
## next layout pass, which resizes the panel and so places it again with the
## height the wrapped line really has.
func _wrap_to(width: float) -> void:
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.custom_minimum_size.x = width - panel.get_theme_stylebox("panel").get_minimum_size().x
    panel.reset_size()


## What stands over the host right now, in this control's own units: every
## docker and menu embedded in the window, and every window of its own, which is
## what each of them is once subwindows are off. A window the pointer passes
## through covers nothing that matters, and a tooltip is one.
func _covering_rects() -> Array[Rect2]:
    var found: Array[Rect2] = []
    var window := get_window()
    if window == null or not is_inside_tree():
        return found
    var origin := global_position
    for sub in SaCursorPolicy.embedded_subwindows(window, true):
        if not sub.mouse_passthrough:
            found.append(Rect2(Vector2(sub.position) - origin, Vector2(sub.size)))
    for other in SaCursorPolicy.windows_of_their_own(get_tree().root, window):
        if other.mouse_passthrough:
            continue
        var rect := SaCursorPolicy.rect_in(window, other)
        if rect.has_area():
            found.append(Rect2(rect.position - origin, rect.size))
    return found
