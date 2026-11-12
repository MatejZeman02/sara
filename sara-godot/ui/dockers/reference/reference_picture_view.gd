## The board's Control: draws the board, turns input into the board's own
## operations, and carries the hover bar with the four per-picture toggles.
##
## **The gesture is here and not in a file of its own**, because a corner
## press, a drag and a toggle are all facts about what is under the pointer,
## which is what this Control already draws, and two files would reach each
## other through the docker. It holds the board it shows as a public member the docker sets on a
## tab change, and it owns the hover, the selected picture, the crop mode and
## the gesture in flight itself. What a hand asks of the board, a fit, a zoom,
## a pan, a crop set outright, is this Control's too, so the docker keeps no
## door that is only a call on it. What the docker has to know after a real
## gesture, a sample, a change to persist, or a toggle, reaches it through four
## signals, `changed(content)`, `sampled(at)`, `toggled(picture, id)` and
## `canvas_wanted`, the last of them asking the docker for a board when there is
## none to draw on. This Control keeps no reference back to the docker that owns
## it.
##
## Left on a picture moves it, with the rest of the selection when it is one
## of them, and a press that never wanders is a click, which samples on the
## lift. Left on the empty board draws the box `ReferenceSelection` in
## `selection/` keeps, Ctrl with it adds, and a click there clears. Ctrl or
## Shift with a click on a picture adds it or takes it out. Alt with left
## samples as it goes, the eyedropper's chord. Middle or Shift with a left drag
## pans, the wheel, a pinch, the zoom chords and the quick zoom's drag zoom,
## `ReferenceZoomGestures` in `zoom/`, and a double click fits one picture.
## The crop, the corner handles and the hover bar, `ReferenceHoverBar` in
## `bar/`, are for one picture: a left drag on it in crop mode is the
## rectangle to keep, a press on a handle resizes it, Shift keeping its
## proportions, and the bar sits over the picture under the pointer, or the
## selected one while the pointer is on the board, and is down off the docker.
##
## **A picture comes off the board** through the right click's Remove from
## Board, `remove_picture`, or Delete or Backspace, which take every selected
## picture off. The file on disk is never touched, the board is saved without it, and a
## soloed picture removed leaves solo.
##
## **Solo shows one picture alone**, and is the board's own state, `SaReferenceBoard.solo`, because what is drawn,
## hovered and picked is all read from the board's `ordered`. This Control turns
## the three ways in, the right click's menu, the docker's Solo button and the
## shortcut, into `toggle_solo`, and takes Escape as the way out.
class_name ReferencePictureView
extends Control

## The id of the right click menu's solo row, and of the solo in `toggle_on`.
const SOLO: StringName = &"solo"

## The id of the right click menu's Remove from Board.
const REMOVE: StringName = &"remove"

## The id of the right click menu's Paste, over a picture and over empty board.
const PASTE: StringName = &"paste"

## The shortcut profile's command for Paste, whose chord the Paste row shows.
const PASTE_COMMAND: StringName = &"edit_paste"

## The shortcut profile's command for the solo, registered by the docker.
const SOLO_COMMAND: StringName = &"docker_reference_solo"

## Logical half width of a corner handle: the square drawn on each corner of the
## selected picture, and the reach of a press that takes hold of it.
const HANDLE: float = 5.0

## What a notch of the wheel and a zoom chord move the zoom by.
const ZOOM_STEP: float = ReferenceZoomGestures.STEP

## How far a press may wander and still be a click rather than a drag, in
## screen pixels.
const CLICK_SLOP: float = 4.0

## The board this Control draws, set by the docker on a tab change, on a load
## and on the auto-create of the first board. Never itself while the docker
## has any board at all.
var board: SaReferenceBoard = null

## The picture under the pointer, which the hover bar follows.
var hover: SaReferenceBoard.Picture = null

