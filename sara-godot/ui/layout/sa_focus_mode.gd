## Focus mode: the dockers hidden, which ones were open remembered, and a
## message in the canvas corner saying so.
##
## Tab remembers what was open rather than hiding everything and showing
## everything again, which would open on the way back dockers the painter had
## closed on purpose. The memory of what was open lives here rather than in `main.gd`,
## which is past the file-length rule, and so does the message, because both
## belong to the same one decision.
##
## A full-rect `Control` over the main window, ignoring the mouse. It draws
## nothing until a toggle, then a small panel in the bottom left for a few
## seconds. Bottom left because every docker Sara ships defaults to the right
## or the top, so this is the one corner a message cannot land behind.
##
## It also keeps the moment the painter has not caught up with the Tab. Where a
## docker stood is the canvas's to paint on, which is what hiding it is for, so
## the canvas keeps that. But a click aimed at a slider that was there a
## heartbeat ago would paint a dab and cost a history step. So each hidden
## docker's place is outlined for half a second and fades, and a left press
## inside an outline is swallowed and makes it flash. After the fade the canvas
## paints there.
@tool
extends Control

class_name SaFocusMode

## How long the message stays, in seconds.
const MESSAGE_SECONDS: float = 2.5

## Distance from the two edges it sits against, in logical pixels.
const CORNER_MARGIN: int = 16

## How long an outline of a hidden docker stays, fading all the way, in seconds,
## half of one because the painter found a whole second too slow to fade.
const OUTLINE_SECONDS: float = 0.5

## How long an outline stays at full strength after a press it swallowed, in
## seconds. It never adds to the outline's own life.
const FLASH_SECONDS: float = 0.18

## The outline's line width, in logical pixels.
const OUTLINE_WIDTH: int = 2

## Whether the dockers are hidden right now.
##
## Static because the Info docker shows this line and has no route to the
## instance: it is handed a canvas and a tool machine, not the window's
## furniture. Process-wide rather than per-window, which is right while one
## Tab hides the dockers of the main window and there is nothing to hide on
## the secondary one.
static var active: bool = false

var _panel: PanelContainer
var _label: Label
var _timer: Timer

## Docker ids that were visible when focus mode was entered, so the way back
## restores those and no others.
##
## Static beside `active`, because the layout store asks which dockers the mode
## hid and has no route to the instance either.
static var _remembered: Dictionary = {}

## Where the dockers Tab hid stood, in the host window's space, for as long as
## the outlines show.
var _outlines: Array[Rect2] = []

## The seconds the outlines have left, counted down by `_process`, and the seconds
## the flash of a swallowed press has left, on the outline at `_flashing`.
var _left: float = 0.0
var _flash: float = 0.0
var _flashing: int = -1

## True between a left press the outlines swallowed and its release, so the
## release is swallowed too and the canvas is never handed half a click.
var _holding: bool = false

## Only carries the theme's colour for the outline, so a theme change reaches it.
var _edge: StyleBoxFlat


func _init() -> void:
    name = "FocusMode"
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE

    _panel = PanelContainer.new()
    _panel.name = "Message"
    _panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _panel.visible = false
    var style := StyleBoxFlat.new()
    SaTheme.bind(style, {"bg_color": "bg_panel", "border_color": "border_drag"})
    style.set_border_width_all(2)
    style.set_content_margin_all(float(SaUI.px(8)))
    _panel.add_theme_stylebox_override("panel", style)
    add_child(_panel)

    _label = SaMake.label(_panel, "Text")
    _label.mouse_filter = Control.MOUSE_FILTER_IGNORE

    _edge = StyleBoxFlat.new()
    SaTheme.bind(_edge, {"border_color": "border_drag"})
    set_process(false)
    set_process_input(false)


func _ready() -> void:
    _timer = Timer.new()
    _timer.name = "MessageTimer"
    _timer.one_shot = true
    _timer.wait_time = MESSAGE_SECONDS
    _timer.timeout.connect(_hide_message)
    add_child(_timer)
    _place_message()
    resized.connect(_place_message)


## Hides every docker that is open and remembers it, or shows back exactly the
## ones that were remembered.
##
## *dockers* is `main.gd`'s docker table: one Dictionary per docker with an
## `id` and a `node`. *stood* is where each open one stands, docker id to a
## `Rect2` in the host window's space, taken before the hide because a window
## that is hidden has no place to ask. *pinned* is the docker ids the painter
## pinned, which stay shown and are drawn no outline, since nothing moved where
## they stand. Answers the ids whose visibility changed, so the caller can tick
## the menus and save the layout for those and no others.
##
## The pins are read on the way in and nowhere else. The way back shows what was
## hidden, so a pin changed while the mode is on counts from the next Tab.
func toggle(dockers: Array, stood: Dictionary = {}, pinned: Array = []) -> Array:
    var changed: Array = []
    if active:
        for config: Dictionary in dockers:
            var window: Window = config.get("node") as Window
            if window == null or not _remembered.has(String(config.get("id", ""))):
                continue
            if not window.visible:
                window.visible = true
                changed.append(config.get("id", ""))
        _remembered.clear()
        _clear_outlines()
        active = false
    else:
        _remembered.clear()
        var outlines: Array[Rect2] = []
        for config: Dictionary in dockers:
            var window: Window = config.get("node") as Window
            var id := String(config.get("id", ""))
            if window == null or not window.visible or pinned.has(id):
                continue
            _remembered[id] = true
            var rect: Rect2 = stood.get(id, Rect2())
            if rect.has_area():
                outlines.append(rect)
            window.visible = false
            changed.append(config.get("id", ""))
        _show_outlines(outlines)
        # Nothing was open, or every open docker is pinned, so there is nothing
        # to come back to and the mode would be a state the next Tab could not
        # leave.
        active = not _remembered.is_empty()
    show_message()
    return changed


