## Draws a label or a button that cuts its text at a sweep of widths, and says
## at which of them the cut carried no mark.
##
## Godot's plain `OVERRUN_TRIM_ELLIPSIS` ends a cut text in "…" only while the
## text it keeps is six characters or more, so a setting that says "ellipsis"
## can draw a cut with nothing to show a character is gone. A suite that reads
## the setting proves nothing about the result, which is how a preset button's "Soft Er"
## went unnoticed. This draws the
## control, the way the suite draws the Layers row, and compares what it drew
## with the same control asked for two other cuts:
##
## - **`OVERRUN_NO_TRIMMING`** with `clip_text` off, which draws the whole
##   text, over the viewport and not only over the control, so what the control
##   cut off shows. A control that clips draws the same clipped picture whether
##   its cut has a mark or not, and would read as a text that fitted. A picture
##   that is the same as the control's own is a text that fitted, and one that
##   differs is a text that was cut, however the cut was made. A label that
##   wraps and keeps a number of lines hides the ones past them with this as
##   well, so a label that has lines it does not show counts as cut.
## - **`OVERRUN_TRIM_CHAR`**, a cut that never has a mark. A cut picture the
##   same as this one is a cut with none, and one that differs is a cut that
##   ends in the ellipsis.
##
## The control is lifted out of whatever holds it into a viewport of its own,
## because the containers that hold these controls keep them at a minimum
## width, which is what the overrun is there to avoid, and the width is what
## this sweeps. Its text, its font, its wrap and its lines are its own as the
## widget built it.
extends RefCounted

## Tall enough for the two lines a wrapped name keeps, at the largest font.
const HEIGHT := 96

## The step between two widths, in pixels. One, because the plain kind loses its
## mark at some widths and keeps it at the ones beside them.
const STEP := 1

## Narrower than this the control has no room for the mark itself, and a cut
## with nothing to show is not the fault.
const ROOM := 24

## The viewport the control is drawn in, a child of *host*.
var viewport: SubViewport


func _init(host: Node) -> void:
    viewport = SubViewport.new()
    viewport.size = Vector2i(ROOM, HEIGHT)
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    host.add_child(viewport)


## Frees the viewport, and with it whatever was lifted into it.
func release() -> void:
    viewport.free()


## Lifts *subject* into the viewport and draws it from *widest* down to *room*
## wide, `ROOM` unless a caller with a short word asks for less. Returns
## `{"cut": how many widths its text did not fit, "unmarked": the widths at
## which it was cut with no ellipsis}`.
##
## A button's icon is put aside while it is drawn, because the arrow of a
## dropdown is drawn by the engine outside a `_draw`, which it refuses with an
## error for every drawing, and the icon only takes room from the text.
##
## *subject* is a `Label` or a `Button`, and the property is set by name because
## neither is a common type that has it.
func sweep(subject: Control, widest: int, room: int = ROOM) -> Dictionary:
    if subject.get_parent() != null:
        subject.get_parent().remove_child(subject)
    subject.set_anchors_preset(Control.PRESET_TOP_LEFT)
    subject.custom_minimum_size.x = 0.0
    viewport.add_child(subject)
    viewport.size = Vector2i(widest, HEIGHT)
    subject.position = Vector2.ZERO

    var built: int = subject.get(&"text_overrun_behavior")
    var clipped: bool = subject.get(&"clip_text")
    var icon: Texture2D = null
    if subject is Button:
        icon = (subject as Button).icon
        (subject as Button).icon = null
    var cut := 0
    var unmarked: Array[int] = []
    for width in range(widest, room - 1, -STEP):
        subject.size = Vector2(width, HEIGHT)
        var as_built := _pixels(subject)
        subject.set(&"text_overrun_behavior", TextServer.OVERRUN_NO_TRIMMING)
        subject.set(&"clip_text", false)
        var whole := _pixels(subject)
        subject.set(&"clip_text", clipped)
        subject.set(&"text_overrun_behavior", TextServer.OVERRUN_TRIM_CHAR)
        var plainly_cut := _pixels(subject)
        subject.set(&"text_overrun_behavior", built)
        if as_built == whole and not _hides_lines(subject):
            continue
        cut += 1
        if as_built == plainly_cut:
            unmarked.append(width)
    if subject is Button:
        (subject as Button).icon = icon
    return {"cut": cut, "unmarked": unmarked}


## Whether *subject* is a label with more lines than it shows.
func _hides_lines(subject: Control) -> bool:
    var label := subject as Label
    return label != null and label.get_line_count() > label.get_visible_line_count()


## One drawing of the whole viewport. A suite runs
## inside one frame, so the control is told to draw itself rather than left to
## the deferred redraw that a `force_draw` would find still waiting.
func _pixels(subject: Control) -> PackedByteArray:
    RenderingServer.canvas_item_clear(subject.get_canvas_item())
    subject.notification(CanvasItem.NOTIFICATION_DRAW)
    RenderingServer.force_draw(false, 0.0)
    return viewport.get_texture().get_image().get_data()