## Whether the pointer is over this Control at all, the bar included. Set by
## `mouse_entered` and by any motion, cleared by `mouse_exited`, and read by
## `hover_target`, so a selected picture carries the bar only while the pointer
## is somewhere on the board, because the buttons must not cover the reference
## all the time.
var inside: bool = false

## Whether the next left drag on the selected picture draws its crop rather than
## moving it. Entered from the hover bar's Crop, left when the drag lifts.
var crop_mode: bool = false

## The hover bar, and the picture it is over for the dump.
var _bar: ReferenceHoverBar
var _bar_for: SaReferenceBoard.Picture = null

## The canvas element's own Control, placed over its rectangle on every redraw.
## One for the view whatever the board holds, because a board has at most one
## canvas element and the docker asks this one for the canvas's size before any
## board has an element at all.
var canvas_element: ReferenceCanvasElement

## Every zoom gesture, a public member so a suite can hold the keys it reads.
var zoom: ReferenceZoomGestures = ReferenceZoomGestures.new(func() -> bool: return inside, changed.emit.bind(false))

## The selected pictures, each drawn with an outline, and the box a left drag
## on the empty board draws. Never replaced, so the docker and a suite read it
## for as long as the view stands.
var selection: ReferenceSelection = ReferenceSelection.new()

## The right click's menu, and the picture it was opened over.
var menu: SaChoicePopup
var _menu_for: SaReferenceBoard.Picture = null

## Where the right click landed, in this Control's own coordinates, and the
## picture the clipboard held when the menu opened, which its Paste row puts
## there. Null when the clipboard held none and the row is dimmed.
var _menu_at: Vector2 = Vector2.ZERO
var _menu_paste: SaDesktopPicture = null

## The gesture in flight.
var _dragging: SaReferenceBoard.Picture = null
var _resizing: SaReferenceBoard.Picture = null
var _corner: Vector2 = Vector2.ZERO
var _panning: bool = false
var _sampling: bool = false
var _cropping: bool = false
var _press_at: Vector2 = Vector2.ZERO
var _last_at: Vector2 = Vector2.ZERO
var _moved: bool = false
## The left press landed on the board off every picture, so a release that
## never moved past `CLICK_SLOP` is a click that unselects.
var _on_empty: bool = false
## The picture a Shift press landed on, a click on which toggles it.
var _shift_pick: SaReferenceBoard.Picture = null

## A drag, a wheel zoom, a pan, a fit or a click-select moved the board or the
## selection, so the docker's status line and its header need to catch up.
## *content* is true for a change to what is on the board rather than to the
## view over it, and only that marks the document modified.
signal changed(content: bool)

## A click, or a drag with alt held, landed on a picture and its colour is
## wanted, at *at* in this Control's own coordinates.
signal sampled(at: Vector2)

## A flag on *picture* flipped through the hover bar or a scenario's `toggle`.
signal toggled(picture: SaReferenceBoard.Picture, id: String)

## There is nothing to draw on: the docker has never been asked for a board.
## Answered synchronously, by `board` being set before the emit returns, so
## `draw_board` has a board as soon as the emit is done.
signal canvas_wanted

## The right click's Paste was chosen: *held* is the clipboard's picture, to go
## on the board with its centre at *at*, in this Control's own coordinates.
signal paste_wanted(at: Vector2, held: SaDesktopPicture)


func _init() -> void:
    mouse_entered.connect(pointer_entered)
    mouse_exited.connect(pointer_left)
    _bar = ReferenceHoverBar.new(SaMake.row(self, "HoverBar", 2), toggle, pointer_entered, pointer_left)
    # Under the bar, so the hover bar over the canvas element is still on top of
    # it: children draw in order and the bar was added first.
    canvas_element = ReferenceCanvasElement.new()
    add_child(canvas_element)
    move_child(canvas_element, 0)
    menu = SaChoicePopup.new()
    menu.name = "PictureMenu"
    add_child(menu)
    menu.chosen.connect(_on_menu_chosen)


