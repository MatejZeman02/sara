## The brush editor and its curve control, driven by a scenario.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The hand half of the brush editor's capture: the door a painter's click opens
## the editor through lives in the package as `SaBrushEditorDoor`, and the
## steps, the complaints and the log live here, because the door, the drivers
## and the captures are not the interface. The window is reached through the
## door's [method SaBrushEditorDoor.live_window], so there is one lookup and not
## two that can disagree.
##
## The bare throwaway host a `curve_option` step falls back to is
## `SaCurveOptionHost`: building a window is not applying a step.
@tool
class_name SaBrushEditorCapture
extends RefCounted

## What `ToolOptionControls.capture_custom` answers when no widget on screen
## has the capture door, which is what sends the `widget` step to the next page.
const NO_WIDGET: String = "SaCapture: no custom option control on screen to edit"

## What a step is told when it reached the throwaway host by accident.
##
## One line naming what went wrong and what to write instead, and
## the run carries on. It says `failed` because `sara_shot.py` reads a
## `SaCapture:` line carrying that word as a problem worth putting in front of a
## reader, which is the whole point of the line.
const SHUT_EDITOR_COMPLAINT := (
    "SaCapture: curve_option failed, no control is on screen and the brush editor is %s, so this step"
    + " edits a throwaway option and reports it as if it were the painter's."
    + ' Reopen the editor with {"brush_editor": {"open": true, "page": "Opacity"}} before the step that reads it.'
)

# --- Finding what is on screen -------------------------------------------------


## The curve control on screen, whichever window is holding it.
##
## Asks `is_visible_in_tree()`, which is the question `live_window` does not ask.
## Found by method rather than by a cast to a `class_name`, which inside a
## `static func` leaks the script.
static func live_control(tree: SceneTree) -> Node:
    for node in tree.root.find_children("*", "VBoxContainer", true, false):
        if node.has_method("option_report") and (node as Control).is_visible_in_tree():
            return node
    return null


## Announces *picked* from *window*, unless the store behind the window has no
## preset by that name.
##
## A name nothing answers to is a loud failure rather than a quiet nothing, as
## for tags one layer down, where a `tag` step naming a tag no preset carries
## would otherwise photograph the whole library and report success. The warning names
## the presets there are, so the next scenario does not have to guess at the
## capital letters.
static func _pick_in_the_fold(window: SaBrushEditorWindow, picked: String) -> void:
    var store := window.preset_bar.session.preset_store
    if store == null or not store.has_preset(picked):
        var there: Array[String] = (
            window.presets_chooser.visible_names() if window.presets_chooser != null else [] as Array[String]
        )
        push_warning(
            (
                "SaCapture: brush editor pick failed, no preset called '%s'. The presets are: %s"
                % [picked, ", ".join(there) if not there.is_empty() else "(none)"]
            )
        )
        return
    window.preset_chosen.emit(picked)


## The `CURVE_OPTION` spec whose page is called *page_title*, off the shown
## tool first and every painting tool after it, or null when no tool declares
## one.
##
## The bare host needs a spec because the widget it shows is the spec's, and a
## scenario names a page rather than a key because that is what the editor's
## list shows. The shown tool goes first so a scenario that switched to the
## eraser drives the eraser's Size and not the brush's.
static func curve_spec(tree: SceneTree, page_title: String) -> SaOptionSpec:
    var bar := SaBrushEditorDoor.tool_options_bar(tree)
    if bar == null:
        return null
    var lists: Array = [bar.shown_specs()]
    var machine := bar.target_tool_machine
    if machine != null:
        for tool_id: StringName in bar.painting_tool_ids():
            var descriptor := machine.get_descriptor(tool_id)
            if descriptor != null:
                lists.append(descriptor.options)
    for specs: Array in lists:
        for candidate: SaOptionSpec in specs:
            if candidate == null or candidate.kind != SaOptionSpec.Kind.CURVE_OPTION:
                continue
            var title := candidate.page if not candidate.page.is_empty() else candidate.label
            # The label as well as the page, because where five options share
            # one page, naming the page answers the first of
            # the five and nothing could reach the other four, so a scenario
            # names the option and the page still works for every page that is
            # one option.
            if title == page_title or candidate.label == page_title:
                return candidate
    return null


# --- The complaints a wrong step earns ----------------------------------------


