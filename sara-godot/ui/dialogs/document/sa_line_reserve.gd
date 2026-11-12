## Holds a wrapping label at the height of the tallest sentence it may be given,
## so whatever stands below it stays where it is while the sentence changes.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The import fit dialog's Place button moved 43 pixels up when the painter chose
## "Fit inside the canvas", because the hint under the fit row wrapped to one
## line fewer than the one before it. A label sized by its own text moves
## every row under it each time the text changes, so this one is sized by the
## whole list of sentences it may carry instead. The list is asked for rather
## than handed over once, because what a label may say can depend on the
## question its window is asking, and it is read at every measure, so a sentence
## added to the list tomorrow is reserved for without a number written down.
##
## The height is worked out the way `Label` works out its own: the sentence
## shaped at the label's width with the label's font, size and break rules, the
## lines' heights and the line spacing between them, and the frame of its
## stylebox. It is measured again whenever the label's width or theme changes,
## which is how an interface scale or a Font size reaches it.
class_name SaLineReserve
extends RefCounted

## The breaks `Label` makes under `AUTOWRAP_WORD_SMART`, the mode the dialog's
## wrapping labels use.
const BREAKS := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE

var _label: Label = null
## Answers the sentences the label may carry, already translated, as an `Array`
## of `String`.
var _sentences: Callable = Callable()


func _init(label: Label, sentences: Callable) -> void:
    _label = label
    _sentences = sentences
    _label.resized.connect(measure)
    _label.theme_changed.connect(measure)


## Sets the label's minimum height to its tallest sentence at the width it has.
## A label with no width yet, hidden or not sorted, is left as it is, since
## every sentence would wrap a word to a line and the reserve would be far too
## tall.
func measure() -> void:
    if not is_instance_valid(_label) or not _sentences.is_valid():
        return
    var frame := _label.get_theme_stylebox(&"normal").get_minimum_size()
    var width := _label.size.x - frame.x
    if width < 2.0:
        return
    var tallest := 0.0
    for sentence: String in _sentences.call():
        tallest = maxf(tallest, height_of(sentence, width))
    var reserved := ceilf(tallest + frame.y)
    if not is_equal_approx(_label.custom_minimum_size.y, reserved):
        _label.custom_minimum_size.y = reserved


## The height *sentence* takes in the label's font wrapped at *width*, without
## the stylebox's frame.
func height_of(sentence: String, width: float) -> float:
    var paragraph := TextParagraph.new()
    paragraph.break_flags = BREAKS
    paragraph.width = width
    paragraph.add_string(sentence, _label.get_theme_font(&"font"), _label.get_theme_font_size(&"font_size"))
    var lines := paragraph.get_line_count()
    var height := 0.0
    for i in lines:
        height += paragraph.get_line_size(i).y
    return height + float(_label.get_theme_constant(&"line_spacing")) * float(maxi(lines - 1, 0))
