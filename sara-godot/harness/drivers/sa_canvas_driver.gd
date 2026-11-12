## What a scenario does to the canvas without painting on it: the view, the
## wheel and the selection.
##
## Not three files of statics, each taking the tree or the root back as its
## first argument, which would be one class over three files rather than three
## classes. They are one class here because they answer one question, what
## the canvas is showing and what part of it is chosen, and because every one of
## them starts by finding the same canvas.
##
## [method main_canvas] stays static, and is the one thing outside this class
## that reaches in: the texel readback needs the canvas and has no runner to ask
## through. Nothing else here answers without one.
##
## Reached by path from the runner rather than by class name, so no editor
## rescan stands between a fresh checkout and a step.
class_name SaCanvasDriver
extends RefCounted

## The built-in dockers' ids, and where a docker's Window is asked for by one.
const DockerIds := preload("res://ui/main/sa_docker_ids.gd")
const MaskReader := preload("res://harness/drivers/sa_select_mask.gd")
## What refuses a `canvas` side no dialog could have made.
const SizeCheck := preload("res://harness/scenario/sa_scenario_size.gd")

## The undo step a dictionary `select` records, by the first of these keys it holds.
const STEP_TITLES: Dictionary[String, String] = {
    "mask": MaskReader.TITLE,
    "rect": SaSelection.RECT_TITLE,
    "ellipse": SaSelection.ELLIPSE_TITLE,
    "polygon": SaSelection.FREEHAND_TITLE,
    "wand": SaSelection.WAND_TITLE,
    "invert": SaSelection.INVERT_TITLE,
    "feather": SaSelection.FEATHER_TITLE,
    "border": SaSelection.BORDER_TITLE,
    "grow": SaSelection.GROW_TITLE,
    "shrink": SaSelection.SHRINK_TITLE,
}

## How many times a selection has been rewritten since the first `select` step
## of this run, which is the dump's witness that a selection step did something.
##
## Read from outside by `sa_state_report.gd`, which is handed this driver for
## the purpose, and written by nothing but the callback below.
##
## **Why the dump needs it at all.** `no_change` compares two dumps with the
## volatile keys taken out, and the only thing the dump said about a selection
## was the overlay's chunk count and the two boxes. A feather, a border and an
## invert all rewrite the mask inside the chunks it already covers, so the
## count and the boxes would be the same either side and the step would read as
## one that did nothing.
##
## It counts rewrites, not differences. `SaSelection.changed` fires when a
## kernel has run over the mask, and telling a rewrite that produced the same
## bits from one that did not would mean reading the mask back off the GPU,
## which the first hard rule forbids. A `select` step that asks for the same
## rectangle twice therefore still moves this, and that is the honest answer:
## the mask was written twice.
var selection_changes: int = 0

## The run, by path like every other harness file this one names.
const CaptureRun := preload("res://harness/sa_capture_run.gd")

## The run, read for the tree every step here begins from.
var _run: CaptureRun = null


func _init(run: CaptureRun) -> void:
    _run = run


## The canvas the painter is working on: the one the front surface draws into,
## which is the document a scenario or a notebook acts on.
##
## The harness's one lookup, over `SaCanvasView.front_canvas()`, which is the
## one answer `render` keeps to "which canvas is the front surface drawing
## into". The first canvas in the root window with a document would not do,
## because the Info docker's scratchpad is a second live canvas, and once a
## second document opens every tab stands in the root window too, so only the
## front surface picks one out.
##
## A canvas without a document is not one a step can act on, so it answers
## null rather than that canvas.
static func main_canvas() -> SaCanvas:
    var canvas := SaCanvasView.front_canvas()
    return canvas if canvas != null and canvas.document != null else null


## Fills the layer with a colour, `{"fill": [4.0, 4.0, 4.0]}`, so a scenario can
## put a value above 1.0 on the canvas without a brush: the heatmap and the
## exposure are about such values, and a stroke's alpha ramp would blur the
## question.
func fill(channels: Array) -> void:
    var canvas := main_canvas()
    if canvas == null or canvas.document.active_layer == null:
        push_warning("SaCapture: no active layer to fill")
        return
    var color := Color(float(channels[0]), float(channels[1]), float(channels[2]), 1.0)
    canvas.document.fill_layer(color)
    canvas.request_composite()
    print("SaCapture: fill %s" % color)


