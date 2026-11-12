## The `toolbox` capture step: drives the flyouts and the drag between them the
## way a painter does, and reports what the docker drew.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Out of `toolbox_docker.gd` and cut by responsibility: this class owns the
## door and the docker owns the buttons.
##
## **Everything here is aimed by `toolbox_report`**. The docker
## says where each button and each row of the open flyout is drawn, and this
## file presses there with an injected press and release, so a step that says
## it pressed something proves the press and not the handler behind it. It
## reads no private member of the docker and calls none of its private
## functions, because a call of a handler skips what the press does first:
## shutting the flyout empties the list of rows the handler looks its row up in,
## so a step calling it would print "picked" and pick nothing. What it does call
## is the docker's public door: `open_flyout`, `close_flyouts` and `move_tool`.
## `drag` injects the press, the motions and the release the engine's drag and
## drop needs, so the shot shows the engine carrying a tool from one embedded
## window to another rather than a call that skipped the pointer.
class_name SaToolBoxCapture
extends RefCounted

## The built-in dockers' ids, and where a docker's Window is asked for by one.
const DockerIds := preload("res://ui/main/sa_docker_ids.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")

## How far past the press the first motions go. The engine starts a drag once
## the pointer has moved past its deadzone with the button down, and a single
## motion of two texels is inside it.
const DRAG_LEAD: float = 24.0

## Where the last injected event put the pointer, so the next motion carries
## the real distance: the engine adds a motion's `relative` up against its
## deadzone before it asks a Control for drag data, and a motion that says it
## moved nothing never starts a drag however far it went.
static var _last_at: Vector2 = Vector2.ZERO


## Right-clicks a tool: a tool of the toolbox, as a hand would, through the real
## input route, `Input.parse_input_event`, `{"toolbox": {"right_press":
## "select"}}`, with `"times": 10` to repeat it.
##
## Kept apart from `flyout` above rather than replacing it, because the two ask
## different questions. `flyout` calls `open_flyout` and asks what the popup
## draws, which is what a picture of the flyout wants and what is measured at
## three UI scales. This one asks whether the press arrives at all, which a
## docker that answers only once a left press has focused it would fail.
##
## `{"toolbox": {"flyout": "paint"}}` opens that category's flyout through
## `open_flyout`, `{"toolbox": {"pick": "eraser"}}` presses that row of the open
## flyout where it is drawn, `{"toolbox": {"press": "select"}}` is a plain left
## press and release on the button, and
## `{"toolbox": {"close": true}}` is the press outside that shuts it.
##
## `{"toolbox": {"move": {"tool": "lasso", "into": "paint", "before":
## "eraser"}}}`, or `"after"`, or `"new_group_at": 1`, which is the docker's
## `move_tool` door, and `{"toolbox": {"drag": ...}}`, the injected gesture in
## six parts a scenario spreads over frames: `{"start": "lasso"}` presses the
## row of the open flyout and moves off it, `{"over": "paint"}` moves onto that
## button, `{"row": "eraser", "half": "upper"}` moves onto that row of the
## flyout the hover opened, `{"empty": true}` moves onto the docker's own empty
## space under its last button, `{"away": true}` moves off the docker
## altogether, and `{"drop": true}` releases where the pointer is.
static func capture_toolbox(tree: SceneTree, spec: Variant) -> String:
    var docker := CaptureRun.DockerLookup.window(tree, DockerIds.TOOLBOX) as ToolBoxDocker
    if docker == null:
        return "SaCapture: no toolbox docker"
    var wanted: Dictionary = spec if spec is Dictionary else {}
    var lines := PackedStringArray()

    if wanted.has("flyout"):
        var category := StringName(wanted["flyout"])
        var opened := docker.open_flyout(category)
        lines.append(
            (
                "SaCapture: flyout %s on '%s', showing %s"
                % ["opened" if opened else "refused", category, str(_flyout_of(docker).get("members", []))]
            )
        )
    if wanted.has("pick"):
        var tool_id := String(wanted["pick"])
        var row := _row_of(docker, tool_id)
        if row < 0:
            lines.append("SaCapture: '%s' is not a row of the open flyout" % tool_id)
        else:
            # The press a painter makes, on the row where the popup drew it. The
            # list hides itself on a choice, the way every menu in Sara does, so
            # nothing here shuts it.
            var at := _row_rect(docker, row).get_center()
            _button(tree, at, true)
            _button(tree, at, false)
            lines.append("SaCapture: picked '%s' from row %d" % [tool_id, row])
    if wanted.has("press"):
        var category := StringName(wanted["press"])
        var entry := _button_entry(docker, category)
        if entry.is_empty():
            lines.append("SaCapture: no button called '%s'" % category)
        else:
            var at := _aim_at(docker, entry)
            _button(tree, at, true, MOUSE_BUTTON_LEFT, docker)
            _button(tree, at, false, MOUSE_BUTTON_LEFT, docker)
            lines.append("SaCapture: pressed the '%s' button" % category)
    if wanted.has("right_press"):
        lines.append(_right_press(tree, docker, wanted))
    if wanted.has("move"):
        lines.append(_move(docker, wanted["move"] as Dictionary))
    if wanted.has("drag"):
        lines.append(_drag(tree, docker, wanted["drag"] as Dictionary))
    if wanted.get("close", false):
        docker.close_flyouts()
        lines.append("SaCapture: the flyout is shut")

    var report := docker.toolbox_report()
    for entry: Dictionary in report.get("buttons", []):
        if entry.has("category"):
            lines.append(
                (
                    "  %s: face %s, members %s, flyout %s"
                    % [entry["category"], entry["face"], str(entry["members"]), entry["has_flyout"]]
                )
            )
    lines.append("  groups: %s" % JSON.stringify(report.get("groups", [])))
    # Without the rows' rectangles, which are what this file aims with and not
    # what a scenario's log is read for: a rectangle moves with the window's
    # size and the line is compared between runs.
    var flyout: Dictionary = (report.get("flyout", {}) as Dictionary).duplicate()
    flyout.erase("row_rects")
    lines.append("  open flyout: %s" % JSON.stringify(flyout))
    return "\n".join(lines)


