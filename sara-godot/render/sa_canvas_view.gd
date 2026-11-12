## SaView implemented over SaCanvas. The only place that knows a view is a Control.
##
## Keeping this adapter in render/ is what lets core/ hold SaView without
## depending on a TextureRect, and what lets a headless test supply a fake view.
class_name SaCanvasView
extends SaView

## The group a Control joins when it is drawn over the canvas along a whole top
## or bottom edge, the way the top bar is. Every fit and centre place the
## document in what such covers leave.
const COVER_GROUP := &"sa_canvas_cover"

## The group a `Window` joins when it floats over the canvas beside the
## document, the way every docker does. A fit and a centre place the document in
## the room such windows leave between them, and Fit to Window does not.
const SIDE_COVER_GROUP := &"sa_canvas_side_cover"

## How near its window edge a side cover's outer side stands for it to count as
## standing against that edge, in the units the windows are placed in: the
## Toolbox's 60 and the gap every shipped layout leaves beside it. A docker
## against an edge always moves it, which is what a docker column is.
const EDGE_REACH: float = 100.0

## The narrowest a docker floating further in may leave the free rectangle, as a
## share of the visible width. One that would leave less is skipped, which keeps
## the Useful layout's Info docker, standing beside the left column and leaving
## 710 of 1920, from squeezing the painting into a strip.
##
## Only a floating docker meets the floor. Applied to every docker, a half
## skipped the left column of the Default layout on a 1280 by 1024 window, whose
## columns leave 580, and two fifths skipped it at an interface scale of 1.25
## there, where they leave 324 of 1024. Either puts a third of the painting
## under Brush Presets and Tool Options on that window, and no share of the
## width tells the Info docker at 1920 from the columns at 1024.
const FREE_WIDTH_FLOOR: float = 0.5

var canvas: SaCanvas


static func for_canvas(target_canvas: SaCanvas) -> SaCanvasView:
    return target_canvas.view()


## The canvas the painter is working on: the one the front surface draws into.
##
## The one lookup for "the" canvas under `render` and the modules, here
## because this is the file that knows a view is a Control over an `SaCanvas`.
## `SaDocuments` says which surface is in front and
## `EventBus.active_document_changed` says when that moved, so a second open
## document changes this answer and no caller learns about tabs. The three
## routes it replaces - the canvas in the root window, the first live canvas
## with a document, and the one a docker was handed at boot - each name one
## canvas only while one document is open.
##
## Null while no owner is reachable, which is a headless suite and a harness
## run with no main scene: there is no front document to answer with, and
## every caller already guards a canvas it may not have yet.
static func front_canvas() -> SaCanvas:
    var tree := Engine.get_main_loop() as SceneTree
    return canvas_of(SaDocuments.front_in(tree.current_scene)) if tree != null else null


## The canvas *surface* draws into, null for a surface shown through a view
## that is not a Control: a suite's fake view, and whatever a module gives a
## surface of its own. Apart from [method front_canvas] so a caller holding a
## surface already, and a suite that builds its own owner, ask the same
## question without a scene.
static func canvas_of(surface: SaSurface) -> SaCanvas:
    var view := surface.view as SaCanvasView if surface != null else null
    return view.canvas if view != null else null


## Document pixels. Correct outside the document bounds too, which matters
## because painting out of bounds is legal - chunks are sparse. While the
## canvas is shown as the sky, the pixel the camera's ray through the pointer
## lands on, which the Environment view answers.
##
## On a document that wraps, a point on a copy of the page is taken back into
## the page by whole turns before any tool sees it, `SaWrapRepeat.in_the_page`,
## so a press on a copy paints the document. Here rather than in each tool,
## because this is the one door every tool reads the pointer through.
func get_document_mouse_position() -> Vector2:
    if canvas == null or not canvas.is_inside_tree():
        return Vector2.ZERO
    var sky := SaEnvironmentView.of_canvas(canvas)
    if sky != null and sky.on:
        return sky.pointer()
    return SaWrapRepeat.in_the_page(canvas, SaCursorPolicy.pointer_in(canvas))


## *to* on the flat canvas, and the copy of it the short way round the seam
## from *from* while the canvas is shown as the sky.
func line_towards(from: Vector2, to: Vector2) -> Vector2:
    var sky := SaEnvironmentView.of_canvas(canvas)
    return sky.line_towards(from, to) if sky != null and sky.on else to