func _draw() -> void:
    if board == null:
        canvas_wanted.emit()
    if board != null:
        place_canvas_element()
        draw_board()
        sync_bar()


## Puts the canvas element's Control over its rectangle and hands it the
## crop, the flip and the grey, or hides it on a board without one.
##
## Before the board is drawn, so the element is where the outline and the
## handles `draw_board` draws say it is in the same frame. A picture drawn over
## the element in the z order is not drawn over it here: a child Control always
## draws after its parent's own `_draw`. That is the one way the canvas element
## is not like the others, and the dump's `canvas_element` says where it is so a
## scenario can see it.
func place_canvas_element() -> void:
    var live := board.canvas_picture() if board != null else null
    var hidden_by_solo := board != null and board.soloed() != null and board.soloed() != live
    if live == null or live.is_missing() or hidden_by_solo:
        canvas_element.visible = false
        return
    var rect := board.view_rect(live)
    canvas_element.position = rect.position
    canvas_element.size = rect.size
    canvas_element.region = live.region()
    canvas_element.flipped = live.flip_h
    canvas_element.greyscale = live.greyscale
    canvas_element.visible = true
    canvas_element.refresh()
    # Redrawn with the board, because a flip is drawn through the element's own
    # transform and changes neither its size nor its material, so nothing else
    # would ask. The board redraws when it changes, not once a frame, so this
    # keeps the element's cost where the board's already is. Without it a flip
    # changes the element in the dump and not on screen.
    canvas_element.queue_redraw()


func _gui_input(event: InputEvent) -> void:
    input(event)


## Every event over the board, from a real press or from a scenario's own
## `picture_input`. Its own method, so the docker's door and the engine's
## `_gui_input` reach the same place.
func input(event: InputEvent) -> void:
    # The wheel, a pinch and the quick zoom's drag, first, `zoom/`'s.
    if zoom.input(event, board, size):
        return
    var button := event as InputEventMouseButton
    if button != null:
        _button_input(button)
        return
    var motion := event as InputEventMouseMotion
    if motion == null:
        return
    if not inside:
        inside = true
        queue_redraw()
    # A motion through the gap between two of the bar's buttons is the bar's,
    # not the board's: it must not move the bar off the picture it sits on.
    if not over_bar(motion.position):
        var under := board.picture_at(board.to_board(motion.position))
        if under != hover:
            hover = under
            queue_redraw()
    if _resizing != null:
        board.resize(_resizing, _corner, board.to_board(motion.position), motion.shift_pressed)
        _moved = true
        queue_redraw()
    elif _cropping:
        queue_redraw()
    elif _panning:
        board.pan_by(motion.position - _last_at)
        changed.emit(false)
    elif _sampling:
        sampled.emit(motion.position)
    elif selection.drawing:
        selection.drag_box(motion.position)
        queue_redraw()
    elif _dragging != null:
        var delta := (motion.position - _last_at) / board.zoom
        for picture in selection.moving(board, _dragging):
            board.move(picture, delta)
        queue_redraw()
    if _panning or _dragging != null or selection.drawing:
        if (motion.position - _press_at).length() > CLICK_SLOP:
            _moved = true
    _last_at = motion.position


func _button_input(button: InputEventMouseButton) -> void:
    if button.button_index == MOUSE_BUTTON_MIDDLE:
        _panning = button.pressed
        _press_at = button.position
        _last_at = button.position
    elif button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
        _press_left(button)
    elif button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
        _release_left(button)
    elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
        open_menu(board.picture_at(board.to_board(button.position)), Vector2(SaPopupRect.at_press(button, self)), button.position)


## The right click's menu over *picture*, at *at* in the space a popup's
## `position` is measured in, which `SaPopupRect.at_press` answers for the
## press, for a click at *view_at* in this Control's own. In solo the row leaves it, and
## Paste is on it everywhere, so it opens over empty board too.
func open_menu(picture: SaReferenceBoard.Picture, at: Vector2, view_at: Vector2 = Vector2(-1, -1)) -> bool:
    if not fill_menu(picture, view_at):
        return false
    menu.open_under(self, at)
    return true