## The open flyout's block of the report, `{"open": false}` when there is none.
static func _flyout_of(docker: ToolBoxDocker) -> Dictionary:
    return docker.toolbox_report().get("flyout", {})


## Which row of the open flyout shows *tool_id*, or -1.
static func _row_of(docker: ToolBoxDocker, tool_id: String) -> int:
    var rows: Array = _flyout_of(docker).get("row_rects", [])
    for row in rows.size():
        if String((rows[row] as Dictionary).get("id", "")) == tool_id:
            return row
    return -1


## Where the open flyout drew *row*, on the host.
static func _row_rect(docker: ToolBoxDocker, row: int) -> Rect2:
    var rows: Array = _flyout_of(docker).get("row_rects", [])
    return _rect_of((rows[row] as Dictionary).get("rect", []))


## The report's entry for *category*'s button, empty when no such button is
## drawn.
static func _button_entry(docker: ToolBoxDocker, category: StringName) -> Dictionary:
    for entry: Dictionary in docker.toolbox_report().get("buttons", []):
        if String(entry.get("category", "")) == String(category) and entry.has("rect"):
            return entry
    return {}


## Where a press on *entry*'s button goes. A pushed event is placed in the
## window's own viewport, an injected one on the screen the injector addresses,
## and only the embedded case makes those the same number.
static func _aim_at(docker: ToolBoxDocker, entry: Dictionary) -> Vector2:
    return _rect_of(entry["rect"] if docker.is_embedded() else entry["rect_in_window"]).get_center()


static func _rect_of(numbers: Variant) -> Rect2:
    var values: Array = numbers if numbers is Array else []
    if values.size() < 4:
        return Rect2()
    return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))


## The docker's door, for the half of a scenario that reads back rather than
## shows: the same call every drop ends in.
static func _move(docker: ToolBoxDocker, spec: Dictionary) -> String:
    var tool_id := String(spec.get("tool", ""))
    if spec.has("new_group_at"):
        var opened := docker.move_tool(tool_id, int(spec["new_group_at"]), 0, true)
        return "SaCapture: moved '%s' into a new group at %d: %s" % [tool_id, int(spec["new_group_at"]), opened]
    var report := docker.toolbox_report()
    var index := (report.get("group_names", []) as Array).find(String(spec.get("into", "")))
    if index < 0:
        return "SaCapture: no group called '%s'" % String(spec.get("into", ""))
    var group: Array = (report.get("groups", []) as Array)[index]
    var position := group.size()
    if spec.has("before"):
        position = maxi(0, group.find(String(spec["before"])))
    elif spec.has("after"):
        position = group.find(String(spec["after"])) + 1
    var ok := docker.move_tool(tool_id, index, position, false)
    return "SaCapture: moved '%s' into '%s' at %d: %s" % [tool_id, spec.get("into", ""), position, ok]


