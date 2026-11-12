## The capture harness's steps over the layers docker and the brush, and the
## door's handle on the `layer` step.
##
## The layers docker's buttons sit in an embedded subwindow an injected click
## cannot reach, so without these steps a scenario could paint on the one layer
## a fresh document has and nothing else, and a check such as paint mid grey,
## put a Multiply layer above it, paint again, would be unphotographable. A
## sibling of `SaCapture` rather than more lines in it, because the steps over
## the stack are a subject of their own.
##
## The `layer` step itself, which builds and edits the stack, is
## `SaLayerStep`'s, and [method run] hands it the step. The rest are here: the
## docker's row picks, drags and renames, its More menu actions, and the brush,
## tool, bar and symmetry steps that had no better home.
class_name SaCaptureLayers
extends RefCounted

## The built-in dockers' ids, and where a docker's Window is asked for by one.
const DockerIds := preload("res://ui/main/sa_docker_ids.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const CanvasDriver := preload("res://harness/drivers/sa_canvas_driver.gd")
const StepKeys := preload("res://harness/scenario/layers/sa_brush_step_keys.gd")

## The `brush` step's keys that are read by the step rather than written onto
## the settings as fields.
const BRUSH_STEP_KEYS: Array[String] = ["tool", "preset", "colour", "radius_px", "tip_pipe", "seed", "painting_mode"]

## The five colour options `SaDynamics` reads by field name, each with what it
## does to the dab's colour, in the words the `brush` answer uses.
const COLOUR_OPTIONS: Dictionary[String, String] = {
    "hue_option": "turns the hue",
    "saturation_option": "moves the saturation",
    "value_option": "moves the value",
    "darken_option": "darkens it",
    "mix_option": "mixes it towards the background colour",
}


## Picks a set of layer rows: in the layers docker, the way a Ctrl click would,
## the `pick_rows` step. `{"pick_rows": [0, 2]}`, counted the way
## the docker draws them with the top of the stack first, and the last one named
## is the active row. An empty list clears the set back to the active layer
## alone.
##
## Same reason as `drag_row` below: an injected press does not route into an
## embedded docker, so the scenario calls what the press would call.
static func pick_rows(tree: SceneTree, rows: Array) -> String:
    var list := _layer_list(tree)
    if list == null:
        return "SaCapture: no layers docker to pick rows in"
    if rows.is_empty():
        return "SaCapture: no rows named, set left alone"
    list.picked.select(int(rows[0]))
    for i in range(1, rows.size()):
        list.picked.select_extra(int(rows[i]))
    return "SaCapture: rows %s picked" % str(list.picked.selected_indices())


## Clicks rows with Shift: a plain click on the first row named, then a shift
## click on each one after it, `{"shift_rows": [0, 2, 1]}`. Counted the way the docker draws them, top of the
## stack first.
##
## Its own step rather than a flag on `pick_rows` because the two gestures
## differ in what they leave active, which is the whole point of the step, and
## a scenario reading `layers_docker.rows` back has to be able to say which
## gesture it made.
##
## Same reason as `pick_rows`: an injected press does not route into an embedded
## docker, so the scenario calls what the press would call. The emit that
## follows a real press is called too, because the active layer lives on the
## document rather than on the list and only that signal moves it.
static func shift_rows(tree: SceneTree, rows: Array) -> String:
    var list := _layer_list(tree)
    if list == null:
        return "SaCapture: no layers docker to shift click in"
    if rows.is_empty():
        return "SaCapture: no rows named, set left alone"
    list.picked.select(int(rows[0]))
    list.item_selected.emit(list.picked.selected_idx)
    for i in range(1, rows.size()):
        list.picked.select_to(int(rows[i]))
        list.item_selected.emit(list.picked.selected_idx)
    return "SaCapture: rows %s picked, %d active" % [str(list.picked.selected_indices()), list.picked.selected_idx]


## Acts on the picked rows: one of the docker's own actions on the set of picked
## rows, `{"layer_action": "group"}`.
## The buttons and the More menu sit in an embedded subwindow a click cannot
## reach, so this is the same door they go through with the pointer left out.
static func layer_action(tree: SceneTree, name: String) -> String:
    var docker := CaptureRun.DockerLookup.window(tree, DockerIds.LAYERS)
    var actions: SaLayerActions = docker.actions if docker != null and "actions" in docker else null
    if actions == null:
        return "SaCapture: no layers docker to act on"
    match name:
        # The More button itself, so a scenario can show the dropdown
        # `SaChoicePopup` open rather than only what its rows do.
        "more":
            actions.more_btn.pressed.emit()
        "group":
            actions.toggle_group()
        "delete":
            actions.delete_layer()
        "duplicate":
            actions.duplicate_layer()
        "merge_down":
            actions.merge_down()
        # The docker's Move Up and Move Down, over the picked rows as the
        # More menu's two rows run them.
        "move_up":
            actions.move_layer(1)
        "move_down":
            actions.move_layer(-1)
        "filter_delete":
            actions.menu.press_row(actions.FILTER_DELETE)
        # The two locks the row's own buttons end in, so a scenario can flip a
        # lock the way a painter does rather than writing the flag.
        "lock":
            actions.set_paint_lock(true)
        "unlock":
            actions.set_paint_lock(false)
        "alpha_lock":
            actions.set_alpha_lock(true)
        "alpha_unlock":
            actions.set_alpha_lock(false)
        # The step a height-writing dab takes on the active layer, taken with
        # no brush that writes height needed to take it.
        "add_height":
            var doc: SaDocument = actions.target_canvas.document if actions.target_canvas != null else null
            if doc == null or not SaHeightOps.new(doc).gain(doc.active_layer):
                return "SaCapture: the active layer takes no height"
        # Two millimetres of height over every chunk the active layer
        # holds, gaining the field first, so a scenario can move relief before
        # a brush lays any. A transfer, and frames stand between it and the
        # next kernel that reads it.
        "raise_height":
            var doc: SaDocument = actions.target_canvas.document if actions.target_canvas != null else null
            var layer := doc.active_layer if doc != null else null
            if layer == null or (not layer.carries_height() and not SaHeightOps.new(doc).gain(layer)):
                return "SaCapture: the active layer takes no height"
            for grid_pos: Vector2i in layer.chunks:
                layer.get_or_create_field(grid_pos, SaFieldSpec.HEIGHT).clear(Color(2.0, 0.0, 0.0, 0.0))
        # Ridges a millimetre either side of one, 32 pixels apart, in every
        # cell of the active layer, so a scenario has slopes for the view's
        # resolve to light, where `raise_height`'s flat two millimetres have none.
        "raise_ridges":
            var doc: SaDocument = actions.target_canvas.document if actions.target_canvas != null else null
            if doc == null or (not doc.active_layer.carries_height() and not SaHeightOps.new(doc).gain(doc.active_layer)):
                return "SaCapture: the active layer takes no height"
            for grid_pos: Vector2i in SaLayer.grid_positions(doc.canvas_size):
                var texture := doc.active_layer.get_or_create_field(grid_pos, SaFieldSpec.HEIGHT)
                var bytes := PackedByteArray()
                bytes.resize(texture.size.x * texture.size.y * 2)
                for i in texture.size.x * texture.size.y:
                    bytes.encode_half(i * 2, 1.0 + cos(TAU * float(i % texture.size.x) / 32.0))
                GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)
            doc.invalidate_all_allocated_chunks()
        _:
            # `raise_paint:<mm>` stands the active layer's paint up by its
            # own alpha, so a stroke painted before it is a stroke *mm* thick
            # with edges as soft as the brush's, which the view can light
            # before a brush deposits height of its own.
            if name.begins_with("raise_paint:"):
                return _raise_paint(actions, float(name.get_slice(":", 1)))
            # A mask row of the menu by its command id, on whatever the menu
            # acts on: the active layer, or the picked filter's record.
            if not SaMaskOps.ALL.has(StringName(name)):
                return "SaCapture: no layer action called '%s'" % name
            actions.run_mask_command(StringName(name))
    return "SaCapture: layer action %s" % name


