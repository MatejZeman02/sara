## The layers docker's capture entry points, kept out of `layer_list.gd`.
##
## The step table calls this class directly rather than through a forwarder on
## the list, so `ui` never names the harness for the sake of a detour.
##
## Its own file rather than a section of the list, because the two are different
## subjects: everything else on the list answers to the docker around it, and
## this answers to a scenario driving the application from outside. It is also
## the block that grows: every gesture a later scenario wants adds a static here
## and nothing to the list.
class_name SaLayerListCapture
extends RefCounted

## The built-in dockers' ids, and where a docker's Window is asked for by one.
const DockerIds := preload("res://ui/main/sa_docker_ids.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")


## Folds or unfolds a layer row: it presses the fold mark of a layer row with
## `{"layer_collapse": 1}`, and reports every row without pressing anything with
## `{"layer_collapse": ""}`.
##
## The press is a real one, into the docker's own `Window` at the rect the row
## reports, because what is in question is a mark drawn on a group row that
## nothing can act on. Calling the handler directly would prove
## the rebuild and not the control.
##
## A row below the docker's visible area is scrolled into view before its mark
## is pressed, as a painter would scroll to it.
##
## The report is what a picture cannot answer. A group with its children folded
## away and a group with no children look the same on screen, so the lines carry
## each row's depth, whether it is a group and which way its mark points. Its
## last line is the rows again as JSON, `SaCapture: layer_collapse [{"row": 0,
## "name": "Group 1", "kind": "group closed"}]`, for a client of the door.
static func collapse(tree: SceneTree, raw: Variant) -> String:
    var docker := CaptureRun.DockerLookup.window(tree, DockerIds.LAYERS)
    if docker == null or not "item_list" in docker:
        return "SaCapture: no layers docker to collapse a group in"
    var list: SaLayerList = docker.item_list
    var report: Array = list.row_report()

    # `str()` and not `String()`: the step's value is an int for a press and a
    # string for a report, and `String(0)` is a nonexistent constructor rather
    # than a cast, which cost this scenario a run.
    if str(raw) != "":
        var row := int(raw)
        if row < 0 or row >= report.size():
            return "SaCapture: no row %d to fold" % row
        var rect: Dictionary = report[row]["disclose_rect"]
        if rect.is_empty():
            return "SaCapture: row %d is not a group, so it has no fold mark" % row
        var scrolled := _scroll_to(list, row)
        rect = list.row_report()[row]["disclose_rect"]
        var at := _press_centre(tree, docker, rect)
        return (
            "SaCapture: pressed the fold mark of row %d at (%d, %d)%s"
            % [row, at.x, at.y, "" if scrolled == 0 else ", the list scrolled %d px to it" % scrolled]
        )

    var lines: Array[String] = ["SaCapture: %d layer rows" % report.size()]
    # The same rows once more as the step's verdict, one JSON line the door
    # hands a client, which keeps only the lines that start with the prefix and
    # so never saw the indented ones.
    var verdict: Array = []
    for i in report.size():
        var entry: Dictionary = report[i]
        var kind := "layer"
        if bool(entry.get("is_group", false)):
            kind = "group closed" if bool(entry.get("collapsed", false)) else "group open"
        var marks := "%s%s" % ["picked " if bool(entry["selected"]) else "", "active" if bool(entry["active"]) else ""]
        lines.append("  %2d  %-20s %-12s %s" % [i, str(entry["name"]), kind, marks])
        verdict.append({"row": i, "name": str(entry["name"]), "kind": kind})
    lines.append("SaCapture: layer_collapse %s" % JSON.stringify(verdict))

    # And then the document's own order, read from the document rather than
    # from the rows above it. The two are what the step has to keep apart: a
    # collapse changes which rows are drawn and nothing else, so these lines
    # have to read the same whichever way every mark points.
    var doc: SaDocument = docker.target_canvas.document if docker.target_canvas != null else null
    if doc == null:
        lines.append("  the docker has no document to read an order from")
        return "\n".join(lines)
    lines.append(
        (
            "  the document's active layer: %s, and the list's active row: %d"
            % [str(doc.active_layer.name) if doc.active_layer != null else "none", list.picked.selected_idx]
        )
    )
    var order: Array[String] = []
    for child in doc.get_children():
        var layer := child as SaLayer
        if layer == null or layer == doc.stroke_layer or layer.is_queued_for_deletion():
            continue
        var group := SaLayerStack.parent_of(layer)
        order.append("%s%s" % [str(layer.name), "" if group == null else " in %s" % group.name])
    lines.append("  the document's own order, bottom up: %s" % ", ".join(order))
    return "\n".join(lines)