## The complaint a step's value earns when its shape is wrong, and `""` when it
## is right.
##
## Every other key of a `curve_option` step goes through `bool()`, `float()`,
## `int()` or `String()`, which coerce whatever they are given. `sensor` and
## `points` are the two whose value is not a scalar, so they are checked here
## rather than cast, because a cast of the wrong type raises `Invalid cast` in the
## engine. A `SCRIPT ERROR` fails the run, so `{"sensor": "pressure"}`, the obvious
## spelling, would lose a whole capture that had done everything else it was
## asked.
##
## Public and static because a window is the only other way to reach it, and
## adding a `Window` in a headless test hangs.
static func shape_complaint(key: String, value: Variant, wanted_type: int, wanted: String) -> String:
    if typeof(value) == wanted_type:
        return ""
    return (
        "SaCapture: curve_option '%s' failed, it wants %s and was given a %s, %s"
        % [key, wanted, type_string(typeof(value)), JSON.stringify(value)]
    )


## The complaint a step earns when no control is on screen and the brush editor
## is the reason it is not, and `""` when the throwaway host is what was meant.
##
## `live_control` asks whether a control is visible in the tree and `live_window`
## asks only whether a window exists, so after a `{"brush_editor": {"close":
## true}}` step one of them finds a window the other does not. This step would
## then edit a bare throwaway option in the host and report it in the same shape
## as the painter's option, with no reading anywhere saying which it was, and a
## proof would go on showing the before-state of a fix that had landed.
##
## Two states earn the line and one does not. A hidden editor is the close and
## reopen trap. A visible editor whose page carries no curve option is the same
## silence with a different cause, because the step still edits a throwaway. No
## editor in the tree at all is the bare host, which `SaCurveOptionHost` opens on
## purpose.
static func shut_editor_complaint(tree: SceneTree) -> String:
    var window := SaBrushEditorDoor.live_window(tree) as Window
    if window == null:
        return ""
    var state := "hidden" if not window.visible else "showing a page with no curve option"
    return SHUT_EDITOR_COMPLAINT % state


# --- The steps a scenario writes ----------------------------------------------


