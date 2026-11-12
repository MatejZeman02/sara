## The Object Selection tool: a box dragged round an object selects the object
## inside it, Shift adding to the selection and Alt subtracting, and a click
## with no drag selects the subject of the whole picture as Select Subject
## does.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Photoshop's Object Selection in its rectangle mode. The run is the module's,
## handed to every surface's tool through
## [member SaToolDescriptor.shared_settings] as Select Subject's is, and it
## takes the box as a fourth argument. The box shows while the drag is on,
## drawn by the selection overlay from [method preview_shape] as the marquee's
## is, and the pointer carries a plus or a minus while Shift or Alt is down
## and through a drag that started with one.
extends ToolState

const SelectSubjectTool := preload("select_subject_tool.gd")


## The pointer's picture for Add and for Subtract, the crosshair with a plus
## or a minus beside it, made once a tool. The base module's selection tools
## draw the same marks, which a module cannot reach, so the two pictures are
## drawn here in the same way, light on a dark rim.
class Chord:
    extends RefCounted

    const SIDE: int = 32
    const CENTRE: Vector2i = Vector2i(12, 12)
    const MARK_AT: Vector2i = Vector2i(24, 24)
    const MARK_HALF: int = 5

    var _pictures: Dictionary = {}

    ## The picture for *mode*, a `SaSelection.Mode`, or null for the plain
    ## cross of a replace.
    func picture_for(mode: int) -> SaCursorPicture:
        if not mode in [SaSelection.Mode.ADD, SaSelection.Mode.SUBTRACT]:
            return null
        if not _pictures.has(mode):
            _pictures[mode] = _make(mode)
        return _pictures[mode]

    func _make(mode: int) -> SaCursorPicture:
        var image := Image.create_empty(SIDE, SIDE, false, Image.FORMAT_RGBA8)
        var c := CENTRE
        var m := MARK_AT
        var h := MARK_HALF
        var strokes: Array = [
            [Vector2i(c.x, 1), Vector2i(c.x, c.y - 3)],
            [Vector2i(c.x, c.y + 3), Vector2i(c.x, c.y + 11)],
            [Vector2i(1, c.y), Vector2i(c.x - 3, c.y)],
            [Vector2i(c.x + 3, c.y), Vector2i(c.x + 11, c.y)],
            [Vector2i(m.x - h, m.y), Vector2i(m.x + h, m.y)],
        ]
        if mode == SaSelection.Mode.ADD:
            strokes.append([Vector2i(m.x, m.y - h), Vector2i(m.x, m.y + h)])
        for pass_index: int in 2:
            var colour := Color(0.08, 0.08, 0.08, 1.0) if pass_index == 0 else Color(1.0, 1.0, 1.0, 1.0)
            for stroke: Array in strokes:
                _line(image, stroke[0], stroke[1], 1 - pass_index, colour)
        var name := &"object_select_add" if mode == SaSelection.Mode.ADD else &"object_select_subtract"
        return SaCursorPicture.new(
            name, ImageTexture.create_from_image(image), (Vector2(CENTRE) + Vector2(0.5, 0.5)) / float(SIDE)
        )

    func _line(image: Image, from: Vector2i, to: Vector2i, grow: int, colour: Color) -> void:
        var steps := maxi(absi(to.x - from.x), absi(to.y - from.y))
        for i: int in steps + 1:
            var at := Vector2i(Vector2(from).lerp(Vector2(to), float(i) / float(maxi(steps, 1))).round())
            for dy: int in range(-grow, grow + 1):
                for dx: int in range(-grow, grow + 1):
                    var x := at.x + dx
                    var y := at.y + dy
                    if x >= 0 and y >= 0 and x < SIDE and y < SIDE:
                        image.set_pixel(x, y, colour)


## The descriptor's [SelectSubjectTool.Click], set by the tool machine.
var settings: Resource = null
## Whether the network reads every layer as shown or the active one alone.
## The `sample_merged` option, the wand's and Select Subject's.
var sample_merged: bool = true

var _dragging: bool = false
var _anchor: Vector2 = Vector2.ZERO
var _corner: Vector2 = Vector2.ZERO
## The mode Shift and Alt gave the press under way, kept through the drag.
var _press_mode: int = SaSelection.Mode.REPLACE
var _chord: Chord = Chord.new()


func reset() -> void:
    _dragging = false


## A press of the left button starts the box, the pointer moves its far
## corner, and the release runs the module's click with the box.
func handle_input(event: InputEvent) -> void:
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if button.pressed:
            press(get_document_mouse_position(), button.shift_pressed, button.alt_pressed)
        elif _dragging:
            _corner = get_document_mouse_position()
            release()
        return
    if event is InputEventMouseMotion and _dragging:
        _corner = get_document_mouse_position()


## Starts a box at *at*, in document pixels, in the mode *shift* and *alt*
## make of a replace. Public, with [method drag_to] and [method release], so a
## suite and a capture step drag without a pointer.
func press(at: Vector2, shift: bool = false, alt: bool = false) -> void:
    _dragging = true
    _anchor = at
    _corner = at
    _press_mode = SaSelection.mode_for_press(SaSelection.Mode.REPLACE, shift, alt)


## Moves the box's far corner to *at*, in document pixels.
func drag_to(at: Vector2) -> void:
    if _dragging:
        _corner = at


## Ends the drag and runs the click: inside the box when it has an area of
## more than a pixel, over the whole picture otherwise.
func release() -> void:
    if not _dragging:
        return
    _dragging = false
    var box := drag_rect()
    if box.size.x <= 1 or box.size.y <= 1:
        box = Rect2i()
    var given := settings as SelectSubjectTool.Click
    if given != null and given.run.is_valid():
        given.run.call(_press_mode, sample_merged, surface, box)


## Whether a box is being dragged.
func dragging() -> bool:
    return _dragging


## The box between the press and the pointer, both corners rounded to the
## nearest pixel edge, as the marquee's.
func drag_rect() -> Rect2i:
    var low := _anchor.min(_corner).round()
    var high := _anchor.max(_corner).round()
    return Rect2i(Vector2i(low), Vector2i(high - low))


## What the overlay draws while the drag is on, the box. Empty otherwise.
func preview_shape() -> Dictionary:
    if not _dragging:
        return {}
    return {"rect": Rect2(drag_rect()), "ellipse": false}


## The mode the pointer shows: the press's own through a drag, and what Shift
## and Alt down now would give a press otherwise.
func shown_mode() -> int:
    if _dragging:
        return _press_mode
    return SaSelection.mode_for_press(SaSelection.Mode.REPLACE, Input.is_key_pressed(KEY_SHIFT), Input.is_key_pressed(KEY_ALT))


## The crosshair with a plus for Add and a minus for Subtract, in the cross's
## slot while a key is down or a press made with one is dragged.
func cursor_picture() -> SaCursorPicture:
    return _chord.picture_for(shown_mode())