## The menu's rows for *picture*, for a click at *at* in this Control's own
## coordinates, the centre of the view when none is given, without opening it,
## which is the half a suite can run on a docker outside the tree. Paste is
## always there, dimmed and disabled when the clipboard holds no picture, so
## the menu always has a row to offer.
##
## The clipboard is read once, as the menu opens, and the row pastes the
## picture it read, so what was offered is what lands.
func fill_menu(picture: SaReferenceBoard.Picture, at: Vector2 = Vector2(-1, -1)) -> bool:
    var in_solo := board != null and board.soloed() != null
    _menu_for = picture
    _menu_at = at if at.x >= 0.0 and at.y >= 0.0 else size / 2.0
    _menu_paste = ReferencePaste.read()
    menu.clear()
    if picture != null or in_solo:
        var label := tr("Show the whole board") if in_solo else tr("Show this picture alone")
        menu.add_row(SOLO, label, false, false, "", _chord(SOLO_COMMAND))
    if picture != null:
        menu.add_row(REMOVE, tr("Remove from Board"), false, false, "", tr("Delete"))
    menu.add_row(PASTE, tr("Paste"), false, false, "", _chord(PASTE_COMMAND), _menu_paste == null)
    return true


func _on_menu_chosen(id: StringName) -> void:
    if id == SOLO:
        toggle_solo(_menu_for)
    elif id == REMOVE:
        remove_picture(_menu_for)
    elif id == PASTE and _menu_paste != null:
        paste_wanted.emit(_menu_at, _menu_paste)
    _menu_for = null
    _menu_paste = null


## Takes *picture* off the board showing: the menu's Remove from Board, Delete
## and Backspace, and a scenario's. The file it came from is never touched, a
## soloed picture leaves solo through `SaReferenceBoard.remove`, and the change
## is content, so the docker saves the board without it. False for a picture
## this board does not hold.
func remove_picture(picture: SaReferenceBoard.Picture) -> bool:
    if board == null or picture == null or not board.pictures.has(picture):
        return false
    board.remove(picture)
    if selection.has(picture):
        selection.forget(picture)
        crop_mode = false
    if hover == picture:
        hover = null
    if _dragging == picture or _resizing == picture:
        _dragging = null
        _resizing = null
    queue_redraw()
    changed.emit(true)
    return true


## The chord the shortcut profile has on *command*, for the menu row's right.
static func _chord(command: StringName) -> String:
    var chords := SaShortcutStore.chords_for(command)
    return chords[0] if not chords.is_empty() else ""


## Solo on *picture*, or off again when the board already shows one alone. The
## menu's, the docker button's and the shortcut's one call. True when the view
## changed.
func toggle_solo(picture: SaReferenceBoard.Picture) -> bool:
    if board == null:
        return false
    var changed_view := board.leave_solo() if board.soloed() != null else board.solo(picture, size)
    if changed_view:
        hover = null
        queue_redraw()
        changed.emit(false)
    return changed_view


## Escape leaves solo, and Delete or Backspace removes the selected picture.
## Unhandled rather than `_gui_input`, because this Control never takes the
## focus, and the router lets Escape pass once it has let go of a text box, the
## quick mask and the focus owner, and lets the two erase keys pass in a docker
## that carries `ShortcutRouter.KEEPS_ERASE_KEYS_META`, which this one's
## window does.
func _unhandled_key_input(event: InputEvent) -> void:
    if escape(event) or erase(event):
        get_viewport().set_input_as_handled()


## Whether *event* was a bare Delete or Backspace that removed the selected
## pictures, every one of them, the half of the key handler a test can call.
func erase(event: InputEvent) -> bool:
    var key := event as InputEventKey
    if key == null or not key.pressed or key.echo or SaShortcutKeys.is_chord(event):
        return false
    if key.keycode != KEY_DELETE and key.keycode != KEY_BACKSPACE:
        return false
    var removed := false
    for picture in selection.held(board):
        removed = remove_picture(picture) or removed
    return removed