## Drives the brush editor: applied in the order a hand would, opened, walked to
## a page, the page's box moved, then written, then tried on the pad, then picked
## from the fold, `{"brush_editor": {"open": true, "page": "General", "check":
## true, "save_as": "Inker", "rename": "Liner", "reset": true, "widget": {...},
## "scratch": {"paint": {"from": [40, 128], "to": [216, 128]}}, "presets":
## {"fold": true, "pick": "Inker"}, "close": true}}`.
##
## `description` writes the preset's description into its box, read before
## `save`, `save_as` and `rename`, so one step can type it and write it.
##
## `save_as` and `rename` press their button and then type the name with Return,
## because the two share one name field and the button is what decides whether
## the loaded preset stays.
##
## A helper rather than a click, for the reason every other window step gives:
## an editor is its own `Window` and an injected click never reaches one. What
## it proves is the path from each control's signal onwards, which is
## everything except the pixel the pointer landed on.
static func capture_editor(tree: SceneTree, spec: Dictionary, out_dir: String = "") -> String:
    var window := SaBrushEditorDoor.live_window(tree) as SaBrushEditorWindow
    # `{"close": true}` is `window.hide()`, so the window stays in the tree
    # and `live_window` keeps finding it. Without the visibility question a page
    # step after a close would switch the page on a window nobody can see, and the
    # `curve_option` step that followed would find no control and edit a
    # throwaway. Asked as `visible`, because a `Window` is its own root and the
    # visible-in-tree question `live_control` asks is the one a `Control` inside a
    # window answers.
    if window == null or not window.visible or bool(spec.get("open", false)):
        window = SaBrushEditorDoor.open(tree) as SaBrushEditorWindow
    if window == null:
        return "SaCapture: no brush editor, and none could be opened"

    if spec.has("page"):
        var wanted := String(spec["page"])
        var at := -1
        for i in window.page_list.page_count():
            if window.page_list.title_at(i) == wanted:
                at = i
                break
        if at < 0:
            return "SaCapture: the brush editor has no page called '%s'" % wanted
        window.show_page(at)
    if spec.has("check"):
        var at := window.page_list.selected
        window.set_page_enabled(at, bool(spec["check"]))
    # Typed into the description box before any write, as a painter fills it
    # in and then saves. The box's own signal, so the session hears it as a key.
    if spec.has("description"):
        window.preset_bar.description_edit.text = String(spec["description"])
        window.preset_bar.description_edit.text_changed.emit()
    if spec.has("save"):
        window.preset_bar.save()
    if spec.has("save_as"):
        window.preset_bar.save_as_button.pressed.emit()
        window.preset_bar.preset_name_edit.text_submitted.emit(String(spec["save_as"]))
    if spec.has("rename"):
        window.preset_bar.rename_button.pressed.emit()
        window.preset_bar.preset_name_edit.text_submitted.emit(String(spec["rename"]))
    if spec.has("reset"):
        window.preset_bar.reset()
    # A module widget's own capture door, `capture_option_edit`, handed the
    # dictionary. The stamp brush's tip preview takes a tip to load there, the
    # Load Tip action's door past the dialog nobody can drive. The preview lives
    # in the module that knows what a tip is, so the step reaches it here rather
    # than on the window.
    if spec.has("widget"):
        if _drive_widget(window, spec["widget"] as Dictionary) == NO_WIDGET:
            return NO_WIDGET
    # The burst a curve dragged by hand makes, which nothing else in the harness
    # can produce: `{"brush_editor": {"preview": 20}}` asks twenty times in one
    # frame, and the compressor's whole claim is that this costs one render.
    if spec.has("preview"):
        for _i in int(spec["preview"]):
            window.request_preview()
    # The scratch pad, which is inside this window, so an injected press never reaches
    # it: the same reason every other key here is a helper rather than a click.
    if spec.has("scratch"):
        window.scratch(spec["scratch"] as Dictionary)
    # The presets fold. The list applies the fold and answers the name, because what a
    # preset means is the window's to say and a list of rows holds no store.
    if spec.has("presets"):
        var picked := window.page_list.capture_presets(spec["presets"] as Dictionary)
        if not picked.is_empty():
            _pick_in_the_fold(window, picked)
    # A `Kind.CURVE` row is a graph a painter drags, and a drag is the one
    # thing this harness cannot inject: the editor is its own `Window`. So the
    # step hands the graph the points a hand would have dragged it to, which
    # proves everything from `curve_changed` onwards, the same half of a gesture
    # every other key here proves. `{"falloff": [[0, 1], [0.3, 0.9], [1, 0]]}`,
    # on whichever page is open, keyed by the option rather than by the page
    # because a second `CURVE` row would want the same step.
    if spec.has("falloff"):
        var complaint := _drag_curve_row(window, spec["falloff"] as Array, StringName(String(spec.get("row", "tip_falloff"))))
        if not complaint.is_empty():
            return complaint
    if spec.has("close"):
        window.hide()
    var line := "SaCapture: brush_editor %s" % JSON.stringify(window.editor_report())
    _write_editor_log(out_dir, line)
    return line


## Hands *step* to the first module widget on screen that answers the capture
## door, walking to the first page that carries one when the open page does not.
##
## A walk rather than a page name, because the page a widget sits on is its
## module's to say and this file names none. The walk stops on the page that
## took the step, which is where a hand would have been.
static func _drive_widget(window: SaBrushEditorWindow, step: Dictionary) -> String:
    var tree := window.get_tree()
    var answer := ToolOptionControls.capture_custom(tree, step)
    if answer != NO_WIDGET:
        return answer
    for index in window.pages.count():
        window.show_page(index)
        answer = ToolOptionControls.capture_custom(tree, step)
        if answer != NO_WIDGET:
            return answer
    return answer


## Drags the open page's `Kind.CURVE` row to *points*, or says why it could not.
##
## The row is found through the page's own `ToolOptionControls` rather than by
## node name, because that is where the control lives and a name is a thing a
## refactor moves.
static func _drag_curve_row(window: SaBrushEditorWindow, points: Array, row: StringName) -> String:
    var controls := window.pages.page_controls if window.pages != null else null
    var graph := SaCurveRow.graph_of(controls.control(row)) if controls != null else null
    if graph == null:
        return "SaCapture: the open page shows no curve row for '%s'" % row
    var wanted := PackedVector2Array()
    for point: Variant in points:
        var pair := point as Array
        if pair == null or pair.size() < 2:
            continue
        wanted.append(Vector2(float(pair[0]), float(pair[1])))
    if wanted.size() < 2:
        return "SaCapture: a curve row needs two points or more, got %d" % wanted.size()
    graph.set_points(wanted)
    return ""