## The active layer's height set to its paint's alpha times *millimetres* in
## every cell it holds paint in. On the GPU, through the height field's own
## `height_over` kernel: the height is cleared to nothing and covered by a stand-in that
## stands *millimetres* high everywhere, as far as the paint covers it, so the
## canvas never leaves VRAM for a scenario step either.
static func _raise_paint(actions: SaLayerActions, millimetres: float) -> String:
    var doc: SaDocument = actions.target_canvas.document if actions.target_canvas != null else null
    var layer := doc.active_layer if doc != null else null
    if layer == null or (not layer.carries_height() and not SaHeightOps.new(doc).gain(layer)):
        return "SaCapture: the active layer takes no height"
    if GlobalShaderCompiler.get_rd() == null:
        return "SaCapture: no rendering device to raise the paint on"
    var compute := SaCompute.new("height")
    var stands: SaTexture = null
    for grid_pos: Vector2i in layer.chunks:
        var paint := layer.get_field(grid_pos)
        if paint == null:
            continue
        var height := layer.get_or_create_field(grid_pos, SaFieldSpec.HEIGHT)
        if stands == null:
            stands = SaTexture.new(Vector2i(1, 1), height.format)
            stands.clear(Color(millimetres, 0.0, 0.0, 1.0))
        height.clear(Color(0.0, 0.0, 0.0, 0.0))
        compute.use_storage_format(height.format)
        compute.use_binding_format(2, paint.format)
        compute.set_texture(0, height.rid)
        compute.set_texture(1, stands.rid)
        compute.set_texture(2, paint.rid)
        compute.set_push_constant_float_array(PackedFloat32Array([1.0, 1.0, 0.0, 0.0]))
        compute.dispatch_kernel("height_over", SaCompute.groups_for(height.size.x), SaCompute.groups_for(height.size.y), 1)
    doc.invalidate_all_allocated_chunks()
    return "SaCapture: the active layer's paint stands %.2f mm" % millimetres


## The layers docker's row list, or null when the docker is not built.
static func _layer_list(tree: SceneTree) -> SaLayerList:
    var docker := CaptureRun.DockerLookup.window(tree, DockerIds.LAYERS)
    return docker.item_list if docker != null and "item_list" in docker else null


## Drags a layer row: without a pointer.
##
##     {"drag_row": {"from": 2, "to": 0, "mode": "above"}}
##     {"drag_row": {"from": 2, "over": 0, "mode": "into"}}
##
## `from` is the row picked up, counted the way the docker draws them with the
## top of the stack first. `to` drops it and `over` stops mid-drag with the mark
## drawn, which is the state the insertion line is photographed in. `mode` is
## `above`, `below` or `into`, and defaults to `above`.
##
## The list is driven by its own three calls rather than by injected mouse
## events, which is the short way to put the mark on a chosen row. Real mouse
## events do reach an embedded docker, and `layer-row-drag.json` drives the whole
## gesture with them.
static func drag_row(tree: SceneTree, spec: Dictionary) -> String:
    var list := _layer_list(tree)
    if list == null:
        return "SaCapture: no layers docker to drag a row in"
    var mode := _drop_mode(String(spec.get("mode", "above")))
    var from := int(spec.get("from", -1))
    list.begin_drag(from)
    if spec.has("over"):
        list.drag_over(int(spec["over"]), mode)
        return "SaCapture: row %d held over row %d, %s" % [from, int(spec["over"]), spec.get("mode", "above")]
    list.drag_over(int(spec.get("to", -1)), mode)
    list.drop()
    return "SaCapture: row %d dropped %s row %d" % [from, spec.get("mode", "above"), int(spec.get("to", -1))]


