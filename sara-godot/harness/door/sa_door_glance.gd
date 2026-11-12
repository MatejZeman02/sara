## What an agent painting beside the painter sees of the document: the view
## line every answer carries, the `glance` step's one screen, and the counter
## that says the painter changed the document since the last step.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## An agent sharing one running Sara with a painter through the door does not
## see the painter rename a layer or move a group, and a dump of the whole state
## is too long to read before every batch. So every answer says whether the
## painter changed the document since the door's last step, and `glance` is the state an agent
## reads before a batch, short enough to read every time.
##
## **The view line is here rather than in the door**, which stands at its line
## budget and takes nothing more. It says where the document sits in the window and
## `glance` says which part of it the window shows, two readings of the same
## transform, so they live together.
class_name SaDoorGlance
extends RefCounted

const CaptureRun := preload("res://harness/sa_capture_run.gd")
## The harness's one lookup for the document the painter is working on.
const CanvasDriver := preload("res://harness/drivers/sa_canvas_driver.gd")


## The painter's changes to the document, counted between the door's steps.
##
## Every change the document announces is heard: `document_changed`, which a
## rename, a lock, a fill and a transform's end emit, the history's
## `version_changed`, which every step it takes and every undo and redo emit,
## a stroke and an opacity drag among them, and the canvas showing another
## document, which is a New or an Open. A change heard while a door step runs,
## from the request being taken to its answer, is the door's own and is not
## counted, so the counter moves only for what a hand did. A painter's change
## inside those few frames is counted as the door's, which is the price of
## telling the two apart without the document knowing who changed it.
##
## The door has one counter for as long as it listens, across connections,
## because `curl` opens one a request and a connection is no longer a
## conversation. "Since the last step" means the last step anyone sent.
class Changes:
    extends RefCounted

    ## How many changes the painter has made since the door opened.
    var count: int = 0

    ## Changes heard since the last answer, the door's and the painter's.
    var _heard: int = 0
    ## Whether the painter changed anything between the last answer and the
    ## request now running, read when the request was taken.
    var _moved: bool = false
    var _document: SaDocument = null
    var _history: UndoRedo = null

    ## A request was taken: what was heard since the last answer is the
    ## painter's, and from here until the answer it is the door's.
    func step_begins() -> void:
        _follow()
        _moved = _heard > 0
        count += _heard
        _heard = 0

    ## The answer is going out: says whether the counter moved before this
    ## step and where it stands, and forgets what the step itself changed.
    func stamp(answer: Dictionary) -> void:
        _follow()
        _heard = 0
        answer["changed"] = _moved
        answer["changes"] = count

    func _hear() -> void:
        _heard += 1

    ## Listens to the document in front, and counts a document that replaced
    ## the one it listened to as a change. A document brought forward is
    ## another document, so it reads as a change too, which is what an agent
    ## sharing the app with a painter has to be told about before it paints.
    func _follow() -> void:
        var canvas := CanvasDriver.main_canvas()
        var document := canvas.document if canvas != null else null
        if document == _document and (document == null or document.undo_redo == _history):
            return
        if is_instance_valid(_document) and _document.document_changed.is_connected(_hear):
            _document.document_changed.disconnect(_hear)
        if _history != null and _history.version_changed.is_connected(_hear):
            _history.version_changed.disconnect(_hear)
        if _document != null:
            _hear()
        _document = document
        _history = document.undo_redo if document != null else null
        if document != null:
            document.document_changed.connect(_hear)
        if _history != null:
            _history.version_changed.connect(_hear)


## Where the front document sits in the window: the point its pixel (0, 0)
## lands on, the zoom and the turn, so a stroke can be aimed without a
## screenshot. Read off the same transform a stroke in document pixels is
## carried through.
##
## The front surface's canvas whatever it holds, rather than the driver's
## narrowing to one with a document, because a view has a place in the window
## before a picture is loaded into it.
static func view_line() -> String:
    var canvas := SaCanvasView.front_canvas()
    if canvas == null:
        return "view: no canvas in front"
    var view := canvas.get_global_transform_with_canvas()
    var size := Vector2i(canvas.canvas_size)
    return (
        "view: document %dx%d, its (0, 0) at (%.1f, %.1f) in the window, zoom %s, turned %s degrees%s"
        % [
            size.x,
            size.y,
            view.origin.x,
            view.origin.y,
            String.num(view.get_scale().abs().x, 4),
            # Plus nought, so a turn of minus nought reads as none.
            String.num(snappedf(rad_to_deg(view.get_rotation()), 0.1) + 0.0, 1),
            ", mirrored" if view.determinant() < 0.0 else "",
        ]
    )


