## The slot a row of the top bar puts its controls in: scrolls without
## showing a scrollbar, and says there is more with a fade at the edge.
##
## A row that does not fit scrolls, and the scrolling blends in, because a
## scrollbar there looks like a mistake rather than a control. So the bar is
## hidden, the wheel still scrolls, a drag on empty space
## scrolls, and whichever edge has content beyond it carries a fade into the
## bar's own colour, which reads as design rather than overflow.
##
## A fade alone reads as design so well that a painter looking straight at the
## bar misses the controls past it. So each fade carries
## an arrow pointing at what is past it, in the text colour, and a press on the
## arrow scrolls the slot a page that way.
##
## A Control around a ScrollContainer rather than a ScrollContainer, because a
## ScrollContainer lays out every child it has and the fades must sit on top of
## the content, outside the scroll.
##
## The slot asks for its content's height and no width. A plain Control asks for
## nothing, so a row holding only a slot would be zero tall: the bar's panel
## would not grow for it, and the scroll inside, which a Control cannot be
## smaller than, would hang below the bar over the canvas with no background
## behind it. A row with menus beside its slot hides this, because they give
## the row a height.
class_name SaRowSlot
extends Control

## Logical pixels of fade at an edge.
const FADE_WIDTH: int = 28

## Logical pixels of the arrow a fade carries, measured in from the slot's edge,
## and how tall its chevron is drawn.
const ARROW_WIDTH: int = 14
const ARROW_HEIGHT: int = 10

## The second row's height, logical, measured in the running app: its tallest
## controls, Edit Brush and the rotation's reset, ask for 33 at every UI scale,
## and the row is no taller, as Krita's is. A floor, so a larger font grows it.
const SECOND_ROW_HEIGHT: int = 33

## The least the slot asks for in height, logical. Zero asks for the
## content's own, which is what the first row wants.
var min_height: int = 0:
    set(value):
        min_height = value
        update_minimum_size()

var scroll: ScrollContainer
var _fade_left: TextureRect
var _fade_right: TextureRect
var _dragging: bool = false


func _init(bar_color: Color = SaTheme.palette.bg_primary) -> void:
    mouse_filter = Control.MOUSE_FILTER_PASS
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL

    scroll = SaMake.scroll(self, "Scroll")
    scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
    scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.mouse_filter = Control.MOUSE_FILTER_PASS

    _fade_left = _make_fade(bar_color, true)
    _fade_right = _make_fade(bar_color, false)
    add_child(_fade_left)
    add_child(_fade_right)

    scroll.minimum_size_changed.connect(update_minimum_size)
    scroll.get_h_scroll_bar().value_changed.connect(_update_fades)
    scroll.get_h_scroll_bar().changed.connect(_update_fades.bind(0.0))
    resized.connect(_update_fades.bind(0.0))
    EventBus.theme_changed.connect(func(_id: String) -> void: _recolor(SaTheme.palette.bg_primary))


## The fades go into the bar's colour, so a theme switch recolours them.
func _recolor(bar_color: Color) -> void:
    var clear := Color(bar_color.r, bar_color.g, bar_color.b, 0.0)
    for pair: Array in [[_fade_left, true], [_fade_right, false]]:
        var texture := (pair[0] as TextureRect).texture as GradientTexture2D
        if texture == null:
            continue
        texture.gradient.set_color(0, bar_color if pair[1] else clear)
        texture.gradient.set_color(1, clear if pair[1] else bar_color)
        (pair[0] as TextureRect).get_node("Arrow").queue_redraw()


## As tall as the content, and as narrow as the row allows, since scrolling
## sideways is the point of the slot.
func _get_minimum_size() -> Vector2:
    return Vector2(0.0, maxf(scroll.get_combined_minimum_size().y, float(SaUI.px(min_height))))


## Puts *node* in the scroll. What a caller adding content should use.
func add_content(node: Control) -> void:
    scroll.add_child(node)


## How far the content is scrolled, in logical pixels.
func scroll_offset() -> int:
    return scroll.scroll_horizontal