## Clears the selected area of the layer: `{"clear": true}` empties the active
## layer to transparent inside the painter's selection, or the whole layer when
## nothing is selected, as one undo step titled "Clear Layer". It is the call
## the Layer menu's Clear Layer makes, which Edit's Clear and the Delete key
## run too, and a group or a locked layer is refused here as it is there.
## One step on the GPU rather than `read_pixels` and `write_pixels` round
## trips. Answers `SaCapture: clear {...}` with
## whether it cleared, the layer, and whether a selection held it in.
func clear() -> void:
    var canvas := main_canvas()
    var document: SaDocument = canvas.document if canvas != null else null
    var layer: SaLayer = document.active_layer if document != null else null
    var answer := {"cleared": false}
    if layer == null:
        answer["error"] = "no active layer to clear"
    elif layer.is_group:
        answer["error"] = "a group holds layers rather than pixels, pick a layer inside it"
    elif layer.is_locked:
        answer["error"] = "the layer is locked"
    else:
        answer["inside_selection"] = document.selection != null and document.selection.active
        document.clear_layer(layer)
        canvas.request_composite()
        answer["cleared"] = true
    if layer != null:
        answer["layer"] = layer.name
    print("SaCapture: clear %s" % JSON.stringify(answer))


## Switches the view mode: by id, `{"view": "hdr_heatmap"}`, or back to the
## picture with `{"view": ""}`. The same call the View menu makes.
func view_mode(transform_id: String) -> void:
    var tree := _run.tree()
    var main_node := tree.current_scene
    if main_node == null or not ("registries" in main_node):
        push_warning("SaCapture: no registries to switch the view with")
        return
    var registry: SaViewTransformRegistry = main_node.registries.view_transforms
    if not registry.set_mode(StringName(transform_id)):
        push_warning("SaCapture: no view mode called '%s'" % transform_id)
        return
    print("SaCapture: view mode '%s'" % transform_id)


## Flips a view toggle, `{"toggle": "gamut_warning"}`, the way the View menu's
## check item does.
func view_toggle(transform_id: String) -> void:
    var tree := _run.tree()
    var main_node := tree.current_scene
    if main_node == null or not ("registries" in main_node):
        push_warning("SaCapture: no registries to flip a view toggle with")
        return
    var registry: SaViewTransformRegistry = main_node.registries.view_transforms
    var id := StringName(transform_id)
    if not registry.set_enabled(id, not registry.is_enabled(id)):
        push_warning("SaCapture: no view toggle called '%s'" % transform_id)
        return
    print("SaCapture: view toggle '%s' -> %s" % [transform_id, registry.is_enabled(id)])


## Sets the canvas size: that size, by the two calls File > New makes once its
## dialog is confirmed, with the layers left where they are, `{"canvas": [3840,
## 2160]}`.
##
## The upgrade the painter means by "full HD to 4K". It resizes without
## moving the origin, which is what neither of the other two doors does: the
## crop tool grows but only by re-tiling onto the rectangle the hand
## dragged, and Image > Canvas Size places the old picture by an anchor.
func canvas_size(wanted: Array) -> void:
    var canvas := main_canvas()
    if canvas == null or canvas.document == null:
        push_warning("SaCapture: no main canvas to resize")
        return
    if wanted == null or wanted.size() < 2:
        push_warning("SaCapture: canvas needs [width, height]")
        return
    # A side no dialog could have made is refused before the document is touched.
    if SizeCheck.is_pair(wanted) and not SizeCheck.refusal("canvas", wanted).is_empty():
        return
    var size := Vector2i(maxi(1, int(wanted[0])), maxi(1, int(wanted[1])))
    # The document first and the signal second, the order `SaCrop` uses, so
    # every listener including the view itself sees the size it is about to
    # measure against.
    canvas.document.canvas_size = size
    EventBus.document_resized.emit(canvas.document, size)
    canvas.request_composite()
    print("SaCapture: canvas %s" % size)


## Zooms the main canvas: to `value`, keeping the point under the viewport
## centre where it is. The same arithmetic as the zoom tool, written against the
## canvas directly so the step does not depend on which view API the tools use.
func zoom(value: float) -> void:
    var canvas := main_canvas()
    if canvas == null:
        push_warning("SaCapture: no main canvas to zoom")
        return
    var centre := canvas.get_viewport_rect().size / 2.0
    # Through the mirror, because the flip rides on the sign of the same scale
    # and a zoom that wrote Vector2(clamped, clamped) would quietly undo it.
    var flip := SaCanvasView.for_canvas(canvas).get_flip()
    var local_centre := (centre - canvas.position) / absf(canvas.scale.x) * flip
    var clamped := maxf(0.001, value)
    canvas.scale = flip * clamped
    canvas.position = centre - local_centre * flip * clamped
    canvas.request_composite()
    print("SaCapture: zoom %.3f" % clamped)