## Whether *event* was an Escape that left solo or unselected the picture, the
## half of the key handler a test can call. Solo goes first, so with a picture
## soloed a second Escape is the one that unselects.
func escape(event: InputEvent) -> bool:
    var key := event as InputEventKey
    if key == null or not key.pressed or key.echo or key.keycode != KEY_ESCAPE:
        return false
    if board != null and board.soloed() != null:
        return toggle_solo(null)
    return unselect()


func _press_left(button: InputEventMouseButton) -> void:
    _press_at = button.position
    _last_at = button.position
    _moved = false
    var picture := board.picture_at(board.to_board(button.position))
    if button.double_click and picture != null:
        board.fit_one(picture, size)
        changed.emit(false)
        return
    # Before the shift and crop branches: a handle is a small, drawn target,
    # and shift on it is the aspect lock rather than a pan.
    var corner := corner_at(button.position)
    if corner.x >= 0.0:
        _resizing = selected()
        _corner = corner
        return
    if button.alt_pressed:
        _sampling = true
        sampled.emit(button.position)
        return
    if button.shift_pressed:
        _panning = true
        _on_empty = picture == null
        _shift_pick = picture
        return
    if picture == null:
        selection.begin_box(button.position, button.ctrl_pressed)
        queue_redraw()
        return
    if button.ctrl_pressed:
        selection.toggle(picture)
        crop_mode = false
        queue_redraw()
        changed.emit(false)
        return
    if crop_mode and picture == selected():
        _cropping = true
        return
    if selection.has(picture):
        board.raise(picture)
        queue_redraw()
    else:
        select_picture(picture)
    _dragging = picture


func _release_left(button: InputEventMouseButton) -> void:
    var was_dragging := _dragging != null or _resizing != null
    var lifted := _dragging
    _dragging = null
    _resizing = null
    _panning = false
    _sampling = false
    var empty_click := _on_empty and not _moved
    _on_empty = false
    var shift_pick := _shift_pick
    _shift_pick = null
    if selection.drawing:
        _finish_box()
        return
    if empty_click:
        unselect()
        return
    if shift_pick != null and not _moved:
        selection.toggle(shift_pick)
        crop_mode = false
        queue_redraw()
        changed.emit(false)
        return
    if _cropping:
        _cropping = false
        _finish_crop(button.position)
        return
    if was_dragging:
        if _moved:
            changed.emit(true)
        else:
            # A click on one of several selected pictures narrows the selection
            # to it, as a file manager does, once the press proved not a drag.
            if lifted != null and selection.held(board).size() > 1:
                select_picture(lifted)
            sampled.emit(button.position)


## The box lifted: a click on the empty board clears the selection unless under
## Ctrl, and a box that opened selects every picture it touches.
func _finish_box() -> void:
    if _moved:
        crop_mode = false
        selection.end_box(board)
    elif not selection.adding:
        selection.clear()
    selection.drop_box()
    sync_bar()
    queue_redraw()
    changed.emit(false)


## The crop drag lifted: the two corners in the picture's texels become its
## crop, and a drag that never opened out is nothing, which leaves crop mode
## the way it was entered.
func _finish_crop(at: Vector2) -> void:
    var picture := selected()
    if picture == null or picture.is_missing():
        crop_mode = false
        queue_redraw()
        return
    var a := picture.texel_at(board.to_board(_press_at))
    var b := picture.texel_at(_onto(picture, board.to_board(at)))
    if a.x < 0 or b.x < 0:
        crop_mode = false
        queue_redraw()
        return
    var texels := Rect2i(a, b - a).abs()
    texels.size += Vector2i.ONE
    if texels.size.x < 2 or texels.size.y < 2:
        crop_mode = false
        queue_redraw()
        return
    picture.set_crop(texels)
    crop_mode = false
    changed.emit(true)