func _make_fade(bar_color: Color, on_left: bool) -> TextureRect:
    var gradient := Gradient.new()
    var clear := Color(bar_color.r, bar_color.g, bar_color.b, 0.0)
    gradient.set_color(0, bar_color if on_left else clear)
    gradient.set_color(1, clear if on_left else bar_color)
    var texture := GradientTexture2D.new()
    texture.gradient = gradient
    texture.width = 64
    texture.height = 4
    var fade := TextureRect.new()
    fade.name = "FadeLeft" if on_left else "FadeRight"
    fade.texture = texture
    fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    fade.stretch_mode = TextureRect.STRETCH_SCALE
    fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    fade.visible = false
    if on_left:
        fade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
        fade.offset_right = float(SaUI.px(FADE_WIDTH))
    else:
        fade.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
        fade.offset_left = -float(SaUI.px(FADE_WIDTH))
    fade.add_child(_make_arrow(on_left))
    return fade


## The arrow a fade carries, at the slot's outer edge, so a row that scrolls
## says so to anyone looking at it. A child of the fade, so the one rule in
## `_update_fades` shows and hides both.
##
## It takes the press rather than letting it through. Under the arrow is the
## faded end of whatever control the edge cut, and an arrow that looks like a
## button and moves the slider beneath it instead would be worse than no arrow.
func _make_arrow(on_left: bool) -> Control:
    var arrow := Control.new()
    arrow.name = "Arrow"
    arrow.mouse_filter = Control.MOUSE_FILTER_STOP
    arrow.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    if on_left:
        arrow.set_anchors_preset(Control.PRESET_LEFT_WIDE)
        arrow.offset_right = float(SaUI.px(ARROW_WIDTH))
    else:
        arrow.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
        arrow.offset_left = -float(SaUI.px(ARROW_WIDTH))
    arrow.draw.connect(_draw_arrow.bind(arrow, on_left))
    arrow.gui_input.connect(_on_arrow_input.bind(on_left))
    return arrow


## A chevron pointing out of the slot, in the theme's text colour, read when
## drawn so a theme switch needs only a redraw.
func _draw_arrow(arrow: Control, on_left: bool) -> void:
    var half := float(SaUI.px(ARROW_HEIGHT)) / 2.0
    var middle := arrow.size / 2.0
    var tip := middle.x + (-half if on_left else half) / 2.0
    var back := middle.x - (-half if on_left else half) / 2.0
    var points := PackedVector2Array([Vector2(back, middle.y - half), Vector2(tip, middle.y), Vector2(back, middle.y + half)])
    arrow.draw_polyline(points, SaTheme.palette.text_primary, float(SaUI.px(2)), true)


## A press on an arrow scrolls towards it by what the slot shows less the fade,
## so the control the fade was covering is the first one read. The wheel over
## the arrow, and a touchpad's pan, scroll the way they do over the rest of the
## row, which the stop filter would otherwise swallow: a `ScrollContainer` with
## its vertical scroll disabled moves an eighth of a page a notch, down or right
## being onwards.
func _on_arrow_input(event: InputEvent, on_left: bool) -> void:
    var bar := scroll.get_h_scroll_bar()
    var moved := SaStep.notches(event)
    if moved != Vector2.ZERO:
        bar.value += bar.page / 8.0 * (moved.x + moved.y)
        return
    var button := event as InputEventMouseButton
    if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
        var step := maxf(1.0, bar.page - float(SaUI.px(FADE_WIDTH)))
        bar.value += -step if on_left else step


## A fade shows at the edge that has content past it, and only then.
func _update_fades(_value: float = 0.0) -> void:
    var bar := scroll.get_h_scroll_bar()
    var overflow := bar.max_value > bar.page + 0.5
    _fade_left.visible = overflow and bar.value > 0.5
    _fade_right.visible = overflow and bar.value + bar.page < bar.max_value - 0.5


## A drag on empty space scrolls. Controls stop the event before it gets here,
## so only the gaps between them reach this.
func _gui_input(event: InputEvent) -> void:
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        _dragging = button.pressed
        if _dragging:
            accept_event()
        return
    var motion := event as InputEventMouseMotion
    if motion != null and _dragging:
        scroll.scroll_horizontal -= int(motion.relative.x)
        accept_event()