## Fits the document in view: it puts the whole document in the view and centres
## it, the call View > Fit to View makes, `{"fit": true}`.
##
## The step a shot wants in front of it: without it a scenario that zoomed in
## to work on a corner has no way back to the whole picture, so every shot after
## the zoom is a photograph of a corner and a reader has to be told which.
##
## The zoom either side is printed, because a fit on a view that was already
## fitted changes nothing and that has to be tellable from a fit that did not
## run. The chunks outside the composited region are invalidated afterwards,
## which is what the View menu does behind the same call: zooming out reveals
## chunks the compositor had no reason to draw.
func fit() -> void:
    var canvas := main_canvas()
    var document: SaDocument = canvas.document if canvas != null else null
    if canvas == null or document == null:
        push_warning("SaCapture: no document to fit the view to")
        return
    var view := SaCanvasView.for_canvas(canvas)
    var before := view.get_zoom()
    view.fit(document.canvas_size)
    document.reveal_all_allocated_chunks()
    canvas.request_composite()
    print(
        "SaCapture: fit %d by %d, zoom %.3f -> %.3f" % [document.canvas_size.x, document.canvas_size.y, before, view.get_zoom()]
    )


## Fills every chunk of the active layer with a black and white checkerboard
## of `cell` texels, uploaded from the CPU the way `SaExport.load_sad` uploads
## a chunk. One chunk's bytes are built once and reused, because a chunk edge
## is a multiple of any cell that divides it and the pattern tiles.
##
## `{"fine_checker": 1}` does the same over chunks made at `resolution_scale`
## 2.0 in place of the layer's, 512 texels across each, which is a layer at
## twice the document's resolution, without the layer carrying a resolution of
## its own.
func checker(cell: int, scale: float = 1.0) -> void:
    var canvas := main_canvas()
    if canvas == null or canvas.document.active_layer == null:
        push_warning("SaCapture: no active layer to fill")
        return
    var rd := GlobalShaderCompiler.get_rd()
    var layer: SaLayer = canvas.document.active_layer
    var size := canvas.document.canvas_size
    var pixel := 0
    var bytes := PackedByteArray()
    var half := false
    var uploaded := 0
    for gy in ceili(float(size.y) / SaLayer.CHUNK_SIZE):
        for gx in ceili(float(size.x) / SaLayer.CHUNK_SIZE):
            var chunk := layer.get_or_create_chunk(Vector2i(gx, gy))
            if scale != chunk.resolution_scale:
                chunk = SaChunk.create(layer.schema, scale)
                layer.chunks[Vector2i(gx, gy)] = chunk
            var texture: SaTexture = chunk.field(&"albedo")
            if texture == null:
                continue
            if bytes.is_empty():
                pixel = chunk.pixel_size()
                half = texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
                bytes = _checker_bytes(pixel, maxi(cell, 1), half)
            rd.texture_update(texture.rid, 0, bytes)
            uploaded += 1
    canvas.document.invalidate_all_allocated_chunks()
    canvas.request_composite()
    print("SaCapture: checker of %d texel cells over %d chunks at %.1f" % [cell, uploaded, scale])


static func _checker_bytes(pixel: int, cell: int, half: bool) -> PackedByteArray:
    var texel_bytes := 8 if half else 16
    var bytes := PackedByteArray()
    bytes.resize(pixel * pixel * texel_bytes)
    for y in pixel:
        for x in pixel:
            @warning_ignore("integer_division")
            var white := ((x / cell) + (y / cell)) % 2 == 0
            var value := 1.0 if white else 0.0
            var at := (y * pixel + x) * texel_bytes
            for channel in 4:
                var stored := 1.0 if channel == 3 else value
                if half:
                    bytes.encode_half(at + channel * 2, stored)
                else:
                    bytes.encode_float(at + channel * 4, stored)
    return bytes