## The line the painter reads, in the corner and in the Info docker.
static func status_text() -> String:
    return "on" if active else "off"


## Whether a layout save writes the docker *id* as open, given that its window
## shows *shown*.
##
## The layout is what is under the mode, and Tab hides the dockers without
## closing them, so a docker the mode hid is open as far as the file is
## concerned. Sara starts with the mode off, and a file that said closed gave
## the next start no docker and no memory of which ones to give back. Every
## other docker is written as its window stands, a pinned one open and one the
## painter closed under the mode closed.
static func layout_visible(id: String, shown: bool) -> bool:
    return shown or (active and _remembered.has(id))


## The painter's own choice about the docker *id* while the mode is on, from
## the Window menu, a chord or the docker's close button. That choice is the
## painter's and not the Tab's, so the layout and the way back both take it as
## it now stands.
static func forget(id: String) -> void:
    _remembered.erase(id)


## Leaves the mode without touching a window, for a layout about to say which
## dockers are open. Nothing is shown here, because the layout names the
## visibility of every docker it holds and a remembered one written over it
## would be the Tab's word against the painter's newer choice.
static func leave() -> void:
    active = false
    _remembered.clear()


func show_message() -> void:
    if active:
        _label.text = tr("Focus mode. Tab or the Focus Mode button on the bar brings the dockers back.")
    else:
        _label.text = tr("Focus mode off. The dockers are as you left them.")
    _panel.visible = true
    _place_message()
    if _timer != null:
        _timer.start()


func _hide_message() -> void:
    _panel.visible = false


## Whether the outlines of the hidden dockers are on screen, which is also
## whether a press inside one is taken.
func outlines_showing() -> bool:
    return _left > 0.0


## Whether *event* is a click the outlines take, and takes it: a left press
## inside one flashes it and answers true, and so does the release that ends
## that press. Nothing else is taken, and nothing at all once the outlines have
## faded.
func swallows(event: InputEvent) -> bool:
    var button := event as InputEventMouseButton
    if button == null or button.button_index != MOUSE_BUTTON_LEFT:
        return false
    if not button.pressed:
        var was_held := _holding
        _holding = false
        if was_held and _left <= 0.0:
            set_process_input(false)
        return was_held
    if _left <= 0.0:
        return false
    for i in _outlines.size():
        if _outlines[i].has_point(button.position):
            _holding = true
            _flash = FLASH_SECONDS
            _flashing = i
            queue_redraw()
            return true
    return false


## Runs ahead of the GUI, so a swallowed press never reaches the canvas under it.
func _input(event: InputEvent) -> void:
    if swallows(event):
        get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
    _left = maxf(0.0, _left - delta)
    _flash = maxf(0.0, _flash - delta)
    if _left <= 0.0:
        _clear_outlines()
        return
    queue_redraw()


func _show_outlines(rects: Array[Rect2]) -> void:
    _outlines = rects
    _left = OUTLINE_SECONDS if not rects.is_empty() else 0.0
    _flash = 0.0
    _flashing = -1
    set_process(_left > 0.0)
    set_process_input(_left > 0.0 or _holding)
    queue_redraw()


## Ends the outlines. A press still held keeps `_input` on until its release.
func _clear_outlines() -> void:
    _outlines = []
    _left = 0.0
    _flash = 0.0
    _flashing = -1
    set_process(false)
    set_process_input(_holding)
    queue_redraw()


func _draw() -> void:
    if _left <= 0.0:
        return
    var fade := _left / OUTLINE_SECONDS
    var edge := _edge.border_color
    var width := float(SaUI.px(OUTLINE_WIDTH))
    var origin := global_position
    for i in _outlines.size():
        var local := Rect2(_outlines[i].position - origin, _outlines[i].size)
        if _flash > 0.0 and i == _flashing:
            draw_rect(local, Color(edge, 0.25), true)
            draw_rect(local, edge, false, width * 2.0)
        else:
            draw_rect(local, Color(edge, fade), false, width)


func _place_message() -> void:
    if _panel == null:
        return
    var margin := float(SaUI.px(CORNER_MARGIN))
    _panel.position = Vector2(margin, size.y - _panel.size.y - margin)
