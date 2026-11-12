## The foreground and background pair as one control: two overlapping squares,
## the arrows that swap them and the mark that resets them, which is where
## Krita and Photoshop both put the pair. Every target is at least `TARGET`
## logical pixels on a side, so a pen finds it without aiming.
##
## Drawn rather than assembled from two `ColorRect`s and two `Button`s,
## because the squares overlap, which a container cannot arrange without
## nested Controls that do nothing else.
##
## It shows what `SaColors` holds and changes nothing: the swap and the reset
## go out as `swap_requested` and `reset_requested`, the way `SaColorPicker` asks rather than acts, and
## whoever builds the control decides what the pair is. Following the bus is
## the display half and is the control's own, exactly as `SaRowSlot` follows
## the theme.
class_name SaColorPair
extends Control

## A gesture asked for the two colours to change places.
signal swap_requested

## A gesture asked for the pair to go back to black over white.
signal reset_requested

## The control's own height in logical pixels, which is the second row's, so the
## pair uses the height that row already had and the row does not grow. The
## pair grows sideways instead, to `width_for` this height.
const BASE_HEIGHT: int = SaRowSlot.SECOND_ROW_HEIGHT

## The smallest side, in logical pixels, of anything a press lands on: each
## square, the strip of the back square that shows, the swap mark and the
## reset mark. The Colour docker's swatches and buttons are 24 as well, so the
## pair is the same target wherever it is shown. Logical, because the window's
## content scale multiplies it at UI scale 2 the way it does every other size.
const TARGET: int = 24

## Logical pixels of breathing room around the whole thing. Above the pair
## this is what keeps the marks clear of the menu row over it.
const PAD: int = 4

## Logical pixels between the squares and the marks, and between the marks.
const GAP: int = 2

## What the control is showing. Read by the suite, since the squares are
## drawn rather than held as child nodes with a `color` to look at.
var foreground: Color = Color.BLACK
var background: Color = Color.WHITE
## The mark the pointer is over, `&"swap"` or `&"reset"`, or empty.
var _hovered: StringName = &""


func _init() -> void:
    name = "ColorPair"
    mouse_filter = Control.MOUSE_FILTER_STOP
    size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    size_flags_vertical = Control.SIZE_FILL
    custom_minimum_size = Vector2(width_for(float(BASE_HEIGHT)), float(DockerUtils.px(BASE_HEIGHT)))
    tooltip_text = tr("Foreground over background. Click the arrow or the back square to swap them (X).")

    # In `_init` rather than `_ready`, the way `SaRowSlot` takes the theme,
    # because a bar built detached for a test never enters a tree and would
    # otherwise show the defaults rather than the store.
    foreground = SaColors.foreground
    background = SaColors.background
    if not EventBus.color_picked.is_connected(_on_foreground_changed):
        EventBus.color_picked.connect(_on_foreground_changed)
    if not EventBus.background_color_changed.is_connected(_on_background_changed):
        EventBus.background_color_changed.connect(_on_background_changed)
    if not EventBus.theme_changed.is_connected(_on_theme_changed):
        EventBus.theme_changed.connect(_on_theme_changed)


## The width the pair takes at *height*: the two squares side by side with the
## back one showing a strip of `TARGET`, then the two marks, each `TARGET`
## wide, with the gaps and the padding.
static func width_for(height: float) -> float:
    var pad := float(DockerUtils.px(PAD))
    var side := maxf(float(DockerUtils.px(TARGET)), height - 2.0 * pad)
    var mark := float(DockerUtils.px(TARGET))
    var gap := float(DockerUtils.px(GAP))
    return pad + side + mark + gap + mark + gap + mark + pad


## The square's side: the whole height inside the padding, which at the second
## row's height is a little over `TARGET`.
func _side() -> float:
    return maxf(1.0, size.y - 2.0 * float(DockerUtils.px(PAD)))


## The foreground square, in front at the left.
func foreground_rect() -> Rect2:
    var pad := float(DockerUtils.px(PAD))
    var side := _side()
    return Rect2(Vector2(pad, pad), Vector2(side, side))


## The background square, behind and to the right, level with the front one
## and shifted by `TARGET`, so the strip of it that shows is the whole height
## and a pen's width and the front square's edge lies over its own. Clicking
## that strip brings it forward, which is the gesture a painter reaches for
## before the arrows. Side by side rather than corner to corner, because a
## diagonal overlap at this height left each square two thirds of the row and
## the back one a corner too small for a pen.
func background_rect() -> Rect2:
    var front := foreground_rect()
    return Rect2(front.position + Vector2(float(DockerUtils.px(TARGET)), 0.0), front.size)


## The double arrow's box, after the squares and as tall as they are, so it
## starts `PAD` below the top of the row rather than at the corner nearest the
## menus.
func swap_rect() -> Rect2:
    var back := background_rect()
    var at := Vector2(back.end.x + float(DockerUtils.px(GAP)), back.position.y)
    return Rect2(at, Vector2(float(DockerUtils.px(TARGET)), back.size.y))


## The reset mark's box, after the arrows and the same size.
func reset_rect() -> Rect2:
    var swap := swap_rect()
    return Rect2(Vector2(swap.end.x + float(DockerUtils.px(GAP)), swap.position.y), swap.size)


