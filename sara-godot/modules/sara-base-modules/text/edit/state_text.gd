## The Text tool: a click on empty canvas starts point text, a click on a text
## layer's letters edits it, and the keyboard types into the block.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **While a block is edited the keyboard is the block's.** The shortcut
## router asks [method takes_typing] before any chord, so "b" types a b and
## does not pick the brush, Space types a space and does not pan. Enter starts
## a new line, the arrows, Home and End walk the caret through Godot's carets,
## which follow mixed directions, and Backspace and Delete take a grapheme.
## Escape, Ctrl+Enter or a click outside the block commits it, and so does
## switching tools, an undo and a save, through [method close_session].
## Ctrl+V pastes plain text from the clipboard at the caret.
##
## **IME.** The window's IME is on while a block is edited, and the text it is
## composing is shown at the caret, underlined, until the input method commits
## it as typed characters. Dead keys arrive composed, as any typed character.
##
## The block's family and size are the Font and Size rows, its colour the
## painter's foreground, which recolours the whole block in hand as it moves. The layer, the drawing and
## the history are `sa_text_session.gd`'s.
extends ToolState

const Fonts = preload("res://modules/sara-base-modules/text/fonts/sa_text_fonts.gd")
const Session = preload("res://modules/sara-base-modules/text/edit/sa_text_session.gd")

## How far the frame round a block stands off its letters, in document pixels.
const FRAME_MARGIN := 4.0
## The keys an edited block takes beside every key that types a character.
const EDITING_KEYS: Array[Key] = [
    KEY_BACKSPACE, KEY_DELETE, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_HOME, KEY_END, KEY_ENTER, KEY_KP_ENTER
]

## Test seam. A suite that replaces it puts DisplayServer.clipboard_get back.
static var clipboard_reader: Callable = DisplayServer.clipboard_get

## The Font row: the place of the family in [constant Fonts.SHIPPED]. The block
## in hand follows on the next frame, see [method tick].
var font_choice: int = 0:
    set(value):
        font_choice = clampi(value, 0, Fonts.SHIPPED.size() - 1)
        _style_pending = true
## The Size row, in document pixels an em. The block in hand follows on the
## next frame, so a value typed a digit at a time lays the block out once, at
## the number the painter ends on, and not at every number on the way.
var font_size: float = 72.0:
    set(value):
        font_size = maxf(value, 1.0)
        _style_pending = true

var _session: Session = null
## What the block says, the composing text not included.
var _text: String = ""
## The caret's place in [member _text].
var _caret: int = 0
## Where a selection started, with [member _caret] its other end, or -1 while
## nothing is selected.
var _anchor: int = -1
## What the input method is composing at the caret, shown and not yet typed.
var _composing: String = ""
## Whether a row has moved since the block in hand was last set in it.
var _style_pending: bool = false
## The painter's colour, in the document's space, as the block in hand last
## heard it, so a block opened with a colour of its own keeps it until the
## painter picks another.
var _seen_colour: Color = Color.BLACK


## The family the Font row names.
func family() -> String:
    return Fonts.SHIPPED.keys()[font_choice]


## Whether a block is being edited.
func editing() -> bool:
    return _session != null and _session.layer != null


func handle_input(event: InputEvent) -> void:
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
        press(get_document_mouse_position())
        return
    var key := event as InputEventKey
    if key != null and key.pressed:
        _key(key)


## A click at *at*, in document pixels: inside the block in hand it moves the
## caret, outside it commits the block, and with none in hand it edits the
## text layer under it or starts a new block there, its first baseline at *at*.
func press(at: Vector2) -> void:
    var doc := document()
    if doc == null:
        return
    _restyle()
    if editing():
        if _session.in_document() and _frame().has_point(at):
            _caret = _session.recipe.laid_out().index_at(at - _session.recipe.origin)
            _anchor = -1
            return
        commit()
        return
    var under := Session.text_layer_at(doc, at)
    if under != null and under.is_locked:
        SaProblems.refuse("Text", tr(Session.LOCKED) % under.name)
        return
    var session := Session.new(doc, under)
    if under != null:
        _hold(session, session.recipe.laid_out().index_at(at - session.recipe.origin))
        return
    if session.begin_new(at, family(), font_size, _current_colour()):
        _hold(session, 0)


## Opens *layer*, a text layer of the document, with the caret at its end, as
## a click on its letters would, the block in hand committed first. Answers
## whether it opened, which a locked layer never is. The door's `text_edit`
## step comes through here.
func edit(layer: SaLayer) -> bool:
    var doc := document()
    if doc == null or not Session.is_text(layer) or layer.is_locked:
        return false
    commit()
    var session := Session.new(doc, layer)
    _hold(session, session.recipe.text.length())
    return true


## Puts the caret before the character at *index* of the block in hand, kept
## inside the text.
func place_caret(index: int) -> void:
    if editing() and _session.in_document():
        _caret = clampi(index, 0, _text.length())