## A release on or past the picture's edge is moved onto the middle of the
## edge texel, so a crop that keeps an edge reaches it. The far edge itself
## lies on the texel one past the last, and a flip turns the near edge into a
## far one, so both sides are pulled in by half a texel.
func _onto(picture: SaReferenceBoard.Picture, point: Vector2) -> Vector2:
    var half := picture.scale() * 0.5
    var low := picture.rect.position + half
    var high := picture.rect.end - half
    return Vector2(clampf(point.x, low.x, maxf(low.x, high.x)), clampf(point.y, low.y, maxf(low.y, high.y)))


## Whether a press is being held, which is when a resize must not refit.
func busy() -> bool:
    return _panning or _dragging != null or _cropping or _resizing != null or selection.drawing or zoom.dragging


## The rectangle being dragged in crop mode, in this Control, or an empty one.
func crop_in_progress() -> Rect2:
    if not _cropping:
        return Rect2()
    return Rect2(_press_at, _last_at - _press_at).abs()


func pointer_entered() -> void:
    if not inside:
        inside = true
        queue_redraw()


## The pointer left this Control, or one of the bar's buttons. A pointer that
## is still on the bar has not left: the engine sends this Control's
## `mouse_exited` when the pointer reaches a button on it, and the bar taken
## down under the pointer is a bar that cannot be pressed.
func pointer_left() -> void:
    if is_inside_tree() and over_bar(get_local_mouse_position()):
        return
    if hover != null or inside:
        hover = null
        inside = false
        queue_redraw()


## The whole board, centred, at the largest zoom that shows all of it, or the
## selection alone when it holds several. The Fit button's call, and a
## scenario's.
##
## A docker that has never been asked for a board has none to fit, and the
## first board is the docker's own to make.
func fit() -> void:
    if board == null:
        return
    var held := selection.several(board)
    if held.is_empty() or board.soloed() != null:
        board.fit_all(size)
    else:
        board.fit_rect(ReferenceSelection.bounds(held), size)
    changed.emit(false)


## The picture under *at*, a point of this Control, and its texel, or (-1, -1)
## beside every picture and with no board to show.
func texel_at(at: Vector2) -> Vector2i:
    if board == null:
        return Vector2i(-1, -1)
    var point := board.to_board(at)
    var picture := board.picture_at(point)
    return picture.texel_at(point) if picture != null else Vector2i(-1, -1)


## One picture brought whole into this Control, the double click's own call.
func fit_picture(picture: SaReferenceBoard.Picture) -> void:
    if board == null or picture == null:
        return
    board.fit_one(picture, size)
    changed.emit(false)


## Every picture at one size in a grid shaped like this Control, *mode* being the Preferences row's own
## answer, which the docker reads because the option is its. With several
## selected, those alone, laid where they stood and fitted after, and the rest
## of the board as it was.
func normalise(mode: String) -> void:
    if board == null:
        return
    var held := selection.several(board)
    board.normalise(mode, size, held)
    board.fit_rect(ReferenceSelection.bounds(held) if not held.is_empty() else board.bounds(), size)
    changed.emit(true)


## The wheel's, a scenario's and a test's zoom about a point of this Control.
func zoom_about(at: Vector2, factor: float) -> void:
    if board != null and board.zoom_about(at, factor):
        changed.emit(false)


## A pan: the middle button's, shift and left's, or a scenario's.
func pan_by(delta: Vector2) -> void:
    if board == null:
        return
    board.pan_by(delta)
    changed.emit(false)


## Sets *picture*'s crop to *texels* outright, the scenario's and the test's
## door beside the drag, and leaves crop mode where the drag would have.
func crop_to(picture: SaReferenceBoard.Picture, texels: Rect2i) -> void:
    if picture == null:
        return
    picture.set_crop(texels)
    crop_mode = false
    changed.emit(true)


