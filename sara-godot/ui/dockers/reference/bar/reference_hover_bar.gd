## The hover bar of a reference picture: the four toggles, flip, grey, crop
## and on top, as small icon buttons in a row over the picture under the
## pointer, which is how PureRef puts a picture's own controls on the picture
## rather than in a menu.
##
## A class of its own in `bar/` since the board's selection took the docker's folder
## past its size: the bar is a row of buttons and where it stands, and the board
## view, which knows the pointer, the pictures and the selection, says where it
## goes through `put_over` and `take_down`. Its row is a child of that view, made
## there and filled here, so the view's draw order and its hit test are
## unchanged. A press on a toggle, and the pointer reaching or leaving a button,
## go back to the view through the three callables it hands the constructor.
class_name ReferenceHoverBar
extends RefCounted

## The four toggles, in the order they sit on the bar: the id the view's `toggle`
## takes, the icon, the button's name, and the tooltip. A mirror, a half filled circle, a crop mark and a pin.
const TOGGLES: Array = [
    ["flip", "symmetry_horizontal", "Flip", "Mirror the picture left to right"],
    ["greyscale", "greyscale", "Grey", "Show the picture without its colour"],
    ["crop", "crop", "Crop", "Drag a rectangle to keep, or press again to show the whole picture"],
    ["on_top", "pin", "Top", "Keep this image on top."],
]

## Logical side of the bar's square buttons, small so the picture under them
## stays seen.
const BAR_H: int = 14

## Logical side of the icon inside one of the bar's buttons.
const BAR_ICON: int = 10

## How many bar heights a picture has to be tall, and how much wider than the
## bar, before the bar stands on it rather than beside it.
const BAR_ROOM: float = 2.0

## The row of buttons, a child of the view, and its buttons by toggle id.
var row: HBoxContainer
var _buttons: Dictionary = {}


## Fills *bar_row* with the toggles. *on_toggle* takes a toggle's id, and *entered*
## and *left* are the view's own pointer enter and exit: the buttons stop the
## pointer, so the view's own enter and exit end at the bar's edge and the bar
## has to say when the pointer is on it, or it would go down as the pointer
## reached for it.
func _init(bar_row: HBoxContainer, on_toggle: Callable, entered: Callable, left: Callable) -> void:
    row = bar_row
    row.visible = false
    for entry: Array in TOGGLES:
        var word := tr(String(entry[2]), "a reference picture's toggle")
        var button := SaMake.button(row, String(entry[0]).capitalize(), "", "%s\n%s" % [word, tr(String(entry[3]))])
        button.toggle_mode = true
        SaTheme.make_toggle(button)
        _shrink(button)
        button.focus_mode = Control.FOCUS_NONE
        SaUI.set_button_icon(button, String(entry[1]), word)
        button.add_theme_constant_override("icon_max_width", SaUI.px(BAR_ICON))
        SaUI.size_text(button, SaUI.fraction_of(8))
        button.custom_minimum_size = Vector2(SaUI.px(BAR_H), SaUI.px(BAR_H))
        var id := String(entry[0])
        button.toggled.connect(func(_pressed: bool) -> void: on_toggle.call(id))
        button.mouse_entered.connect(entered)
        button.mouse_exited.connect(left)
        _buttons[id] = button


## The toggle boxes `SaTheme.make_toggle` gave *button*, with the content margin
## one pixel, so the button is the icon's size and not the text button's. The
## pressed box keeps its own colour, which is how a pressed toggle reads.
static func _shrink(button: Button) -> void:
    for state: String in SaTheme.TOGGLE_STATES:
        var style := button.get_theme_stylebox(state) as StyleBoxFlat
        if style != null and button.has_theme_stylebox_override(state):
            style.set_content_margin_all(float(SaUI.px(1)))


## The bar up over a picture shown in *rect* of a view of *room*, with its
## buttons pressed as *flags* says, keyed by toggle id.
func put_over(rect: Rect2, room: Vector2, flags: Dictionary) -> void:
    row.visible = true
    # Its own least size, set rather than waited for, because a container
    # outside the tree, as in a suite, is never sorted.
    row.size = row.get_combined_minimum_size()
    row.position = place(rect, row.size, room)
    for id: String in _buttons:
        (_buttons[id] as Button).set_pressed_no_signal(bool(flags[id]))


## The bar down, over no picture.
func take_down() -> void:
    row.visible = false


## Where the bar of *bar_size* stands for a picture shown in *rect*, in a view
## of *room*. On the picture's top edge when the picture is `BAR_ROOM` times
## the bar's height and wider than the bar by a margin each side, so most of
## the picture is still seen under it. Otherwise just outside the picture,
## touching it so the pointer passes from the picture onto the bar without
## crossing the board: above, or below when there is no room above. Kept
## inside the view either way, so a picture that runs off the edge still shows
## its whole bar.
static func place(rect: Rect2, bar_size: Vector2, room: Vector2) -> Vector2:
    var margin := SaUI.pxf(2)
    var fits := rect.size.x >= bar_size.x + margin * 2.0 and rect.size.y >= bar_size.y * BAR_ROOM + margin
    var at := rect.position + Vector2(margin, margin)
    if not fits:
        at = Vector2(rect.position.x, rect.position.y - bar_size.y)
        if at.y < 0.0:
            at.y = rect.end.y
    var spare := room - bar_size
    return Vector2(clampf(at.x, 0.0, maxf(spare.x, 0.0)), clampf(at.y, 0.0, maxf(spare.y, 0.0)))


## Whether *at*, a point in the view, is over the bar while it is up.
func covers(at: Vector2) -> bool:
    return row.visible and Rect2(row.position, row.size).has_point(at)
