## The patch tool: a click inside a selection fills it out of its
## surround.
##
## Two methods on the Method row, both in `sa_patch.gd`. Texture copies patches
## of the picture from around the region and is the default, because a blemish
## a painter reaches for this tool over usually sits in a texture or across an
## edge. Smooth is a normalised convolution, which a soft gradient wants
## instead, since a gradient has no patch elsewhere that matches it.
##
## In the selection group of the toolbox rather than the paint group, because
## what it still acts on is a region: the one the painter selected, or the one
## the tool's own circle painted when there is no selection.
##
## **Three ways in, and all three are one call.** A click inside the selection
## is the gesture a painter reaches for, the Patch row on the tool's options is
## the command for a selection already made, which the Tool Options docker and
## the canvas's own right-click menu both show, and a drag with no selection is
## the tool's own region. The crop's Crop row is the same shape as the row for
## the same reason.
##
## **The region.** The tool works with no selection at all: it has a circle of
## its own, which is the software ring the descriptor asks for, sized by the
## Size row here, and the patch runs when the stroke is released. Dragging
## it stamps discs into an [SaSelection] of the tool's own, magenta while the
## pointer is down, and the release hands that mask to `sa_patch.gd` at the
## binding the document's selection would have used, so nothing under this file
## learns the mask came from anywhere else.
##
## **A live selection wins.** A painter who drew one meant it, so a press with a
## selection on the canvas patches that selection and paints no region.
extends ToolState

## The engine beside this file, reached by path the way `state_bucket_fill.gd`
## reaches the flood, rather than through the class cache.
const SaPatchScript = preload("res://modules/sara-base-modules/base/patch/sa_patch.gd")

## What the region is drawn in while the pointer is down: magenta, a colour no
## painting holds. Half transparent, because a painter aiming at a blemish has
## to see the blemish under the paint that is about to cover it.
const REGION_TINT := Color(1.0, 0.0, 1.0, 0.5)

## How wide the tool's own circle is to begin with, in document pixels. A little
## wider than the blemishes the tool was written for, because the fill draws
## from the ring outside what is painted and a circle that only just covers a
## spot leaves the fill nothing of the spot's own surround to read.
const DEFAULT_SIZE: float = 48.0

## The range of the Size row, which the gestures keep to as well.
const SIZE_MIN: float = 2.0
const SIZE_MAX: float = 400.0

## How far two stamps of the circle sit apart along a drag, as a fraction of the
## radius. The mask is a union of discs, so a spacing at the radius leaves the
## outline scalloped where the drag turns, and half of it is round to the eye at
## every angle without paying for a stamp a pixel.
const STAMP_SPACING: float = 0.5

## The diameter of the tool's own circle in document pixels, the `patch_size`
## option. A plain value rather than a view of a setting, the way the wand's
## tolerance is: it belongs to this tool and no other tool shares it.
var region_size: float = DEFAULT_SIZE

## How the region is drawn again, an `SaPatch.Method`, the `patch_method`
## option. Texture unless the painter picks Smooth.
var method: int = SaPatchScript.Method.TEXTURE

var _patch: SaPatchScript = null

## The mask a drag is painting, an [SaSelection] of this tool's own so that the
## engine below reads it exactly as it reads the document's. Null when no drag
## is in the air, which is what frees it: the release hands it over as a local
## and clears this in the same breath, so the chunks go with the stroke.
var _region: SaSelection = null

## Where the circle has been stamped, in document pixels, for the overlay to
## draw magenta and for a capture to count. The mask itself cannot be asked:
## reading it back is what hard rule 1 forbids.
var _stamps: PackedVector2Array = PackedVector2Array()

var _painting: bool = false


## Fills the selection out of its surround, as one undo step. The Patch row and
## a click inside the selection both land here.
##
## Answers the number of chunks it wrote, which is zero when there is no
## selection, no active layer, or the layer is locked.
func patch_now() -> int:
    var doc: SaDocument = document()
    if doc == null:
        return 0
    var layer := doc.active_layer
    if layer == null:
        return 0
    if not doc.selection.active:
        SaProblems.refuse("Patch", tr("There is no selection to patch. Draw one first."))
        return 0
    return _engine().patch(doc, layer, null, method)


