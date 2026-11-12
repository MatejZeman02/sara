## What a switched-off mask's picture wears: a veil of the row's ground over
## it and a red cross, Photoshop's mark, so a mask that is off reads at a
## glance on its row and not only as a fainter grey.
##
## A child of the mask's picture rather than part of its `_draw`, because the
## mark says the mask's state and not what the mask holds, and the veil is the
## dimming, so nothing dims the cross with it. It takes no pointer, so the press
## and the tooltip stay the picture's.
class_name SaMaskOffMark
extends Control

## How much of the picture shows through the veil, the dimming the row's own
## toggles use for a flag that is off.
const SHOWN_THROUGH: float = 0.3

## Photoshop's red, read the same on the light themes and the dark ones.
const CROSS := Color(0.9, 0.18, 0.15)

## How thick the cross is, and how far inside the rim it stops, in logical units.
const CROSS_WIDTH: float = 2.0
const CROSS_INSET: float = 3.0


func _init() -> void:
    name = "MaskOffMark"
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_preset(Control.PRESET_FULL_RECT)
    visible = false
    # The veil reads the palette, and a theme swap moves nothing here on its own.
    if EventBus:
        EventBus.theme_changed.connect(func(_id: String) -> void: queue_redraw())


## Puts the mark on or takes it off, *off* being the mask switched off.
func show_off(off: bool) -> void:
    if visible != off:
        visible = off


func _draw() -> void:
    var picture := get_parent() as SaLayerThumbnail
    var rim := picture.rim_rect() if picture != null else Rect2(Vector2.ZERO, size)
    if rim.size.x <= 0.0 or rim.size.y <= 0.0:
        return
    draw_rect(rim, Color(SaTheme.palette.bg_secondary, 1.0 - SHOWN_THROUGH))
    var cross := rim.grow(-SaUI.pxf(CROSS_INSET))
    var width := SaUI.pxf(CROSS_WIDTH)
    draw_line(cross.position, cross.end, CROSS, width, true)
    draw_line(Vector2(cross.end.x, cross.position.y), Vector2(cross.position.x, cross.end.y), CROSS, width, true)
