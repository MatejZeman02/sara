## The Reference docker's door for a scenario and the dump: the
## `reference` step and the `reference` block of the state.
##
## Every step here is the call the hand makes, and the one gesture a hand
## makes that a call cannot stand in for, the drag of a picture, goes through
## the same press, motion and release `board_view.input` gets from the mouse, so
## a scenario proves the gesture and not only the docker's `move`. What a step
## needs to know about the docker it reads off `ReferenceDocker.report()`, and
## the dump's block is the docker's own `capture_state`.
class_name SaReferenceCapture
extends RefCounted

## The built-in dockers' ids, and where a docker's Window is asked for by one.
const DockerIds := preload("res://ui/main/sa_docker_ids.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")


## Drives the Reference board: from a scenario, `{"reference": {...}}`. `open`
## takes a path or a list, `board` adds, selects, renames or closes a tab, `drag`
## moves a picture by its index through the same press, motion and release a hand
## makes, `fit`, `fit_picture` and `normalise` are the buttons, `zoom` and `pan`
## move the view, and `sample` takes the colour at a point in the picture Control.
##
## `canvas`, true, puts the canvas on the board as an element, the Canvas
## button's own call. `select` takes the picture by index that
## the hover bar and the Graph docker read, `toggle` for one of `flip`,
## `greyscale`, `crop` and `on_top` on that picture, the bar's own call, and
## `crop` for `{"picture": 0, "rect": [x, y, w, h]}` in texels, which is the
## rectangle the drag would have made.
##
## `rename_tab`, an index, which opens the dialog a double
## click on that tab opens, `rename_click`, an index, which is that double click
## itself sent through the engine's input, and `rename_field`, true, which reads whether the
## open dialog's field has the keys and its whole text selected. The two are
## separate steps so a `wait` between them lets the popup take its frame.
static func capture_reference(tree: SceneTree, spec: Variant) -> String:
    var docker := CaptureRun.DockerLookup.window(tree, DockerIds.REFERENCE) as ReferenceDocker
    if docker == null:
        return "SaCapture: no Reference docker"
    var wanted: Dictionary = spec if spec is Dictionary else {}

    if wanted.has("open"):
        var paths := PackedStringArray([String(wanted["open"])] if wanted["open"] is String else wanted["open"])
        var placed := docker.open_paths(paths)
        return "SaCapture: reference opened %d of %d" % [placed, paths.size()]
    if wanted.has("rename_tab"):
        return _open_rename(docker, int(wanted["rename_tab"]))
    if wanted.has("rename_click"):
        return _double_click_tab(docker, int(wanted["rename_click"]))
    if wanted.get("rename_field", false):
        return _read_rename(tree)
    if wanted.get("clear", false):
        docker.clear()
        return "SaCapture: reference cleared"
    if wanted.has("board"):
        _drive_board(docker, wanted["board"])
    if wanted.get("canvas", false):
        docker.toggle_canvas()
    if wanted.has("select"):
        var chosen := int(wanted["select"])
        if chosen >= 0 and chosen < docker.board().pictures.size():
            docker.board_view.select_picture(docker.board().pictures[chosen])
    if wanted.has("toggle"):
        # The selected picture when there is one, and the hover bar's target
        # otherwise: a scenario's pointer is not over the board, so the bar's own
        # target is null and the step would do nothing.
        var target := docker.board_view.selected() if docker.board_view.selected() != null else docker.board_view.hover_target()
        docker.board_view.toggle_on(target, String(wanted["toggle"]))
    if wanted.has("crop"):
        var ask: Dictionary = wanted["crop"]
        var index := int(ask.get("picture", 0))
        var r: Array = ask.get("rect", [])
        if index >= 0 and index < docker.board().pictures.size() and r.size() >= 4:
            var texels := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
            docker.board_view.crop_to(docker.board().pictures[index], texels)
    if wanted.has("drag"):
        var problem := _drag(docker, wanted["drag"])
        if not problem.is_empty():
            return problem
    if wanted.get("fit", false):
        docker.board_view.fit()
    if wanted.has("fit_picture"):
        var index := int(wanted["fit_picture"])
        if index >= 0 and index < docker.board().pictures.size():
            docker.board_view.fit_picture(docker.board().pictures[index])
    if wanted.get("normalise", false):
        docker.normalise()
    if wanted.has("zoom"):
        var size: Dictionary = docker.report()["picture_size"]
        var middle := Vector2(float(size["w"]), float(size["h"])) * 0.5
        docker.board_view.zoom_about(middle, float(wanted["zoom"]) / maxf(0.001, docker.board().zoom))
    if wanted.has("pan"):
        var by: Array = wanted["pan"]
        docker.board_view.pan_by(Vector2(float(by[0]), float(by[1])))
    if wanted.has("sample"):
        var at: Array = wanted["sample"]
        var hit := docker.sample_at(Vector2(float(at[0]), float(at[1])))
        if not hit:
            return "SaCapture: reference sample at (%s, %s) is off every picture" % [at[0], at[1]]
    var shown := docker.report()
    var display: Array = shown["sampled_display"]
    return (
        "SaCapture: reference board %d of %d, zoom %.3f, offset (%.1f, %.1f), texel %s, display %s"
        % [
            shown["current"],
            (shown["boards"] as Array).size(),
            shown["zoom"],
            shown["offset"]["x"],
            shown["offset"]["y"],
            shown["sampled_at"],
            Color(display[0], display[1], display[2], display[3]).to_html(false),
        ]
    )


