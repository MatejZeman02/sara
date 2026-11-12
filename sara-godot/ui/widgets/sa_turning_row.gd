## A row of buttons that stands them one over the other when their words do
## not fit side by side.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A row of buttons in a docker that clip their words keeps the docker at its
## own width and cuts the words, and one whose buttons ask for their words
## widens the docker past its window's edge. Both are what a language 40%
## longer than English did to the Recorder, the Filters and the Palette
## dockers. This row turns instead: side by side while every child's
## words fit the share of the row it gets, each the row's width one under the
## other once one does not. English fits at every docker's shipped width, so
## it is laid out exactly as an `HBoxContainer` would lay it out.
##
## **A plain `BoxContainer`**, because an `HBoxContainer` refuses `vertical`.
## The row is as wide whichever way it stands, since its parent gives it the
## width, so a turn never turns it back.
class_name SaTurningRow
extends BoxContainer

## How wide one child's words draw, `func(child: Control) -> float`, for a
## child that is not a button. Empty measures a button's text and frame and
## reads any other child as asking for nothing.
var measure: Callable


func _init(child_words: Callable = Callable()) -> void:
    measure = child_words
    resized.connect(fit)


func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED or what == NOTIFICATION_THEME_CHANGED:
        fit.call_deferred()


## Reads the children again and turns the row when their words have stopped
## fitting or fit again. Called on a resize and a change of language or theme,
## and by an owner whose children's words changed.
func fit() -> void:
    if size.x <= 0.0:
        return
    var shown: Array[Control] = []
    for child in get_children():
        if child is Control and (child as Control).visible:
            shown.append(child as Control)
    if shown.size() < 2:
        if vertical:
            vertical = false
        return
    var gaps := float(get_theme_constant(&"separation")) * float(shown.size() - 1)
    var words: Array[float] = []
    var total := gaps
    var ratios := 0.0
    var fixed := gaps
    for child in shown:
        var width := words_width(child)
        words.append(width)
        total += width
        if child.size_flags_horizontal & Control.SIZE_EXPAND:
            ratios += child.size_flags_stretch_ratio
        else:
            fixed += maxf(width, child.get_combined_minimum_size().x)
    var stack := total > size.x + 0.5
    for at in shown.size():
        var child := shown[at]
        if stack or not (child.size_flags_horizontal & Control.SIZE_EXPAND) or ratios <= 0.0:
            continue
        var share := (size.x - fixed) * child.size_flags_stretch_ratio / ratios
        stack = words[at] > share + 0.5
    if vertical != stack:
        vertical = stack


## How wide *child*'s words draw: the owner's measure when it gave one, a
## button's text through the catalogue with its frame and icon, or else the
## child's own minimum.
func words_width(child: Control) -> float:
    if measure.is_valid():
        return float(measure.call(child))
    var button := child as Button
    if button == null:
        return child.get_combined_minimum_size().x
    var font := button.get_theme_font(&"font")
    var font_size := button.get_theme_font_size(&"font_size")
    var width := font.get_string_size(button.atr(button.text), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    width += button.get_theme_stylebox(&"normal").get_minimum_size().x
    if button.icon != null:
        width += float(button.icon.get_width()) + float(button.get_theme_constant(&"h_separation"))
    return maxf(ceilf(width), button.custom_minimum_size.x)
