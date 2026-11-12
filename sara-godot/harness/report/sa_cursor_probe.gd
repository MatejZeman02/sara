## What the cursor logic would answer, and what the ring believed it drew.
##
## Two reports rather than two injections, and that is why they are not with the
## input driver: neither pushes an event at the app. Wayland refuses to warp a
## client pointer, so "hover a docker and look" is not something a script can do
## here, and both of these ask the live code the same question a hover would have
## asked without moving anything.
##
## Each appends to a file beside the shots, `probe.txt` and `ring.jsonl`, which
## is the one thing they share and the reason they sit in one class.
##
## Reached by path from the runner rather than by class name, so no editor
## rescan stands between a fresh checkout and a step.
class_name SaCursorProbe
extends RefCounted

## The run, by path like every other harness file this one names.
const CaptureRun := preload("res://harness/sa_capture_run.gd")

## The run, read for its tree and for the folder the logs go beside.
var _run: CaptureRun = null


func _init(run: CaptureRun) -> void:
    _run = run


## Probes the cursor logic: what it answers at points the pointer is not at.
##
## Wayland refuses to warp a client pointer, so "hover a docker and look" is not
## something a script can do here. This calls the same two functions the
## CursorOverlay calls every frame, against the real docker geometry, which is
## what tells a geometry bug apart from an input-routing one. The centre of every
## embedded docker is probed on top of whatever points the scenario names.
func probe(raw: Variant) -> void:
    var root := _run.tree().root
    var points: Array = []
    if raw is Array:
        for entry: Variant in raw as Array:
            var pair := entry as Array
            if pair != null and pair.size() >= 2:
                points.append(["scenario point", Vector2(float(pair[0]), float(pair[1]))])
    for docker in SaCursorPolicy.embedded_subwindows(root):
        points.append(["centre of '%s'" % docker.title, Vector2(docker.position) + Vector2(docker.size) * 0.5])
    # The other kind, which is what `embed_subwindows` off makes of every docker:
    # a window of its own is placed in screen pixels, so its rectangle is
    # read through the policy rather than taken for a point in the root's space.
    # Without these rows the scan above finds nothing at all with the switch off
    # and every docker reads as the canvas underneath it.
    for other in SaCursorPolicy.windows_of_their_own(root):
        var rect := SaCursorPolicy.rect_in(root, other)
        print("SaCapture: probe window of its own '%s' at %s in the root's space" % [other.title, str(rect)])
        points.append(["centre of '%s' (its own window)" % other.title, rect.position + rect.size * 0.5])
        points.append(["top left of '%s' (its own window)" % other.title, rect.position + Vector2(4.0, 4.0)])
    # An open menu is a Window the scan above never names, because a PopupMenu
    # is an internal child of whoever owns it. It is also the one place the
    # cursor logic could hide the OS pointer with nothing drawn in its place, so
    # a probe that cannot reach it cannot prove anything about that case.
    #
    # Top and bottom rather than the centre, because a menu that opens out of
    # the title bar crosses the canvas edge and the two ends can get different
    # answers, and that difference is what the probe is for.
    for sub in SaCursorPolicy.embedded_subwindows(root, true):
        if sub is Popup:
            var rect := Rect2(Vector2(sub.position), Vector2(sub.size))
            points.append(["top row of menu '%s'" % sub.name, rect.position + Vector2(rect.size.x * 0.5, 6.0)])
            points.append(["last row of menu '%s'" % sub.name, rect.end - Vector2(rect.size.x * 0.5, 6.0)])
    points.append(["viewport centre", root.get_visible_rect().size * 0.5])
    # Where the pointer physically is, which is the only point whose `over_ui`
    # and `ring` columns mean anything, every other row on this list being the
    # geometry answered for somewhere the pointer is not.
    points.append(["the real pointer", SaCursorPolicy.pointer_in_window(root)])

    # What the whole batch was taken under. The mode is the thing the three
    # rows below are about, `os_cursor` is the process-wide answer that mode is
    # supposed to decide, and `tool_cursor` is the picture standing in a cursor
    # slot, which no screenshot can show because the compositor draws it.
    var tool_cursor: Dictionary = SaCursorPolicy.tool_cursor_state()
    var header := (
        "SaCapture: probe mode=%s os_cursor=%s tool_cursor=%s tablet=%s"
        % [
            SaSettings.software_cursor,
            "hidden" if Input.get_mouse_mode() == Input.MOUSE_MODE_HIDDEN else "visible",
            String(tool_cursor.get("tool", "")) if bool(tool_cursor.get("custom", false)) else "-",
            str(SaCursorPolicy.pointer_is_tablet)
        ]
    )
    print(header)

    # Reported separately, because the hovered-Control half answers for wherever
    # the real pointer is and would otherwise mask what the rect test found.
    var written: PackedStringArray = [header]
    for probe_point: Array in points:
        var at := probe_point[1] as Vector2
        var in_docker := "-"
        for docker in SaCursorPolicy.embedded_subwindows(root):
            if Rect2(Vector2(docker.position), Vector2(docker.size)).has_point(at):
                in_docker = docker.title
        for other in SaCursorPolicy.windows_of_their_own(root):
            if SaCursorPolicy.rect_in(root, other).has_point(at):
                in_docker = other.title
        var over_ui := str(SaCursorPolicy.pointer_is_over_ui(root, at))
        var ring := SaCursorPolicy.cursor_ring_radius_at(root, at)
        # The two geometric halves, printed beside the full answer because that
        # answer is masked here: `over_ui` folds in `gui_get_hovered_control`,
        # which reports wherever the hand physically left the mouse rather than
        # the point being probed, and Wayland will not let a capture move it.
        # These two ask nothing but rectangles, so they are the columns to
        # read a before-and-after in.
        var over_window := str(SaCursorPolicy.pointer_is_over_embedded_window(root, at))
        var canvas_ring := SaCursorPolicy.canvas_ring_radius_at(root, at)
        # What is drawn at this point, the column that says which cursor shows: `ring`
        # is Sara's ring, `pointer` its drawn arrow, and `system` is the OS
        # cursor left in charge. Rectangles only, because the `ring` column
        # beside it folds in the hovered Control and so answers for wherever the
        # hand left the mouse: offscreen every row of it reads -1.0 whatever the
        # mode, so that column alone could say nothing about the modes.
        var drawn := SaCursorPolicy.drawn_at(root, at)
        # Whether the active tool's own picture belongs here. The note this
        # answers is an eyedropper icon left over a docker, and the display
        # server draws that picture, so no screenshot can show it and this
        # column is the only reading of it.
        var picture := "yes" if SaCursorPolicy.tool_cursor_shows_at(root, at) else "no"
        var line := (
            "SaCapture: probe %-30s (%4d, %4d)  in_docker=%-14s"
            + "  over_window=%-5s canvas_ring=%6.1f  over_ui=%-5s ring=%6.1f  drawn=%-7s picture=%s"
        )
        var row := line % [probe_point[0], at.x, at.y, in_docker, over_window, canvas_ring, over_ui, ring, drawn, picture]
        print(row)
        written.append(row)

    _append_log("probe.txt", written, true)

    var found_here := SaCursorPolicy.embedded_subwindows(root).size()
    print(
        (
            "SaCapture: probe found %d embedded docker(s); the window's own children hold %d"
            % [found_here, _direct_child_windows(root)]
        )
    )