## Renames a layer in its row: it opens a row's name, types into the field, and
## answers it, through the same handlers a keyboard and a pointer reach. A row
## scrolled out of the docker is scrolled into view first and clicked a frame
## later, and the answer says whether it scrolled.
##
##     {"layer_rename": {"row": 1, "open": "double"}}
##     {"layer_rename": {"text": "Sky", "key": "enter"}}
##     {"layer_rename": {"open": "f2"}}
##
## `open` is "double" for the double click on the row and "f2" for the key on
## the active row, `text` replaces what the field holds, and `key` is "enter" to
## commit or "escape" to throw it away. Keys are done in that order, so one step
## can open, type and answer.
##
## The events go into the docker's own `Window` with `push_input`, which is what
## the embedder does with them, so both handlers are reached the way a real
## keyboard and pointer reach them.
##
## `Input.parse_input_event` cannot serve, and the reason is the key rather than
## the press. A press carries a position, so the root viewport hands it to the
## embedded docker under that point, which is what `layer-row-eye.json` proves. A key
## carries none, so nothing routes it into a subwindow: F2 and three letters pushed that way
## were each read by the main window as a tool shortcut, leaving the canvas
## changed and the rename never opened. The `press` step has no double click in
## it either, which is the other half of what this step supplies.
static func rename(tree: SceneTree, spec: Dictionary) -> String:
    var list := _layer_list(tree)
    if CaptureRun.DockerLookup.window(tree, DockerIds.LAYERS) == null or list == null:
        return "SaCapture: no layers docker to rename in"
    var row := int(spec.get("row", -1))
    if String(spec.get("open", "")) != "double" or row < 0 or row >= list.rows.size():
        return _rename_now(tree, spec, false)
    # A row beyond the scroll's clip has a rect no push lands on. The
    # list scrolls it into view, and the rows move only when the container
    # sorts them, so the press waits a frame for the report to say where.
    var before := Vector2i(list.scroll_horizontal, list.scroll_vertical)
    list.ensure_control_visible(list.rows[row])
    if Vector2i(list.scroll_horizontal, list.scroll_vertical) == before:
        return _rename_now(tree, spec, false)
    tree.process_frame.connect(func() -> void: print(_rename_now(tree, spec, true)), CONNECT_ONE_SHOT)
    return "SaCapture: rename scrolled row %d into view, the double click follows next frame" % row


## The rename itself, once the row it opens on is in view. `scrolled` is said in
## the answer, so a scenario can tell a long stack's rename from a short one's.
static func _rename_now(tree: SceneTree, spec: Dictionary, scrolled: bool) -> String:
    var docker := CaptureRun.DockerLookup.window(tree, DockerIds.LAYERS)
    var list := _layer_list(tree)
    if docker == null or list == null:
        return "SaCapture: no layers docker to rename in"

    var done: Array[String] = []
    match String(spec.get("open", "")):
        "double":
            var row := int(spec.get("row", -1))
            var report: Array = list.row_report()
            if row < 0 or row >= report.size():
                return "SaCapture: no row %d to rename" % row
            var rect: Dictionary = report[row]["rect"]
            var at := Vector2(float(rect["x"]) + float(rect["w"]) * 0.5, float(rect["y"]) + float(rect["h"]) * 0.5)
            # The plain press first, because a double click is the second of a
            # pair and the first is what selects the row.
            _push_click(docker, at, false)
            _push_click(docker, at, true)
            done.append("double click on row %d, %s" % [row, "scrolled into view" if scrolled else "already in view"])
        "f2":
            _push_key(docker, KEY_F2, 0)
            done.append("F2")
        "":
            pass
        var other:
            return "SaCapture: no way to open a rename called '%s'" % other

    if spec.has("text"):
        var text := String(spec["text"])
        for i in text.length():
            _push_key(docker, OS.find_keycode_from_string(text[i].to_upper()), text.unicode_at(i))
        done.append("typed '%s'" % text)

    match String(spec.get("key", "")):
        "enter":
            _push_key(docker, KEY_ENTER, 0)
            done.append("Enter")
        "escape":
            _push_key(docker, KEY_ESCAPE, 0)
            done.append("Escape")
        "":
            pass
        var other:
            return "SaCapture: no rename answer called '%s'" % other

    return "SaCapture: rename %s, row %d open" % [", ".join(done), list.renaming_row()]


## A press and a release at a point in the docker window's own coordinates,
## which is what the row rects the state dump carries are measured in.
static func _push_click(window: Window, at: Vector2, double: bool) -> void:
    for pressed: bool in [true, false]:
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = pressed
        event.double_click = pressed and double
        event.position = at
        event.global_position = at
        window.push_input(event, true)


## A press and a release of one key. The unicode matters as much as the keycode:
## a `LineEdit` inserts what the event carries there, so a key pushed without it
## moves the caret and types nothing.
static func _push_key(window: Window, keycode: Key, unicode: int) -> void:
    for pressed: bool in [true, false]:
        var event := InputEventKey.new()
        event.keycode = keycode
        event.physical_keycode = keycode
        event.unicode = unicode
        event.pressed = pressed
        window.push_input(event, true)


## The scenario's word for an edge. A dictionary constant cannot hold these,
## because another class's enum is not a constant expression here.
static func _drop_mode(name: String) -> SaLayerList.Drop:
    match name:
        "below":
            return SaLayerList.Drop.BELOW
        "into":
            return SaLayerList.Drop.INTO
        _:
            return SaLayerList.Drop.ABOVE