func handle_input(event: InputEvent) -> void:
    var doc: SaDocument = document()
    if doc == null:
        return
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if button.pressed:
            _press(get_document_mouse_position())
        elif _painting:
            _release()
        return
    if _painting and event is InputEventMouseMotion:
        _extend(get_document_mouse_position())


## A left press: the selection's patch when there is one, and the first stamp of
## the tool's own region when there is not.
func _press(at: Vector2) -> void:
    var doc: SaDocument = document()
    if doc.selection.active:
        if not _inside(Vector2i(floori(at.x), floori(at.y))):
            # A click outside the selection is a painter aiming at the wrong
            # place, not a request to patch somewhere else: with a selection on
            # the canvas the tool has one region and it is the one with the ants
            # round it.
            return
        patch_now()
        return
    _region = SaSelection.new()
    _stamps = PackedVector2Array()
    _painting = true
    _stamp(at)


## The drag: the circle stamped along the segment the pointer travelled, so the
## region is what the hand covered rather than where the motions happened to
## land. A motion is one a frame at best and a hand crosses more than a radius
## in a frame often enough that stamping the endpoints alone leaves a dotted
## line.
func _extend(to: Vector2) -> void:
    var from := _last_stamp()
    var spacing := maxf(region_size * 0.5 * STAMP_SPACING, 1.0)
    var span := from.distance_to(to)
    if span < spacing:
        return
    for i in range(1, floori(span / spacing) + 1):
        _stamp(from.lerp(to, minf(float(i) * spacing / span, 1.0)))


## The release: the region is patched and then gone.
##
## The mask is taken into a local and this tool's own reference cleared before
## the fill runs, so the chunks are freed the moment the fill returns however it
## returned. A region kept until the next press would hold a chunk per 256
## pixels of the drag for as long as the painter looked at the result.
func _release() -> void:
    var doc: SaDocument = document()
    # The pointer where it was let go, so the region ends where the hand did
    # rather than at the last stamp the spacing happened to allow. Without it a
    # drag that stops a third of a spacing past its last disc leaves that third
    # unpatched, which a painter reads as the tool missing the end of the mark.
    # A release on the last disc's own point costs no dispatch, which is the
    # common case of a hand that let go without moving.
    var at := get_document_mouse_position()
    if _region != null and not at.is_equal_approx(_last_stamp()):
        _stamp(at)
    _painting = false
    var region := _region
    _region = null
    _stamps = PackedVector2Array()
    if region == null or doc == null:
        return
    var layer := doc.active_layer
    if layer == null:
        return
    _engine().patch(doc, layer, region, method)


## One disc of the circle at *at*, added to the region.
##
## Through [method SaSelection.select_ellipse] in add mode rather than a kernel
## of this tool's own, which is hard rule 6 read inwards: the selection already
## writes an ellipse over its own box and nothing else, so a stamp is one
## dispatch over a circle's worth of texels and the tool ships no shader.
func _stamp(at: Vector2) -> void:
    var radius := maxf(region_size * 0.5, 0.5)
    var side := ceili(radius * 2.0)
    var box := Rect2i(Vector2i(roundi(at.x - radius), roundi(at.y - radius)), Vector2i(side, side))
    _region.select_ellipse(box, SaSelection.Mode.ADD)
    _stamps.append(at)


## Where the last disc went, or the pointer when none has gone anywhere yet.
func _last_stamp() -> Vector2:
    return _stamps[_stamps.size() - 1] if not _stamps.is_empty() else get_document_mouse_position()


## The region so far, for the overlay to draw in magenta while the pointer is
## down. Discs rather than a line, because the mask is a union of discs and a
## preview that draws a different shape from the one the fill will read is a
## preview of nothing.
func preview_shape() -> Dictionary:
    if not _painting or _stamps.is_empty():
        return {}
    return {"discs": _stamps.duplicate(), "radius": maxf(region_size * 0.5, 0.5), "fill": REGION_TINT}