## The injected gesture, one part per call. Every position is a rectangle the
## docker reports at the moment of the call, so the scenario names a tool and a
## button rather than a point that goes stale.
static func _drag(tree: SceneTree, docker: ToolBoxDocker, spec: Dictionary) -> String:
    if spec.has("start"):
        var tool_id := String(spec["start"])
        var row := _row_of(docker, tool_id)
        if row < 0:
            return "SaCapture: '%s' is not a row of the open flyout" % tool_id
        var at := _row_rect(docker, row).get_center()
        _button(tree, at, true)
        _motion(tree, at + Vector2(DRAG_LEAD * 0.5, 0.0))
        _motion(tree, at + Vector2(DRAG_LEAD, 0.0))
        return "SaCapture: drag of '%s' started at %s, dragging %s" % [tool_id, at, tree.root.gui_is_dragging()]
    if spec.has("over"):
        var entry := _button_entry(docker, StringName(spec["over"]))
        if entry.is_empty():
            return "SaCapture: no button called '%s'" % String(spec["over"])
        var drawn := _rect_of(entry["rect"])
        var at := drawn.get_center()
        # `along`, 0 to 1 down or across the button, aims at a third of it: the
        # first opens a group before the button and the last one after it.
        if spec.has("along"):
            var along := clampf(float(spec["along"]), 0.0, 1.0)
            var column := int(docker.toolbox_report().get("columns", 1)) == 1
            var fractions := Vector2(0.5 if column else along, along if column else 0.5)
            at = drawn.position + drawn.size * fractions
        _motion(tree, at)
        return (
            "SaCapture: dragged over the '%s' button at %s, dragging %s" % [String(spec["over"]), at, tree.root.gui_is_dragging()]
        )
    if spec.has("row"):
        var tool_id := String(spec["row"])
        var row := _row_of(docker, tool_id)
        if row < 0:
            return "SaCapture: '%s' is not a row of the open flyout" % tool_id
        var drawn := _row_rect(docker, row)
        var at := drawn.get_center()
        at.y += _row_height(docker, drawn) * (-0.3 if String(spec.get("half", "upper")) == "upper" else 0.3)
        _motion(tree, at)
        return "SaCapture: dragged over the '%s' row at %s, dragging %s" % [tool_id, at, tree.root.gui_is_dragging()]
    if spec.get("empty", false):
        # `Variant` on purpose, because the answer is a point or nothing and a
        # `Vector2` has no value that means "no space": every point is one.
        var space: Variant = _empty_space(docker)
        if space == null:
            return "SaCapture: the toolbox has no empty space under its buttons"
        var at := space as Vector2
        _motion(tree, at)
        return "SaCapture: dragged onto the toolbox's empty space at %s, dragging %s" % [at, tree.root.gui_is_dragging()]
    if spec.get("away", false):
        var at := _away_from(tree, docker)
        _motion(tree, at)
        return "SaCapture: dragged off the toolbox to %s, dragging %s" % [at, tree.root.gui_is_dragging()]
    if spec.get("drop", false):
        var at := tree.root.get_mouse_position()
        _button(tree, at, false)
        return "SaCapture: dropped at %s" % at
    return "SaCapture: drag wants start, over, row, empty, away or drop"


## The middle of the toolbox's own empty space, under its last visible button
## and inside the button area, which is where a release means "a group of its
## own". Null when the buttons fill the docker, because a scenario that
## asked for a gesture the docker has no room for wants to be told rather than
## to drop on the last button by accident.
##
## Read off the report at the moment of the call, the way every other aim in
## this file is: the docker is moved and resized by the scenario two steps
## earlier and a point written down here would be right for one size.
static func _empty_space(docker: ToolBoxDocker) -> Variant:
    var area := docker.drop_area_screen_rect()
    if area.size.y <= 0.0:
        return null
    var lowest := area.position.y
    for entry: Dictionary in docker.toolbox_report().get("buttons", []):
        if entry.has("category") and entry.has("rect"):
            lowest = maxf(lowest, _rect_of(entry["rect"]).end.y)
    var bottom := area.position.y + area.size.y
    if lowest >= bottom - 4.0:
        return null
    return Vector2(area.position.x + area.size.x * 0.5, (lowest + bottom) * 0.5)


## A point outside the docker altogether, which is the release that puts a
## dragged tool back. To the left of the docker when there is room, and to the
## right when the docker is against the left edge.
static func _away_from(tree: SceneTree, docker: ToolBoxDocker) -> Vector2:
    var area := docker.drop_area_screen_rect()
    var middle := Vector2(tree.root.size) * 0.5
    if area.size.x <= 0.0:
        return middle
    # A hundred rather than a few, because the rectangle is the docker's inside
    # and the window's own border and shadow sit outside it.
    if area.position.x > 160.0:
        return Vector2(area.position.x - 100.0, area.position.y + area.size.y * 0.5)
    return Vector2(area.position.x + area.size.x + 100.0, area.position.y + area.size.y * 0.5)


