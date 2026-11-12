## Filter > Wrap Offset, the transform that shifts the canvas round on
## itself.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Paint pushed off one edge comes back in at the opposite one, modulo the
## canvas, which is how a tileable texture is painted across its own seam: wrap
## by half the canvas, paint over the seam now in the middle, wrap back.
##
## **A wrap reads the whole canvas.** The source of one texel may be anywhere,
## so the run records a pass that reads the whole node rather than a radius.
## A source offset declared beside the radius would let a chunk
## gather only the four chunks its displaced rectangle touches. No such
## door exists, and the whole-node door is the one the tree has, so every
## evaluation gathers the node once. The write stays on the dirty region, and
## the pass declares the displacement its paint moves by, so both forms write
## where the node's chunks land as well as where they are: a stroke on the
## left edge wrapped by half the canvas shows in the middle, on ground the
## layer never allocated.
##
## **A selection does not narrow the read.** A wrap of part of the canvas is not
## a wrap, so the source is the whole node whatever is selected, and the write
## goes through the selection mask the way every filter's does.
class_name SaWrapOffsetFilter
extends SaFilter

## How far a drag on either slider reaches either way, in pixels, so nought
## sits at the middle of its track, and how far a typed value may go. Any
## value is meaningful, since the kernel reduces it modulo the canvas.
const SOFT_REACH: int = 2048
const HARD_REACH: int = 16384

## The canvas the last run saw, which "Half the canvas" halves. The dialog runs
## the filter when it opens, so this is set before the button can be pressed.
var _canvas: Vector2i = Vector2i.ZERO


func title() -> String:
    return "Wrap Offset"


## No: a pixel reads the one the offset carries to it, which can be anywhere
## on the layer, so a brush has nothing local to paint.
func can_be_a_brush() -> bool:
    return false


## Listed under Distort in the Filter menu and the browser.
func family() -> StringName:
    return &"distort"


func sentence() -> String:
    return "Shift the whole canvas round on itself, so what leaves one edge comes back at the other, for painting a tile's seam."


func build(ui: SaDialog) -> void:
    var hard := {"hard_min": -HARD_REACH, "hard_max": HARD_REACH}
    ui.slider("Offset X", -SOFT_REACH, SOFT_REACH, 0, hard)
    ui.slider("Offset Y", -SOFT_REACH, SOFT_REACH, 0, hard)
    # A weak reference, because the button the dialog owns holds this callable
    # and a strong one would be the dialog holding itself.
    ui.button("Half the canvas", _to_half.bind(weakref(ui)))


func run(ctx: SaFilterContext) -> void:
    # A margin past any canvas answers the canvas itself, which rect_for clamps
    # to, whatever is selected or painted.
    _canvas = ctx.rect_for(HARD_REACH * 4).size
    var moved := _offset()
    var params := {"offset": Vector2(moved), "canvas": Vector2(_canvas)}
    ctx.neighbourhood_pass("wrap_offset", "wrap_offset", params, SaNeighbourhoodPass.WHOLE_NODE)
    var recorded := ctx.point as SaNeighbourhoodPass
    recorded.writes = SaNeighbourhoodPass.WRITES_DISPLACED
    recorded.displacement = moved


func _offset() -> Vector2i:
    return Vector2i(int(parameter(&"offset_x")), int(parameter(&"offset_y")))


## Puts the seam in the middle of the picture, which is what the filter is for.
func _to_half(dialog: WeakRef) -> void:
    var ui := dialog.get_ref() as SaDialog
    if ui == null:
        return
    write_parameter(&"offset_x", _canvas.x / 2.0)
    write_parameter(&"offset_y", _canvas.y / 2.0)
    ui.request_rerun()