## Takes *session*'s block in hand with the caret at *at*, and turns the Font
## and Size rows to the block's own, so a row moved next restyles it from what
## it is and not from what a block before it was set in.
func _hold(session: Session, at: int) -> void:
    # Before the session is held, so the rows' setters restyle nothing.
    var shipped := Fonts.SHIPPED.keys().find(session.recipe.family)
    if shipped >= 0:
        font_choice = shipped
    font_size = session.recipe.size
    _session = session
    _text = session.recipe.text
    _caret = clampi(at, 0, _text.length())
    _composing = ""
    _anchor = -1
    _style_pending = false
    _seen_colour = _current_colour()
    DisplayServer.window_set_ime_active(true)
    # The panel and the bar read the rows off the tool only when told it moved.
    EventBus.tool_options_moved.emit()


static func _is_paste_key(event: InputEventKey) -> bool:
    return (
        (event.ctrl_pressed or event.meta_pressed)
        and not event.shift_pressed
        and not event.alt_pressed
        and (event.keycode == KEY_V or event.physical_keycode == KEY_V or event.key_label == KEY_V)
    )


static func _is_select_all_key(event: InputEventKey) -> bool:
    return (
        (event.ctrl_pressed or event.meta_pressed)
        and not event.shift_pressed
        and not event.alt_pressed
        and (event.keycode == KEY_A or event.physical_keycode == KEY_A or event.key_label == KEY_A)
    )


static func _is_commit_chord(event: InputEventKey) -> bool:
    return (
        (event.ctrl_pressed or event.meta_pressed)
        and not event.alt_pressed
        and (event.keycode in [KEY_ENTER, KEY_KP_ENTER] or event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER])
    )


## Whether *event* is the edited block's, which the shortcut router asks before
## any chord answers it: every press that types a character or edits the text,
## Ctrl+V, which pastes text, and Ctrl+Enter, which commits. Tab and the other
## chords stay the window's.
func takes_typing(event: InputEventKey) -> bool:
    if not editing() or not event.pressed:
        return false
    if event.ctrl_pressed or event.meta_pressed or event.alt_pressed:
        return _is_paste_key(event) or _is_commit_chord(event) or _is_select_all_key(event)
    return event.keycode in EDITING_KEYS or (event.unicode >= 32 and event.unicode != 127)


func _key(event: InputEventKey) -> void:
    if not editing():
        return
    _restyle()
    if event.keycode == KEY_ESCAPE or _is_commit_chord(event):
        commit()
        return
    if not _session.in_document():
        return
    if _is_paste_key(event):
        _paste()
        return
    if _is_select_all_key(event):
        _anchor = 0
        _caret = _text.length()
        return
    var layout := _session.recipe.laid_out()
    var selected := _anchor >= 0 and _anchor != _caret
    if selected and event.keycode in [KEY_BACKSPACE, KEY_DELETE]:
        _delete_selection()
        return
    if selected and event.keycode in [KEY_LEFT, KEY_RIGHT]:
        _caret = mini(_anchor, _caret) if event.keycode == KEY_LEFT else maxi(_anchor, _caret)
        _anchor = -1
        return
    if event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_HOME, KEY_END]:
        _anchor = -1
    match event.keycode:
        KEY_ENTER, KEY_KP_ENTER:
            _type("\n")
        KEY_BACKSPACE:
            if _caret > 0:
                var from := layout.previous_index(_caret)
                _text = _text.erase(from, _caret - from)
                _caret = from
                _show()
        KEY_DELETE:
            if _caret < _text.length():
                _text = _text.erase(_caret, layout.next_index(_caret) - _caret)
                _show()
        KEY_LEFT:
            _caret = layout.previous_index(_caret)
        KEY_RIGHT:
            _caret = layout.next_index(_caret)
        KEY_UP:
            _caret = layout.index_across(_caret, -1)
        KEY_DOWN:
            _caret = layout.index_across(_caret, 1)
        KEY_HOME:
            _caret = layout.line_start(_caret)
        KEY_END:
            _caret = layout.line_end(_caret)
        _:
            if event.unicode >= 32 and event.unicode != 127:
                _type(String.chr(event.unicode))


## Puts *typed_text* in at the caret and moves the caret past it.
func type_text(typed_text: String) -> void:
    if editing() and _session.in_document():
        _restyle()
        _type(typed_text)


func _paste() -> void:
    if not clipboard_reader.is_valid():
        return
    var raw := str(clipboard_reader.call())
    if raw.is_empty():
        return
    var clean := clean_clipboard_text(raw)
    if clean.is_empty():
        return
    _type(clean)


## *raw* with newlines kept and other control characters dropped, so text from
## the clipboard pastes as clean lines.
static func clean_clipboard_text(raw: String) -> String:
    var normalized := raw.replace("\r\n", "\n").replace("\r", "\n")
    var clean := ""
    for i in normalized.length():
        var code := normalized.unicode_at(i)
        if code == 10 or (code >= 32 and code != 127 and (code < 128 or code > 159)):
            clean += String.chr(code)
    return clean


