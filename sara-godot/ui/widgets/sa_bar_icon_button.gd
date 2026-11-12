## The one size of an icon button on the bar's second row: the erase toggle,
## both mirrors, the rotation's reset and any toggle a tool declares with an
## icon. Each of them sized itself from `SaUI.BASE_ICON_SIZE` in its own file,
## 24 by 22 logical pixels with a 16 pixel icon, which a pen tip on a tablet
## barely hit and a stranger could not read.
##
## The window's own buttons at the top right are not shaped here, they keep
## their size.
##
## A widget rather than a bar file's method, because four files across
## `ui/tool_options` and `ui/top_bar` build these buttons and one place has to
## say how large they are.
class_name SaBarIconButton
extends RefCounted

## The button's width, in logical pixels. Krita's bar on a tablet
## leaves about as much room either side of an icon as the icon is wide, and a
## fingertip is about this wide too.
const WIDTH: int = 44

## The least height of the button, in logical pixels, the least every control
## on the row asks for. The row makes it taller, see `shape`.
const HEIGHT: int = SaUI.BASE_ICON_SIZE + 2

## The icon's side, in logical pixels, a fifth larger than the theme's cap of
## 20 and half again the 16 the old 24 pixel width left once the box's margins
## were taken. Krita's icons on a tablet are about as tall as its
## Opacity and Size sliders, and a slider on this bar is about this tall.
const ICON: int = 24

## The meta a shaped button carries, so a dump finds every one of them.
const META := &"sa_bar_icon_button"


## Gives *button* the icon called *icon_name*, or *fallback_text* when the
## icon set has none, at the bar's icon size, centred with the room at both
## sides. It fills the row's height rather than centring at its own, so it
## stands as tall as Keep Blend Mode beside it, whose words make it the row's
## tallest, and a row shorter than the icon draws the icon smaller rather than
## clipping it.
static func shape(button: Button, icon_name: String, fallback_text: String = "") -> void:
    if button == null:
        return
    SaUI.set_button_icon(button, icon_name, fallback_text)
    button.custom_minimum_size = Vector2(SaUI.px(WIDTH), SaUI.px(HEIGHT))
    button.size_flags_vertical = Control.SIZE_FILL
    button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
    button.expand_icon = true
    button.add_theme_constant_override("icon_max_width", SaUI.px(ICON))
    button.set_meta(META, true)


## Every shaped button under *under* that is on screen, by name, with its rect
## in its window and the icon's side, for a capture to set beside a shot. Sizes
## are physical pixels, as a shot's are.
static func report(under: Node) -> Dictionary:
    var out := {}
    if under == null:
        return out
    for node: Node in under.find_children("*", "Button", true, false):
        var button := node as Button
        if not button.has_meta(META) or not button.is_visible_in_tree():
            continue
        var rect := button.get_global_rect()
        var box := button.get_theme_stylebox("normal")
        var room := rect.size - (box.get_minimum_size() if box != null else Vector2.ZERO)
        out[String(button.name)] = {
            "rect": {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y},
            "icon_side": mini(button.get_theme_constant("icon_max_width"), int(minf(room.x, room.y))),
            "icon": button.icon.resource_path if button.icon != null else "",
            "pressed": button.button_pressed,
        }
    return out