## Sets brush fields by name: on the active brush's settings, so a scenario can
## turn the stabilizer on without reaching the bar's dropdown, names under
## `unset` every key it could not set, and takes a `seed` that the strokes after
## it are laid with. `{"brush": {"stabilizer_mode": 2, "stabilizer_amount":
## 0.8}}`.
##
## Each key written by name is read back afterwards, because `set_indexed`
## drops what it cannot write without a word: a number over a resource that
## holds its number under `value`, such as the stamp brush's `hardness`, and a
## path that names nothing, such as `ratio:value`. The answer ends on `unset`
## and a JSON object of every key that did not take, each with the path that
## would reach it or null when none does, `unset {"hardness": "hardness:value",
## "ratio:value": "tip:ratio", "hardnes": null}`, and on `unset {}` when every
## key took. A key took when its field
## holds what was asked or changed from what it held. The step still answers
## as it did, so a scenario that sets a key one brush lacks keeps running, and
## a `radius_px` sent to a brush with no radius is named there as well.
##
## A field on a sub-resource is a path, and `tip:angle` is the tip's own turn,
## in radians as `SaBrushTip.angle` reads it and a shipped preset stores it:
## `{"brush": {"tip:angle": 0.785}}` stands the tip at 45 degrees, where 45
## would turn it 45 radians. `masking:tip:angle` is the mask's, in radians too.
## A drawing angle sensor's `angle_offset` under `pen_settings` is in degrees.
##
## One key is not a field: `pen_settings` is handed to the settings resource's
## own `apply_pen_settings`, which reaches the nine curve options and can tick a
## sensor, so a scenario can prove Rotation by tilt without the brush editor.
## `{"brush": {"pen_settings": {"rotation": {"enabled": true, "sensors":
## ["tilt_direction"]}}}}`. Pressure ticked on an option that read no sensor
## and is given no curve is read along the curve the bar's switch draws: the
## stamp's Size along pressure to the power 4.8 and its Opacity to 1.2, the
## noise brush's Size from a third up the same 4.8. The harness pen's table,
## `SaHarnessPen`, is fitted to that 4.8, so a stroke step's pressure lays
## nearly that share of the full width either way, `size_by_pressure` or
## `pen_settings`. A `common_curve` beside the tick is read as given, and the
## straight line it replaces put a stroke sent at 0.2 at about 0.6 of the
## width. A `common_curve`, and a sensor's `curve`, is a list of pairs
## `[[0, 0.02], [1, 1]]` or of objects `{"x": 0, "y": 0.02}`, x from 0 to 1 and
## rising, and a curve in any other form refuses the step by its path before
## anything is set, the preset included. Nor is `tool`, which names the brush whose settings
## the step writes when it is not the stamp: `{"brush": {"tool": "noise_brush",
## "smudge_pickup_option:enabled": true}}`.
##
## Three more keys set what a painter sets before a stroke, so one step does
## the work of three, applied in this order and before any field:
## `{"brush": {"preset": "Airbrush", "colour": "#4080c0", "radius_px": 12}}`.
## `preset` is a stored name, matched the way `pick_preset` matches one and
## loaded through the bar's preset group, so it works with the Brush Presets
## docker closed. A name that matches nothing changes nothing, and the answer
## names the presets on offer. With no `tool` beside it, the keys after it write
## onto the engine the load put in the hand. `colour` is a hex code or a channel
## list, through the `colour` step's own route, so a channel above 1.0 survives.
## `radius_px` is the radius in the pixels the bar shows, turned into the
## fraction of the document's `brush_side` that `radius` stores and held to the
## range a number typed on the bar is held to. `radius` keeps its meaning, so
## `{"radius": 0.05}` is still a twentieth of that side. The answer is what is in
## force after the step rather than what it asked for: the preset, the radius
## in pixels and as stored, the opacity, the blend mode, the colour, what will change that
## colour on the canvas with the key that switches each off, or that nothing
## will, and the tool in hand.
##
## `tip_pipe` writes a GIMP pipe too large to keep in the tree into the
## painter's tips folder and points the tip at it without loading it:
## `{"brush": {"tip_pipe": {"file": "knife.gih", "cells": 360, "side": 256}}}`,
## in `SaScenarioTips.pipe`.
##
## **A number past its field's band is refused**, and the step sets nothing
## after the preset. A field the brush clamps declares the band as its range
## hint, and `{"brush": {"texture_contrast": 3.0}}` answers that it could not
## set it, rather than answering as done and painting a contrast of one.
##
## `seed` is a whole number that every `stroke` step after it is laid with,
## plus the count of `stroke` steps sent since, so the noise brush's grain is
## the steps' and not the session's: `{"brush": {"preset": "Grain Round",
## "seed": 7}}` lays the next stroke with 7 and the one after with 8, whatever
## tool paints them. `"seed": null` gives the seed back to the press, which
## draws one off the clock. The answer says `seed 9 next` while one is set, and
## a `seed` that is neither a whole number nor null sets nothing and is named
## under `unset`. A stroke made of `press` and `release` steps is not counted.
##
## `painting_mode` is `"build-up"` or `"wash"`, the stamp brush's Cross row, and
## the answer gives the mode beside the opacity: `opacity 0.20 of each dab,
## painting_mode build-up`. Under build-up the opacity is each dab's, so the
## dabs of one stroke build on each other past it, and under wash it is the
## whole stroke's, which one stroke reaches and never passes. Wash is the
## glaze. A step without the key leaves the mode the
## preset set, and a brush that has no mode, the noise brush, names it under
## `unset`, as it does a name that is neither.
static func brush(tree: SceneTree, spec: Dictionary) -> String:
    var canvas := CanvasDriver.main_canvas()
    if canvas == null:
        return "SaCapture: brush step found no canvas"
    var machine := canvas.get_node_or_null("ToolMachine") as ToolMachine
    if machine == null:
        return "SaCapture: brush step found no brush"
    # Before the preset, so a curve the step cannot read leaves the brush as
    # it was.
    var refused_curves := PackedStringArray()
    var pen: Variant = StepKeys.PenCurves.read(spec.get("pen_settings", {}), refused_curves)
    if not refused_curves.is_empty():
        var said := "SaCapture: brush could not read the curve pen_settings:%s, a curve is %s, and set nothing"
        return said % [refused_curves[0], StepKeys.PenCurves.FORM]
    LoadedPresets.watch()
    # First, because a load copies every stored field onto the settings and
    # would undo a size set before it.
    if spec.has("preset"):
        var refused := _load_preset(tree, String(spec["preset"]))
        if not refused.is_empty():
            return refused
    # `tool` names another brush engine's settings, the noise brush's.
    var tool_id := String(spec.get("tool", _painter_in_hand(machine) if spec.has("preset") else "brush"))
    var tool: Variant = machine.get_tool(tool_id)
    if tool == null or not "settings" in tool:
        return "SaCapture: brush step found no brush"
    var past := _past_band(tool.settings as Object, spec)
    if not past.is_empty():
        return "SaCapture: could not set %s, and set nothing%s" % [past, " after the preset" if spec.has("preset") else ""]
    # Each key the step could not set, with the path that would reach it
    # or null.
    var unset := {}
    if spec.has("seed") and not StepKeys.DoorSeed.hand(machine, spec["seed"]):
        unset["seed"] = null
    if spec.has("painting_mode") and not StepKeys.PaintingModeKey.hand(tool.settings, spec["painting_mode"]):
        unset["painting_mode"] = null
    if spec.has("colour"):
        CanvasDriver.colour(spec["colour"])
    if spec.has("radius_px") and "radius" in tool.settings:
        var side := _brush_side(canvas.document)
        tool.settings.radius = clampf(float(spec["radius_px"]) / side, ToolMachine.BRUSH_RADIUS_MIN, ToolMachine.BRUSH_RADIUS_MAX)
    elif spec.has("radius_px"):
        unset["radius_px"] = null
    if spec.has("tip_pipe"):
        var pointed := SaScenarioTips.pipe(spec["tip_pipe"] as Dictionary)
        if pointed.is_empty():
            return "SaCapture: brush could not write the pipe %s" % JSON.stringify(spec["tip_pipe"])
        for field: String in pointed:
            tool.settings.set_indexed(field, pointed[field])
    for key: String in spec:
        if BRUSH_STEP_KEYS.has(key):
            continue
        # `pen_settings` reaches the nine curve options, which `set` cannot,
        # asked for by method name so the skeleton names no module script.
        if key == "pen_settings" and tool.settings.has_method("apply_pen_settings"):
            tool.settings.call("apply_pen_settings", pen)
            continue
        # `set_indexed` rather than `set`, so a field on a sub-resource is
        # reachable: `{"brush": {"tip:angle": 1.57}}` turns the tip, which
        # is a stored field with no bar option in front of it. A plain
        # name is an indexed path of one, so a plain name reads as a plain
        # property. Read back afterwards, because `set_indexed`
        # drops a number written over a resource, or onto a path that
        # names nothing, without a word.
        # The brush's blend is refused as the layer step's is, because a mode
        # no module registers lays its dabs as Normal with nothing said.
        if key == "blend_mode":
            var refusal := SaLayerStep.unregistered_blend(
                canvas.document.compositor.registry if canvas.document.compositor != null else null,
                StringName(String(spec[key])),
                "the brush's blend"
            )
            if not refusal.is_empty():
                push_error("SaCapture: brush %s" % refusal)
                unset[key] = null
                continue
        var before: Variant = tool.settings.get_indexed(key)
        tool.settings.set_indexed(key, spec[key])
        if not StepKeys.KeyReadBack.took(tool.settings, key, spec[key], before):
            unset[key] = StepKeys.KeyReadBack.reach(tool.settings, key, spec[key])
    EventBus.tool_changed.emit(tool_id)
    var in_force := _brush_in_force(tree, machine, tool.settings as Resource, _brush_side(canvas.document))
    return "%s%s, unset %s" % [in_force, _other_hand(machine, tool_id), JSON.stringify(unset, "", false)]