## Takes the selected letters out and leaves the caret where they were.
func _delete_selection() -> void:
    var first := mini(_anchor, _caret)
    var last := maxi(_anchor, _caret)
    _anchor = -1
    _text = _text.erase(first, last - first)
    _caret = first
    _show()


func _type(typed_text: String) -> void:
    if _anchor >= 0 and _anchor != _caret:
        _delete_selection()
    _anchor = -1
    _text = _text.insert(_caret, typed_text)
    _caret += typed_text.length()
    _show()


## The block drawn as it reads now, the composing text at the caret.
func _show() -> void:
    if _session != null and _session.in_document():
        _session.show(_text.insert(_caret, _composing) if not _composing.is_empty() else _text)


## The painter's foreground in the document's own space.
func _current_colour() -> Color:
    var doc := document()
    var colour := SaInHand.Pair.foreground()
    var space: SaColorSpace = doc.color_space if doc != null else null
    return space.from_display(colour) if space != null else colour


## Sets the block in hand in the rows and the colour as they stand, once,
## however many times they moved since. A colour the painter picked colours the
## whole block, as Font and Size do.
func _restyle() -> void:
    if not editing():
        return
    var colour := _current_colour()
    var moved := _style_pending or not colour.is_equal_approx(_seen_colour)
    if not moved:
        return
    _style_pending = false
    _seen_colour = colour
    if _session.in_document():
        _session.restyle(family(), font_size, colour)


## Ends the block in hand as one history step, and answers whether it left
## one.
func commit() -> bool:
    if not editing():
        return false
    _restyle()
    _composing = ""
    if _session.in_document():
        _session.show(_text)
    var session := _session
    _session = null
    DisplayServer.window_set_ime_active(false)
    return session.commit()


func close_session() -> bool:
    return commit()


func holds_session() -> bool:
    return editing() and _session.in_document()


func reset() -> void:
    commit()


## Sets the block in the rows the painter moved, and reads what the input
## method composes, which Godot gives a window and not a tool, once a frame
## while a block is edited.
func tick(_delta: float) -> void:
    if not editing() or not _session.in_document():
        return
    _restyle()
    var composing := DisplayServer.ime_get_text()
    if composing != _composing:
        _composing = composing
        _show()


## The box round the block and its caret, in document pixels.
func _frame() -> Rect2:
    var recipe := _session.recipe
    var caret_rect := recipe.laid_out().caret_at(_caret + _composing.length())
    var box := Rect2(recipe.origin + caret_rect.position, caret_rect.size)
    var drawn := recipe.bounds()
    if drawn.has_area():
        box = box.merge(Rect2(drawn))
    return box.grow(FRAME_MARGIN)


## The block's frame, its caret and the composing text's underline, drawn by
## the canvas's overlay in screen pixels, so they are crisp at any zoom and
## never in the document. Empty while no block is edited, which also tells the
## shortcut router that Escape is not this tool's.
func preview_shape() -> Dictionary:
    if not editing() or not _session.in_document():
        return {}
    var recipe := _session.recipe
    var layout := recipe.laid_out()
    var at := layout.caret_at(_caret + _composing.length())
    var lines: Array[PackedVector2Array] = [
        PackedVector2Array([recipe.origin + at.position, recipe.origin + at.position + Vector2(0.0, at.size.y)])
    ]
    if not _composing.is_empty():
        var from := layout.caret_at(_caret)
        var foot := recipe.origin + Vector2(0.0, from.position.y + layout.ascent + layout.descent * 0.5)
        lines.append(PackedVector2Array([foot + Vector2(from.position.x, 0.0), foot + Vector2(at.position.x, 0.0)]))
    return {"rect": _frame(), "lines": lines, "fills": _selection_boxes()}


## One box per line the selection reaches, in document pixels.
func _selection_boxes() -> Array[Rect2]:
    var boxes: Array[Rect2] = []
    if _anchor < 0 or _anchor == _caret:
        return boxes
    var recipe := _session.recipe
    var layout := recipe.laid_out()
    var first := mini(_anchor, _caret)
    var last := maxi(_anchor, _caret)
    for l in range(layout.line_of(first), layout.line_of(last) + 1):
        var from := maxi(first, layout.starts[l])
        var to := mini(last, layout.starts[l] + layout.lengths[l])
        var a := layout.caret_at(from)
        var b := layout.caret_at(to)
        # A line break inside the selection shows as a short stub past the line's end.
        var width := b.position.x - a.position.x + (4.0 if last > to else 0.0)
        if width > 0.0:
            boxes.append(Rect2(recipe.origin + a.position, Vector2(width, a.size.y)))
    return boxes


## The I-beam over the canvas, the pointer a painter knows for text.
func cursor_shape() -> int:
    return Control.CURSOR_IBEAM


func capture_report(_tool_name: StringName, active: bool) -> Dictionary:
    if not active:
        return {}
    return {
        "text_tool":
        {
            "editing": editing() and _session.in_document(),
            "text": _text,
            "caret": _caret,
            "family": family(),
            "size": font_size,
        }
    }