## Whether *point*, in the control's own coordinates, asks for a swap. The
## foreground square is tested first, because it covers part of the other one
## and clicking the colour already in use must do nothing.
func swaps_at(point: Vector2) -> bool:
    if foreground_rect().has_point(point):
        return false
    return swap_rect().has_point(point) or background_rect().has_point(point)


## Whether *point* asks for black over white.
func resets_at(point: Vector2) -> bool:
    return reset_rect().has_point(point)


## The tooltip of the target under *at*, so each target names what it does.
func _get_tooltip(at: Vector2) -> String:
    if resets_at(at):
        return tr("Reset to black and white (D)")
    if swap_rect().has_point(at):
        return tr("Swap the two colours (X)")
    return tooltip_text


func _draw() -> void:
    var border := SaTheme.palette.border_primary
    _draw_swatch(background_rect(), background, border)
    _draw_swatch(foreground_rect(), foreground, border)
    _draw_arrow(swap_rect(), _mark_color(&"swap"))
    _draw_reset(reset_rect(), _mark_color(&"reset"), border)


func _mark_color(mark: StringName) -> Color:
    return SaTheme.palette.text_primary if _hovered == mark else SaTheme.palette.text_muted


## A square of colour with the bar's own border round it, so a swatch of the
## background colour is still a square rather than a hole in the bar.
func _draw_swatch(rect: Rect2, color: Color, border: Color) -> void:
    var checker := maxf(2.0, rect.size.x * 0.25)
    if color.a < 1.0:
        draw_rect(rect, Color(0.6, 0.6, 0.6), true)
        var light := Color(0.85, 0.85, 0.85)
        var rows := int(ceilf(rect.size.y / checker))
        var cols := int(ceilf(rect.size.x / checker))
        for row in rows:
            for col in cols:
                if (row + col) % 2 == 1:
                    continue
                var cell := Rect2(rect.position + Vector2(col, row) * checker, Vector2(checker, checker))
                draw_rect(cell.intersection(rect), light, true)
    draw_rect(rect, color, true)
    draw_rect(rect, border, false, maxf(1.0, rect.size.x * 0.06))


## Two parallel arrows pointing opposite ways, which is what the docker's own
## button drew as a glyph. Lines rather than a font, so it stays sharp at
## whatever height the row gives it. Drawn in the square in the middle of the
## mark's box, which is taller than it is wide.
func _draw_arrow(box: Rect2, color: Color) -> void:
    var rect := _middle_square(box)
    var width := maxf(1.0, rect.size.x * 0.08)
    var head := rect.size.x * 0.22
    var left := rect.position.x + rect.size.x * 0.12
    var right := rect.position.x + rect.size.x * 0.88
    var top := rect.position.y + rect.size.y * 0.32
    var bottom := rect.position.y + rect.size.y * 0.68

    draw_line(Vector2(left, top), Vector2(right, top), color, width)
    draw_line(Vector2(right, top), Vector2(right - head, top - head * 0.7), color, width)
    draw_line(Vector2(right, top), Vector2(right - head, top + head * 0.7), color, width)

    draw_line(Vector2(right, bottom), Vector2(left, bottom), color, width)
    draw_line(Vector2(left, bottom), Vector2(left + head, bottom - head * 0.7), color, width)
    draw_line(Vector2(left, bottom), Vector2(left + head, bottom + head * 0.7), color, width)


## A small black square over a small white one, the mark Krita and Photoshop
## both put beside the pair for its reset. Its outline takes the mark's colour,
## so it lights under the pointer as the arrows do.
func _draw_reset(box: Rect2, color: Color, border: Color) -> void:
    var rect := _middle_square(box)
    var side := rect.size.x * 0.5
    var back := Rect2(rect.position + rect.size * 0.38, Vector2(side, side))
    var front := Rect2(rect.position + rect.size * 0.12, Vector2(side, side))
    var width := maxf(1.0, rect.size.x * 0.06)
    draw_rect(back, Color.WHITE, true)
    draw_rect(back, border, false, width)
    draw_rect(front, Color.BLACK, true)
    draw_rect(front, color, false, width)


## The largest square centred in *box*.
func _middle_square(box: Rect2) -> Rect2:
    var side := minf(box.size.x, box.size.y)
    return Rect2(box.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))


func _gui_input(event: InputEvent) -> void:
    var motion := event as InputEventMouseMotion
    if motion != null:
        _set_hovered(_mark_at(motion.position))
        return
    var button := event as InputEventMouseButton
    if button == null or button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
        return
    if swaps_at(button.position):
        swap_requested.emit()
        accept_event()
    elif resets_at(button.position):
        reset_requested.emit()
        accept_event()


## The mark under *point* that lights while the pointer is there. The back
## square swaps as the arrows do, so it lights the arrows.
func _mark_at(point: Vector2) -> StringName:
    if swaps_at(point):
        return &"swap"
    if resets_at(point):
        return &"reset"
    return &""


func _notification(what: int) -> void:
    if what == NOTIFICATION_MOUSE_EXIT:
        _set_hovered(&"")
    elif what == NOTIFICATION_RESIZED:
        queue_redraw()


func _set_hovered(value: StringName) -> void:
    if _hovered == value:
        return
    _hovered = value
    queue_redraw()


func _on_foreground_changed(color: Color) -> void:
    foreground = color
    queue_redraw()


func _on_background_changed(color: Color) -> void:
    background = color
    queue_redraw()


func _on_theme_changed(_theme_id: String) -> void:
    queue_redraw()