## What a `brush` step that wrote the settings of *tool_id* adds when the tool in
## *machine*'s hand is another one, naming both, or empty when they are one.
##
## **Why.** The Brush and the Eraser keep settings of their own, and a step with
## no `tool` key writes the Brush's. A painter who set a radius of 1 that way
## with the Brush in hand, then took up the Eraser, erased at the Eraser's 15 px
## and no answer had said the radius was not the Eraser's.
static func _other_hand(machine: ToolMachine, tool_id: String) -> String:
    var held := String(machine.active_tool_name)
    if held == tool_id:
        return ""
    var tool: Variant = machine.get_tool(held)
    var own := "paints with settings of its own" if tool != null and "settings" in tool else "does not paint"
    return ", wrote the settings of %s and not of %s, which %s" % [tool_id, held, own]


## The first field of *spec* whose number is outside the band its property
## declares on *settings*, as the field, the number and the band, or empty when
## every number is inside its band or the field declares none.
##
## Read off the property list, so the harness names no module's constants and a
## field with no range hint is written as it always was. The brush clamps such a
## field where it reads it, and the step refuses rather than write a number the
## stroke would paint as the clamp: contrasts of 1.5 and 3.0 laid one stroke
## and the step answered both as done. A path such as
## `tip:angle` is looked up on the resource its last name sits on.
static func _past_band(settings: Object, spec: Dictionary) -> String:
    for key: String in spec:
        var value: Variant = spec[key]
        if BRUSH_STEP_KEYS.has(key) or not (value is float or value is int):
            continue
        var path := key.rsplit(":", true, 1)
        var owner: Variant = settings.get_indexed(path[0]) if path.size() == 2 else settings
        if not owner is Object:
            continue
        for property: Dictionary in (owner as Object).get_property_list():
            if String(property["name"]) != path[path.size() - 1] or int(property["hint"]) != PROPERTY_HINT_RANGE:
                continue
            var band := String(property["hint_string"]).split(",")
            var low := float(band[0])
            var high := float(band[1])
            var number := float(value)
            if (number < low and not band.has("or_less")) or (number > high and not band.has("or_greater")):
                return "%s to %s, which is outside the %s to %s the brush clamps it to" % [key, value, low, high]
    return ""


## Lays the seed a `brush` step set on the stroke the `stroke` step *spec* has
## just spliced in, and counts that stroke. The press is
## one of the spliced steps, so it comes on a later frame and finds the seed
## laid. Nothing while no seed is set, so a scenario that sends none paints as
## it did, and nothing for the parts a stroke splices in behind itself under
## the same key, which are one stroke and not several.
static func seed_stroke(spec: Dictionary) -> void:
    for part: String in StepKeys.DoorSeed.STROKE_PARTS:
        if spec.has(part):
            return
    var canvas := CanvasDriver.main_canvas()
    var machine := canvas.get_node_or_null("ToolMachine") as ToolMachine if canvas != null else null
    var seeded := StepKeys.DoorSeed.on(machine) if machine != null else null
    if seeded != null:
        seeded.lay(machine)