## Picks the brush colour: through the same signal the colour picker and the
## eyedropper use, `{"colour": "#4080c0"}`. Exists because the default is black,
## and black multiplied by anything is black, so a Multiply layer merged with the
## default colour cannot be told from one that was not.
##
## **Arguments.**
## - `colour` string or array, `#rrggbb`, or channels that may pass 1.0.
static func colour(raw: Variant) -> void:
    # `{"colour": [3.0, 0.5, 0.2]}` as well as `{"colour": "#e0a040"}`, because a
    # hex code cannot name a channel above 1.0 and hard rule 5 says those are
    # exactly the values that have to survive, among them what proves the
    # picker's numeric sliders do not clamp what the eyedropper found.
    if raw is Array:
        var parts := raw as Array
        if parts.size() < 3:
            push_warning("SaCapture: a colour needs at least three channels")
            return
        var picked := Color(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]) if parts.size() > 3 else 1.0)
        EventBus.color_picked.emit(picked)
        print("SaCapture: colour %s" % str(picked))
        return
    var html := String(raw)
    if not Color.html_is_valid(html):
        push_warning("SaCapture: '%s' is not a colour" % html)
        return
    EventBus.color_picked.emit(Color.html(html))
    print("SaCapture: colour %s" % html)


## Sets the picker's other colour: the other of the pair, the one X swaps in and
## the one the Mix option blends towards, `{"background_colour": "#e0cc99"}`.
##
## Written onto `SaColors` rather than emitted on the bus, unlike the foreground
## above: the store is what holds the pair, its setter is what announces the
## change, and emitting straight would leave the picker showing the old swatch.
##
## Takes a list or a hex code for the reason the foreground does: a hex code
## cannot name a channel above 1.0 and hard rule 5 says those have to survive.
static func background_colour(raw: Variant) -> void:
    if raw is Array:
        var parts := raw as Array
        if parts.size() < 3:
            push_warning("SaCapture: a colour needs at least three channels")
            return
        var picked := Color(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]) if parts.size() > 3 else 1.0)
        SaColors.background = picked
        print("SaCapture: background colour %s" % str(picked))
        return
    var html := String(raw)
    if not Color.html_is_valid(html):
        push_warning("SaCapture: '%s' is not a colour" % html)
        return
    SaColors.background = Color.html(html)
    print("SaCapture: background colour %s" % html)


## Starts or stops the timelapse: it starts into the recorder docker's folder
## with `{"recorder": {"start": true, "settle": 0.5}}` and stops with
## `{"recorder": {"stop": true}}`, and either prints the frame count and where
## the frames are, which is what a scenario that paints twice and expects two
## frames reads.
func recorder(spec: Dictionary) -> void:
    var tree := _run.tree()
    var docker := CaptureRun.DockerLookup.window(tree, DockerIds.RECORDER) as RecorderDocker
    if docker == null:
        push_warning("SaCapture: no recorder docker")
        return
    if spec.has("settle"):
        docker.settle.value = float(spec["settle"])
    if spec.get("start", false):
        docker.record_button.button_pressed = true
    if spec.get("stop", false):
        docker.record_button.button_pressed = false
    var rec := docker.recorder
    print(
        (
            "SaCapture: recorder %s, %d frames in %s"
            % ["on" if rec.recording else "off", rec.frame_count, ProjectSettings.globalize_path(rec.directory)]
        )
    )


## Turns the mouse wheel: three notches in at a point in logical units, negative
## for out, `{"wheel": {"at": [x, y], "notches": 3}}`. Returns the point, which
## the harness keeps as the last pointer so a `press` without an `at` lands there.
##
## A notch is a press and a release of a wheel button, which is what a real
## wheel sends. The point is handed over pre-multiplied by the root transform,
## as every injected event has to be.
##
## A point inside an embedded docker gets a press and a release on that docker's
## drag bar first, and its notches then go through the root rather than through
## `Input`, and `_reach_into` says why.
##
## `"pan"` sends a touchpad's two finger scroll in place of notches, one pan
## gesture for each delta in its list, `{"wheel": {"at": [x, y], "pan": [12.5,
## 7.5]}}`. A delta is what a compositor sends, ten for one wheel click and
## positive for down. `"read": true` prints where the scroll under the point
## stands once the notches or pans are in. Only a point inside a docker or a
## dialog is read, because only there are they delivered before the step ends.
func wheel(spec: Dictionary) -> Vector2:
    var root := _run.tree().root
    var coords := spec.get("at", []) as Array
    if coords == null or coords.size() < 2:
        push_warning("SaCapture: wheel needs an 'at' point")
        return Vector2.ZERO
    var at := Vector2(float(coords[0]), float(coords[1]))
    var notches := int(spec.get("notches", 1))
    var index := MOUSE_BUTTON_WHEEL_UP if notches > 0 else MOUSE_BUTTON_WHEEL_DOWN
    var physical := root.get_final_transform() * at

    var docker := _reach_into(root, at)
    var where := "the root" if docker == null else "'%s'" % docker.title

    if spec.has("pan"):
        var pans: Array = spec["pan"] if spec["pan"] is Array else [spec["pan"]]
        var total := 0.0
        for delta: Variant in pans:
            var pan := InputEventPanGesture.new()
            pan.delta = Vector2(0.0, float(delta))
            pan.ctrl_pressed = bool(spec.get("ctrl", false))
            pan.position = physical
            _deliver(root, docker, pan)
            total += float(delta)
        var said := "SaCapture: pan of %+.2f delta in %d gesture(s) at (%d, %d), routed to %s"
        print(said % [total, pans.size(), at.x, at.y, where])
    else:
        for _notch in absi(notches):
            for pressed: bool in [true, false]:
                var event := InputEventMouseButton.new()
                event.button_index = index
                event.pressed = pressed
                event.factor = 1.0
                event.ctrl_pressed = bool(spec.get("ctrl", false))
                event.position = physical
                event.global_position = physical
                _deliver(root, docker, event)
        print("SaCapture: wheel %+d notch(es) at (%d, %d), routed to %s" % [notches, at.x, at.y, where])

    if bool(spec.get("read", false)):
        print(_scroll_under(docker, at))
    return at