## Drives a curve option: applied in the order a hand would, what is bound
## first, then what is picked, then what is written, `{"curve_option":
## {"preset": "s"}}` and the rest.
##
## Opens the bare host when no control is on screen, so a scenario proves the
## control rather than proving that some other part of the app is there.
static func capture_control(tree: SceneTree, spec: Dictionary) -> String:
    # Collected rather than returned at once, so a step that carries one wrong
    # key still applies the others and the answer names every complaint it
    # earned. A run that stops at the first mistake tells the writer about one.
    var complaints := PackedStringArray()

    var control := live_control(tree)
    if control == null:
        # The bare host below is right when nothing else has a control, which
        # is what it is for, and wrong when the painter's editor is
        # in the tree with its curve option out of reach. Only the
        # second case earns a line, so a scenario that means the bare host is
        # not told off for reaching it.
        var missed := shut_editor_complaint(tree)
        if not missed.is_empty():
            complaints.append(missed)
        # The throwaway is the module's to make: the host is opened on the
        # page's spec with no value, and the spec's binder builds a default
        # option, so this file names no class the stamp brush declares. A
        # `strength` in the step is applied below with the other keys.
        var page := String(spec.get("page", "Size"))
        control = SaCurveOptionHost.open(tree, curve_spec(tree, page), null, page)
    if control == null:
        return "SaCapture: no curve option control, and none could be opened"

    if spec.has("select"):
        control.call("select_sensor", String(spec["select"]))
    if spec.has("share"):
        control.call("set_use_same_curve", bool(spec["share"]))
    if spec.has("preset"):
        var applied: bool = control.call("apply_preset", String(spec["preset"]))
        if not applied:
            return "SaCapture: '%s' is not one of the eight curve presets" % String(spec["preset"])
    if spec.has("points"):
        var points_complaint := shape_complaint("points", spec["points"], TYPE_ARRAY, "an array of [x, y] pairs")
        if points_complaint.is_empty():
            var points := PackedVector2Array()
            for pair: Variant in spec["points"] as Array:
                if pair is Array and (pair as Array).size() >= 2:
                    points.append(Vector2(float((pair as Array)[0]), float((pair as Array)[1])))
            control.call("set_curve", points)
        else:
            complaints.append(points_complaint)
    if spec.has("drag") and spec["drag"] is Array and (spec["drag"] as Array).size() == 2:
        var ends := spec["drag"] as Array
        control.call("drag_curve", Vector2(ends[0][0], ends[0][1]), Vector2(ends[1][0], ends[1][1]))
    if spec.has("strength"):
        control.call("set_strength", float(spec["strength"]))
    if spec.has("use_curve"):
        control.call("set_use_curve", bool(spec["use_curve"]))
    if spec.has("combine"):
        control.call("set_combine", int(spec["combine"]))
    if spec.has("length"):
        control.call("set_length", int(spec["length"]))
    if spec.has("periodic"):
        control.call("set_periodic", bool(spec["periodic"]))
    if spec.has("angle_offset"):
        control.call("set_angle_offset", float(spec["angle_offset"]))
    if spec.has("lock_angle"):
        control.call("set_lock_angle", bool(spec["lock_angle"]))
    # Last, and reported by name, because this is the one edit that can be
    # refused: the last active sensor does not switch off.
    if spec.has("sensor"):
        var sensor_complaint := shape_complaint("sensor", spec["sensor"], TYPE_DICTIONARY, 'an object such as {"pressure": true}')
        if sensor_complaint.is_empty():
            var wanted := spec["sensor"] as Dictionary
            for key: Variant in wanted:
                var taken: bool = control.call("set_sensor_active", String(key), bool(wanted[key]))
                print("SaCapture: sensor %s -> %s %s" % [String(key), wanted[key], "taken" if taken else "REFUSED"])
        else:
            complaints.append(sensor_complaint)

    var answer := "SaCapture: curve_option %s" % JSON.stringify(control.call("option_report"))
    if complaints.is_empty():
        return answer
    # The complaints first, so the reader meets them before the report they are
    # about, and each on its own line because `sara_shot.py` scans by line.
    return "\n".join(complaints) + "\n" + answer


## Appends the editor's report to `brush_editor.txt` in *dir*, the run's own
## folder, handed in as a string rather than read off the runner, which is all
## this file would take the runner for.
##
## Appended rather than written, because a scenario walks several pages and the
## sequence is what says the list switched.
static func _write_editor_log(dir: String, line: String) -> void:
    if dir.is_empty():
        return
    var path := dir.path_join("brush_editor.txt")
    var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
    if file == null:
        push_warning("SaCapture: could not write %s" % path)
        return
    file.seek_end()
    file.store_line(line.trim_prefix("SaCapture: "))