## The circle the painter paints the region with, which is what the ring on the
## canvas is drawn at. Positive whatever the selection says, because the ring is
## how a painter reads the size row, and a tool that offers a size and shows no
## circle for it is a row with nothing under it.
func get_cursor_radius() -> float:
    return maxf(region_size * 0.5, 0.5)


## The circle's width, which is what the bracket keys and a shift-drag resize,
## as they resize a brush.
func own_size() -> float:
    return region_size


## Kept inside the range the Size row offers, so a key held down cannot take the
## circle anywhere the row could not follow.
func resize_own(size: float) -> void:
    region_size = clampf(size, SIZE_MIN, SIZE_MAX)


## A drag dropped when the tool is switched away from, or the document rebuilt,
## takes its mask with it.
func reset() -> void:
    _painting = false
    _region = null
    _stamps = PackedVector2Array()


## What a capture's state dump says about this tool: the method, whether there
## is a selection to patch and how big its rectangle is, because a shot of a
## patched picture cannot show what was selected before it, and with no
## selection the region block below instead.
##
## The work a patch of that selection would do is said in the method's own
## terms: the sweeps Smooth runs, or the rectangle Texture copies patches out of
## and the levels of its pyramid.
func capture_report(_tool_name: StringName, active: bool) -> Dictionary:
    var doc: SaDocument = document()
    if not active or doc == null:
        return {}
    var selection := doc.selection
    if not selection.active:
        var idle := _region_block()
        idle["method"] = _method_name()
        return {"patch": idle}
    var bounds := selection.bounds
    var block := {
        "selection": true,
        "method": _method_name(),
        "bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
    }
    var work := SaPatchScript.work_for(bounds, doc.canvas_size, method)
    if method == SaPatchScript.Method.SMOOTH:
        block["passes"] = SaPatchScript.passes_for(work.size)
    else:
        var hole := Rect2i(bounds.position - work.position, bounds.size)
        block["work"] = [work.position.x, work.position.y, work.size.x, work.size.y]
        block["levels"] = SaPatchScript.SaPatchMatchScript.levels_for(work.size, hole)
    return {"patch": block}


## The method's name as the Method row shows it, lower case for a dump.
func _method_name() -> String:
    return "smooth" if method == SaPatchScript.Method.SMOOTH else "texture"


## What the dump says with no selection: the size of the tool's own circle, and
## the region a drag has painted while it is in the air.
##
## The stamps are counted and their box named rather than listed, because a drag
## across a picture is a few hundred of them and what a reader of a dump asks is
## whether the region went where the pointer did and how much of the canvas it
## claimed. A shot cannot answer the second at all: the magenta is half
## transparent and the box is not drawn.
func _region_block() -> Dictionary:
    var block := {"selection": false, "size": region_size, "painting": _painting}
    if _region == null or not _region.active:
        return block
    var bounds := _region.bounds
    block["stamps"] = _stamps.size()
    block["region_bounds"] = [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]
    block["region_chunks"] = _region.chunks.size()
    return block


## Whether *point* is inside the selection's rectangle.
##
## The rectangle rather than the mask, and that is hard rule 1 rather than
## laziness: asking whether one texel of the mask is set means reading a texture
## back to the CPU, and the only things allowed to do that are export, the
## eyedropper and the capture's texel step. So a click in the empty corner of an
## ellipse's box counts as inside, and what it does there is patch the ellipse,
## which is the only region the tool has.
func _inside(point: Vector2i) -> bool:
    var doc: SaDocument = document()
    var selection := doc.selection
    return selection.bounds.has_point(point)


## The patch engine under the `patch` role when the machine handed this tool
## the registries, so a module's own method is what the tool patches with,
## and `SaPatch` itself when nothing did.
func _engine() -> SaPatchScript:
    if _patch == null:
        var claimed: Script = roles.script_for(&"patch") if roles != null else null
        _patch = (claimed if claimed != null else SaPatchScript).new()
    return _patch
