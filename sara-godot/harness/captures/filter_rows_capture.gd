## The `filter_rows` step: attached filters in the layers docker, driven and read
## from a scenario.
##
## `{"filter_rows": {"attach": "base.levels", "layer": "Group 1"}}` attaches the
## filter of that key to the layer of that name, or to the document's root
## without one, through `SaFilterOps`, with optional `"params"` and `"enabled"`.
## Attaching here does not need the menu, so a scenario has something to list
## whatever the menus hold. `{"filter_rows": {"press": 2}}` presses row 2 with a real
## mouse press at the rect the row reports, `"double": true` beside it makes
## that press the second of a pair, which is what the engine hands a row as
## `InputEventMouseButton.double_click`, `{"filter_rows":
## {"eye": 2}}` presses its eye, `{"filter_rows": {"flatten": 2}}` flattens the
## record on row 2 as the panel's Flatten button does, with no question asked
## and `{"filter_rows": ""}` prints every row and the panel the tool
## options docker is showing.
##
## The presses are real ones through the root, for the reason
## `SaLayerListCapture.collapse` records: an embedded docker is fed by the
## root's own routing, and calling the handler would prove the handler and not
## the row.
class_name SaFilterRowsCapture
extends RefCounted

## The built-in dockers' ids, and where a docker's Window is asked for by one.
const DockerIds := preload("res://ui/main/sa_docker_ids.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")


## Drives the filter rows: those of the layers docker and of the tool options
## docker, `{"filter_rows": {"attach": key, "layer": name}}` attaches a filter
## to the layer of that name or to the root without one, and an attach under an
## active selection takes it as the record's mask and its answer says so in the
## Filter dialog's words, `{"press": row}` and
## `{"eye": row}` press a row or its eye with a real mouse press, `"double":
## true` makes the press the second of a double click, and `{"filter_rows": ""}`
## prints every row of the layers docker and the filter panel the tool options
## docker is showing.
static func run(tree: SceneTree, document: SaDocument, raw: Variant) -> String:
    var spec: Dictionary = raw if raw is Dictionary else {}
    if spec.has("attach"):
        return _attach(tree, document, spec)
    var docker := CaptureRun.DockerLookup.window(tree, DockerIds.LAYERS)
    if docker == null or not "item_list" in docker:
        return "SaCapture: no layers docker to list a filter in"
    var list: SaLayerList = docker.item_list
    if spec.has("press"):
        return _press(tree, docker, list, int(spec["press"]), "rect", bool(spec.get("double", false)))
    if spec.has("eye"):
        return _press(tree, docker, list, int(spec["eye"]), "eye_rect")
    if spec.has("flatten"):
        return _flatten(document, list, int(spec["flatten"]))
    return _report(tree, list)


static func _flatten(document: SaDocument, list: SaLayerList, row: int) -> String:
    var view := list.filter_at(row)
    if document == null or view == null:
        return "SaCapture: no filter on row %d to flatten" % row
    var ops := SaFilterOps.new(document)
    var node := ops.node_of(view.record)
    var said := ops.flatten_sentence(node, view.record)
    if not ops.flatten(node, view.record):
        return "SaCapture: the filter on row %d was not flattened" % row
    return "SaCapture: flattened row %d. %s" % [row, said]


static func _attach(tree: SceneTree, document: SaDocument, spec: Dictionary) -> String:
    if document == null:
        return "SaCapture: no document to attach a filter in"
    var key := StringName(String(spec["attach"]))
    var wanted := String(spec.get("layer", ""))
    var node: SaLayer = null
    if not wanted.is_empty():
        node = document.get_node_or_null(NodePath(wanted)) as SaLayer
        if node == null:
            return "SaCapture: no layer called '%s' to attach '%s' to" % [wanted, key]
    var record := SaFilterOps.new(document).attach(node, key, spec.get("params", {}) as Dictionary)
    if record == null:
        return "SaCapture: '%s' was refused" % key
    if not bool(spec.get("enabled", true)):
        SaFilterOps.new(document).set_enabled(record, false)
    var registry := _registry(tree)
    var known := registry != null and registry.has(key)
    var note := (
        "" if known else ", which no module registers, known: %s" % ", ".join(registry.list_keys() if registry != null else [])
    )
    var masked := ". The selection becomes the filter's mask." if record.mask != null else ""
    return "SaCapture: attached '%s' to %s%s%s" % [key, wanted if node != null else "the root", note, masked]


## One press and release at the rect *which* names, or two pairs when *double*,
## the second press carrying the flag the engine sets on it. The whole pair is
## pushed rather than one press, because that is what a painter's hand sends and
## what a row sees, and the flag is written here rather than waited for, because
## a hand's two clicks are inside the engine's own interval and a script's steps
## are not.
static func _press(tree: SceneTree, docker: Window, list: SaLayerList, row: int, which: String, double: bool = false) -> String:
    var report: Array = list.row_report()
    if row < 0 or row >= report.size():
        return "SaCapture: no row %d to press" % row
    var rect: Dictionary = report[row][which]
    var origin := Vector2(docker.position) if docker.is_embedded() else Vector2.ZERO
    var at := origin + Vector2(float(rect["x"]) + float(rect["w"]) * 0.5, float(rect["y"]) + float(rect["h"]) * 0.5)
    var physical: Vector2 = tree.root.get_final_transform() * at
    var motion := InputEventMouseMotion.new()
    motion.position = physical
    motion.global_position = physical
    Input.parse_input_event(motion)
    var clicks := 2 if double else 1
    for click in clicks:
        for pressed: bool in [true, false]:
            var event := InputEventMouseButton.new()
            event.button_index = MOUSE_BUTTON_LEFT
            event.pressed = pressed
            event.double_click = pressed and click == 1
            event.position = physical
            event.global_position = physical
            Input.parse_input_event(event)
    var what := "eye" if which == "eye_rect" else "middle"
    return "SaCapture: %s the %s of row %d at (%d, %d)" % ["double clicked" if double else "pressed", what, row, at.x, at.y]


static func _report(tree: SceneTree, list: SaLayerList) -> String:
    var report: Array = list.row_report()
    var lines: Array[String] = ["SaCapture: %d rows in the layers docker" % report.size()]
    for i in report.size():
        var entry: Dictionary = report[i]
        if String(entry.get("kind", "")) == "filter":
            var state := "on" if bool(entry["enabled"]) else "off"
            var under := String(entry["node"]) if not String(entry["node"]).is_empty() else "the root"
            var marks := " picked" if bool(entry["selected"]) else ""
            lines.append("  %2d    filter %-24s %-3s under %s%s" % [i, String(entry["title"]), state, under, marks])
        else:
            var mark := " picked" if bool(entry["selected"]) else (" target" if bool(entry.get("target", false)) else "")
            var group := " (group)" if bool(entry.get("is_group", false)) else ""
            lines.append("  %2d  %s%s%s" % [i, str(entry["name"]), group, mark])
    var options := CaptureRun.DockerLookup.window(tree, DockerIds.TOOL_OPTIONS)
    var panel: Node = options.find_child(SaFilterPanel.NODE_NAME, true, false) if options != null else null
    if panel is SaFilterPanel:
        lines.append("  the tool options docker shows %s" % JSON.stringify((panel as SaFilterPanel).describe()))
    else:
        lines.append("  the tool options docker shows the tool's own rows")
    return "\n".join(lines)


static func _registry(tree: SceneTree) -> SaFilterRegistry:
    var main_node := tree.current_scene if tree != null else null
    var registries := main_node.get("registries") as SaRegistries if main_node != null else null
    return registries.filters if registries != null else null