## The one selected picture, which the hover bar, the handles, the crop, the
## docker's status line and the Graph docker's two-graph mode read, or null
## when none is selected or several are, since each of those is for one.
func selected() -> SaReferenceBoard.Picture:
    return selection.one(board)


## A click landed on *picture*, or a scenario or the docker's own door chose
## it: it alone is selected and comes to the top.
func select_picture(picture: SaReferenceBoard.Picture) -> void:
    selection.only(picture)
    board.raise(picture)
    queue_redraw()
    changed.emit(false)


## Forgets the selection outright, for a board switch or a reload, which
## neither raises anything nor is a change to persist.
func deselect() -> void:
    selection.clear()


## A click on the empty board or an Escape let go of the selection: the
## handles and the outlines go and the status line catches up, through
## `changed(false)` because the board itself is as it was. Whether there was a
## picture to let go of.
func unselect() -> bool:
    if selection.held(board).is_empty():
        return false
    deselect()
    sync_bar()
    queue_redraw()
    changed.emit(false)
    return true


## The picture the hover bar belongs to: the one under the pointer, or the
## selected one while the pointer is on the board but off every picture. With
## the pointer off the docker there is none, so the bar is down and the pictures
## are whole, and with several selected there is none either, the bar being a
## one-picture affair.
func hover_target() -> SaReferenceBoard.Picture:
    if board != null and selection.held(board).size() > 1:
        return null
    if hover != null and board != null and board.pictures.has(hover):
        return hover
    var chosen := selected() if inside else null
    # In solo the bar is on the picture shown or nowhere, never over one hidden.
    if chosen != null and board.soloed() != null and chosen != board.soloed():
        return null
    return chosen


## Flips one of the four flags on the hover bar's picture: `flip`,
## `greyscale`, `crop` or `on_top`. Crop is the one that is not a flag alone:
## a picture with a crop loses it, and one without enters crop mode, where the
## next drag on it is the rectangle to keep.
func toggle(id: String) -> void:
    toggle_on(hover_target(), id)


## Flips one of the four flags on *picture*, or solos it for `solo`, the half of [method toggle] that
## does not ask where the pointer is.
##
## A door of its own, because a scenario selects a picture and then toggles it
## with the pointer nowhere near the docker, and `hover_target` answers null
## there: the selected picture is only the target while the pointer is inside
## the board. The bar's buttons still go through `toggle`, so what a hand does
## is unchanged.
func toggle_on(picture: SaReferenceBoard.Picture, id: String) -> void:
    if id == SOLO:
        toggle_solo(picture)
        return
    if picture == null:
        return
    match id:
        "flip":
            picture.flip_h = not picture.flip_h
        "greyscale":
            picture.greyscale = not picture.greyscale
        "on_top":
            picture.on_top = not picture.on_top
        "crop":
            if picture.crop.size.x > 0 and picture.crop.size.y > 0:
                picture.set_crop(Rect2i())
                crop_mode = false
            else:
                crop_mode = not crop_mode
                selection.only(picture)
                queue_redraw()
                return
    toggled.emit(picture, id)