## The right press through the input route, once or *times* over, each round
## reporting whether the flyout came open and closing it again for the next.
##
## Through `Input.parse_input_event` on purpose: the question is delivery
## rather than the popup, and a step that calls `open_flyout`
## proves nothing about it. The button is found by its Control at the moment of
## the press, the way every other injected gesture here is, so a docker moved
## between rounds is still aimed at.
##
## A category with fewer than two reachable tools has no flyout and the answer
## is "shut" every round, which is not a failure of the route: that is the plain
## button that carries no corner mark.
##
## Each round shuts the flyout first. A single press leaves it standing, so a
## `shot` after it shows the flyout the report names, and a repeat ends shut.
static func _right_press(tree: SceneTree, docker: ToolBoxDocker, spec: Dictionary) -> String:
    var category := StringName(spec["right_press"])
    var rounds := maxi(1, int(spec.get("times", 1)))
    if _button_entry(docker, category).is_empty():
        return "SaCapture: no button called '%s'" % category
    var opened := PackedStringArray()
    for round_index in rounds:
        docker.close_flyouts()
        # Asked again every round, so a docker moved between rounds is still
        # aimed at.
        var at := _aim_at(docker, _button_entry(docker, category))
        _button(tree, at, true, MOUSE_BUTTON_RIGHT, docker)
        _button(tree, at, false, MOUSE_BUTTON_RIGHT, docker)
        opened.append("open" if String(_flyout_of(docker).get("category", "")) == String(category) else "shut")
    if rounds > 1:
        # A repeat is a measurement rather than a picture, and ten popups opened
        # and shut inside one frame leave the last one hidden a frame later
        # whatever the report says. It ends shut, and a scenario that wants the
        # flyout in a shot asks for one more press of its own.
        docker.close_flyouts()
    return (
        "SaCapture: %d right presses on '%s' at the button, %s: %s"
        % [rounds, category, "embedded" if docker.is_embedded() else "not embedded", ", ".join(opened)]
    )


## A row's height in the popup's own units, which is what the aim inside a row
## has always been measured in. *drawn* is the same row on the host, a quarter
## taller on a maximised toolbox, and is the answer only when the popup says
## nothing.
static func _row_height(docker: ToolBoxDocker, drawn: Rect2) -> float:
    var popup: Dictionary = _flyout_of(docker).get("popup", {})
    var height := float(popup.get("row_height", 0.0))
    return height if height > 0.0 else drawn.size.y


## Positions are in the root window's logical units, which is what a Control
## in an embedded window reports as its screen position, and an event pushed
## in from outside is un-scaled on the way in, so it goes in pre-multiplied.
static func _physical(tree: SceneTree, at: Vector2) -> Vector2:
    return tree.root.get_final_transform() * at


## One injected button event. *into*, when it names a window the desktop owns
## rather than an embedded one, is pushed at directly.
##
## `Input.parse_input_event` addresses the main window and nothing else, so a
## docker the desktop has given a window of its own is out of its reach: the
## point lands on the canvas at the docker's own local coordinates, the tool
## machine answers, and a run reads that as the application misrouting a press
## it never received. `Window.push_input` is the call `Window._window_input`
## makes on the event the compositor hands it, so this is the same route with
## the compositor's half supplied, and it is the only one there is offscreen.
static func _button(
    tree: SceneTree, at: Vector2, pressed: bool, which: MouseButton = MOUSE_BUTTON_LEFT, into: Window = null
) -> void:
    Input.warp_mouse(at)
    _last_at = at
    var event := InputEventMouseButton.new()
    event.button_index = which
    event.pressed = pressed
    event.position = _physical(tree, at)
    event.global_position = event.position
    var mask := MOUSE_BUTTON_MASK_LEFT if which == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
    event.button_mask = mask if pressed else 0
    if into != null and not into.is_embedded():
        into.push_input(event)
        return
    Input.parse_input_event(event)


static func _motion(tree: SceneTree, at: Vector2) -> void:
    Input.warp_mouse(at)
    var event := InputEventMouseMotion.new()
    event.position = _physical(tree, at)
    event.global_position = event.position
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    event.relative = _physical(tree, at) - _physical(tree, _last_at)
    _last_at = at
    Input.parse_input_event(event)