## The sky's stretch while the Environment view is on, and the flat dab's
## nought while it is off.
func dab_stretch(pixel: Vector2) -> float:
    var sky := SaEnvironmentView.of_canvas(canvas)
    return sky.dab_stretch(pixel) if sky != null and sky.on else 0.0


## The magnitude of the canvas's scale. A mirrored view carries the sign on the
## same Control property, and a zoom that came back negative would divide every
## document coordinate the wrong way round, so the sign is get_flip's business
## and never this one's.
func get_zoom() -> float:
    return absf(canvas.scale.x) if canvas != null else 1.0


func set_zoom(value: float) -> void:
    if canvas == null:
        return
    var clamped := maxf(0.001, value)
    var wanted := get_flip() * clamped
    if canvas.scale.is_equal_approx(wanted):
        return
    canvas.scale = wanted
    transform_changed.emit()


## Which way round the canvas is drawn, read off the sign of its scale. A
## Control mirrors by a negative scale, so the mirror needs no second transform
## and the child overlays, the axes and the selection outline follow it.
func get_flip() -> Vector2:
    if canvas == null:
        return Vector2.ONE
    return Vector2(-1.0 if canvas.scale.x < 0.0 else 1.0, -1.0 if canvas.scale.y < 0.0 else 1.0)


func set_flip(value: Vector2) -> void:
    if canvas == null:
        return
    var zoom := get_zoom()
    var wanted := Vector2(-zoom if value.x < 0.0 else zoom, -zoom if value.y < 0.0 else zoom)
    if canvas.scale.is_equal_approx(wanted):
        return
    canvas.scale = wanted
    transform_changed.emit()


## The canvas keeps its pivot at the origin (sa_canvas.gd pins it there), which
## is what makes SaView's anchored maths hold: Godot rotates a Control about its
## pivot, and a pivot at the origin means screen = position + rotate(local * scale).
func get_rotation() -> float:
    return canvas.rotation if canvas != null else 0.0


func set_rotation(value: float) -> void:
    if canvas == null or is_equal_approx(canvas.rotation, value):
        return
    canvas.rotation = value
    transform_changed.emit()


func get_viewport_size() -> Vector2:
    if canvas == null or not canvas.is_inside_tree():
        return Vector2.ZERO
    return canvas.get_viewport_rect().size


## The viewport less the strips the covers in its tree draw along its top and
## bottom edges. A cover whose middle is in the upper half hides everything
## above its bottom edge, and one in the lower half everything below its top,
## so the answer does not depend on the order the group lists them in.
##
## A group rather than a reference, because the top bar is built by `ui/` after
## this canvas and `render/` does not know it exists. A hidden cover hides
## nothing, which is what focus mode wants, and a cover in another viewport is
## not over this canvas, which is what the Info docker's scratchpad wants. Read
## in viewport coordinates, the same space `get_viewport_size` assumes the pan
## is in.
func get_visible_rect() -> Rect2:
    var whole := Rect2(Vector2.ZERO, get_viewport_size())
    if whole.size.y <= 0.0:
        return whole
    var top := 0.0
    var bottom := whole.size.y
    for node in canvas.get_tree().get_nodes_in_group(COVER_GROUP):
        var cover := node as Control
        if cover == null or not cover.is_visible_in_tree() or cover.get_viewport() != canvas.get_viewport():
            continue
        var rect := cover.get_global_rect()
        if rect.get_center().y < whole.size.y * 0.5:
            top = maxf(top, rect.end.y)
        else:
            bottom = minf(bottom, rect.position.y)
    # A cover taller than the window leaves nothing to fit into, and the whole
    # area is a better answer than a fit to zero.
    if bottom - top <= 0.0:
        return whole
    return Rect2(0.0, top, whole.size.x, bottom - top)


## The part of the document the window shows, in document pixels: the
## visible rectangle taken back through the canvas's turn, flip, zoom and pan,
## as the box that holds it, within the document. An open reads these chunks
## first.
func shown_document_rect() -> Rect2i:
    var shown := canvas.get_global_transform_with_canvas().affine_inverse() * get_visible_rect()
    var box := Rect2i(Vector2i(shown.position.floor()), Vector2i(shown.size.ceil()) + Vector2i.ONE)
    return box.intersection(Rect2i(Vector2i.ZERO, canvas.canvas_size))