## Loads the stored preset *wanted* comes to, through the bar's preset group,
## which is what the Brush Presets docker's own click calls, so no docker has to
## be open. Empty once it loaded, or the answer that says why nothing changed.
##
## Matched against every stored name rather than the docker's grid, which is a
## tag and a search a painter set and a script cannot see.
static func _load_preset(tree: SceneTree, wanted: String) -> String:
    var presets := ToolOptionsPresets.in_tree(tree.root)
    if presets == null:
        return "SaCapture: brush step found no tool options bar, so there is no preset to load"
    var stored: Array[String] = []
    stored.assign(presets.preset_store.list_names())
    var found := SaPresetPick.match_name(wanted, stored)
    if found.is_empty():
        return "SaCapture: brush found no preset named '%s' and changed nothing, on offer %s" % [wanted, JSON.stringify(stored)]
    if not presets.load_preset(found):
        return "SaCapture: brush could not load the preset '%s' and set nothing else" % found
    return ""


## The tool in *machine*'s hand when it carries brush settings, which after a
## preset's load is the engine that paints it, and the stamp brush otherwise.
static func _painter_in_hand(machine: ToolMachine) -> String:
    var held := String(machine.active_tool_name)
    var tool: Variant = machine.get_tool(held)
    return held if tool != null and "settings" in tool else "brush"


## The side a stored radius is a fraction of, `SaDocument.brush_side`, which is
## the document's shorter side until a crop keeps the one it had, and the bar's
## own stand-in when there is no document.
static func _brush_side(document: SaDocument) -> float:
    if document == null:
        return 1000.0
    return document.brush_side


## What the `brush` step leaves in force, read back off *settings* rather than
## echoed from the step, so an answer cannot claim a size the brush does not
## have. The colour is the four channels, which a hex code would clamp, and the
## hex code beside them when there is one.
static func _brush_in_force(tree: SceneTree, machine: ToolMachine, settings: Resource, side: float) -> String:
    var parts: Array[String] = [LoadedPresets.named(tree, settings)]
    if "radius" in settings:
        var stored := float(settings.get("radius"))
        parts.append("radius %.2f px, stored %.6f" % [stored * side, stored])
    if "opacity" in settings:
        parts.append(StepKeys.PaintingModeKey.opacity(settings))
    # The blend mode, so a script reads whether the next stroke lays paint or
    # takes it away, `blend erase` after the Eraser.
    if "blend_mode" in settings:
        parts.append("blend %s" % settings.get("blend_mode"))
    var colour: Color = settings.get("color") if "color" in settings else SaColors.foreground
    var channels := "colour [%.4f, %.4f, %.4f, %.4f]" % [colour.r, colour.g, colour.b, colour.a]
    var within := colour.r <= 1.0 and colour.g <= 1.0 and colour.b <= 1.0 and minf(minf(colour.r, colour.g), colour.b) >= 0.0
    parts.append(channels + (" #%s" % colour.to_html(false) if within else ""))
    parts.append(_colour_changers(settings))
    var seeded := StepKeys.DoorSeed.on(machine)
    if seeded != null:
        parts.append("seed %d next" % seeded.upcoming())
    parts.append("tool in hand %s" % machine.active_tool_name)
    return "SaCapture: brush %s" % ", ".join(parts)


## What will move the next dab's colour away from the one asked for, each with
## the key that switches it off through the same `brush` step, or that nothing
## will. Read by field name, so any engine's settings answer and the skeleton
## names no module script.
##
## **Why the answer says it.** A script whose greys come out tinted cannot tell
## a brush that turns its colour from a script that asked for the tint, unless
## the answer rules the brush in or out. A colour option counts only where the
## engine reads it (`SaDynamics._modulates`): on, through its curve, and with a
## sensor. The smudge stage's colour rate and length are given as the
## engine reads them, the rate nought and the length one when switched off,
## because an Oil Smudge whose two were off carried the paint under it in full
## and laid none of the colour asked.
static func _colour_changers(settings: Resource) -> String:
    var found: Array[String] = []
    var variation := float(settings.get("chroma_variation")) if "chroma_variation" in settings else 0.0
    if variation > 0.0:
        var turned := "the texture turns the hue and the saturation"
        found.append('colour variation %.2f, %s (off: "chroma_variation": 0)' % [variation, turned])
    for field: String in COLOUR_OPTIONS:
        var option := settings.get(field) as SaCurveOption if field in settings else null
        if option == null or not option.enabled or not option.use_curve:
            continue
        var sensors: Array[String] = []
        var only_texture := true
        for sensor: SaSensor in option.active_sensors():
            sensors.append(SaSensor.key_of(sensor.id))
            only_texture = only_texture and sensor.id == SaSensor.Id.TEXTURE
        # The colour variation above is this binding, already named with its key.
        if sensors.is_empty() or (variation > 0.0 and only_texture):
            continue
        found.append('%s %s by %s (off: "%s:enabled": false)' % [field, COLOUR_OPTIONS[field], " and ".join(sensors), field])
    if "color_source" in settings and int(settings.get("color_source")) != SaColorDynamics.Source.PLAIN:
        var source := String(SaColorDynamics.Source.find_key(int(settings.get("color_source"))))
        found.append('colour source %s (off: "color_source": %d)' % [source, SaColorDynamics.Source.PLAIN])
    var pickup := settings.get("smudge_pickup_option") as SaCurveOption if "smudge_pickup_option" in settings else null
    if pickup != null and pickup.enabled:
        var rate := _smudge_reading(settings, "smudge_color_rate_option", 0.0)
        var length := _smudge_reading(settings, "smudge_length_option", 1.0)
        var carried := "the smudge stage, which carries the paint under the dab into the colour"
        var amounts := "pickup %.2f, colour rate %.2f, length %.2f" % [pickup.strength, rate, length]
        found.append('%s, %s (off: "smudge_pickup_option:enabled": false)' % [carried, amounts])
    if found.is_empty():
        return "nothing changes the colour"
    return "colour changed by %s" % ", ".join(found)