## Hands *event* to the root through `Input`, or straight to the root when it
## goes into *docker*, for the reason `_reach_into` gives.
static func _deliver(root: Viewport, docker: Window, event: InputEvent) -> void:
    if docker == null:
        Input.parse_input_event(event)
    else:
        root.push_input(event)


## Where the innermost scroll under *at* in *window* stands, its bar's value,
## the page it shows and how far it can travel, in one line.
static func _scroll_under(window: Window, at: Vector2) -> String:
    if window == null:
        return "SaCapture: no scroll read, (%d, %d) is not inside a docker or a dialog" % [at.x, at.y]
    var inside := window.get_final_transform().affine_inverse() * (at - Vector2(window.position))
    var found: ScrollContainer = null
    for node: Node in window.find_children("*", "ScrollContainer", true, false):
        var scroll := node as ScrollContainer
        if scroll.is_visible_in_tree() and scroll.get_global_rect().has_point(inside):
            found = scroll
    if found == null:
        return "SaCapture: no scroll under (%d, %d) in '%s'" % [at.x, at.y, window.title]
    var bar := found.get_v_scroll_bar()
    return (
        "SaCapture: scroll '%s' in '%s' stands at %.1f px, page %.1f, travel %.1f"
        % [found.name, window.title, bar.value, bar.page, bar.max_value - bar.page]
    )


## Makes the root route the notches that follow into the docker *at* is inside,
## with a press and a release on that docker's own drag bar.
##
## Every docker is an embedded `Window`, and the root forwards a mouse event into
## one only once it knows which subwindow is in play. A real pointer tells it
## that by moving, which the compositor reports, and an injected motion does not,
## as the `stroke` step's own documentation says: "An injected motion is never
## delivered to a Control's `gui_input`, so a hover reaches nothing, whatever its
## coordinates." A left press is routed by
## position instead, and that is the only thing here that establishes the docker.
##
## **The press is on the drag bar and not at the point the notches go to**. A
## press at the point lands on whatever control is under it, and in a toolbox at
## its floor that is a tool button, so the notches would scroll the docker and
## change the tool. The bar answers only to ALT,
## so a plain press on it does nothing, and six pixels in from the docker's own
## corner keeps it off the hide button at the far end.
##
## **The left button rather than one Sara binds nowhere, such as `XBUTTON1`**,
## because `Viewport` takes the left button alone for this. A screenshot of the
## docker compared byte for byte cannot tell a scroll from a tool change or from
## a hover highlight, so the witness is `docker_grips.corner_control`, because it reads the clipped rect of the
## control nearest the corner and so answers "which button is on screen".
##
## The notches go through `root.push_input` rather than `Input.parse_input_event`
## once there is a docker, so the press and the notches are one ordered batch.
## Queued through `Input` they are flushed together and the routing the press
## sets does not reach the notches beside it.
##
## This is a hole in the harness and not in the application. A painter's own
## pointer is where the compositor says it is, and without this no scenario can
## show a docker scroll.
static func _reach_into(root: Viewport, at: Vector2) -> Window:
    var docker := _docker_under(root, at)
    if docker == null:
        return null
    var corner := Vector2(docker.position) + Vector2(6, 6)
    var bar: Vector2 = root.get_final_transform() * corner
    for pressed: bool in [true, false]:
        var reach := InputEventMouseButton.new()
        reach.button_index = MOUSE_BUTTON_LEFT
        reach.pressed = pressed
        reach.position = bar
        reach.global_position = bar
        root.push_input(reach)
    return docker