## Makes *target_canvas* a document of *size* as an open over frames lands its stack
## with the chunks still to come, and answers the part of it the window shows,
## which the open reads first. An empty rectangle for no canvas.
static func landed(target_canvas: SaCanvas, size: Vector2i) -> Rect2i:
    if not is_instance_valid(target_canvas):
        return Rect2i()
    target_canvas.resize_canvas(size)
    return for_canvas(target_canvas).shown_document_rect()


## The visible rectangle less the dockers standing along its sides, the room a
## fit and a centre place the document in.
##
## A side cover whose middle is left of the visible rectangle's moves the left
## edge to its right side, and one right of it moves the right edge to its left
## side. Every one standing against its window edge, within `EDGE_REACH`, moves
## its edge. The ones floating further in are walked from each window edge
## inward afterwards, the one whose inner side is nearest its own edge first,
## and each is skipped when it would leave less than `FREE_WIDTH_FLOOR` of the
## visible width. So the columns along the edges count, a docker floating in
## the middle does not, and the answer does not depend on the order the group
## lists them in.
##
## Only a side cover that is shown, embedded in this canvas's viewport and over
## the visible rectangle counts. A docker hidden by Tab hides nothing, so with
## the dockers hidden the free rectangle is the visible one, and a docker let
## out as a window of its own, or one in a secondary workspace, stands in front
## of another viewport. Read off the windows' own rectangles in the host's
## space, the space `get_visible_rect` answers in.
func get_free_rect() -> Rect2:
    var area := get_visible_rect()
    if area.size.x <= 0.0 or canvas == null or not canvas.is_inside_tree():
        return area
    var against: Array[Rect2] = []
    var floating: Array[Rect2] = []
    for node in canvas.get_tree().get_nodes_in_group(SIDE_COVER_GROUP):
        var side := node as Window
        if side == null or not side.visible or not side.is_embedded():
            continue
        var host := side.get_parent()
        if host == null or host.get_viewport() != canvas.get_viewport():
            continue
        var rect := Rect2(Vector2(side.position), Vector2(side.size))
        if not rect.intersects(area):
            continue
        if _gap(rect, area) <= EDGE_REACH:
            against.append(rect)
        else:
            floating.append(rect)
    floating.sort_custom(func(a: Rect2, b: Rect2) -> bool: return _reach(a, area) < _reach(b, area))
    var free := area
    for rect in against:
        free = _beside(free, rect, area)
    var narrowest := area.size.x * FREE_WIDTH_FLOOR
    for rect in floating:
        var moved := _beside(free, rect, area)
        if moved.size.x >= narrowest:
            free = moved
    # Columns that meet leave nothing to fit into, and the whole area is a
    # better answer than a fit to zero, as it is under the covers.
    return free if free.size.x > 0.0 else area


## *free* with its edge on *rect*'s side moved to *rect*'s inner side.
static func _beside(free: Rect2, rect: Rect2, area: Rect2) -> Rect2:
    var left := free.position.x
    var right := free.end.x
    if rect.get_center().x < area.get_center().x:
        left = maxf(left, rect.end.x)
    else:
        right = minf(right, rect.position.x)
    return Rect2(left, free.position.y, right - left, free.size.y)


## How far *rect*'s outer side stands from the window edge it is along.
static func _gap(rect: Rect2, area: Rect2) -> float:
    if rect.get_center().x < area.get_center().x:
        return rect.position.x - area.position.x
    return area.end.x - rect.end.x


## How far *rect*'s inner side stands from the window edge it is along, which is
## the order the walk takes the floating side covers in.
static func _reach(rect: Rect2, area: Rect2) -> float:
    if rect.get_center().x < area.get_center().x:
        return rect.end.x - area.position.x
    return area.end.x - rect.position.x


func get_pan() -> Vector2:
    return canvas.position if canvas != null else Vector2.ZERO


func set_pan(value: Vector2) -> void:
    if canvas == null or canvas.position == value:
        return
    canvas.position = value
    transform_changed.emit()


## The window's content scale factor, which is the interface scale
## `SaUI.apply_to_window` wrote and the second of the two scalings that stack
## between a texel and a device pixel. One before the canvas is in a tree,
## where there is no window to ask.
func get_content_scale() -> float:
    if canvas == null or not canvas.is_inside_tree():
        return 1.0
    var window := canvas.get_window()
    return window.content_scale_factor if window != null else 1.0