## `{"rename_tab": 0}`: the docker's rename, the call the double click on a
## tab makes.
static func _open_rename(docker: ReferenceDocker, index: int) -> String:
    if docker.open_rename(index) == null:
        return "SaCapture: no tab %d to rename" % index
    return "SaCapture: reference rename dialog open on tab %d" % index


## `{"rename_click": 0}`: a press, a release and a second press marked as a
## double click on the middle of the tab, then its release, sent through
## `Input` the way the `press` step sends one, so the embedder picks the
## docker's window and the tab bar's own input opens the dialog, the path a
## painter's hand takes.
static func _double_click_tab(docker: ReferenceDocker, index: int) -> String:
    var bar := docker.find_child("Tabs", true, false) as TabBar
    if bar == null:
        return "SaCapture: no tab bar on the Reference docker"
    if index < 0 or index >= bar.tab_count:
        return "SaCapture: no tab %d to rename" % index
    var at := bar.get_screen_transform() * bar.get_tab_rect(index).get_center()
    var root_at := at - Vector2(docker.get_tree().root.position)
    for double: bool in [false, true]:
        var press := _mouse_button(root_at, true)
        press.global_position = root_at
        press.double_click = double
        press.button_mask = MOUSE_BUTTON_MASK_LEFT
        Input.parse_input_event(press)
        var release := _mouse_button(root_at, false)
        release.global_position = root_at
        Input.parse_input_event(release)
    return "SaCapture: reference double click on tab %d at (%.0f, %.0f)" % [index, root_at.x, root_at.y]


## `{"rename_field": true}`: whether the rename dialog's field has the keys and
## its whole text selected, which is what lets a painter type the new name
## straight away. Says `failed` otherwise, so the run lists it as a problem.
static func _read_rename(tree: SceneTree) -> String:
    var field: LineEdit = null
    var open := 0
    for found in tree.root.find_children("BoardName", "LineEdit", true, false):
        if (found as LineEdit).is_visible_in_tree():
            field = found as LineEdit
            open += 1
    if field == null:
        return "SaCapture: no rename dialog open"
    var focused := field.has_focus()
    var whole := field.has_selection() and field.get_selected_text() == field.text and not field.text.is_empty()
    var verdict := "holds the keys with its whole text selected" if focused and whole else "failed"
    return (
        'SaCapture: reference rename field %s, focus %s, selected "%s" of "%s", %d dialog(s) open, this one %s'
        % [verdict, focused, field.get_selected_text(), field.text, open, field.get_parent().get_instance_id()]
    )


## `{"board": {"add": "The mug"}}`, `{"select": 1}`, `{"rename": "The cup"}`
## on the board showing, or `{"close": true}` for it.
static func _drive_board(docker: ReferenceDocker, ask: Dictionary) -> void:
    if ask.has("add"):
        docker.add_board(String(ask["add"]))
    if ask.has("select"):
        docker.select_board(int(ask["select"]))
    if ask.has("rename"):
        docker.rename_board(int(docker.report()["current"]), String(ask["rename"]))
    if ask.get("close", false):
        docker.close_board(int(docker.report()["current"]))


## `{"drag": {"picture": 0, "by": [60, 120]}}`: a press on the centre of the
## picture, two motions and a release, in screen pixels of the picture
## Control. Answers a problem, or an empty string.
static func _drag(docker: ReferenceDocker, ask: Dictionary) -> String:
    var index := int(ask.get("picture", 0))
    var by: Array = ask.get("by", [0, 0])
    if index < 0 or index >= docker.board().pictures.size():
        return "SaCapture: reference has no picture %d to drag" % index
    var from := docker.board().view_rect(docker.board().pictures[index]).get_center()
    var to := from + Vector2(float(by[0]), float(by[1]))
    docker.board_view.input(_mouse_button(from, true))
    docker.board_view.input(_mouse_motion(from + (to - from) * 0.5))
    docker.board_view.input(_mouse_motion(to))
    docker.board_view.input(_mouse_button(to, false))
    return ""


static func _mouse_button(at: Vector2, pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = at
    return event


static func _mouse_motion(at: Vector2) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    return event