## The embedded docker *at* is inside, or null when the point is the root's own.
static func _docker_under(root: Viewport, at: Vector2) -> Window:
    for window in SaCursorPolicy.embedded_subwindows(root):
        if window.visible and Rect2(Vector2(window.position), Vector2(window.size)).has_point(at):
            return window
    return null


## Selects a mask, a shape, all or none: a mask file the size of the
## canvas with `{"select": {"mask": "strips.npy"}}`, a closed polygon in document
## pixels with `{"select": {"polygon": [[x, y], ...]}}`, or rings with
## `[[[x, y], ...], [[x, y], ...]]`, a ring inside another a hole, a rectangle
## with `{"select": [x, y, w, h]}`, the canvas with `"all"` and nothing with
## `"none"`, a relative `mask` in a raw request read from the run's folder and
## `sara.py` sending the caller's own, and a mask that is not there, cannot be
## read or is the wrong size selects nothing, leaves the selection as it was and
## puts its reason, with the path it tried, in the answer's `errors`, as does a
## shape it cannot read, while the steps after it run as sent, and a mask that
## after its mode leaves the selection empty puts a warning naming it in the
## answer's `warnings`, since a fill or a filter then covers the whole layer. A mask is a
## `.npy` of one channel, float coverage 0 to 1 or uint8 255ths, or a picture
## whose first channel is read, and a soft mask selects softly. `{"grow": 4}` and `{"shrink": 4}`
## are the menu's "Grow Selection" and "Shrink Selection", recording nothing at 0
## or less, and `{"ellipse": [x, y, w, h]}`, `{"invert": true}`, `{"feather":
## 2.5}`, `{"border": 6}` and `{"quick_mask": true}` its other rows, each one undo
## step as the tool's, a feather keeping its fraction and the rest dropping it.
## The marquee and the lasso are the pointer steps'. `"anti_alias": true` grades
## a polygon's or an ellipse's edge by the share of each pixel it covers, as the
## lasso does, and `"mode"` `"subtract"`, `"add"` or `"intersect"` takes a mask,
## a polygon, a rectangle or an ellipse out of the selection, joins it or meets it.
func select(raw: Variant) -> void:
    # The tree for the role registry a wand's flood is asked of, below.
    var tree := _run.tree()
    var canvas := main_canvas()
    var document: SaDocument = canvas.document if canvas != null else null
    if document == null:
        push_warning("SaCapture: no document to select on")
        return
    var selection := document.selection
    _watch(selection)
    if raw is String:
        if String(raw) == "all":
            selection.change(SaSelection.ALL_TITLE, selection.select_all.bind(document.canvas_size))
        else:
            selection.change(SaSelection.DROP_TITLE, selection.deselect)
    elif raw is Dictionary:
        var spec := raw as Dictionary
        var mode := _mode(String(spec.get("mode", "replace")))
        var mask: Variant = MaskReader.read(spec, document.canvas_size, _run.out_dir) if spec.has("mask") else null
        if mask is String:
            _select_failed(mask)
            return
        var title := ""
        for key: String in STEP_TITLES:
            if title.is_empty() and spec.get(key, false):
                title = STEP_TITLES[key]
        var shapes := func() -> bool:
            select_shapes(selection, spec, mode)
            if mask is Image:
                MaskReader.merge(selection, mask, mode)
            if spec.get("invert", false):
                SaSelectionFilters.invert(selection, document.canvas_size)
            if spec.has("feather"):
                selection.feather.apply(selection, float(spec["feather"]), document.canvas_size, document.projection.wrapping)
            if spec.has("border"):
                SaSelectionFilters.border(selection, int(spec["border"]), document.canvas_size, document.projection.wrapping)
            if spec.has("grow"):
                SaSelectionFilters.grow(selection, int(spec["grow"]), document.canvas_size, document.projection.wrapping)
            if spec.has("shrink"):
                SaSelectionFilters.shrink(selection, int(spec["shrink"]), document.canvas_size, document.projection.wrapping)
            if spec.has("wand"):
                # `{"wand": [x, y], "tolerance": 0.1, "merged": true}` floods through the base module's role, and a run
                # with none fails in a sentence the shot reader counts, not at a parse error.
                var at := spec["wand"] as Array
                var flood := _engine_for(tree, &"flood")
                if flood == null:
                    _select_failed("no module registered a 'flood' role for the wand. The base module does.")
                    return false
                var wand: RefCounted = flood.new()
                var merged: SaTexture = null
                if bool(spec.get("merged", true)):
                    merged = _main_easel_output()
                var reached: int = wand.flood(
                    document,
                    Vector2i(int(at[0]), int(at[1])),
                    float(spec.get("tolerance", 0.1)),
                    mode,
                    merged,
                    document.active_layer
                )
                print("SaCapture: wand reached %d chunk(s)" % reached)
            return true
        if title.is_empty() and not spec.has("quick_mask"):
            _select_failed("%s holds no key a selection is made from" % JSON.stringify(spec))
            return
        if not title.is_empty() and not selection.change(title, shapes):
            return
        if mask is Image and not selection.active:
            _mask_left_nothing(String(spec["mask"]))
        if spec.has("quick_mask"):
            selection.editing = bool(spec["quick_mask"])
    else:
        var coords := raw as Array
        if coords == null or coords.size() < 4:
            _select_failed('select needs [x, y, w, h], "all", "none" or a dictionary')
            return
        selection.change(SaSelection.RECT_TITLE, selection.select_rect.bind(_rect(coords)))
    print(
        (
            "SaCapture: selection %s, %d chunk(s), %d mask rewrite(s) this run"
            % [JSON.stringify(raw), selection.chunks.size(), selection_changes]
        )
    )


