## The note mode's marks on one Window: the box round the control under the
## pointer, the outline of the one a click froze, and the small text box the
## note is typed into.
##
## One per Window, the way CursorOverlay is, because a Control can only draw
## inside its own viewport. An embedded docker is drawn on a canvas layer above
## every control of the root window, whatever z_index a root control asks for,
## so a highlight drawn from the root would sit under the docker it marks.
##
## The overlay ignores the mouse, so the control it marks is still the one the
## GUI reports as hovered. Its `_input` is what swallows the click that freezes
## a note: with subwindows embedded the viewport forwards an event to the
## focused subwindow before any root node's `_input` runs, so the node that
## intercepts a click on a docker has to live in that docker's window, and a
## node's `_input` is the one place the handled flag survives until GUI
## dispatch. The mode itself is one node
## in the main tree, and every overlay reports to it.
class_name SaNoteOverlay
extends Control

const NODE_NAME := "SaNoteOverlay"

## Sits under the cursor ring, which draws at 4096, so a note on the canvas
## still shows the brush ring the painter saw.
const Z_INDEX := 4095

const FILL := Color(0.95, 0.61, 0.07, 0.16)
const INK := Color("#F39C12")
const FROZEN_FILL := Color(0.27, 0.77, 0.43, 0.14)
const FROZEN_INK := Color("#45C46D")
const TAG_INK := Color(0.06, 0.08, 0.07, 1.0)

## The region a shift-drag frames, drawn in the blue that is neither of the two
## above, so it reads as a third thing rather than a second highlight.
const REGION_FILL := Color(0.24, 0.58, 0.94, 0.12)
const REGION_INK := Color("#3D93F0")

## Logical size of the text box, before the theme scales it.
const BOX_WIDTH: int = 360
const BOX_TEXT_HEIGHT: int = 72
const BOX_GAP: int = 6

## The smallest the box may be dragged to, and the floor a stored size has to
## clear to be a preference rather than a corrupt file.
const BOX_MIN_WIDTH: int = 240
const BOX_MIN_HEIGHT: int = 140

## Room under the buttons for the resize grip, which is anchored to the corner
## the Save button would otherwise fill.
const BOX_GRIP_MARGIN: int = 22

## What a press on the box took hold of.
const GRAB_NONE: int = 0
const GRAB_MOVE: int = 1
const GRAB_SIZE: int = 2

## Who hears the clicks and keys this window sees while the mode is on.
var mode: Node = null

## The window this overlay moves and resizes: the note box, for the overlay
## inside it, and null for every other one.
var drags: Window = null

var _rect := Rect2()
var _label := ""
var _frozen := false
var _region := Rect2()
var box: Window = null
var _text: TextEdit = null

## What the press on the box grabbed, and where it grabbed it.
var _grab := GRAB_NONE
var _grab_from := Vector2.ZERO
var _grab_size := Vector2.ZERO


## Adds an overlay to `window` unless it already has one. Safe to call repeatedly.
static func attach_to(window: Window) -> SaNoteOverlay:
    if window == null:
        return null
    var existing := find_in(window)
    if existing != null:
        return existing
    var overlay := SaNoteOverlay.new()
    overlay.name = NODE_NAME
    window.add_child(overlay)
    return overlay


static func find_in(window: Window) -> SaNoteOverlay:
    return window.get_node_or_null(NODE_NAME) as SaNoteOverlay if window != null else null


func _ready() -> void:
    name = NODE_NAME
    mouse_filter = MOUSE_FILTER_IGNORE
    set_anchors_preset(Control.PRESET_FULL_RECT)
    top_level = true
    z_as_relative = false
    z_index = Z_INDEX
    set_process_input(true)


## Every event this window sees, ahead of its GUI. Handed to the mode, which
## says whether it took it.
func _input(event: InputEvent) -> void:
    if _drive_box(event):
        get_viewport().set_input_as_handled()
        return
    if mode == null or not mode.has_method("handle_window_input"):
        return
    if mode.handle_window_input(event, get_window()):
        get_viewport().set_input_as_handled()