## Every picture in its rectangle, in the board's draw order, a placeholder
## as a dimmed square with its name, every selected one outlined, the handles on
## the one when it is alone, the crop in progress as a rectangle over its
## picture, and the selection's box while it is drawn.
func draw_board() -> void:
    var shown := board
    if shown == null:
        return
    var font := get_theme_default_font()
    var font_size := SaUI.font_size_for(SaUI.fraction_of(11))
    for picture in shown.ordered():
        var rect := shown.view_rect(picture)
        if picture.is_missing():
            draw_rect(rect, Color(0.5, 0.5, 0.5, 0.25), true)
            draw_rect(rect, Color(0.6, 0.6, 0.6, 0.8), false, 1.0)
            var text := picture.path.get_file()
            var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
            draw_string(
                font,
                rect.position + Vector2((rect.size.x - width) * 0.5, rect.size.y * 0.5),
                text,
                HORIZONTAL_ALIGNMENT_LEFT,
                -1,
                font_size
            )
        elif picture.live:
            # Drawn by its own Control, which `place_canvas_element` has put
            # over this rectangle: the texture needs the canvas's material and a
            # draw call carries none.
            pass
        else:
            # The region is the crop or the whole image. A flip is the same
            # region drawn through a mirror about the rectangle's own middle:
            # a negative source width draws nothing on this renderer.
            if picture.flip_h:
                draw_set_transform(Vector2(rect.position.x * 2.0 + rect.size.x, 0.0), 0.0, Vector2(-1.0, 1.0))
            draw_texture_rect_region(picture.shown_texture(), rect, Rect2(picture.region()))
            if picture.flip_h:
                draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        if selection.has(picture):
            draw_rect(rect.grow(1.0), Color(1.0, 1.0, 1.0, 0.9), false, 2.0)
        if picture == selected():
            for corner in SaReferenceBoard.CORNERS:
                var handle := handle_rect(rect, corner)
                draw_rect(handle, Color(0.1, 0.1, 0.1, 0.9), true)
                draw_rect(handle, Color(1.0, 1.0, 1.0, 0.9), false, 1.0)
    var pending := crop_in_progress()
    if pending.size.x > 0.0 and pending.size.y > 0.0:
        draw_rect(pending, Color(1.0, 0.85, 0.2, 0.9), false, 1.0)
    var box := selection.box()
    if box.size.x > 0.0 or box.size.y > 0.0:
        draw_rect(box, Color(0.45, 0.7, 1.0, 0.18), true)
        draw_rect(box, Color(0.45, 0.7, 1.0, 0.9), false, 1.0)


## Puts the bar over the picture the pointer is on, or the selected one, and
## reads that picture's four flags onto the buttons. Off every picture, or
## off the docker, the bar is hidden.
func sync_bar() -> void:
    var target := hover_target()
    if target == null or target.is_missing():
        _bar.take_down()
        _bar_for = null
        return
    var flags := {
        "flip": target.flip_h,
        "greyscale": target.greyscale,
        "crop": crop_mode or (target.crop.size.x > 0 and target.crop.size.y > 0),
        "on_top": target.on_top,
    }
    _bar.put_over(board.view_rect(target), size, flags)
    _bar_for = target


## The square drawn on *corner* of a picture shown in *rect*, in this
## Control's coordinates. One place for the drawing and the hit test, so the
## handle a painter sees is the one a press takes hold of.
static func handle_rect(rect: Rect2, corner: Vector2) -> Rect2:
    var half := SaUI.pxf(HANDLE)
    return Rect2(rect.position + rect.size * corner - Vector2(half, half), Vector2(half, half) * 2.0)


## The corner of the selected picture whose handle is under *at*, or
## (-1, -1) for none. Only the selected picture shows handles, so only it
## answers, and a press on another picture's corner selects it first.
func corner_at(at: Vector2) -> Vector2:
    var picture := selected()
    if picture == null or board == null or not board.ordered().has(picture):
        return Vector2(-1, -1)
    var rect := board.view_rect(picture)
    for corner in SaReferenceBoard.CORNERS:
        if handle_rect(rect, corner).has_point(at):
            return corner
    return Vector2(-1, -1)


## Whether *at*, a point in this Control, is over the bar, so a press there
## is the bar's and not the board's.
func over_bar(at: Vector2) -> bool:
    return _bar.covers(at)


## What the dump says about the bar: whether it is up, the index of the
## picture it sits on in the board showing or -1, and where, so a scenario
## proves the bar gone and back rather than reading it off a screenshot.
func bar_report() -> Dictionary:
    var row := _bar.row
    var index := board.pictures.find(_bar_for) if row.visible and _bar_for != null and board != null else -1
    return {"visible": row.visible, "picture": index, "position": [row.position.x, row.position.y]}