## A `select` that made no selection, said as an error of the step, so the
## door's answer carries *why* in its `errors` as it does a stroke the brush
## tool turned away, and printed for the verdict line. The
## selection is left as it was.
static func _select_failed(why: String) -> void:
    print("SaCapture: select failed, %s" % why)
    push_error("SaCapture: select failed, %s" % why)


## A `select` whose mask, after its mode, left no selection, said as a warning
## in the door's answer. An empty selection is no selection, as the Select menu
## has it, so the next fill or filter covers the whole layer, and a painter who
## sent a mask of nothing meant something else. *name* is the mask as the step
## named it.
static func _mask_left_nothing(name: String) -> void:
    push_warning(
        (
            (
                "SaCapture: the mask %s selects nothing, so the document now has no selection"
                + " and a fill or a filter covers the whole layer"
            )
            % name
        )
    )


## Starts counting *selection*'s rewrites, once per selection.
##
## Connected on the first `select` step rather than when the document is built,
## because this class hears about a document only when a step reaches it, and
## it stays connected afterwards so a marquee dragged with the pointer steps
## moves the same number a `select` step does.
func _watch(selection: SaSelection) -> void:
    if not selection.changed.is_connected(_note_change):
        selection.changed.connect(_note_change)


## One rewrite of a mask this run has been watching.
func _note_change() -> void:
    selection_changes += 1


## The script registered under *role*, or null when nothing is, or when the
## scene has no registries to ask. The same door every construction site in
## the skeleton walks through.
static func _engine_for(tree: SceneTree, role: StringName) -> Script:
    var main_node := tree.current_scene
    if main_node == null or not ("registries" in main_node):
        return null
    return main_node.registries.roles.script_for(role)


## Writes the rectangle, the ellipse and the polygon *spec* names into
## *selection* in *mode*, the ellipse and the polygon graded at their edge when
## *spec* asks for `"anti_alias"`.
##
## A painting whose clouds have no line round them takes their edge from the
## selection, and a curve selected here with the hard edge steps a whole pixel
## at a time, though the mask grades a lasso's edge by default. A static of its
## own so a suite can ask it on a bare document.
static func select_shapes(selection: SaSelection, spec: Dictionary, mode: int) -> void:
    var smooth := bool(spec.get("anti_alias", false))
    if spec.has("rect"):
        selection.select_rect(_rect(spec["rect"]), mode)
    if spec.has("ellipse"):
        selection.select_ellipse(_rect(spec["ellipse"]), mode, smooth)
    if spec.has("polygon"):
        # One ring `[[x, y], ...]`, or rings `[[[x, y], ...], ...]` in which a
        # ring inside another is a hole.
        var list := spec["polygon"] as Array
        var nested := not list.is_empty() and list[0] is Array and not (list[0] as Array).is_empty() and list[0][0] is Array
        var rings := []
        for ring: Variant in list if nested else [list]:
            var points := PackedVector2Array()
            for pair: Variant in ring as Array:
                points.append(Vector2(float(pair[0]), float(pair[1])))
            rings.append(points)
        selection.select_rings(rings, mode, smooth)