## Appends *rows* to *file_name* in the capture's own directory, with a blank
## line after the batch when *spacer* asks for one.
##
## A probe's whole result is text, and `scripts/sara_shot.py` shows a run's
## stdout only when something failed, so without a file the one step whose
## output is the proof would leave nothing in the folder a person reviews. Appended rather than
## written, because a scenario probes before and after the thing it is testing
## and the pair is what is worth reading. A probe reads as paragraphs and wants
## the spacer, a `.jsonl` file is one record per line and a blank line in it is
## a parse error, which is why the flag is an argument rather than always on.
func _append_log(file_name: String, rows: PackedStringArray, spacer: bool) -> void:
    var dir := _run.out_dir
    if dir == "" or rows.is_empty():
        return
    var path := dir.path_join(file_name)
    var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
    if file == null:
        push_warning("SaCapture: could not write %s" % path)
        return
    file.seek_end()
    for row in rows:
        file.store_line(row)
    if spacer:
        file.store_line("")


## Why every ring record's `lag_ms` is null, and is never zero.
##
## The overlay samples the OS pointer at draw time, so a record's drawn centre and
## the pointer it was drawn for are the same number by construction, and a reader
## subtracting one from the other reads no lag at all. The lag is between the frame
## this record describes and the older frame the compositor is still showing, and
## nothing in the process can see that second one.
const LAG_UNKNOWN: String = "read from a desktop screenshot carrying the hardware pointer, which no capture image holds"


## Logs where rings were drawn: this frame, as one JSON line appended to
## `ring.jsonl` beside the shots, `{"ring_dump": "sweep"}`.
##
## Sara's half of the lag measurement. `scripts/ring_lag.py` drives the pointer across
## the desktop and reads back the frames the compositor showed, and this says what
## Sara believed it was drawing: the centre, the radius, which of the three cursor
## outcomes was drawn, and the cursor mode, content scale and display server the
## numbers belong to. The script searches each frame for a ring whose size it has
## been told rather than for any circle, and that is the pairing.
## `lag_ms` is null and `lag_unknown` says why, so an offscreen run reads unknown.
func ring_dump(raw: Variant) -> void:
    var root := _run.tree().root
    var record := {
        "name": String(raw) if typeof(raw) == TYPE_STRING else "ring",
        "unix_time": Time.get_unix_time_from_system(),
        "display_server": DisplayServer.get_name(),
        "cursor_mode": SaSettings.software_cursor,
        "content_scale": root.content_scale_factor,
        "window": [root.position.x, root.position.y, root.size.x, root.size.y],
        "overlays": CursorOverlay.state_of(root),
        "lag_ms": null,
        "lag_unknown": LAG_UNKNOWN,
    }
    var line := JSON.stringify(record)
    print("SaCapture: ring_dump %s" % line)
    _append_log("ring.jsonl", PackedStringArray([line]), false)


## What the old over-UI scan saw: dockers are children of Main, not of the Window.
static func _direct_child_windows(root: Window) -> int:
    var count := 0
    for child in root.get_children():
        var sub := child as Window
        if sub != null and sub.visible and sub.is_embedded():
            count += 1
    return count