## A smudge option's strength as the dab reads it: its own when switched on,
## and *off* when it is not, which `SaDynamics` reads as one for the length and
## nought for the colour rate.
static func _smudge_reading(settings: Resource, field: String, off: float) -> float:
    var option := settings.get(field) as SaCurveOption if field in settings else null
    return option.strength if option != null and option.enabled else off


## Picks a tool by its id: `{"tool": "lasso"}` makes that tool the permanent
## one, so a capture can photograph what a tool puts on the bar and in the Tool
## Options docker without clicking the toolbox.
##
## **Arguments.**
## - `tool` string or object, an id such as `brush`, or `id` and `options`.
## - `id` string, the tool's id.
## - `options` object, the tool's option keys and values.
##
## `{"tool": {"id": "gradient", "options": {"gradient_shape": 1}}}` also sets
## options by the keys the descriptor declares, through the same door the bar
## and the docker write through, because a tool whose shape decides what
## the capture shows has no other way to be photographed twice, and driving an
## OptionButton popup by coordinate is a capture that breaks when the row moves.
static func set_tool(spec: Variant) -> String:
    var options: Dictionary = {}
    var tool_id := ""
    if spec is Dictionary:
        var asked := spec as Dictionary
        tool_id = String(asked.get("id", ""))
        options = asked.get("options", {}) as Dictionary
    else:
        tool_id = String(spec)
    var canvas := CanvasDriver.main_canvas()
    var machine := canvas.get_node_or_null("ToolMachine") as ToolMachine if canvas != null else null
    if machine == null:
        return "SaCapture: tool step found no canvas"
    if not machine.registry.has(StringName(tool_id)):
        return "SaCapture: no tool called '%s'" % tool_id
    LoadedPresets.watch()
    machine.set_active_tool(StringName(tool_id))
    var written := _write_options(machine, StringName(tool_id), options)
    return "SaCapture: tool '%s'%s%s" % [tool_id, written, _paints_with(machine, StringName(tool_id), canvas.document)]


## What the tool *tool_id* taken up paints with, its own settings' preset,
## radius and blend, or empty for a tool that carries no brush settings.
##
## **Why.** The Brush and the Eraser keep settings of their own, so a radius set
## with the Brush in hand is not the one the Eraser erases at. The answer
## names the Eraser's, so a script reads the size before the first dab rather
## than in the paint it took away.
static func _paints_with(machine: ToolMachine, tool_id: StringName, document: SaDocument) -> String:
    var tool: Variant = machine.get_tool(tool_id)
    if tool == null or not "settings" in tool or tool.settings == null:
        return ""
    var settings := tool.settings as Resource
    var parts: Array[String] = [LoadedPresets.named(machine.get_tree(), settings)]
    if "radius" in settings:
        var stored := float(settings.get("radius"))
        parts.append("radius %.2f px, stored %.6f" % [stored * _brush_side(document), stored])
    if "blend_mode" in settings:
        parts.append("blend %s" % settings.get("blend_mode"))
    return ", paints with its own settings, %s" % ", ".join(parts)


## Writes *options* onto the active tool by option key, and says which landed.
static func _write_options(machine: ToolMachine, tool_id: StringName, options: Dictionary) -> String:
    if options.is_empty():
        return ""
    var descriptor := machine.registry.get_descriptor(tool_id)
    var tool_state := machine.active_tool
    if descriptor == null or tool_state == null:
        return " (no descriptor to write options through)"
    var done := PackedStringArray()
    for key: String in options:
        for option: SaOptionSpec in descriptor.options:
            if String(option.key) != key:
                continue
            if ToolOptionControls.write_spec(option, options[key], tool_state):
                done.append("%s=%s" % [key, options[key]])
    EventBus.tool_changed.emit(String(tool_id))
    return " with " + ", ".join(done)


## Moves one control on the bar: by option key, on the tool options bar,
## `{"bar_option": {"key": "radius", "value": 0.05}}`, and answers with what the
## bar shows and what the tool holds afterwards.
##
## The bar's twin of the Tool Options docker's `capture_option`, so a size or an
## opacity changed from the bar is capturable as well.
##
## It drives the control rather than calling `write_option`, for the reason the
## docker's step gives: what is worth proving is the path from the control's own
## signal onwards, the control writing the shown tool and the other surface
## mirroring it. `write_option` skips the control and would pass while the bar
## was wired to nothing.
##
## `value` is in the option's own units, which for a canvas-scaled slider such
## as `radius` is the fraction rather than the pixels the bar draws, and it is
## clamped to the slider's range. Two kinds are not driven here: a CUSTOM row has
## its own `ramp` step and may hold an object rather than a value, and an ACTION
## row is a press rather than a value to write.
static func bar_option(tree: SceneTree, spec: Dictionary) -> String:
    var bar := _tool_options_bar(tree)
    if bar == null or bar.options == null:
        return "SaCapture: no tool options bar"
    var key := StringName(String(spec.get("key", "")))
    var node := bar.options.control(key)
    if node == null:
        return "SaCapture: the tool options bar shows no control for '%s'" % key
    var value: Variant = spec.get("value")
    if not _drive_bar_control(node, value):
        return "SaCapture: nothing on the bar for '%s' takes %s" % [key, JSON.stringify(value)]
    return (
        "SaCapture: bar option %s, shown %s, tool %s"
        % [key, bar.control_value(key), bar.options.read(key, bar.shown_tool(), bar.shown_tool_id())]
    )