## Moves the note box by its title and resizes it by its corner, from the
## events its own window sees.
##
## Here rather than on the bar's `gui_input`, which is where a docker's drag
## lives: an injected motion never reaches `gui_input`, so a bar wired that way is one no
## scenario can prove and no capture can photograph mid-drag. A node's `_input`
## gets the motion, which is the same reason DockerDragHandle's ALT-drag is in
## one. Everything here is in the box's own coordinates, and its position is in
## the host's, so a move is the difference between the two rather than either.
func _drive_box(event: InputEvent) -> bool:
    if drags == null:
        return false
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if not button.pressed:
            var was := _grab
            _grab = GRAB_NONE
            return was != GRAB_NONE
        _grab = _grab_at(button.position)
        _grab_from = button.position
        _grab_size = Vector2(drags.size)
        return _grab != GRAB_NONE
    var motion := event as InputEventMouseMotion
    if motion == null or _grab == GRAB_NONE:
        return false
    if _grab == GRAB_MOVE:
        # The box moves out from under the pointer, so the next event measures
        # the same grab point again and the drag corrects itself.
        drags.position += Vector2i((motion.position - _grab_from).round())
    else:
        var wanted := _grab_size + motion.position - _grab_from
        drags.size = Vector2i(wanted.round()).max(drags.min_size)
    return true


## What the point is on: the corner grip, the title bar, or neither. Read off
## the box's own children, because the overlay that drives the box is not the
## one that built it.
func _grab_at(point: Vector2) -> int:
    var grip := drags.find_child("Resizer", true, false) as Control
    if grip != null and grip.get_global_rect().has_point(point):
        return GRAB_SIZE
    var bar := drags.find_child("DragHandle", true, false) as Control
    if bar != null and bar.get_global_rect().has_point(point):
        return GRAB_MOVE
    return GRAB_NONE


## Marks the control the pointer is over. Called on every change, not every frame.
func highlight(rect: Rect2, label: String) -> void:
    _rect = rect
    _label = label
    _frozen = false
    queue_redraw()


## Marks the control a click froze, in the colour that says "this one".
func freeze(rect: Rect2, label: String) -> void:
    _rect = rect
    _label = label
    _frozen = true
    queue_redraw()


func clear() -> void:
    _rect = Rect2()
    _label = ""
    _frozen = false
    close_box()
    queue_redraw()


## Draws the region a shift-drag is framing, given in the root viewport's
## coordinates. Kept apart from the highlight, because the pointer goes on
## marking controls while the region stands, and `clear()` is called on every
## window the pointer is not in.
func show_region(rect_in_root: Rect2) -> void:
    var wanted := _from_host(rect_in_root) if rect_in_root.size != Vector2.ZERO else Rect2()
    if wanted == _region:
        return
    _region = wanted
    queue_redraw()


func clear_region() -> void:
    show_region(Rect2())


func has_mark() -> bool:
    return _rect.size != Vector2.ZERO