## Presses a layer row's picture: the mask's picture on row 0 with
## `{"layer_picture": {"row": 0, "picture": "mask"}}`, and the layer's with
## `"picture": "layer"`, and `"double": true` beside it makes it a double click.
## A real press, for the reason `collapse` gives, and the
## answer is read back from the rows after it: which picture each row says the
## brush paints into, whether its mask is dimmed, and the document's
## `mask_target`, because a picked rim is two pixels of accent and not something
## to find in a shot. The press lands a frame later, so a scenario that wants the
## answer after it runs the step again with `"picture": ""`, which presses
## nothing.
static func press_picture(tree: SceneTree, raw: Dictionary) -> String:
    var docker := CaptureRun.DockerLookup.window(tree, DockerIds.LAYERS)
    if docker == null or not "item_list" in docker:
        return "SaCapture: no layers docker to press a picture in"
    var list: SaLayerList = docker.item_list
    var report: Array = list.row_report()
    var picture := str(raw.get("picture", ""))
    var pressed := ""
    if picture != "":
        var row := int(raw.get("row", 0))
        if row < 0 or row >= report.size():
            return "SaCapture: no row %d to press a picture on" % row
        var key := "mask_rect" if picture == "mask" else "thumb_rect"
        var rect: Dictionary = report[row][key]
        if rect.is_empty():
            return "SaCapture: row %d has no %s picture" % [row, picture]
        var double := bool(raw.get("double", false))
        var at := _press_centre(tree, docker, rect, double)
        var how := "double clicked" if double else "pressed"
        pressed = "%s the %s picture of row %d at (%d, %d), " % [how, picture, row, at.x, at.y]
    var lines: Array[String] = ["SaCapture: %s%d layer rows" % [pressed, report.size()]]
    for i in report.size():
        var entry: Dictionary = report[i]
        var mask := "no mask"
        if bool(entry.get("has_mask", false)):
            mask = "mask dimmed" if bool(entry.get("mask_dimmed", false)) else "mask"
        lines.append("  %2d  %-20s %-12s picked %s" % [i, str(entry["name"]), mask, str(entry.get("picked", ""))])
    var doc: SaDocument = docker.target_canvas.document if docker.target_canvas != null else null
    if doc != null:
        var owner := "none"
        for child in doc.get_children():
            var layer := child as SaLayer
            if layer != null and doc.mask_target != null and layer.mask == doc.mask_target:
                owner = str(layer.name)
            if layer != null:
                owner = _filter_owning(layer.filters, doc.mask_target, owner)
        owner = _filter_owning(doc.root_filters, doc.mask_target, owner)
        lines.append(
            "  the document's mask target: the mask of %s" % owner if owner != "none" else "  the document's mask target: none"
        )
    return "\n".join(lines)


## "the filter <key>" when one of *records* owns *mask*, and *owner* otherwise.
## A filter's mask belongs to no layer, so its record names it.
static func _filter_owning(records: Array[SaAttachedFilter], mask: SaMask, owner: String) -> String:
    for record in records:
        if mask != null and record.mask == mask:
            return "the filter %s" % record.key
    return owner


## Scrolls *list* until row *row* is in view, as a painter would before a
## press on it, and answers how far it moved, down positive. A row below the
## docker's visible area draws its mark where no press reaches it, so without
## this a fold through the door would do nothing for the lowest groups. The container
## moves its rows when it sorts, which it queues for the end of the frame, and
## the press is handed on before that, so it sorts here at once and the rows
## stand where the press is aimed.
static func _scroll_to(list: SaLayerList, row: int) -> int:
    var before := list.scroll_vertical
    list.ensure_control_visible(list.rows[row])
    if list.scroll_vertical != before:
        list.notification(Container.NOTIFICATION_PRE_SORT_CHILDREN)
        list.notification(Container.NOTIFICATION_SORT_CHILDREN)
    return list.scroll_vertical - before


## A left press and release at the centre of *rect*, a rectangle in the docker
## window's own coordinates, routed through the root. Answers the point in the
## root's coordinates.
static func _press_centre(tree: SceneTree, docker: Window, rect: Dictionary, double: bool = false) -> Vector2:
    # The docker's own corner plus the rect, then through the root, which is
    # the route `capture_hide` takes and the one that works. A push straight
    # into the docker `Window` reaches nothing: the same press, the same
    # coordinates and the same button, and the mark never turned. The embedded
    # subwindow is fed by the root's own routing, so a scenario has to hand the
    # event to the root and let it find the window.
    var at := (
        Vector2(docker.position) + Vector2(float(rect["x"]) + float(rect["w"]) * 0.5, float(rect["y"]) + float(rect["h"]) * 0.5)
    )
    var physical: Vector2 = tree.root.get_final_transform() * at
    var motion := InputEventMouseMotion.new()
    motion.position = physical
    motion.global_position = physical
    Input.parse_input_event(motion)
    # A double click is a plain pair and then a pair whose press carries the
    # flag, written here because a script's steps are outside the engine's
    # interval, as `SaFilterRowsCapture` writes it.
    for click: int in 2 if double else 1:
        for pressed: bool in [true, false]:
            var event := InputEventMouseButton.new()
            event.button_index = MOUSE_BUTTON_LEFT
            event.pressed = pressed
            event.double_click = pressed and click == 1
            event.position = physical
            event.global_position = physical
            Input.parse_input_event(event)
    return at
