## The selection tools' chord as the painter sees it: Shift adds, Alt subtracts
## and both intersect, shown on the Tool Options mode row and as a mark on the
## pointer while the keys are down.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The marquee, the ellipse, the lasso and the wand each hold one, so the three
## pointer pictures are made once per tool and handed back as the same objects
## every frame, which is how the machine tells that nothing changed. The keys
## are read off `Input` because a held key is not an event the tool is handed:
## the press reads its own modifiers, and this answers between presses.
##
## The pictures are drawn here rather than shipped as icons, a crosshair with a
## plus, a minus or a cross beside it, light on a dark rim like the Transform's
## rotate arrow, so the mark reads over white paint as over black.
extends RefCounted

## The side the pictures are drawn at, in pixels, before the cursor policy
## sizes them to the edge every tool picture shares.
const SIDE: int = 32

## Where the crosshair's centre is, which is the pointer's point.
const CENTRE: Vector2i = Vector2i(12, 12)

## The mark's centre and its half length, beside and below the crosshair.
const MARK_AT: Vector2i = Vector2i(24, 24)
const MARK_HALF: int = 5

## The three pictures by mode, made on first ask.
var _pictures: Dictionary = {}


## The mode Shift and Alt down now would give a press over *base*, the tool's
## chosen mode, or -1 while neither is down.
static func held_mode(base: int) -> int:
    var shift := Input.is_key_pressed(KEY_SHIFT)
    var alt := Input.is_key_pressed(KEY_ALT)
    return SaSelection.mode_for_press(base, shift, alt) if shift or alt else -1


## The mode a press with *shift* and *alt* gives over *base*, or -1 when it
## took neither, which is what a tool keeps through its drag.
static func pressed_mode(base: int, shift: bool, alt: bool) -> int:
    return SaSelection.mode_for_press(base, shift, alt) if shift or alt else -1


## What the mode row shows for *chord*, a mode or -1 for the painter's own.
static func options_for(chord: int) -> Dictionary:
    return {} if chord < 0 else {&"selection_mode": chord}


## The pointer picture for *chord*: the crosshair with a plus for Add, a minus
## for Subtract and a cross for Intersect, and null for the rest, which leaves
## the descriptor's plain cross.
func picture_for(chord: int) -> SaCursorPicture:
    if not chord in [SaSelection.Mode.ADD, SaSelection.Mode.SUBTRACT, SaSelection.Mode.INTERSECT]:
        return null
    if not _pictures.has(chord):
        _pictures[chord] = _make(chord)
    return _pictures[chord]


func _make(chord: int) -> SaCursorPicture:
    var image := Image.create_empty(SIDE, SIDE, false, Image.FORMAT_RGBA8)
    var names := {SaSelection.Mode.ADD: &"select_add", SaSelection.Mode.SUBTRACT: &"select_subtract"}
    var strokes: Array = _crosshair() + _mark(chord)
    # The rim first and the fill over it, so each line is light with a dark
    # edge all round, crossings included.
    for pass_index: int in 2:
        var colour := Color(0.08, 0.08, 0.08, 1.0) if pass_index == 0 else Color(1.0, 1.0, 1.0, 1.0)
        for stroke: Array in strokes:
            _line(image, stroke[0], stroke[1], 1 - pass_index, colour)
    var texture := ImageTexture.create_from_image(image)
    var hotspot := (Vector2(CENTRE) + Vector2(0.5, 0.5)) / float(SIDE)
    return SaCursorPicture.new(names.get(chord, &"select_intersect"), texture, hotspot)


## The four arms of the crosshair, with a gap at the centre so the pixel under
## the point stays visible.
func _crosshair() -> Array:
    var c := CENTRE
    return [
        [Vector2i(c.x, 1), Vector2i(c.x, c.y - 3)],
        [Vector2i(c.x, c.y + 3), Vector2i(c.x, c.y + 11)],
        [Vector2i(1, c.y), Vector2i(c.x - 3, c.y)],
        [Vector2i(c.x + 3, c.y), Vector2i(c.x + 11, c.y)],
    ]


func _mark(chord: int) -> Array:
    var m := MARK_AT
    var h := MARK_HALF
    var across := [Vector2i(m.x - h, m.y), Vector2i(m.x + h, m.y)]
    match chord:
        SaSelection.Mode.ADD:
            return [across, [Vector2i(m.x, m.y - h), Vector2i(m.x, m.y + h)]]
        SaSelection.Mode.SUBTRACT:
            return [across]
        _:
            var d := h - 1
            var falling := [Vector2i(m.x - d, m.y - d), Vector2i(m.x + d, m.y + d)]
            return [falling, [Vector2i(m.x - d, m.y + d), Vector2i(m.x + d, m.y - d)]]


## Draws a straight or diagonal line from *from* to *to* as squares *grow*
## pixels out from each point, clipped to the picture.
func _line(image: Image, from: Vector2i, to: Vector2i, grow: int, colour: Color) -> void:
    var steps := maxi(absi(to.x - from.x), absi(to.y - from.y))
    for i: int in steps + 1:
        var t := float(i) / float(maxi(steps, 1))
        var at := Vector2i(Vector2(from).lerp(Vector2(to), t).round())
        for dy: int in range(-grow, grow + 1):
            for dx: int in range(-grow, grow + 1):
                var x := at.x + dx
                var y := at.y + dy
                if x >= 0 and y >= 0 and x < SIDE and y < SIDE:
                    image.set_pixel(x, y, colour)