func _draw() -> void:
    if _region.size != Vector2.ZERO:
        draw_rect(_region, REGION_FILL, true)
        draw_rect(_region, REGION_INK, false, 1.0)
    if not has_mark():
        return
    var ink := FROZEN_INK if _frozen else INK
    draw_rect(_rect, FROZEN_FILL if _frozen else FILL, true)
    draw_rect(_rect.grow(1.0), ink, false, 2.0)
    if _label.is_empty():
        return
    # The tag names the node, because the node path is what the note carries
    # and what a reader of the note sees. Above the control when there is room, inside
    # its top-left corner when it is at the top of the window.
    var font := get_theme_default_font()
    var font_size := SaUI.font_size_for(SaUI.fraction_of(11))
    var pad := SaUI.pxf(3.0)
    var text_size := font.get_string_size(_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
    var tag_size := text_size + Vector2(pad * 2.0, pad * 2.0)
    var tag_pos := _rect.position - Vector2(0.0, tag_size.y + 1.0)
    if tag_pos.y < 0.0:
        tag_pos = _rect.position + Vector2(1.0, 1.0)
    draw_rect(Rect2(tag_pos, tag_size), ink, true)
    var baseline := tag_pos + Vector2(pad, pad + font.get_ascent(font_size))
    draw_string(font, baseline, _label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, TAG_INK)


## Opens the text box near `near`, with `initial` already in it.
##
## The box is a small Window rather than a child of this control, because an
## embedded docker is a viewport of its own and a box drawn inside a
## sixty-pixel toolbox is cut off at its edge. A Window is embedded by the root
## whatever it is a child of, sits on the subwindow layer above every docker,
## and takes the keyboard for its text. Built once per open and freed on close,
## so a second note never carries the first one's text.
##
## Borderless at the Godot level and bordered by Sara: the engine's title bar
## sits outside the window's own viewport, where no Control can draw. The strip along the top is a Sara drag bar
## with the title in it, so the box moves by its title the way a dialog does,
## and the corner carries a docker's resize grip. The size it is left at is
## kept, since a note long enough to need a bigger box is usually followed by
## another one.
func open_box(near: Rect2, title: String, initial: String = "") -> void:
    close_box()
    box = Window.new()
    box.name = "NoteBox"
    box.title = title
    box.borderless = true
    box.unresizable = false
    box.transient = false
    box.visible = false
    add_child(box)
    # Every docker and dialog carries one, and a window without one is where the
    # pen has no arrow and a mouse is never heard, so the last pen's word stood
    # and the system cursor stayed hidden over the box for both.
    CursorOverlay.attach_to(box)

    # The grip and the drag handle anchor themselves inside a Control, and a
    # Window is not one.
    var shell := Control.new()
    shell.name = "Shell"
    shell.set_anchors_preset(Control.PRESET_FULL_RECT)
    box.add_child(shell)

    var panel := PanelContainer.new()
    panel.name = "Panel"
    panel.set_anchors_preset(Control.PRESET_FULL_RECT)
    var style := StyleBoxFlat.new()
    SaTheme.bind(style, {"bg_color": "bg_panel", "border_color": "border_drag"})
    style.set_border_width_all(2)
    style.set_content_margin_all(float(SaUI.px(8)))
    # The grip draws in the bottom corner, which is where Save sits.
    style.content_margin_bottom = float(SaUI.px(BOX_GRIP_MARGIN))
    panel.add_theme_stylebox_override("panel", style)
    shell.add_child(panel)

    var column := SaMake.column(panel, "Column", 6)

    var bar := _build_drag_bar(title)
    column.add_child(bar)

    _text = TextEdit.new()
    _text.name = "Text"
    _text.text = initial
    _text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    _text.custom_minimum_size = Vector2(SaUI.px(BOX_WIDTH), SaUI.px(BOX_TEXT_HEIGHT))
    _text.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _text.placeholder_text = tr("What is wrong, or what was expected")
    column.add_child(_text)

    var row := SaMake.row(column, "Buttons", SaTheme.GAP)
    var hint := SaMake.label(row, "Hint", tr("Ctrl+Enter saves, Escape cancels"))
    SaUI.size_text(hint, SaUI.fraction_of(10))
    SaTheme.bind_font(hint, "text_muted")
    hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    SaMake.button(row, "Export", tr("Export")).pressed.connect(func() -> void: _tell_mode("export"))
    SaMake.button(row, "Cancel", tr("Cancel")).pressed.connect(func() -> void: _tell_mode("cancel"))
    SaMake.button(row, "Save", tr("Save")).pressed.connect(func() -> void: _tell_mode("save"))

    # The grip draws the corner and hears nothing: the box is moved and resized
    # by the overlay inside it, which is the only path an injected event can
    # take (see `_drive_box`).
    var grip := DockerResizer.new(box)
    grip.name = "Resizer"
    grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
    shell.add_child(grip)

    # Built after the theme pass, so it has to be themed by whoever builds it,
    # or it keeps the engine's default font.
    SaUI.apply_ui_theme(panel)
    var smallest := Vector2(float(SaUI.px(BOX_MIN_WIDTH)), float(SaUI.px(BOX_MIN_HEIGHT)))
    smallest = smallest.max(panel.get_combined_minimum_size())
    box.min_size = Vector2i(smallest.ceil())
    box.size = Vector2i(box_size_for(smallest, SaSettings.note_box_size).ceil())
    box.position = Vector2i(_box_position(_in_host(near), Vector2(box.size)))
    SaNoteOverlay.attach_to(box).drags = box
    box.visible = true
    # The window first, then the field in it. A control's focus is its own
    # window's only, and with subwindows off the box is a window of the
    # operating system that a pen tap under WinTab left without the focus, so
    # the note took no typing until the mouse clicked it.
    box.grab_focus()
    _text.grab_focus()
    _text.set_caret_line(_text.get_line_count() - 1)
    _text.set_caret_column(_text.get_line(_text.get_line_count() - 1).length())


## The size the box opens at: the one it was last left at, never below what its
## own contents need. A stored size smaller than that is a corrupt file rather
## than a preference, and is ignored whole
## rather than per axis, since half of a corrupt pair is not a preference either.
static func box_size_for(smallest: Vector2, stored: Vector2i) -> Vector2:
    if stored.x < BOX_MIN_WIDTH or stored.y < BOX_MIN_HEIGHT:
        return smallest
    return smallest.max(Vector2(stored))


## The title strip, which is what the box is dragged by.
func _build_drag_bar(bar_title: String) -> PanelContainer:
    var bar := PanelContainer.new()
    bar.name = "DragHandle"
    bar.custom_minimum_size = Vector2(0.0, float(SaUI.px(DockerUtils.BASE_DRAG_H)))
    bar.add_theme_stylebox_override("panel", SaTheme.make_drag_bar_style(false))

    var label := SaGrip.before(SaMake.label(bar, "TitleLabel", bar_title))
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.add_theme_color_override("font_color", SaTheme.palette.text_primary)
    return bar


## A rect of this window in the coordinates the box's position is written in:
## the host viewport's logical space for an embedded window, which is what an
## embedded window's own position is measured in.
func _in_host(rect: Rect2) -> Rect2:
    var window := get_window()
    if window == null or window == get_tree().root or not window.is_embedded():
        return rect
    return Rect2(rect.position + Vector2(window.position), rect.size)


## The inverse: a rectangle the root viewport measures, in this window's own
## coordinates, so every overlay can draw one region from one rectangle.
func _from_host(rect: Rect2) -> Rect2:
    var window := get_window()
    if window == null or window == get_tree().root or not window.is_embedded():
        return rect
    return Rect2(rect.position - Vector2(window.position), rect.size)


## Below the control when it fits, above it otherwise, and never off the host.
func _box_position(near: Rect2, box_size: Vector2) -> Vector2:
    var bounds := get_tree().root.get_visible_rect()
    var gap := SaUI.pxf(float(BOX_GAP))
    var at := Vector2(near.position.x, near.end.y + gap)
    if at.y + box_size.y > bounds.end.y:
        at.y = near.position.y - gap - box_size.y
    at.x = clampf(at.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - box_size.x))
    at.y = clampf(at.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - box_size.y))
    return at.round()


func close_box() -> void:
    if box == null:
        return
    _remember_box_size()
    box.queue_free()
    box = null
    _text = null


## Keeps the size the box was left at. Logical units, because `Window.size` is
## physical for a real OS window and logical for an embedded one, and the box
## is rebuilt from scratch for every note.
func _remember_box_size() -> void:
    if box == null or not box.visible:
        return
    var factor := maxf(SaUI.window_scale(box), 0.001)
    var logical := Vector2i((Vector2(box.size) / factor).round())
    if logical.x < BOX_MIN_WIDTH or logical.y < BOX_MIN_HEIGHT:
        return
    if logical != SaSettings.note_box_size:
        SaSettings.note_box_size = logical


func box_open() -> bool:
    return box != null


func box_text() -> String:
    return _text.text if _text != null else ""


func set_box_text(text: String) -> void:
    if _text != null:
        _text.text = text


func _tell_mode(what: String) -> void:
    if mode != null and mode.has_method("box_pressed"):
        mode.box_pressed(what)
