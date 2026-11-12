## The six dots Sara draws before a docker's or a window's title, as a grip.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The braille six-dot sign drawn by Sara: two columns of three dots, sized by
## `SaUI` and coloured from the palette, never a font glyph. None of the four
## families Sara ships holds U+283F, so the glyph would come from whatever
## fallback the system has, and a font that
## lacks it draws a box. This control draws circles and no text, so no font
## can turn it into one.
##
## `SaGrip.before(label)` is the one call. It lays the grip over the left of
## the title label, which keeps room for it with a left margin, and the label
## holds the title alone: a retitle writes the words and nothing else. The grip
## follows the label's alignment, standing as far before the first letter as the
## letter stands from the margin.
class_name SaGrip
extends Control

## The node's name under the label, which is how a second call finds the first.
const NODE_NAME := "Grip"

## The dots' columns and rows.
const COLUMNS := 2
const ROWS := 3

## The diameter of a dot and the distance between two dots' centres, in logical
## units. The window's content scale makes them twice as large at scale 2.
const DOT := 3
const PITCH := 5

## The space between the grip and the first letter, in logical units.
const GAP := 5

## The palette key the dots take, so a theme switch recolours them.
const COLOR_KEY := "text_primary"


## Puts the grip before *label*'s title and returns the label, so the call
## wraps the one that makes it. A label that has one already keeps it, so the
## call may be made again, and *wanted* false leaves the label as it is, which is
## a vertical docker title's or an empty one's.
static func before(label: Label, wanted := true) -> Label:
    if wanted and label.get_node_or_null(NODE_NAME) == null:
        var grip := SaGrip.new()
        grip.name = NODE_NAME
        label.add_child(grip)
    return label


## The width of the six dots in logical units.
static func dots_width() -> int:
    return SaUI.px(PITCH) * (COLUMNS - 1) + SaUI.px(DOT)


## The height of the six dots in logical units.
static func dots_height() -> int:
    return SaUI.px(PITCH) * (ROWS - 1) + SaUI.px(DOT)


## The room the title's label keeps on its left for the grip.
static func room() -> int:
    return dots_width() + SaUI.px(GAP)


## The colour the dots are drawn in under the palette that is in force.
static func color() -> Color:
    return SaTheme.palette.get(COLOR_KEY) as Color


## Where the right edge of the dots sits in the label's coordinates.
func dots_right() -> float:
    return dots_left() + float(dots_width())


## Where the left edge of the dots sits in the label's coordinates.
func dots_left() -> float:
    var label := get_parent() as Label
    if label == null or label.text == "":
        return 0.0
    var font := label.get_theme_font("font")
    var font_size := label.get_theme_font_size("font_size")
    var text_width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
    var start := float(room())
    var bounds := label.get_character_bounds(0)
    if bounds.size.x > 0.0:
        start = maxf(start, bounds.position.x)
    else:
        match label.horizontal_alignment:
            HORIZONTAL_ALIGNMENT_CENTER:
                start = maxf(start, (label.size.x - text_width) * 0.5)
            HORIZONTAL_ALIGNMENT_RIGHT:
                start = maxf(start, label.size.x - text_width)
    return start - float(room())


func _init() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE


func _enter_tree() -> void:
    _apply_margins()
    var label := get_parent() as Label
    if label == null:
        return
    if not label.draw.is_connected(queue_redraw):
        label.draw.connect(queue_redraw)
    if not EventBus.ui_scale_changed.is_connected(_apply_margins):
        EventBus.ui_scale_changed.connect(_apply_margins)


func _exit_tree() -> void:
    if EventBus.ui_scale_changed.is_connected(_apply_margins):
        EventBus.ui_scale_changed.disconnect(_apply_margins)


func _apply_margins(_scale: float = 0.0) -> void:
    var label := get_parent() as Label
    if label == null:
        return
    var box := StyleBoxEmpty.new()
    box.content_margin_left = float(room())
    box.content_margin_right = float(room())
    label.add_theme_stylebox_override("normal", box)


func _draw() -> void:
    var label := get_parent() as Label
    if label == null or label.text == "":
        return
    var left := dots_left()
    var top := (label.size.y - float(dots_height())) * 0.5
    var radius := float(SaUI.px(DOT)) * 0.5
    for column in COLUMNS:
        for row in ROWS:
            var centre := Vector2(left + radius + float(column * SaUI.px(PITCH)), top + radius + float(row * SaUI.px(PITCH)))
            draw_circle(centre, radius, color())