## Prints the state to read before painting: the `layers` line, then
## `SaCapture: glance <json>`, one screen with the stack and the hand.
##
## Read before each batch, and again whenever an answer's `changed` is true,
## rather than painting from what was seen an hour ago. The glance names the
## active `tool`, the brush `preset` in hand, `""` for none, the foreground
## `colour` as hex, the brush's `size` across in document pixels and its
## `opacity`, null for a tool with neither, `selection`, the selection's
## `[x, y, w, h]` or null for none, and `shows`, the `[x, y, w, h]` of the
## document the window shows clear of the top bar and the docker columns, so a
## stroke aimed inside it lands on the canvas and not under a docker. `shows` is
## null when no part of the document is in view.
##
## **Arguments.**
## - `glance` boolean, true.
static func capture(run: CaptureRun, layers_line: String) -> String:
    var tree := run.tree()
    var root := tree.root if tree != null else null
    var canvas := CanvasDriver.main_canvas()
    var document := canvas.document if canvas != null else null
    var settings := _brush_settings(root)
    var tool := canvas.tool_machine().active_tool if canvas != null and canvas.tool_machine() != null else null
    var radius := tool.get_cursor_radius() if tool != null else -1.0
    var selection: Variant = null
    if document != null and document.selection.active:
        selection = _rect(Rect2(document.selection.bounds))
    var shown := shows(canvas)
    # Assigned rather than written as ternaries in the literal: a number or an
    # array and a null are not mutually compatible and the language server says so.
    var size: Variant = null
    if radius > 0.0:
        size = snappedf(radius * 2.0, 0.1)
    var in_view: Variant = null
    if shown.has_area():
        in_view = _rect(shown)
    var glance := {
        "tool": run.active_tool_name(),
        "preset": _preset_name(root),
        "colour": "#" + SaColors.foreground.to_html(false),
        "size": size,
        "opacity": settings.get("opacity") if settings != null else null,
        "selection": selection,
        "shows": in_view,
    }
    return "%s\nSaCapture: glance %s" % [layers_line, JSON.stringify(glance)]


## The part of *canvas*'s document its window shows clear of the covers, in
## document pixels and inside the document: the free rectangle the fit uses,
## carried back through the view and cut to the document's own bounds. An
## empty rectangle when none of it shows. A turned view answers the box around
## what shows.
static func shows(canvas: SaCanvas) -> Rect2:
    if canvas == null or not canvas.is_inside_tree():
        return Rect2()
    var free := canvas.view().get_free_rect()
    var back := canvas.get_global_transform_with_canvas().affine_inverse()
    var corners := [free.position, Vector2(free.end.x, free.position.y), free.end, Vector2(free.position.x, free.end.y)]
    var box := Rect2(back * (corners[0] as Vector2), Vector2.ZERO)
    for corner: Vector2 in corners:
        box = box.expand(back * corner)
    return box.intersection(Rect2(Vector2.ZERO, Vector2(canvas.canvas_size)))


static func _rect(rect: Rect2) -> Array:
    return [roundi(rect.position.x), roundi(rect.position.y), roundi(rect.size.x), roundi(rect.size.y)]


## The tool options bar in *root*, which holds the preset in hand.
static func _bar(root: Window) -> ToolOptionsBar:
    if root == null:
        return null
    for node in root.find_children("*", "HBoxContainer", true, false):
        if node is ToolOptionsBar:
            return node as ToolOptionsBar
    return null


static func _preset_name(root: Window) -> String:
    var bar := _bar(root)
    return bar.preset_box.selected_preset if bar != null and bar.preset_box != null else ""


## The settings of the brush in hand, what the bar shows, or null.
static func _brush_settings(root: Window) -> Resource:
    var bar := _bar(root)
    if bar == null or bar.preset_box == null or not bar.preset_box.settings_source.is_valid():
        return null
    return bar.preset_box.settings_source.call() as Resource
