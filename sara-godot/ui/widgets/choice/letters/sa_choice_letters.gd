## A key pressed on an open `SaChoicePopup` that is a row's underlined letter,
## run as the row's click.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Which letter a row should carry is a question about a menu's words,
## `SaMenuLetters` beside `SaMenu`, which hands each row its letter through
## `underline`. This folder owns the rest of a row's letter: the line under it,
## what a row says its letter is, and what the key does. A feature of its own
## rather than three more methods on the list and the row, because what a
## letter does is one question with one answer,
## asked by the list's key handling and by a suite that cannot open a `Window`
## and type into it.
class_name SaChoiceLetters
extends RefCounted


## Runs the row of *popup* whose underlined letter is *letter*, folded, and says
## whether a row holds the letter. A dimmed row's letter, or a row a search has
## hidden, is held and runs nothing, as its click runs nothing, so the key never
## goes on to the type-ahead. A branch row opens its child list, as the right
## arrow does, and any other row is pressed and the keyboard put on it.
static func press(popup: SaChoicePopup, letter: String) -> bool:
    var folded := letter.to_lower()
    if popup == null or folded.is_empty():
        return false
    for id: StringName in popup.row_ids():
        if letter_of(popup.row_of(id)) != folded:
            continue
        if popup.is_disabled(id) or not popup.is_row_shown(id):
            return true
        popup.set_highlight(id)
        if popup.is_branch(id):
            popup.branched.emit(id)
        else:
            popup.press_row(id)
        return true
    return false


## Underlines the letter at *at* in *row*'s label and says whether there was one
## to underline. Once per build: a second call on a row whose line shows finds it
## and refuses. A row a kept list refilled has its line hidden, and that
## line is moved to *at* and shown again rather than a second one made.
static func underline(row: SaChoiceRow, at: int) -> bool:
    var button := row.label_button() if row != null else null
    if button == null or at < 0 or at >= button.text.length():
        return false
    var line := button.get_node_or_null("Underline") as Underline
    if line == null:
        button.add_child(Underline.new(button, at))
        return true
    if line.visible:
        return false
    line.move_to(at)
    return true


## *row*'s underlined letter, folded, or "" for a row with none.
static func letter_of(row: SaChoiceRow) -> String:
    var button := row.label_button() if row != null else null
    var line := button.get_node_or_null("Underline") as Underline if button != null else null
    return button.text[line.at].to_lower() if line != null and line.visible and line.at < button.text.length() else ""


## The line under a row's letter, a child of the label button drawn over it.
##
## Drawn rather than written into the label, because a `Button` draws one plain
## string and every reader of a row, the search, the type-ahead and the suites,
## reads that string. Its own node rather than a `draw` hook on the button, so a
## row says whether it is underlined by what it holds. It ignores the pointer,
## which goes on pressing the button under it, and takes the button's fade, so a
## dimmed row's line is dimmed with its words.
class Underline:
    extends Control

    ## The index of the letter in the label. Written by `_init` and `move_to`.
    var at: int = 0
    var _button: Button = null

    func _init(button: Button = null, letter_at: int = 0) -> void:
        _button = button
        at = letter_at
        name = "Underline"
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        set_anchors_preset(Control.PRESET_FULL_RECT)

    ## The line put under the letter at *letter_at* and shown, for a row a kept
    ## list refilled with its line hidden.
    func move_to(letter_at: int) -> void:
        at = letter_at
        visible = true
        queue_redraw()

    ## Where the label's text starts, as the engine's button lays it out: the
    ## stylebox's left margin, and an icon and its gap before the words.
    func _text_left() -> float:
        var box := _button.get_theme_stylebox("normal")
        var left := box.get_margin(SIDE_LEFT) if box != null else 0.0
        if _button.icon != null:
            var cap := _button.get_theme_constant("icon_max_width")
            var wide := float(_button.icon.get_width())
            left += (minf(wide, float(cap)) if cap > 0 else wide) + float(_button.get_theme_constant("h_separation"))
        return left

    func _draw() -> void:
        if _button == null or at >= _button.text.length():
            return
        var font := _button.get_theme_font("font")
        var font_size := _button.get_theme_font_size("font_size")
        var before := font.get_string_size(_button.text.substr(0, at), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
        var wide := font.get_string_size(_button.text[at], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
        var top := (size.y - font.get_height(font_size)) * 0.5
        var y := roundf(top + font.get_ascent(font_size) + float(SaUI.px(2)))
        var x := _text_left() + before
        var colour := _button.get_theme_color("font_disabled_color" if _button.disabled else "font_color")
        draw_line(Vector2(x, y), Vector2(x + wide, y), colour, float(maxi(1, SaUI.px(1))))