## Moves *node* to *value* so that the control's own signal fires, whatever kind
## of control it is. False when nothing here knows how to move it.
##
## Every branch sets the value without a signal and then emits, the way the
## docker's step does: a scenario that writes the value a control already holds
## still wants the write to happen, and Godot drops a signal for a value that
## did not change.
static func _drive_bar_control(node: Control, value: Variant) -> bool:
    var slider := node as FactorSlider
    if slider != null:
        slider.set_value_no_signal(clampf(float(value), slider.min_value, slider.max_value))
        slider.value_changed.emit(slider.value)
        return true
    var blend_button := node as BlendModeButton
    if blend_button != null:
        var refusal := SaLayerStep.unregistered_blend(blend_button.registry, StringName(String(value)), "the bar's blend")
        if not refusal.is_empty():
            push_error("SaCapture: bar option %s" % refusal)
            return true
        blend_button.select_mode(StringName(String(value)))
        blend_button.mode_selected.emit(blend_button.current)
        return true
    # Before the toggle branch, because an `SaChoiceButton` is a `Button` that is
    # not in toggle mode and would otherwise fall past both.
    var choice := node as SaChoiceButton
    if choice != null:
        if choice.select_value(value):
            choice.choice_picked.emit(choice.selected_value())
            return true
        var values := choice.choice_values()
        if not (value is int or value is float) or int(value) < 0 or int(value) >= values.size():
            return false
        choice.select_value(values[int(value)])
        choice.choice_picked.emit(choice.selected_value())
        return true
    var toggle := node as Button
    if toggle != null and toggle.toggle_mode:
        toggle.set_pressed_no_signal(bool(value))
        toggle.toggled.emit(toggle.button_pressed)
        return true
    return false


## The bar in *tree*, found by class rather than by name, so this step and the
## `tool_options_bar` block of the dump cannot disagree about which node it is.
static func _tool_options_bar(tree: SceneTree) -> ToolOptionsBar:
    for node in tree.root.find_children("*", "HBoxContainer", true, false):
        var bar := node as ToolOptionsBar
        if bar != null:
            return bar
    return null


## Sets the document's symmetry: `{"symmetry": {"horizontal": true, "vertical":
## false, "radial": 6}}`, on the document, so the next stroke is mirrored.
static func symmetry(document: SaDocument, spec: Dictionary) -> String:
    if document == null:
        return "SaCapture: symmetry step has no document"
    var mirrors := document.symmetry
    if spec.has("horizontal"):
        mirrors.mirror_horizontal = bool(spec["horizontal"])
    if spec.has("vertical"):
        mirrors.mirror_vertical = bool(spec["vertical"])
    if spec.has("radial"):
        mirrors.radial = int(spec["radial"])
    return "SaCapture: symmetry h %s v %s radial %d" % [mirrors.mirror_horizontal, mirrors.mirror_vertical, mirrors.radial]


## Adds, picks or changes a layer: it runs one step against *document*, and
## answers a line carrying JSON that says what it did, `SaCapture: layer {...}`.
## `SaLayerStep` owns the keys and the answer, this is the door's handle on it.
## An `of` no layer answers to refuses the step before anything runs, and the
## selection does not move. A `blend` no module registers is refused in
## `errors` with the registered id nearest in spelling.
##
## **Arguments.**
## - `of` string or number, the layer the keys act on, a name or an index from
##   the bottom, and the active layer without it.
## - `add` string, a layer's name, made active, and added when none has it.
## - `activate` string, the layer to make active, refused when none has it.
## - `opacity` number, 0 to 1.
## - `blend` string, a registered blend mode, such as `multiply`.
## - `visible` boolean, shows or hides it.
## - `fill` array, `[r, g, b, a]` over the whole layer.
## - `delete` boolean, deletes it.
## - `transform` object or `"none"`, a live transform: `move` `[x, y]`, `turn`
##   degrees clockwise, `scale` a number or `[sx, sy]` and `pivot` `[x, y]`, or
##   `corners`, four points the canvas's corners go to.
## - `duplicate_to` string, another open document by name or surface id, which
##   the layer or group `of` names is copied into, with `under` a group there
##   and `replace` true to swap the node of its name, `SaLayerDuplicateToStep`.
static func run(document: SaDocument, spec: Dictionary, types: SaLayerTypeRegistry = null) -> String:
    if spec.has("duplicate_to"):
        return SaLayerDuplicateToStep.run(document, spec)
    return SaLayerStep.run(document, spec, types)


## Which stored preset was last loaded onto each settings object, so an answer
## names the preset of the settings it reads and not the bar's.
##
## **Why.** The bar holds one preset name for every tool, and it keeps the name
## across a tool switch: after Inked Pen was loaded with the Brush in hand and
## the Eraser taken up, the bar still said Inked Pen while the Eraser painted
## with its own settings. A load lands on the tool in hand's settings, so
## each one heard on the bus is kept against those.
class LoadedPresets:
    ## The preset name last loaded onto each settings object, by instance id.
    static var _onto: Dictionary[int, String] = {}

    ## Starts listening for loads, once, before the first step that answers.
    ## A load before it is not known, and [method named] says so.
    static func watch() -> void:
        if not EventBus.preset_loaded.is_connected(_loaded):
            EventBus.preset_loaded.connect(_loaded)

    static func _loaded(stored_name: String) -> void:
        var canvas := CanvasDriver.main_canvas()
        var machine := canvas.get_node_or_null("ToolMachine") as ToolMachine if canvas != null else null
        var tool: Variant = machine.active_tool if machine != null else null
        if tool != null and "settings" in tool and tool.settings != null:
            _onto[(tool.settings as Object).get_instance_id()] = stored_name

    ## The preset of *settings* as an answer's words. A load onto them the door
    ## did not hear, one at boot above all, is not known, and the answer says
    ## so beside the bar's name rather than lend the bar's name to them.
    static func named(tree: SceneTree, settings: Resource) -> String:
        var id := settings.get_instance_id()
        if _onto.has(id):
            return "preset '%s'" % _onto[id] if not _onto[id].is_empty() else "no preset"
        var presets := ToolOptionsPresets.in_tree(tree.root)
        var shown := presets.selected_preset if presets != null else ""
        if shown.is_empty():
            return "no preset"
        return "preset not known, the bar shows '%s'" % shown