static func _rect(coords: Variant) -> Rect2i:
    var list := coords as Array
    if list == null or list.size() < 4:
        return Rect2i()
    return Rect2i(int(list[0]), int(list[1]), int(list[2]), int(list[3]))


static func _mode(name: String) -> int:
    match name:
        "add":
            return SaSelection.Mode.ADD
        "subtract":
            return SaSelection.Mode.SUBTRACT
        "intersect":
            return SaSelection.Mode.INTERSECT
        _:
            return SaSelection.Mode.REPLACE


## The front document's composite, flushed, which is what a flood fill over
## the merged picture reads.
static func _main_easel_output() -> SaTexture:
    var canvas := main_canvas()
    if canvas == null or canvas.easel == null:
        return null
    canvas.easel.catch_up()
    canvas.easel.flush()
    return canvas.easel.output


## Cuts, copies or pastes: on the main document's active layer, by the same
## calls the Edit menu makes, `{"clipboard": "cut"}`, `"copy"` or `"paste"`.
func clipboard(action: String) -> void:
    var canvas := main_canvas()
    var document: SaDocument = canvas.document if canvas != null else null
    var tree := Engine.get_main_loop() as SceneTree
    var held := SaDocuments.clipboard_in(tree.current_scene if tree != null else null)
    if document == null or held == null:
        push_warning("SaCapture: no document or no clipboard for the clipboard step")
        return
    match action:
        "cut":
            held.cut(document, document.active_layer)
        "copy":
            held.copy(document, document.active_layer)
        "paste":
            held.paste(document)
        _:
            push_warning("SaCapture: no clipboard action called '%s'" % action)
            return
    print("SaCapture: clipboard %s, holding %d chunk(s)" % [action, held.chunks.size()])


## Puts fingers on the screen: one list of points per moment in root logical
## units, with one point a finger, `{"touch": [[[x, y], [x, y]], [[x, y], [x, y]],
## ...]}`. The first moment lands every finger, each one after moves them and the
## fingers lift after the last. Two fingers pan, pinch and turn the view, one
## finger moves nothing and paints nothing.
##
## Through `Input.parse_input_event`, so Godot emulates the mouse from the first
## finger as it does for a real screen, and that copy has to be refused by the
## canvas too. The buffer is flushed before the view is read, so the line says
## what the fingers came to rather than what they were about to. It prints the
## view and the active layer's chunk count either side. A stroke lands in the
## frames after its events, so the count a finger's paint shows up in is the
## next touch step's first one, with a wait between.
func touch(moments: Array) -> void:
    var root := _run.tree().root
    var canvas := main_canvas()
    var document: SaDocument = canvas.document if canvas != null else null
    if document == null or moments.is_empty():
        push_warning("SaCapture: touch needs a document and at least one moment")
        return
    var view := SaCanvasView.for_canvas(canvas)
    var before := _view_line(view)
    var chunks_before := document.active_layer.chunks.size()
    var fingers := (moments[0] as Array).size()
    for moment in moments.size() + 1:
        var points := moments[mini(moment, moments.size() - 1)] as Array
        for index in fingers:
            var coords := points[index] as Array
            var at := root.get_final_transform() * Vector2(float(coords[0]), float(coords[1]))
            if moment == 0 or moment == moments.size():
                var landing := InputEventScreenTouch.new()
                landing.index = index
                landing.position = at
                landing.pressed = moment == 0
                Input.parse_input_event(landing)
            else:
                var drag := InputEventScreenDrag.new()
                drag.index = index
                drag.position = at
                Input.parse_input_event(drag)
        Input.flush_buffered_events()
    canvas.request_composite()
    print(
        (
            "SaCapture: touch, %d finger(s) over %d moment(s), view %s -> %s, layer chunks %d -> %d"
            % [fingers, moments.size(), before, _view_line(view), chunks_before, document.active_layer.chunks.size()]
        )
    )


static func _view_line(view: SaView) -> String:
    var pan := view.get_pan()
    return "pan (%.1f, %.1f) zoom %.3f turn %.1f deg" % [pan.x, pan.y, view.get_zoom(), rad_to_deg(view.get_rotation())]
